// ============================================
// FIXED HARDCODED NOTIFICATION SOLUTION
// ============================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart'; // Your existing notification service

class NotificationHandler {
  static final NotificationHandler _instance = NotificationHandler._internal();
  factory NotificationHandler() => _instance;
  NotificationHandler._internal();

  StreamSubscription? _notificationSubscription; // ✅ FIXED: Added StreamSubscription
  bool _isListening = false;

  // ============================================
  // MAIN METHOD: Start listening for notifications
  // ============================================
  void startListeningToNotifications() {
    if (_isListening) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    print('🔔 Starting notification listener for user: ${user.id}');

    // ✅ FIXED: Store the subscription so we can cancel it later
    _notificationSubscription = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen((data) {
      print('📡 Real-time notification data received: ${data.length} items');

      // Process each notification
      for (final notification in data) {
        _handleRealtimeNotification(notification);
      }
    });

    _isListening = true;
    print('✅ Notification listener started');
  }

  // ============================================
  // HANDLE REAL-TIME NOTIFICATION
  // ============================================
  void _handleRealtimeNotification(Map<String, dynamic> notification) {
    print('📱 Processing notification: ${notification['title']}');

    // Check if this notification should show popup
    final isRead = notification['is_read'] ?? false;
    final isSent = notification['is_sent'] ?? false; // ✅ ADDED: Check if already sent
    final createdAt = DateTime.parse(notification['created_at']);
    final now = DateTime.now();
    final isRecent = now.difference(createdAt).inMinutes < 5; // Within 5 minutes

    // Show popup for unread, unsent, and recent notifications
    if (!isRead && !isSent && isRecent) {
      _showPhonePopup(notification);
    }
  }

  // ============================================
  // SHOW PHONE POPUP NOTIFICATION
  // ============================================
  Future<void> _showPhonePopup(Map<String, dynamic> notification) async {
    print('🔔 Showing phone popup for: ${notification['title']}');

    try {
      final title = notification['title'] ?? 'IronXpress';
      final body = notification['body'] ?? 'You have a new notification';
      final type = notification['type'] ?? 'general';
      final data = notification['data'] ?? {};

      // Call your existing Edge Function for phone popup
      final success = await NotificationService().sendNotificationViaEdgeFunction(
        userId: notification['user_id'],
        title: title,
        body: body,
        data: {
          'notification_id': notification['id'],
          'type': type,
          ...Map<String, dynamic>.from(data), // ✅ FIXED: Proper casting
        },
      );

      if (success) {
        print('✅ Phone popup sent successfully');

        // Mark as sent in database
        await Supabase.instance.client
            .from('notifications')
            .update({
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
        })
            .eq('id', notification['id']);

      } else {
        print('❌ Failed to send phone popup');
      }

    } catch (e) {
      print('❌ Error showing phone popup: $e');
    }
  }

  // ============================================
  // MANUAL METHOD: Send notification + popup immediately
  // ============================================
  static Future<void> sendNotificationWithPopup({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    try {
      print('📤 Sending notification with popup: $title');

      // 1. Insert into database (for app notification list)
      final notification = await Supabase.instance.client
          .from('notifications')
          .insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'is_read': false,
        'is_sent': false, // ✅ ADDED: Mark as not sent initially
        'created_at': DateTime.now().toIso8601String(),
      })
          .select()
          .single();

      print('✅ Notification saved to database');

      // 2. Immediately send phone popup
      final success = await NotificationService().sendNotificationViaEdgeFunction(
        userId: userId,
        title: title,
        body: body,
        data: {
          'notification_id': notification['id'],
          'type': type,
          if (data != null) ...data, // ✅ FIXED: Proper spreading
        },
      );

      if (success) {
        // 3. Mark as sent
        await Supabase.instance.client
            .from('notifications')
            .update({
          'is_sent': true,
          'sent_at': DateTime.now().toIso8601String(),
        })
            .eq('id', notification['id']);

        print('✅ Notification with popup sent successfully');
      } else {
        print('⚠️ Notification saved but popup failed');
      }

    } catch (e) {
      print('❌ Error sending notification with popup: $e');
    }
  }

  // ============================================
  // METHODS FOR DIFFERENT NOTIFICATION TYPES
  // ============================================

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
        body = 'Your fresh laundry is ready and will be delivered soon!';
        break;
      case 'delivered':
        title = 'Order Delivered ✅';
        body = 'Your laundry has been delivered. Thank you for choosing IronXpress!';
        break;
      default:
        title = 'Order Update';
        body = 'Your order status has been updated.';
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

  // ✅ FIXED: Properly stop listening and cancel subscription
  void stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _isListening = false;
    print('🔕 Notification listener stopped');
  }
}

// ============================================
// USAGE IN YOUR APP
// ============================================

// 1. ADD TO YOUR MAIN APP INITIALIZATION
class MyApp extends StatefulWidget {
  const MyApp({super.key}); // ✅ FIXED: Added const and key

  @override
  State<MyApp> createState() => _MyAppState(); // ✅ FIXED: Modern syntax
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // Start listening when app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationHandler().startListeningToNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronXpress',
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_laundry_service, size: 64, color: Colors.blue),
              SizedBox(height: 16),
              Text(
                'IronXpress',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 32),
              TestNotificationButton(), // Test button to verify notifications work
            ],
          ),
        ),
      ),
    );
  }
}

// 2. ADD TO YOUR ORDER CREATION CODE
Future<void> createOrder(Map<String, dynamic> orderData) async {
  try {
    // Create the order
    final order = await Supabase.instance.client
        .from('orders')
        .insert(orderData)
        .select()
        .single();

    print('✅ Order created: ${order['id']}');

    // IMMEDIATELY send notification with popup
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await NotificationHandler.sendOrderConfirmation(
        userId: user.id,
        orderId: order['id'],
      );
    }

  } catch (e) {
    print('❌ Error creating order: $e');
  }
}

// 3. ADD TO YOUR ORDER STATUS UPDATE CODE
Future<void> updateOrderStatus(String orderId, String newStatus) async {
  try {
    // Update order status
    await Supabase.instance.client
        .from('orders')
        .update({'order_status': newStatus})
        .eq('id', orderId);

    // Get order details
    final order = await Supabase.instance.client
        .from('orders')
        .select('user_id')
        .eq('id', orderId)
        .single();

    // IMMEDIATELY send status update notification with popup
    await NotificationHandler.sendOrderStatusUpdate(
      userId: order['user_id'],
      orderId: orderId,
      status: newStatus,
    );

  } catch (e) {
    print('❌ Error updating order status: $e');
  }
}

// 4. TEST BUTTON FOR YOUR APP
class TestNotificationButton extends StatelessWidget {
  const TestNotificationButton({super.key}); // ✅ FIXED: Added const and key

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          // Test notification with popup
          await NotificationHandler.sendNotificationWithPopup(
            userId: user.id,
            title: 'Test Notification 🧪',
            body: 'This should show in app AND as phone popup!',
            type: 'test',
            data: {'test': true},
          );

          if (context.mounted) { // ✅ FIXED: Check if context is still mounted
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Test notification sent!')),
            );
          }
        }
      },
      child: const Text('Test Notification + Popup'),
    );
  }
}

// ============================================
// AUTH LISTENER SETUP
// ============================================
class AuthHandler {
  static void setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;

      if (user != null) {
        // User logged in - start listening to notifications
        print('👤 User logged in: ${user.id}');
        NotificationHandler().startListeningToNotifications();
      } else {
        // User logged out - stop listening
        print('👤 User logged out');
        NotificationHandler().stopListening();
      }
    });
  }
}