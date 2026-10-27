import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/cooldown.dart';

/// Each cooldown owns notification IDs seq*10 .. seq*10+9.
const int _idsPerCooldown = 10;

/// How many future occurrences of an auto-repeating cooldown are queued, so
/// reminders keep firing even if the app isn't opened for a while.
const int _occurrencesAhead = 5;

/// iOS keeps at most 64 pending notifications per app.
const int _maxPending = 60;

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _exactAllowed = false;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('Timezone lookup failed, using UTC: $e');
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    await _refreshExactPermission();
  }

  /// Ask for permission to post notifications (Android 13+, iOS).
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? true;
      await _refreshExactPermission();
      return granted;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true;
  }

  bool get exactAlarmsAllowed => !Platform.isAndroid || _exactAllowed;

  /// Android 12+: opens the system screen for "Alarms & reminders" so
  /// reminders fire on the minute instead of within a ~10-minute window.
  Future<void> requestExactAlarms() async {
    if (!Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    await _refreshExactPermission();
  }

  Future<void> _refreshExactPermission() async {
    if (!Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    _exactAllowed = await android?.canScheduleExactNotifications() ?? false;
  }

  Future<void> cancelFor(Cooldown c) async {
    for (var i = 0; i < _idsPerCooldown; i++) {
      await _plugin.cancel(c.seq * _idsPerCooldown + i);
    }
  }

  static String _defaultBody(Cooldown c) => !c.repeats
      ? 'Your cooldown is over.'
      : c.waitForDone
          ? 'Ready! Open the app and tap Done to start the next round.'
          : 'Ready! The next round has started automatically.';

  /// Simplest correct approach: wipe and rebuild the whole queue whenever
  /// anything changes or the app starts.
  Future<void> rescheduleAll(List<Cooldown> items) async {
    await _plugin.cancelAll();
    final now = DateTime.now();

    final jobs = <({int id, Cooldown c, DateTime at})>[];
    for (final c in items.where((c) => c.notify)) {
      final ends = c.upcomingEnds(now, c.autoRepeats ? _occurrencesAhead : 1);
      for (var i = 0; i < ends.length; i++) {
        jobs.add((id: c.seq * _idsPerCooldown + i, c: c, at: ends[i]));
      }
    }
    jobs.sort((a, b) => a.at.compareTo(b.at));

    final mode = exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final job in jobs.take(_maxPending)) {
      final c = job.c;
      final title = '${c.emoji} ${c.name.isEmpty ? 'Cooldown' : c.name}';
      final body = c.finishText.isNotEmpty ? c.finishText : _defaultBody(c);
      try {
        await _plugin.zonedSchedule(
          job.id,
          title,
          body,
          tz.TZDateTime.from(job.at, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'cooldown_end',
              'Cooldown finished',
              channelDescription: 'Shown when a cooldown ends',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: mode,
          payload: c.id,
        );
      } catch (e) {
        debugPrint('Could not schedule notification for ${c.name}: $e');
      }
    }
  }
}
