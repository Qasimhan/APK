import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_mobile/core/scan/scan_feedback_provider.dart';
import 'package:pos_mobile/data/db/db.dart';
import 'package:pos_mobile/data/db/database_provider.dart';
import 'package:pos_mobile/data/db/shop_profile_providers.dart';
import 'package:pos_mobile/features/sync/sync_providers.dart';
import 'package:pos_mobile/features/pos/cart_controller.dart';
import 'package:pos_mobile/features/pos/checkout_screen.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _lastBarcode;
  DateTime? _lastScanAt;
  Product? _scannedProduct;
  String? _lookupMessage;
  final _manualBarcodeController = TextEditingController();
  StreamSubscription<String>? _remoteScanSub;
  bool _remoteScanActive = false;
  String? _remoteScanSessionId;

  @override
  void dispose() {
    _remoteScanSub?.cancel();
    _controller.dispose();
    _manualBarcodeController.dispose();
    super.dispose();
  }

  void _handleBarcode(String barcode) async {
    final now = DateTime.now();
    if (_lastBarcode == barcode &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!).inMilliseconds < 1500) {
      return;
    }

    _lastBarcode = barcode;
    _lastScanAt = now;

    try {
      final feedback = await ref.read(scanFeedbackProvider.future);
      await playScanFeedback(feedback);
    } catch (_) {
      // ignore
    }

    final db = ref.read(databaseProvider);
    final product = await db.productDao.getProductByBarcode(barcode);

    if (!mounted) return;

    setState(() {
      _scannedProduct = product;
      _lookupMessage = product == null ? 'Product not found' : null;
    });

    if (product != null) {
      ref.read(cartProvider.notifier).addProduct(product);
      if (_remoteScanActive && _remoteScanSessionId != null) {
        // If remote scan is active, send the result back and exit remote mode
        try {
          ref
              .read(syncServiceProvider)
              .sendScanResult(_remoteScanSessionId!, barcode);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sent scan result to desktop')));
        } catch (_) {}
        setState(() {
          _remoteScanActive = false;
          _remoteScanSessionId = null;
        });
        return;
      }
    }
  }

  void _submitManualBarcode() {
    final barcode = _manualBarcodeController.text.trim();
    if (barcode.isEmpty) return;
    _handleBarcode(barcode);
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final cartCount = ref.watch(cartItemCountProvider);
    final currency = ref.watch(shopCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
        actions: [
          Consumer(builder: (context, ref, _) {
            final pendingAsync = ref.watch(pendingActionsCountProvider);
            return IconButton(
              icon: Stack(
                alignment: Alignment.topRight,
                children: [
                  const Icon(Icons.shopping_cart_outlined),
                  CircleAvatar(
                    radius: 8,
                    backgroundColor: cartCount > 0 ? Colors.red : Colors.grey,
                    child: Text(
                      cartCount.toString(),
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  // Pending sync badge (small orange dot with count)
                  pendingAsync.when(
                    data: (pending) => pending > 0
                        ? Positioned(
                            right: 0,
                            child: CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.orange,
                              child: Text(pending.toString(),
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white)),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              onPressed: () {
                if (cartItems.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cart is empty')),
                  );
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CheckoutScreen(),
                ));
              },
            );
          })
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull?.rawValue;
                if (barcode != null) {
                  _handleBarcode(barcode);
                } else {
                  setState(() {
                    _lookupMessage = 'Unsupported barcode format';
                  });
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _manualBarcodeController,
                  decoration: InputDecoration(
                    labelText: 'Enter barcode manually',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _submitManualBarcode,
                    ),
                  ),
                  onSubmitted: (_) => _submitManualBarcode(),
                ),
                const SizedBox(height: 12),
                if (_lookupMessage != null)
                  Text(_lookupMessage!,
                      style: const TextStyle(color: Colors.red)),
                if (_scannedProduct != null) ...[
                  const SizedBox(height: 12),
                  _buildProductCard(_scannedProduct!, currency),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, String currency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildImage(product.imagePath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(product.description ?? 'No description'),
                  const SizedBox(height: 8),
                  Text('Price: $currency${product.price.toStringAsFixed(2)}'),
                  Text('Stock: ${product.stockQty}'),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(cartProvider.notifier).addProduct(product);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${product.name} added to cart')),
                );
              },
              child: const Text('Add to Cart'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String? imagePath) {
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(file, width: 80, height: 80, fit: BoxFit.cover);
      }
    }
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image, size: 40, color: Colors.grey),
    );
  }

  @override
  void initState() {
    super.initState();
    // Listen for remote scan requests from the SyncService
    _remoteScanSub =
        ref.read(syncServiceProvider).scanRequestStream.listen((sessionId) {
      if (!mounted) return;
      setState(() {
        _remoteScanActive = true;
        _remoteScanSessionId = sessionId;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Remote scan requested — waiting for a barcode')));
    });
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
