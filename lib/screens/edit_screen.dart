import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cooldown.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import 'color_picker.dart';

const _palette = <int>[
  0xFF4F7CAC, // blue
  0xFF3A9D5D, // green
  0xFFD9822B, // orange
  0xFFC4466A, // pink
  0xFF8E5CC2, // purple
  0xFF2B9C9C, // teal
  0xFFB8A12A, // mustard
  0xFF6B6B6B, // grey
];

const _emojiSuggestions = ['⏳', '🌱', '💧', '🪴', '🎮', '🎂', '✈️', '💊', '🏋️', '🧹', '🚗', '📦'];

enum _Mode { duration, date }

class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.store, required this.notifications, this.existing});

  final CooldownStore store;
  final NotificationService notifications;
  final Cooldown? existing;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final Cooldown _base;
  late final TextEditingController _name;
  late final TextEditingController _emoji;
  late final TextEditingController _finishText;
  late final TextEditingController _durValue;
  late final TextEditingController _repValue;
  late final DateTime _originalDate;

  late int _color;
  late double _widgetOpacity;

  /// Until the slider is moved here, follow changes made from the widget's
  /// settings (the store reloads when the app comes back to the front).
  bool _opacityTouched = false;
  late _Mode _mode;
  RepeatUnit _durUnit = RepeatUnit.days;
  late DateTime _date;
  late bool _repeat;
  late RepeatUnit _repUnit;
  late bool _waitForDone;
  late bool _notify;
  late AlertMode _alert;
  DisplayFormat? _display;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = widget.existing ?? widget.store.newDraft();
    _name = TextEditingController(text: _base.name);
    _emoji = TextEditingController(text: _base.emoji);
    _finishText = TextEditingController(text: _base.finishText);
    _durValue = TextEditingController(text: '7');
    _repValue = TextEditingController(text: '${_base.repeats ? _base.repeatValue : 1}');
    _color = _base.color;
    _widgetOpacity = _base.widgetOpacity;
    widget.store.addListener(_syncOpacity);
    _mode = _isNew ? _Mode.duration : _Mode.date;
    _date = _base.currentEnd(now);
    _originalDate = _date;
    _repeat = _base.repeats;
    _repUnit = _base.repeatUnit;
    _waitForDone = _base.waitForDone;
    _notify = _base.notify;
    _alert = _base.alert;
    _display = _base.display;
  }

  void _syncOpacity() {
    final latest = widget.store.byId(_base.id);
    if (_opacityTouched || latest == null || latest.widgetOpacity == _widgetOpacity) return;
    setState(() => _widgetOpacity = latest.widgetOpacity);
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncOpacity);
    _name.dispose();
    _emoji.dispose();
    _finishText.dispose();
    _durValue.dispose();
    _repValue.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 50),
    );
    if (d == null) return;
    setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t == null) return;
    setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  void _error(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final now = DateTime.now();
    final name = _name.text.trim();
    if (name.isEmpty) { _error('Give it a name.'); return; }

    late DateTime target;
    late DateTime start;
    var repeatValue = 0;
    var repeatUnit = _repUnit;

    if (_mode == _Mode.duration) {
      final n = int.tryParse(_durValue.text.trim());
      if (n == null || n <= 0) { _error('Enter a duration greater than 0.'); return; }
      target = addInterval(now, _durUnit, n);
      start = now;
      if (_repeat) {
        repeatValue = n;
        repeatUnit = _durUnit;
      }
    } else {
      final dateChanged = _date != _originalDate;
      if ((_isNew || dateChanged) && !_date.isAfter(now)) {
        _error('Pick a date and time in the future.');
        return;
      }
      target = _date;
      start = (_isNew || dateChanged) ? now : _base.currentStart(now);
      if (_repeat) {
        final n = int.tryParse(_repValue.text.trim());
        if (n == null || n <= 0) { _error('Enter how often it repeats.'); return; }
        repeatValue = n;
      }
    }

    if (_notify) await widget.notifications.requestPermission();

    final saved = Cooldown(
      id: _base.id,
      seq: _base.seq,
      name: name,
      emoji: _emoji.text.trim().isEmpty ? '⏳' : _emoji.text.trim(),
      color: _color,
      target: target,
      start: start,
      repeatValue: repeatValue,
      repeatUnit: repeatUnit,
      waitForDone: _waitForDone,
      notify: _notify,
      display: _display,
      finishText: _finishText.text.trim(),
      alert: _alert,
      widgetOpacity: _widgetOpacity,
    );
    await widget.store.upsert(saved);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultLabel = widget.store.defaultDisplay.label;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New cooldown' : 'Edit cooldown'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _emoji,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                  decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Water the plants',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (final e in _emojiSuggestions)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _emoji.text = e),
                  child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 22))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final col in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = col),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(col),
                    child: _color == col ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                  ),
                ),
              CustomColorButton(
                selected: _palette.contains(_color) ? null : Color(_color),
                onTap: () async {
                  final picked = await showCustomColorPicker(context, _color);
                  if (picked != null) setState(() => _color = picked);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WidgetPreview(color: Color(_color), opacity: _widgetOpacity, emoji: _emoji.text),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Widget background: ${(_widgetOpacity * 100).round()}%', style: theme.textTheme.bodyMedium),
                    Slider(
                      value: _widgetOpacity,
                      divisions: 20,
                      label: '${(_widgetOpacity * 100).round()}%',
                      onChanged: (v) => setState(() {
                        _widgetOpacity = v;
                        _opacityTouched = true;
                      }),
                    ),
                    if (Platform.isAndroid)
                      Text(
                        'Same setting as in the widget’s own settings '
                        '(long-press the widget on the home screen).',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.duration, label: Text('Duration'), icon: Icon(Icons.timelapse)),
              ButtonSegment(value: _Mode.date, label: Text('Date & time'), icon: Icon(Icons.event)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == _Mode.duration)
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _durValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ends in', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _unitDropdown(_durUnit, (u) => setState(() => _durUnit = u))),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(DateFormat('HH:mm').format(_date)),
                ),
              ],
            ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat'),
            subtitle: Text(_mode == _Mode.duration
                ? 'Starts again with the same duration'
                : 'Repeats on a fixed interval'),
            value: _repeat,
            onChanged: (v) => setState(() => _repeat = v),
          ),
          if (_repeat && _mode == _Mode.date)
            Row(
              children: [
                const Text('Every'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _repValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _unitDropdown(_repUnit, (u) => setState(() => _repUnit = u))),
              ],
            ),
          if (_repeat)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wait until I tap “Done”'),
              subtitle: Text(_waitForDone
                  ? 'Next round starts when you mark it done (e.g. after watering)'
                  : 'Next round starts automatically when this one ends'),
              value: _waitForDone,
              onChanged: (v) => setState(() => _waitForDone = v),
            ),
          const Divider(height: 32),
          TextField(
            controller: _finishText,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Message when it ends (optional)',
              hintText: 'Water your plants!',
              helperText: 'Shown in the reminder, on the card and on the widget',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AlertMode?>(
                  initialValue: _notify ? _alert : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reminder when it ends', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Off')),
                    for (final m in AlertMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setState(() {
                    _notify = m != null;
                    if (m != null) _alert = m;
                  }),
                ),
              ),
              IconButton(
                tooltip: 'Try it',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: _notify
                    ? () async {
                        await widget.notifications.requestPermission();
                        await widget.notifications.preview(_alert);
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DisplayFormat?>(
            initialValue: _display,
            decoration: const InputDecoration(labelText: 'Show remaining time as', border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: null, child: Text('Default ($defaultLabel)')),
              for (final f in DisplayFormat.values) DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _display = v),
          ),
          const SizedBox(height: 24),
          Text(
            'Widgets are optional: after saving, use “Add to home screen” from the card menu, '
            'or add a Cooldown widget from your home screen and pick this cooldown.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _unitDropdown(RepeatUnit value, ValueChanged<RepeatUnit> onChanged) {
    return DropdownButtonFormField<RepeatUnit>(
      initialValue: value,
      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
      items: [for (final u in RepeatUnit.values) DropdownMenuItem(value: u, child: Text(u.plural))],
      onChanged: (u) {
        if (u != null) onChanged(u);
      },
    );
  }
}

/// The widget's background over a sample "wallpaper", to show the chosen transparency.
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({required this.color, required this.opacity, required this.emoji});

  final Color color;
  final double opacity;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A9A5B), Color(0xFF35506B)],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(borderRadius: radius, color: color.withValues(alpha: opacity)),
        alignment: Alignment.center,
        child: Text(emoji.trim().isEmpty ? '⏳' : emoji.trim(), style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
