import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/colors.dart';

const _rainbow = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

/// Lets the user pick any colour (hue / saturation / brightness or a hex code).
/// Returns the ARGB value, or null if cancelled.
Future<int?> showCustomColorPicker(BuildContext context, int initial) =>
    showDialog<int>(context: context, builder: (_) => _ColorPickerDialog(initial: initial));

/// The rainbow circle that opens the picker. Shows [selected] (with a tick)
/// inside a rainbow ring when a custom colour is in use, otherwise a "+".
class CustomColorButton extends StatelessWidget {
  const CustomColorButton({super.key, required this.onTap, this.selected});

  final VoidCallback onTap;
  final Color? selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Custom colour',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: _rainbow)),
          child: selected == null
              ? const Icon(Icons.add, size: 20, color: Colors.white, shadows: [Shadow(blurRadius: 3)])
              : DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: selected),
                  child: Icon(Icons.check, size: 16, color: foregroundOn(selected!)),
                ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final int initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.initial));
    _hex = TextEditingController(text: _hexOf(_color));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hexOf(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(HSVColor hsv) => setState(() {
        _hsv = hsv;
        _hex.text = _hexOf(_color);
      });

  void _onHex(String text) {
    if (text.length != 6) return;
    final v = int.tryParse(text, radix: 16);
    if (v != null) setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | v)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(16)),
              child: Text('Aa', style: TextStyle(color: foregroundOn(_color), fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            _GradientSlider(
              label: 'Hue',
              colors: _rainbow,
              value: _hsv.hue / 360,
              onChanged: (v) => _set(_hsv.withHue(v * 360)),
            ),
            _GradientSlider(
              label: 'Saturation',
              colors: [HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(), HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor()],
              value: _hsv.saturation,
              onChanged: (v) => _set(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              colors: [Colors.black, HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor()],
              value: _hsv.value,
              onChanged: (v) => _set(_hsv.withValue(v)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hex,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
              decoration: const InputDecoration(
                labelText: 'Hex',
                prefixText: '#',
                counterText: '',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onHex,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color.toARGB32()), child: const Text('Use colour')),
      ],
    );
  }
}

/// A slider drawn on top of a gradient bar that shows what each position means.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({required this.label, required this.colors, required this.value, required this.onChanged});

  final String label;
  final List<Color> colors;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 12,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.black12,
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
