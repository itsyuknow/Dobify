

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'; // for Color
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_settings/app_settings.dart';

import 'email_service.dart';

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

      // Token
      await _getFCMToken();

      // Handlers
      _setupMessageHandlers();

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

  Future<void> _getFCMToken() async {
    try {
      if (kIsWeb) return;
      _fcmToken = await FirebaseMessaging.instance.getToken();
      print('📱 FCM Token: $_fcmToken');
      await _storeFCMToken();
    } catch (e) {
      print('❌ Error getting FCM token: $e');
    }
  }

  Future<void> _storeFCMToken() async {
    if (_fcmToken == null) return;
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('user_devices').upsert({
          'user_id': user.id,
          'device_token': _fcmToken,
          'platform': 'android',
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('❌ Error storing FCM token: $e');
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📱 Foreground message: ${message.messageId}');
    await _showLocalNotification(message);
    await _storeNotificationInDatabase(message);
  }

  Future<void> _handleMessageTap(RemoteMessage message) async {
    print('📱 Message tapped: ${message.messageId}');
    final data = message.data;
    if (data['type'] == 'order_update' && data['order_id'] != null) {
      print('🧭 Navigate to order: ${data['order_id']}');
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

    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

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

  // ===========================================================================
  // ✅ NEW: Are notifications enabled on this device?
  // Uses Android-specific API when available; falls back to FCM settings on iOS.
  // ===========================================================================
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    try {
      // Android path (plugin exposes native check)
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final enabled = await androidPlugin.areNotificationsEnabled();
        // Some plugin versions return bool?, default to true if null
        return enabled ?? true;
      }

      // iOS/macOS path — query FCM permission state
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      final allowed = status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
      return allowed;
    } catch (e) {
      print('⚠️ areNotificationsEnabled() failed: $e');
      // Be permissive on error to avoid blocking UX
      return true;
    }
  }


  Future<void> openNotificationSettings() async {
    if (kIsWeb) return;
    try {
      // Try the dedicated notifications settings screen where supported
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (e) {
      print('⚠️ openNotificationSettings(notification) failed, trying generic app settings: $e');
      try {
        // Fallback: open the app's general settings page
        await AppSettings.openAppSettings();
      } catch (e2) {
        print('⚠️ openAppSettings() failed, falling back to permission prompt: $e2');
        // Ultimate fallback (mainly iOS): re-request permission prompt
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }
    }
  }


  // --- PUBLIC API: Combined send (DB + push + email) -------------------------

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

      await _storeOrderNotification(
        userId: userId,
        orderId: orderId,
        title: title,
        body: body,
        type: type,
        orderData: orderData,
      );

      await _sendPushNotification(
        userId: userId,
        title: title,
        body: body,
        data: {
          'type': type,
          'order_id': orderId,
          'status': status,
          ...?orderData,
        },
      );

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
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('❌ Error storing order notification: $e');
    }
  }

  Future<void> _sendPushNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final devices = await supabase
          .from('user_devices')
          .select('device_token')
          .eq('user_id', userId)
          .eq('is_active', true);

      if (devices.isEmpty) {
        print('⚠️ No active devices found for user $userId');
        return;
      }

      for (final device in devices) {
        await supabase.functions.invoke('send-push', body: {
          'token': device['device_token'],
          'title': title,
          'body': body,
          'data': data,
        });
      }
    } catch (e) {
      print('❌ Error sending push notification: $e');
    }
  }

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

  // ---------------------------------------------------------------------------
  // ✅ Used by NotificationHandler to trigger a phone popup/push via Edge Func
  // ---------------------------------------------------------------------------
  Future<bool> sendNotificationViaEdgeFunction({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      // Fetch active device tokens for the user
      final devices = await supabase
          .from('user_devices')
          .select('device_token')
          .eq('user_id', userId)
          .eq('is_active', true);

      if (devices.isEmpty) {
        print('⚠️ No active devices for user $userId');
        return false;
      }

      int sent = 0;
      for (final device in devices) {
        final token = (device['device_token'] ?? '').toString().trim();
        if (token.isEmpty) continue;

        await supabase.functions.invoke(
          'send-push', // rename if your Edge Function uses a different name
          body: <String, dynamic>{
            'token': token,
            'title': title,
            'body': body,
            'data': data,
          },
        );
        sent++;
      }

      print('✅ Edge function push enqueued to $sent device(s) for $userId');
      return sent > 0;
    } catch (e) {
      print('❌ Error in sendNotificationViaEdgeFunction: $e');
      return false;
    }
  }
}
