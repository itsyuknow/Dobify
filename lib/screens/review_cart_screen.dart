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
  bool _isSuccessDialogVisible = false;
  Timer? _successAutoCloseTimer;

  // Coupon related variables
  String? _appliedCouponCode;
  double discount = 0.0;

  // ADD: per-item loading so other rows don't refresh
  final Set<String> _updatingItems = <String>{};

  String _itemKey(Map<String, dynamic> item) =>
      '${item['product_name']}|${item['service_type']}|${item['product_price']}|${item['service_price']}';

  bool _isUpdating(Map<String, dynamic> item) => _updatingItems.contains(_itemKey(item));


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
  double freeStandardThreshold = 300.0; // NEW
  Map<String, Map<String, String>> _billingNotes = {}; // NEW {key: {title, content}}
  double deliveryGstPercent = 0.0; // % GST on delivery fee, from Supabase



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
    _loadBillingSettings();   // this sets deliveryGstPercent inside setState()
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
      // 1) settings
      final settings = await supabase.from('billing_settings').select().single();

      // 2) notes (incl. delivery_gst so info icon explains GST on delivery)
      final List<dynamic> notesResp = await supabase
          .from('billing_notes')
          .select()
          .or(
          'key.eq.minimum_cart_fee,'
              'key.eq.platform_fee,'
              'key.eq.service_tax,'
              'key.eq.delivery_standard,'
              'key.eq.delivery_standard_free,'
              'key.eq.delivery_express,'
              'key.eq.delivery_gst'
      );

      // 3) map to {key: {title, content}}
      final Map<String, Map<String, String>> notesMap = {
        for (final row in notesResp)
          (row['key'] as String): {
            'title': row['title']?.toString() ?? '',
            'content': row['content']?.toString() ?? '',
          }
      };

      // ✅ Robust min-cart threshold (accepts minimum_cart_value OR minimum_cart_fee)
      final dynamic _minCartRaw =
          settings['minimum_cart_value'] ?? settings['minimum_cart_fee'] ?? 100;

      setState(() {
        minimumCartFee        = (_minCartRaw is num)
            ? _minCartRaw.toDouble()
            : double.tryParse(_minCartRaw.toString()) ?? 100.0;

        platformFee           = (settings['platform_fee'] ?? 0).toDouble();
        serviceTaxPercent     = (settings['service_tax_percent'] ?? 0).toDouble();
        standardDeliveryFee   = (settings['standard_delivery_fee'] ?? 0).toDouble();
        expressDeliveryFee    = (settings['express_delivery_fee'] ?? 0).toDouble();
        freeStandardThreshold = (settings['free_standard_threshold'] ?? 300).toDouble();

        // GST on delivery (so Service Taxes = item GST + delivery GST)
        deliveryGstPercent    = (settings['delivery_gst_percent'] ?? 0).toDouble();

        _billingNotes = notesMap;
        _billingLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading billing settings/notes: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load billing information'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _billingLoading = false);
    }
  }


  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  Widget _popoverBubble({
    required BuildContext context,
    required String title,
    String? description,
    required List<Widget> rows,
    Widget? footer,
  }) {
    // 🔽 Bubble with pointer bottom-right
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // pointer bottom-right
        Positioned(
          bottom: 4,
          right: 20,
          child: Transform.rotate(
            angle: 45 * 3.14159 / 180, // 45° upward arrow
            child: Container(
              width: 14,
              height: 14,
              color: const Color(0xFF1F1F1F),
            ),
          ),
        ),

        // main bubble body
        Container(
          margin: const EdgeInsets.only(bottom: 10, right: 8),
          width: MediaQuery.of(context).size.width * 0.86,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                if (description != null && description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), height: 1.25),
                  ),
                ],
                const SizedBox(height: 10),
                ...rows,
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white24, height: 20, thickness: 1),
                  footer,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _rowLr(String l, String r, {bool bold = false, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              l,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted ? Colors.white70 : Colors.white,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            r,
            style: TextStyle(
              color: muted ? Colors.white70 : Colors.white,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showPopover(Widget child) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 130),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (_, a, __, ___) {
        return Opacity(
          opacity: a.value,
          child: Center(child: child),
        );
      },
    );
  }



  void _showInfoDialog(String title, String content) {
    // Fallback simple text pop if someone calls it directly elsewhere
    _showPopover(
      _popoverBubble(
        context: context,
        title: title,
        description: content,
        rows: const [],
      ),
    );
  }


  void _showMinimumCartFeePopover(Map<String, double> billing) {
    final note = _billingNotes['minimum_cart_fee'];
    final base  = billing['minimumCartFee'] ?? 0;
    final gst   = billing['taxOnMinCart'] ?? 0;
    final total = base + gst;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Minimum Cart Fee Breakdown',
        description: note?['content'],
        rows: [
          _rowLr('Fee before tax', _money(base), muted: true),
          _rowLr('GST @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
        ],
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }

  void _showPlatformFeePopover(Map<String, double> billing) {
    final note = _billingNotes['platform_fee'];
    final base  = billing['platformFee'] ?? 0;
    final gst   = billing['taxOnPlatform'] ?? 0;
    final total = base + gst;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Platform Fee Breakdown',
        description: note?['content'],
        rows: [
          _rowLr('Fee before tax', _money(base), muted: true),
          _rowLr('GST @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
        ],
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }

  void _showServiceTaxesPopover(Map<String, double> billing) {
    final note = _billingNotes['service_tax'];
    final ds        = billing['discountedSubtotal'] ?? 0;
    final tItems    = billing['taxOnItems'] ?? 0;
    final tMinCart  = billing['taxOnMinCart'] ?? 0;
    final tPlatform = billing['taxOnPlatform'] ?? 0;
    final tDelivery = billing['taxOnDelivery'] ?? 0;
    final total     = billing['serviceTax'] ?? 0;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Tax & Charges',
        description: note?['content'],
        rows: [
          _rowLr('Items tax @ ${serviceTaxPercent.toStringAsFixed(0)}% (on ₹${ds.toStringAsFixed(2)})', _money(tItems), muted: true),
          _rowLr('GST on Minimum Cart Fee @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(tMinCart), muted: true),
          _rowLr('GST on Platform Fee @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(tPlatform), muted: true),
          _rowLr('GST on Delivery @ ${deliveryGstPercent.toStringAsFixed(0)}%', _money(tDelivery), muted: true),
        ],
        footer: _rowLr('Total Taxes & Charges', _money(total), bold: true),
      ),
    );
  }

  void _showDeliveryFeePopover(Map<String, double> billing) {
    final isStandard = selectedDeliveryType == 'Standard';
    final infoKey = isStandard ? 'delivery_standard' : 'delivery_express';
    final note = _billingNotes[infoKey] ?? _billingNotes['delivery_standard_free'];

    final fee      = billing['deliveryFee'] ?? 0;
    final gst      = billing['taxOnDelivery'] ?? 0;
    final total    = fee + gst;
    final ds       = billing['discountedSubtotal'] ?? 0;
    final qualifiesFreeStandard = isStandard && (ds >= freeStandardThreshold);

    final rows = <Widget>[
      if (isStandard && qualifiesFreeStandard)
        _rowLr('Standard Delivery — Free (≥ ₹${freeStandardThreshold.toStringAsFixed(0)})', _money(0), muted: true)
      else
        _rowLr('${isStandard ? 'Standard' : 'Express'} fee (before tax)', _money(fee), muted: true),
      _rowLr('GST @ ${deliveryGstPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
    ];

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Delivery Partner Fee Breakup',
        description: note?['content'],
        rows: rows,
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }



  void _showSuccessPopup(String couponCode, double discountAmount) {
    // mark visible and clear any previous timer
    _isSuccessDialogVisible = true;
    _successAutoCloseTimer?.cancel();

    Future.delayed(const Duration(milliseconds: 50), () {
      // keep a local BuildContext for the dialog navigator
      final navigator = Navigator.of(context, rootNavigator: true);

      showGeneralDialog(
        context: context,
        barrierDismissible: true,          // tap outside = dismiss dialog only
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        transitionBuilder: (_, animation, __, ___) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: Opacity(
              opacity: animation.value,
              child: Center(
                // Tapping the popup itself also closes ONLY the dialog (stops animation)
                child: GestureDetector(
                  onTap: () {
                    if (_isSuccessDialogVisible) {
                      _isSuccessDialogVisible = false;
                      // close only the dialog route
                      if (navigator.canPop()) {
                        final popped = navigator.pop();
                        // no-op on result
                      }
                    }
                  },
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

                        // ✅ Title
                        Text(
                          "Coupon Applied!",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            fontFamily: 'YourAppFont',
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
                              fontFamily: 'YourAppFont',
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
                                fontFamily: 'YourAppFont',
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              "₹${discountAmount.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                                fontFamily: 'YourAppFont',
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
            ),
          );
        },
      ).then((_) {
        // Dialog is gone (by tap or auto-close). Mark invisible and cancel timer.
        _isSuccessDialogVisible = false;
        _successAutoCloseTimer?.cancel();
      });

      // Auto-close after 1.2s — ONLY if dialog still visible.
      _successAutoCloseTimer = Timer(const Duration(milliseconds: 1200), () {
        if (_isSuccessDialogVisible) {
          _isSuccessDialogVisible = false;
          if (navigator.canPop()) {
            navigator.pop(); // pop only the dialog that is on top
          }
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

  void _removeCoupon({String? reason}) {
    setState(() {
      _appliedCouponCode = null;
      discount = 0.0;
    });

    if (!mounted) return;

    final msg = reason ?? 'Coupon removed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchCouponByCode(String code) async {
    try {
      final coupon = await supabase
          .from('coupons')
          .select()
          .eq('code', code.toUpperCase())
          .eq('is_active', true)
          .maybeSingle();
      if (coupon == null) return null;
      return Map<String, dynamic>.from(coupon);
    } catch (e) {
      debugPrint('fetchCoupon error: $e');
      return null;
    }
  }


  Future<void> _revalidateAppliedCoupon() async {
    if (_appliedCouponCode == null) return;

    // Current (pre-discount) subtotal of items
    final double itemSubtotal = _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    // If nothing in cart, remove immediately
    if (itemSubtotal <= 0) {
      _removeCoupon(reason: 'Coupon removed as cart is empty');
      return;
    }

    // Load latest coupon row and validate key constraints that can change
    final coupon = await _fetchCouponByCode(_appliedCouponCode!);
    if (coupon == null) {
      _removeCoupon(reason: 'Coupon no longer available');
      return;
    }

    // Expiry check
    if (coupon['expiry_date'] != null) {
      try {
        final expiry = DateTime.parse(coupon['expiry_date'].toString());
        if (DateTime.now().isAfter(expiry)) {
          _removeCoupon(reason: 'Coupon expired');
          return;
        }
      } catch (_) {/* ignore parse issues */}
    }

    // Global usage limit check (optional but safe)
    if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
      final used = (coupon['usage_count'] as num).toInt();
      final limit = (coupon['usage_limit'] as num).toInt();
      if (used >= limit) {
        _removeCoupon(reason: 'Coupon usage limit exceeded');
        return;
      }
    }

    // Minimum order value check (this is your main issue)
    final double? minOrder = (coupon['minimum_order_value'] as num?)
        ?.toDouble();
    if (minOrder != null && itemSubtotal < minOrder) {
      _removeCoupon(
        reason: 'Coupon removed: order below minimum of ₹${minOrder.toStringAsFixed(0)}',
      );
      return;
    }

    // If still valid, optionally clamp discount again (keeps UI consistent)
    // (No need to update here; your _calculateBilling already clamps. Kept for safety.)
    setState(() {
      final String type = (coupon['discount_type'] ?? '').toString();
      final double value = (coupon['discount_value'] as num?)?.toDouble() ?? 0.0;
      double newDiscount = 0.0;
      if (type == 'percentage') {
        newDiscount = itemSubtotal * value / 100.0;
        final double? maxDisc =
        (coupon['max_discount_amount'] as num?)?.toDouble();
        if (maxDisc != null && newDiscount > maxDisc) newDiscount = maxDisc;
      } else {
        newDiscount = value;
      }
      // Don’t let discount exceed the current subtotal
      discount = newDiscount.clamp(0.0, itemSubtotal);
    });
  }


  double _calculateSubtotal() {
    return _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });
  }

  Map<String, double> _calculateBilling() {
    // 1) Original subtotal (before discount)
    final double itemSubtotal = _cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    // 2) Discount applied (cap at subtotal)
    final double discountApplied = discount.clamp(0.0, itemSubtotal);

    // 3) Subtotal AFTER discount
    final double discountedSubtotal = itemSubtotal - discountApplied;

    // 4) Minimum cart fee based on DISCOUNTED subtotal
    final double minCartFeeApplied =
    discountedSubtotal < minimumCartFee ? (minimumCartFee - discountedSubtotal) : 0.0;

    // 5) Delivery fee (Standard can be free if discounted subtotal ≥ threshold)
    final bool isStandard = (selectedDeliveryType == 'Standard');
    final bool qualifiesFreeStandard = isStandard && (discountedSubtotal >= freeStandardThreshold);
    final double deliveryFee = isStandard
        ? (qualifiesFreeStandard ? 0.0 : standardDeliveryFee)
        : expressDeliveryFee;

    // 6) TAXES
    //    • Item tax on discounted items
    //    • PLUS tax on Minimum Cart Fee
    //    • PLUS tax on Platform Fee
    //    • PLUS GST on Delivery (separate %)
    final double taxOnItems     = (discountedSubtotal * serviceTaxPercent) / 100.0;
    final double taxOnMinCart   = (minCartFeeApplied * serviceTaxPercent) / 100.0;
    final double taxOnPlatform  = (platformFee * serviceTaxPercent) / 100.0;
    final double taxOnDelivery  = deliveryFee > 0 ? (deliveryFee * deliveryGstPercent) / 100.0 : 0.0;

    final double serviceTax = taxOnItems + taxOnMinCart + taxOnPlatform + taxOnDelivery;

    // 7) Total
    double totalAmount = discountedSubtotal + minCartFeeApplied + platformFee + deliveryFee + serviceTax;
    if (totalAmount < 0) totalAmount = 0;

    return {
      'subtotal'           : itemSubtotal,
      'discount'           : discountApplied,
      'discountedSubtotal' : discountedSubtotal,
      'minimumCartFee'     : minCartFeeApplied,
      'platformFee'        : platformFee,
      'deliveryFee'        : deliveryFee,
      // individual tax parts (for popovers)
      'taxOnItems'         : taxOnItems,
      'taxOnMinCart'       : taxOnMinCart,
      'taxOnPlatform'      : taxOnPlatform,
      'taxOnDelivery'      : taxOnDelivery,
      'serviceTax'         : serviceTax,
      'totalAmount'        : totalAmount,
    };
  }



  Future<void> _updateQuantityInSupabase(Map<String, dynamic> item, int delta) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Build a stable key for this line item (prod+service+prices)
    String _buildKey(Map<String, dynamic> it) =>
        '${it['product_name']}|${it['service_type']}|${it['product_price']}|${it['service_price']}';

    final String key = _buildKey(item);

    // If this row is already updating, ignore extra taps
    if (_updatingItems.contains(key)) return;

    setState(() {
      _updatingItems.add(key);
    });

    // ---- local helper to revalidate currently applied coupon against new cart ----
    Future<void> _revalidateAppliedCouponInline() async {
      if (_appliedCouponCode == null) return;

      // Current (pre-discount) subtotal using local state
      final double itemSubtotal = _cartItems.fold(0.0, (sum, it) {
        return sum + (it['total_price']?.toDouble() ?? 0.0);
      });

      // If nothing in cart, remove immediately
      if (itemSubtotal <= 0) {
        setState(() {
          _appliedCouponCode = null;
          discount = 0.0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Coupon removed as cart is empty'),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      // Fetch latest coupon row
      Map<String, dynamic>? coupon;
      try {
        final resp = await supabase
            .from('coupons')
            .select()
            .eq('code', _appliedCouponCode!.toUpperCase())
            .eq('is_active', true)
            .maybeSingle();
        if (resp != null) {
          coupon = Map<String, dynamic>.from(resp);
        }
      } catch (e) {
        debugPrint('Coupon fetch error: $e');
      }

      // If coupon not found/active anymore
      if (coupon == null) {
        setState(() {
          _appliedCouponCode = null;
          discount = 0.0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Coupon removed: no longer available'),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      // Expiry check
      if (coupon['expiry_date'] != null) {
        try {
          final expiry = DateTime.parse(coupon['expiry_date'].toString());
          if (DateTime.now().isAfter(expiry)) {
            setState(() {
              _appliedCouponCode = null;
              discount = 0.0;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Coupon removed: expired'),
                  backgroundColor: Colors.orange.shade600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
            return;
          }
        } catch (_) { /* ignore parse errors */ }
      }

      // Global usage limit (optional but safe)
      if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
        final used = (coupon['usage_count'] as num).toInt();
        final limit = (coupon['usage_limit'] as num).toInt();
        if (used >= limit) {
          setState(() {
            _appliedCouponCode = null;
            discount = 0.0;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Coupon removed: usage limit exceeded'),
                backgroundColor: Colors.orange.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          return;
        }
      }

      // Minimum order value check — main case from your screenshots
      final double? minOrder = (coupon['minimum_order_value'] as num?)?.toDouble();
      if (minOrder != null && itemSubtotal < minOrder) {
        setState(() {
          _appliedCouponCode = null;
          discount = 0.0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Coupon removed: order below minimum of ₹${minOrder.toStringAsFixed(0)}'),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      // Still valid → recompute/clamp discount to current subtotal for consistency
      final String type = (coupon['discount_type'] ?? '').toString();
      final double value = (coupon['discount_value'] as num?)?.toDouble() ?? 0.0;
      double newDiscount = 0.0;
      if (type == 'percentage') {
        newDiscount = itemSubtotal * value / 100.0;
        final double? maxDisc = (coupon['max_discount_amount'] as num?)?.toDouble();
        if (maxDisc != null && newDiscount > maxDisc) newDiscount = maxDisc;
      } else {
        newDiscount = value;
      }
      setState(() {
        discount = newDiscount.clamp(0.0, itemSubtotal);
      });
    }
    // ---------------------------------------------------------------------------

    try {
      final int currentQuantity = (item['product_quantity'] ?? 0).toInt();
      final int newQty = currentQuantity + delta;

      final double productPrice = (item['product_price'] ?? 0).toDouble();
      final double servicePrice = (item['service_price'] ?? 0).toDouble();

      if (newQty > 0) {
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

        // Optimistically update JUST this row in memory
        setState(() {
          _cartItems = _cartItems.map((cartItem) {
            final isSame =
                (cartItem['product_name'] == item['product_name']) &&
                    (cartItem['service_type'] == item['service_type']) &&
                    ((cartItem['product_price'] ?? 0).toDouble() == productPrice) &&
                    ((cartItem['service_price'] ?? 0).toDouble() == servicePrice);
            if (isSame) {
              cartItem = Map<String, dynamic>.from(cartItem);
              cartItem['product_quantity'] = newQty;
              cartItem['total_price'] = newQty * (productPrice + servicePrice);
            }
            return cartItem;
          }).toList();
        });

        // ✅ Revalidate coupon after quantity change
        await _revalidateAppliedCouponInline();

      } else {
        // Delete the row when quantity drops to 0
        await supabase
            .from('cart')
            .delete()
            .eq('id', userId)
            .eq('product_name', item['product_name'])
            .eq('service_type', item['service_type'])
            .eq('product_price', productPrice)
            .eq('service_price', servicePrice);

        setState(() {
          _cartItems.removeWhere((cartItem) {
            final isSame =
                (cartItem['product_name'] == item['product_name']) &&
                    (cartItem['service_type'] == item['service_type']) &&
                    ((cartItem['product_price'] ?? 0).toDouble() == productPrice) &&
                    ((cartItem['service_price'] ?? 0).toDouble() == servicePrice);
            return isSame;
          });
        });

        // ✅ Revalidate coupon after removal of a row
        await _revalidateAppliedCouponInline();
      }
    } catch (e) {
      debugPrint("Error updating quantity: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating cart: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingItems.remove(key);
        });
      } else {
        _updatingItems.remove(key);
      }
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

    // ADD: cancel success auto-close timer and mark dialog not visible
    _successAutoCloseTimer?.cancel();
    _isSuccessDialogVisible = false;

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
    final categoryText = (item['category'] ?? '').toString().trim();
    final bool rowLoading = _isUpdating(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.grey.shade50, Colors.white]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // LEFT: Product Image + Category
          Column(
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
                    child: Icon(Icons.image_not_supported,
                        color: Colors.grey.shade400, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (categoryText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    categoryText,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 12),

          // MIDDLE: Product details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.5,
                  ),
                  child: Text(
                    item['product_name']?.toString() ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                if ((item['service_type'] ?? '').toString().trim().isNotEmpty)
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

          // RIGHT: Quantity counter (per-item loading)
          Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildQuantityButton(
                      icon: Icons.remove,
                      onTap: () => _updateQuantityInSupabase(item, -1),
                      isLoading: rowLoading, // 🔁 per-item
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: rowLoading
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Text(
                        '${item['product_quantity'] ?? 0}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildQuantityButton(
                      icon: Icons.add,
                      onTap: () => _updateQuantityInSupabase(item, 1),
                      isLoading: rowLoading, // 🔁 per-item
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
        ],
      ),
    );
  }


  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isLoading,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 16,
        ),
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

    final bool isStandard = selectedDeliveryType == 'Standard';
    final double sub = billing['subtotal'] ?? 0;
    final double disc = billing['discount'] ?? 0;
    final bool qualifiesFreeStandard =
        isStandard && ((sub - disc) >= freeStandardThreshold);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryColor.withOpacity(0.05), Colors.white],
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
                    colors: [
                      kPrimaryColor.withOpacity(0.1),
                      kPrimaryColor.withOpacity(0.05)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: kPrimaryColor, size: 18),
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

          // (Subtotal − Discount) + Min Cart + Platform + Delivery + Service Taxes
          _buildBillingRow('Subtotal', sub),

          if (disc > 0)
            _buildBillingRow(
              _appliedCouponCode != null
                  ? 'Discount (${_appliedCouponCode!})'
                  : 'Discount',
              -disc,
              color: Colors.green,
            ),


          if ((billing['minimumCartFee'] ?? 0) > 0)
            _buildBillingRow(
              'Minimum Cart Fee',
              billing['minimumCartFee'] ?? 0,
              infoKey: 'minimum_cart_fee',
            ),

          _buildBillingRow(
            'Platform Fee',
            billing['platformFee'] ?? 0,
            infoKey: 'platform_fee',
          ),

          _buildBillingRow(
            'Delivery Fee ($selectedDeliveryType)',
            billing['deliveryFee'] ?? 0,
            infoKey: isStandard
                ? (qualifiesFreeStandard
                ? 'delivery_standard_free'
                : 'delivery_standard')
                : 'delivery_express',
            overrideTitle:
            (isStandard && qualifiesFreeStandard) ? 'Standard Delivery — Free' : null,
          ),

          // Service Taxes already include (discountedSubtotal × serviceTax%)
          // plus (deliveryFee × deliveryGst%)
          _buildBillingRow(
            'Service Taxes',
            billing['serviceTax'] ?? 0,
            infoKey: 'service_tax',
          ),

          const Divider(height: 20, thickness: 1),

          _buildBillingRow(
            'Total Amount',
            billing['totalAmount'] ?? 0,
            isTotal: true,
            color: kPrimaryColor,
          ),
        ],
      ),
    );
  }





  Widget _buildBillingRow(
      String label,
      double amount, {
        bool isTotal = false,
        Color? color,
        String? infoKey,
        String? overrideTitle,
        String? customValue,
      }) {
    // Only clickable if an info note exists for this key
    final bool clickable = infoKey != null && (_billingNotes[infoKey] != null);

    final TextStyle labelStyle = TextStyle(
      fontSize: isTotal ? 14 : 12,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
      color: color ?? Colors.black87,
    );

    final TextStyle valueStyle = TextStyle(
      fontSize: isTotal ? 14 : 12,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
      color: color ?? Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            // ⛔️ If not clickable (e.g., Discount row), do nothing on tap
            onTap: () {
              if (!clickable) return;

              // We need current billing numbers for accurate breakdowns
              final billing = _calculateBilling();

              if (infoKey == 'minimum_cart_fee') {
                _showMinimumCartFeePopover(billing);
                return;
              }
              if (infoKey == 'platform_fee') {
                _showPlatformFeePopover(billing);
                return;
              }
              if (infoKey == 'service_tax') {
                _showServiceTaxesPopover(billing);
                return;
              }
              if (infoKey == 'delivery_standard' ||
                  infoKey == 'delivery_express' ||
                  infoKey == 'delivery_standard_free') {
                _showDeliveryFeePopover(billing);
                return;
              }

              // Generic fallback (only if clickable == true)
              final note = _billingNotes[infoKey!];
              _showInfoDialog(overrideTitle ?? (note?['title'] ?? label), note?['content'] ?? '');
            },
            // Remove ripple when not clickable
            splashColor: clickable ? null : Colors.transparent,
            highlightColor: clickable ? null : Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(overrideTitle ?? label, style: labelStyle),
                if (clickable) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 14, color: color ?? Colors.black54),
                ],
              ],
            ),
          ),

          customValue != null
              ? Text(customValue, style: valueStyle)
              : Text('₹${amount.toStringAsFixed(2)}', style: valueStyle),
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