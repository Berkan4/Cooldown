import 'package:cooldown/main.dart';
import 'package:cooldown/models/cooldown.dart';
import 'package:cooldown/services/notifications.dart';
import 'package:cooldown/services/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Notifications need the real plugin; the UI tests don't.
class _FakeNotifications extends NotificationService {
  @override
  Future<void> rescheduleAll(List<Cooldown> items) async {}

  @override
  Future<void> cancelFor(Cooldown c) async {}

  @override
  Future<bool> requestPermission() async => true;
}

/// In-memory stand-in for home_widget's shared storage.
final _storage = <String, Object?>{};

Future<CooldownStore> _store() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('home_widget'),
    (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'saveWidgetData':
          _storage[args!['id'] as String] = args['data'];
        case 'getWidgetData':
          return _storage[args!['id']] ?? args['defaultValue'];
      }
      return true;
    },
  );
  final store = CooldownStore(_FakeNotifications());
  await store.load();
  return store;
}

void main() {
  setUp(() {
    _storage.clear();
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 3;
  });

  testWidgets('starts empty, creates a cooldown and lists it', (tester) async {
    final store = await _store();
    await tester.pumpWidget(CooldownApp(store: store, notifications: _FakeNotifications()));
    expect(find.text('No cooldowns yet'), findsOneWidget);

    await tester.tap(find.text('New cooldown'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Water the plants');
    await tester.enterText(find.widgetWithText(TextField, 'Ends in'), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Water the plants'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(store.items.single.name, 'Water the plants');
    // Saved to the storage the widgets read.
    expect(Cooldown.decodeList(_storage['cooldowns'] as String).single.name, 'Water the plants');

    // Unmount so the home screen's 1-second ticker is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact list toggle is remembered', (tester) async {
    final store = await _store();
    await tester.pumpWidget(CooldownApp(store: store, notifications: _FakeNotifications()));

    await tester.tap(find.byTooltip('Compact list'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Card view'), findsOneWidget);
    expect(_storage['list_view'], 'compact');

    await tester.pumpWidget(const SizedBox());
  });
}
