import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/cooldown.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import '../utils/format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.notifications});

  final CooldownStore store;
  final NotificationService notifications;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sampleNow = DateTime.now();
    final sampleEnd = sampleNow.add(const Duration(days: 23, hours: 5, minutes: 12));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Default time format', style: theme.textTheme.titleSmall),
            ),
            RadioGroup<DisplayFormat>(
              groupValue: widget.store.defaultDisplay,
              onChanged: (f) {
                if (f != null) widget.store.setDefaultDisplay(f);
              },
              child: Column(
                children: [
                  for (final f in DisplayFormat.values)
                    RadioListTile<DisplayFormat>(
                      value: f,
                      title: Text(f.label),
                      subtitle: Text(() {
                        final r = formatRemaining(sampleNow, sampleEnd, f);
                        return 'e.g. ${r.value} ${r.label}';
                      }()),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Allow notifications'),
              subtitle: const Text('Needed for end-of-cooldown reminders'),
              onTap: () async {
                final ok = await widget.notifications.requestPermission();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Notifications allowed' : 'Notifications are off — enable them in system settings'),
                ));
              },
            ),
            if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.alarm_on_outlined),
                title: const Text('On-time reminders'),
                subtitle: Text(widget.notifications.exactAlarmsAllowed
                    ? 'Allowed — reminders fire on the minute'
                    : 'Not allowed — reminders may be up to ~10 min late. Tap to allow “Alarms & reminders”.'),
                onTap: () async {
                  await widget.notifications.requestExactAlarms();
                  await widget.notifications.rescheduleAll(widget.store.items);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}
