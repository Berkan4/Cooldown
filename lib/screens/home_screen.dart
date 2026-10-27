import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cooldown.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import '../utils/format.dart';
import 'edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.notifications});

  final CooldownStore store;
  final NotificationService notifications;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  Future<void> _openEditor([Cooldown? existing]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditScreen(store: widget.store, notifications: widget.notifications, existing: existing),
    ));
  }

  Future<void> _addWidget(Cooldown c) async {
    final pinned = await widget.store.requestPinWidget(c);
    if (pinned || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a widget'),
        content: Text(Platform.isIOS
            ? '1. Long-press your home screen (or lock screen) and tap “Edit” → “Add Widget”.\n'
                '2. Search for “Cooldown” and add it.\n'
                '3. Long-press the new widget → “Edit Widget” and pick “${c.name}”.'
            : '1. Long-press your home screen and open “Widgets”.\n'
                '2. Find “Cooldown” and drag it onto the screen.\n'
                '3. Pick “${c.name}” from the list that appears.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _confirmDelete(Cooldown c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${c.name}”?'),
        content: const Text('Widgets showing it will show “not found”.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await widget.store.delete(c);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final items = widget.store.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cooldowns'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(store: widget.store, notifications: widget.notifications),
                )),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('New cooldown'),
          ),
          body: items.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return _CooldownCard(
                      cooldown: c,
                      format: widget.store.displayFor(c),
                      onTap: () => _openEditor(c),
                      onDone: () => widget.store.markDone(c),
                      onAction: (action) {
                        switch (action) {
                          case _Action.edit:
                            _openEditor(c);
                          case _Action.restart:
                            widget.store.markDone(c);
                          case _Action.widget:
                            _addWidget(c);
                          case _Action.delete:
                            _confirmDelete(c);
                        }
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

enum _Action { edit, restart, widget, delete }

class _CooldownCard extends StatelessWidget {
  const _CooldownCard({
    required this.cooldown,
    required this.format,
    required this.onTap,
    required this.onDone,
    required this.onAction,
  });

  final Cooldown cooldown;
  final DisplayFormat format;
  final VoidCallback onTap;
  final VoidCallback onDone;
  final ValueChanged<_Action> onAction;

  @override
  Widget build(BuildContext context) {
    final c = cooldown;
    final now = DateTime.now();
    final end = c.currentEnd(now);
    final begin = c.currentStart(now);
    final finished = !end.isAfter(now);
    final remaining = formatRemaining(now, end, format);
    final accent = Color(c.color);
    final theme = Theme.of(context);

    final totalMs = end.difference(begin).inMilliseconds;
    final progress = totalMs <= 0 ? 1.0 : (now.difference(begin).inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                        Text(
                          '${describeRepeat(c)}${c.notify ? '' : ' · silent'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_Action>(
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                      if (c.repeats) const PopupMenuItem(value: _Action.restart, child: Text('Restart now')),
                      const PopupMenuItem(value: _Action.widget, child: Text('Add to home screen')),
                      const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (finished)
                      Text(c.repeats ? 'Ready' : 'Done 🎉',
                          style: theme.textTheme.headlineMedium?.copyWith(color: accent, fontWeight: FontWeight.w700))
                    else ...[
                      Text(remaining.value,
                          style: theme.textTheme.headlineMedium?.copyWith(color: accent, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(remaining.label, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                    const Spacer(),
                    if (finished && c.repeats && c.waitForDone)
                      FilledButton.icon(
                        onPressed: onDone,
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                        style: FilledButton.styleFrom(backgroundColor: accent),
                      ),
                  ],
                ),
              ),
              if (finished && c.finishText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 12),
                  child: Text(c.finishText, style: theme.textTheme.titleSmall?.copyWith(color: accent)),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.15),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                finished ? 'Ended ${_fmtDate(end)}' : 'Ends ${_fmtDate(end)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy · HH:mm').format(d);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏳', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('No cooldowns yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Count down to a date (a game release) or set a repeating cooldown (water the plants every 3 days).',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
