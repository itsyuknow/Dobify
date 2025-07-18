import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Cancel order settings
  int standardDeliveryCancelMinutes = 30; // Default 30 minutes
  int expressDeliveryCancelMinutes = 15;  // Default 15 minutes

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
    _loadCancelSettings();
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

  Future<void> _loadCancelSettings() async {
    try {
      final response = await supabase
          .from('app_settings')
          .select('setting_key, setting_value')
          .inFilter('setting_key', ['standard_delivery_cancel_minutes', 'express_delivery_cancel_minutes']);

      for (var setting in response) {
        if (setting['setting_key'] == 'standard_delivery_cancel_minutes') {
          standardDeliveryCancelMinutes = int.tryParse(setting['setting_value']?.toString() ?? '30') ?? 30;
        } else if (setting['setting_key'] == 'express_delivery_cancel_minutes') {
          expressDeliveryCancelMinutes = int.tryParse(setting['setting_value']?.toString() ?? '15') ?? 15;
        }
      }

      print('Cancel settings loaded - Standard: ${standardDeliveryCancelMinutes}min, Express: ${expressDeliveryCancelMinutes}min');
    } catch (e) {
      print('Error loading cancel settings: $e');
    }
  }

  Future<void> _loadOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => isLoading = true);
      print('Loading orders for user: ${user.id}');

      // Get basic orders data
      final ordersResponse = await supabase
          .from('orders')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      print('Found ${ordersResponse.length} orders');

      List<Map<String, dynamic>> ordersWithDetails = [];

      for (var order in ordersResponse) {
        Map<String, dynamic> orderWithDetails = Map<String, dynamic>.from(order);

        try {
          // Get order items with product details
          final orderItemsResponse = await supabase
              .from('order_items')
              .select('*')
              .eq('order_id', order['id']);

          print('Found ${orderItemsResponse.length} items for order ${order['id']}');

          // Process order items
          List<Map<String, dynamic>> processedItems = [];
          for (var item in orderItemsResponse) {
            Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);

            // Get product details if product_id exists
            if (item['product_id'] != null) {
              try {
                final productResponse = await supabase
                    .from('products')
                    .select('id, name, image_url, price')
                    .eq('id', item['product_id'])
                    .maybeSingle();

                if (productResponse != null) {
                  processedItem['products'] = productResponse;
                } else {
                  // Fallback product data
                  processedItem['products'] = {
                    'id': item['product_id'],
                    'name': item['product_name'] ?? 'Product ${item['product_id']}',
                    'image_url': null,
                    'price': item['price'] ?? 0.0,
                  };
                }
              } catch (e) {
                print('Error loading product ${item['product_id']}: $e');
                // Fallback product data
                processedItem['products'] = {
                  'id': item['product_id'],
                  'name': item['product_name'] ?? 'Unknown Product',
                  'image_url': null,
                  'price': item['price'] ?? 0.0,
                };
              }
            } else {
              // No product_id, use item data
              processedItem['products'] = {
                'id': null,
                'name': item['product_name'] ?? 'Unknown Product',
                'image_url': null,
                'price': item['price'] ?? 0.0,
              };
            }

            processedItems.add(processedItem);
          }

          orderWithDetails['order_items'] = processedItems;

          // Get delivery address if available
          if (order['delivery_address_id'] != null) {
            try {
              final addressResponse = await supabase
                  .from('user_addresses')
                  .select('recipient_name, address_line_1, city, state, pincode')
                  .eq('id', order['delivery_address_id'])
                  .maybeSingle();

              if (addressResponse != null) {
                orderWithDetails['user_addresses'] = addressResponse;
              }
            } catch (e) {
              print('Error loading address for order ${order['id']}: $e');
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

  void _setupCancelTimer(Map<String, dynamic> order) {
    if (!_canShowCancelButton(order)) return;

    final orderId = order['id'].toString();
    final orderTime = DateTime.parse(order['created_at']);
    final isExpress = _isExpressDelivery(order);
    final cancelMinutes = isExpress ? expressDeliveryCancelMinutes : standardDeliveryCancelMinutes;
    final cancelDeadline = orderTime.add(Duration(minutes: cancelMinutes));
    final now = DateTime.now();

    if (now.isBefore(cancelDeadline)) {
      final remainingSeconds = cancelDeadline.difference(now).inSeconds;
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
  }

  bool _canShowCancelButton(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase() ?? '';
    return status == 'pending' || status == 'confirmed' || status == 'processing';
  }

  bool _isExpressDelivery(Map<String, dynamic> order) {
    // Check from order_billing_details
    final billingDetails = order['order_billing_details'];
    if (billingDetails != null && billingDetails is List && billingDetails.isNotEmpty) {
      final deliveryType = billingDetails[0]['delivery_type']?.toString().toLowerCase() ?? '';
      return deliveryType == 'express';
    }

    // Fallback: check if order has express in any field
    final orderString = order.toString().toLowerCase();
    return orderString.contains('express');
  }

  int _getRemainingCancelTime(String orderId) {
    return _cancelTimeRemaining[orderId] ?? 0;
  }

  String _formatRemainingTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text('Cancel Order'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to cancel this order?'),
            const SizedBox(height: 8),
            Text(
              'Order #${order['order_number'] ?? order['id']}',
              style: TextStyle(fontWeight: FontWeight.w600, color: kPrimaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Order'),
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
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: kPrimaryColor),
                const SizedBox(height: 16),
                const Text('Cancelling your order...'),
              ],
            ),
          ),
        ),
      );

      // Update order status to cancelled
      await supabase
          .from('orders')
          .update({
        'status': 'cancelled',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Order cancelled successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      // Reload orders
      await _loadOrders();

    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      print('Error cancelling order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Failed to cancel order'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
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
              'No Orders Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order history will appear here once you make your first purchase.',
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
                                'Order #${order['order_number'] ?? order['id'].toString().substring(0, 8)}',
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
                        : _buildStatusBadge(order['status']),
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
                              'Qty: ${firstProduct['quantity'] ?? 1}',
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

                const SizedBox(height: 12),

                // Action Row - Always show View Details, and Cancel Order if applicable
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _showOrderDetails(order),
                        icon: Icon(Icons.visibility_rounded, size: 18, color: kPrimaryColor),
                        label: Text(
                          'View Details',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: kPrimaryColor.withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Always show second button - Cancel Order or Reorder
                    Expanded(
                      child: canCancel
                          ? (remainingTime > 0
                          ? TextButton.icon(
                        onPressed: () => _cancelOrder(order),
                        icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                        label: const Text(
                          'Cancel Order',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      )
                          : Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.block, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              'Cannot Cancel',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ))
                          : (_canReorder(order['status'])
                          ? TextButton.icon(
                        onPressed: () => _reorderItems(order),
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.green),
                        label: const Text(
                          'Reorder',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      )
                          : Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              'Order ${order['status'] ?? 'Processing'}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )),
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
          colors: [Colors.orange, Colors.orange.withOpacity(0.8)],
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
          Icon(Icons.timer, color: Colors.white, size: 14),
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
        color = Colors.green;
        icon = Icons.check_circle_rounded;
        break;
      case 'cancelled':
        color = Colors.red;
        icon = Icons.cancel_rounded;
        break;
      case 'pending':
        color = Colors.orange;
        icon = Icons.access_time_rounded;
        break;
      case 'confirmed':
        color = Colors.blue;
        icon = Icons.check_rounded;
        break;
      case 'processing':
        color = Colors.purple;
        icon = Icons.sync_rounded;
        break;
      case 'shipped':
        color = Colors.indigo;
        icon = Icons.local_shipping_rounded;
        break;
      default:
        color = Colors.grey;
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

  void _reorderItems(Map<String, dynamic> order) {
    // Implement reorder functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Reorder functionality coming soon!'),
        backgroundColor: kPrimaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(order: order),
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

// Order Details Sheet
class _OrderDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderDetailsSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final address = order['user_addresses'];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                        'Order #${order['order_number'] ?? order['id'].toString().substring(0, 8)}',
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
                  icon: const Icon(Icons.close_rounded),
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
                  // Order Items
                  const Text(
                    'Order Items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...orderItems.map((item) => _buildOrderItem(item)),

                  const SizedBox(height: 24),

                  // Delivery Address
                  if (address != null) ...[
                    const Text(
                      'Delivery Address',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                          Text(
                            address['recipient_name'] ?? 'N/A',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${address['address_line_1'] ?? ''}\n${address['city'] ?? ''}, ${address['state'] ?? ''} - ${address['pincode'] ?? ''}',
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

                  // Order Summary
                  const Text(
                    'Order Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₹${order['total_amount'] ?? '0.00'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order Date',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatDate(order['created_at']),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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
              child: product?['image_url'] != null && product['image_url'].toString().isNotEmpty
                  ? Image.network(
                product['image_url'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(16),
                  child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 24),
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
                Text(
                  '₹${product?['price'] ?? item['price'] ?? '0.00'} each',
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
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