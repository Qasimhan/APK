import 'package:flutter/material.dart';

/// A simple numeric keypad that reports the current entered PIN via
/// [onChanged] and fires [onSubmit] once [pinLength] digits are in.
class PinPad extends StatefulWidget {
  final int pinLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onSubmit;
  final bool enabled;

  const PinPad({
    super.key,
    this.pinLength = 4,
    this.onChanged,
    required this.onSubmit,
    this.enabled = true,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _append(String digit) {
    if (!widget.enabled || _pin.length >= widget.pinLength) return;
    setState(() => _pin += digit);
    widget.onChanged?.call(_pin);
    if (_pin.length == widget.pinLength) {
      widget.onSubmit(_pin);
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
    widget.onChanged?.call(_pin);
  }

  void clear() {
    setState(() => _pin = '');
    widget.onChanged?.call(_pin);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.pinLength, (i) {
            final filled = i < _pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        _buildRow(['1', '2', '3']),
        _buildRow(['4', '5', '6']),
        _buildRow(['7', '8', '9']),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 72, height: 72),
            _digitButton('0'),
            SizedBox(
              width: 72,
              height: 72,
              child: IconButton(
                onPressed: widget.enabled ? _backspace : null,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: digits.map(_digitButton).toList(),
    );
  }

  Widget _digitButton(String digit) {
    return SizedBox(
      width: 72,
      height: 72,
      child: TextButton(
        onPressed: widget.enabled ? () => _append(digit) : null,
        child: Text(digit, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
