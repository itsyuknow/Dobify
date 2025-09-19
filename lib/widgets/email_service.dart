import 'package:supabase_flutter/supabase_flutter.dart';

class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final supabase = Supabase.instance.client;

  /// Sends order emails via the `send-email` Edge Function.
  /// - If [status] is empty, we'll fetch it from `orders.order_status`.
  /// - Returns `true` only when the function returns `{ success: true }`.
  Future<bool> sendOrderEmail({
    required String userEmail,
    required String userName,
    required String orderId,
    required String status, // can be '', we'll fetch from DB if so
    required String emailType,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      // Use the logged-in user's email if not provided
      if (userEmail.isEmpty) {
        final user = supabase.auth.currentUser;
        if (user?.email == null) return false;
        userEmail = user!.email!;
      }

      // Ensure we use the latest status from DB if the passed-in status is empty
      final String effectiveStatus = await _resolveOrderStatus(orderId, status);

      // Build the email content based on emailType + effectiveStatus
      final emailContent = _generateEmailContent(
        emailType: emailType,
        userName: userName,
        orderId: orderId,
        status: effectiveStatus,
        orderData: orderData,
      );

      // Invoke the Edge Function
      final resp = await supabase.functions.invoke(
        'send-email',
        body: <String, dynamic>{
          'to': userEmail,
          'subject': emailContent['subject'],
          'html': emailContent['html'],
          'text': emailContent['text'],
        },
      );

      // Parse response safely across SDK versions
      final dynamic dyn = resp;
      final int httpStatus = (dyn.status is int) ? dyn.status as int : 200;
      final dynamic data = dyn.data;

      if (httpStatus != 200) {
        print('❌ send-email failed (HTTP $httpStatus): $data');
        return false;
      }

      if (data is Map && data['success'] == true) {
        print('✅ Email sent to $userEmail (email_id: ${data['email_id']})');
        return true;
      } else {
        print('❌ send-email returned non-success payload: $data');
        return false;
      }
    } catch (e) {
      print('❌ Error calling send-email: $e');
      return false;
    }
  }

  /// If [passedStatus] is non-empty, use it.
  /// Otherwise fetch `orders.order_status` for [orderId]. Fallback to 'unknown'.
  Future<String> _resolveOrderStatus(String orderId, String passedStatus) async {
    final trimmed = passedStatus.trim();
    if (trimmed.isNotEmpty) return trimmed;

    try {
      final row = await supabase
          .from('orders')
          .select('order_status')
          .eq('id', orderId)
          .maybeSingle();

      final dbStatus = row?['order_status']?.toString() ?? '';
      if (dbStatus.trim().isNotEmpty) return dbStatus.trim();
    } catch (e) {
      print('⚠️ Failed to fetch order status from DB: $e');
    }
    return 'unknown';
  }

  // ------------------- Templating -------------------

  Map<String, String> _generateEmailContent({
    required String emailType,
    required String userName,
    required String orderId,
    required String status,
    Map<String, dynamic>? orderData,
  }) {
    switch (emailType) {
      case 'order_placed':
        return {
          'subject': '🎉 Order Confirmed - #$orderId | IronXpress',
          'html': _orderPlacedHtml(userName, orderId, orderData),
          'text': _orderPlacedText(userName, orderId, orderData),
        };
      case 'order_status_update':
        return {
          'subject': '📦 Order Update - #$orderId | IronXpress',
          'html': _orderUpdateHtml(userName, orderId, status, orderData),
          'text': _orderUpdateText(userName, orderId, status, orderData),
        };
      case 'order_delivered':
        return {
          'subject': '✅ Order Delivered - #$orderId | IronXpress',
          'html': _orderDeliveredHtml(userName, orderId, orderData),
          'text': _orderDeliveredText(userName, orderId, orderData),
        };
      default:
        return {
          'subject': '🔔 Notification from IronXpress',
          'html': _defaultHtml(userName, orderId, status),
          'text': _defaultText(userName, orderId, status),
        };
    }
  }

  // HTML templates
  String _orderPlacedHtml(String userName, String orderId, Map<String, dynamic>? data) {
    final pickupDate = data?['pickup_date'] ?? 'TBD';
    final deliveryDate = data?['delivery_date'] ?? 'TBD';
    final totalAmount = data?['total_amount']?.toString() ?? '0';
    final paymentMethod = data?['payment_method'] ?? 'COD';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Order Confirmation</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; font-weight: 700; }
    .content { padding: 30px; }
    .order-info { background-color: #f8fafc; border-radius: 8px; padding: 20px; margin: 20px 0; }
    .info-row { display: flex; justify-content: space-between; margin: 10px 0; }
    .label { font-weight: 600; color: #374151; }
    .value { color: #6b7280; }
    .status-badge { display: inline-block; background-color: #10b981; color: white; padding: 6px 12px; border-radius: 20px; font-size: 14px; font-weight: 600; }
    .footer { background-color: #1f2937; color: white; padding: 20px; text-align: center; }
    .btn { display: inline-block; background-color: #6366f1; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; margin: 10px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Order Confirmed!</h1>
      <p>Thank you for choosing IronXpress</p>
    </div>
    <div class="content">
      <h2>Hello $userName,</h2>
      <p>Your laundry order has been successfully placed and confirmed. We'll take great care of your items!</p>

      <div class="order-info">
        <h3>Order Details</h3>
        <div class="info-row"><span class="label">Order ID:</span><span class="value"><strong>#$orderId</strong></span></div>
        <div class="info-row"><span class="label">Status:</span><span class="status-badge">Confirmed</span></div>
        <div class="info-row"><span class="label">Pickup Date:</span><span class="value">$pickupDate</span></div>
        <div class="info-row"><span class="label">Delivery Date:</span><span class="value">$deliveryDate</span></div>
        <div class="info-row"><span class="label">Total Amount:</span><span class="value">₹$totalAmount</span></div>
        <div class="info-row"><span class="label">Payment Method:</span><span class="value">${paymentMethod.toUpperCase()}</span></div>
      </div>

      <p><strong>What's Next?</strong></p>
      <ul>
        <li>We'll contact you to confirm pickup details</li>
        <li>Your items will be collected on the scheduled date</li>
        <li>Professional cleaning and pressing</li>
        <li>Delivery back to your doorstep</li>
      </ul>

      <center><a href="#" class="btn">Track Your Order</a></center>
    </div>
    <div class="footer">
      <p>Need help? Contact us at support@ironxpress.com</p>
      <p>© 2025 IronXpress - Premium Laundry Service</p>
    </div>
  </div>
</body>
</html>''';
  }

  String _orderUpdateHtml(String userName, String orderId, String status, Map<String, dynamic>? data) {
    final statusColors = {
      'accepted': '#10b981',
      'assigned': '#3b82f6',
      'working_in_progress': '#f59e0b',
      'ready_to_dispatch': '#8b5cf6',
      'in_transit': '#06b6d4',
      'delivered': '#10b981',
      'completed': '#10b981',
      'cancelled': '#ef4444',
    };

    final statusEmojis = {
      'accepted': '✅',
      'assigned': '🚚',
      'working_in_progress': '🧽',
      'ready_to_dispatch': '📦',
      'in_transit': '🚛',
      'delivered': '✅',
      'completed': '🎉',
      'cancelled': '❌',
    };

    final statusColor = statusColors[status] ?? '#6b7280';
    final statusEmoji = statusEmojis[status] ?? '📦';
    final totalAmount = data?['total_amount']?.toString() ?? '0';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Order Update</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; font-weight: 700; }
    .content { padding: 30px; }
    .status-update { background-color: #f8fafc; border-left: 4px solid $statusColor; border-radius: 8px; padding: 20px; margin: 20px 0; }
    .status-badge { display: inline-block; background-color: $statusColor; color: white; padding: 6px 12px; border-radius: 20px; font-size: 14px; font-weight: 600; }
    .footer { background-color: #1f2937; color: white; padding: 20px; text-align: center; }
    .btn { display: inline-block; background-color: #6366f1; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; margin: 10px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>$statusEmoji Order Update</h1>
      <p>Your order status has been updated</p>
    </div>
    <div class="content">
      <h2>Hello $userName,</h2>
      <p>We wanted to keep you informed about your laundry order progress.</p>

      <div class="status-update">
        <h3>Order #$orderId</h3>
        <p><strong>New Status:</strong> <span class="status-badge">${status.replaceAll('_', ' ').toUpperCase()}</span></p>
        <p><strong>Order Value:</strong> ₹$totalAmount</p>
      </div>

      ${_getStatusMessage(status)}

      <center><a href="#" class="btn">Track Your Order</a></center>
    </div>
    <div class="footer">
      <p>Need help? Contact us at support@ironxpress.com</p>
      <p>© 2025 IronXpress - Premium Laundry Service</p>
    </div>
  </div>
</body>
</html>''';
  }

  String _orderDeliveredHtml(String userName, String orderId, Map<String, dynamic>? data) {
    final totalAmount = data?['total_amount']?.toString() ?? '0';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Order Delivered</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 28px; font-weight: 700; }
    .content { padding: 30px; }
    .delivery-info { background-color: #f0fdf4; border-radius: 8px; padding: 20px; margin: 20px 0; text-align: center; }
    .footer { background-color: #1f2937; color: white; padding: 20px; text-align: center; }
    .btn { display: inline-block; background-color: #10b981; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: 600; margin: 10px 5px; }
    .rating { font-size: 24px; margin: 10px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🎉 Order Delivered!</h1>
      <p>Your laundry has been successfully delivered</p>
    </div>
    <div class="content">
      <h2>Hello $userName,</h2>
      <p>Great news! Your laundry order has been delivered successfully.</p>

      <div class="delivery-info">
        <h3>✅ Order #$orderId Completed</h3>
        <p><strong>Order Value:</strong> ₹$totalAmount</p>
        <p>We hope you're satisfied with our premium laundry service!</p>
      </div>

      <h3>How was your experience?</h3>
      <p>We'd love to hear your feedback about our service.</p>
      <div class="rating">⭐⭐⭐⭐⭐</div>

      <center>
        <a href="#" class="btn">Rate Our Service</a>
        <a href="#" class="btn">Order Again</a>
      </center>

      <p><strong>Thank you for choosing IronXpress!</strong></p>
    </div>
    <div class="footer">
      <p>Need help? Contact us at support@ironxpress.com</p>
      <p>© 2025 IronXpress - Premium Laundry Service</p>
    </div>
  </div>
</body>
</html>''';
  }

  String _defaultHtml(String userName, String orderId, String status) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>IronXpress Notification</title>
  <style>
    body { font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    .header { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; padding: 30px; text-align: center; }
    .content { padding: 30px; }
    .footer { background-color: #1f2937; color: white; padding: 20px; text-align: center; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header"><h1>🔔 IronXpress</h1></div>
    <div class="content">
      <h2>Hello $userName,</h2>
      <p>You have a new notification regarding your order #$orderId.</p>
      <p><strong>Status:</strong> $status</p>
    </div>
    <div class="footer"><p>© 2025 IronXpress - Premium Laundry Service</p></div>
  </div>
</body>
</html>''';
  }

  // Plain-text versions
  String _orderPlacedText(String userName, String orderId, Map<String, dynamic>? data) {
    return '''
Hello $userName,

🎉 Your laundry order has been successfully placed!

Order Details:
- Order ID: #$orderId
- Status: Confirmed
- Pickup Date: ${data?['pickup_date'] ?? 'TBD'}
- Delivery Date: ${data?['delivery_date'] ?? 'TBD'}
- Total Amount: ₹${data?['total_amount'] ?? '0'}
- Payment Method: ${data?['payment_method']?.toString().toUpperCase() ?? 'COD'}

What's Next:
• We'll contact you to confirm pickup details
• Your items will be collected on the scheduled date
• Professional cleaning and pressing
• Delivery back to your doorstep

Thank you for choosing IronXpress!

Need help? Contact us at support@ironxpress.com
© 2025 IronXpress - Premium Laundry Service''';
  }

  String _orderUpdateText(String userName, String orderId, String status, Map<String, dynamic>? data) {
    return '''
Hello $userName,

📦 Order Update for #$orderId

Your order status has been updated to: ${status.replaceAll('_', ' ').toUpperCase()}
Order Value: ₹${data?['total_amount'] ?? '0'}

${_getStatusMessageText(status)}

Thank you for choosing IronXpress!

Need help? Contact us at support@ironxpress.com
© 2025 IronXpress - Premium Laundry Service''';
  }

  String _orderDeliveredText(String userName, String orderId, Map<String, dynamic>? data) {
    return '''
Hello $userName,

🎉 Great news! Your laundry order has been delivered successfully.

Order #$orderId Completed
Order Value: ₹${data?['total_amount'] ?? '0'}

We hope you're satisfied with our premium laundry service!

Thank you for choosing IronXpress!

Need help? Contact us at support@ironxpress.com
© 2025 IronXpress - Premium Laundry Service''';
  }

  String _defaultText(String userName, String orderId, String status) {
    return '''
Hello $userName,

🔔 You have a new notification from IronXpress.

Order: #$orderId
Status: $status

Thank you for choosing IronXpress!

© 2025 IronXpress - Premium Laundry Service''';
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'accepted':
        return '<p><strong>Great news!</strong> Your order has been accepted and we\'re preparing to collect your items.</p>';
      case 'assigned':
        return '<p><strong>Pickup Scheduled!</strong> A delivery partner has been assigned to your order. They will contact you soon.</p>';
      case 'working_in_progress':
      case 'work_in_progress':
        return '<p><strong>In Progress!</strong> Our team is currently working on your laundry with care and attention.</p>';
      case 'ready_to_dispatch':
        return '<p><strong>Ready for Delivery!</strong> Your freshly cleaned items are ready and will be dispatched soon.</p>';
      case 'in_transit':
        return '<p><strong>On the Way!</strong> Your order is currently being delivered to your address.</p>';
      case 'delivered':
        return '<p><strong>Delivered!</strong> Your laundry has been successfully delivered. Thank you for choosing IronXpress!</p>';
      case 'completed':
        return '<p><strong>Order Complete!</strong> Your order has been completed successfully. We hope you\'re satisfied with our service!</p>';
      case 'cancelled':
        return '<p><strong>Order Cancelled.</strong> Your order has been cancelled. If you have any questions, please contact our support team.</p>';
      default:
        return '<p>Your order status has been updated. Thank you for choosing IronXpress!</p>';
    }
  }

  String _getStatusMessageText(String status) {
    switch (status) {
      case 'accepted':
        return 'Great news! Your order has been accepted and we\'re preparing to collect your items.';
      case 'assigned':
        return 'Pickup Scheduled! A delivery partner has been assigned to your order. They will contact you soon.';
      case 'working_in_progress':
      case 'work_in_progress':
        return 'In Progress! Our team is currently working on your laundry with care and attention.';
      case 'ready_to_dispatch':
        return 'Ready for Delivery! Your freshly cleaned items are ready and will be dispatched soon.';
      case 'in_transit':
        return 'On the Way! Your order is currently being delivered to your address.';
      case 'delivered':
        return 'Delivered! Your laundry has been successfully delivered. Thank you for choosing IronXpress!';
      case 'completed':
        return 'Order Complete! Your order has been completed successfully. We hope you\'re satisfied with our service!';
      case 'cancelled':
        return 'Order Cancelled. Your order has been cancelled. If you have any questions, please contact our support team.';
      default:
        return 'Your order status has been updated. Thank you for choosing IronXpress!';
    }
  }
}
