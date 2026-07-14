<<<<<<< HEAD
import 'dart:async';
=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import 'package:pos_mobile/data/db/database_provider.dart';
<<<<<<< HEAD
import 'package:pos_mobile/data/db/shop_profile_providers.dart';
import 'package:pos_mobile/features/pos/cart_controller.dart';
import 'package:pos_mobile/features/pos/checkout_result_screen.dart';
import 'package:pos_mobile/features/sync/sync_providers.dart';
=======
import 'package:pos_mobile/features/pos/cart_controller.dart';
import 'package:pos_mobile/features/pos/checkout_result_screen.dart';
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006

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
<<<<<<< HEAD
    final currency = ref.watch(shopCurrencyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Checkout'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SafeArea(
        child: cartItems.isEmpty
            ? _buildEmptyState(theme)
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummaryCard(theme, total, currency),
                    const SizedBox(height: 16),
                    _buildPaymentMethod(theme),
                    if (_paymentMethod == 'cash') ...[
                      const SizedBox(height: 14),
                      _buildCashField(theme, currency),
                    ],
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      _buildErrorBanner(theme),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Items',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildCartList(theme, cartItems, currency)),
                    const SizedBox(height: 12),
                    _buildConfirmButton(theme, items: cartItems, total: total),
                  ],
                ),
=======

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
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
              ),
      ),
    );
  }

<<<<<<< HEAD
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Your cart is empty.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, double total, String currency) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL DUE',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$currency${total.toStringAsFixed(2)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                _paymentMethod == 'cash'
                    ? Icons.payments_outlined
                    : Icons.credit_card,
                size: 16,
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                'Payment method: ${_paymentMethod.capitalize()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethod(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _PaymentOptionChip(
            label: 'Cash',
            icon: Icons.payments_outlined,
            selected: _paymentMethod == 'cash',
            onSelected: () => setState(() => _paymentMethod = 'cash'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PaymentOptionChip(
            label: 'Card',
            icon: Icons.credit_card,
            selected: _paymentMethod == 'card',
            onSelected: () => setState(() => _paymentMethod = 'card'),
          ),
=======
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
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
        ),
      ],
    );
  }

<<<<<<< HEAD
  Widget _buildCashField(ThemeData theme, String currency) {
    return TextField(
      controller: _cashController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: theme.textTheme.titleMedium,
      decoration: InputDecoration(
        labelText: 'Amount tendered',
        prefixText: '$currency ',
        prefixIcon: const Icon(Icons.calculate_outlined),
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
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

  Widget _buildCartList(
      ThemeData theme, List<CartItem> items, String currency) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _CartItemCard(
          theme: theme,
          currency: currency,
          item: item,
          onRemove: () =>
              ref.read(cartProvider.notifier).removeProduct(item.product.id),
          onDecrement: () => ref
              .read(cartProvider.notifier)
              .decrementQuantity(item.product.id),
          onIncrement: () => ref
              .read(cartProvider.notifier)
              .incrementQuantity(item.product.id),
=======
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
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
        );
      },
    );
  }

<<<<<<< HEAD
  Widget _buildConfirmButton(
    ThemeData theme, {
    required List<CartItem> items,
    required double total,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: const Icon(Icons.check_circle_outline),
        onPressed: () => _confirmCheckout(items, total),
        label: const Text('Confirm Checkout'),
      ),
    );
  }

=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
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

<<<<<<< HEAD
    // Push immediately rather than waiting for the next WebSocket
    // reconnect cycle — same reasoning as the inventory screen.
    unawaited(ref.read(syncServiceProvider).flushNow());

=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
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

<<<<<<< HEAD
/// A pill-shaped, icon-labeled payment method selector.
class _PaymentOptionChip extends StatelessWidget {
  const _PaymentOptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single cart row: image slot on the left, name/price that wrap safely,
/// a corner-anchored delete button (ready for a future thumbnail to sit
/// where the image slot is), and a proper stepper for quantity.
class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.theme,
    required this.currency,
    required this.item,
    required this.onRemove,
    required this.onDecrement,
    required this.onIncrement,
  });

  final ThemeData theme;
  final String currency;
  final CartItem item;
  final VoidCallback onRemove;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.product.price * item.quantity;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reserved for a future item thumbnail.
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 28, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$currency${item.product.price.toStringAsFixed(2)} each',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuantityStepper(
                    theme: theme,
                    quantity: item.quantity,
                    onDecrement: onDecrement,
                    onIncrement: onIncrement,
                  ),
                  Text(
                    '$currency${lineTotal.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Remove item',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                onPressed: onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill-shaped [-] qty [+] control for adjusting cart quantity.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.theme,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final ThemeData theme;
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            tooltip: 'Decrease quantity',
            onPressed: onDecrement,
          ),
          SizedBox(
            width: 28,
            child: Text(
              quantity.toString(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            tooltip: 'Increase quantity',
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
