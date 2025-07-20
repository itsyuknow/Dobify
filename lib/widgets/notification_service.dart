// widgets/notification_service.dart - COMPLETE PRODUCTION-READY NOTIFICATION SERVICE
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;
  bool _hasPermission = false;

  // ✅ Main initialization method
  Future<void> initialize() async {
    if (_isInitialized) {
      print('🔔 Notification service already initialized');
      return;
    }

    try {
      print('🔔 Initializing notification service...');

      // Step 1: Request permissions
      await _requestPermissions();

      // Step 2: Initialize local notifications
      await _initializeLocalNotifications();

      // Step 3: Get FCM token
      await _getFCMToken();

      // Step 4: Setup message handlers
      _setupMessageHandlers();

      // Step 5: Create notification channels
      await _createNotificationChannels();

      _isInitialized = true;
      print('✅ Notification service initialized successfully');

    } catch (e) {
      print('❌ Error initializing notification service: $e');
      rethrow;
    }
  }

  // ✅ Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      print('🔔 Requesting notification permissions...');

      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        announcement: false,
      );

      _hasPermission = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      print('🔔 Permission status: ${settings.authorizationStatus}');
      print('🔔 Permissions granted: $_hasPermission');

      if (_hasPermission) {
        print('✅ Notification permissions granted');
      } else {
        print('⚠️ Notification permissions denied');
      }
    } catch (e) {
      print('❌ Error requesting permissions: $e');
    }
  }

  // ✅ Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      print('🔔 Initializing local notifications...');

      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      bool? initialized = await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      print('🔔 Local notifications initialized: $initialized');
    } catch (e) {
      print('❌ Error initializing local notifications: $e');
    }
  }

  // ✅ Get FCM token
  Future<void> _getFCMToken() async {
    try {
      print('🔔 Getting FCM token...');

      _fcmToken = await _firebaseMessaging.getToken();

      if (_fcmToken != null) {
        print('✅ FCM Token received: ${_fcmToken!.substring(0, 50)}...');

        // Save token to database
        await _saveFCMTokenToDatabase();

        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          print('🔔 FCM Token refreshed');
          _fcmToken = newToken;
          _saveFCMTokenToDatabase();
        });
      } else {
        print('❌ Failed to get FCM token');
      }
    } catch (e) {
      print('❌ Error getting FCM token: $e');
    }
  }

  // ✅ Save FCM token to Supabase
  Future<void> _saveFCMTokenToDatabase() async {
    if (_fcmToken == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'fcm_token': _fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
      print('✅ FCM token saved to database');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // ✅ Setup Firebase message handlers
  void _setupMessageHandlers() {
    print('🔔 Setting up Firebase message handlers...');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap when app is terminated
    _firebaseMessaging.getInitialMessage().then(_handleNotificationTap);

    print('✅ Message handlers setup complete');
  }

  // ✅ Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground message received: ${message.messageId}');
    print('📱 Title: ${message.notification?.title}');
    print('📱 Body: ${message.notification?.body}');
    print('📱 Data: ${message.data}');

    // Store in database
    await _storeNotificationInDatabase(message);

    // Show local notification
    await _showLocalNotification(message);
  }

  // ✅ Handle notification tap
  Future<void> _handleNotificationTap(RemoteMessage? message) async {
    if (message == null) return;

    print('📱 Notification tapped: ${message.messageId}');

    // Mark as read in database
    await _markNotificationAsRead(message.messageId);

    // Handle navigation based on notification data
    _handleNotificationNavigation(message.data);
  }

  // ✅ Show local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'ironxpress_notifications',
        'IronXpress Notifications',
        channelDescription: 'Notifications for iron services',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        showWhen: true,
        when: null,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        message.notification?.title ?? 'IronXpress',
        message.notification?.body ?? 'You have a new notification',
        details,
        payload: message.messageId,
      );

      print('✅ Local notification shown');
    } catch (e) {
      print('❌ Error showing local notification: $e');
    }
  }

  // ✅ Store notification in Supabase database
  Future<void> _storeNotificationInDatabase(RemoteMessage message) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': user.id,
        'message_id': message.messageId,
        'title': message.notification?.title ?? 'IronXpress',
        'body': message.notification?.body ?? '',
        'data': message.data,
        'type': message.data['type'] ?? 'general',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      print('✅ Notification stored in database');
    } catch (e) {
      print('❌ Error storing notification: $e');
    }
  }

  // ✅ Mark notification as read
  Future<void> _markNotificationAsRead(String? messageId) async {
    if (messageId == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('message_id', messageId)
          .eq('user_id', user.id);
      print('✅ Notification marked as read');
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  // ✅ Handle notification navigation
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] ?? 'general';

    switch (type) {
      case 'order_update':
        print('🔄 Navigate to order: ${data['order_id']}');
        // TODO: Navigate to order details screen
        break;
      case 'promotion':
        print('🎁 Navigate to promotions');
        // TODO: Navigate to promotions screen
        break;
      case 'system':
        print('⚙️ Navigate to system notifications');
        // TODO: Navigate to notifications screen
        break;
      default:
        print('📱 General notification handled');
    }
  }

  // ✅ Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    if (Platform.isAndroid) {
      print('🔔 Creating Android notification channels...');

      const List<AndroidNotificationChannel> channels = [
        AndroidNotificationChannel(
          'ironxpress_notifications',
          'IronXpress Notifications',
          description: 'General notifications for ironXpress',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'ironxpress_orders',
          'Order Updates',
          description: 'Notifications about order status',
          importance: Importance.high,
        ),
        AndroidNotificationChannel(
          'ironxpress_promotions',
          'Promotions',
          description: 'Special offers and promotions',
          importance: Importance.defaultImportance,
        ),
        AndroidNotificationChannel(
          'ironxpress_system',
          'System Notifications',
          description: 'Important system notifications',
          importance: Importance.high,
        ),
      ];

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        for (final channel in channels) {
          await androidPlugin.createNotificationChannel(channel);
        }
        print('✅ Android notification channels created');
      }
    }
  }

  // ✅ Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    print('📱 Local notification tapped: ${response.payload}');
    // Handle local notification tap if needed
  }

  // ✅ Subscribe to topics for targeted notifications
  Future<void> subscribeToTopics(String userId) async {
    if (!_hasPermission) {
      print('⚠️ No notification permissions, skipping topic subscription');
      return;
    }

    try {
      await _firebaseMessaging.subscribeToTopic('user_$userId');
      await _firebaseMessaging.subscribeToTopic('all_users');
      await _firebaseMessaging.subscribeToTopic('ironxpress_updates');
      print('✅ Subscribed to notification topics for user: $userId');
    } catch (e) {
      print('❌ Error subscribing to topics: $e');
    }
  }

  // ✅ Unsubscribe from topics
  Future<void> unsubscribeFromTopics(String userId) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic('user_$userId');
      await _firebaseMessaging.unsubscribeFromTopic('all_users');
      await _firebaseMessaging.unsubscribeFromTopic('ironxpress_updates');
      print('✅ Unsubscribed from notification topics for user: $userId');
    } catch (e) {
      print('❌ Error unsubscribing from topics: $e');
    }
  }

  // ✅ Send a test notification (for debugging)
  Future<void> sendTestNotification() async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'ironxpress_notifications',
        'IronXpress Notifications',
        channelDescription: 'Test notification',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        999,
        'IronXpress Test',
        'This is a test notification from IronXpress! 🔥',
        details,
      );

      print('✅ Test notification sent');
    } catch (e) {
      print('❌ Error sending test notification: $e');
    }
  }

  // ✅ Get notification history from database
  Future<List<Map<String, dynamic>>> getNotificationHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getting notification history: $e');
      return [];
    }
  }

  // ✅ Get unread notification count
  Future<int> getUnreadCount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 0;

    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      if (response is List) {
        return response.length;
      }
      return 0;
    } catch (e) {
      print('❌ Error getting unread count: $e');
      return 0;
    }
  }

  // ✅ Mark all notifications as read
  Future<void> markAllAsRead() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
      print('✅ All notifications marked as read');
    } catch (e) {
      print('❌ Error marking all as read: $e');
    }
  }

  // ✅ Clear old notifications
  Future<void> clearOldNotifications({int daysOld = 30}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

      await Supabase.instance.client
          .from('notifications')
          .delete()
          .eq('user_id', user.id)
          .lt('created_at', cutoffDate.toIso8601String());

      print('✅ Old notifications cleared');
    } catch (e) {
      print('❌ Error clearing old notifications: $e');
    }
  }

  // ✅ Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    final settings = await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  // ✅ Open notification settings
  Future<void> openNotificationSettings() async {
    try {
      await _firebaseMessaging.requestPermission();
    } catch (e) {
      print('❌ Error opening notification settings: $e');
    }
  }

  // ✅ Getters
  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;
  bool get hasPermission => _hasPermission;
}