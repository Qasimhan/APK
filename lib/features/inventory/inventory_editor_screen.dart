import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_mobile/data/db/database_provider.dart';
import 'package:pos_mobile/data/db/db.dart';

class InventoryEditorScreen extends ConsumerStatefulWidget {
  const InventoryEditorScreen({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<InventoryEditorScreen> createState() =>
      _InventoryEditorScreenState();
}

class _InventoryEditorScreenState extends ConsumerState<InventoryEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  String? _errorText;

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
    _stockController =
        TextEditingController(text: widget.product?.stockQty.toString() ?? '0');
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final barcode = _barcodeController.text.trim();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final stockQty = int.tryParse(_stockController.text.trim());

    if (price == null || price < 0) {
      setState(() => _errorText = 'Enter a valid price.');
      return;
    }
    if (stockQty == null || stockQty < 0) {
      setState(() => _errorText = 'Enter a valid stock quantity.');
      return;
    }

    final db = ref.read(databaseProvider);
    final existing = await db.productDao.getProductByBarcode(barcode);
    if (existing != null && existing.id != widget.product?.id) {
      setState(
          () => _errorText = 'A product with this barcode already exists.');
      return;
    }

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

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteProduct() async {
    if (widget.product == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product'),
        content: const Text('Remove this product from local inventory?'),
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'Add Product'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteProduct,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorText != null) ...[
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _barcodeController,
                    decoration: const InputDecoration(labelText: 'Barcode'),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Barcode is required.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) => value?.trim().isEmpty == true
                        ? 'Product name is required.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                        labelText: 'Price', prefixText: '៛'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stockController,
                    decoration:
                        const InputDecoration(labelText: 'Stock quantity'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveProduct,
                    child: Text(isEditing ? 'Save Changes' : 'Create Product'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Changes are stored locally in the mobile cache. Synchronization with the desktop backend will be added in a later phase.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
