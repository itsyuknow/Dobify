// ✅ COMPLETE ELECTRIC IRON MAIN.DART - FULL FIREBASE INTEGRATION WITH NOTIFICATIONS
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/home_screen.dart';
import 'screens/colors.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/app_wrapper.dart';
import 'widgets/notification_service.dart';
// import 'firebase_options.dart'; // ✅ Uncomment if using manual config

// 👇 GLOBAL CART COUNT NOTIFIER
final ValueNotifier<int> cartItemCountNotifier = ValueNotifier<int>(0);

// ✅ BACKGROUND MESSAGE HANDLER (TOP-LEVEL FUNCTION)
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  print('📱 Background message received: ${message.messageId}');

  try {
    // Initialize Firebase if needed
    await Firebase.initializeApp();

    // Initialize Supabase if needed - Check if already initialized
    try {
      // Try to access Supabase to see if it's initialized
      Supabase.instance.client;
    } catch (e) {
      // If not initialized, initialize it
      await Supabase.initialize(
        url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
      );
    }

    // Store notification in background
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

  print('🚀 Initializing ironXpress with notifications...');

  try {
    // ✅ Initialize EasyLocalization FIRST
    await EasyLocalization.ensureInitialized();
    print('✅ Localization initialized');

    // ✅ Initialize Firebase with comprehensive error handling
    bool firebaseInitialized = false;
    try {
      // Option 1: Auto-configure (requires google-services.json)
      await Firebase.initializeApp();

      // Option 2: Manual configure (uncomment if google-services.json doesn't work)
      // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      print('✅ Firebase initialized successfully');
      firebaseInitialized = true;

      // ✅ Set background message handler
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
      print('✅ Background message handler set');
    } catch (firebaseError) {
      print('❌ Firebase initialization failed: $firebaseError');
      print('📱 Please check:');
      print('📱 1. google-services.json is in android/app/');
      print('📱 2. Package name matches: com.yuknow.ironly');
      print('📱 3. Firebase project is properly configured');
      print('📱 Continuing without Firebase notifications...');
    }

    // ✅ Initialize Supabase (independent of Firebase)
    await Supabase.initialize(
      url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
    );
    print('✅ Supabase initialized');

    // ✅ Initialize Notification Service (only if Firebase works)
    if (firebaseInitialized) {
      try {
        await NotificationService().initialize();
        print('✅ Notification service initialized');
      } catch (notificationError) {
        print('⚠️ Notification service failed: $notificationError');
        print('📱 Continuing without notifications...');
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
      supportedLocales: const [
        Locale('en'), // English
        Locale('or'), // Odia
        Locale('hi'), // Hindi
      ],
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
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kPrimaryColor, width: 2.0),
              ),
              labelStyle: TextStyle(color: kPrimaryColor),
            ),
          ),
          // ✅ Use premium iron-themed entry point
          home: const IronXpressPremiumEntry(),
          // ✅ Add error handling for localization issues
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
              child: child!,
            );
          },
        );
      },
    );
  }
}

// ✅ PREMIUM IRON-THEMED ENTRY WITH 10-SECOND SPLASH + NOTIFICATION SETUP
class IronXpressPremiumEntry extends StatefulWidget {
  const IronXpressPremiumEntry({super.key});

  @override
  State<IronXpressPremiumEntry> createState() => _IronXpressPremiumEntryState();
}

class _IronXpressPremiumEntryState extends State<IronXpressPremiumEntry>
    with TickerProviderStateMixin {

  // ELECTRIC IRON 10-second animation controllers
  late AnimationController _ironController;
  late AnimationController _steamController;
  late AnimationController _heatController;
  late AnimationController _textController;
  late AnimationController _sparkController;
  late AnimationController _glowController;

  late Animation<double> _ironScale;
  late Animation<double> _ironOpacity;
  late Animation<double> _steamAnimation;
  late Animation<double> _heatAnimation;
  late Animation<double> _textOpacity;
  late Animation<double> _sparkAnimation;
  late Animation<double> _glowAnimation;

  String _statusMessage = 'Heating up the iron...';

  @override
  void initState() {
    super.initState();
    _initializeElectricIronAnimations();
    _startIronXpressSplash();
  }

  void _initializeElectricIronAnimations() {
    // Iron heating animation
    _ironController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Steam generation
    _steamController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Heat glow effect
    _heatController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    // Text animation
    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Electric sparks
    _sparkController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );

    // Glow effect
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _ironScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ironController, curve: Curves.elasticOut),
    );

    _ironOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ironController, curve: Curves.easeInOut),
    );

    _steamAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _steamController, curve: Curves.easeInOut),
    );

    _heatAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heatController, curve: Curves.easeInOut),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOut),
    );

    _sparkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sparkController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  Future<void> _startIronXpressSplash() async {
    print('🔥 Starting ironXpress...');

    // Phase 1: Iron plugging in and heating up (0-2s)
    if (mounted) {
      setState(() {
        _statusMessage = 'Plugging in services...';
      });
    }
    _ironController.forward();
    _glowController.repeat(reverse: true);
    await Future.delayed(const Duration(milliseconds: 2000));

    // Phase 2: Generating steam and heat (2-4s)
    if (mounted) {
      setState(() {
        _statusMessage = 'Generating notifications...';
      });
    }
    _steamController.repeat(reverse: true);
    _heatController.repeat(reverse: true);

    // ✅ Setup notification listeners during splash
    await _setupNotificationSystemAsync();
    await Future.delayed(const Duration(milliseconds: 2000));

    // Phase 3: Electric sparks and power (4-6s)
    if (mounted) {
      setState(() {
        _statusMessage = 'Power optimization...';
      });
    }
    _textController.forward();
    _sparkController.repeat();
    await Future.delayed(const Duration(milliseconds: 2000));

    // Phase 4: Perfect temperature reached (6-8s)
    if (mounted) {
      setState(() {
        _statusMessage = 'Reaching perfect temperature...';
      });
    }
    await Future.delayed(const Duration(milliseconds: 2000));

    // Phase 5: Ready for service (8-10s)
    if (mounted) {
      setState(() {
        _statusMessage = 'Ready at your service...';
      });
    }
    await Future.delayed(const Duration(milliseconds: 2000));

    // Stop animations and navigate to AppWrapper
    _steamController.stop();
    _heatController.stop();
    _sparkController.stop();
    _glowController.stop();

    print('🎉 ironXpress ready with notifications!');
    _navigateToAppWrapper();
  }

  // ✅ Setup notification system during splash screen
  Future<void> _setupNotificationSystemAsync() async {
    try {
      // Setup auth state listener for notifications
      Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        final user = data.session?.user;
        if (user != null) {
          print('📱 User logged in, setting up notifications for: ${user.id}');

          // Setup user-specific notification listeners
          try {
            if (NotificationService().isInitialized) {
              await NotificationService().subscribeToTopics(user.id);
              print('✅ User notifications setup complete for: ${user.id}');
            } else {
              print('⚠️ Notification service not initialized, skipping topic subscription');
            }
          } catch (e) {
            print('❌ Error setting up user notifications: $e');
          }

          // Send welcome notification for new users (optional)
          try {
            final existing = await Supabase.instance.client
                .from('user_profiles')
                .select('user_id')
                .eq('user_id', user.id)
                .maybeSingle();

            if (existing == null) {
              await Future.delayed(const Duration(seconds: 3));
              // You can implement welcome notification logic here
              print('📱 New user detected, could send welcome notification');
            }
          } catch (e) {
            print('❌ Error checking user profile: $e');
          }
        } else {
          print('📱 User signed out, cleaning up notifications');
          try {
            // Unsubscribe from topics when user logs out
            final currentUser = Supabase.instance.client.auth.currentUser;
            if (currentUser != null && NotificationService().isInitialized) {
              await NotificationService().unsubscribeFromTopics(currentUser.id);
            }
          } catch (e) {
            print('❌ Error cleaning up notifications: $e');
          }
        }
      });

      print('✅ Notification system setup complete');
    } catch (e) {
      print('❌ Error setting up notification system: $e');
    }
  }

  void _navigateToAppWrapper() {
    if (mounted) {  // ✅ Check if widget is still mounted
      // ✅ Add a longer delay to ensure Supabase is fully ready
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const AppWrapper(),
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1565C0).withOpacity(0.9), // Electric blue
              const Color(0xFF2196F3).withOpacity(0.8), // Blue
              const Color(0xFF42A5F5).withOpacity(0.7), // Light blue
              const Color(0xFF90CAF9).withOpacity(0.9), // Very light blue
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Electric spark particles
            ...List.generate(25, (index) => _buildElectricSpark(index)),

            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated electric iron with heat and steam
                  AnimatedBuilder(
                    animation: _ironController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _ironScale.value,
                        child: Opacity(
                          opacity: _ironOpacity.value,
                          child: AnimatedBuilder(
                            animation: _heatController,
                            builder: (context, child) {
                              return AnimatedBuilder(
                                animation: _glowController,
                                builder: (context, child) {
                                  return Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.4),
                                          Colors.orange.withOpacity(0.3 * _heatAnimation.value),
                                          Colors.red.withOpacity(0.2 * _heatAnimation.value),
                                          Colors.blue.withOpacity(0.1),
                                        ],
                                        stops: const [0.0, 0.5, 0.7, 1.0],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.withOpacity(0.6 * _glowAnimation.value),
                                          blurRadius: 60,
                                          offset: const Offset(0, 0),
                                        ),
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3 * _glowAnimation.value),
                                          blurRadius: 100,
                                          offset: const Offset(0, 20),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Main iron icon with notification badge
                                        Stack(
                                          children: [
                                            const Icon(
                                              Icons.iron,
                                              size: 90,
                                              color: Colors.white,
                                            ),
                                            // Notification indicator
                                            Positioned(
                                              top: 5,
                                              right: 5,
                                              child: AnimatedBuilder(
                                                animation: _textController,
                                                builder: (context, child) {
                                                  return Opacity(
                                                    opacity: _textOpacity.value,
                                                    child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        color: Colors.red,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.red.withOpacity(0.5),
                                                            blurRadius: 8,
                                                            offset: Offset.zero,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Steam effect
                                        AnimatedBuilder(
                                          animation: _steamController,
                                          builder: (context, child) {
                                            return Positioned(
                                              top: 15,
                                              child: Opacity(
                                                opacity: _steamAnimation.value * 0.8,
                                                child: Transform.scale(
                                                  scale: 1 + _steamAnimation.value * 0.5,
                                                  child: const Icon(
                                                    Icons.cloud,
                                                    size: 35,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        // Heat indicator
                                        AnimatedBuilder(
                                          animation: _heatController,
                                          builder: (context, child) {
                                            return Positioned(
                                              bottom: 15,
                                              child: Opacity(
                                                opacity: _heatAnimation.value * 0.9,
                                                child: Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange,
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.orange.withOpacity(0.8),
                                                        blurRadius: 15,
                                                        offset: Offset.zero,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 60),

                  // Iron service branding
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textOpacity.value,
                        child: const Text(
                          'ironXpress',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 4,
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                offset: Offset(0, 3),
                                blurRadius: 6,
                              ),
                              Shadow(
                                color: Colors.orange,
                                offset: Offset(0, 0),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Service types
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _textOpacity.value * 0.9,
                        child: const Text(
                          'Iron Services • Smart Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Loading indicator with notification setup status
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _textController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textOpacity.value,
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withOpacity(0.15),
                                Colors.orange.withOpacity(0.1),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.3),
                                blurRadius: 25,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withOpacity(0.95),
                              ),
                              strokeWidth: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                            shadows: const [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElectricSpark(int index) {
    final random = (index * 67890) % 1000 / 1000.0;
    final size = MediaQuery.of(context).size;
    final sparkSize = 3 + random * 12;

    return Positioned(
      left: random * size.width,
      top: (random * 0.9 + 0.05) * size.height,
      child: AnimatedBuilder(
        animation: _sparkController,
        builder: (context, child) {
          return AnimatedBuilder(
            animation: _heatController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  (random - 0.5) * 100 * (_sparkAnimation.value) +
                      (random - 0.5) * 30 * (_heatAnimation.value),
                  -40 * (_sparkAnimation.value) +
                      (random - 0.5) * 50 * (_heatAnimation.value),
                ),
                child: Opacity(
                  opacity: (0.2 + random * 0.7) * _ironOpacity.value,
                  child: Container(
                    width: sparkSize,
                    height: sparkSize,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.yellow.withOpacity(0.9),
                          Colors.orange.withOpacity(0.6),
                          Colors.blue.withOpacity(0.3),
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.yellow.withOpacity(0.5),
                          blurRadius: sparkSize * 1.2,
                          offset: Offset.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _ironController.dispose();
    _steamController.dispose();
    _heatController.dispose();
    _textController.dispose();
    _sparkController.dispose();
    _glowController.dispose();
    super.dispose();
  }
}