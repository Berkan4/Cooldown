import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'services/notifications.dart';
import 'services/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  final store = CooldownStore(notifications);
  await store.load();
  runApp(CooldownApp(store: store, notifications: notifications));
}

class CooldownApp extends StatefulWidget {
  const CooldownApp({super.key, required this.store, required this.notifications});

  final CooldownStore store;
  final NotificationService notifications;

  @override
  State<CooldownApp> createState() => _CooldownAppState();
}

class _CooldownAppState extends State<CooldownApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app: reload (a widget may have changed nothing, but
    // repeating reminders get topped up and widgets refreshed).
    if (state == AppLifecycleState.resumed) widget.store.load();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4F7CAC);
    return MaterialApp(
      title: 'Cooldown',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('de'), Locale('tr')],
      home: HomeScreen(store: widget.store, notifications: widget.notifications),
    );
  }
}
