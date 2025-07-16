import 'dart:async';
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

  // ✅ Premium Animation controllers
  late AnimationController _bannerController;
  late AnimationController _couponController;
  late AnimationController _popupController;
  late AnimationController _successController;
  late AnimationController _floatingController;
  late AnimationController _slideController; // ✅ New controller for sliding animation

  late Animation<double> _bannerSlideAnimation;
  late Animation<double> _bannerFadeAnimation;
  late Animation<Offset> _couponSlideAnimation;
  late Animation<double> _popupScaleAnimation;
  late Animation<double> _popupFadeAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successRotationAnimation;
  late Animation<double> _floatingAnimation;
  late Animation<Offset> _bannerCarouselAnimation; // ✅ New animation for carousel sliding

  // ✅ Popup overlay state
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
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 1500), // ✅ Longer for premium effect
      vsync: this,
    );

    _floatingController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // ✅ New slide controller for smooth carousel transitions
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

    // ✅ Premium success animations with multiple stages
    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.2).animate(
      CurvedAnimation(
          parent: _successController,
          curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)
      ),
    );

    _successRotationAnimation = Tween<double>(begin: -0.5, end: 0.0).animate(
      CurvedAnimation(
          parent: _successController,
          curve: const Interval(0.3, 1.0, curve: Curves.elasticOut)
      ),
    );

    _floatingAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );

    // ✅ Smooth carousel sliding animation
    _bannerCarouselAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeInOutCubic));

    _bannerController.forward();
    _couponController.forward();
    _floatingController.repeat(reverse: true);
  }

  // ✅ Load multiple banner coupons from Supabase for auto-slide
  Future<void> _loadBannerCoupon() async {
    try {
      final response = await supabase
          .from('coupons')
          .select()
          .eq('is_active', true)
          .eq('is_featured', true)
          .order('discount_value', ascending: false)
          .limit(5); // Get top 5 featured coupons

      setState(() {
        _bannerCoupons = List<Map<String, dynamic>>.from(response);
        _bannerLoading = false;
      });

      // Start auto-slide timer if we have multiple coupons
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

  // ✅ Start auto-slide timer for banner with smooth sliding
  void _startBannerAutoSlide() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && _bannerCoupons.isNotEmpty) {
        // ✅ Trigger slide animation before changing index
        _slideController.forward().then((_) {
          setState(() {
            _currentBannerIndex = (_currentBannerIndex + 1) % _bannerCoupons.length;
          });
          _slideController.reset();
        });
      }
    });
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

  // ✅ PREMIUM SWIGGY-STYLE: Enhanced success popup animation
  void _showSuccessPopup(String couponCode, double discountAmount) {
    _overlayEntry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: _popupController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _popupFadeAnimation,
            child: Container(
              color: Colors.black.withOpacity(0.7),
              child: Stack(
                children: [
                  // ✅ Premium particle effects background
                  ...List.generate(20, (index) => _buildParticle(index)),

                  Center(
                    child: ScaleTransition(
                      scale: _popupScaleAnimation,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white,
                              kPrimaryColor.withOpacity(0.05),
                              Colors.white,
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 50,
                              offset: const Offset(0, 25),
                            ),
                            BoxShadow(
                              color: kPrimaryColor.withOpacity(0.3),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ✅ Top decorative element
                            Container(
                              height: 6,
                              margin: const EdgeInsets.only(top: 20, left: 80, right: 80),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.5)],
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ✅ Premium animated icon with multiple layers
                            AnimatedBuilder(
                              animation: _successController,
                              builder: (context, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer ring animation
                                    Transform.scale(
                                      scale: _successScaleAnimation.value * 1.5,
                                      child: Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: kPrimaryColor.withOpacity(0.3),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Middle ring
                                    Transform.scale(
                                      scale: _successScaleAnimation.value * 1.2,
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: kPrimaryColor.withOpacity(0.1),
                                        ),
                                      ),
                                    ),

                                    // Main icon
                                    Transform.scale(
                                      scale: _successScaleAnimation.value,
                                      child: Transform.rotate(
                                        angle: _successRotationAnimation.value,
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            gradient: RadialGradient(
                                              colors: [
                                                kPrimaryColor,
                                                kPrimaryColor.withOpacity(0.8),
                                                kPrimaryColor,
                                              ],
                                            ),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: kPrimaryColor.withOpacity(0.4),
                                                blurRadius: 20,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 28),

                            // ✅ Premium text with gradient
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                children: [
                                  ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.7)],
                                    ).createShader(bounds),
                                    child: const Text(
                                      '🎉 Coupon Applied!',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  Text(
                                    'Code: $couponCode',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimaryColor,
                                      letterSpacing: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 20),

                                  // ✅ Premium savings display
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          kPrimaryColor.withOpacity(0.1),
                                          kPrimaryColor.withOpacity(0.05),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: kPrimaryColor.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.savings_rounded,
                                          color: kPrimaryColor,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'You saved ₹${discountAmount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: kPrimaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _popupController.forward();
    _successController.forward();

    // Auto hide after 3.5 seconds
    Future.delayed(const Duration(milliseconds: 3500), () {
      _hideSuccessPopup();
    });
  }

  // ✅ Premium particle effect for success animation
  Widget _buildParticle(int index) {
    final random = index * 0.1;
    final animationDelay = (index % 5) * 0.2;

    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        final progress = (_successController.value - animationDelay).clamp(0.0, 1.0);

        return Positioned(
          left: MediaQuery.of(context).size.width * (0.1 + random),
          top: MediaQuery.of(context).size.height * (0.2 + random * 0.6),
          child: Transform.scale(
            scale: progress,
            child: Opacity(
              opacity: (1.0 - progress).clamp(0.0, 1.0),
              child: Container(
                width: 8 + (index % 3) * 4,
                height: 8 + (index % 3) * 4,
                decoration: BoxDecoration(
                  color: index % 2 == 0 ? kPrimaryColor : Colors.orange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (index % 2 == 0 ? kPrimaryColor : Colors.orange).withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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

  // Handle coupon application
  void _onCouponApplied(String couponCode, double discountAmount) {
    setState(() {
      _appliedCouponCode = couponCode;
      discount = discountAmount;
    });

    // ✅ Show premium success popup
    _showSuccessPopup(couponCode, discountAmount);

    // Update coupon usage count in Supabase
    _updateCouponUsage(couponCode);
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

  // Calculate basic subtotal
  double _calculateSubtotal() {
    return _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });
  }

  // ✅ Calculate billing breakdown
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
    _slideController.dispose(); // ✅ Dispose slide controller
    _bannerTimer?.cancel(); // ✅ Cancel auto-slide timer if exists
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

  // ✅ SMOOTH SLIDING: Auto-sliding banner with carousel animation
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
          // ✅ Current banner
          _buildBannerCard(_bannerCoupons[_currentBannerIndex], false),

          // ✅ Next banner with slide animation
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

  // ✅ Individual banner card builder
  Widget _buildBannerCard(Map<String, dynamic> coupon, bool isSliding) {
    // Dynamic colors based on discount type and index
    List<Color> bannerColors;
    String discountText;

    if (coupon['discount_type'] == 'percentage') {
      bannerColors = [Colors.purple.shade800, Colors.purple.shade600, Colors.purple.shade700];
      discountText = "${coupon['discount_value'].toInt()}% OFF";
    } else {
      bannerColors = [Colors.orange.shade800, Colors.orange.shade600, Colors.orange.shade700];
      discountText = "₹${coupon['discount_value'].toInt()} OFF";
    }

    // Add variety with different color schemes based on current index
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

  // ✅ COMPACT: More compact offers and discounts section
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

          // Applied Coupon Display
          if (_appliedCouponCode != null) ...[
            SlideTransition(
              position: _couponSlideAnimation,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.shade50,
                      Colors.green.shade100.withOpacity(0.3),
                    ],
                  ),
                  border: Border.all(color: Colors.green.shade300, width: 1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade600, Colors.green.shade500],
                        ),
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

          // Apply Coupon Button - More compact
          SlideTransition(
            position: _couponSlideAnimation,
            child: Container(
              decoration: BoxDecoration(
                gradient: _appliedCouponCode != null
                    ? LinearGradient(colors: [Colors.grey.shade100, Colors.grey.shade50])
                    : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, kPrimaryColor.withOpacity(0.05)],
                ),
                border: Border.all(
                  color: _appliedCouponCode != null
                      ? Colors.grey.shade300
                      : kPrimaryColor.withOpacity(0.2),
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
                    gradient: _appliedCouponCode != null
                        ? LinearGradient(colors: [Colors.grey.shade200, Colors.grey.shade100])
                        : LinearGradient(
                      colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_offer_rounded,
                    color: _appliedCouponCode != null ? Colors.grey.shade500 : kPrimaryColor,
                    size: 18,
                  ),
                ),
                title: Text(
                  _appliedCouponCode != null ? "Change Coupon" : "Apply Coupon",
                  style: TextStyle(
                    color: _appliedCouponCode != null ? Colors.grey.shade600 : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  _appliedCouponCode != null ? "Tap to apply different coupon" : "Save more with exclusive offers",
                  style: TextStyle(
                    color: _appliedCouponCode != null
                        ? Colors.grey.shade500
                        : kPrimaryColor.withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: _appliedCouponCode != null ? Colors.grey.shade400 : kPrimaryColor,
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
      ),
    );
  }

  // ✅ COMPACT: More compact order summary
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

  // ✅ COMPACT: More compact order item
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
                Text(
                  item['product_name']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${item['service_type']?.toString() ?? ''} (+₹${item['service_price']?.toString() ?? '0'})",
                    style: TextStyle(
                      fontSize: 10,
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w600,
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
                      child: CircularProgressIndicator(strokeWidth: 1.5)
                  )
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
                      child: CircularProgressIndicator(strokeWidth: 1.5)
                  )
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

  // ✅ PREMIUM: Enhanced Billing Summary
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
                            gradient: LinearGradient(
                              colors: [Colors.green.shade100, Colors.green.shade50],
                            ),
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