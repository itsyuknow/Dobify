import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart'; // Replace with your actual theme import

class ApplyCouponScreen extends StatefulWidget {
  final double subtotal;
  final Function(String couponCode, double discount) onCouponApplied;

  const ApplyCouponScreen({
    super.key,
    required this.subtotal,
    required this.onCouponApplied,
  });

  @override
  State<ApplyCouponScreen> createState() => _ApplyCouponScreenState();
}

class _ApplyCouponScreenState extends State<ApplyCouponScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _couponController = TextEditingController();

  List<Map<String, dynamic>> _coupons = [];
  List<Map<String, dynamic>> _topCoupons = [];
  bool _isLoading = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    try {
      final response = await supabase
          .from('coupons')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      setState(() {
        _coupons = List<Map<String, dynamic>>.from(response);
        _topCoupons = _coupons.where((coupon) => coupon['is_featured'] == true).toList();
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading coupons: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _applyCoupon(String couponCode) async {
    if (couponCode.isEmpty) return;

    setState(() {
      _isApplying = true;
    });

    try {
      // Find the coupon
      final couponResponse = await supabase
          .from('coupons')
          .select()
          .eq('code', couponCode.toUpperCase())
          .eq('is_active', true)
          .maybeSingle();

      if (couponResponse == null) {
        _showErrorSnackBar('Invalid coupon code');
        setState(() {
          _isApplying = false;
        });
        return;
      }

      final coupon = couponResponse;

      // Check if coupon is valid
      if (!_isCouponValid(coupon)) {
        setState(() {
          _isApplying = false;
        });
        return;
      }

      // Calculate discount
      double discount = _calculateDiscount(coupon);

      // Apply the coupon
      widget.onCouponApplied(couponCode.toUpperCase(), discount);

      if (mounted) {
        Navigator.pop(context);
      }

    } catch (e) {
      print("Error applying coupon: $e");
      _showErrorSnackBar('Error applying coupon');
    } finally {
      setState(() {
        _isApplying = false;
      });
    }
  }

  bool _isCouponValid(Map<String, dynamic> coupon) {
    final now = DateTime.now();

    // Check expiry date
    if (coupon['expiry_date'] != null) {
      final expiryDate = DateTime.parse(coupon['expiry_date']);
      if (now.isAfter(expiryDate)) {
        _showErrorSnackBar('Coupon has expired');
        return false;
      }
    }

    // Check minimum order value
    if (coupon['minimum_order_value'] != null) {
      final minOrderValue = coupon['minimum_order_value'].toDouble();
      if (widget.subtotal < minOrderValue) {
        _showErrorSnackBar('Minimum order value of ₹${minOrderValue.toStringAsFixed(0)} required');
        return false;
      }
    }

    // Check usage limit
    if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
      if (coupon['usage_count'] >= coupon['usage_limit']) {
        _showErrorSnackBar('Coupon usage limit exceeded');
        return false;
      }
    }

    return true;
  }

  double _calculateDiscount(Map<String, dynamic> coupon) {
    double discount = 0.0;

    if (coupon['discount_type'] == 'percentage') {
      discount = (widget.subtotal * coupon['discount_value']) / 100;

      // Check maximum discount limit
      if (coupon['max_discount_amount'] != null) {
        final maxDiscount = coupon['max_discount_amount'].toDouble();
        if (discount > maxDiscount) {
          discount = maxDiscount;
        }
      }
    } else if (coupon['discount_type'] == 'fixed') {
      discount = coupon['discount_value'].toDouble();
    }

    return discount;
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        title: const Text(
          "Apply Coupon",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coupon Code Input
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _couponController,
                        decoration: const InputDecoration(
                          hintText: 'Enter coupon code',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ElevatedButton(
                        onPressed: _isApplying
                            ? null
                            : () => _applyCoupon(_couponController.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: _isApplying
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Gift Voucher Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.card_giftcard,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Gift Voucher',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Handle gift voucher redemption
                      },
                      child: Text(
                        'Redeem',
                        style: TextStyle(
                          color: kPrimaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Top Coupons Section
              if (_topCoupons.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Top Coupons for You',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_up,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                ...(_topCoupons.map((coupon) => _buildCouponCard(coupon, true))),

                const SizedBox(height: 24),
              ],

              // More Coupons Section
              if (_coupons.where((c) => c['is_featured'] != true).isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'More Coupons',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_up,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                ...(_coupons.where((c) => c['is_featured'] != true).map((coupon) => _buildCouponCard(coupon, false))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon, bool isTop) {
    final isEligible = _isCouponEligible(coupon);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEligible ? kPrimaryColor.withOpacity(0.3) : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Color indicator
                Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isEligible ? kPrimaryColor : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),

                // Coupon details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            coupon['code'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isEligible ? kPrimaryColor : Colors.grey.shade600,
                            ),
                          ),
                          if (coupon['is_featured'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'EXCLUSIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        coupon['description'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (coupon['minimum_order_value'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Minimum order: ₹${coupon['minimum_order_value'].toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Apply button
                ElevatedButton(
                  onPressed: isEligible && !_isApplying
                      ? () => _applyCoupon(coupon['code'])
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEligible ? kPrimaryColor : Colors.grey.shade300,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isEligible ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Brand logo (if available)
          if (coupon['brand_logo'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.network(
                    coupon['brand_logo'],
                    height: 20,
                    width: 60,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _isCouponEligible(Map<String, dynamic> coupon) {
    // Check minimum order value
    if (coupon['minimum_order_value'] != null) {
      final minOrderValue = coupon['minimum_order_value'].toDouble();
      if (widget.subtotal < minOrderValue) {
        return false;
      }
    }

    // Check expiry date
    if (coupon['expiry_date'] != null) {
      final expiryDate = DateTime.parse(coupon['expiry_date']);
      if (DateTime.now().isAfter(expiryDate)) {
        return false;
      }
    }

    // Check usage limit
    if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
      if (coupon['usage_count'] >= coupon['usage_limit']) {
        return false;
      }
    }

    return true;
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }
}