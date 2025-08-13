// ✅ SIMPLIFIED MAIN.DART — PREMIUM SPLASH WITH TRANSPARENT LOGO (NO 10s ANIMATION)
// Shows your transparent PNG logo for 3 seconds, then a status line
// (“Setting up IronXpress…”) and proceeds exactly as before to AppWrapper.
// Nothing else in your app flow is changed.

import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/home_screen.dart';
import 'screens/colors.dart';
import 'screens/login_screen.dart';
import 'screens/app_wrapper.dart';
import 'widgets/notification_service.dart';

// 👇 GLOBAL CART COUNT NOTIFIER
final ValueNotifier<int> cartItemCountNotifier = ValueNotifier<int>(0);

// ✅ BACKGROUND MESSAGE HANDLER (TOP-LEVEL FUNCTION)
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  print('📱 Background message received: ${message.messageId}');
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
    await Supabase.instance.client.from('notifications').insert({
      'message_id': message.messageId,
      'title': message.notification?.title ?? 'IronXpress',
      'body': message.notification?.body ?? '',
      'data': message.data,
      'type': message.data['type'] ?? 'general',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
    print('✅ Background notification stored');
  } catch (e) {
    print('❌ Error in background handler: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  print('🚀 Initializing ironXpress with notifications...');

  try {
    await EasyLocalization.ensureInitialized();
    print('✅ Localization initialized');

    bool firebaseInitialized = false;
    try {
      await Firebase.initializeApp();
      print('✅ Firebase initialized successfully');
      firebaseInitialized = true;
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
      print('✅ Background message handler set');
    } catch (firebaseError) {
      print('❌ Firebase initialization failed: $firebaseError');
      print('📱 Continuing without Firebase notifications...');
    }

    await Supabase.initialize(
      url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
    );
    print('✅ Supabase initialized');

    if (firebaseInitialized) {
      try {
        await NotificationService().initialize();
        print('✅ Notification service initialized');
      } catch (notificationError) {
        print('⚠️ Notification service failed: $notificationError');
      }
    } else {
      print('⚠️ Skipping notification service (Firebase not available)');
    }

    print('🎉 App initialization complete!');
  } catch (e) {
    print('❌ Critical error during initialization: $e');
    print('📱 Starting app with limited functionality...');
  }

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
    return ValueListenableBuilder<int>(
      valueListenable: cartItemCountNotifier,
      builder: (context, count, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'ironXpress',
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(
            primarySwatch: Colors.deepPurple,
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: kPrimaryColor),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kPrimaryColor, width: 2.0),
              ),
              labelStyle: TextStyle(color: kPrimaryColor),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: kPrimaryColor,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              elevation: 8,
            ),
          ),
          home: const IronXpressPremiumEntry(),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final screenHeight = mediaQuery.size.height;
            final screenWidth = mediaQuery.size.width;
            final topPadding = mediaQuery.padding.top;
            final bottomPadding = mediaQuery.padding.bottom;
            final leftPadding = mediaQuery.padding.left;
            final rightPadding = mediaQuery.padding.right;
            final viewInsets = mediaQuery.viewInsets;
            final viewPadding = mediaQuery.viewPadding;
            final effectiveBottomPadding =
            bottomPadding > 0 ? bottomPadding : viewPadding.bottom;

            print('📱 App Builder Debug:');
            print('📱 Screen: ${screenWidth}x${screenHeight}');
            print(
                '📱 Safe Area: top=$topPadding, bottom=$bottomPadding, left=$leftPadding, right=$rightPadding');
            print(
                '📱 View Padding: top=${viewPadding.top}, bottom=${viewPadding.bottom}');
            print(
                '📱 View Insets: top=${viewInsets.top}, bottom=${viewInsets.bottom}');
            print(
                '📱 Effective Bottom: $effectiveBottomPadding, Has Bottom Insets: ${effectiveBottomPadding > 0}');

            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaleFactor: mediaQuery.textScaleFactor.clamp(0.8, 1.3),
                padding: EdgeInsets.only(
                  top: max(topPadding, viewPadding.top),
                  bottom: max(bottomPadding, viewPadding.bottom),
                  left: max(leftPadding, viewPadding.left),
                  right: max(rightPadding, viewPadding.right),
                ),
                viewPadding: EdgeInsets.only(
                  top: max(viewPadding.top, topPadding),
                  bottom: max(viewPadding.bottom, bottomPadding),
                  left: max(viewPadding.left, leftPadding),
                  right: max(viewPadding.right, rightPadding),
                ),
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}

// ✅ PREMIUM ENTRY: Transparent logo splash (3s), then status text, then go forward.
class IronXpressPremiumEntry extends StatefulWidget {
  const IronXpressPremiumEntry({super.key});

  @override
  State<IronXpressPremiumEntry> createState() => _IronXpressPremiumEntryState();
}

class _IronXpressPremiumEntryState extends State<IronXpressPremiumEntry> {
  bool _showStatus = false;
  String _statusMessage = 'Setting up IronXpress…';

  @override
  void initState() {
    super.initState();
    _runSplashSequence();
  }

  Future<void> _runSplashSequence() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() => _showStatus = true);
    await _setupNotificationSystemAsync();
    await Future.delayed(const Duration(seconds: 2));
    _navigateToAppWrapper();
  }

  Future<void> _setupNotificationSystemAsync() async {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        final user = data.session?.user;
        if (user != null) {
          try {
            if (NotificationService().isInitialized) {
              await NotificationService().subscribeToTopics(user.id);
            }
          } catch (_) {}
        } else {
          try {
            final currentUser = Supabase.instance.client.auth.currentUser;
            if (currentUser != null && NotificationService().isInitialized) {
              await NotificationService().unsubscribeFromTopics(currentUser.id);
            }
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  void _navigateToAppWrapper() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        const AppWrapper(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final padding = mq.padding;
    final viewPadding = mq.viewPadding;
    final viewInsets = mq.viewInsets;

    final effectiveTop = max(padding.top, viewPadding.top);
    final effectiveBottom = max(padding.bottom, viewPadding.bottom);
    final availableHeight =
        size.height - effectiveTop - effectiveBottom - viewInsets.bottom;

    final isSmall = availableHeight < 600;
    final isLarge = availableHeight > 800;

    // ⬆️ Increased logo size even more
    final logoSize = isSmall ? 280.0 : (isLarge ? 400.0 : 340.0);
    final statusFontSize = isSmall ? 14.0 : (isLarge ? 20.0 : 17.0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // ⬜ Background color to white
        color: Colors.white,
        child: SafeArea(
          minimum: EdgeInsets.only(
            top: effectiveTop > 0 ? 8 : 24,
            bottom: effectiveBottom > 0 ? 8 : 24,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Transparent PNG logo (now bigger)
                SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Image.asset(
                      'assets/images/ironxpress_logo.png',
                    ),
                  ),
                ),
                SizedBox(height: availableHeight * 0.06),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _showStatus
                      ? Column(
                    key: const ValueKey('status'),
                    children: [
                      SizedBox(
                        width: isSmall ? 50 : 60,
                        height: isSmall ? 50 : 60,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blueAccent, // matches your brand
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: availableHeight * 0.02),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: statusFontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

