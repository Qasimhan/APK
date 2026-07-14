import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_client.dart';
import '../../../core/scan/scan_feedback_provider.dart';
import '../application/pairing_controller.dart';
import '../data/onboarding_repository.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handledOneCode = false;
  bool _pairingAttemptStarted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handledOneCode) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    PairingQrPayload payload;
    try {
      payload = PairingQrPayload.fromRaw(raw);
    } catch (_) {
      // Not a pairing QR (or malformed) — keep scanning silently rather
      // than interrupting with an error for every stray code in frame.
      return;
    }

    ref.read(scanFeedbackProvider.future).then(playScanFeedback);

    _pairingAttemptStarted = true;
    setState(() => _handledOneCode = true);
    ref.read(pairingControllerProvider.notifier).pairFromQr(payload);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pairingControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          if (_pairingAttemptStarted && previous?.isLoading == true) {
            _pairingAttemptStarted = false;
            context.go('/onboarding/login');
          }
        },
        error: (error, _) {
          final message = error is PosApiException
              ? error.message
              : 'Pairing failed. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          _pairingAttemptStarted = false;
          setState(() => _handledOneCode = false);
        },
      );
    });

    final pairingState = ref.watch(pairingControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pairing QR')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Simple viewfinder frame overlay.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (pairingState.isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Setting up your shop...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
