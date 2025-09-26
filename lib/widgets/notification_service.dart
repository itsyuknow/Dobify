// lib/widgets/notification_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final supabase = Supabase.instance.client;

  bool _isInitialized = false;
  String? _fcmToken;

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    try {
      if (kIsWeb) return;

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

      await _localNotifications.initialize(initSettings, onDidReceiveNotificationResponse: _onNotificationTapped);
      await _createNotificationChannel();
      await _requestPermissions();
      await _initializeFCMToken();
      _setupMessageHandlers();
      _listenForTokenRefresh();

      _isInitialized = true;
      debugPrint('✅ Notification service initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing notifications: $e');
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
    await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('⚠️ User denied notification permissions');
    }
  }

  Future<void> _initializeFCMToken() async {
    try {
      if (kIsWeb) return;
      _fcmToken = await FirebaseMessaging.instance.getToken();
      if (_fcmToken != null) await _storeFCMToken();
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
    }
  }

  Future<void> _storeFCMToken() async {
    if (_fcmToken == null) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Upsert and de-dupe by (user_id, device_token)
      await supabase.from('user_devices').upsert({
        'user_id': user.id,
        'device_token': _fcmToken,
        'platform': 'android',
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_token');

    } catch (e) {
      debugPrint('❌ Error storing FCM token: $e');
    }
  }

  void _listenForTokenRefresh() {
    if (kIsWeb) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
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
    await _showLocalNotification(message);
    await _storeNotificationInDatabase(message);
  }

  Future<void> _handleMessageTap(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] == 'order_update' && data['order_id'] != null) {
      // TODO: Navigate to order screen
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
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
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
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('❌ Error storing notification: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('📱 Local notification tapped: ${response.payload}');
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final enabled = await androidPlugin.areNotificationsEnabled();
        return enabled ?? true;
      }
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      return status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
    } catch (_) {
      return true;
    }
  }

  Future<void> openNotificationSettings() async {
    if (kIsWeb) return;
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      try {
        await AppSettings.openAppSettings();
      } catch (_) {
        await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      }
    }
  }

  // ---------------- PUSH SENDER (dedupe + collapse/group) ----------------
  Future<bool> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final devices = await supabase
          .from('user_devices')
          .select('device_token, platform')
          .eq('user_id', userId)
          .eq('is_active', true);

      if (devices.isEmpty) return false;

      // de-dupe tokens
      final tokens = <String>{};
      for (final d in devices) {
        final t = (d['device_token'] ?? '').toString().trim();
        if (t.isNotEmpty) tokens.add(t);
      }
      if (tokens.isEmpty) return false;

      // collapse/group keys
      final collapseKey = data['order_id'] != null
          ? 'order_${data['order_id']}_${data['status'] ?? ''}'
          : 'general';
      final threadId = data['order_id']?.toString() ?? 'general';

      bool anySuccess = false;

      for (final token in tokens) {
        try {
          final resp = await supabase.functions.invoke(
            'send-push-notification',
            body: {
              'token': token,
              'notification': {'title': title, 'body': body},
              'data': data,
              'android': {
                'channel_id': 'ironxpress_orders',
                'priority': 'high',
                'collapse_key': collapseKey, // server maps to v1 collapseKey
              },
              'apns': {
                'payload': {
                  'aps': {
                    'alert': {'title': title, 'body': body},
                    'badge': 1,
                    'sound': 'default',
                    'thread-id': threadId, // iOS grouping
                  },
                },
              },
            },
          );

          if (resp.data != null && resp.data['success'] == true) {
            anySuccess = true;
          } else {
            debugPrint('❌ Push failed for token ${token.substring(0, 16)}… : ${resp.data}');
          }
        } catch (e) {
          debugPrint('❌ Error sending to token ${token.substring(0, 16)}… : $e');
        }
      }

      return anySuccess;
    } catch (e) {
      debugPrint('❌ Error in sendPushNotification: $e');
      return false;
    }
  }

  // 🔥 COMPREHENSIVE ORDER NOTIFICATION (DB + Email). Push is handled by realtime listener.
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
      // 1) Insert into DB; listener will pick it up and send push exactly once.
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'data': {
          'order_id': orderId,
          'type': type,
          'status': status,
          ...?orderData,
        },
        'type': type,
        'is_read': false,
        'is_sent': false, // will be set true by listener after push succeeds
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2) Optional email
      if (sendEmail) {
        await _sendEmailNotification(
          userId: userId,
          orderId: orderId,
          status: status,
          type: type,
          orderData: orderData,
        );
      }
    } catch (e) {
      print('❌ Error sending comprehensive notification: $e');
    }
  }


  // ---------------- remaining helpers (unchanged except trimmed logs) ----------------
  Future<void> _sendEmailNotification({
    required String userId,
    required String orderId,
    required String status,
    required String type,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      final preferences = await _getUserEmailPreferences(userId);
      if (!preferences['enabled']!) return;

      final userResponse = await supabase.from('profiles').select('full_name, email').eq('id', userId).maybeSingle();
      if (userResponse == null) return;

      final userName = userResponse['full_name'] ?? 'Valued Customer';
      final userEmail = userResponse['email'];
      if (userEmail == null || userEmail.isEmpty) return;

      String emailType = 'order_status_update';
      if (type == 'order_placed' || type == 'order_confirmation') emailType = 'order_placed';
      else if (status == 'delivered' || status == 'completed') emailType = 'order_delivered';

      if (!preferences[emailType]!) return;

      final emailService = EmailService();
      await emailService.sendOrderEmail(
        userEmail: userEmail,
        userName: userName,
        orderId: orderId,
        status: status,
        emailType: emailType,
        orderData: orderData,
      );
    } catch (_) {}
  }

  Future<Map<String, bool>> _getUserEmailPreferences(String userId) async {
    try {
      final r = await supabase.from('user_notification_preferences').select().eq('user_id', userId).maybeSingle();
      if (r == null) {
        return {'enabled': true, 'order_placed': true, 'order_status_update': true, 'order_delivered': true};
      }
      return {
        'enabled': r['email_notifications_enabled'] ?? true,
        'order_placed': r['order_placed_email'] ?? true,
        'order_status_update': r['order_status_email'] ?? true,
        'order_delivered': r['order_delivered_email'] ?? true,
      };
    } catch (_) {
      return {'enabled': true, 'order_placed': true, 'order_status_update': true, 'order_delivered': true};
    }
  }

  Future<void> subscribeToTopics(String userId) async {
    if (!_isInitialized || kIsWeb) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic('user_$userId');
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
    } catch (_) {}
  }

  Future<void> unsubscribeFromTopics(String userId) async {
    if (!_isInitialized || kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('user_$userId');
      await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
    } catch (_) {}
  }

  Future<void> refreshFCMToken() async {
    if (kIsWeb || !_isInitialized) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
      await _initializeFCMToken();
    } catch (_) {}
  }

  Future<void> cleanup() async {
    if (kIsWeb) return;
    try {
      final user = supabase.auth.currentUser;
      if (user != null && _fcmToken != null) {
        await supabase.from('user_devices')
            .update({'is_active': false})
            .eq('user_id', user.id)
            .eq('device_token', _fcmToken!);
        await unsubscribeFromTopics(user.id);
      }
      _fcmToken = null;
    } catch (_) {}
  }
}
