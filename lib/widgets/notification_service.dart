import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_settings/app_settings.dart';

import 'email_service.dart'; // Keep email service unchanged

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  final supabase = Supabase.instance.client;

  bool _isInitialized = false;
  String? _fcmToken;

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        print('📱 Web platform — skipping local notifications setup');
        return;
      }

      // Initialize local notifications
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create Android channel
      await _createNotificationChannel();

      // Ask for permissions
      await _requestPermissions();

      // Get and store FCM token
      await _initializeFCMToken();

      // Setup message handlers
      _setupMessageHandlers();

      // Listen for token refresh
      _listenForTokenRefresh();

      _isInitialized = true;
      print('✅ Notification service initialized successfully');
    } catch (e) {
      print('❌ Error initializing notifications: $e');
      _isInitialized = false;
    }
  }

  Future<void> _createNotificationChannel() async {
    if (kIsWeb) return;

    const androidChannel = AndroidNotificationChannel(
      'ironxpress_orders',
      'Order Updates',
      description: 'Notifications for order status updates',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('⚠️ User denied notification permissions');
    } else {
      print('✅ Notification permissions granted (${settings.authorizationStatus})');
    }
  }

  // 🔥 IMPROVED FCM TOKEN MANAGEMENT
  Future<void> _initializeFCMToken() async {
    try {
      if (kIsWeb) return;

      _fcmToken = await FirebaseMessaging.instance.getToken();
      print('📱 FCM Token obtained: $_fcmToken');

      if (_fcmToken != null) {
        await _storeFCMToken();
      }
    } catch (e) {
      print('❌ Error getting FCM token: $e');
    }
  }

  Future<void> _storeFCMToken() async {
    if (_fcmToken == null) {
      print('⚠️ No FCM token to store');
      return;
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        print('⚠️ No authenticated user to store token for');
        return;
      }

      await supabase.from('user_devices').upsert({
        'user_id': user.id,
        'device_token': _fcmToken,
        'platform': 'android', // You can detect platform if needed
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('✅ FCM token stored successfully');
    } catch (e) {
      print('❌ Error storing FCM token: $e');
    }
  }

  void _listenForTokenRefresh() {
    if (kIsWeb) return;

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print('🔄 FCM token refreshed: $newToken');
      _fcmToken = newToken;
      await _storeFCMToken();
    });
  }

  void _setupMessageHandlers() {
    if (kIsWeb) return;

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground message received: ${message.messageId}');
    print('📱 Title: ${message.notification?.title}');
    print('📱 Body: ${message.notification?.body}');
    print('📱 Data: ${message.data}');

    await _showLocalNotification(message);
    await _storeNotificationInDatabase(message);
  }

  Future<void> _handleMessageTap(RemoteMessage message) async {
    print('📱 Message tapped: ${message.messageId}');
    final data = message.data;

    if (data['type'] == 'order_update' && data['order_id'] != null) {
      print('🧭 Navigate to order: ${data['order_id']}');
      // Add navigation logic here if needed
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'ironxpress_orders',
      'Order Updates',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF6366F1),
      icon: '@mipmap/ic_launcher',
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'IronXpress',
      message.notification?.body ?? '',
      details,
      payload: message.data.toString(),
    );
  }

  Future<void> _storeNotificationInDatabase(RemoteMessage message) async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'message_id': message.messageId,
          'title': message.notification?.title ?? 'IronXpress',
          'body': message.notification?.body ?? '',
          'data': message.data,
          'type': message.data['type'] ?? 'general',
          'is_read': false,
          'is_sent': true, // Mark as sent since it came from FCM
          'sent_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('❌ Error storing notification: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('📱 Local notification tapped: ${response.payload}');
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;

    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final enabled = await androidPlugin.areNotificationsEnabled();
        return enabled ?? true;
      }

      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (e) {
      print('⚠️ areNotificationsEnabled() failed: $e');
      return true;
    }
  }

  Future<void> openNotificationSettings() async {
    if (kIsWeb) return;

    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (e) {
      print('⚠️ openNotificationSettings failed, trying generic: $e');
      try {
        await AppSettings.openAppSettings();
      } catch (e2) {
        print('⚠️ openAppSettings failed, falling back to permission prompt: $e2');
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }
    }
  }

  // 🔥 IMPROVED PUSH NOTIFICATION SENDING
  Future<bool> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      print('📤 Sending push notification to user: $userId');
      print('📤 Title: $title');
      print('📤 Body: $body');

      // Get all active device tokens for the user
      final devices = await supabase
          .from('user_devices')
          .select('device_token, platform')
          .eq('user_id', userId)
          .eq('is_active', true);

      if (devices.isEmpty) {
        print('⚠️ No active devices found for user $userId');
        return false;
      }

      print('📱 Found ${devices.length} device(s) for user $userId');

      bool anySuccess = false;

      for (final device in devices) {
        final token = device['device_token'];
        if (token == null || token.toString().trim().isEmpty) {
          print('⚠️ Empty token for device, skipping');
          continue;
        }

        try {
          final response = await supabase.functions.invoke(
            'send-push-notification',
            body: {
              'token': token,
              'notification': {
                'title': title,
                'body': body,
              },
              'data': data,
              'android': {
                'channel_id': 'ironxpress_orders',
                'priority': 'high',
              },
              'apns': {
                'payload': {
                  'aps': {
                    'alert': {
                      'title': title,
                      'body': body,
                    },
                    'badge': 1,
                    'sound': 'default',
                  },
                },
              },
            },
          );

          if (response.data != null && response.data['success'] == true) {
            print('✅ Push sent successfully to device with token: ${token.toString().substring(0, 20)}...');
            anySuccess = true;
          } else {
            print('❌ Push failed for device: ${response.data}');
          }
        } catch (e) {
          print('❌ Error sending to device token ${token.toString().substring(0, 20)}...: $e');
        }
      }

      return anySuccess;
    } catch (e) {
      print('❌ Error in sendPushNotification: $e');
      return false;
    }
  }

  // 🔥 COMPREHENSIVE ORDER NOTIFICATION (Push + Email + DB)
  Future<void> sendOrderNotification({
    required String userId,
    required String orderId,
    required String title,
    required String body,
    required String type,
    required String status,
    Map<String, dynamic>? orderData,
    bool sendEmail = true,
  }) async {
    try {
      print('📤 Sending comprehensive notification for order $orderId');

      // 1. Store in database
      await _storeOrderNotification(
        userId: userId,
        orderId: orderId,
        title: title,
        body: body,
        type: type,
        orderData: orderData,
      );

      // 2. Send push notification
      final pushData = {
        'type': type,
        'order_id': orderId,
        'status': status,
        ...?orderData,
      };

      final pushSent = await sendPushNotification(
        userId: userId,
        title: title,
        body: body,
        data: pushData,
      );

      if (pushSent) {
        // Mark as sent in database
        await supabase.from('notifications')
            .update({
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
        })
            .eq('user_id', userId)
            .eq('type', type)
            .order('created_at', ascending: false)
            .limit(1);
      }

      // 3. Send email notification (keep your existing email logic)
      if (sendEmail) {
        await _sendEmailNotification(
          userId: userId,
          orderId: orderId,
          status: status,
          type: type,
          orderData: orderData,
        );
      }

      print('✅ Comprehensive notification sent for order $orderId');
    } catch (e) {
      print('❌ Error sending comprehensive notification: $e');
    }
  }

  Future<void> _storeOrderNotification({
    required String userId,
    required String orderId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'data': {
          'order_id': orderId,
          'type': type,
          ...?orderData,
        },
        'type': type,
        'is_read': false,
        'is_sent': false, // Will be updated after push is sent
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Notification stored in database');
    } catch (e) {
      print('❌ Error storing order notification: $e');
    }
  }

  // Keep your existing email notification method unchanged
  Future<void> _sendEmailNotification({
    required String userId,
    required String orderId,
    required String status,
    required String type,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      final preferences = await _getUserEmailPreferences(userId);
      if (!preferences['enabled']!) {
        print('📧 Email notifications disabled for user $userId');
        return;
      }

      final userResponse = await supabase
          .from('profiles')
          .select('full_name, email')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse == null) {
        print('❌ User profile not found for $userId');
        return;
      }

      final userName = userResponse['full_name'] ?? 'Valued Customer';
      final userEmail = userResponse['email'];

      if (userEmail == null || userEmail.isEmpty) {
        print('❌ User email not found for $userId');
        return;
      }

      String emailType = 'order_status_update';
      if (type == 'order_placed' || type == 'order_confirmation') {
        emailType = 'order_placed';
      } else if (status == 'delivered' || status == 'completed') {
        emailType = 'order_delivered';
      }

      if (!preferences[emailType]!) {
        print('📧 Email type $emailType disabled for user $userId');
        return;
      }

      final emailService = EmailService();
      final success = await emailService.sendOrderEmail(
        userEmail: userEmail,
        userName: userName,
        orderId: orderId,
        status: status,
        emailType: emailType,
        orderData: orderData,
      );

      if (success) {
        print('📧 Email sent successfully to $userEmail');
      } else {
        print('❌ Failed to send email to $userEmail');
      }
    } catch (e) {
      print('❌ Error sending email notification: $e');
    }
  }

  Future<Map<String, bool>> _getUserEmailPreferences(String userId) async {
    try {
      final response = await supabase
          .from('user_notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        return {
          'enabled': true,
          'order_placed': true,
          'order_status_update': true,
          'order_delivered': true,
        };
      }

      return {
        'enabled': response['email_notifications_enabled'] ?? true,
        'order_placed': response['order_placed_email'] ?? true,
        'order_status_update': response['order_status_email'] ?? true,
        'order_delivered': response['order_delivered_email'] ?? true,
      };
    } catch (e) {
      print('❌ Error getting email preferences: $e');
      return {
        'enabled': true,
        'order_placed': true,
        'order_status_update': true,
        'order_delivered': true,
      };
    }
  }

  // Topic subscription methods
  Future<void> subscribeToTopics(String userId) async {
    if (!_isInitialized || kIsWeb) return;

    try {
      await FirebaseMessaging.instance.subscribeToTopic('user_$userId');
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      print('✅ Subscribed to topics for user $userId');
    } catch (e) {
      print('❌ Error subscribing to topics: $e');
    }
  }

  Future<void> unsubscribeFromTopics(String userId) async {
    if (!_isInitialized || kIsWeb) return;

    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('user_$userId');
      await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
      print('✅ Unsubscribed from topics for user $userId');
    } catch (e) {
      print('❌ Error unsubscribing from topics: $e');
    }
  }

  // Convenience methods for different order states
  Future<void> sendOrderPlacedNotification({
    required String userId,
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    await sendOrderNotification(
      userId: userId,
      orderId: orderId,
      title: 'Order Placed Successfully! 🎉',
      body: 'Your order #$orderId has been placed and will be processed soon.',
      type: 'order_placed',
      status: 'confirmed',
      orderData: orderData,
      sendEmail: true,
    );
  }

  Future<void> sendOrderStatusUpdateNotification({
    required String userId,
    required String orderId,
    required String oldStatus,
    required String newStatus,
    required Map<String, dynamic> orderData,
  }) async {
    final title = _getStatusUpdateTitle(newStatus);
    final body = _getStatusUpdateBody(orderId, newStatus);

    await sendOrderNotification(
      userId: userId,
      orderId: orderId,
      title: title,
      body: body,
      type: 'order_status_update',
      status: newStatus,
      orderData: orderData,
      sendEmail: true,
    );
  }

  String _getStatusUpdateTitle(String status) {
    switch (status) {
      case 'accepted':
        return 'Order Accepted ✅';
      case 'assigned':
        return 'Rider Assigned 🚚';
      case 'working_in_progress':
      case 'work_in_progress':
        return 'Work in Progress 🧽';
      case 'ready_to_dispatch':
        return 'Ready for Delivery 📦';
      case 'in_transit':
        return 'Out for Delivery 🚛';
      case 'delivered':
        return 'Order Delivered ✅';
      case 'completed':
        return 'Order Completed 🎉';
      case 'cancelled':
        return 'Order Cancelled ❌';
      default:
        return 'Order Update 📦';
    }
  }

  String _getStatusUpdateBody(String orderId, String status) {
    switch (status) {
      case 'accepted':
        return 'Great news! Your order #$orderId has been accepted and is being prepared.';
      case 'assigned':
        return 'A delivery partner has been assigned to your order #$orderId. They will contact you soon!';
      case 'working_in_progress':
      case 'work_in_progress':
        return 'Our team is currently working on your order #$orderId with care and attention.';
      case 'ready_to_dispatch':
        return 'Your order #$orderId is ready and will be dispatched soon.';
      case 'in_transit':
        return 'Your order #$orderId is on the way to your address.';
      case 'delivered':
        return 'Your laundry has been delivered. Thank you for choosing IronXpress!';
      case 'completed':
        return 'Your order #$orderId has been completed successfully. Thank you!';
      case 'cancelled':
        return 'Your order #$orderId has been cancelled. Contact support if you have questions.';
      default:
        return 'Your order #$orderId status has been updated to: ${status.replaceAll('_', ' ')}';
    }
  }

  // 🔥 LEGACY COMPATIBILITY - Keep this for NotificationHandler
  Future<bool> sendNotificationViaEdgeFunction({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    return await sendPushNotification(
      userId: userId,
      title: title,
      body: body,
      data: data,
    );
  }

  // 🔥 REFRESH TOKEN METHOD - Call this when user logs in
  Future<void> refreshFCMToken() async {
    if (kIsWeb || !_isInitialized) return;

    try {
      await FirebaseMessaging.instance.deleteToken();
      await _initializeFCMToken();
      print('🔄 FCM token refreshed');
    } catch (e) {
      print('❌ Error refreshing FCM token: $e');
    }
  }

  // 🔥 CLEANUP METHOD - Call this when user logs out
  Future<void> cleanup() async {
    if (kIsWeb) return;

    try {
      final user = supabase.auth.currentUser;
      if (user != null && _fcmToken != null) {
        // Mark current device as inactive
        await supabase.from('user_devices')
            .update({'is_active': false})
            .eq('user_id', user.id)
            .eq('device_token', _fcmToken!);

        await unsubscribeFromTopics(user.id);
      }

      _fcmToken = null;
      print('🧹 Notification service cleaned up');
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }
}