import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'colors.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;
  Map<String, Timer?> _cancelTimers = {};
  Map<String, int> _cancelTimeRemaining = {};

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _loadOrders();
  }

  @override
  void dispose() {
    _animationController.dispose();
    // Dispose all timers
    for (var timer in _cancelTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => isLoading = true);
      print('Loading orders for user: ${user.id}');

      // Get orders from past 30 days with optimized query
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      // ✅ OPTIMIZED: Single query with proper filtering and joins to reduce API calls
      final ordersResponse = await supabase
          .from('orders')
          .select('''
            *,
            pickup_slot_display_time,
            pickup_slot_start_time,
            pickup_slot_end_time,
            delivery_slot_display_time,
            delivery_slot_start_time,
            delivery_slot_end_time
          ''')
          .eq('user_id', user.id) // ✅ OPTIMIZED: Filter by user_id first
          .gte('created_at', thirtyDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      print('Found ${ordersResponse.length} orders from past 30 days');

      List<Map<String, dynamic>> ordersWithDetails = [];

      for (var order in ordersResponse) {
        Map<String, dynamic> orderWithDetails = Map<String, dynamic>.from(order);

        try {
          // ✅ OPTIMIZED: Get order items with single query
          final orderItemsResponse = await supabase
              .from('order_items')
              .select('*, product_image')
              .eq('order_id', order['id']);

          print('Found ${orderItemsResponse.length} items for order ${order['id']}');

          // Process order items
          List<Map<String, dynamic>> processedItems = [];
          for (var item in orderItemsResponse) {
            Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);

            String? productImageUrl = item['product_image'];

            // Get additional product details if product_id exists
            if (item['product_id'] != null) {
              try {
                final productResponse = await supabase
                    .from('products')
                    .select('id, product_name, image_url, product_price, category_id')
                    .eq('id', item['product_id'])
                    .maybeSingle();

                if (productResponse != null) {
                  processedItem['products'] = {
                    'id': productResponse['id'],
                    'name': productResponse['product_name'],
                    'image_url': productImageUrl ?? productResponse['image_url'],
                    'price': productResponse['product_price'],
                    'category_id': productResponse['category_id'],
                  };
                } else {
                  // Fallback product data
                  processedItem['products'] = {
                    'id': item['product_id'],
                    'name': item['product_name'] ?? 'Product ${item['product_id']}',
                    'image_url': productImageUrl,
                    'price': item['product_price'] ?? 0.0,
                    'category_id': null,
                  };
                }
              } catch (e) {
                print('Error loading product ${item['product_id']}: $e');
                // Fallback product data
                processedItem['products'] = {
                  'id': item['product_id'],
                  'name': item['product_name'] ?? 'Unknown Product',
                  'image_url': productImageUrl,
                  'price': item['product_price'] ?? 0.0,
                  'category_id': null,
                };
              }
            } else {
              // No product_id, use item data
              processedItem['products'] = {
                'id': null,
                'name': item['product_name'] ?? 'Unknown Product',
                'image_url': productImageUrl,
                'price': item['product_price'] ?? 0.0,
                'category_id': null,
              };
            }

            processedItems.add(processedItem);
          }

          orderWithDetails['order_items'] = processedItems;

          // Get delivery address if available
          if (order['address_details'] != null) {
            try {
              orderWithDetails['address_info'] = order['address_details'];
            } catch (e) {
              print('Error parsing address details: $e');
            }
          }

          // ✅ OPTIMIZED: Get billing details with single query
          try {
            final billingResponse = await supabase
                .from('order_billing_details')
                .select('*')
                .eq('order_id', order['id'])
                .maybeSingle();

            if (billingResponse != null) {
              orderWithDetails['order_billing_details'] = [billingResponse];
            }
          } catch (e) {
            print('Error loading billing details for order ${order['id']}: $e');
          }

          // ✅ NEW: Use stored slot details from orders table instead of separate queries
          if (order['pickup_slot_display_time'] != null) {
            orderWithDetails['pickup_slot'] = {
              'display_time': order['pickup_slot_display_time'],
              'start_time': order['pickup_slot_start_time'],
              'end_time': order['pickup_slot_end_time'],
            };
          }

          if (order['delivery_slot_display_time'] != null) {
            orderWithDetails['delivery_slot'] = {
              'display_time': order['delivery_slot_display_time'],
              'start_time': order['delivery_slot_start_time'],
              'end_time': order['delivery_slot_end_time'],
            };
          }

          // Setup cancel timer if order can be cancelled
          _setupCancelTimer(orderWithDetails);

        } catch (e) {
          print('Error loading order items for order ${order['id']}: $e');
          orderWithDetails['order_items'] = [];
        }

        ordersWithDetails.add(orderWithDetails);
      }

      if (mounted) {
        setState(() {
          orders = ordersWithDetails;
          isLoading = false;
        });
        _animationController.forward();
        print('Successfully loaded ${orders.length} orders with details');
      }
    } catch (e) {
      print('Error loading orders: $e');
      if (mounted) {
        setState(() {
          orders = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _reorderItems(Map<String, dynamic> order) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('Please login to reorder');
      return;
    }

    try {
      // Show loading overlay
      _showLoadingDialog('Adding items to cart...');

      final orderItems = order['order_items'] as List<dynamic>? ?? [];
      int addedItems = 0;

      // First, clear any existing cart for fresh reorder
      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      for (var item in orderItems) {
        final product = item['products'];
        if (product != null) {
          try {
            // Check if product is still available (if product_id exists)
            if (product['id'] != null) {
              final productCheck = await supabase
                  .from('products')
                  .select('id, product_name, product_price, image_url, is_enabled, category_id')
                  .eq('id', product['id'])
                  .eq('is_enabled', true)
                  .maybeSingle();

              if (productCheck != null) {
                final imageUrl = product['image_url'] ?? productCheck['image_url'];

                // Add item to cart with same service type
                await supabase.from('cart').insert({
                  'user_id': user.id,
                  'product_name': productCheck['product_name'],
                  'product_image': imageUrl,
                  'product_price': productCheck['product_price'],
                  'service_type': item['service_type'] ?? 'Standard',
                  'service_price': item['service_price'] ?? 0.0,
                  'product_quantity': item['quantity'] ?? 1,
                  'total_price': (productCheck['product_price'] ?? 0.0) * (item['quantity'] ?? 1),
                  'category': product['category_id'],
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                });
                addedItems++;
              }
            } else {
              // For products without product_id, add based on name
              await supabase.from('cart').insert({
                'user_id': user.id,
                'product_name': product['name'] ?? item['product_name'],
                'product_image': product['image_url'],
                'product_price': product['price'] ?? item['product_price'],
                'service_type': item['service_type'] ?? 'Standard',
                'service_price': item['service_price'] ?? 0.0,
                'product_quantity': item['quantity'] ?? 1,
                'total_price': (product['price'] ?? item['product_price'] ?? 0.0) * (item['quantity'] ?? 1),
                'category': product['category_id'],
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              });
              addedItems++;
            }
          } catch (e) {
            print('Error adding item ${product['name']} to cart: $e');
          }
        }
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (addedItems > 0) {
        // Show success message and navigate to cart
        _showSuccessSnackBar('$addedItems items added to cart!');

        // Navigate to cart screen
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            Navigator.of(context).pushNamed('/cart');
          }
        });
      } else {
        _showErrorSnackBar('No items could be added. Products may be unavailable.');
      }

    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      print('Error during reorder: $e');
      _showErrorSnackBar('Failed to reorder items');
    }
  }

  void _setupCancelTimer(Map<String, dynamic> order) {
    if (!_canShowCancelButton(order)) return;

    final orderId = order['id'].toString();
    final orderDate = order['pickup_date'];
    final pickupSlot = order['pickup_slot'];

    if (orderDate == null || pickupSlot == null) return;

    try {
      // Parse order date and pickup slot time
      final pickupDate = DateTime.parse(orderDate);
      final startTimeStr = pickupSlot['start_time'].toString();

      // Parse time (format: HH:mm:ss or HH:mm)
      final timeParts = startTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Create pickup deadline (pickup date + pickup time - 1 hour buffer)
      final pickupDeadline = DateTime(
          pickupDate.year,
          pickupDate.month,
          pickupDate.day,
          hour,
          minute
      ).subtract(const Duration(hours: 1)); // 1 hour before pickup

      final now = DateTime.now();

      if (now.isBefore(pickupDeadline)) {
        final remainingSeconds = pickupDeadline.difference(now).inSeconds;
        _cancelTimeRemaining[orderId] = remainingSeconds;

        _cancelTimers[orderId] = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _cancelTimeRemaining[orderId] = (_cancelTimeRemaining[orderId] ?? 0) - 1;
          });

          if ((_cancelTimeRemaining[orderId] ?? 0) <= 0) {
            timer.cancel();
            _cancelTimers.remove(orderId);
            _cancelTimeRemaining.remove(orderId);
          }
        });
      }
    } catch (e) {
      print('Error setting up cancel timer: $e');
    }
  }

  bool _canShowCancelButton(Map<String, dynamic> order) {
    final status = order['order_status']?.toString().toLowerCase() ?? '';
    return status == 'pending' || status == 'confirmed';
  }

  bool _canReschedule(Map<String, dynamic> order) {
    final status = order['order_status']?.toString().toLowerCase() ?? '';

    if (!(status == 'pending' || status == 'confirmed')) {
      return false;
    }

    // Then check if we're within the reschedule time window (same as cancel logic)
    final orderId = order['id'].toString();
    final remainingTime = _getRemainingCancelTime(orderId);

    // Can only reschedule if there's remaining time (same as cancel button logic)
    return remainingTime > 0;
  }

  int _getRemainingCancelTime(String orderId) {
    return _cancelTimeRemaining[orderId] ?? 0;
  }

  String _formatRemainingTime(int seconds) {
    if (seconds <= 0) return '00:00';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    // Show cancellation reason dialog instead of direct confirmation
    await _showCancellationReasonDialog(order);
  }

  Future<void> _showCancellationReasonDialog(Map<String, dynamic> order) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CancellationReasonDialog(
        order: order,
        onCancel: () => Navigator.pop(context),
        onConfirm: (String reason, int? reasonId) async {
          Navigator.pop(context); // Close dialog first
          await _performOrderCancellationWithReason(order, reason, reasonId);
        },
      ),
    );
  }


  Future<void> _performOrderCancellationWithReason(
      Map<String, dynamic> order,
      String cancellationReason,
      int? selectedReasonId
      ) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('User not authenticated');
      return;
    }

    try {
      // Show loading overlay
      _showLoadingDialog('Cancelling your order...');

      // Update order status
      await supabase
          .from('orders')
          .update({
        'status': 'cancelled',
        'order_status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', order['id']);

      // Log cancellation reason
      await supabase.from('order_cancellation_logs').insert({
        'order_id': order['id'],
        'user_id': user.id,
        'cancellation_reason': cancellationReason,
        'selected_reason_id': selectedReasonId,
        'cancelled_at': DateTime.now().toIso8601String(),
      });

      // Stop the timer for this order
      final orderId = order['id'].toString();
      _cancelTimers[orderId]?.cancel();
      _cancelTimers.remove(orderId);
      _cancelTimeRemaining.remove(orderId);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show success animation and message
      await _showCancellationSuccessAnimation();

      // Reload orders
      await _loadOrders();

    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      print('Error cancelling order: $e');
      _showErrorSnackBar('Failed to cancel order. Please try again.');
    }
  }

  Future<void> _showCancellationSuccessAnimation() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CancellationSuccessDialog(),
    );
  }



  // NEW METHOD: Show reschedule dialog
  Future<void> _showRescheduleDialog(Map<String, dynamic> order) async {
    showDialog(
      context: context,
      builder: (context) => _RescheduleDialog(
        order: order,
        onReschedule: (newPickupSlot, newDeliverySlot, newPickupDate, newDeliveryDate) {
          _rescheduleOrder(order, newPickupSlot, newDeliverySlot, newPickupDate, newDeliveryDate);
        },
      ),
    );
  }

  // NEW METHOD: Reschedule order
  Future<void> _rescheduleOrder(
      Map<String, dynamic> order,
      Map<String, dynamic> newPickupSlot,
      Map<String, dynamic> newDeliverySlot,
      DateTime newPickupDate,
      DateTime newDeliveryDate,
      ) async {
    try {
      _showLoadingDialog('Rescheduling your order...');

      // Update order with new slots and dates
      await supabase.from('orders').update({
        'pickup_slot_id': newPickupSlot['id'],
        'delivery_slot_id': newDeliverySlot['id'],
        'pickup_date': newPickupDate.toIso8601String().split('T')[0],
        'delivery_date': newDeliveryDate.toIso8601String().split('T')[0],
        // ✅ NEW: Update stored slot details
        'pickup_slot_display_time': newPickupSlot['display_time'],
        'pickup_slot_start_time': newPickupSlot['start_time'],
        'pickup_slot_end_time': newPickupSlot['end_time'],
        'delivery_slot_display_time': newDeliverySlot['display_time'],
        'delivery_slot_start_time': newDeliverySlot['start_time'],
        'delivery_slot_end_time': newDeliverySlot['end_time'],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order['id']);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      _showSuccessSnackBar('Order rescheduled successfully!');

      // Reload orders to reflect changes
      await _loadOrders();

    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('Error rescheduling order: $e');
      _showErrorSnackBar('Failed to reschedule order');
    }
  }

  Future<void> _generateInvoice(Map<String, dynamic> order) async {
    try {
      // Show loading overlay
      _showLoadingDialog('Generating invoice...');

      final pdf = pw.Document();
      final orderItems = order['order_items'] as List<dynamic>? ?? [];
      final billingDetails = order['order_billing_details'] != null &&
          (order['order_billing_details'] as List).isNotEmpty
          ? (order['order_billing_details'] as List)[0]
          : null;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'IronXpress',
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            'At Your Service',
                            style: pw.TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Order #${order['id'].toString().substring(0, 8)}',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Date: ${_formatDate(order['created_at'])}',
                            style: pw.TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // Order Items
                pw.Text(
                  'Order Items',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Service', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                    // Item rows
                    ...orderItems.map((item) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(item['products']?['name'] ?? item['product_name'] ?? 'Unknown'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(item['service_type'] ?? 'Standard'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${item['quantity'] ?? 1}'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Rs ${item['product_price'] ?? '0.00'}'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Rs ${item['total_price'] ?? '0.00'}'),
                        ),
                      ],
                    )).toList(),
                  ],
                ),

                pw.SizedBox(height: 20),

                // Bill Summary
                pw.Text(
                  'Bill Summary',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    children: [
                      if (billingDetails != null) ...[
                        _buildPdfBillRow('Subtotal', 'Rs ${billingDetails['subtotal'] ?? '0.00'}'),
                        if ((billingDetails['minimum_cart_fee'] ?? 0) > 0)
                          _buildPdfBillRow('Minimum Cart Fee', 'Rs ${billingDetails['minimum_cart_fee']}'),
                        if ((billingDetails['platform_fee'] ?? 0) > 0)
                          _buildPdfBillRow('Platform Fee', 'Rs ${billingDetails['platform_fee']}'),
                        if ((billingDetails['service_tax'] ?? 0) > 0)
                          _buildPdfBillRow('Service Tax', 'Rs ${billingDetails['service_tax']}'),
                        if ((billingDetails['delivery_fee'] ?? 0) > 0)
                          _buildPdfBillRow('Delivery Fee', 'Rs ${billingDetails['delivery_fee']}'),
                        if ((billingDetails['discount_amount'] ?? 0) > 0)
                          _buildPdfBillRow('Discount', '-Rs ${billingDetails['discount_amount']}'),
                        pw.Divider(),
                        _buildPdfBillRow('Total Amount', 'Rs ${billingDetails['total_amount'] ?? order['total_amount'] ?? '0.00'}', isTotal: true),
                      ] else ...[
                        _buildPdfBillRow('Total Amount', 'Rs ${order['total_amount'] ?? '0.00'}', isTotal: true),
                      ],
                      pw.SizedBox(height: 10),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Payment Method:'),
                          pw.Text(order['payment_method']?.toString().toUpperCase() ?? 'N/A'),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // Footer
                pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'Thank you for choosing our IronXpress!',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'For any queries, contact us at info@ironxpress.in',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Save and share PDF
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/invoice_${order['id'].toString().substring(0, 8)}.pdf');
      await file.writeAsBytes(await pdf.save());

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Share the PDF
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice for Order #${order['id'].toString().substring(0, 8)}',
      );

      _showSuccessSnackBar('Invoice generated successfully!');

    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      print('Error generating invoice: $e');
      _showErrorSnackBar('Failed to generate invoice');
    }
  }

  pw.Widget _buildPdfBillRow(String label, String value, {bool isTotal = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for UI feedback
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: kPrimaryColor,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final isSmallScreen = screenWidth < 360;
    final cardMargin = isSmallScreen ? 8.0 : 16.0;
    final cardPadding = isSmallScreen ? 16.0 : 20.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Order History',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isSmallScreen ? 18 : 20,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: isLoading
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              Text(
                'Loading your orders...',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        )
            : orders.isEmpty
            ? Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(cardMargin),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 24 : 32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPrimaryColor.withOpacity(0.1),
                        Colors.purple.withOpacity(0.05)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    size: isSmallScreen ? 60 : 80,
                    color: kPrimaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Orders in Last 30 Days',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 20 : 24,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your recent order history will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  constraints:
                  BoxConstraints(maxWidth: screenWidth * 0.8),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                          '/orders', (route) => false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 24 : 32,
                        vertical: isSmallScreen ? 12 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25)),
                    ),
                    child: Text(
                      'Start Shopping',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
            : FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: _loadOrders,
            color: kPrimaryColor,
            child: ListView.builder(
              padding: EdgeInsets.only(
                left: cardMargin,
                right: cardMargin,
                top: cardMargin,
                bottom: cardMargin +
                    MediaQuery.of(context).padding.bottom,
              ),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                return _buildEnhancedOrderCard(
                    orders[index], index, cardPadding, isSmallScreen);
              },
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildEnhancedOrderCard(Map<String, dynamic> order, int index, double cardPadding, bool isSmallScreen) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final totalItems = orderItems.length;
    final firstProduct = orderItems.isNotEmpty ? orderItems[0] : null;
    final orderId = order['id'].toString();
    final canCancel = _canShowCancelButton(order);
    final canReschedule = _canReschedule(order);
    final remainingTime = _getRemainingCancelTime(orderId);

    return Container(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16, top: index == 0 ? 8 : 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showOrderDetails(order),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.receipt_rounded,
                                color: kPrimaryColor,
                                size: isSmallScreen ? 16 : 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  // 🔧 CHANGED: show only the full ID (no "#" and no substring)
                                  order['id']?.toString() ?? 'N/A',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: isSmallScreen ? 14 : 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(order['created_at']),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Show countdown timer for cancellable orders, otherwise show status badge
                    canCancel && remainingTime > 0
                        ? _buildCountdownBadge(remainingTime, isSmallScreen)
                        : _buildStatusBadge(order['order_status'], isSmallScreen),
                  ],
                ),

                SizedBox(height: isSmallScreen ? 12 : 16),

                // Product Preview with proper image handling
                if (firstProduct != null && firstProduct['products'] != null) ...[
                  Row(
                    children: [
                      // Product Image
                      Container(
                        width: isSmallScreen ? 50 : 60,
                        height: isSmallScreen ? 50 : 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey.shade100,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: firstProduct['products']['image_url'] != null &&
                              firstProduct['products']['image_url'].toString().isNotEmpty
                              ? Image.network(
                            firstProduct['products']['image_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey.shade400,
                                size: isSmallScreen ? 20 : 24,
                              ),
                            ),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                      : null,
                                  strokeWidth: 2,
                                  color: kPrimaryColor,
                                ),
                              );
                            },
                          )
                              : Container(
                            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.grey.shade400,
                              size: isSmallScreen ? 20 : 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Product Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              firstProduct['products']['name']?.toString() ?? 'Unknown Product',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: isSmallScreen ? 13 : 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty: ${firstProduct['quantity'] ?? 1} • ${firstProduct['service_type'] ?? 'Standard'}',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 11 : 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (totalItems > 1) ...[
                              const SizedBox(height: 2),
                              Text(
                                '+${totalItems - 1} more item${totalItems > 2 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: kPrimaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),
                ],

                // Order Summary
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor.withOpacity(0.05), Colors.purple.withOpacity(0.02)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Amount',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${order['total_amount'] ?? '0.00'}',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              fontWeight: FontWeight.w800,
                              color: kPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Items',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 11 : 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$totalItems',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isSmallScreen ? 12 : 16),

                // Action Buttons Row - UPDATED: Reschedule button instead of View Details
                Row(
                  children: [
                    // Reschedule Button (was View Details)
                    Expanded(
                      child: Container(
                        height: isSmallScreen ? 42 : 48,
                        child: ElevatedButton.icon(
                          onPressed: (canReschedule && remainingTime > 0) ? () => _showRescheduleDialog(order) : null,
                          icon: Icon(
                            (canReschedule && remainingTime > 0) ? Icons.schedule : Icons.block,
                            size: isSmallScreen ? 16 : 18,
                            color: (canReschedule && remainingTime > 0) ? kPrimaryColor : Colors.grey.shade500,
                          ),
                          label: Text(
                            (canReschedule && remainingTime > 0) ? 'Reschedule' :
                            canReschedule ? 'Reschedule Timeout' : 'Reschedule',
                            style: TextStyle(
                              color: (canReschedule && remainingTime > 0) ? kPrimaryColor : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (canReschedule && remainingTime > 0)
                                ? kPrimaryColor.withOpacity(0.1)
                                : Colors.grey.shade100,
                            foregroundColor: (canReschedule && remainingTime > 0) ? kPrimaryColor : Colors.grey.shade500,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Cancel Order or Reorder Button - FIXED LOGIC
                    Expanded(
                      child: Container(
                        height: isSmallScreen ? 42 : 48,
                        child: canCancel
                            ? ElevatedButton.icon(
                          // Button is enabled only when there's remaining time
                          onPressed: remainingTime > 0 ? () => _cancelOrder(order) : null,
                          icon: Icon(
                            remainingTime > 0 ? Icons.cancel_outlined : Icons.block,
                            size: isSmallScreen ? 16 : 18,
                            color: remainingTime > 0 ? Colors.white : Colors.grey.shade500,
                          ),
                          label: Text(
                            remainingTime > 0 ? 'Cancel Order' : 'Cancel ',
                            style: TextStyle(
                              color: remainingTime > 0 ? Colors.white : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: remainingTime > 0 ? Colors.red.shade600 : Colors.grey.shade200,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                            : (_canReorder(order['order_status'])
                            ? ElevatedButton.icon(
                          onPressed: () => _reorderItems(order),
                          icon: Icon(Icons.refresh_rounded, size: isSmallScreen ? 16 : 18, color: Colors.white),
                          label: Text(
                            'Reorder',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                            : ElevatedButton.icon(
                          onPressed: null,
                          icon: Icon(Icons.info_outline, size: isSmallScreen ? 16 : 18, color: Colors.grey.shade500),
                          label: Text(
                            'Order ${(order['order_status'] ?? 'Processing').toString().toLowerCase()}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 10 : 12,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildCountdownBadge(int remainingTime, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12, vertical: isSmallScreen ? 6 : 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.orange.shade500],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, color: Colors.white, size: isSmallScreen ? 12 : 14),
          const SizedBox(width: 6),
          Text(
            _formatRemainingTime(remainingTime),
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmallScreen ? 10 : 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(dynamic status, bool isSmallScreen) {
    final statusString = status?.toString().toLowerCase() ?? '';
    Color color;
    IconData icon;

    switch (statusString) {
      case 'delivered':
        color = Colors.green.shade600;
        icon = Icons.check_circle_rounded;
        break;
      case 'cancelled':
        color = Colors.red.shade600;
        icon = Icons.cancel_rounded;
        break;
      case 'pending':
        color = Colors.orange.shade600;
        icon = Icons.access_time_rounded;
        break;
      case 'confirmed':
        color = Colors.blue.shade600;
        icon = Icons.check_rounded;
        break;
      case 'processing':
        color = Colors.purple.shade600;
        icon = Icons.sync_rounded;
        break;
      case 'shipped':
        color = Colors.indigo.shade600;
        icon = Icons.local_shipping_rounded;
        break;
      case 'reached':
        color = Colors.teal.shade600;
        icon = Icons.location_on_rounded;
        break;
      default:
        color = Colors.grey.shade600;
        icon = Icons.help_outline_rounded;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12, vertical: isSmallScreen ? 4 : 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: isSmallScreen ? 12 : 14),
          const SizedBox(width: 6),
          Text(
            status?.toString().toUpperCase() ?? 'UNKNOWN',
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmallScreen ? 9 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  bool _canReorder(dynamic status) {
    final statusString = status?.toString().toLowerCase() ?? '';
    return statusString == 'delivered' || statusString == 'cancelled';
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(
        order: order,
        onGenerateInvoice: () => _generateInvoice(order),
      ),
    );
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString.toString());
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]}, ${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }
}

// End of OrderHistoryScreenState class
// NEW CLASS: Reschedule Dialog Widget
class _RescheduleDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Function(Map<String, dynamic>, Map<String, dynamic>, DateTime, DateTime) onReschedule;

  const _RescheduleDialog({
    required this.order,
    required this.onReschedule,
  });

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  final supabase = Supabase.instance.client;

  // Slot data
  List<Map<String, dynamic>> pickupSlots = [];
  List<Map<String, dynamic>> deliverySlots = [];
  bool isLoadingSlots = true;

  // Selected values
  Map<String, dynamic>? selectedPickupSlot;
  Map<String, dynamic>? selectedDeliverySlot;
  DateTime selectedPickupDate = DateTime.now();
  DateTime selectedDeliveryDate = DateTime.now();

  // Dates
  late List<DateTime> pickupDates;
  late List<DateTime> deliveryDates;

  // Progress
  int currentStep = 0; // 0: pickup, 1: delivery

  // Express delivery (get from order)
  bool isExpressDelivery = false;

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _getDeliveryTypeFromOrder();
    _loadSlots();
  }

  void _initializeDates() {
    // Pickup dates: 7 days from today
    pickupDates = List.generate(7, (index) => DateTime.now().add(Duration(days: index)));

    // Delivery dates: Initially same as pickup, will be updated when pickup date is selected
    deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));
  }

  void _getDeliveryTypeFromOrder() {
    // Get delivery type from order
    final deliveryType = widget.order['delivery_type']?.toString().toLowerCase() ?? 'standard';
    isExpressDelivery = deliveryType == 'express';
  }

  Future<void> _loadSlots() async {
    try {
      final pickupResponse = await supabase
          .from('pickup_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      final deliveryResponse = await supabase
          .from('delivery_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      setState(() {
        pickupSlots = List<Map<String, dynamic>>.from(pickupResponse);
        deliverySlots = List<Map<String, dynamic>>.from(deliveryResponse);
        isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => isLoadingSlots = false);
    }
  }

  void _updateDeliveryDates() {
    // Delivery dates: 7 days starting from selected pickup date
    deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));

    // Ensure selected delivery date is not before pickup date
    if (selectedDeliveryDate.isBefore(selectedPickupDate)) {
      selectedDeliveryDate = selectedPickupDate;
    }
  }

  void _onPickupDateSelected(DateTime date) {
    setState(() {
      selectedPickupDate = date;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
      _updateDeliveryDates();
    });
  }

  void _onDeliveryDateSelected(DateTime date) {
    setState(() {
      selectedDeliveryDate = date;
      selectedDeliverySlot = null;
    });
  }

  void _onPickupSlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedPickupSlot = slot;
      selectedDeliverySlot = null;
      currentStep = 1;
      _updateDeliveryDates();

      // Auto-select next available delivery date
      DateTime? nextAvailableDate = _findNextAvailableDeliveryDate();
      if (nextAvailableDate != null) {
        selectedDeliveryDate = nextAvailableDate;
      } else {
        selectedDeliveryDate = selectedPickupDate; // Fallback to pickup date
      }
    });
  }

  void _onDeliverySlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedDeliverySlot = slot;
    });
  }

  DateTime? _findNextAvailableDeliveryDate() {
    for (int i = 0; i < deliveryDates.length; i++) {
      DateTime date = deliveryDates[i];
      if (_hasAvailableDeliverySlots(date)) {
        return date;
      }
    }
    return null;
  }
  // Get ALL pickup slots (including unavailable ones)
  List<Map<String, dynamic>> _getAllPickupSlots() {
    int selectedDayOfWeek = selectedPickupDate.weekday;

    List<Map<String, dynamic>> daySlots = pickupSlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == selectedDayOfWeek ||
          (selectedDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && selectedDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    // Sort slots by time
    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  // Get ALL delivery slots (including unavailable ones)
  List<Map<String, dynamic>> _getAllDeliverySlots() {
    if (selectedPickupSlot == null) return [];

    final deliveryDate = selectedDeliveryDate;
    int deliveryDayOfWeek = deliveryDate.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == deliveryDayOfWeek ||
          (deliveryDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && deliveryDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    // Sort slots by time
    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  // Check if pickup slot is available
  bool _isPickupSlotAvailable(Map<String, dynamic> slot) {
    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    if (!isToday) return true; // All slots available for future dates

    // For today, check if slot has passed
    final currentTime = TimeOfDay.now();
    String timeString = slot['start_time'];
    TimeOfDay slotTime = _parseTimeString(timeString);

    // Check if slot has passed
    if (slotTime.hour < currentTime.hour) return false;
    if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return false;

    return true;
  }

  bool _hasAvailableDeliverySlots(DateTime date) {
    int dayOfWeek = date.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == dayOfWeek ||
          (dayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && dayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    if (daySlots.isEmpty) return false;

    // Check if any slot would be available for this date
    for (var slot in daySlots) {
      // Create a temporary selected delivery date to test availability
      DateTime tempDeliveryDate = selectedDeliveryDate;
      selectedDeliveryDate = date;

      bool isAvailable = _isDeliverySlotAvailable(slot);

      // Restore original date
      selectedDeliveryDate = tempDeliveryDate;

      if (isAvailable) return true;
    }

    return false;
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      List<String> parts = timeString.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return TimeOfDay(hour: 0, minute: 0);
    }
  }
  bool _isDeliverySlotAvailable(Map<String, dynamic> slot) {
    if (selectedPickupSlot == null) return false;

    final pickupDate = selectedPickupDate;
    final deliveryDate = selectedDeliveryDate;

    // Check if slot has passed (only for same day as today)
    final now = DateTime.now();
    final isToday = deliveryDate.day == now.day &&
        deliveryDate.month == now.month &&
        deliveryDate.year == now.year;

    if (isToday) {
      final currentTime = TimeOfDay.now();
      String timeString = slot['start_time'];
      TimeOfDay slotTime = _parseTimeString(timeString);

      if (slotTime.hour < currentTime.hour) return false;
      if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return false;
    }

    // Apply same logic as slot selector screen
    if (!isExpressDelivery) {
      String pickupStartTime = selectedPickupSlot!['start_time'];
      String pickupEndTime = selectedPickupSlot!['end_time'];

      if (pickupStartTime == '20:00:00' && pickupEndTime == '22:00:00') {
        DateTime tomorrow = pickupDate.add(Duration(days: 1));
        if (deliveryDate.day == tomorrow.day &&
            deliveryDate.month == tomorrow.month &&
            deliveryDate.year == tomorrow.year) {
          if (slot['start_time'] == '08:00:00' && slot['end_time'] == '10:00:00') {
            return false;
          }
        }
      }

      if (pickupDate.day == deliveryDate.day &&
          pickupDate.month == deliveryDate.month &&
          pickupDate.year == deliveryDate.year) {

        List<Map<String, dynamic>> allDaySlots = deliverySlots.where((s) {
          int slotDayOfWeek = s['day_of_week'] ?? 0;
          int dayOfWeek = deliveryDate.weekday;
          return slotDayOfWeek == dayOfWeek ||
              (dayOfWeek == 7 && slotDayOfWeek == 0) ||
              (slotDayOfWeek == 7 && dayOfWeek == 0);
        }).toList();

        int pickupSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['start_time'] == selectedPickupSlot!['start_time'] &&
              allDaySlots[i]['end_time'] == selectedPickupSlot!['end_time']) {
            pickupSlotIndex = i;
            break;
          }
        }

        int currentSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['id'] == slot['id']) {
            currentSlotIndex = i;
            break;
          }
        }

        if (pickupSlotIndex != -1 && currentSlotIndex != -1) {
          if (currentSlotIndex <= pickupSlotIndex + 1) {
            return false;
          }
        }
      }
    } else {
      if (pickupDate.day == deliveryDate.day &&
          pickupDate.month == deliveryDate.month &&
          pickupDate.year == deliveryDate.year) {

        List<Map<String, dynamic>> allDaySlots = deliverySlots.where((s) {
          int slotDayOfWeek = s['day_of_week'] ?? 0;
          int dayOfWeek = deliveryDate.weekday;
          return slotDayOfWeek == dayOfWeek ||
              (dayOfWeek == 7 && slotDayOfWeek == 0) ||
              (slotDayOfWeek == 7 && dayOfWeek == 0);
        }).toList();

        int pickupSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['start_time'] == selectedPickupSlot!['start_time'] &&
              allDaySlots[i]['end_time'] == selectedPickupSlot!['end_time']) {
            pickupSlotIndex = i;
            break;
          }
        }

        int currentSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['id'] == slot['id']) {
            currentSlotIndex = i;
            break;
          }
        }

        if (pickupSlotIndex != -1 && currentSlotIndex != -1) {
          if (currentSlotIndex <= pickupSlotIndex) {
            return false;
          }
        }
      }
    }

    return true;
  }

  void _goBackToPickup() {
    setState(() {
      currentStep = 0;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
    });
  }

  void _handleConfirmReschedule() {
    if (selectedPickupSlot != null && selectedDeliverySlot != null) {
      Navigator.pop(context); // Close dialog
      widget.onReschedule(
        selectedPickupSlot!,
        selectedDeliverySlot!,
        selectedPickupDate,
        selectedDeliveryDate,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        width: MediaQuery.of(context).size.width * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reschedule Order',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Order #${widget.order['id'].toString().substring(0, 8)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Progress Indicator
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: currentStep >= 0 ? kPrimaryColor : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      selectedPickupSlot != null ? Icons.check : Icons.schedule,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      selectedDeliverySlot != null ? Icons.check : Icons.local_shipping,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: isLoadingSlots
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: kPrimaryColor),
                    const SizedBox(height: 16),
                    const Text('Loading available slots...'),
                  ],
                ),
              )
                  : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (currentStep == 0) ...[
                      _buildDateSelector(true),
                      const SizedBox(height: 16),
                      _buildSlotsSection(true),
                    ],
                    if (currentStep == 1) ...[
                      _buildDateSelector(false),
                      const SizedBox(height: 16),
                      _buildSlotsSection(false),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  if (currentStep == 1)
                    Expanded(
                      child: TextButton(
                        onPressed: _goBackToPickup,
                        child: const Text('Back to Pickup'),
                      ),
                    ),
                  if (currentStep == 1) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (currentStep == 0 && selectedPickupSlot != null) ||
                          (currentStep == 1 && selectedDeliverySlot != null)
                          ? (currentStep == 0 ? null : _handleConfirmReschedule)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        currentStep == 1 && selectedDeliverySlot != null
                            ? 'Confirm'
                            : currentStep == 0
                            ? 'Continue'
                            : 'Select Delivery Slot',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(bool isPickup) {
    DateTime selectedDate = isPickup ? selectedPickupDate : selectedDeliveryDate;
    List<DateTime> dates = isPickup ? pickupDates : deliveryDates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today, color: kPrimaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              'Select ${isPickup ? 'Pickup' : 'Delivery'} Date',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            itemBuilder: (context, index) {
              final date = dates[index];
              final isSelected = date.day == selectedDate.day &&
                  date.month == selectedDate.month &&
                  date.year == selectedDate.year;
              final isToday = date.day == DateTime.now().day &&
                  date.month == DateTime.now().month &&
                  date.year == DateTime.now().year;

              bool isDisabled = false;
              if (!isPickup) {
                isDisabled = date.isBefore(selectedPickupDate);
              }

              return GestureDetector(
                onTap: isDisabled ? null : () {
                  if (isPickup) {
                    _onPickupDateSelected(date);
                  } else {
                    _onDeliveryDateSelected(date);
                  }
                },
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? Colors.grey.shade200
                        : isSelected ? kPrimaryColor : Colors.white,
                    border: Border.all(
                      color: isDisabled
                          ? Colors.grey.shade300
                          : isSelected ? kPrimaryColor : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getDayName(date.weekday),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDisabled
                              ? Colors.grey.shade500
                              : isSelected ? Colors.white : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date.day.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDisabled
                              ? Colors.grey.shade500
                              : isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDisabled
                                ? Colors.grey.shade400
                                : isSelected ? Colors.white : kPrimaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: isDisabled
                                  ? Colors.white
                                  : isSelected ? kPrimaryColor : Colors.white,
                            ),
                          ),
                        )
                      else
                        Text(
                          _getMonthName(date.month),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white70 : Colors.black45,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlotsSection(bool isPickup) {
    // Show ALL slots (including unavailable ones) like SlotSelectorScreen
    List<Map<String, dynamic>> slots = isPickup
        ? _getAllPickupSlots()  // Show all pickup slots
        : _getAllDeliverySlots(); // Show all delivery slots

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!isPickup)
              IconButton(
                onPressed: _goBackToPickup,
                icon: const Icon(Icons.arrow_back, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (!isPickup) const SizedBox(width: 8),
            Icon(
              isPickup ? Icons.schedule : Icons.local_shipping,
              color: kPrimaryColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '${isPickup ? 'Pickup' : 'Delivery'} ${isExpressDelivery ? '(Express)' : '(Standard)'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.schedule, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No ${isPickup ? 'pickup' : 'delivery'} slots available',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              bool isSelected = isPickup
                  ? (selectedPickupSlot?['id'] == slot['id'])
                  : (selectedDeliverySlot?['id'] == slot['id']);

              // Check if slot is available like SlotSelectorScreen
              bool isSlotAvailable = isPickup
                  ? _isPickupSlotAvailable(slot)
                  : _isDeliverySlotAvailable(slot);

              return GestureDetector(
                onTap: !isSlotAvailable ? null : () {  // Disable tap for unavailable slots
                  if (isPickup) {
                    _onPickupSlotSelected(slot);
                  } else {
                    _onDeliverySlotSelected(slot);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    // Gray out unavailable slots
                    color: !isSlotAvailable
                        ? Colors.grey.shade100
                        : isSelected ? kPrimaryColor : Colors.white,
                    border: Border.all(
                      color: !isSlotAvailable
                          ? Colors.grey.shade300
                          : isSelected ? kPrimaryColor : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          slot['display_time'] ?? '${slot['start_time']} - ${slot['end_time']}',
                          style: TextStyle(
                            // Gray out text for unavailable slots
                            color: !isSlotAvailable
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        // Show "Unavailable" text like SlotSelectorScreen
                        if (!isSlotAvailable)
                          Text(
                            'Unavailable',
                            style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  String _getDayName(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[month - 1];
  }
}

// End of _RescheduleDialog class
// Enhanced Order Details Sheet with Premium Design
class _OrderDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onGenerateInvoice;

  const _OrderDetailsSheet({
    required this.order,
    required this.onGenerateInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final addressInfo = order['address_info'] ?? order['address_details'];
    final billingDetails = order['order_billing_details'] != null &&
        (order['order_billing_details'] as List).isNotEmpty
        ? (order['order_billing_details'] as List)[0]
        : null;

    // ✅ RESPONSIVE: Get screen dimensions for universal phone display
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      // ✅ FIX: Use flexible height with constraints
      constraints: BoxConstraints(
        maxHeight: screenSize.height * 0.95,
        minHeight: screenSize.height * 0.5,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_rounded,
                      color: Colors.white, size: isSmallScreen ? 18 : 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Details',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      // 🔧 CHANGED: show only the full ID (no "Order #" and no substring)
                      Text(
                        order['id']?.toString() ?? 'N/A',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.close_rounded,
                        size: isSmallScreen ? 18 : 20),
                  ),
                ),
              ],
            ),
          ),

          // ✅ FIX: Flexible content with proper scrolling
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: isSmallScreen ? 16 : 20,
                right: isSmallScreen ? 16 : 20,
                bottom: bottomPadding + 20, // ✅ Add safe area padding
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Items Section
                  _buildSectionHeader(
                      'Order Items', Icons.shopping_bag_outlined, isSmallScreen),
                  const SizedBox(height: 12),
                  ...orderItems
                      .map((item) => _buildOrderItem(item, isSmallScreen))
                      .toList(),

                  const SizedBox(height: 24),

                  // Bill Details Section with Invoice Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long,
                              color: kPrimaryColor,
                              size: isSmallScreen ? 18 : 20),
                          const SizedBox(width: 8),
                          Text(
                            'Bill Details',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        height: isSmallScreen ? 32 : 36,
                        child: ElevatedButton.icon(
                          onPressed: onGenerateInvoice,
                          icon: Icon(Icons.picture_as_pdf,
                              size: isSmallScreen ? 14 : 16,
                              color: Colors.white),
                          label: Text(
                            'Get Invoice',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kPrimaryColor.withOpacity(0.05),
                          Colors.purple.withOpacity(0.02)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        if (billingDetails != null) ...[
                          _buildBillRow(
                              'Subtotal',
                              '₹${billingDetails['subtotal'] ?? '0.00'}',
                              isSmallScreen: isSmallScreen),
                          if ((billingDetails['minimum_cart_fee'] ?? 0) > 0)
                            _buildBillRow(
                                'Minimum Cart Fee',
                                '₹${billingDetails['minimum_cart_fee']}',
                                isSmallScreen: isSmallScreen),
                          if ((billingDetails['platform_fee'] ?? 0) > 0)
                            _buildBillRow(
                                'Platform Fee',
                                '₹${billingDetails['platform_fee']}',
                                isSmallScreen: isSmallScreen),
                          if ((billingDetails['service_tax'] ?? 0) > 0)
                            _buildBillRow(
                                'Service Tax',
                                '₹${billingDetails['service_tax']}',
                                isSmallScreen: isSmallScreen),
                          if ((billingDetails['delivery_fee'] ?? 0) > 0)
                            _buildBillRow(
                                'Delivery Fee',
                                '₹${billingDetails['delivery_fee']}',
                                isSmallScreen: isSmallScreen),
                          if ((billingDetails['discount_amount'] ?? 0) > 0)
                            _buildBillRow(
                                'Discount',
                                '-₹${billingDetails['discount_amount']}',
                                isDiscount: true,
                                isSmallScreen: isSmallScreen),
                          if (billingDetails['applied_coupon_code'] != null)
                            _buildBillRow(
                                'Coupon',
                                billingDetails['applied_coupon_code']
                                    .toString(),
                                isInfo: true,
                                isSmallScreen: isSmallScreen),
                          const Divider(height: 24, thickness: 1),
                          _buildBillRow(
                              'Total Amount',
                              '₹${billingDetails['total_amount'] ?? order['total_amount'] ?? '0.00'}',
                              isTotal: true,
                              isSmallScreen: isSmallScreen),
                        ] else ...[
                          _buildBillRow('Total Amount',
                              '₹${order['total_amount'] ?? '0.00'}',
                              isTotal: true, isSmallScreen: isSmallScreen),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Method',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: isSmallScreen ? 12 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                order['payment_method']
                                    ?.toString()
                                    .toUpperCase() ??
                                    'N/A',
                                style: TextStyle(
                                  color: kPrimaryColor,
                                  fontSize: isSmallScreen ? 12 : 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Delivery Address
                  if (addressInfo != null) ...[
                    _buildSectionHeader('Delivery Address', Icons.location_on,
                        isSmallScreen),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            kPrimaryColor.withOpacity(0.05),
                            Colors.purple.withOpacity(0.02)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person,
                                  color: kPrimaryColor,
                                  size: isSmallScreen ? 16 : 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  addressInfo['recipient_name'] ?? 'N/A',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: isSmallScreen ? 14 : 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${addressInfo['address_line_1'] ?? ''}\n${addressInfo['city'] ?? ''}, ${addressInfo['state'] ?? ''} - ${addressInfo['pincode'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: isSmallScreen ? 12 : 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ✅ NEW: Order Timeline with Slot Details
                  _buildSectionHeader(
                      'Order Timeline', Icons.timeline, isSmallScreen),
                  const SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor.withOpacity(0.8), kPrimaryColor],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildTimelineRow('Order Placed',
                            _formatDate(order['created_at']), isSmallScreen),
                        // Show pickup slot details
                        if (order['pickup_date'] != null &&
                            order['pickup_slot'] != null) ...[
                          const SizedBox(height: 12),
                          _buildTimelineRowWithSlot(
                              'Pickup Scheduled',
                              _formatDate(order['pickup_date']),
                              order['pickup_slot']['display_time'] ??
                                  '${order['pickup_slot']['start_time']} - ${order['pickup_slot']['end_time']}',
                              isSmallScreen),
                        ],
                        // Show delivery slot details
                        if (order['delivery_date'] != null &&
                            order['delivery_slot'] != null) ...[
                          const SizedBox(height: 12),
                          _buildTimelineRowWithSlot(
                              'Delivery Scheduled',
                              _formatDate(order['delivery_date']),
                              order['delivery_slot']['display_time'] ??
                                  '${order['delivery_slot']['start_time']} - ${order['delivery_slot']['end_time']}',
                              isSmallScreen),
                        ],
                        // Show delivery type
                        if (order['delivery_type'] != null) ...[
                          const SizedBox(height: 12),
                          _buildTimelineRow('Service Type',
                              order['delivery_type'].toString().toUpperCase(),
                              isSmallScreen),
                        ],
                      ],
                    ),
                  ),

                  // ✅ FIX: Extra bottom spacing for safe scrolling
                  SizedBox(height: isSmallScreen ? 60 : 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, bool isSmallScreen) {
    return Row(
      children: [
        Icon(icon, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow(String label, String value, bool isSmallScreen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: isSmallScreen ? 14 : 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // Timeline row with slot details
  Widget _buildTimelineRowWithSlot(
      String label, String date, String slot, bool isSmallScreen) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              date,
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                slot,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 10 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBillRow(String label, String value,
      {bool isTotal = false,
        bool isDiscount = false,
        bool isInfo = false,
        required bool isSmallScreen}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize:
                isTotal ? (isSmallScreen ? 14 : 16) : (isSmallScreen ? 12 : 14),
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                color: isTotal ? Colors.black : Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize:
              isTotal ? (isSmallScreen ? 16 : 18) : (isSmallScreen ? 12 : 14),
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: isTotal
                  ? kPrimaryColor
                  : isDiscount
                  ? Colors.green
                  : isInfo
                  ? kPrimaryColor
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item, bool isSmallScreen) {
    final product = item['products'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: product?['image_url'] != null &&
                  product['image_url'].toString().isNotEmpty &&
                  product['image_url'].toString() != 'null'
                  ? Image.network(
                product['image_url'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    padding:
                    EdgeInsets.all(isSmallScreen ? 12 : 16),
                    child: Icon(Icons.image_not_supported_outlined,
                        color: Colors.grey.shade400,
                        size: isSmallScreen ? 20 : 24),
                  );
                },
                loadingBuilder:
                    (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes !=
                          null
                          ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: kPrimaryColor,
                    ),
                  );
                },
              )
                  : Container(
                padding:
                EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Icon(Icons.shopping_bag_outlined,
                    color: Colors.grey.shade400,
                    size: isSmallScreen ? 20 : 24),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Product Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product?['name']?.toString() ?? 'Unknown Product',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmallScreen ? 13 : 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Quantity: ${item['quantity'] ?? 1}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: isSmallScreen ? 11 : 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '₹${product?['price'] ?? item['product_price'] ?? '0.00'} each',
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontSize: isSmallScreen ? 12 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item['service_type'] ?? 'Standard',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: isSmallScreen ? 9 : 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Item Total
          Text(
            '₹${item['total_price']?.toString() ?? '0.00'}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: isSmallScreen ? 14 : 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString.toString());
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${date.day} ${months[date.month - 1]}, ${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }
}




class _CancellationReasonDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onCancel;
  final Function(String reason, int? reasonId) onConfirm;

  const _CancellationReasonDialog({
    required this.order,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<_CancellationReasonDialog> createState() => _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<_CancellationReasonDialog>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _customReasonController = TextEditingController();

  List<Map<String, dynamic>> cancellationReasons = [];
  bool isLoadingReasons = true;
  int? selectedReasonId;
  String? selectedReasonText;
  bool showCustomInput = false;
  bool isSubmitting = false;
  bool isDropdownOpen = false;

  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _loadCancellationReasons();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _customReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadCancellationReasons() async {
    try {
      final response = await supabase
          .from('cancellation_reasons')
          .select('*')
          .eq('is_active', true)
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          cancellationReasons = List<Map<String, dynamic>>.from(response);
          isLoadingReasons = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error loading cancellation reasons: $e');
      if (mounted) {
        setState(() {
          isLoadingReasons = false;
        });
      }
    }
  }

  void _onReasonSelected(int reasonId, String reasonText) {
    setState(() {
      selectedReasonId = reasonId;
      selectedReasonText = reasonText;
      isDropdownOpen = false;
      showCustomInput = reasonText.toLowerCase().contains('other');
      if (!showCustomInput) {
        _customReasonController.clear();
      }
    });
  }

  void _handleSubmit() async {
    if (selectedReasonId == null) {
      _showSnackBar('Please select a reason for cancellation', Colors.red);
      return;
    }

    String finalReason;
    if (showCustomInput) {
      if (_customReasonController.text.trim().isEmpty) {
        _showSnackBar('Please specify your reason', Colors.red);
        return;
      }
      finalReason = _customReasonController.text.trim();
    } else {
      finalReason = selectedReasonText!;
    }

    setState(() => isSubmitting = true);

    try {
      await widget.onConfirm(finalReason, selectedReasonId);
    } catch (e) {
      setState(() => isSubmitting = false);
      _showSnackBar('Failed to cancel order. Please try again.', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).viewPadding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.black.withOpacity(0.6),
            child: SafeArea(
              child: Transform.translate(
                offset: Offset(0, _slideAnimation.value * screenSize.height * 0.3),
                child: Center(
                  child: Container(
                    margin: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: keyboardHeight > 0 ? keyboardHeight + 20 : safeAreaBottom + 20,
                    ),
                    constraints: BoxConstraints(
                      maxHeight: screenSize.height * 0.85,
                      maxWidth: 420,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Premium Header
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFFF6B6B),
                                Colors.red.shade600,
                                const Color(0xFFFF6B9D),
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.warning_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Cancel Order',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Order #${widget.order['id'].toString().substring(0, 8)}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: IconButton(
                                      onPressed: widget.onCancel,
                                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Please select a reason for cancelling your order',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Content Section
                        Flexible(
                          child: isLoadingReasons
                              ? Container(
                            padding: const EdgeInsets.all(60),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFFF6B6B).withOpacity(0.1),
                                        Colors.red.shade600.withOpacity(0.1),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const CircularProgressIndicator(
                                    color: Color(0xFFFF6B6B),
                                    strokeWidth: 3,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Loading reasons...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                              : SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Premium Dropdown
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.grey.shade50,
                                        Colors.white,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selectedReasonId != null
                                          ? const Color(0xFFFF6B6B).withOpacity(0.3)
                                          : Colors.grey.shade200,
                                      width: selectedReasonId != null ? 2 : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: selectedReasonId != null
                                            ? const Color(0xFFFF6B6B).withOpacity(0.1)
                                            : Colors.grey.withOpacity(0.08),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // Dropdown Header
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              isDropdownOpen = !isDropdownOpen;
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(20),
                                          child: Container(
                                            padding: const EdgeInsets.all(20),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: selectedReasonId != null
                                                          ? [const Color(0xFFFF6B6B), Colors.red.shade600]
                                                          : [Colors.grey.shade300, Colors.grey.shade400],
                                                    ),
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  child: const Icon(
                                                    Icons.format_list_bulleted_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'Cancellation Reason',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: Colors.grey.shade600,
                                                          letterSpacing: 0.8,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        selectedReasonText ?? 'Choose a reason',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                          color: selectedReasonId != null
                                                              ? Colors.black87
                                                              : Colors.grey.shade500,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                AnimatedRotation(
                                                  turns: isDropdownOpen ? 0.5 : 0.0,
                                                  duration: const Duration(milliseconds: 300),
                                                  child: Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFFF6B6B).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: const Icon(
                                                      Icons.keyboard_arrow_down_rounded,
                                                      color: Color(0xFFFF6B6B),
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Dropdown Options with Animation (capped & scrollable)
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 350),
                                        curve: Curves.easeInOutCubic,
                                        // Cap height to avoid RenderFlex overflow; list inside will scroll if needed
                                        height: isDropdownOpen
                                            ? min(6, cancellationReasons.length) * 56.0
                                            : 0,
                                        clipBehavior: Clip.hardEdge,
                                        decoration: const BoxDecoration(
                                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                                        ),
                                        child: isDropdownOpen
                                            ? Container(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.grey.shade100,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            itemCount: cancellationReasons.length,
                                            itemBuilder: (context, index) {
                                              final reason = cancellationReasons[index];
                                              final isSelected = selectedReasonId == reason['id'];
                                              final isLast = index == cancellationReasons.length - 1;

                                              return Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () => _onReasonSelected(
                                                      reason['id'], reason['reason_text']),
                                                  borderRadius: isLast
                                                      ? const BorderRadius.vertical(
                                                      bottom: Radius.circular(20))
                                                      : null,
                                                  child: Container(
                                                    height: 56,
                                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                                    decoration: BoxDecoration(
                                                      color: isSelected
                                                          ? const Color(0xFFFF6B6B).withOpacity(0.08)
                                                          : Colors.transparent,
                                                      border: !isLast
                                                          ? Border(
                                                        bottom: BorderSide(
                                                          color: Colors.grey.shade100,
                                                          width: 0.5,
                                                        ),
                                                      )
                                                          : null,
                                                      borderRadius: isLast
                                                          ? const BorderRadius.vertical(
                                                          bottom: Radius.circular(20))
                                                          : null,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        AnimatedContainer(
                                                          duration:
                                                          const Duration(milliseconds: 200),
                                                          width: 20,
                                                          height: 20,
                                                          decoration: BoxDecoration(
                                                            gradient: isSelected
                                                                ? LinearGradient(colors: [
                                                              const Color(0xFFFF6B6B),
                                                              Colors.red.shade600
                                                            ])
                                                                : null,
                                                            color: isSelected
                                                                ? null
                                                                : Colors.transparent,
                                                            border: Border.all(
                                                              color: isSelected
                                                                  ? const Color(0xFFFF6B6B)
                                                                  : Colors.grey.shade400,
                                                              width: 2,
                                                            ),
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: isSelected
                                                              ? const Icon(Icons.check_rounded,
                                                              color: Colors.white, size: 12)
                                                              : null,
                                                        ),
                                                        const SizedBox(width: 16),
                                                        Expanded(
                                                          child: Text(
                                                            reason['reason_text'],
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight: isSelected
                                                                  ? FontWeight.w600
                                                                  : FontWeight.w500,
                                                              color: isSelected
                                                                  ? const Color(0xFFFF6B6B)
                                                                  : Colors.black87,
                                                            ),
                                                          ),
                                                        ),
                                                        if (isSelected)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                                horizontal: 10, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              gradient: LinearGradient(colors: [
                                                                const Color(0xFFFF6B6B),
                                                                Colors.red.shade600
                                                              ]),
                                                              borderRadius:
                                                              BorderRadius.circular(12),
                                                            ),
                                                            child: const Text(
                                                              'SELECTED',
                                                              style: TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w700,
                                                                letterSpacing: 0.5,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ),

                                // Custom Input Section
                                if (showCustomInput) ...[
                                  const SizedBox(height: 24),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFFFF6B6B).withOpacity(0.05),
                                          Colors.red.shade600.withOpacity(0.03),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: const Color(0xFFFF6B6B).withOpacity(0.2), width: 1.5),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [const Color(0xFFFF6B6B), Colors.red.shade600],
                                                  ),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(Icons.edit_rounded,
                                                    color: Colors.white, size: 18),
                                              ),
                                              const SizedBox(width: 12),
                                              const Expanded(
                                                child: Text(
                                                  'Please specify your reason',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFFFF6B6B),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(0.1),
                                                blurRadius: 15,
                                                offset: const Offset(0, 5),
                                              ),
                                            ],
                                          ),
                                          child: TextField(
                                            controller: _customReasonController,
                                            maxLines: 4,
                                            maxLength: 200,
                                            decoration: InputDecoration(
                                              hintText: 'Enter your specific reason here...',
                                              hintStyle: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500),
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(16),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFFFF6B6B), width: 2),
                                              ),
                                              contentPadding: const EdgeInsets.all(16),
                                              counterStyle: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 12,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),

                        // Bottom Actions
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 56,
                                  child: TextButton(
                                    onPressed: isSubmitting ? null : widget.onCancel,
                                    style: TextButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: BorderSide(color: Colors.grey.shade300, width: 2),
                                      ),
                                      backgroundColor: Colors.white,
                                    ),
                                    child: Text(
                                      'Keep Order',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [const Color(0xFFFF6B6B), Colors.red.shade600],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF6B6B).withOpacity(0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isSubmitting ? null : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: isSubmitting
                                        ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                        : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.cancel_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Cancel',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _CancellationSuccessDialog extends StatefulWidget {
  @override
  State<_CancellationSuccessDialog> createState() => _CancellationSuccessDialogState();
}

class _CancellationSuccessDialogState extends State<_CancellationSuccessDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _checkController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _checkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.easeIn),
    );

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await _scaleController.forward();
    await _checkController.forward();

    // Auto close after 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleController, _checkController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade400, Colors.red.shade600],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Transform.scale(
                      scale: _checkAnimation.value,
                      child: const Icon(
                        Icons.cancel_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Order Cancelled!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your order has been successfully cancelled',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}