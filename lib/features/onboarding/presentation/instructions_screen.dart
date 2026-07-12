import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // Simple line-art style illustration placeholder — a
              // real illustration asset can replace this in Phase 10.
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 120,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Scan the QR code on your shop\'s POS computer',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'On the shop computer, open the POS app and look for a '
                'pairing QR code on screen. Point your camera at it to '
                'connect this phone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/onboarding/scan'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Scan Now'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
