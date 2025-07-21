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

  // ✅ Save FCM token to Supabase - IMPROVED with better error handling
  Future<void> _saveFCMTokenToDatabase() async {
    if (_fcmToken == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('⚠️ No authenticated user, skipping FCM token save');
      return;
    }

    try {
      // First, deactivate old tokens for this user on this device
      await Supabase.instance.client
          .from('user_fcm_tokens')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('device_type', Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'unknown');

      // Then insert/update the new token
      await Supabase.instance.client.from('user_fcm_tokens').upsert(
        {
          'user_id': user.id,
          'fcm_token': _fcmToken,
          'device_type': Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'unknown',
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,fcm_token',
      );

      print('✅ FCM token saved to database');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
      // Don't rethrow - this shouldn't break the app
    }
  }

  // 🆕 NEW: Send notification via your Edge Function
  Future<bool> sendNotificationViaEdgeFunction({
    String? userId,
    String? fcmToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
  }) async {
    try {
      print('📤 Sending notification via Edge Function...');

      final payload = {
        if (userId != null) 'user_id': userId,
        if (fcmToken != null) 'fcm_token': fcmToken,
        'title': title,
        'body': body,
        if (data != null) 'data': data,
        if (imageUrl != null) 'image': imageUrl,
      };

      final response = await Supabase.instance.client.functions.invoke(
        'send-push-notification',
        body: payload,
      );

      if (response.data != null && response.data['success'] == true) {
        print('✅ Notification sent successfully via Edge Function');
        print('📊 Response: ${response.data}');
        return true;
      } else {
        print('❌ Edge Function returned error: ${response.data}');
        return false;
      }
    } catch (e) {
      print('❌ Error sending notification via Edge Function: $e');
      return false;
    }
  }

  // 🆕 NEW: Send test notification via Edge Function
  Future<void> sendTestNotificationViaEdgeFunction() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('⚠️ No authenticated user for test notification');
      return;
    }

    await sendNotificationViaEdgeFunction(
      userId: user.id,
      title: 'Test from IronXpress! 🧽',
      body: 'Your Edge Function is working perfectly! This is a test notification.',
      data: {
        'type': 'test',
        'timestamp': DateTime.now().toIso8601String(),
        'action': 'open_app',
      },
    );
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

  // ✅ Handle foreground messages - IMPROVED with better error handling
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground message received: ${message.messageId}');
    print('📱 Title: ${message.notification?.title}');
    print('📱 Body: ${message.notification?.body}');
    print('📱 Data: ${message.data}');

    try {
      // Store in database (don't let this fail the notification display)
      await _storeNotificationInDatabase(message).catchError((e) {
        print('⚠️ Failed to store notification in database: $e');
      });

      // Show local notification
      await _showLocalNotification(message);
    } catch (e) {
      print('❌ Error handling foreground message: $e');
    }
  }

  // ✅ Handle notification tap
  Future<void> _handleNotificationTap(RemoteMessage? message) async {
    if (message == null) return;

    print('📱 Notification tapped: ${message.messageId}');

    try {
      // Mark as read in database
      await _markNotificationAsRead(message.messageId);

      // Handle navigation based on notification data
      _handleNotificationNavigation(message.data);
    } catch (e) {
      print('❌ Error handling notification tap: $e');
    }
  }

  // ✅ Show local notification for foreground messages - FIXED
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      // Determine channel based on notification type
      final notificationType = message.data['type'] ?? 'general';
      final channelId = _getChannelIdForType(notificationType);

      // Get appropriate channel name based on type
      final channelName = _getChannelNameForType(notificationType);
      final channelDescription = _getChannelDescriptionForType(notificationType);

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId, // Use the dynamic channel ID here
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        showWhen: true,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(''), // Better for long text
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'ironxpress_notification',
      );

      final NotificationDetails details = NotificationDetails(
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

  // 🆕 NEW: Get channel ID based on notification type
  String _getChannelIdForType(String type) {
    switch (type) {
      case 'order_update':
        return 'ironxpress_orders';
      case 'promotion':
        return 'ironxpress_promotions';
      case 'system':
        return 'ironxpress_system';
      default:
        return 'ironxpress_notifications';
    }
  }

  // 🆕 NEW: Get channel name based on notification type
  String _getChannelNameForType(String type) {
    switch (type) {
      case 'order_update':
        return 'Order Updates';
      case 'promotion':
        return 'Promotions & Offers';
      case 'system':
        return 'System Notifications';
      default:
        return 'IronXpress Notifications';
    }
  }

  // 🆕 NEW: Get channel description based on notification type
  String _getChannelDescriptionForType(String type) {
    switch (type) {
      case 'order_update':
        return 'Notifications about order status changes';
      case 'promotion':
        return 'Special offers, discounts and promotions';
      case 'system':
        return 'Important system notifications and updates';
      default:
        return 'General notifications for IronXpress';
    }
  }

  // ✅ Store notification in Supabase database - IMPROVED
  Future<void> _storeNotificationInDatabase(RemoteMessage message) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': user.id,
        'title': message.notification?.title ?? 'IronXpress',
        'body': message.notification?.body ?? '',
        'data': message.data.isNotEmpty ? message.data : null,
        'type': message.data['type'] ?? 'general',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      print('✅ Notification stored in database');
    } catch (e) {
      print('❌ Error storing notification: $e');
      // Don't rethrow - this shouldn't break notification display
    }
  }

  // ✅ Mark notification as read - IMPROVED
  Future<void> _markNotificationAsRead(String? messageId) async {
    if (messageId == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('notifications')
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', user.id)
          .eq('is_read', false); // Only update unread notifications

      print('✅ Notification marked as read');
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  // ✅ Handle notification navigation - ENHANCED
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] ?? 'general';
    final action = data['action'] ?? '';

    print('🔄 Handling navigation for type: $type, action: $action');

    switch (type) {
      case 'order_update':
        final orderId = data['order_id'];
        if (orderId != null) {
          print('🔄 Navigate to order: $orderId');
          // TODO: Navigate to order details screen
          // NavigationService.instance.navigateToOrder(orderId);
        }
        break;
      case 'promotion':
        final couponCode = data['coupon_code'];
        print('🎁 Navigate to promotions${couponCode != null ? ' with code: $couponCode' : ''}');
        // TODO: Navigate to promotions screen
        // NavigationService.instance.navigateToPromotions(couponCode);
        break;
      case 'system':
        print('⚙️ Navigate to system notifications');
        // TODO: Navigate to notifications screen
        // NavigationService.instance.navigateToNotifications();
        break;
      case 'test':
        print('🧪 Test notification - no navigation needed');
        break;
      default:
        print('📱 General notification handled');
    // TODO: Navigate to default screen (maybe notifications list)
    // NavigationService.instance.navigateToNotifications();
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
          description: 'General notifications for IronXpress',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'ironxpress_orders',
          'Order Updates',
          description: 'Notifications about order status changes',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'ironxpress_promotions',
          'Promotions & Offers',
          description: 'Special offers, discounts and promotions',
          importance: Importance.defaultImportance,
          enableVibration: false,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'ironxpress_system',
          'System Notifications',
          description: 'Important system notifications and updates',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
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

    // Mark the notification as read if we have the payload (message ID)
    if (response.payload != null) {
      _markNotificationAsRead(response.payload);
    }
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

  // ✅ Send a test notification (local only)
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
        'IronXpress Local Test',
        'This is a local test notification! 🧪',
        details,
      );

      print('✅ Local test notification sent');
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
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
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