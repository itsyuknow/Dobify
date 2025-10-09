import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'colors.dart';
import '../screens/cart_screen.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'order_screen.dart'; // 👈 adjust path if needed
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle, ByteData;





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
  Map<String, int> _pickupTimeRemaining = {};
  Map<String, int> _deliveryTimeRemaining = {};


  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ===================== REVIEW STATE (for dialog) =====================

  int _getPickupTimeRemaining(String orderId) {
    return _pickupTimeRemaining[orderId] ?? 0;
  }

  int _getDeliveryTimeRemaining(String orderId) {
    return _deliveryTimeRemaining[orderId] ?? 0;
  }
  int _dialogSelectedRating = 0;
  List<String> _dialogSelectedFeedback = [];
  List<Map<String, dynamic>> _reviewFeedbackOptions = [];
  final TextEditingController _dialogFeedbackController = TextEditingController();

  bool _isExpressOrder(Map<String, dynamic> order) {
    // If backend already marks express
    final rawOrderExpress = order['is_express'];
    if (rawOrderExpress is bool && rawOrderExpress == true) return true;
    if (rawOrderExpress is String && rawOrderExpress.toLowerCase() == 'true') return true;

    // Other common flags some schemas use
    final deliveryType = order['delivery_type']?.toString().toLowerCase();
    if (deliveryType == 'express') return true;
    final speed = order['delivery_speed']?.toString().toLowerCase();
    if (speed == 'express') return true;

    // Infer from items if needed
    final items = order['order_items'] as List<dynamic>? ?? const [];
    for (final it in items) {
      final st = it['service_type']?.toString().toLowerCase();
      if (st == 'express') return true;
      final itemExpress = it['is_express'];
      if (itemExpress is bool && itemExpress == true) return true;
      if (itemExpress is String && itemExpress.toLowerCase() == 'true') return true;
    }

    return false;
  }

  // =====================================================================

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
    _loadReviewFeedbackOptions(); // LOAD feedback chips once
    _loadOrders();
  }

  @override
  void dispose() {
    _animationController.dispose();
    for (var timer in _cancelTimers.values) {
      timer?.cancel();
    }
    _dialogFeedbackController.dispose(); // NEW
    super.dispose();
  }

  Future<void> _loadReviewFeedbackOptions() async {
    try {
      final response = await supabase
          .from('review_feedback_options')
          .select('*')
          .order('id');
      setState(() {
        _reviewFeedbackOptions = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      // Silent fail; dialog will still work without chips
      debugPrint('Error loading review feedback options: $e');
    }
  }

  Future<void>  _loadOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => isLoading = true);
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

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
          .eq('user_id', user.id)
          .gte('created_at', thirtyDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> ordersWithDetails = [];

      for (var order in ordersResponse) {
        Map<String, dynamic> orderWithDetails = Map<String, dynamic>.from(order);

        try {
          final orderItemsResponse = await supabase
              .from('order_items')
              .select('*, product_image')
              .eq('order_id', order['id']);

          List<Map<String, dynamic>> processedItems = [];
          for (var item in orderItemsResponse) {
            Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);
            String? productImageUrl = item['product_image'];

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
                  processedItem['products'] = {
                    'id': item['product_id'],
                    'name': item['product_name'] ?? 'Product ${item['product_id']}',
                    'image_url': productImageUrl,
                    'price': item['product_price'] ?? 0.0,
                    'category_id': null,
                  };
                }
              } catch (e) {
                processedItem['products'] = {
                  'id': item['product_id'],
                  'name': item['product_name'] ?? 'Unknown Product',
                  'image_url': productImageUrl,
                  'price': item['product_price'] ?? 0.0,
                  'category_id': null,
                };
              }
            } else {
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

          orderWithDetails['is_express'] = _isExpressOrder(orderWithDetails);


          orderWithDetails['order_items'] = processedItems;

          if (order['address_details'] != null) {
            try {
              orderWithDetails['address_info'] = order['address_details'];
            } catch (e) {
              debugPrint('Error parsing address details: $e');
            }
          }

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
            debugPrint('Error loading billing details for order ${order['id']}: $e');
          }

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

          _setupCancelTimer(orderWithDetails);  // KEEP THIS
          _setupPickupTimer(orderWithDetails);
          _setupDeliveryTimer(orderWithDetails); // ADD THIS LINE

          // ===================== NEW: review existence for delivered =====================
          final statusStr = (order['order_status'] ?? '').toString().toLowerCase();
          if (statusStr == 'delivered') {
            try {
              final existingReview = await supabase
                  .from('reviews')
                  .select('id')
                  .eq('order_id', order['id'])
                  .maybeSingle();
              orderWithDetails['has_review'] = existingReview != null;
            } catch (e) {
              orderWithDetails['has_review'] = false;
            }
          } else {
            orderWithDetails['has_review'] = false;
          }
          // ==============================================================================

        } catch (e) {
          debugPrint('Error loading order items for order ${order['id']}: $e');
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
      }
    } catch (e) {
      debugPrint('Error loading orders: $e');
      if (mounted) {
        setState(() {
          orders = [];
          isLoading = false;
        });
      }
    }
  }

  void _setupPickupTimer(Map<String, dynamic> order) {
    final orderId = order['id'].toString();
    final pickupDate = order['pickup_date'];
    final pickupSlot = order['pickup_slot'];
    final status = order['order_status']?.toString().toLowerCase() ?? '';

    if (status != 'confirmed' && status != 'pickup_scheduled') return;
    if (pickupDate == null || pickupSlot == null) return;

    try {
      final pickupDateTime = DateTime.parse(pickupDate);
      // CHANGED: Use end_time instead of start_time
      final endTimeStr = pickupSlot['end_time'].toString();
      final timeParts = endTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final pickupEndTime = DateTime(
        pickupDateTime.year,
        pickupDateTime.month,
        pickupDateTime.day,
        hour,
        minute,
      );

      final now = DateTime.now();
      if (now.isBefore(pickupEndTime)) {
        final remainingSeconds = pickupEndTime.difference(now).inSeconds;
        _pickupTimeRemaining[orderId] = remainingSeconds;

        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _pickupTimeRemaining[orderId] = (_pickupTimeRemaining[orderId] ?? 0) - 1;
          });

          if ((_pickupTimeRemaining[orderId] ?? 0) <= 0) {
            timer.cancel();
            _pickupTimeRemaining.remove(orderId);
          }
        });
      }
    } catch (e) {
      debugPrint('Error setting up pickup timer: $e');
    }
  }

  Future<void> _reorderItems(Map<String, dynamic> order) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('Please login to reorder');
      return;
    }

    try {
      _showLoadingDialog('Adding items to cart...');

      final orderItems = order['order_items'] as List<dynamic>? ?? [];
      int addedItems = 0;

      await supabase.from('cart').delete().eq('user_id', user.id);

      for (var item in orderItems) {
        final product = item['products'];
        if (product != null) {
          try {
            if (product['id'] != null) {
              final productCheck = await supabase
                  .from('products')
                  .select('id, product_name, product_price, image_url, is_enabled, category_id')
                  .eq('id', product['id'])
                  .eq('is_enabled', true)
                  .maybeSingle();

              if (productCheck != null) {
                final imageUrl = product['image_url'] ?? productCheck['image_url'];
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
            debugPrint('Error adding item ${product['name']} to cart: $e');
          }
        }
      }

      if (mounted) Navigator.pop(context);

      if (addedItems > 0) {
        _showSuccessSnackBar('$addedItems items added to cart!');
        // NEW: open the cart screen
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CartScreen()),
            );
          }
        });
      } else {
        _showErrorSnackBar('No items could be added. Products may be unavailable.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error during reorder: $e');
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
      final pickupDate = DateTime.parse(orderDate);
      final startTimeStr = pickupSlot['start_time'].toString();

      final timeParts = startTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // 👉 Key change: deadline depends on Express vs Standard
      final bool isExpress = (order['is_express'] == true) || _isExpressOrder(order);

      // Standard: 1 hour before start; Express: at start
      final pickupDeadline = DateTime(
        pickupDate.year,
        pickupDate.month,
        pickupDate.day,
        hour,
        minute,
      ).subtract(isExpress ? Duration.zero : const Duration(hours: 1));

      final now = DateTime.now();

      if (now.isBefore(pickupDeadline)) {
        final remainingSeconds = pickupDeadline.difference(now).inSeconds;
        _cancelTimeRemaining[orderId] = remainingSeconds;

        _cancelTimers[orderId]?.cancel();
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
      } else {
        // Already past deadline: ensure no timer & disable cancel by clearing remaining time
        _cancelTimers[orderId]?.cancel();
        _cancelTimers.remove(orderId);
        _cancelTimeRemaining.remove(orderId);
      }
    } catch (e) {
      debugPrint('Error setting up cancel timer: $e');
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

    final orderId = order['id'].toString();
    final remainingTime = _getRemainingCancelTime(orderId);

    return remainingTime > 0;
  }

  int _getRemainingCancelTime(String orderId) {
    return _cancelTimeRemaining[orderId] ?? 0;
  }


  void _setupDeliveryTimer(Map<String, dynamic> order) {
    final orderId = order['id'].toString();
    final deliveryDate = order['delivery_date'];
    final deliverySlot = order['delivery_slot'];
    final status = order['order_status']?.toString().toLowerCase() ?? '';

    if (status != 'picked_up' && status != 'shipped' && status != 'reached') return;
    if (deliveryDate == null || deliverySlot == null) return;

    try {
      final deliveryDateTime = DateTime.parse(deliveryDate);
      // CHANGED: Use end_time instead of start_time
      final endTimeStr = deliverySlot['end_time'].toString();
      final timeParts = endTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final deliveryEndTime = DateTime(
        deliveryDateTime.year,
        deliveryDateTime.month,
        deliveryDateTime.day,
        hour,
        minute,
      );

      final now = DateTime.now();
      if (now.isBefore(deliveryEndTime)) {
        final remainingSeconds = deliveryEndTime.difference(now).inSeconds;
        _deliveryTimeRemaining[orderId] = remainingSeconds;

        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _deliveryTimeRemaining[orderId] = (_deliveryTimeRemaining[orderId] ?? 0) - 1;
          });

          if ((_deliveryTimeRemaining[orderId] ?? 0) <= 0) {
            timer.cancel();
            _deliveryTimeRemaining.remove(orderId);
          }
        });
      }
    } catch (e) {
      debugPrint('Error setting up delivery timer: $e');
    }
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
          Navigator.pop(context);
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
      _showLoadingDialog('Cancelling your order...');

      await supabase
          .from('orders')
          .update({
        'status': 'cancelled',
        'order_status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', order['id']);

      await supabase.from('order_cancellation_logs').insert({
        'order_id': order['id'],
        'user_id': user.id,
        'cancellation_reason': cancellationReason,
        'selected_reason_id': selectedReasonId,
        'cancelled_at': DateTime.now().toIso8601String(),
      });

      final orderId = order['id'].toString();
      _cancelTimers[orderId]?.cancel();
      _cancelTimers.remove(orderId);
      _cancelTimeRemaining.remove(orderId);

      if (mounted) Navigator.pop(context);

      await _showCancellationSuccessAnimation();
      await _loadOrders();

    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error cancelling order: $e');
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

  // ========================= REVIEW DIALOG FLOW =========================
  Future<void> _showReviewDialog(Map<String, dynamic> order) async {
    _dialogSelectedRating = 0;
    _dialogSelectedFeedback = [];
    _dialogFeedbackController.clear();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isSmall = MediaQuery.of(context).size.height < 700;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.star_rate_rounded, color: Colors.amber, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Rate your experience',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stars
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final s = i + 1;
                          final filled = s <= _dialogSelectedRating;
                          return IconButton(
                            onPressed: () => modalSetState(() {
                              _dialogSelectedRating = s;
                            }),
                            icon: Icon(
                              filled ? Icons.star_rounded : Icons.star_border_rounded,
                              color: filled ? Colors.orange : Colors.grey.shade400,
                              size: isSmall ? 28 : 32,
                            ),
                          );
                        }),
                      ),

                      const SizedBox(height: 8),

                      if (_reviewFeedbackOptions.isNotEmpty) ...[
                        const Text(
                          'What went well?',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _reviewFeedbackOptions.map((opt) {
                            final txt = opt['text'] as String;
                            final isSelected = _dialogSelectedFeedback.contains(txt);
                            return GestureDetector(
                              onTap: () => modalSetState(() {
                                if (isSelected) {
                                  _dialogSelectedFeedback.remove(txt);
                                } else {
                                  _dialogSelectedFeedback.add(txt);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? kPrimaryColor.withOpacity(0.1) : Colors.grey[100],
                                  border: Border.all(color: isSelected ? kPrimaryColor : Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  txt,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? kPrimaryColor : Colors.grey[700],
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Comment
                      TextField(
                        controller: _dialogFeedbackController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Add a comment (optional)',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: kPrimaryColor),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _dialogSelectedRating == 0
                              ? null
                              : () async {
                            await _submitReviewForOrder(order);
                            if (mounted) Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            'Submit Review',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _submitReviewForOrder(Map<String, dynamic> order) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('reviews').insert({
        'order_id': order['id'],
        'user_id': userId,
        'rating': _dialogSelectedRating,
        'feedback_options': _dialogSelectedFeedback,
        'custom_feedback': _dialogFeedbackController.text.trim().isEmpty
            ? null
            : _dialogFeedbackController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      // flip button to "Reviewed" without full reload
      final idx = orders.indexWhere((o) => o['id'].toString() == order['id'].toString());
      if (idx != -1) {
        setState(() {
          orders[idx]['has_review'] = true;
        });
      }

      _showSuccessSnackBar('Thank you for your review!');
    } catch (e) {
      _showErrorSnackBar('Error submitting review: $e');
    }
  }
  // =====================================================================

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

  Future<void> _rescheduleOrder(
      Map<String, dynamic> order,
      Map<String, dynamic> newPickupSlot,
      Map<String, dynamic> newDeliverySlot,
      DateTime newPickupDate,
      DateTime newDeliveryDate,
      ) async {
    try {
      _showLoadingDialog('Rescheduling your order...');

      await supabase.from('orders').update({
        'pickup_slot_id': newPickupSlot['id'],
        'delivery_slot_id': newDeliverySlot['id'],
        'pickup_date': newPickupDate.toIso8601String().split('T')[0],
        'delivery_date': newDeliveryDate.toIso8601String().split('T')[0],
        'pickup_slot_display_time': newPickupSlot['display_time'],
        'pickup_slot_start_time': newPickupSlot['start_time'],
        'pickup_slot_end_time': newPickupSlot['end_time'],
        'delivery_slot_display_time': newDeliverySlot['display_time'],
        'delivery_slot_start_time': newDeliverySlot['start_time'],
        'delivery_slot_end_time': newDeliverySlot['end_time'],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order['id']);

      if (mounted) Navigator.pop(context);

      _showSuccessSnackBar('Order rescheduled successfully!');
      await _loadOrders();

    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error rescheduling order: $e');
      _showErrorSnackBar('Failed to reschedule order');
    }
  }

  Future<void> _generateInvoice(Map<String, dynamic> order) async {
    try {
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

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/invoice_${order['id'].toString().substring(0, 8)}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (mounted) Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Invoice for Order #${order['id'].toString().substring(0, 8)}',
      );

      _showSuccessSnackBar('Invoice generated successfully!');

    } catch (e) {
      if (mounted) Navigator.pop(context);

      debugPrint('Error generating invoice: $e');
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
          icon: const Icon(
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
                  constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const OrdersScreen()), // 👈 make sure class name matches in order_screen.dart
                            (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 24 : 32,
                        vertical: isSmallScreen ? 12 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
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
                bottom: cardMargin + MediaQuery.of(context).padding.bottom,
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

    final statusStr = (order['order_status'] ?? '').toString().toLowerCase();
    final isDelivered = statusStr == 'delivered';
    final hasReview = (order['has_review'] ?? false) == true;

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
                    _buildStatusBadge(order['order_status'], isSmallScreen),
                  ],
                ),

                // Add notification here
                _buildCompactNotification(order, isSmallScreen),

                SizedBox(height: isSmallScreen ? 12 : 16),

                if (firstProduct != null && firstProduct['products'] != null) ...[
                  Row(
                    children: [
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

                // Action Buttons Row
                Row(
                  children: [
                    // LEFT BUTTON
                    Expanded(
                      child: SizedBox(
                        height: isSmallScreen ? 42 : 48,
                        child: isDelivered
                            ? ElevatedButton.icon(
                          onPressed: hasReview ? null : () => _showReviewDialog(order),
                          icon: Icon(
                            hasReview ? Icons.check_circle_outline : Icons.rate_review_outlined,
                            size: isSmallScreen ? 16 : 18,
                            color: hasReview ? Colors.grey.shade600 : kPrimaryColor,
                          ),
                          label: Text(
                            hasReview ? 'Reviewed' : 'Review',
                            style: TextStyle(
                              color: hasReview ? Colors.grey.shade600 : kPrimaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasReview ? Colors.grey.shade100 : kPrimaryColor.withOpacity(0.1),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                            : ElevatedButton.icon(
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
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // RIGHT BUTTON - KEEP ORIGINAL CANCEL LOGIC
                    Expanded(
                      child: SizedBox(
                        height: isSmallScreen ? 42 : 48,
                        child: canCancel
                            ? ElevatedButton.icon(
                          onPressed: remainingTime > 0 ? () => _cancelOrder(order) : null,
                          icon: Icon(
                            remainingTime > 0 ? Icons.cancel_outlined : Icons.block,
                            size: isSmallScreen ? 16 : 18,
                            color: remainingTime > 0 ? Colors.white : Colors.grey.shade500,
                          ),
                          label: Text(
                            remainingTime > 0 ? 'Cancel Order' : 'Cancel Timeout',
                            style: TextStyle(
                              color: remainingTime > 0 ? Colors.white : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: remainingTime > 0 ? Colors.red.shade600 : Colors.grey.shade200,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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


  Widget _buildCompactNotification(Map<String, dynamic> order, bool isSmallScreen) {
    final status = order['order_status']?.toString().toLowerCase() ?? '';
    final orderId = order['id'].toString();
    final pickupTimeRemaining = _getPickupTimeRemaining(orderId);
    final deliveryTimeRemaining = _getDeliveryTimeRemaining(orderId);

    String message = '';
    Color bgColor = Colors.blue.shade50;
    Color borderColor = Colors.blue.shade200;
    Color iconColor = Colors.blue.shade600;
    Color textColor = Colors.blue.shade700;
    IconData icon = Icons.schedule;

    if ((status == 'confirmed' || status == 'pickup_scheduled' || status == 'processing') && pickupTimeRemaining > 0) {
      message = 'Pickup in ${_formatRemainingTime(pickupTimeRemaining)} - prepare your items';
    }
    else if ((status == 'picked_up' || status == 'shipped' || status == 'reached') && deliveryTimeRemaining > 0) {
      message = 'Delivery in ${_formatRemainingTime(deliveryTimeRemaining)} - be ready to receive';
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      iconColor = Colors.green.shade600;
      textColor = Colors.green.shade700;
      icon = Icons.local_shipping;
    }

    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: isSmallScreen ? 8 : 12, bottom: 4),
      padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 10 : 12,
          vertical: isSmallScreen ? 8 : 10
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: isSmallScreen ? 14 : 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: isSmallScreen ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

// (Your existing _RescheduleDialog, _CancellationReasonDialog, _OrderDetailsSheet, etc. remain unchanged below)


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

  // Timer tracking
  Timer? _countdownTimer;
  int _remainingCancelTime = 0;
  int _remainingPickupTime = 0;
  int _remainingDeliveryTime = 0;

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _getDeliveryTypeFromOrder();
    _setupTimers();
    _loadSlots();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _initializeDates() {
    // Pickup dates: 7 days from today
    pickupDates = List.generate(7, (index) => DateTime.now().add(Duration(days: index)));

    // Delivery dates: Initially same as pickup, will be updated when pickup date is selected
    deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));
  }

  void _getDeliveryTypeFromOrder() {
    // Get delivery type from order or detect express
    final rawOrderExpress = widget.order['is_express'];
    if (rawOrderExpress is bool && rawOrderExpress == true) {
      isExpressDelivery = true;
      return;
    }
    if (rawOrderExpress is String && rawOrderExpress.toLowerCase() == 'true') {
      isExpressDelivery = true;
      return;
    }

    final deliveryType = widget.order['delivery_type']?.toString().toLowerCase();
    if (deliveryType == 'express') {
      isExpressDelivery = true;
      return;
    }

    final speed = widget.order['delivery_speed']?.toString().toLowerCase();
    if (speed == 'express') {
      isExpressDelivery = true;
      return;
    }

    // Check order items
    final items = widget.order['order_items'] as List<dynamic>? ?? const [];
    for (final item in items) {
      final st = item['service_type']?.toString().toLowerCase();
      if (st == 'express') {
        isExpressDelivery = true;
        return;
      }
      final itemExpress = item['is_express'];
      if (itemExpress is bool && itemExpress == true) {
        isExpressDelivery = true;
        return;
      }
      if (itemExpress is String && itemExpress.toLowerCase() == 'true') {
        isExpressDelivery = true;
        return;
      }
    }

    isExpressDelivery = false;
  }

  // Setup timers like in main screen
  void _setupTimers() {
    _setupCancelTimer();
    _setupPickupTimer();
    _setupDeliveryTimer();

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_remainingCancelTime > 0) _remainingCancelTime--;
        if (_remainingPickupTime > 0) _remainingPickupTime--;
        if (_remainingDeliveryTime > 0) _remainingDeliveryTime--;
      });
    });
  }

  void _setupCancelTimer() {
    final orderDate = widget.order['pickup_date'];
    final pickupSlot = widget.order['pickup_slot'];

    if (orderDate == null || pickupSlot == null) return;

    try {
      final pickupDate = DateTime.parse(orderDate);
      final startTimeStr = pickupSlot['start_time'].toString();
      final timeParts = startTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Express: at start, Standard: 1 hour before start
      final pickupDeadline = DateTime(
        pickupDate.year,
        pickupDate.month,
        pickupDate.day,
        hour,
        minute,
      ).subtract(isExpressDelivery ? Duration.zero : const Duration(hours: 1));

      final now = DateTime.now();
      if (now.isBefore(pickupDeadline)) {
        _remainingCancelTime = pickupDeadline.difference(now).inSeconds;
      }
    } catch (e) {
      debugPrint('Error setting up cancel timer: $e');
    }
  }

  void _setupPickupTimer() {
    final pickupDate = widget.order['pickup_date'];
    final pickupSlot = widget.order['pickup_slot'];
    final status = widget.order['order_status']?.toString().toLowerCase() ?? '';

    if (status != 'confirmed' && status != 'pickup_scheduled') return;
    if (pickupDate == null || pickupSlot == null) return;

    try {
      final pickupDateTime = DateTime.parse(pickupDate);
      final endTimeStr = pickupSlot['end_time'].toString();
      final timeParts = endTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final pickupEndTime = DateTime(
        pickupDateTime.year,
        pickupDateTime.month,
        pickupDateTime.day,
        hour,
        minute,
      );

      final now = DateTime.now();
      if (now.isBefore(pickupEndTime)) {
        _remainingPickupTime = pickupEndTime.difference(now).inSeconds;
      }
    } catch (e) {
      debugPrint('Error setting up pickup timer: $e');
    }
  }

  void _setupDeliveryTimer() {
    final deliveryDate = widget.order['delivery_date'];
    final deliverySlot = widget.order['delivery_slot'];
    final status = widget.order['order_status']?.toString().toLowerCase() ?? '';

    if (status != 'picked_up' && status != 'shipped' && status != 'reached') return;
    if (deliveryDate == null || deliverySlot == null) return;

    try {
      final deliveryDateTime = DateTime.parse(deliveryDate);
      final endTimeStr = deliverySlot['end_time'].toString();
      final timeParts = endTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final deliveryEndTime = DateTime(
        deliveryDateTime.year,
        deliveryDateTime.month,
        deliveryDateTime.day,
        hour,
        minute,
      );

      final now = DateTime.now();
      if (now.isBefore(deliveryEndTime)) {
        _remainingDeliveryTime = deliveryEndTime.difference(now).inSeconds;
      }
    } catch (e) {
      debugPrint('Error setting up delivery timer: $e');
    }
  }

  // Format time like main screen
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

  // Build notification widget
  Widget _buildNotificationBanner() {
    final status = widget.order['order_status']?.toString().toLowerCase() ?? '';

    String message = '';
    Color bgColor = Colors.blue.shade50;
    Color borderColor = Colors.blue.shade200;
    Color iconColor = Colors.blue.shade600;
    Color textColor = Colors.blue.shade700;
    IconData icon = Icons.schedule;

    if ((status == 'confirmed' || status == 'pickup_scheduled' || status == 'processing') && _remainingPickupTime > 0) {
      message = 'Pickup in ${_formatRemainingTime(_remainingPickupTime)} - prepare your items';
    }
    else if ((status == 'picked_up' || status == 'shipped' || status == 'reached') && _remainingDeliveryTime > 0) {
      message = 'Delivery in ${_formatRemainingTime(_remainingDeliveryTime)} - be ready to receive';
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      iconColor = Colors.green.shade600;
      textColor = Colors.green.shade700;
      icon = Icons.local_shipping;
    }
    else if (_remainingCancelTime > 0) {
      message = 'Reschedule deadline: ${_formatRemainingTime(_remainingCancelTime)} remaining';
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      iconColor = Colors.orange.shade600;
      textColor = Colors.orange.shade700;
      icon = Icons.timer;
    }

    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Build compact policy banner
  Widget _buildPolicyBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50,
            Colors.indigo.shade50,
          ],
        ),
        border: Border.all(
          color: Colors.blue.shade200,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isExpressDelivery ? Colors.orange.shade100 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isExpressDelivery ? Icons.flash_on : Icons.schedule,
              color: isExpressDelivery ? Colors.orange.shade700 : Colors.blue.shade700,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isExpressDelivery ? 'Express' : 'Standard'} Reschedule Policy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isExpressDelivery ? Colors.orange.shade800 : Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Colors.black87,
                    ),
                    children: [
                      const TextSpan(text: 'You can reschedule up to '),
                      TextSpan(
                        text: isExpressDelivery
                            ? 'the exact start time'
                            : '1 hour before',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isExpressDelivery ? Colors.orange.shade700 : Colors.blue.shade700,
                        ),
                      ),
                      const TextSpan(text: ' of your pickup slot'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> getDownloadsPath() async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
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
                    // Notification banner
                    _buildNotificationBanner(),

                    // Policy banner
                    _buildPolicyBanner(),

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

    // ✅ CHECK: Order status for invoice download
    final orderStatus = order['order_status']?.toString() ?? '';
    final isOrderDelivered = orderStatus == 'Delivered';

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
                          // ✅ FIX: Disable button if order is not delivered
                          onPressed: isOrderDelivered ? () => _downloadInvoice(context) : null,
                          icon: Icon(Icons.picture_as_pdf,
                              size: isSmallScreen ? 14 : 16,
                              color: isOrderDelivered ? Colors.white : Colors.grey.shade400),
                          label: Text(
                            isOrderDelivered ? 'Get Invoice' : 'Get Invoice',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              fontWeight: FontWeight.w600,
                              color: isOrderDelivered ? Colors.white : Colors.grey.shade400,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isOrderDelivered
                                ? kPrimaryColor
                                : Colors.grey.shade300,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            // ✅ Disable interaction when not delivered
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ✅ NEW: Show status message for non-delivered orders
                  if (!isOrderDelivered) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange.shade600,
                              size: isSmallScreen ? 14 : 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Invoice will be available once order is delivered',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: isSmallScreen ? 11 : 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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
                        // ✅ NEW: Show order status
                        const SizedBox(height: 12),
                        _buildTimelineRow('Order Status',
                            orderStatus, isSmallScreen),
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

  Future<void> _downloadInvoice(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: kPrimaryColor),
            const SizedBox(width: 16),
            const Expanded(child: Text('Generating invoice...')),
          ],
        ),
      ),
    );

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final orderId = (order['id'] ?? order['order_code'] ?? 'unknown').toString();
      final invoiceNumber = 'INV-$orderId';
      final fileName = 'Invoice_Order_$orderId.pdf';

      // 1) Build PDF
      final Uint8List pdfBytes = await _buildInvoicePdfBytes(order);

      // 2) Upload to Supabase Storage
      final String storagePath = '$userId/$fileName';

      try {
        // Check if file already exists
        final existingFiles = await Supabase.instance.client
            .storage
            .from('invoices')
            .list(path: userId);

        final fileExists = existingFiles.any((file) => file.name == fileName);

        if (fileExists) {
          // Delete old file before uploading new one
          await Supabase.instance.client
              .storage
              .from('invoices')
              .remove(['$storagePath']);
        }

        // Upload new file
        await Supabase.instance.client
            .storage
            .from('invoices')
            .uploadBinary(
          storagePath,
          pdfBytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

        // Get file size
        final fileSize = pdfBytes.length;

        // 3) Save invoice record to database
        await Supabase.instance.client.from('invoice_records').upsert({
          'order_id': orderId,
          'user_id': userId,
          'invoice_number': invoiceNumber,
          'file_path': storagePath,
          'file_size': fileSize,
          'generated_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'order_id');

        debugPrint('✅ Invoice uploaded to Supabase: $storagePath');
      } catch (storageError) {
        debugPrint('⚠️ Storage upload failed: $storageError');
        // Continue with local save even if upload fails
      }

      // 4) Save locally for user access
      String savedPath = '';

      if (kIsWeb) {
        // Web: triggers browser download
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: pdfBytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else if (Platform.isAndroid) {
        try {
          // Save to Downloads via MediaStore
          savedPath = await FileSaver.instance.saveFile(
            name: fileName,
            bytes: pdfBytes,
            ext: 'pdf',
            mimeType: MimeType.pdf,
          );
        } catch (e) {
          // Fallback to app documents
          final dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(pdfBytes);
          savedPath = file.path;
        }
      } else if (Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        savedPath = file.path;
      }

      if (Navigator.canPop(context)) Navigator.of(context).pop();

      // 5) Auto-open (mobile/desktop only)
      if (!kIsWeb) {
        String openPath = savedPath;
        if (openPath.isEmpty) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$fileName');
          await tempFile.writeAsBytes(pdfBytes);
          openPath = tempFile.path;
        }

        final result = await OpenFilex.open(openPath);
        if (result.type != ResultType.done) {
          _showErrorSnackbar(context, 'Could not open PDF. Please install a PDF viewer.');
        }
      }

      // 6) Success toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.download_done, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Invoice saved successfully!')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      debugPrint('❌ Invoice generation error: $e\n$st');
      _showErrorSnackbar(context, 'Failed to generate invoice. Please try again.');
    }
  }



  Future<Uint8List> _buildInvoicePdfBytes(Map<String, dynamic> order) async {
    // ---- Safe helpers ----
    String _text(dynamic v) => (v == null || v.toString() == 'null') ? '' : v.toString();
    num _num(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }
    Map<String, dynamic> _map(dynamic v) {
      if (v == null) return <String, dynamic>{};
      if (v is Map) return Map<String, dynamic>.from(v as Map);
      return <String, dynamic>{};
    }
    List<Map<String, dynamic>> _listOfMaps(dynamic v) {
      if (v is List) return v.map((e) => _map(e)).toList();
      return <Map<String, dynamic>>[];
    }

    final pdf = pw.Document();

    // ---- Logo (safe load) ----
    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/images/dobify_inv_logo.jpg');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    // ---- Inputs from order ----
    final billingList = _listOfMaps(order['order_billing_details']);
    final billing = billingList.isNotEmpty ? billingList.first : <String, dynamic>{};

    final address = _map(order['address_info']).isNotEmpty
        ? _map(order['address_info'])
        : _map(order['address_details']);

    final items = _listOfMaps(order['order_items']);

    final createdAt = _text(order['created_at']);
    final orderId = _text(order['id'] ?? order['order_code']);
    final paymentMethod = _text(order['payment_method']).toUpperCase();

    // Dynamic % (fallbacks)
    final double serviceTaxPercent =
    (_num(billing['service_tax_percent'])).toDouble() > 0
        ? (_num(billing['service_tax_percent'])).toDouble()
        : 18.0;
    final double deliveryGstPercent =
    (_num(billing['delivery_gst_percent'])).toDouble() > 0
        ? (_num(billing['delivery_gst_percent'])).toDouble()
        : 18.0;

    // Charges are **pre-GST bases**
    final double minCartBase   = (_num(billing['minimum_cart_fee'])).toDouble();
    final double platformBase  = (_num(billing['platform_fee'])).toDouble();
    final double deliveryBase  = (_num(billing['delivery_fee'])).toDouble();
    final double totalDiscount = (_num(billing['discount_amount'])).toDouble();

    // Items base subtotal
    double itemsBaseSubtotal = 0;
    for (final it in items) {
      itemsBaseSubtotal += (_num(it['total_price'])).toDouble();
    }
    final billedSubtotal = (_num(billing['subtotal'])).toDouble();
    if (billedSubtotal > 0) itemsBaseSubtotal = billedSubtotal;

    // Total amount (if provided)
    final billedTotalOpt = (_num(billing['total_amount'])).toDouble();
    final bool hasBilledTotal = billedTotalOpt > 0;

    String _formatDate(String isoDate) {
      if (isoDate.isEmpty) return '';
      try {
        final dt = DateTime.parse(isoDate);
        return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
      } catch (_) {
        return isoDate;
      }
    }
    final invoiceDate = _formatDate(createdAt);

    // **Generate a new Invoice No (not equal to Order Id)**
    String _genInvoiceNo() {
      final now = DateTime.tryParse(createdAt) ?? DateTime.now();
      final y = now.year.toString();
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final base = _text(orderId).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final suffix = base.isEmpty
          ? (now.millisecondsSinceEpoch.toRadixString(36).toUpperCase())
          : base.substring(0, base.length.clamp(0, 6)).toUpperCase();
      return 'INV-$y$m$d-$suffix';
    }
    final invoiceNo = _text(billing['invoice_no']).isNotEmpty
        ? _text(billing['invoice_no'])
        : _genInvoiceNo();

    // ---- Function to convert number to words ----
    String _numberToWords(double amount) {
      final ones = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
      final teens = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
      final tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
      final scales = ['', 'thousand', 'lakh', 'crore'];

      String convertBelow1000(int num) {
        if (num == 0) return '';
        String result = '';
        final hundreds = num ~/ 100;
        final remainder = num % 100;

        if (hundreds > 0) result += '${ones[hundreds]} hundred ';
        if (remainder >= 20) {
          result += '${tens[remainder ~/ 10]} ';
          if (remainder % 10 > 0) result += '${ones[remainder % 10]} ';
        } else if (remainder >= 10) {
          result += '${teens[remainder - 10]} ';
        } else if (remainder > 0) {
          result += '${ones[remainder]} ';
        }
        return result.trim();
      }

      final rupees = amount.toInt();
      final paise = ((amount - rupees) * 100).toInt();

      if (rupees == 0 && paise == 0) return 'Zero';

      String result = '';
      int scaleIndex = 0;
      int num = rupees;
      final parts = [];

      while (num > 0) {
        if (num % 1000 > 0) {
          parts.insert(0, '${convertBelow1000(num % 1000)} ${scales[scaleIndex]}');
        }
        num ~/= 1000;
        scaleIndex++;
      }

      result = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

      if (paise > 0) {
        result += ' and ${convertBelow1000(paise)} paise';
      }

      return result.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    // ---- Table helpers ----
    pw.Widget buildCell(String text,
        {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) {
      return pw.Padding(
        padding: pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          maxLines: 2,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: align,
        ),
      );
    }

    // Totals for last row
    double qtySum = 0;
    double taxableSum = 0; // bases
    double cgstSum = 0;
    double sgstSum = 0;
    double grandTotal = 0;
    double discountSum = 0;

    // Recipient & phone (unchanged)
    final recipientName = _text(address['recipient_name']).isEmpty
        ? 'Customer'
        : _text(address['recipient_name']);
    final recipientPhone = _text(address['phone']).isNotEmpty
        ? _text(address['phone'])
        : (_text(address['phone_number']).isNotEmpty
        ? _text(address['phone_number'])
        : (_text(address['mobile']).isNotEmpty
        ? _text(address['mobile'])
        : _text(address['contact'])));

    // Column widths
    final colW = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(30),
      1: pw.FlexColumnWidth(3),
      2: pw.FixedColumnWidth(45),
      3: pw.FixedColumnWidth(40),
      4: pw.FixedColumnWidth(30),
      5: pw.FixedColumnWidth(30),
      6: pw.FixedColumnWidth(40),
      7: pw.FixedColumnWidth(55),
      8: pw.FixedColumnWidth(35),
      9: pw.FixedColumnWidth(40),
      10: pw.FixedColumnWidth(35),
      11: pw.FixedColumnWidth(40),
      12: pw.FixedColumnWidth(54),
    };

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(20),
        build: (ctx) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 2, color: PdfColors.black),
            ),
            padding: pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Center(
                  child: pw.Container(
                    padding: pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                    child: pw.Text('Tax Invoice',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ),
                ),
                pw.SizedBox(height: 10),

                // Company / Order
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Invoice From',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('LEOWORKS PRIVATE LIMITED',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Ground Floor, Plot No-362, Damana Road,', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Chandrasekharpur, Bhubaneswar-751024', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Khordha, Odisha', style: pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(height: 4),
                          pw.Text('Email ID: info@dobify.in', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('PIN Code: 751016', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('GSTIN: 21AAGCL4609M1ZH', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('CIN: U62011OD2025PTC050462', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('PAN: AAGCL4609M', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('TAN: BBNL01690D', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if (logoImage != null)
                            pw.Container(width: 80, height: 80, child: pw.Image(logoImage!, fit: pw.BoxFit.contain)),
                          pw.SizedBox(height: 8),
                          pw.Text('Order Id: $orderId', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Invoice No: $invoiceNo', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Invoice Date: $invoiceDate', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Place of Supply: Odisha', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('State Code: 21', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),

                // Invoice To - FULL ADDRESS DISPLAY
                pw.Container(
                  padding: pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Invoice To',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              recipientName,
                              maxLines: 2,
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                          if (recipientPhone.isNotEmpty)
                            pw.Text('Ph: $recipientPhone', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      if (_text(address['address_line_1']).isNotEmpty)
                        pw.Text(_text(address['address_line_1']), style: pw.TextStyle(fontSize: 8), maxLines: 2),
                      if (_text(address['address_line_2']).isNotEmpty)
                        pw.Text(_text(address['address_line_2']), style: pw.TextStyle(fontSize: 8), maxLines: 2),
                      pw.Text(
                        '${_text(address['city']).isNotEmpty ? _text(address['city']) : ''}'
                            '${_text(address['city']).isNotEmpty && _text(address['state']).isNotEmpty ? ', ' : ''}'
                            '${_text(address['state']).isNotEmpty ? _text(address['state']) : ''}'
                            '${_text(address['pincode']).isNotEmpty ? ' - ${_text(address['pincode'])}' : ''}',
                        style: pw.TextStyle(fontSize: 8),
                        maxLines: 2,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        children: [
                          pw.Text('Category: B2C', style: pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(width: 20),
                          pw.Text('Reverse Charges Applicable: No', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.Text('Transaction Type: $paymentMethod', style: pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                // Items Table
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: colW,
                  children: [
                    // Header - WITH ALL HEADERS COMPLETE
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        buildCell('Sr. No.', bold: true),
                        buildCell('Item Description', bold: true),
                        buildCell('HSN/SAC', bold: true),
                        buildCell('Unit Price', bold: true),
                        buildCell('Qty.', bold: true),
                        buildCell('UQC', bold: true),
                        buildCell('Discount\n(INR)', bold: true),
                        buildCell('Taxable\nAmount\n(INR)', bold: true),
                        buildCell('CGST\n(%)', bold: true),
                        buildCell('CGST\n(INR)', bold: true),
                        buildCell('SGST\n(%)', bold: true),
                        buildCell('SGST\n(INR)', bold: true),
                        buildCell('Total (INR)', bold: true),
                      ],
                    ),

                    // Item rows - USING SERVICE PRICE & PROPORTIONAL DISCOUNT
                    ...items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final it = entry.value;
                      final prod = _map(it['products']);
                      final name = _text(prod['name']).isNotEmpty ? _text(prod['name']) : _text(it['product_name']);
                      final qty = (_num(it['quantity'])).toDouble();
                      final base = (_num(it['total_price'])).toDouble();

                      // Calculate service_price from total_price / quantity
                      final unitPrice = qty > 0 ? (base / qty) : 0.0;

                      // Calculate proportional discount based on item's share of subtotal
                      final itemDiscount = itemsBaseSubtotal > 0
                          ? (base / itemsBaseSubtotal) * totalDiscount
                          : 0.0;

                      // Apply discount BEFORE calculating GST
                      final taxableAfterDiscount = base - itemDiscount;

                      final cg = taxableAfterDiscount * (serviceTaxPercent / 2) / 100.0;
                      final sg = taxableAfterDiscount * (serviceTaxPercent / 2) / 100.0;
                      final rowTotal = taxableAfterDiscount + cg + sg;

                      qtySum += qty;
                      taxableSum += taxableAfterDiscount;
                      cgstSum += cg;
                      sgstSum += sg;
                      grandTotal += rowTotal;
                      discountSum += itemDiscount;

                      return pw.TableRow(
                        children: [
                          buildCell('$idx'),
                          buildCell(name.isEmpty ? 'Item' : name),
                          buildCell('9997'),
                          buildCell(unitPrice.toStringAsFixed(2)),
                          buildCell(qty.toStringAsFixed(0)),
                          buildCell('NOS'),
                          buildCell(itemDiscount.toStringAsFixed(2)),
                          buildCell(taxableAfterDiscount.toStringAsFixed(2)),
                          buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                          buildCell('${cg.toStringAsFixed(2)}'),
                          buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                          buildCell('${sg.toStringAsFixed(2)}'),
                          buildCell(rowTotal.toStringAsFixed(2)),
                        ],
                      );
                    }),

                    // Platform Fee
                    if (platformBase > 0)
                      (() {
                        final cg = platformBase * (serviceTaxPercent / 2) / 100.0;
                        final sg = platformBase * (serviceTaxPercent / 2) / 100.0;
                        final total = platformBase + cg + sg;

                        taxableSum += platformBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        return pw.TableRow(
                          children: [
                            buildCell('${items.length + 1}'),
                            buildCell('Platform Fee'),
                            buildCell('9997'),
                            buildCell(platformBase.toStringAsFixed(2)),
                            buildCell('1.00'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(platformBase.toStringAsFixed(2)),
                            buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${cg.toStringAsFixed(2)}'),
                            buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${sg.toStringAsFixed(2)}'),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    // Minimum Cart Fee
                    if (minCartBase > 0)
                      (() {
                        final cg = minCartBase * (serviceTaxPercent / 2) / 100.0;
                        final sg = minCartBase * (serviceTaxPercent / 2) / 100.0;
                        final total = minCartBase + cg + sg;

                        taxableSum += minCartBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        final sr = items.length + (platformBase > 0 ? 2 : 1);
                        return pw.TableRow(
                          children: [
                            buildCell('$sr'),
                            buildCell('Minimum Cart Fee'),
                            buildCell('9997'),
                            buildCell(minCartBase.toStringAsFixed(2)),
                            buildCell('1.00'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(minCartBase.toStringAsFixed(2)),
                            buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${cg.toStringAsFixed(2)}'),
                            buildCell('${(serviceTaxPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${sg.toStringAsFixed(2)}'),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    // Delivery Fee
                    if (deliveryBase > 0)
                      (() {
                        final cg = deliveryBase * (deliveryGstPercent / 2) / 100.0;
                        final sg = deliveryBase * (deliveryGstPercent / 2) / 100.0;
                        final total = deliveryBase + cg + sg;

                        taxableSum += deliveryBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        final sr = items.length +
                            (platformBase > 0 ? 1 : 0) +
                            (minCartBase > 0 ? 1 : 0) +
                            1;
                        return pw.TableRow(
                          children: [
                            buildCell('$sr'),
                            buildCell('Delivery Fee'),
                            buildCell('996813'),
                            buildCell(deliveryBase.toStringAsFixed(2)),
                            buildCell('1.00'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(deliveryBase.toStringAsFixed(2)),
                            buildCell('${(deliveryGstPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${cg.toStringAsFixed(2)}'),
                            buildCell('${(deliveryGstPercent / 2).toStringAsFixed(2)}%'),
                            buildCell('${sg.toStringAsFixed(2)}'),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    // TOTAL ROW
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        buildCell('Total', bold: true),
                        buildCell('', bold: true),
                        buildCell('', bold: true),
                        buildCell('', bold: true),
                        buildCell(qtySum.toStringAsFixed(0), bold: true),
                        buildCell('', bold: true),
                        buildCell(discountSum.toStringAsFixed(2), bold: true),
                        buildCell(taxableSum.toStringAsFixed(2), bold: true),
                        buildCell('', bold: true),
                        buildCell('${cgstSum.toStringAsFixed(2)}', bold: true),
                        buildCell('', bold: true),
                        buildCell('${sgstSum.toStringAsFixed(2)}', bold: true),
                        buildCell((hasBilledTotal ? billedTotalOpt : grandTotal).toStringAsFixed(2),
                            bold: true),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 8),

                if (_text(billing['applied_coupon_code']).isNotEmpty)
                  pw.Text('Coupon Applied: ${_text(billing['applied_coupon_code'])}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),

                pw.SizedBox(height: 4),
                pw.Text('Amount in Words:',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  'Rupees ${_numberToWords(hasBilledTotal ? billedTotalOpt : grandTotal)} only',
                  style: pw.TextStyle(fontSize: 9),
                ),

                pw.SizedBox(height: 10),

                // Footer
                pw.Container(
                  padding: pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('For Dobify',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('A trade of Leoworks Private Limited', style: pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Registered Office: Ground Floor, Plot No-362, Damana Road, Chandrasekharpur, Bhubaneswar-751024, Khordha, Odisha',
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        'Email: info@dobify.in | Contact: +91 7326019870 | Website: www.dobify.in',
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Digitally Signed by', style: pw.TextStyle(fontSize: 8)),
                            pw.Text('Leoworks Private Limited.',
                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            pw.Text(invoiceDate, style: pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 8),

                // Notes & T&C
                pw.Text('Note:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  'This is a digitally signed computer-generated invoice and does not require a signature. All transactions are subject to the terms and conditions of Dobify.',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Terms & Conditions:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  '1. For any issues, contact Dobify chat support or email info@dobify.in',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  '2. Dobify never asks for sensitive banking details (CVV, account number, UPI PIN, passwords).',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text('3. Services are provided by Dobify, a trade of Leoworks Private Limited.',
                    style: pw.TextStyle(fontSize: 7)),
                pw.Text(
                  '4. Refunds/cancellations are processed as per Dobify policy.',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text('5. Delays/issues beyond control are not our responsibility.',
                    style: pw.TextStyle(fontSize: 7)),
                pw.Text('6. Jurisdiction: Bhubaneswar, Odisha.', style: pw.TextStyle(fontSize: 7)),
              ],
            ),
          );
        },
      ),
    );

    return await pdf.save();
  }





  pw.Widget _sumRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }



  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // Local ScaffoldMessenger so SnackBars appear above the dialog
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
  GlobalKey<ScaffoldMessengerState>();

  List<Map<String, dynamic>> cancellationReasons = [];
  bool isLoadingReasons = true;
  int? selectedReasonId;
  String? selectedReasonText;
  bool showCustomInput = false;
  bool isSubmitting = false;
  bool isDropdownOpen = false;

  static const int _otherLocalId = -1; // synthetic id for "Other"

  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  String _getOrderType() {
    final orderType = widget.order['delivery_type'] ?? 'standard';
    return orderType.toString().toLowerCase();
  }

  Widget _buildCancellationPolicyNote() {
    final orderType = _getOrderType();
    final isExpress = orderType == 'express';

    String policyTitle;
    String policyMessage;

    if (isExpress) {
      policyTitle = 'Express Orders:';
      policyMessage = 'Order cancellation allowed up to the pick-up slot time.';
    } else {
      policyTitle = 'Standard Orders:';
      policyMessage = 'Order cancellation allowed up to 60 minutes before the scheduled pickup.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade50,
            Colors.indigo.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.shade200,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: Colors.blue.shade600,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancellation Policy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(
                        text: '$policyTitle ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      TextSpan(text: policyMessage),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          _ensureOtherReasonIncluded();
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

  // Make sure "Other" exists even if DB doesn't return it
  void _ensureOtherReasonIncluded() {
    final hasOther = cancellationReasons.any((r) {
      final t = (r['reason_text'] ?? '').toString().toLowerCase();
      return t.contains('other');
    });
    if (!hasOther) {
      cancellationReasons = [
        ...cancellationReasons,
        {'id': _otherLocalId, 'reason_text': 'Other'},
      ];
    }
  }

  void _onReasonSelected(int reasonId, String reasonText) {
    final isOther = reasonId == _otherLocalId || reasonText.toLowerCase().contains('other');
    setState(() {
      selectedReasonId = reasonId;
      selectedReasonText = reasonText;
      isDropdownOpen = false;
      showCustomInput = isOther;
      if (!showCustomInput) _customReasonController.clear();
    });
  }

  void _handleSubmit() async {
    if (selectedReasonId == null) {
      _showSnackBar('Please select a reason for cancellation', Colors.red);
      return;
    }

    final pickedIsOther =
        selectedReasonId == _otherLocalId || (selectedReasonText ?? '').toLowerCase().contains('other');

    String finalReason;
    if (pickedIsOther) {
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
    _scaffoldMessengerKey.currentState?.clearSnackBars();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSelectReasonBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF6B6B).withOpacity(0.25),
          width: 1,
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFFF6B6B), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Please select a reason for cancelling your order',
              style: TextStyle(
                color: Color(0xFFE53935),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
          child: ScaffoldMessenger(
            key: _scaffoldMessengerKey,
            child: Scaffold(
              backgroundColor: Colors.black.withOpacity(0.6),
              body: SafeArea(
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
                        maxHeight: screenSize.height * 0.90,
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
                          // Header
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
                            child: Row(
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
                          ),

                          // CONTENT
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
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1) Policy
                                  _buildCancellationPolicyNote(),
                                  const SizedBox(height: 12),

                                  // 2) Banner
                                  _buildSelectReasonBanner(),
                                  const SizedBox(height: 12),

                                  // 3) Dropdown
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.grey.shade50,
                                          Colors.white,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
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
                                        // Dropdown header
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                isDropdownOpen = !isDropdownOpen;
                                              });
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              padding: const EdgeInsets.all(16),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: selectedReasonId != null
                                                            ? [const Color(0xFFFF6B6B), Colors.red.shade600]
                                                            : [Colors.grey.shade300, Colors.grey.shade400],
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: const Icon(
                                                      Icons.format_list_bulleted_rounded,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'Cancellation Reason',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.grey.shade600,
                                                            letterSpacing: 0.8,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Text(
                                                          selectedReasonText ?? 'Choose a reason',
                                                          style: TextStyle(
                                                            fontSize: 15,
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
                                                  const SizedBox(width: 10),
                                                  AnimatedRotation(
                                                    turns: isDropdownOpen ? 0.5 : 0.0,
                                                    duration: const Duration(milliseconds: 300),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFF6B6B).withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(
                                                        Icons.keyboard_arrow_down_rounded,
                                                        color: Color(0xFFFF6B6B),
                                                        size: 18,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Options with fixed scrolling
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 350),
                                          curve: Curves.easeInOutCubic,
                                          height: isDropdownOpen
                                              ? (cancellationReasons.length > 4
                                              ? 200.0  // 4 * 50 = fixed height for scrolling
                                              : cancellationReasons.length * 50.0)
                                              : 0,
                                          clipBehavior: Clip.hardEdge,
                                          decoration: const BoxDecoration(
                                            borderRadius:
                                            BorderRadius.vertical(bottom: Radius.circular(16)),
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
                                              shrinkWrap: true,
                                              physics: cancellationReasons.length > 4
                                                  ? const AlwaysScrollableScrollPhysics()
                                                  : const NeverScrollableScrollPhysics(),
                                              itemCount: cancellationReasons.length,
                                              itemBuilder: (context, index) {
                                                final reason = cancellationReasons[index];
                                                final isSelected = selectedReasonId == reason['id'];
                                                final isLast = index == cancellationReasons.length - 1;

                                                return Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () => _onReasonSelected(
                                                        reason['id'],
                                                        reason['reason_text']),
                                                    borderRadius: isLast
                                                        ? const BorderRadius.vertical(
                                                      bottom: Radius.circular(16),
                                                    )
                                                        : null,
                                                    child: Container(
                                                      height: 50,
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 16),
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? const Color(0xFFFF6B6B)
                                                            .withOpacity(0.08)
                                                            : Colors.transparent,
                                                        border: !isLast
                                                            ? Border(
                                                          bottom: BorderSide(
                                                            color: Colors
                                                                .grey.shade100,
                                                            width: 0.5,
                                                          ),
                                                        )
                                                            : null,
                                                        borderRadius: isLast
                                                            ? const BorderRadius.vertical(
                                                            bottom: Radius.circular(16))
                                                            : null,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          AnimatedContainer(
                                                            duration: const Duration(
                                                                milliseconds: 200),
                                                            width: 18,
                                                            height: 18,
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
                                                                    : Colors
                                                                    .grey.shade400,
                                                                width: 2,
                                                              ),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: isSelected
                                                                ? const Icon(
                                                              Icons.check_rounded,
                                                              color: Colors.white,
                                                              size: 10,
                                                            )
                                                                : null,
                                                          ),
                                                          const SizedBox(width: 14),
                                                          Expanded(
                                                            child: Text(
                                                              reason['reason_text'],
                                                              style: TextStyle(
                                                                fontSize: 14,
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
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                              decoration: BoxDecoration(
                                                                gradient: LinearGradient(
                                                                  colors: [
                                                                    const Color(0xFFFF6B6B),
                                                                    Colors.red.shade600
                                                                  ],
                                                                ),
                                                                borderRadius:
                                                                BorderRadius.circular(10),
                                                              ),
                                                              child: const Text(
                                                                'SELECTED',
                                                                style: TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                  FontWeight.w700,
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

                                  // Custom reason input
                                  if (showCustomInput) ...[
                                    const SizedBox(height: 20),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFFFF6B6B).withOpacity(0.05),
                                            Colors.red.shade600.withOpacity(0.03),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFFF6B6B).withOpacity(0.2),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        const Color(0xFFFF6B6B),
                                                        Colors.red.shade600
                                                      ],
                                                    ),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: const Icon(Icons.edit_rounded,
                                                      color: Colors.white, size: 16),
                                                ),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Text(
                                                    'Please specify your reason',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w700,
                                                      color: Color(0xFFFF6B6B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
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
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide.none,
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide:
                                                  const BorderSide(color: Color(0xFFFF6B6B), width: 2),
                                                ),
                                                contentPadding: const EdgeInsets.all(14),
                                                counterStyle: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // Bottom actions
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: TextButton(
                                      onPressed: isSubmitting ? null : widget.onCancel,
                                      style: TextButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          side: BorderSide(color: Colors.grey.shade300, width: 2),
                                        ),
                                        backgroundColor: Colors.white,
                                      ),
                                      child: Text(
                                        'Keep Order',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [const Color(0xFFFF6B6B), Colors.red.shade600],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
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
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: isSubmitting
                                          ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                          : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.cancel_rounded, size: 18),
                                          SizedBox(width: 6),
                                          Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontSize: 15,
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