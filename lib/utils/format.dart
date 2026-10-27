import '../models/cooldown.dart';

/// Big value + small label, e.g. ("23", "days") or ("3d 4h 12m", "left").
/// The native widgets implement the exact same rules (CooldownFormat.kt /
/// CooldownWidget.swift) — keep them in sync.
class Remaining {
  const Remaining(this.value, this.label);
  final String value;
  final String label;
}

int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _hm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '<1m';
}

String _dhm(Duration d) {
  final days = d.inDays;
  final h = d.inHours % 24;
  final m = d.inMinutes % 60;
  if (days > 0) return '${days}d ${h}h ${m}m';
  return _hm(d);
}

Remaining formatRemaining(DateTime now, DateTime end, DisplayFormat format) {
  final left = end.difference(now);
  if (left <= Duration.zero) return const Remaining('0', 'ready');
  final calDays = calendarDaysBetween(now, end);

  Remaining days() {
    if (calDays >= 1) return Remaining('$calDays', calDays == 1 ? 'day' : 'days');
    return Remaining(_hm(left), 'left today');
  }

  switch (format) {
    case DisplayFormat.days:
      return days();
    case DisplayFormat.weeks:
      if (calDays >= 7) {
        final w = calDays ~/ 7;
        final d = calDays % 7;
        return Remaining(d == 0 ? '${w}w' : '${w}w ${d}d', 'left');
      }
      return days();
    case DisplayFormat.hours:
      if (left.inHours >= 1) {
        return Remaining('${left.inHours}', left.inHours == 1 ? 'hour' : 'hours');
      }
      return Remaining(left.inMinutes > 0 ? '${left.inMinutes}' : '<1', 'min');
    case DisplayFormat.detailed:
      return Remaining(_dhm(left), 'left');
    case DisplayFormat.auto:
      if (calDays >= 2) return days();
      return Remaining(_dhm(left), 'left');
  }
}

String describeRepeat(Cooldown c) {
  if (!c.repeats) return 'One-time';
  final every = c.repeatValue == 1
      ? 'Every ${c.repeatUnit.singular}'
      : 'Every ${c.repeatValue} ${c.repeatUnit.plural}';
  return c.waitForDone ? '$every · after done' : every;
}
