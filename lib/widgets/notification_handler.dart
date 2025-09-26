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
      debugPrint('ℹ️ No logged-in user; skipping notification listener.');
      return;
    }

    debugPrint('🔔 Starting notification listener for user: ${user.id}');

    _notificationSubscription = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen(
          (rows) async {
        if (rows.isEmpty) return;

        for (final notif in rows) {
          _handleRealtimeNotification(notif);
        }
      },
      onError: (e, st) => debugPrint('❌ Realtime notifications stream error: $e'),
      cancelOnError: false,
    );

    _isListening = true;
    debugPrint('✅ Notification listener started');
  }

  void _handleRealtimeNotification(Map<String, dynamic> notification) {
    final bool isRead = (notification['is_read'] ?? false) == true;
    final bool isSent = (notification['is_sent'] ?? false) == true;

    final createdAtRaw = notification['created_at'];
    DateTime createdAt = DateTime.now();
    if (createdAtRaw is String) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    }
    final bool isRecent = DateTime.now().difference(createdAt).inMinutes < 10;

    // Only send push for unread, unsent, *recent* notifications
    if (!isRead && !isSent && isRecent) {
      _sendPushNotification(notification);
    }
  }

  Future<void> _sendPushNotification(Map<String, dynamic> notification) async {
    try {
      final String userId = (notification['user_id'] ?? '').toString();
      if (userId.isEmpty) return;

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
        await _markNotificationAsSent(notification['id']);
      }
    } catch (e) {
      debugPrint('❌ Error sending push notification: $e');
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
    } catch (e) {
      debugPrint('❌ Error marking notification as sent: $e');
    }
  }

  void stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _isListening = false;
  }

  Map<String, dynamic>? _coerceToMap(dynamic raw) {
    try {
      if (raw == null) return <String, dynamic>{};
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
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
        NotificationHandler().startListeningToNotifications();
      } else {
        NotificationHandler().stopListening();
      }
    });
  }
}
