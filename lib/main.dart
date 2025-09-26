// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ironly/widgets/mobile_wrapper.dart';
import 'screens/colors.dart';
import 'screens/app_wrapper.dart';
import 'widgets/notification_service.dart';
import 'widgets/notification_handler.dart';

// ✅ Brand colors
const Color kAppPrimaryBlue = Color(0xFF42A5F5);
const Color kAppBackground = Colors.white;
const bool kSilenceAllLogs = true;

final ValueNotifier<int> cartItemCountNotifier = ValueNotifier<int>(0);

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  if (kSilenceAllLogs) _silenceAllLogs();

  return runWithoutPrints(() async {
    try {
      await Firebase.initializeApp();

      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(
          url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
          anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
        );
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': user.id,
          'message_id': message.messageId,
          'title': message.notification?.title ?? 'Dobify',
          'body': message.notification?.body ?? '',
          'data': message.data,
          'type': message.data['type'] ?? 'general',
          'is_read': false,
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      // swallowed
    }
  });
}

/// 🔕 Safe no-op on non-web. We removed dart:js so this won't break mobile.
/// Logs are still silenced by `_silenceAllLogs()` + `runWithoutPrints()`.
void _muteBrowserConsole() {
  if (!kIsWeb) return;
  // Intentionally left blank. If you *really* want to override window.console,
  // implement a small JS snippet in web/index.html instead.
}

/// 🔇 Silence Flutter/Dart framework logging
void _silenceAllLogs() {
  debugPrint = (String? message, {int? wrapWidth}) {};
  FlutterError.onError = (FlutterErrorDetails details) {
    // Intentionally no-op
  };
}

/// 🔇 Run a function inside a zone that ignores all `print()` calls
Future<T> runWithoutPrints<T>(Future<T> Function() body) {
  return runZoned<Future<T>>(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // swallow all print() output
      },
    ),
    onError: (Object error, StackTrace stack) {
      // swallow uncaught errors here (or forward to Crashlytics/Sentry)
    },
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kSilenceAllLogs) {
    _muteBrowserConsole(); // safe no-op without dart:js
    _silenceAllLogs();
    await runWithoutPrints(_bootstrap);
  } else {
    await _bootstrap();
  }
}

// Your existing initialization logic moved here unchanged
Future<void> _bootstrap() async {
  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  try {
    await EasyLocalization.ensureInitialized();

    bool firebaseInitialized = false;
    try {
      await Firebase.initializeApp();
      firebaseInitialized = true;

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    } catch (_) {
      // swallowed when silenced
    }

    await Supabase.initialize(
      url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
    );

    if (firebaseInitialized) {
      try {
        await NotificationService().initialize();
      } catch (_) {}
    }

    AuthHandler.setupAuthListener();
  } catch (_) {}

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('or'), Locale('hi')],
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // This print will be swallowed when kSilenceAllLogs == true
    print('🏗️ MyApp build called — kIsWeb: $kIsWeb');

    return ValueListenableBuilder<int>(
      valueListenable: cartItemCountNotifier,
      builder: (context, count, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dobify',
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(
            primarySwatch: _createMaterialColor(kAppPrimaryBlue),
            primaryColor: kAppPrimaryBlue,
            scaffoldBackgroundColor: kAppBackground,
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAppPrimaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: kAppPrimaryBlue),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide:
                const BorderSide(color: kAppPrimaryBlue, width: 2.0),
              ),
              labelStyle: const TextStyle(color: kAppPrimaryBlue),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: kAppPrimaryBlue,
              elevation: 0,
              titleTextStyle: TextStyle(
                color: kAppPrimaryBlue,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              iconTheme: IconThemeData(color: kAppPrimaryBlue),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: kAppPrimaryBlue,
              unselectedItemColor: Colors.grey.shade600,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),
            useMaterial3: true,
          ),

          // ✅ go straight to the real app
          home: const AppWrapper(),

          // keep MobileWrapper for web layout only
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            final mediaQuery = MediaQuery.of(context);
            final adjustedChild = MediaQuery(
              data: mediaQuery.copyWith(
                textScaleFactor:
                mediaQuery.textScaleFactor.clamp(0.8, 1.3),
              ),
              child: child,
            );
            return kIsWeb ? MobileWrapper(child: adjustedChild) : adjustedChild;
          },
        );
      },
    );
  }
}

// Helper: create MaterialColor from Color
MaterialColor _createMaterialColor(Color color) {
  final List<double> strengths = <double>[.05];
  final Map<int, Color> swatch = <int, Color>{};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (final strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}
