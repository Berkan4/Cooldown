import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/cooldown.dart';
import '../services/notifications.dart';
import '../services/store.dart';
import '../utils/colors.dart';
import '../utils/format.dart';
import 'detail_screen.dart';
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
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    if (Platform.isAndroid || Platform.isIOS) {
      // Tapping a widget opens the app on that widget's cooldown, whether the
      // app was closed (initial launch) or still running (click stream).
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget, onError: (_) {});
      _widgetClicks = HomeWidget.widgetClicked.listen(_openFromWidget, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    _widgetClicks?.cancel();
    super.dispose();
  }

  /// Widget links look like `cooldown://open?id=<cooldown id>&homeWidget`.
  void _openFromWidget(Uri? uri) {
    final id = uri?.queryParameters['id'];
    if (!mounted || id == null || widget.store.byId(id) == null) return;
    final nav = Navigator.of(context);
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute<void>(
      builder: (_) => DetailScreen(store: widget.store, notifications: widget.notifications, cooldownId: id),
    ));
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
        final compact = widget.store.compactList;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cooldowns'),
            actions: [
              IconButton(
                icon: Icon(compact ? Icons.view_agenda_outlined : Icons.view_list_outlined),
                tooltip: compact ? 'Card view' : 'Compact list',
                onPressed: () => widget.store.setCompactList(!compact),
              ),
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
                  separatorBuilder: (_, __) => SizedBox(height: compact ? 6 : 12),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    void onAction(_Action action) {
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
                    }

                    return (compact ? _CooldownRow.new : _CooldownCard.new)(
                      cooldown: c,
                      format: widget.store.displayFor(c),
                      onTap: () => _openEditor(c),
                      onDone: () => widget.store.markDone(c),
                      onAction: onAction,
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

    // Same look as the widget: solid in the cooldown's colour (the widget
    // transparency setting does not apply here).
    final fg = foregroundOn(accent);
    final muted = fg.withValues(alpha: 0.8);

    return Card(
      color: accent,
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
                        Text(
                          c.name,
                          style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${describeRepeat(c)}${alertSuffix(c)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  _ActionsMenu(cooldown: c, onAction: onAction, color: fg),
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
                          style: theme.textTheme.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w700))
                    else ...[
                      Text(remaining.value,
                          style: theme.textTheme.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(remaining.label, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                      ),
                    ],
                    const Spacer(),
                    if (finished && c.repeats && c.waitForDone)
                      FilledButton.icon(
                        onPressed: onDone,
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                        style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: accent),
                      ),
                  ],
                ),
              ),
              if (finished && c.finishText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 12),
                  child: Text(c.finishText,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: fg,
                    backgroundColor: fg.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                finished ? 'Ended ${_fmtDate(end)}' : 'Ends ${_fmtDate(end)}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy · HH:mm').format(d);
}

/// One line per cooldown, to see many at a glance.
class _CooldownRow extends StatelessWidget {
  const _CooldownRow({
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
    final value = finished ? (c.repeats ? 'Ready' : 'Done') : remaining.value;
    final label = finished ? '' : remaining.label;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                child: Text(c.emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    if (finished && c.finishText.isNotEmpty)
                      Text(c.finishText, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (label.isNotEmpty) TextSpan(text: ' $label', style: theme.textTheme.bodySmall),
                  ]),
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (finished && c.repeats && c.waitForDone)
                IconButton.filled(
                  tooltip: 'Done',
                  onPressed: onDone,
                  icon: const Icon(Icons.check),
                  style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: foregroundOn(accent)),
                )
              else
                _ActionsMenu(cooldown: c, onAction: onAction),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.cooldown, required this.onAction, this.color});

  final Cooldown cooldown;
  final ValueChanged<_Action> onAction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Action>(
      iconColor: color,
      onSelected: onAction,
      itemBuilder: (_) => [
        const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
        if (cooldown.repeats) const PopupMenuItem(value: _Action.restart, child: Text('Restart now')),
        const PopupMenuItem(value: _Action.widget, child: Text('Add to home screen')),
        const PopupMenuItem(value: _Action.delete, child: Text('Delete')),
      ],
    );
  }
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
