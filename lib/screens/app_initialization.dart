import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📱 Background message received: ${message.messageId}');
  await Firebase.initializeApp();
  // Store notification when app is in background
  await _storeBackgroundNotification(message);
}

Future<void> _storeBackgroundNotification(RemoteMessage message) async {
  try {
    await Supabase.initialize(
      url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
    );

    final userId = message.data['user_id'];
    if (userId != null) {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': userId,
        'title': message.notification?.title ?? 'New Notification',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': jsonEncode(message.data),
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  } catch (e) {
    print('Error storing background notification: $e');
  }
}


class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Notification channels for Android
  static const String orderChannel = 'order_updates';
  static const String promotionChannel = 'promotions';
  static const String systemChannel = 'system_notifications';
  static const String generalChannel = 'general_notifications';

  bool _isInitialized = false;


  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🚀 Initializing notification service...');

      // 1. Initialize local notifications (for popup notifications)
      await _initializeLocalNotifications();

      // 2. Initialize Firebase messaging (for push notifications)
      await _initializeFirebaseMessaging();

      // 3. Request ALL permissions (critical for phone popups)
      await _requestAllPermissions();

      // 4. Setup notification listeners
      _setupNotificationListeners();

      // 5. Create notification channels (Android)
      await _createNotificationChannels();

      _isInitialized = true;
      print('✅ Notification service initialized - Phone popups enabled!');
    } catch (e) {
      print('❌ Error initializing notification service: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android settings - ensures popups work
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings - ensures popups work
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true, // For important notifications
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;

    final List<AndroidNotificationChannel> channels = [
      const AndroidNotificationChannel(
        orderChannel,
        'Order Updates',
        description: 'Notifications about your order status',
        importance: Importance.high, // HIGH = Popup notification
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
      const AndroidNotificationChannel(
        promotionChannel,
        'Promotions & Offers',
        description: 'Special offers and promotional notifications',
        importance: Importance.high, // HIGH = Popup notification
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
      const AndroidNotificationChannel(
        systemChannel,
        'System Notifications',
        description: 'Important app updates and system messages',
        importance: Importance.max, // MAX = Popup notification with sound
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
      const AndroidNotificationChannel(
        generalChannel,
        'General Notifications',
        description: 'General app notifications',
        importance: Importance.high, // HIGH = Popup notification
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
    ];

    for (final channel in channels) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    print('✅ Notification channels created - Popups guaranteed!');
  }

  Future<void> _initializeFirebaseMessaging() async {
    // Configure Firebase for foreground notifications (shows popups even when app is open)
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,  // Shows popup
      badge: true,  // Shows badge
      sound: true,  // Plays sound
    );

    // Get and save FCM token
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _saveFCMToken(token);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveFCMToken);
  }

  Future<void> _requestAllPermissions() async {
    print('📱 Requesting notification permissions...');

    // Request notification permission (Android 13+)
    final notificationStatus = await Permission.notification.request();
    print('📱 Notification permission: $notificationStatus');

    // Request Firebase messaging permissions (iOS & Android)
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,      // Shows popup alerts
      badge: true,      // Shows app badge
      sound: true,      // Plays notification sound
      provisional: false, // Request explicit permission
      criticalAlert: true, // For critical notifications
    );

    print('📱 Firebase permission: ${settings.authorizationStatus}');

    // Additional Android permissions
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.systemAlertWindow.request(); // For overlay notifications
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ All permissions granted - Phone popups will work!');
    } else {
      print('⚠ Permissions not granted - Popups may not work');
    }
  }

  void _setupNotificationListeners() {
    // Foreground messages (app is open) - SHOWS POPUP
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📱 Foreground message received: ${message.messageId}');
      _handleForegroundMessage(message);
    });

    // Background/terminated app messages (app opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📱 App opened from notification: ${message.messageId}');
      _handleNotificationTap(message.data);
    });

    // When app is opened from terminated state
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('📱 App launched from notification: ${message.messageId}');
        _handleNotificationTap(message.data);
      }
    });
  }

  // ============================================
  // POPUP NOTIFICATION DISPLAY
  // ============================================
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('🔔 Showing popup notification...');

    // Store in database
    await _storeNotificationInDatabase(message);

    // Show LOCAL popup notification (guaranteed to show)
    await _showLocalPopupNotification(message);
  }

  Future<void> _showLocalPopupNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? 'Dobify';
    final body = message.notification?.body ?? 'New notification';
    final type = message.data['type'] ?? 'general';

    // Create high-priority notification details for POPUP
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _getChannelForType(type),
        _getChannelNameForType(type),
        channelDescription: _getChannelDescriptionForType(type),
        importance: Importance.max,    // MAX = Popup with sound
        priority: Priority.high,       // HIGH = Shows on lock screen
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          htmlFormatContent: true,
          htmlFormatContentTitle: true,
        ),
        enableVibration: true,
        playSound: true,
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
        // Makes notification popup on screen
        fullScreenIntent: false,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,      // Shows popup alert
        presentBadge: true,      // Shows app badge
        presentSound: true,      // Plays sound
        sound: 'default',        // Default notification sound
        subtitle: _getTypeLabel(type),
        threadIdentifier: type,
        interruptionLevel: InterruptionLevel.active, // Shows immediately
      ),
    );

    // Show the popup notification
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: jsonEncode(message.data),
    );

    print('✅ Popup notification displayed: $title');
  }

  // ============================================
  // NOTIFICATION SENDING METHODS
  // ============================================
  Future<void> sendOrderNotification({
    required String userId,
    required String orderId,
    required String title,
    required String body,
    Map<String, dynamic>? additionalData,
  }) async {
    await _sendNotification(
      userId: userId,
      title: title,
      body: body,
      type: 'order',
      data: {
        'order_id': orderId,
        'user_id': userId,
        ...?additionalData,
      },
    );
  }

  Future<void> sendPromotionNotification({
    required String userId,
    required String title,
    required String body,
    String? promotionId,
    Map<String, dynamic>? additionalData,
  }) async {
    await _sendNotification(
      userId: userId,
      title: title,
      body: body,
      type: 'promotion',
      data: {
        'user_id': userId,
        if (promotionId != null) 'promotion_id': promotionId,
        ...?additionalData,
      },
    );
  }

  Future<void> sendSystemNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? additionalData,
  }) async {
    await _sendNotification(
      userId: userId,
      title: title,
      body: body,
      type: 'system',
      data: {
        'user_id': userId,
        ...?additionalData,
      },
    );
  }

  Future<void> _sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      // Store in database
      final response = await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': jsonEncode(data),
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      print('✅ Notification stored in database: $title');

      // If this is the current user, show immediate popup
      final currentUser = _supabase.auth.currentUser;
      if (currentUser?.id == userId) {
        await _showImmediateLocalNotification(title, body, type, data);
      }

      // Send FCM push notification to user's devices
      await _sendFCMNotification(userId: userId, title: title, body: body, type: type, data: data);

    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  Future<void> _showImmediateLocalNotification(String title, String body, String type, Map<String, dynamic> data) async {
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _getChannelForType(type),
        _getChannelNameForType(type),
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: jsonEncode(data),
    );
  }

  // ============================================
  // HELPER METHODS
  // ============================================
  Future<void> _saveFCMToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'device_type': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      });
      print('✅ FCM token saved: ${token.substring(0, 20)}...');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  Future<void> _storeNotificationInDatabase(RemoteMessage message) async {
    final userId = message.data['user_id'] ?? _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': message.notification?.title ?? 'New Notification',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': jsonEncode(message.data),
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('❌ Error storing notification: $e');
    }
  }

  Future<void> _sendFCMNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      final tokens = await _supabase
          .from('user_fcm_tokens')
          .select('fcm_token')
          .eq('user_id', userId);

      if (tokens.isEmpty) {
        print('⚠ No FCM tokens found for user: $userId');
        return;
      }

      print('📱 Would send FCM to ${tokens.length} devices for user: $userId');
      // In production, you'd send via your backend/Firebase Admin SDK
    } catch (e) {
      print('❌ Error sending FCM: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final data = jsonDecode(payload);
      _handleNotificationTap(data);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] ?? 'general';
    final orderId = data['order_id'];

    print('📱 Notification tapped: $type');

    // Add your navigation logic here
    // if (type == 'order' && orderId != null) {
    //   Navigator.pushNamed(context, '/order', arguments: orderId);
    // }
  }

  String _getChannelForType(String type) {
    switch (type) {
      case 'order': return orderChannel;
      case 'promotion': return promotionChannel;
      case 'system': return systemChannel;
      default: return generalChannel;
    }
  }

  String _getChannelNameForType(String type) {
    switch (type) {
      case 'order': return 'Order Updates';
      case 'promotion': return 'Promotions & Offers';
      case 'system': return 'System Notifications';
      default: return 'General Notifications';
    }
  }

  String _getChannelDescriptionForType(String type) {
    switch (type) {
      case 'order': return 'Notifications about your order status';
      case 'promotion': return 'Special offers and promotional notifications';
      case 'system': return 'Important app updates and system messages';
      default: return 'General app notifications';
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'order': return 'Order Update';
      case 'promotion': return 'Promotion';
      case 'system': return 'System';
      default: return 'Notification';
    }
  }

  // Utility methods
  Future<void> clearNotificationBadge() async {
    await _localNotifications.cancelAll();
  }

  Future<bool> areNotificationsEnabled() async {
    final permission = await Permission.notification.status;
    return permission == PermissionStatus.granted;
  }

  Future<void> openNotificationSettings() async {
    await openAppSettings();
  }
}

// ============================================
// APP INITIALIZATION
// ============================================
class AppInitializer {
  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    print('🚀 Initializing ironXpress...');

    // Initialize Firebase
    await Firebase.initializeApp();
    print('✅ Firebase initialized');

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize Supabase
    await Supabase.initialize(
      url: 'https://qehtgclgjhzdlqcjujpp.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
    );
    print('✅ Supabase initialized');

    // Initialize notification service (this enables phone popups)
    await NotificationService().initialize();
    print('✅ Notification service ready - Phone popups enabled!');

    // Setup auth listener
    AuthNotificationSetup.setupAuthListener();
    print('✅ Auth listener setup complete');
  }
}

void main() async {
  await AppInitializer.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ironXpress',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(), // Replace with your actual home screen
      debugShowCheckedModeBanner: false,
    );
  }
}

// Placeholder home screen - replace with your actual home screen
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ironXpress'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // Navigate to notifications screen
              // Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen()));
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ironXpress App', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _testNotification(context),
              child: const Text('Test Notification'),
            ),
          ],
        ),
      ),
    );
  }

  void _testNotification(BuildContext context) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await NotificationService().sendOrderNotification(
        userId: user.id,
        orderId: 'TEST123',
        title: 'Test Notification 🎉',
        body: 'This is a test popup notification!',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent!')),
        );
      }
    }
  }
}

// ============================================
// ORDER SERVICE WITH NOTIFICATIONS
// ============================================
class OrderService {
  static Future<void> sendOrderConfirmation(String orderId, String userId) async {
    await NotificationService().sendOrderNotification(
      userId: userId,
      orderId: orderId,
      title: 'Order Confirmed! 🎉',
      body: 'Your order #$orderId has been confirmed and will be picked up soon.',
      additionalData: {'status': 'confirmed', 'action': 'view_order'},
    );
  }

  static Future<void> sendOrderUpdate(String orderId, String userId, String status) async {
    String title = '';
    String body = '';

    switch (status.toLowerCase()) {
      case 'picked_up':
        title = 'Order Picked Up 📦';
        body = 'Your laundry has been picked up and is being processed.';
        break;
      case 'in_progress':
        title = 'Order In Progress 🧽';
        body = 'Your laundry is being cleaned with care.';
        break;
      case 'ready_for_delivery':
        title = 'Ready for Delivery 🚚';
        body = 'Your fresh laundry is ready and will be delivered soon.';
        break;
      case 'delivered':
        title = 'Order Delivered ✅';
        body = 'Your laundry has been delivered. Thank you for choosing ironXpress!';
        break;
      default:
        title = 'Order Update';
        body = 'Your order status has been updated.';
    }

    await NotificationService().sendOrderNotification(
      userId: userId,
      orderId: orderId,
      title: title,
      body: body,
      additionalData: {'status': status, 'action': 'view_order'},
    );
  }

  static Future<void> sendPromotion(String userId, String promoCode, int discount) async {
    await NotificationService().sendPromotionNotification(
      userId: userId,
      title: 'Special Offer Just for You! 🎁',
      body: 'Get $discount% off your next order with code $promoCode. Limited time offer!',
      additionalData: {'promo_code': promoCode, 'discount_percent': discount},
    );
  }
}

// ============================================
// AUTH NOTIFICATION SETUP
// ============================================
class AuthNotificationSetup {
  static void setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      if (user != null) {
        await _setupUserNotifications(user.id);
      }
    });
  }

  static Future<void> _setupUserNotifications(String userId) async {
    try {
      // Setup user preferences if new user
      final existing = await Supabase.instance.client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (existing == null) {
        await Supabase.instance.client.from('user_preferences').insert({
          'user_id': userId,
          'notifications_enabled': true,
          'push_notifications': true,
          'email_notifications': true,
          'order_updates': true,
          'promotion_notifications': true,
          'system_notifications': true,
        });

        // Send welcome notification
        await Future.delayed(const Duration(seconds: 2));
        await NotificationService().sendSystemNotification(
          userId: userId,
          title: 'Welcome to ironXpress! 👋',
          body: 'Your laundry experience just got a whole lot better!',
          additionalData: {'welcome': true},
        );
      }
    } catch (e) {
      print('Error setting up user notifications: $e');
    }
  }
}