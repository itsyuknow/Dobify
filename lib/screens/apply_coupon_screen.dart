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

class _ApplyCouponScreenState extends State<ApplyCouponScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _couponController = TextEditingController();

  List<Map<String, dynamic>> _coupons = [];
  List<Map<String, dynamic>> _topCoupons = [];
  bool _isLoading = true;
  bool _isApplying = false;

  // ✅ Animation controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _slideController.forward();
    _fadeController.forward();
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

  // ✅ Tag colors based on database tag value
  List<Color> _getTagColorsFromDB(String tag) {
    switch (tag.toUpperCase()) {
      case 'NEW':
        return [Colors.green.shade600, Colors.green.shade500];
      case 'EXCLUSIVE':
        return [Colors.purple.shade600, Colors.purple.shade500];
      case 'LIMITED':
        return [Colors.red.shade600, Colors.red.shade500];
      case 'MEGA DEAL':
        return [Colors.orange.shade600, Colors.orange.shade500];
      case 'HOT':
        return [Colors.pink.shade600, Colors.pink.shade500];
      case 'POPULAR':
        return [Colors.blue.shade600, Colors.blue.shade500];
      case 'TRENDING':
        return [Colors.teal.shade600, Colors.teal.shade500];
      default:
        return [Colors.grey.shade600, Colors.grey.shade500];
    }
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
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
              ],
            ),
          ),
        ),
        automaticallyImplyLeading: true,
        title: const Text(
          "Apply Coupon",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ COMPACT: Coupon Code Input
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _couponController,
                            decoration: InputDecoration(
                              hintText: 'Enter coupon code',
                              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              prefixIcon: Icon(Icons.local_offer_outlined, color: kPrimaryColor, size: 20),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              elevation: 2,
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
                                : const Text(
                              'Apply',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ✅ COMPACT: Top Coupons Section
                  if (_topCoupons.isNotEmpty) ...[
                    _buildSectionHeader('⭐ Featured Coupons', Icons.star_rounded),
                    const SizedBox(height: 12),

                    ...(_topCoupons.map((coupon) => _buildCompactCouponCard(coupon, true))),

                    const SizedBox(height: 20),
                  ],

                  // ✅ COMPACT: More Coupons Section
                  if (_coupons.where((c) => c['is_featured'] != true).isNotEmpty) ...[
                    _buildSectionHeader('🎟️ More Coupons', Icons.local_offer_rounded),
                    const SizedBox(height: 12),

                    ...(_coupons.where((c) => c['is_featured'] != true).map((coupon) => _buildCompactCouponCard(coupon, false))),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ✅ COMPACT: Section Header
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 18),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // ✅ COMPACT: Much more compact coupon card
  Widget _buildCompactCouponCard(Map<String, dynamic> coupon, bool isFeatured) {
    final isEligible = _isCouponEligible(coupon);

    // Dynamic colors based on discount type
    Color accentColor;
    if (coupon['discount_type'] == 'percentage') {
      accentColor = Colors.purple.shade600;
    } else {
      accentColor = Colors.green.shade600;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEligible ? accentColor.withOpacity(0.3) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // ✅ COMPACT: Color indicator + icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withOpacity(0.1),
                        accentColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_offer_rounded,
                    color: accentColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),

                // ✅ COMPACT: Coupon details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            coupon['code'],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isEligible ? accentColor : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (coupon['tag'] != null && coupon['tag'].toString().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _getTagColorsFromDB(coupon['tag']),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                coupon['tag'].toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        coupon['description'] ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (coupon['minimum_order_value'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Min order: ₹${coupon['minimum_order_value'].toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ✅ COMPACT: Apply button
                Container(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: isEligible && !_isApplying
                        ? () => _applyCoupon(coupon['code'])
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEligible ? accentColor : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      elevation: isEligible ? 2 : 0,
                    ),
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isEligible ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ COMPACT: Brand logo (if available) - much smaller
          if (coupon['brand_logo'] != null)
            Container(
              height: 20,
              padding: const EdgeInsets.only(bottom: 8, right: 12),
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
                    height: 12,
                    width: 40,
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
}