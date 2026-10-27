import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:uuid/uuid.dart';

import '../models/cooldown.dart';
import 'notifications.dart';

/// Must match the App Group configured in Xcode for both the Runner target and
/// the widget extension (see README).
const String kAppGroupId = 'group.com.berkan.cooldown';
const String kIOSWidgetKind = 'CooldownWidget';
const String kAndroidWidgetName = 'CooldownWidgetProvider';
const String kAndroidWidgetQualified = 'com.berkan.cooldown.CooldownWidgetProvider';

const _kCooldowns = 'cooldowns';
const _kDefaultDisplay = 'default_display';
const _kPendingPin = 'pending_pin';
const _kListView = 'list_view';

/// Single source of truth. Everything is stored in the widget-shared storage
/// (SharedPreferences "HomeWidgetPreferences" on Android, App Group
/// UserDefaults on iOS) so the widgets read exactly what the app writes.
class CooldownStore extends ChangeNotifier {
  CooldownStore(this._notifications);

  final NotificationService _notifications;
  final List<Cooldown> _items = [];
  DisplayFormat _defaultDisplay = DisplayFormat.days;
  bool _compactList = false;

  List<Cooldown> get items {
    final now = DateTime.now();
    final sorted = [..._items];
    sorted.sort((a, b) => a.currentEnd(now).compareTo(b.currentEnd(now)));
    return sorted;
  }

  DisplayFormat get defaultDisplay => _defaultDisplay;

  /// Home screen shows small rows instead of big cards.
  bool get compactList => _compactList;
  DisplayFormat displayFor(Cooldown c) => c.display ?? _defaultDisplay;

  Future<void> load() async {
    if (Platform.isIOS) await HomeWidget.setAppGroupId(kAppGroupId);
    final raw = await HomeWidget.getWidgetData<String>(_kCooldowns);
    _items
      ..clear()
      ..addAll(Cooldown.decodeList(raw));
    _defaultDisplay = DisplayFormat.fromKey(await HomeWidget.getWidgetData<String>(_kDefaultDisplay));
    _compactList = await HomeWidget.getWidgetData<String>(_kListView) == 'compact';
    notifyListeners();
    // Re-schedule on every launch: keeps repeating reminders topped up.
    await _notifications.rescheduleAll(_items);
    await _refreshWidgets();
  }

  Cooldown? byId(String id) {
    for (final c in _items) {
      if (c.id == id) return c;
    }
    return null;
  }

  Cooldown newDraft() {
    final now = DateTime.now();
    final usedSeqs = _items.map((c) => c.seq).toSet();
    var seq = 1;
    while (usedSeqs.contains(seq)) {
      seq++;
    }
    return Cooldown(
      id: const Uuid().v4(),
      seq: seq,
      name: '',
      emoji: '⏳',
      color: 0xFF4F7CAC,
      target: now.add(const Duration(days: 7)),
      start: now,
      repeatValue: 0,
      repeatUnit: RepeatUnit.days,
      waitForDone: true,
      notify: true,
    );
  }

  Future<void> upsert(Cooldown c) async {
    final i = _items.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      _items[i] = c;
    } else {
      _items.add(c);
    }
    await _persist();
  }

  Future<void> delete(Cooldown c) async {
    _items.removeWhere((e) => e.id == c.id);
    await _notifications.cancelFor(c);
    await _persist();
  }

  Future<void> markDone(Cooldown c) async {
    c.restart(DateTime.now());
    await _persist();
  }

  Future<void> setDefaultDisplay(DisplayFormat f) async {
    _defaultDisplay = f;
    await HomeWidget.saveWidgetData<String>(_kDefaultDisplay, f.key);
    notifyListeners();
    await _refreshWidgets();
  }

  Future<void> setCompactList(bool compact) async {
    _compactList = compact;
    notifyListeners();
    await HomeWidget.saveWidgetData<String>(_kListView, compact ? 'compact' : 'cards');
  }

  /// Android: asks the launcher to pin a widget showing [c].
  /// Returns false where that is not possible (iOS, or unsupported launcher).
  Future<bool> requestPinWidget(Cooldown c) async {
    if (!Platform.isAndroid) return false;
    final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
    if (!supported) return false;
    await HomeWidget.saveWidgetData<String>(_kPendingPin, c.id);
    await HomeWidget.requestPinWidget(
      name: kAndroidWidgetName,
      androidName: kAndroidWidgetName,
      qualifiedAndroidName: kAndroidWidgetQualified,
    );
    return true;
  }

  Future<void> _persist() async {
    await HomeWidget.saveWidgetData<String>(_kCooldowns, Cooldown.encodeList(_items));
    notifyListeners();
    await _notifications.rescheduleAll(_items);
    await _refreshWidgets();
  }

  Future<void> _refreshWidgets() async {
    try {
      await HomeWidget.updateWidget(
        name: kAndroidWidgetName,
        androidName: kAndroidWidgetName,
        qualifiedAndroidName: kAndroidWidgetQualified,
        iOSName: kIOSWidgetKind,
      );
    } catch (e) {
      debugPrint('Widget refresh failed: $e');
    }
  }
}
