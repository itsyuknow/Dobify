import 'dart:async';
import 'dart:math';
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

class _ReviewCartScreenState extends State<ReviewCartScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _cartItems = [];
  bool _cartLoading = false;
  bool _billingLoading = true;

  // Coupon related variables
  String? _appliedCouponCode;
  double discount = 0.0;

  // Banner coupon data
  List<Map<String, dynamic>> _bannerCoupons = [];
  int _currentBannerIndex = 0;
  bool _bannerLoading = true;
  Timer? _bannerTimer;

  // Billing details
  double minimumCartFee = 100.0;
  double platformFee = 0.0;
  double serviceTaxPercent = 0.0;
  double standardDeliveryFee = 0.0;
  double expressDeliveryFee = 0.0;
  String selectedDeliveryType = 'Standard';

  // Animation controllers
  late AnimationController _bannerController;
  late AnimationController _couponController;
  late AnimationController _popupController;
  late AnimationController _successController;
  late AnimationController _floatingController;
  late AnimationController _slideController;

  late Animation<double> _bannerSlideAnimation;
  late Animation<double> _bannerFadeAnimation;
  late Animation<Offset> _couponSlideAnimation;
  late Animation<double> _popupScaleAnimation;
  late Animation<double> _popupFadeAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successOpacityAnimation;
  late Animation<double> _floatingAnimation;
  late Animation<Offset> _bannerCarouselAnimation;

  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _cartItems = List<Map<String, dynamic>>.from(widget.cartItems);
    _loadBillingSettings();
    _loadBannerCoupon();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _bannerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _couponController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _popupController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _bannerSlideAnimation = Tween<double>(begin: 100.0, end: 0.0).animate(
      CurvedAnimation(parent: _bannerController, curve: Curves.elasticOut),
    );

    _bannerFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bannerController, curve: Curves.easeIn),
    );

    _couponSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _couponController, curve: Curves.easeOutCubic));

    _popupScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _popupController, curve: Curves.elasticOut),
    );

    _popupFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _popupController, curve: Curves.easeIn),
    );

    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    _successOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.easeIn),
    );

    _floatingAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );

    _bannerCarouselAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeInOutCubic));

    _bannerController.forward();
    _couponController.forward();
    _floatingController.repeat(reverse: true);
  }

  Future<void> _loadBannerCoupon() async {
    try {
      final response = await supabase
          .from('coupons')
          .select()
          .eq('is_active', true)
          .eq('is_featured', true)
          .order('discount_value', ascending: false)
          .limit(5);

      setState(() {
        _bannerCoupons = List<Map<String, dynamic>>.from(response);
        _bannerLoading = false;
      });

      if (_bannerCoupons.length > 1) {
        _startBannerAutoSlide();
      }
    } catch (e) {
      print("Error loading banner coupons: $e");
      setState(() {
        _bannerLoading = false;
      });
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && _bannerCoupons.isNotEmpty) {
        _slideController.forward().then((_) {
          setState(() {
            _currentBannerIndex = (_currentBannerIndex + 1) % _bannerCoupons.length;
          });
          _slideController.reset();
        });
      }
    });
  }

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

  void _showSuccessPopup(String couponCode, double discountAmount) {
    Future.delayed(const Duration(milliseconds: 100), () {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        transitionBuilder: (_, animation, __, ___) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: Opacity(
              opacity: animation.value,
              child: Center(
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ✅ Success icon
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.85)],
                          ),
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 12),

                      // ✅ Title (consistent font)
                      Text(
                        "Coupon Applied!",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          fontFamily: 'YourAppFont', // <-- Use your app-wide font here
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // ✅ Coupon code
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          couponCode,
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 1.2,
                            fontFamily: 'YourAppFont', // <-- consistent font
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ✅ Savings message
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.savings_outlined, color: Colors.green.shade700, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            "You saved ",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade700,
                              fontFamily: 'YourAppFont', // <-- consistent font
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            "₹${discountAmount.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                              fontFamily: 'YourAppFont', // <-- consistent font
                              decoration: TextDecoration.none,
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
        },
      );

      // ⏱️ Auto-close after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    });
  }



  void _hideSuccessPopup() {
    if (_overlayEntry != null) {
      _popupController.reverse().then((_) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        _popupController.reset();
        _successController.reset();
      });
    }
  }

  void _onCouponApplied(String couponCode, double discountAmount) {
    setState(() {
      _appliedCouponCode = couponCode;
      discount = discountAmount;
    });

    _showSuccessPopup(couponCode, discountAmount);
    _updateCouponUsage(couponCode);
  }

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

  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      discount = 0.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info, color: Colors.white),
              SizedBox(width: 8),
              Text('Coupon removed'),
            ],
          ),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  double _calculateSubtotal() {
    return _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });
  }

  Map<String, double> _calculateBilling() {
    double subtotal = _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    double minCartFeeApplied = subtotal < minimumCartFee ? (minimumCartFee - subtotal) : 0.0;
    double adjustedSubtotal = subtotal + minCartFeeApplied;
    double serviceTax = (subtotal * serviceTaxPercent) / 100;
    double deliveryFee = selectedDeliveryType == 'Express' ? expressDeliveryFee : standardDeliveryFee;
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

  Future<void> _updateQuantityInSupabase(Map<String, dynamic> item, int delta) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _cartLoading = true);

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
    } finally {
      setState(() => _cartLoading = false);
    }
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _couponController.dispose();
    _popupController.dispose();
    _successController.dispose();
    _floatingController.dispose();
    _slideController.dispose();
    _bannerTimer?.cancel();
    _hideSuccessPopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final billing = _calculateBilling();

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
          "Review Cart",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildFloatingBannerCoupon(),
                  _buildCompactOffersAndDiscounts(),
                  _buildCompactOrderSummary(_cartItems),
                  _buildBillingSummary(billing),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildBottomBar(context, billing['totalAmount']!),
        ],
      ),
    );
  }

  Widget _buildFloatingBannerCoupon() {
    if (_bannerLoading) {
      return Container(
        margin: const EdgeInsets.all(16),
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bannerCoupons.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      height: 90,
      child: Stack(
        children: [
          _buildBannerCard(_bannerCoupons[_currentBannerIndex], false),
          AnimatedBuilder(
            animation: _slideController,
            builder: (context, child) {
              if (_slideController.value > 0) {
                final nextIndex = (_currentBannerIndex + 1) % _bannerCoupons.length;
                return SlideTransition(
                  position: _bannerCarouselAnimation,
                  child: _buildBannerCard(_bannerCoupons[nextIndex], true),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBannerCard(Map<String, dynamic> coupon, bool isSliding) {
    List<Color> bannerColors;
    String discountText;

    if (coupon['discount_type'] == 'percentage') {
      bannerColors = [Colors.purple.shade800, Colors.purple.shade600, Colors.purple.shade700];
      discountText = "${coupon['discount_value'].toInt()}% OFF";
    } else {
      bannerColors = [Colors.orange.shade800, Colors.orange.shade600, Colors.orange.shade700];
      discountText = "₹${coupon['discount_value'].toInt()} OFF";
    }

    if (_currentBannerIndex % 3 == 1) {
      bannerColors = [Colors.green.shade800, Colors.green.shade600, Colors.green.shade700];
    } else if (_currentBannerIndex % 3 == 2) {
      bannerColors = [Colors.blue.shade800, Colors.blue.shade600, Colors.blue.shade700];
    }

    final bannerText = coupon['description'] ?? "SPECIAL OFFER!";

    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnimation.value),
          child: GestureDetector(
            onTap: () {
              if (_appliedCouponCode == null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ApplyCouponScreen(
                      subtotal: _calculateSubtotal(),
                      onCouponApplied: _onCouponApplied,
                    ),
                  ),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: bannerColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: bannerColors[1].withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: bannerColors[1].withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              "🎉 $discountText",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_bannerCoupons.length > 1 && !isSliding)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_currentBannerIndex + 1}/${_bannerCoupons.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Use ${coupon['code']} • $bannerText",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactOffersAndDiscounts() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.discount_rounded, color: kPrimaryColor, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                "Offers & Discounts",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_appliedCouponCode != null) ...[
            SlideTransition(
              position: _couponSlideAnimation,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300, width: 1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_appliedCouponCode Applied',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Saved ₹${discount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _removeCoupon,
                      icon: Icon(Icons.close_rounded, color: Colors.red.shade600, size: 18),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_appliedCouponCode == null) ...[
            SlideTransition(
              position: _couponSlideAnimation,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, kPrimaryColor.withOpacity(0.05)],
                  ),
                  border: Border.all(
                    color: kPrimaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.local_offer_rounded,
                      color: kPrimaryColor,
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    "Apply Coupon",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    "Save more with exclusive offers",
                    style: TextStyle(
                      color: kPrimaryColor.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: kPrimaryColor,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ApplyCouponScreen(
                          subtotal: _calculateSubtotal(),
                          onCouponApplied: _onCouponApplied,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactOrderSummary(List<Map<String, dynamic>> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shopping_bag_rounded, color: kPrimaryColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                "Order Summary (${items.length})",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          items.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text('No items in cart.'),
          )
              : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildCompactOrderItem(item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompactOrderItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade50, Colors.white],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              item['product_image']?.toString() ?? '',
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FIXED: Product name with proper text handling
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.5, // Limit width to 50% of screen
                  ),
                  child: Text(
                    item['product_name']?.toString() ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    maxLines: 2, // Allow text to wrap to second line
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${item['service_type']}",
                    style: TextStyle(
                      fontSize: 11,
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              GestureDetector(
                onTap: _cartLoading ? null : () => _updateQuantityInSupabase(item, -1),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: _cartLoading
                      ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                      : const Icon(Icons.remove, color: Colors.black, size: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${item['product_quantity']?.toString() ?? '0'}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _cartLoading ? null : () => _updateQuantityInSupabase(item, 1),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: _cartLoading
                      ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5))
                      : const Icon(Icons.add, color: Colors.black, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Text(
            "₹${item['total_price']?.toString() ?? '0'}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingSummary(Map<String, double> billing) {
    if (_billingLoading) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimaryColor.withOpacity(0.05),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: kPrimaryColor, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                "Bill Summary",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBillingRow('Subtotal', billing['subtotal']!),
          if (billing['minimumCartFee']! > 0)
            _buildBillingRow('Minimum Cart Fee', billing['minimumCartFee']!),
          _buildBillingRow('Platform Fee', billing['platformFee']!),
          _buildBillingRow('Service Tax', billing['serviceTax']!),
          _buildBillingRow('Delivery Fee ($selectedDeliveryType)', billing['deliveryFee']!),
          if (billing['discount']! > 0)
            _buildBillingRow('Discount', -billing['discount']!, color: Colors.green),
          const Divider(height: 20, thickness: 1),
          _buildBillingRow('Total Amount', billing['totalAmount']!,
              isTotal: true, color: kPrimaryColor),
        ],
      ),
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
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black87,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, double totalAmount) {
    final canProceed = _cartItems.isNotEmpty && !_cartLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Total Amount",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        "₹${totalAmount.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (discount > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Saved ₹${discount.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              height: 55,
              child: ElevatedButton(
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
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: canProceed ? 8 : 0,
                  shadowColor: kPrimaryColor.withOpacity(0.3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _cartLoading ? "Loading..." : canProceed ? "Select Slot" : "Cart Empty",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}