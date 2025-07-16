import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import 'apply_coupon_screen.dart';
import 'slot_selector_screen.dart';

class ReviewCartScreen extends StatefulWidget {
  final double subtotal;
  final List<Map<String, dynamic>> cartItems;

  const ReviewCartScreen({super.key, required this.subtotal, required this.cartItems});

  @override
  State<ReviewCartScreen> createState() => _ReviewCartScreenState();
}

class _ReviewCartScreenState extends State<ReviewCartScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _cartItems = [];
  bool _cartLoading = true;
  bool _billingLoading = true;

  // Coupon related variables
  String? _appliedCouponCode;
  double discount = 0.0;

  // Billing details
  double minimumCartFee = 100.0;
  double platformFee = 0.0;
  double serviceTaxPercent = 0.0;
  double standardDeliveryFee = 0.0;
  double expressDeliveryFee = 0.0;
  String selectedDeliveryType = 'Standard';

  @override
  void initState() {
    super.initState();
    _cartItems = List<Map<String, dynamic>>.from(widget.cartItems);
    _loadBillingSettings();
  }

  // Load billing settings from Supabase
  Future<void> _loadBillingSettings() async {
    try {
      final response = await supabase
          .from('billing_settings')
          .select()
          .single();

      setState(() {
        minimumCartFee = response['minimum_cart_fee']?.toDouble() ?? 100.0;
        platformFee = response['platform_fee']?.toDouble() ?? 0.0;
        serviceTaxPercent = response['service_tax_percent']?.toDouble() ?? 0.0;
        standardDeliveryFee = response['standard_delivery_fee']?.toDouble() ?? 0.0;
        expressDeliveryFee = response['express_delivery_fee']?.toDouble() ?? 0.0;
        _billingLoading = false;
      });
    } catch (e) {
      print("Error loading billing settings: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load billing information'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _billingLoading = false;
      });
    }
  }

  // Handle coupon application
  void _onCouponApplied(String couponCode, double discountAmount) {
    setState(() {
      _appliedCouponCode = couponCode;
      discount = discountAmount;
    });

    // Update coupon usage count in Supabase
    _updateCouponUsage(couponCode);

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coupon "$couponCode" applied successfully! You saved ₹${discountAmount.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Update coupon usage count
  Future<void> _updateCouponUsage(String couponCode) async {
    try {
      await supabase
          .from('coupons')
          .update({'usage_count': supabase.rpc('increment_usage_count')})
          .eq('code', couponCode);
    } catch (e) {
      print("Error updating coupon usage: $e");
    }
  }

  // Remove applied coupon
  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      discount = 0.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coupon removed'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Calculate billing breakdown
  Map<String, double> _calculateBilling() {
    double subtotal = _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    // Minimum cart fee logic
    double minCartFeeApplied = subtotal < minimumCartFee ? (minimumCartFee - subtotal) : 0.0;

    // Adjusted subtotal after minimum cart fee
    double adjustedSubtotal = subtotal + minCartFeeApplied;

    // Service tax calculation (on subtotal only)
    double serviceTax = (subtotal * serviceTaxPercent) / 100;

    // Delivery fee (Standard by default)
    double deliveryFee = selectedDeliveryType == 'Express' ? expressDeliveryFee : standardDeliveryFee;

    // Total amount
    double totalAmount = adjustedSubtotal + platformFee + serviceTax + deliveryFee - discount;

    return {
      'subtotal': subtotal,
      'minimumCartFee': minCartFeeApplied,
      'platformFee': platformFee,
      'serviceTax': serviceTax,
      'deliveryFee': deliveryFee,
      'discount': discount,
      'totalAmount': totalAmount,
    };
  }

  // Update quantity in Supabase
  Future<void> _updateQuantityInSupabase(Map<String, dynamic> item, int delta) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      int currentQuantity = item['product_quantity']?.toInt() ?? 0;
      int newQty = currentQuantity + delta;

      if (newQty > 0) {
        double productPrice = item['product_price']?.toDouble() ?? 0.0;
        double servicePrice = item['service_price']?.toDouble() ?? 0.0;

        await supabase
            .from('cart')
            .update({
          'product_quantity': newQty,
          'total_price': newQty * (productPrice + servicePrice),
        })
            .eq('id', userId)
            .eq('product_name', item['product_name'])
            .eq('service_type', item['service_type'])
            .eq('product_price', productPrice)
            .eq('service_price', servicePrice);

        setState(() {
          _cartItems = _cartItems.map((cartItem) {
            if (cartItem == item) {
              cartItem['product_quantity'] = newQty;
              cartItem['total_price'] = newQty * (productPrice + servicePrice);
            }
            return cartItem;
          }).toList();
        });
      } else {
        await supabase
            .from('cart')
            .delete()
            .eq('id', userId)
            .eq('product_name', item['product_name'])
            .eq('service_type', item['service_type'])
            .eq('product_price', item['product_price'])
            .eq('service_price', item['service_price']);

        setState(() {
          _cartItems.removeWhere((cartItem) => cartItem == item);
        });
      }
    } catch (e) {
      print("Error updating quantity: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating cart: ${e.toString()}')),
        );
      }
    }
  }

  // Show billing breakdown dialog
  void _showBillingBreakdown() {
    final billing = _calculateBilling();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Billing Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                _buildBillingRow('Subtotal', billing['subtotal']!),
                if (billing['minimumCartFee']! > 0)
                  _buildBillingRow('Minimum Cart Fee', billing['minimumCartFee']!),
                _buildBillingRow('Platform Fee', billing['platformFee']!),
                _buildBillingRow('Service Tax', billing['serviceTax']!),
                _buildBillingRow('Delivery Fee ($selectedDeliveryType)', billing['deliveryFee']!),
                if (billing['discount']! > 0)
                  _buildBillingRow('Discount', -billing['discount']!, color: Colors.green),
                const Divider(),
                _buildBillingRow('Total Amount', billing['totalAmount']!,
                    isTotal: true, color: Colors.black),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: kIconColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBillingRow(String label, double amount, {bool isTotal = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = _calculateBilling();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        title: const Text(
          "Review Cart",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildSavingBanner(),
                  _buildOffersAndDiscounts(),
                  _buildOrderSummary(_cartItems),
                  _buildBillingSummary(billing),
                ],
              ),
            ),
          ),
          _buildBottomBar(context, billing['totalAmount']!),
        ],
      ),
    );
  }

  Widget _buildSavingBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade800,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.savings, color: Colors.white),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Get upto 60% OFF Use PRABHATINFINITY!",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildOffersAndDiscounts() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Offers & Discounts",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          // Applied Coupon Display
          if (_appliedCouponCode != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coupon Applied: $_appliedCouponCode',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'You saved ₹${discount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _removeCoupon,
                    icon: Icon(Icons.close, color: Colors.red.shade600, size: 20),
                    tooltip: 'Remove coupon',
                  ),
                ],
              ),
            ),
          ],

          // Apply Coupon Button
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _appliedCouponCode != null ? Colors.grey.shade300 : Colors.green.shade800),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                  Icons.percent,
                  color: _appliedCouponCode != null ? Colors.grey.shade400 : Colors.green
              ),
              title: Text(
                _appliedCouponCode != null ? "Change Coupon" : "Apply Offers and Coupons",
                style: TextStyle(
                  color: _appliedCouponCode != null ? Colors.grey.shade600 : Colors.black,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: _appliedCouponCode != null ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ApplyCouponScreen(
                      subtotal: _calculateBilling()['subtotal']!,
                      onCouponApplied: _onCouponApplied,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Order Summary (${items.length})",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          items.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('No items in cart.'),
          )
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildOrderItem(item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item['product_image']?.toString() ?? '',
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['product_name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text("${item['service_type']?.toString() ?? ''} (+₹${item['service_price']?.toString() ?? '0'})",
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () => _updateQuantityInSupabase(item, -1),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove, color: Colors.black, size: 16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${item['product_quantity']?.toString() ?? '0'}',
                  style: const TextStyle(
                      fontSize: 16, color: Colors.black, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                onTap: () => _updateQuantityInSupabase(item, 1),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Text("₹${item['total_price']?.toString() ?? '0'}",
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBillingSummary(Map<String, double> billing) {
    if (_billingLoading) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(32),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Billing Summary",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildBillingRow('Subtotal', billing['subtotal']!),
          if (billing['minimumCartFee']! > 0)
            _buildBillingRow('Minimum Cart Fee', billing['minimumCartFee']!),
          _buildBillingRow('Platform Fee', billing['platformFee']!),
          _buildBillingRow('Service Tax', billing['serviceTax']!),
          _buildBillingRow('Delivery Fee ($selectedDeliveryType)', billing['deliveryFee']!),
          if (billing['discount']! > 0)
            _buildBillingRow('Discount', -billing['discount']!, color: Colors.green),
          const Divider(height: 20),
          _buildBillingRow('Total Amount', billing['totalAmount']!,
              isTotal: true, color: Colors.black),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, double totalAmount) {
    final canProceed = _cartItems.isNotEmpty && !_billingLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        color: Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Total Amount", style: TextStyle(fontSize: 13, color: Colors.black54)),
                  Row(
                    children: [
                      if (_billingLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text("₹${totalAmount.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (discount > 0 && !_billingLoading) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Saved ₹${discount.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (!_billingLoading) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showBillingBreakdown,
                  icon: const Icon(Icons.receipt_outlined, size: 20),
                  tooltip: 'View Bill Details',
                ),
              ],
            ],
          ),
          ElevatedButton(
            onPressed: canProceed ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SlotSelectorScreen(
                    totalAmount: totalAmount,
                    cartItems: _cartItems,
                    appliedCouponCode: _appliedCouponCode,
                    discount: discount,
                  ),
                ),
              );
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: kIconColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: canProceed ? 6 : 0,
            ),
            child: Text(
              _billingLoading ? "Loading..." : canProceed ? "Select Slot" : "Cart Empty",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}