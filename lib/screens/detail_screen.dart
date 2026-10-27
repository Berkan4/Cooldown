import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cooldown.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import '../utils/colors.dart';
import '../utils/format.dart';
import 'edit_screen.dart';

/// One cooldown, big. Opened by tapping its home-screen widget.
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.store, required this.notifications, required this.cooldownId});

  final CooldownStore store;
  final NotificationService notifications;
  final String cooldownId;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final c = widget.store.byId(widget.cooldownId);
        if (c == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This cooldown no longer exists.')));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EditScreen(store: widget.store, notifications: widget.notifications, existing: c),
                )),
              ),
            ],
          ),
          body: _body(context, c),
        );
      },
    );
  }

  Widget _body(BuildContext context, Cooldown c) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final end = c.currentEnd(now);
    final begin = c.currentStart(now);
    final finished = !end.isAfter(now);
    final remaining = formatRemaining(now, end, widget.store.displayFor(c));
    final accent = Color(c.color);
    final fg = foregroundOn(accent);
    final muted = fg.withValues(alpha: 0.8);
    final totalMs = end.difference(begin).inMilliseconds;
    final progress = totalMs <= 0 ? 1.0 : (now.difference(begin).inMilliseconds / totalMs).clamp(0.0, 1.0);
    final dateFormat = DateFormat('EEE, d MMM yyyy · HH:mm');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  finished ? (c.repeats ? 'Ready' : 'Done 🎉') : remaining.value,
                  style: theme.textTheme.displayLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ),
              if (!finished) Text(remaining.label, style: theme.textTheme.titleLarge?.copyWith(color: muted)),
              if (finished && c.finishText.isNotEmpty)
                Text(c.finishText, style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  color: fg,
                  backgroundColor: fg.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${finished ? 'Ended' : 'Ends'} ${dateFormat.format(end)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (finished && c.repeats && c.waitForDone)
          FilledButton.icon(
            onPressed: () => widget.store.markDone(c),
            icon: const Icon(Icons.check),
            label: const Text('Done – start the next round'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: fg,
              minimumSize: const Size.fromHeight(52),
            ),
          )
        else if (c.repeats)
          OutlinedButton.icon(
            onPressed: () => widget.store.markDone(c),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restart now'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.repeat),
          title: Text(describeRepeat(c)),
          subtitle: Text('${c.repeats ? 'This round started' : 'Started'} ${dateFormat.format(begin)}'),
        ),
        ListTile(
          leading: Icon(c.notify ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          title: Text(c.notify ? 'Reminder: ${c.alert.label}' : 'No reminder'),
        ),
      ],
    );
  }
}
