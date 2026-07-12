import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import 'package:pos_mobile/data/db/database_provider.dart';
import 'package:pos_mobile/features/pos/cart_controller.dart';
import 'package:pos_mobile/features/pos/checkout_result_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _paymentMethod = 'cash';
  final _cashController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: cartItems.isEmpty
            ? const Center(child: Text('Your cart is empty.'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummary(total),
                  const SizedBox(height: 16),
                  _buildPaymentMethod(),
                  if (_paymentMethod == 'cash') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cashController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount tendered',
                        prefixText: '',
                      ),
                    ),
                  ],
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorText!,
                        style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  Expanded(child: _buildCartList(cartItems)),
                  ElevatedButton(
                    onPressed: () => _confirmCheckout(cartItems, total),
                    child: const Text('Confirm Checkout'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary(double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total: ${total.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Payment method: ${_paymentMethod.capitalize()}'),
      ],
    );
  }

  Widget _buildPaymentMethod() {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Cash'),
          selected: _paymentMethod == 'cash',
          onSelected: (_) => setState(() => _paymentMethod = 'cash'),
        ),
        const SizedBox(width: 10),
        ChoiceChip(
          label: const Text('Card'),
          selected: _paymentMethod == 'card',
          onSelected: (_) => setState(() => _paymentMethod = 'card'),
        ),
      ],
    );
  }

  Widget _buildCartList(List<CartItem> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(item.product.name),
          subtitle: Text(
              'Qty ${item.quantity} • ${item.product.price.toStringAsFixed(2)} each'),
          trailing: Text(
              '${(item.product.price * item.quantity).toStringAsFixed(2)}'),
        );
      },
    );
  }

  Future<void> _confirmCheckout(List<CartItem> items, double total) async {
    setState(() => _errorText = null);
    if (items.isEmpty) return;

    if (_paymentMethod == 'cash') {
      final tendered = double.tryParse(_cashController.text);
      if (tendered == null || tendered < total) {
        setState(
            () => _errorText = 'Enter an amount at least equal to the total.');
        return;
      }
    }

    final db = ref.read(databaseProvider);
    final session = await db.sessionDao.getCurrentSession();
    if (session == null) {
      setState(() => _errorText = 'No active staff session.');
      return;
    }

    final saleItemsPayload = items
        .map((item) => {
              'product_id': item.product.id,
              'qty': item.quantity,
              'price_at_sale': item.product.price,
            })
        .toList();

    final saleId = await db.salesDao.createLocalSale(
      total: total,
      paymentMethod: _paymentMethod,
      staffId: session.staffId,
      items: items
          .map((item) => (
                productId: item.product.id,
                qty: item.quantity,
                priceAtSale: item.product.price,
              ))
          .toList(),
    );

    // Enqueue the sale to the sync queue so Phase 8/9 can push it to the
    // desktop backend when connectivity is available.
    try {
      await db.syncQueueDao.enqueue(
        actionType: 'sale',
        payloadJson: jsonEncode({
          'sale_id': saleId,
          'total': total,
          'payment_method': _paymentMethod,
          'staff_id': session.staffId,
          'items': saleItemsPayload,
        }),
      );
    } catch (_) {
      // Swallow enqueue errors; sale is still recorded locally.
    }

    ref.read(cartProvider.notifier).clear();
    if (!mounted) return;

    if (_paymentMethod == 'cash') {
      final tendered = double.parse(_cashController.text);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CheckoutResultScreen(
            saleId: saleId,
            change: tendered - total,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CheckoutResultScreen(
            saleId: saleId,
            change: 0,
          ),
        ),
      );
    }
  }
}

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
