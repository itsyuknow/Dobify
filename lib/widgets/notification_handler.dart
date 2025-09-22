// lib/widgets/notification_handler.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class NotificationHandler {
  static final NotificationHandler _instance = NotificationHandler._internal();
  factory NotificationHandler() => _instance;
  NotificationHandler._internal();

  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;
  bool _isListening = false;

  void startListeningToNotifications() {
    if (_isListening) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      print('ℹ️ No logged-in user; skipping notification listener.');
      return;
    }

    print('🔔 Starting notification listener for user: ${user.id}');

    _notificationSubscription = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen(
          (rows) async {
        if (rows.isEmpty) return;
        print('📡 Real-time notifications batch: ${rows.length} item(s)');

        for (final notif in rows) {
          _handleRealtimeNotification(notif);
        }
      },
      onError: (e, st) {
        print('❌ Realtime notifications stream error: $e');
      },
      cancelOnError: false,
    );

    _isListening = true;
    print('✅ Notification listener started');
  }

  void _handleRealtimeNotification(Map<String, dynamic> notification) {
    final title = (notification['title'] ?? 'IronXpress').toString();
    print('📱 Processing notification: $title');

    final bool isRead = (notification['is_read'] ?? false) == true;
    final bool isSent = (notification['is_sent'] ?? false) == true;

    final createdAtRaw = notification['created_at'];
    DateTime createdAt = DateTime.now();
    if (createdAtRaw is String) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    }

    final now = DateTime.now();
    final bool isRecent = now.difference(createdAt).inMinutes < 5;

    // Only send push for unread, unsent, and recent notifications
    if (!isRead && !isSent && isRecent) {
      _sendPushNotification(notification);
    }
  }

  Future<void> _sendPushNotification(Map<String, dynamic> notification) async {
    print('🔔 Sending push notification for: ${notification['title']}');

    try {
      final String userId = (notification['user_id'] ?? '').toString();
      if (userId.isEmpty) {
        print('⚠️ Missing user_id in notification; skipping push.');
        return;
      }

      final String title = (notification['title'] ?? 'IronXpress').toString();
      final String body = (notification['body'] ?? 'You have a new notification').toString();
      final String type = (notification['type'] ?? 'general').toString();
      final Map<String, dynamic> rawData = _coerceToMap(notification['data']) ?? <String, dynamic>{};

      final bool success = await NotificationService().sendPushNotification(
        userId: userId,
        title: title,
        body: body,
        data: <String, dynamic>{
          'notification_id': notification['id'],
          'type': type,
          ...rawData,
        },
      );

      if (success) {
        print('✅ Push notification sent successfully');
        await _markNotificationAsSent(notification['id']);
      } else {
        print('❌ Failed to send push notification');
      }
    } catch (e) {
      print('❌ Error sending push notification: $e');
    }
  }

  Future<void> _markNotificationAsSent(dynamic notificationId) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({
        'is_sent': true,
        'sent_at': DateTime.now().toIso8601String(),
      })
          .eq('id', notificationId);

      print('✅ Notification marked as sent');
    } catch (e) {
      print('❌ Error marking notification as sent: $e');
    }
  }

  // 🔥 IMPROVED: Direct push notification methods using the fixed service
  static Future<void> sendNotificationWithPopup({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    try {
      print('📤 Sending notification with push: $title');

      // 1) Insert into DB for in-app display
      final inserted = await Supabase.instance.client
          .from('notifications')
          .insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? <String, dynamic>{},
        'is_read': false,
        'is_sent': false,
        'created_at': DateTime.now().toIso8601String(),
      })
          .select()
          .single();

      print('✅ Notification saved to database (id: ${inserted['id']})');

      // 2) Send push notification using the improved service
      final pushSuccess = await NotificationService().sendPushNotification(
        userId: userId,
        title: title,
        body: body,
        data: <String, dynamic>{
          'notification_id': inserted['id'],
          'type': type,
          if (data != null) ...data,
        },
      );

      // 3) Mark as sent if push succeeded
      if (pushSuccess) {
        await Supabase.instance.client
            .from('notifications')
            .update({
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
        })
            .eq('id', inserted['id']);
        print('✅ Notification with push sent successfully');
      } else {
        print('⚠️ Notification saved but push failed');
      }
    } catch (e) {
      print('❌ Error sending notification with push: $e');
    }
  }

  // Convenience methods for specific notification types
  static Future<void> sendOrderConfirmation({
    required String userId,
    required String orderId,
  }) async {
    await sendNotificationWithPopup(
      userId: userId,
      title: 'Order Confirmed! 🎉',
      body: 'Your order #$orderId has been confirmed and will be picked up soon.',
      type: 'order_confirmation',
      data: {
        'order_id': orderId,
        'action': 'view_order',
      },
    );
  }

  static Future<void> sendOrderStatusUpdate({
    required String userId,
    required String orderId,
    required String status,
  }) async {
    String title;
    String body;

    switch (status.toLowerCase()) {
      case 'picked_up':
        title = 'Order Picked Up 📦';
        body = 'Your laundry has been picked up and is being processed.';
        break;
      case 'in_progress':
      case 'work_in_progress':
      case 'working_in_progress':
        title = 'Order In Progress 🧽';
        body = 'Your laundry is being cleaned with care.';
        break;
      case 'ready_for_delivery':
      case 'ready_to_dispatch':
        title = 'Ready for Delivery 🚚';
        body = 'Your fresh laundry is ready and will be delivered soon!';
        break;
      case 'in_transit':
        title = 'Out for Delivery 🚛';
        body = 'Your order #$orderId is on the way to your address.';
        break;
      case 'delivered':
        title = 'Order Delivered ✅';
        body = 'Your laundry has been delivered. Thank you for choosing IronXpress!';
        break;
      case 'completed':
        title = 'Order Completed 🎉';
        body = 'Your order #$orderId has been completed successfully. Thank you!';
        break;
      case 'cancelled':
        title = 'Order Cancelled ❌';
        body = 'Your order #$orderId has been cancelled. Contact support if you have questions.';
        break;
      case 'accepted':
        title = 'Order Accepted ✅';
        body = 'Great news! Your order #$orderId has been accepted and is being prepared.';
        break;
      case 'assigned':
        title = 'Rider Assigned 🚚';
        body = 'A delivery partner has been assigned to your order #$orderId. They will contact you soon!';
        break;
      default:
        title = 'Order Update 📦';
        body = 'Your order #$orderId status has been updated to: ${status.replaceAll('_', ' ')}';
    }

    await sendNotificationWithPopup(
      userId: userId,
      title: title,
      body: body,
      type: 'order_update',
      data: {
        'order_id': orderId,
        'status': status,
        'action': 'view_order',
      },
    );
  }

  static Future<void> sendPromotion({
    required String userId,
    required String promoCode,
    required int discountPercent,
  }) async {
    await sendNotificationWithPopup(
      userId: userId,
      title: 'Special Offer! 🎁',
      body: 'Get $discountPercent% off your next order with code $promoCode!',
      type: 'promotion',
      data: {
        'promo_code': promoCode,
        'discount_percent': discountPercent,
        'action': 'view_promotions',
      },
    );
  }

  void stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _isListening = false;
    print('🔕 Notification listener stopped');
  }

  Map<String, dynamic>? _coerceToMap(dynamic raw) {
    try {
      if (raw == null) return <String, dynamic>{};
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

// Authentication handler to manage notification lifecycle
class AuthHandler {
  static void setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      if (user != null) {
        print('👤 User logged in: ${user.id}');

        // Refresh FCM token on login
        await NotificationService().refreshFCMToken();

        // Subscribe to topics
        if (NotificationService().isInitialized) {
          await NotificationService().subscribeToTopics(user.id);
        }

        // Start listening to notifications
        NotificationHandler().startListeningToNotifications();
      } else {
        print('👤 User logged out');

        // Cleanup on logout
        await NotificationService().cleanup();

        // Stop listening
        NotificationHandler().stopListening();
      }
    });
  }
}