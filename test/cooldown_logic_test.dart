import 'package:cooldown/models/cooldown.dart';
import 'package:cooldown/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

Cooldown _make({
  required DateTime target,
  required DateTime start,
  int repeatValue = 0,
  RepeatUnit unit = RepeatUnit.days,
  bool waitForDone = true,
}) =>
    Cooldown(
      id: 'x',
      seq: 1,
      name: 'Test',
      emoji: '⏳',
      color: 0xFF4F7CAC,
      target: target,
      start: start,
      repeatValue: repeatValue,
      repeatUnit: unit,
      waitForDone: waitForDone,
      notify: true,
    );

void main() {
  test('months clamp to end of month', () {
    expect(addInterval(DateTime(2026, 1, 31, 9), RepeatUnit.months, 1), DateTime(2026, 2, 28, 9));
    expect(addInterval(DateTime(2028, 1, 31, 9), RepeatUnit.months, 1), DateTime(2028, 2, 29, 9));
    expect(addInterval(DateTime(2026, 11, 15), RepeatUnit.months, 3), DateTime(2027, 2, 15));
  });

  test('auto-repeat rolls over to the next occurrence', () {
    final c = _make(
      target: DateTime(2026, 10, 1, 18),
      start: DateTime(2026, 9, 28, 18),
      repeatValue: 3,
      waitForDone: false,
    );
    final now = DateTime(2026, 10, 8, 12);
    expect(c.currentEnd(now), DateTime(2026, 10, 10, 18));
    expect(c.currentStart(now), DateTime(2026, 10, 7, 18));
    expect(c.upcomingEnds(now, 3), [
      DateTime(2026, 10, 10, 18),
      DateTime(2026, 10, 13, 18),
      DateTime(2026, 10, 16, 18),
    ]);
  });

  test('monthly auto-repeat years later does not skip occurrences', () {
    final c = _make(
      target: DateTime(2020, 1, 15),
      start: DateTime(2019, 12, 15),
      repeatValue: 1,
      unit: RepeatUnit.months,
      waitForDone: false,
    );
    expect(c.currentEnd(DateTime(2030, 6, 20)), DateTime(2030, 7, 15));
  });

  test('wait-for-done stays finished until restarted', () {
    final c = _make(target: DateTime(2026, 10, 1), start: DateTime(2026, 9, 28), repeatValue: 3);
    final now = DateTime(2026, 10, 2, 10);
    expect(c.isFinished(now), isTrue);
    c.restart(now);
    expect(c.currentEnd(now), DateTime(2026, 10, 5, 10));
    expect(c.isFinished(now), isFalse);
  });

  test('day format counts calendar days', () {
    final now = DateTime(2026, 10, 27, 12, 30);
    expect(formatRemaining(now, DateTime(2026, 11, 19), DisplayFormat.days).value, '23');
    expect(formatRemaining(now, DateTime(2026, 10, 28, 1), DisplayFormat.days).label, 'day');
    final today = formatRemaining(now, DateTime(2026, 10, 27, 15, 0), DisplayFormat.days);
    expect(today.value, '2h 30m');
    expect(formatRemaining(now, DateTime(2026, 11, 19), DisplayFormat.weeks).value, '3w 2d');
  });

  test('json round trip', () {
    final c = _make(target: DateTime(2026, 11, 19), start: DateTime(2026, 10, 27), repeatValue: 2);
    final back = Cooldown.decodeList(Cooldown.encodeList([c])).single;
    expect(back.target, c.target);
    expect(back.repeatValue, 2);
    expect(back.display, isNull);
    expect(back.finishText, '');
    expect(back.alert, AlertMode.soundAndVibrate);
    expect(back.widgetOpacity, 1.0);
  });

  test('widget opacity survives json and is clamped', () {
    final c = _make(target: DateTime(2026, 11, 19), start: DateTime(2026, 10, 27))..widgetOpacity = 0.35;
    expect(Cooldown.decodeList(Cooldown.encodeList([c])).single.widgetOpacity, 0.35);
    expect(Cooldown.fromJson(c.toJson()..['widgetOpacity'] = 3).widgetOpacity, 1.0);
    expect(Cooldown.fromJson(c.toJson()..['widgetOpacity'] = 0).widgetOpacity, 0.0);
  });

  test('alert mode survives json and old data keeps sound + vibration', () {
    final c = _make(target: DateTime(2026, 11, 19), start: DateTime(2026, 10, 27))..alert = AlertMode.vibrate;
    expect(Cooldown.decodeList(Cooldown.encodeList([c])).single.alert, AlertMode.vibrate);

    final old = c.toJson()..remove('alert');
    expect(Cooldown.fromJson(old).alert, AlertMode.soundAndVibrate);
    expect(AlertMode.vibrate.playsSound, isFalse);
    expect(AlertMode.sound.vibrates, isFalse);
  });

  test('finish text survives json and defaults to empty for old data', () {
    final c = _make(target: DateTime(2026, 11, 19), start: DateTime(2026, 10, 27))..finishText = 'Water your plants!';
    expect(Cooldown.decodeList(Cooldown.encodeList([c])).single.finishText, 'Water your plants!');

    final old = c.toJson()..remove('finishText');
    expect(Cooldown.fromJson(old).finishText, '');
  });
}
