import 'dart:async';
import 'dart:io';
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

      // Get orders from past 30 days
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      final ordersResponse = await supabase
          .from('orders')
          .select('*')
          .eq('user_id', user.id)
          .gte('created_at', thirtyDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      print('Found ${ordersResponse.length} orders from past 30 days');

      List<Map<String, dynamic>> ordersWithDetails = [];

      for (var order in ordersResponse) {
        Map<String, dynamic> orderWithDetails = Map<String, dynamic>.from(order);

        try {
          // ✅ FIXED: Get order items with product_image directly
          final orderItemsResponse = await supabase
              .from('order_items')
              .select('*, product_image') // ✅ Include product_image from order_items
              .eq('order_id', order['id']);

          print('Found ${orderItemsResponse.length} items for order ${order['id']}');

          // Process order items
          List<Map<String, dynamic>> processedItems = [];
          for (var item in orderItemsResponse) {
            Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);

            // ✅ FIXED: Use product_image from order_items first, then fallback to products table
            String? productImageUrl = item['product_image']; // From order_items

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
                    // ✅ FIXED: Use order_items image first, then products table image
                    'image_url': productImageUrl ?? productResponse['image_url'],
                    'price': productResponse['product_price'],
                    'category_id': productResponse['category_id'],
                  };
                } else {
                  // Fallback product data
                  processedItem['products'] = {
                    'id': item['product_id'],
                    'name': item['product_name'] ?? 'Product ${item['product_id']}',
                    'image_url': productImageUrl, // ✅ Use from order_items
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
                  'image_url': productImageUrl, // ✅ Use from order_items
                  'price': item['product_price'] ?? 0.0,
                  'category_id': null,
                };
              }
            } else {
              // No product_id, use item data
              processedItem['products'] = {
                'id': null,
                'name': item['product_name'] ?? 'Unknown Product',
                'image_url': productImageUrl, // ✅ Use from order_items
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

          // Get billing details if available
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

          // Get pickup slot details for cancel timer
          if (order['pickup_slot_id'] != null) {
            try {
              final pickupSlotResponse = await supabase
                  .from('pickup_slots')
                  .select('start_time, end_time, display_time')
                  .eq('id', order['pickup_slot_id'])
                  .maybeSingle();

              if (pickupSlotResponse != null) {
                orderWithDetails['pickup_slot'] = pickupSlotResponse;
              }
            } catch (e) {
              print('Error loading pickup slot for order ${order['id']}: $e');
            }
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
                // ✅ FIXED: Use product image from order first, then from products table
                final imageUrl = product['image_url'] ?? productCheck['image_url'];

                // Add item to cart with same service type
                await supabase.from('cart').insert({
                  'user_id': user.id,
                  'product_name': productCheck['product_name'],
                  'product_image': imageUrl, // ✅ Use correct image URL
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
                'product_image': product['image_url'], // ✅ Use image from order
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
    final status = order['status']?.toString().toLowerCase() ??
        order['order_status']?.toString().toLowerCase() ?? '';
    return status == 'pending' || status == 'confirmed';
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
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Cancel Order',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this order?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Order #${order['id'].toString().substring(0, 8)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: kPrimaryColor,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancellation is only allowed up to 1 hour before pickup time.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Keep Order',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel Order',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await _performOrderCancellation(order);
    }
  }

  Future<void> _performOrderCancellation(Map<String, dynamic> order) async {
    try {
      // Show loading overlay
      _showLoadingDialog('Cancelling your order...');

      // Update order status to cancelled
      await supabase
          .from('orders')
          .update({
        'status': 'cancelled',
        'order_status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', order['id']);

      // Stop the timer for this order
      final orderId = order['id'].toString();
      _cancelTimers[orderId]?.cancel();
      _cancelTimers.remove(orderId);
      _cancelTimeRemaining.remove(orderId);

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Show success message
      _showSuccessSnackBar('Order cancelled successfully');

      // Reload orders
      await _loadOrders();

    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      print('Error cancelling order: $e');
      _showErrorSnackBar('Failed to cancel order');
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Order History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_rounded, color: kPrimaryColor, size: 16),
          ),
        ),
      ),
      body: isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimaryColor),
            const SizedBox(height: 16),
            const Text(
              'Loading your orders...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      )
          : orders.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor.withOpacity(0.1), Colors.purple.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.shopping_bag_outlined,
                size: 80,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Orders in Last 30 Days',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your recent order history will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Navigate to home
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              child: const Text(
                'Start Shopping',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      )
          : FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          color: kPrimaryColor,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              return _buildEnhancedOrderCard(orders[index], index);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedOrderCard(Map<String, dynamic> order, int index) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final totalItems = orderItems.length;
    final firstProduct = orderItems.isNotEmpty ? orderItems[0] : null;
    final orderId = order['id'].toString();
    final canCancel = _canShowCancelButton(order);
    final remainingTime = _getRemainingCancelTime(orderId);

    return Container(
      margin: EdgeInsets.only(bottom: 16, top: index == 0 ? 8 : 0),
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
            padding: const EdgeInsets.all(20),
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
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Order #${order['id'].toString().substring(0, 8)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(order['created_at']),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Show countdown timer for cancellable orders, otherwise show status badge
                    canCancel && remainingTime > 0
                        ? _buildCountdownBadge(remainingTime)
                        : _buildStatusBadge(order['status'] ?? order['order_status']),
                  ],
                ),

                const SizedBox(height: 16),

                // Product Preview with proper image handling
                if (firstProduct != null && firstProduct['products'] != null) ...[
                  Row(
                    children: [
                      // Product Image
                      Container(
                        width: 60,
                        height: 60,
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
                              padding: const EdgeInsets.all(16),
                              child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey.shade400,
                                  size: 24
                              ),
                            ),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                  strokeWidth: 2,
                                  color: kPrimaryColor,
                                ),
                              );
                            },
                          )
                              : Container(
                            padding: const EdgeInsets.all(16),
                            child: Icon(
                                Icons.shopping_bag_outlined,
                                color: Colors.grey.shade400,
                                size: 24
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Qty: ${firstProduct['quantity'] ?? 1} • ${firstProduct['service_type'] ?? 'Standard'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (totalItems > 1) ...[
                              const SizedBox(height: 2),
                              Text(
                                '+${totalItems - 1} more item${totalItems > 2 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
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
                  const SizedBox(height: 16),
                ],

                // Order Summary
                Container(
                  padding: const EdgeInsets.all(16),
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
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${order['total_amount'] ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 18,
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
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '$totalItems',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action Buttons Row - FIXED CANCEL BUTTON LOGIC
                Row(
                  children: [
                    // View Details Button
                    Expanded(
                      child: Container(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => _showOrderDetails(order),
                          icon: Icon(Icons.visibility_rounded, size: 18, color: kPrimaryColor),
                          label: Text(
                            'View Details',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor.withOpacity(0.1),
                            foregroundColor: kPrimaryColor,
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
                        height: 48,
                        child: canCancel
                            ? ElevatedButton.icon(
                          // Button is enabled only when there's remaining time
                          onPressed: remainingTime > 0 ? () => _cancelOrder(order) : null,
                          icon: Icon(
                            remainingTime > 0 ? Icons.cancel_outlined : Icons.block,
                            size: 18,
                            color: remainingTime > 0 ? Colors.white : Colors.grey.shade500,
                          ),
                          label: Text(
                            remainingTime > 0 ? 'Cancel Order' : 'Cancel Timeout',
                            style: TextStyle(
                              color: remainingTime > 0 ? Colors.white : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
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
                            : (_canReorder(order['status'] ?? order['order_status'])
                            ? ElevatedButton.icon(
                          onPressed: () => _reorderItems(order),
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                          label: const Text(
                            'Reorder',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
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
                          icon: Icon(Icons.info_outline, size: 18, color: Colors.grey.shade500),
                          label: Text(
                            'Order ${(order['status'] ?? order['order_status'] ?? 'Processing').toString().toLowerCase()}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
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

  Widget _buildCountdownBadge(int remainingTime) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          const Icon(Icons.timer, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            _formatRemainingTime(remainingTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(dynamic status) {
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
      default:
        color = Colors.grey.shade600;
        icon = Icons.help_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            status?.toString().toUpperCase() ?? 'UNKNOWN',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
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
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Order #${order['id'].toString().substring(0, 8)}',
                        style: TextStyle(
                          fontSize: 14,
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
                    child: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order Items Section
                  _buildSectionHeader('Order Items', Icons.shopping_bag_outlined),
                  const SizedBox(height: 12),
                  ...orderItems.map((item) => _buildOrderItem(item)).toList(),

                  const SizedBox(height: 24),

                  // Bill Details Section with Invoice Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long, color: kPrimaryColor, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Bill Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: onGenerateInvoice,
                          icon: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
                          label: const Text(
                            'Get Invoice',
                            style: TextStyle(
                              fontSize: 14,
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
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor.withOpacity(0.05), Colors.purple.withOpacity(0.02)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        if (billingDetails != null) ...[
                          _buildBillRow('Subtotal', '₹${billingDetails['subtotal'] ?? '0.00'}'),
                          if ((billingDetails['minimum_cart_fee'] ?? 0) > 0)
                            _buildBillRow('Minimum Cart Fee', '₹${billingDetails['minimum_cart_fee']}'),
                          if ((billingDetails['platform_fee'] ?? 0) > 0)
                            _buildBillRow('Platform Fee', '₹${billingDetails['platform_fee']}'),
                          if ((billingDetails['service_tax'] ?? 0) > 0)
                            _buildBillRow('Service Tax', '₹${billingDetails['service_tax']}'),
                          if ((billingDetails['delivery_fee'] ?? 0) > 0)
                            _buildBillRow('Delivery Fee', '₹${billingDetails['delivery_fee']}'),
                          if ((billingDetails['discount_amount'] ?? 0) > 0)
                            _buildBillRow('Discount', '-₹${billingDetails['discount_amount']}', isDiscount: true),
                          if (billingDetails['applied_coupon_code'] != null)
                            _buildBillRow('Coupon', billingDetails['applied_coupon_code'].toString(), isInfo: true),
                          const Divider(height: 24, thickness: 1),
                          _buildBillRow('Total Amount', '₹${billingDetails['total_amount'] ?? order['total_amount'] ?? '0.00'}', isTotal: true),
                        ] else ...[
                          _buildBillRow('Total Amount', '₹${order['total_amount'] ?? '0.00'}', isTotal: true),
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                order['payment_method']?.toString().toUpperCase() ?? 'N/A',
                                style: TextStyle(
                                  color: kPrimaryColor,
                                  fontSize: 14,
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
                    _buildSectionHeader('Delivery Address', Icons.location_on),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kPrimaryColor.withOpacity(0.05), Colors.purple.withOpacity(0.02)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person, color: kPrimaryColor, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                addressInfo['recipient_name'] ?? 'N/A',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${addressInfo['address_line_1'] ?? ''}\n${addressInfo['city'] ?? ''}, ${addressInfo['state'] ?? ''} - ${addressInfo['pincode'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Order Timeline
                  _buildSectionHeader('Order Timeline', Icons.timeline),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildTimelineRow('Order Placed', _formatDate(order['created_at'])),
                        if (order['pickup_date'] != null) ...[
                          const SizedBox(height: 12),
                          _buildTimelineRow('Pickup Date', _formatDate(order['pickup_date'])),
                        ],
                        if (order['delivery_date'] != null) ...[
                          const SizedBox(height: 12),
                          _buildTimelineRow('Delivery Date', _formatDate(order['delivery_date'])),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: kPrimaryColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildBillRow(String label, String value, {bool isTotal = false, bool isDiscount = false, bool isInfo = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? Colors.black : Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
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

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final product = item['products'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 60,
            height: 60,
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
                    padding: const EdgeInsets.all(16),
                    child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 24),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: kPrimaryColor,
                    ),
                  );
                },
              )
                  : Container(
                padding: const EdgeInsets.all(16),
                child: Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade400, size: 24),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Quantity: ${item['quantity'] ?? 1}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item['service_type'] ?? 'Standard',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 11,
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
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]}, ${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }
}