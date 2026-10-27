import 'dart:convert';

/// How the remaining time is shown. Mirrored 1:1 in the Android (Kotlin) and
/// iOS (Swift) widget code — keep the string values in sync.
enum DisplayFormat {
  days('days', 'Days'),
  weeks('weeks', 'Weeks + days'),
  hours('hours', 'Hours'),
  detailed('detailed', 'Days, hours, minutes'),
  auto('auto', 'Automatic');

  const DisplayFormat(this.key, this.label);
  final String key;
  final String label;

  static DisplayFormat fromKey(String? key) =>
      DisplayFormat.values.firstWhere((f) => f.key == key, orElse: () => DisplayFormat.days);
}

enum RepeatUnit {
  hours('hours', 'hour', 'hours'),
  days('days', 'day', 'days'),
  weeks('weeks', 'week', 'weeks'),
  months('months', 'month', 'months'),
  years('years', 'year', 'years');

  const RepeatUnit(this.key, this.singular, this.plural);
  final String key;
  final String singular;
  final String plural;

  String label(int n) => n == 1 ? singular : plural;

  static RepeatUnit fromKey(String? key) =>
      RepeatUnit.values.firstWhere((u) => u.key == key, orElse: () => RepeatUnit.days);
}

/// How the end-of-cooldown reminder gets your attention.
enum AlertMode {
  silent('silent', 'Silent'),
  vibrate('vibrate', 'Vibrate'),
  sound('sound', 'Sound'),
  soundAndVibrate('soundVibrate', 'Sound + vibration');

  const AlertMode(this.key, this.label);
  final String key;
  final String label;

  bool get playsSound => this == sound || this == soundAndVibrate;
  bool get vibrates => this == vibrate || this == soundAndVibrate;

  static AlertMode fromKey(String? key) =>
      AlertMode.values.firstWhere((m) => m.key == key, orElse: () => AlertMode.soundAndVibrate);
}

class Cooldown {
  Cooldown({
    required this.id,
    required this.seq,
    required this.name,
    required this.emoji,
    required this.color,
    required this.target,
    required this.start,
    required this.repeatValue,
    required this.repeatUnit,
    required this.waitForDone,
    required this.notify,
    this.display,
    this.finishText = '',
    this.alert = AlertMode.soundAndVibrate,
    this.widgetOpacity = 1.0,
  });

  final String id;

  /// Small stable integer used to derive notification IDs.
  final int seq;
  String name;
  String emoji;
  int color;

  /// For one-off cooldowns: the end. For auto-repeating ones: the anchor of the
  /// schedule (every occurrence is anchor + k * interval).
  DateTime target;

  /// When the current cycle started (used for the progress bar).
  DateTime start;

  /// 0 = does not repeat.
  int repeatValue;
  RepeatUnit repeatUnit;

  /// Repeating only: if true the cooldown stays "ready" after it ends until you
  /// tap "Done", then restarts from that moment (good for watering plants).
  /// If false it rolls over to the next occurrence automatically.
  bool waitForDone;
  bool notify;

  /// Only used when [notify] is on.
  AlertMode alert;

  /// Opacity of the widget background in its colour: 0 = fully transparent, 1 = solid.
  double widgetOpacity;

  /// null = use the app-wide default.
  DisplayFormat? display;

  /// Optional message shown when it ends ("Water your plants!"). Empty = none.
  String finishText;

  bool get repeats => repeatValue > 0;
  bool get autoRepeats => repeats && !waitForDone;

  // ---------------------------------------------------------------------------
  // Schedule logic (mirrored in Kotlin + Swift)
  // ---------------------------------------------------------------------------

  /// The end of the current cycle, taking auto-repeat into account.
  DateTime currentEnd(DateTime now) {
    if (!autoRepeats || target.isAfter(now)) return target;
    return _occurrenceAfter(now).$1;
  }

  /// Start of the current cycle.
  DateTime currentStart(DateTime now) {
    if (!autoRepeats || target.isAfter(now)) return start;
    return _occurrenceAfter(now).$2;
  }

  bool isFinished(DateTime now) => !currentEnd(now).isAfter(now);

  /// The next [count] end times from [now] on (for scheduling notifications).
  List<DateTime> upcomingEnds(DateTime now, int count) {
    if (!autoRepeats) return target.isAfter(now) ? [target] : [];
    final k0 = _occurrenceAfter(now).$3;
    return [for (var i = 0; i < count; i++) addInterval(target, repeatUnit, repeatValue * (k0 + i))];
  }

  int _estimateK(DateTime t) {
    final approx = _approxIntervalMs();
    final diff = t.millisecondsSinceEpoch - target.millisecondsSinceEpoch;
    final k = diff ~/ approx - 2;
    return k < 0 ? 0 : k;
  }

  /// Deliberately on the long side so the estimate of k never overshoots.
  int _approxIntervalMs() {
    const h = 3600000;
    switch (repeatUnit) {
      case RepeatUnit.hours:
        return repeatValue * h;
      case RepeatUnit.days:
        return repeatValue * 24 * h;
      case RepeatUnit.weeks:
        return repeatValue * 7 * 24 * h;
      case RepeatUnit.months:
        return repeatValue * 31 * 24 * h;
      case RepeatUnit.years:
        return repeatValue * 366 * 24 * h;
    }
  }

  /// Returns (end, start, index) of the first occurrence strictly after [now].
  (DateTime, DateTime, int) _occurrenceAfter(DateTime now) {
    var k = _estimateK(now);
    var end = addInterval(target, repeatUnit, repeatValue * k);
    while (!end.isAfter(now)) {
      k++;
      end = addInterval(target, repeatUnit, repeatValue * k);
    }
    final begin = k == 0 ? start : addInterval(target, repeatUnit, repeatValue * (k - 1));
    return (end, begin, k);
  }

  /// Restart the cycle from [now] (used by "Done" / "Restart").
  void restart(DateTime now) {
    if (!repeats) return;
    start = now;
    target = addInterval(now, repeatUnit, repeatValue);
  }

  // ---------------------------------------------------------------------------
  // Serialisation — this exact JSON is also read by the native widgets.
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'seq': seq,
        'name': name,
        'emoji': emoji,
        'color': color,
        'targetMs': target.millisecondsSinceEpoch,
        'startMs': start.millisecondsSinceEpoch,
        'repeatValue': repeatValue,
        'repeatUnit': repeatUnit.key,
        'waitForDone': waitForDone,
        'notify': notify,
        'display': display?.key ?? 'default',
        'finishText': finishText,
        'alert': alert.key,
        'widgetOpacity': widgetOpacity,
      };

  factory Cooldown.fromJson(Map<String, dynamic> j) => Cooldown(
        id: j['id'] as String,
        seq: (j['seq'] as num).toInt(),
        name: j['name'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '⏳',
        color: (j['color'] as num?)?.toInt() ?? 0xFF4F7CAC,
        target: DateTime.fromMillisecondsSinceEpoch((j['targetMs'] as num).toInt()),
        start: DateTime.fromMillisecondsSinceEpoch((j['startMs'] as num).toInt()),
        repeatValue: (j['repeatValue'] as num?)?.toInt() ?? 0,
        repeatUnit: RepeatUnit.fromKey(j['repeatUnit'] as String?),
        waitForDone: j['waitForDone'] as bool? ?? true,
        notify: j['notify'] as bool? ?? true,
        display: j['display'] == null || j['display'] == 'default'
            ? null
            : DisplayFormat.fromKey(j['display'] as String),
        finishText: j['finishText'] as String? ?? '',
        alert: AlertMode.fromKey(j['alert'] as String?),
        widgetOpacity: ((j['widgetOpacity'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
      );

  static String encodeList(List<Cooldown> list) => jsonEncode(list.map((c) => c.toJson()).toList());

  static List<Cooldown> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((e) => Cooldown.fromJson(e as Map<String, dynamic>)).toList();
  }
}

/// Adds n units to [t] in local wall-clock time. Months/years clamp the day to
/// the end of the month (Jan 31 + 1 month = Feb 28/29), same as Swift/Kotlin.
DateTime addInterval(DateTime t, RepeatUnit unit, int n) {
  switch (unit) {
    case RepeatUnit.hours:
      return t.add(Duration(hours: n));
    case RepeatUnit.days:
      return DateTime(t.year, t.month, t.day + n, t.hour, t.minute, t.second, t.millisecond);
    case RepeatUnit.weeks:
      return DateTime(t.year, t.month, t.day + 7 * n, t.hour, t.minute, t.second, t.millisecond);
    case RepeatUnit.months:
      return _addMonths(t, n);
    case RepeatUnit.years:
      return _addMonths(t, 12 * n);
  }
}

DateTime _addMonths(DateTime t, int months) {
  final total = t.year * 12 + (t.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  final d = t.day > lastDay ? lastDay : t.day;
  return DateTime(y, m, d, t.hour, t.minute, t.second, t.millisecond);
}
