import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pos_mobile/data/db/shop_profile_providers.dart';

class CheckoutResultScreen extends ConsumerWidget {
=======

class CheckoutResultScreen extends StatelessWidget {
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
  const CheckoutResultScreen({
    super.key,
    required this.saleId,
    required this.change,
  });

  final String saleId;
  final double change;

  @override
<<<<<<< HEAD
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(shopCurrencyProvider);

=======
  Widget build(BuildContext context) {
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
    return Scaffold(
      appBar: AppBar(title: const Text('Sale Complete')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 84, color: Colors.green),
            const SizedBox(height: 24),
<<<<<<< HEAD
            const Text(
              'Sale recorded locally!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('Sale ID: $saleId', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text(
              'Change due: $currency${change.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
            ),
=======
            const Text('Sale recorded locally!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Sale ID: $saleId', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text('Change due: ${change.toStringAsFixed(2)}',
                textAlign: TextAlign.center),
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('New Sale'),
            ),
          ],
        ),
      ),
    );
  }
}
