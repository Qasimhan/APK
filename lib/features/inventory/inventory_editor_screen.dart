import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pos_mobile/data/db/database_provider.dart';
import 'package:pos_mobile/data/db/db.dart';
import 'package:pos_mobile/features/sync/sync_providers.dart';

class InventoryEditorScreen extends ConsumerStatefulWidget {
  const InventoryEditorScreen({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<InventoryEditorScreen> createState() =>
      _InventoryEditorScreenState();
}

class _InventoryEditorScreenState extends ConsumerState<InventoryEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _customCategoryValue = '__custom__';
  static const List<String> _categoryOptions = [
    'General',
    'Food',
    'Beverages',
    'Snacks',
    'Household',
    _customCategoryValue,
  ];

  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  // NEW: matches the desktop dialog's "Cost" field. The local Product
  // model/table has no cost column (see data/db/tables.dart), so this
  // value is not persisted locally — same limitation as before, where
  // the sync payload always hardcoded 'cost': 0. Now it's just wired
  // to an actual input instead of a hardcoded literal.
  late final TextEditingController _costController;
  late final TextEditingController _stockController;
  late final TextEditingController _customCategoryController;
  late final TextEditingController _imagePathController;
  String _selectedCategory = 'General';
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _barcodeController =
        TextEditingController(text: widget.product?.barcode ?? '');
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.product?.description ?? '');
    _priceController = TextEditingController(
        text: widget.product?.price.toStringAsFixed(2) ?? '0.00');
    _costController = TextEditingController(text: '0');
    _stockController =
        TextEditingController(text: widget.product?.stockQty.toString() ?? '0');
    _customCategoryController = TextEditingController(text: '');
    _imagePathController =
        TextEditingController(text: widget.product?.imagePath ?? '');
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    _customCategoryController.dispose();
    _imagePathController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final barcode = _barcodeController.text.trim();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final cost = double.tryParse(_costController.text.trim()) ?? 0;
    final stockQty = int.tryParse(_stockController.text.trim());
    final customCategoryName = _customCategoryController.text.trim();
    final imagePath = _imagePathController.text.trim();

    if (price == null || price < 0) {
      setState(() => _errorText = 'Enter a valid price.');
      return;
    }
    if (stockQty == null || stockQty < 0) {
      setState(() => _errorText = 'Enter a valid stock quantity.');
      return;
    }
    if (_selectedCategory == _customCategoryValue &&
        customCategoryName.isEmpty) {
      setState(
          () => _errorText = 'Enter a category name for the custom option.');
      return;
    }

    final categoryName = _selectedCategory == _customCategoryValue
        ? customCategoryName
        : _selectedCategory;

    final db = ref.read(databaseProvider);
    final existing = await db.productDao.getProductByBarcode(barcode);
    if (existing != null && existing.id != widget.product?.id) {
      setState(
          () => _errorText = 'A product with this barcode already exists.');
      return;
    }

    setState(() => _saving = true);

    final isEditing = widget.product != null;
    // Local-only placeholder id for brand-new products, until the
    // desktop assigns a real one and the sync flush below replaces it.
    final id = widget.product?.id ?? -DateTime.now().millisecondsSinceEpoch;

    await db.productDao.upsertProduct(
      ProductsCompanion(
        id: drift.Value(id),
        barcode: drift.Value(barcode),
        name: drift.Value(name),
        description: drift.Value(description.isEmpty ? null : description),
        price: drift.Value(price),
        stockQty: drift.Value(stockQty),
        lastSyncedAt: drift.Value(DateTime.now()),
      ),
    );

    // Enqueue the create/update so SyncService pushes it to the
    // desktop as soon as the WebSocket is connected — previously
    // nothing enqueued this at all, so products added on the phone
    // never left the local cache. Body uses the server's camelCase
    // shape (see MOBILE_API_REFERENCE.md POST/PUT /products).
    final payload = <String, dynamic>{
      if (isEditing) 'id': widget.product!.id,
      'name': name,
      'barcode': barcode,
      'price': price,
      'cost': cost,
      'categoryId': null,
      'categoryName': categoryName,
      'stockQty': stockQty,
      'description': description.isEmpty ? null : description,
      'imagePath': imagePath.isEmpty ? null : imagePath,
    };

    try {
      await db.syncQueueDao.enqueue(
        actionType: isEditing ? 'product_update' : 'product_create',
        payloadJson: jsonEncode(payload),
      );
    } catch (_) {
      // Swallow enqueue errors; product is still saved locally and
      // will simply need a manual "Refresh sync" retry later.
    }

    // Trigger an immediate push attempt instead of waiting for the
    // next WebSocket reconnect cycle, so "add product" reaches the
    // desktop right away when connectivity is already up.
    unawaited(ref.read(syncServiceProvider).flushNow());

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _deleteProduct() async {
    if (widget.product == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product'),
        content: const Text(
          'Remove this product from local inventory?\n\n'
          'Note: the desktop server currently has no delete/deactivate '
          'endpoint for products, so this only removes it from this '
          'phone\'s cache — it will reappear after the next sync unless '
          'it\'s also removed on the desktop.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref
        .read(databaseProvider)
        .productDao
        .deleteProduct(widget.product!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // Real image picker: lets staff choose from the gallery or snap a
  // photo with the camera. Requires the `image_picker` dependency —
  // see the pubspec.yaml note that ships alongside this file.
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            if (_imagePathController.text.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Remove image',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  // Handled directly rather than via the sheet's return
                  // value, so it can't be confused with "sheet dismissed
                  // without a choice" (both would otherwise pop as null).
                  setState(() => _imagePathController.text = '');
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) {
      // Sheet dismissed (tapped outside) or "Remove image" already
      // handled its own state change above — nothing more to do.
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _imagePathController.text = picked.path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Could not open $source: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.product != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'New Product'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isEditing)
            IconButton(
              tooltip: 'Delete product',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteProduct,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorText != null) ...[
                    _buildErrorBanner(theme),
                    const SizedBox(height: 14),
                  ],

                  // --- Image picker row, like the desktop dialog ---
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _imagePathController.text.isNotEmpty &&
                                File(_imagePathController.text).existsSync()
                            ? Image.file(
                                File(_imagePathController.text),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.image_outlined,
                                  size: 28,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              )
                            : Icon(
                                Icons.image_outlined,
                                size: 28,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.upload_outlined, size: 18),
                              label: Text(
                                _imagePathController.text.isEmpty
                                    ? 'Choose image'
                                    : 'Change image',
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _fieldLabel(theme, 'Name'),
                  TextFormField(
                    controller: _nameController,
                    decoration: _fieldDecoration(theme),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Product name is required.'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  _fieldLabel(theme, 'Barcode'),
                  TextFormField(
                    controller: _barcodeController,
                    decoration: _fieldDecoration(theme),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Barcode is required.'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // --- Price / Cost side by side, like the desktop dialog ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(theme, 'Price'),
                            TextFormField(
                              controller: _priceController,
                              decoration:
                                  _fieldDecoration(theme, prefixText: '৳'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(theme, 'Cost'),
                            TextFormField(
                              controller: _costController,
                              decoration: _fieldDecoration(theme),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // --- Category / Stock qty side by side ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(theme, 'Category'),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              decoration: _fieldDecoration(theme),
                              items: _categoryOptions
                                  .map(
                                    (value) => DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(
                                        value == _customCategoryValue
                                            ? 'Custom...'
                                            : value,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedCategory = value;
                                  _errorText = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(theme, 'Stock qty'),
                            TextFormField(
                              controller: _stockController,
                              decoration: _fieldDecoration(theme),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_selectedCategory == _customCategoryValue) ...[
                    const SizedBox(height: 16),
                    _fieldLabel(theme, 'Custom category name'),
                    TextFormField(
                      controller: _customCategoryController,
                      decoration: _fieldDecoration(theme),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _fieldLabel(theme, 'Description'),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: _fieldDecoration(
                      theme,
                      hintText: 'Optional details shown to staff at lookup...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  // --- Cancel / Save footer, like the desktop dialog ---
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveProduct,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Saved locally and pushed to the shop computer as soon '
                    'as it\'s reachable.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    ThemeData theme, {
    String? prefixText,
    String? hintText,
  }) {
    return InputDecoration(
      prefixText: prefixText,
      hintText: hintText,
      filled: true,
      fillColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
