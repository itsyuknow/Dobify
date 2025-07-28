import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import 'profile_screen.dart';
import 'order_screen.dart';// Import the OrdersScreen

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  final double totalAmount;
  final List<Map<String, dynamic>> cartItems;
  final String paymentMethod;
  final String? paymentId;
  final String? appliedCouponCode;
  final double discount;
  final Map<String, dynamic> selectedAddress;
  final DateTime pickupDate;
  final Map<String, dynamic> pickupSlot;
  final DateTime deliveryDate;
  final Map<String, dynamic> deliverySlot;
  final bool isExpressDelivery;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.totalAmount,
    required this.cartItems,
    required this.paymentMethod,
    this.paymentId,
    this.appliedCouponCode,
    required this.discount,
    required this.selectedAddress,
    required this.pickupDate,
    required this.pickupSlot,
    required this.deliveryDate,
    required this.deliverySlot,
    required this.isExpressDelivery,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // Billing details from database
  Map<String, dynamic>? billingDetails;
  bool isLoadingBilling = true;

  // ✅ NEW: Expanded items state
  bool _isOrderDetailsExpanded = false;

  late AnimationController _mainController;
  late AnimationController _checkController;
  late AnimationController _textController;
  late AnimationController _confettiController;
  late AnimationController _pulseController;
  late AnimationController _backgroundController;
  // ✅ NEW: Expansion animation controller
  late AnimationController _expansionController;

  // Background animations
  late Animation<double> _backgroundFadeAnimation;
  late Animation<double> _gradientAnimation;

  // Main animations
  late Animation<double> _cardScaleAnimation;
  late Animation<Offset> _cardSlideAnimation;

  // Check mark animations
  late Animation<double> _checkScaleAnimation;
  late Animation<double> _checkFadeAnimation;
  late Animation<double> _checkRotationAnimation;

  // Text animations
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _titleFadeAnimation;
  late Animation<Offset> _subtitleSlideAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<Offset> _detailsSlideAnimation;
  late Animation<double> _detailsFadeAnimation;

  // Confetti and effects
  late Animation<double> _confettiAnimation;
  late Animation<double> _pulseAnimation;

  // ✅ NEW: Expansion animation
  late Animation<double> _expansionAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBillingDetails();
    _startAnimationSequence();
  }

  void _initializeAnimations() {
    // Background controller for gradient effects
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Main controller for overall flow
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Check mark controller
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Text animations controller
    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Confetti controller
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    // Pulse controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // ✅ NEW: Expansion controller
    _expansionController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Background animations
    _backgroundFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));

    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    // Card animations
    _cardScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));

    // Check mark animations
    _checkScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    _checkFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _checkRotationAnimation = Tween<double>(
      begin: -0.8,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    // Text animations
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _titleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
    ));

    _subtitleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
    ));

    _detailsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
    ));

    _detailsFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeIn),
    ));

    // Confetti animation
    _confettiAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _confettiController,
      curve: Curves.easeOut,
    ));

    // Pulse animation
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // ✅ NEW: Expansion animation
    _expansionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expansionController,
      curve: Curves.easeInOutCubic,
    ));
  }

  void _startAnimationSequence() async {
    // Start background animation
    _backgroundController.repeat(reverse: true);

    // Start main animation
    _mainController.forward();

    // Start check animation after delay
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      _checkController.forward();

      // Start pulse animation
      _pulseController.repeat(reverse: true);
    }

    // Start text animations
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      _textController.forward();
    }

    // Start confetti
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _confettiController.forward();
    }
  }

  // ✅ NEW: Toggle order details expansion
  void _toggleOrderDetailsExpansion() {
    setState(() {
      _isOrderDetailsExpanded = !_isOrderDetailsExpanded;
    });

    if (_isOrderDetailsExpanded) {
      _expansionController.forward();
    } else {
      _expansionController.reverse();
    }
  }

  // Load billing details from database
  Future<void> _loadBillingDetails() async {
    try {
      final response = await supabase
          .from('order_billing_details')
          .select()
          .eq('order_id', widget.orderId)
          .single();

      setState(() {
        billingDetails = response;
        isLoadingBilling = false;
      });
    } catch (e) {
      print('Error loading billing details: $e');
      setState(() {
        isLoadingBilling = false;
      });
    }
  }

  // ✅ ENHANCED: Handle back button press with attractive popup design
  Future<bool> _onWillPop() async {
    // Show enhanced dialog with attractive design
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor,
                      kPrimaryColor.withOpacity(0.8),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                'Order Confirmed!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Your order has been placed successfully.\nWhat would you like to do next?',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Order ID Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kPrimaryColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      color: kPrimaryColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Order: ${widget.orderId.length > 15 ? widget.orderId.substring(0, 15) + '...' : widget.orderId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Action Buttons
              Column(
                children: [
                  // Continue Shopping Button - Enhanced
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        _navigateToOrdersScreen(); // ✅ FIXED: Navigate to OrdersScreen
                      },
                      icon: const Icon(
                        Icons.shopping_bag_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Continue Shopping',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 24,
                        ),
                        elevation: 4,
                        shadowColor: kPrimaryColor.withOpacity(0.3),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Stay Here Button - Enhanced
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(
                        Icons.visibility_rounded,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      label: Text(
                        'Stay Here',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 24,
                        ),
                        backgroundColor: Colors.grey.shade50,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Additional info
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.grey.shade400,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'You can always view your order details later',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return false; // Always prevent back navigation
  }

  // ✅ Navigate to order history (Profile screen with order history opened)
  void _navigateToOrderHistory() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(openOrderHistory: true),
      ),
          (route) => false,
    );
  }

  // ✅ Navigate to home screen and clear entire navigation stack
  void _navigateToHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  // ✅ Navigate to orders screen (OrdersScreen)
  void _navigateToOrdersScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const OrdersScreen(),
      ),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _mainController.dispose();
    _checkController.dispose();
    _textController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    _expansionController.dispose(); // ✅ NEW: Dispose expansion controller
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return 'Today';
    } else if (date.day == now.add(const Duration(days: 1)).day &&
        date.month == now.add(const Duration(days: 1)).month &&
        date.year == now.add(const Duration(days: 1)).year) {
      return 'Tomorrow';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _backgroundController,
        _mainController,
        _checkController,
        _textController,
        _confettiController,
        _pulseController,
        _expansionController, // ✅ NEW: Add expansion controller
      ]),
      builder: (context, child) {
        return PopScope(
          // ✅ Prevent back navigation - use PopScope for newer Flutter versions
          canPop: false,
          onPopInvoked: (didPop) async {
            if (!didPop) {
              await _onWillPop();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kPrimaryColor.withOpacity(0.05 + (_gradientAnimation.value * 0.1)),
                    Colors.white,
                    Colors.white,
                    kPrimaryColor.withOpacity(0.03 + (_gradientAnimation.value * 0.07)),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Animated Background Circles
                  ...List.generate(5, (index) => _buildBackgroundCircle(index)),

                  // Confetti Effect
                  if (_confettiAnimation.value > 0)
                    ...List.generate(30, (index) => _buildConfettiParticle(index)),

                  // Main Content
                  SafeArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SlideTransition(
                          position: _cardSlideAnimation,
                          child: ScaleTransition(
                            scale: _cardScaleAnimation,
                            child: FadeTransition(
                              opacity: _backgroundFadeAnimation,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimaryColor.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    // Success Icon
                                    ScaleTransition(
                                      scale: _pulseAnimation,
                                      child: RotationTransition(
                                        turns: _checkRotationAnimation,
                                        child: FadeTransition(
                                          opacity: _checkFadeAnimation,
                                          child: ScaleTransition(
                                            scale: _checkScaleAnimation,
                                            child: Container(
                                              width: 100,
                                              height: 100,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    kPrimaryColor,
                                                    kPrimaryColor.withOpacity(0.8),
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: kPrimaryColor.withOpacity(0.3),
                                                    blurRadius: 15,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.check_rounded,
                                                color: Colors.white,
                                                size: 50,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Success Title
                                    SlideTransition(
                                      position: _titleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _titleFadeAnimation,
                                        child: Column(
                                          children: [
                                            Text(
                                              'Order Placed',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: kPrimaryColor,
                                              ),
                                            ),
                                            Text(
                                              'Successfully!',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: kPrimaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // Order ID
                                    SlideTransition(
                                      position: _subtitleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _subtitleFadeAnimation,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kPrimaryColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Order ID',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: kPrimaryColor.withOpacity(0.8),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                widget.orderId,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: kPrimaryColor,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Order Details
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Column(
                                          children: [
                                            _buildOrderDetailsCard(),
                                            const SizedBox(height: 16),
                                            _buildScheduleCard(),
                                            const SizedBox(height: 16),
                                            _buildBillCard(),
                                            const SizedBox(height: 16),
                                            _buildInfoCard(),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 32),

                                    // ✅ ENHANCED Action Buttons with smooth animations
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Column(
                                          children: [
                                            // ✅ NEW: View Your Orders Button (goes to profile with order history)
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: _navigateToOrderHistory,
                                                icon: const Icon(
                                                  Icons.receipt_long_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                label: const Text(
                                                  'View Your Orders',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: kPrimaryColor,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                    horizontal: 24,
                                                  ),
                                                  elevation: 4,
                                                  shadowColor: kPrimaryColor.withOpacity(0.3),
                                                ),
                                              ),
                                            ),

                                            const SizedBox(height: 12),

                                            // ✅ NEW: Continue Shopping Button (goes to OrdersScreen)
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: _navigateToOrdersScreen,
                                                icon: Icon(
                                                  Icons.shopping_bag_outlined,
                                                  color: kPrimaryColor,
                                                  size: 20,
                                                ),
                                                label: Text(
                                                  'Continue Shopping',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: kPrimaryColor,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(
                                                    color: kPrimaryColor,
                                                    width: 2,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                    horizontal: 24,
                                                  ),
                                                  backgroundColor: Colors.transparent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
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
  }

  // ✅ ENHANCED Order Details Card with expandable functionality
  Widget _buildOrderDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Order Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Always show first 3 items
          ...widget.cartItems.take(3).map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item['product_name']} x${item['product_quantity']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  '₹${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )).toList(),

          // ✅ ENHANCED: Show expandable section for remaining items
          if (widget.cartItems.length > 3) ...[
            // Expandable content with smooth animation
            SizeTransition(
              sizeFactor: _expansionAnimation,
              child: FadeTransition(
                opacity: _expansionAnimation,
                child: Column(
                  children: widget.cartItems.skip(3).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item['product_name']} x${item['product_quantity']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          '₹${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),

            // ✅ ENHANCED: Smooth toggle button with rotation animation
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _toggleOrderDetailsExpansion,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(_isOrderDetailsExpanded ? 0.1 : 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kPrimaryColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isOrderDetailsExpanded
                          ? 'View Less'
                          : 'View ${widget.cartItems.length - 3} More Items',
                      style: TextStyle(
                        fontSize: 12,
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 300),
                      turns: _isOrderDetailsExpanded ? 0.5 : 0.0,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: kPrimaryColor,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPrimaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Schedule',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildScheduleRow(
            Icons.local_laundry_service,
            'Pickup',
            '${_formatDate(widget.pickupDate)} at ${widget.pickupSlot['display_time'] ?? '${widget.pickupSlot['start_time']} - ${widget.pickupSlot['end_time']}'}',
          ),
          const SizedBox(height: 8),
          _buildScheduleRow(
            Icons.local_shipping,
            'Delivery',
            '${_formatDate(widget.deliveryDate)} at ${widget.deliverySlot['display_time'] ?? '${widget.deliverySlot['start_time']} - ${widget.deliverySlot['end_time']}'}',
          ),
          const SizedBox(height: 8),
          _buildScheduleRow(
            Icons.flash_on,
            'Delivery Type',
            widget.isExpressDelivery ? 'Express Delivery' : 'Standard Delivery',
          ),
          const SizedBox(height: 8),
          _buildScheduleRow(
            Icons.location_on,
            'Address',
            '${widget.selectedAddress['address_line_1']}, ${widget.selectedAddress['city']} - ${widget.selectedAddress['pincode']}',
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kPrimaryColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: kPrimaryColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard() {
    if (isLoadingBilling) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Bill Summary',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (billingDetails != null) ...[
            _buildBillRow('Subtotal', '₹${billingDetails!['subtotal']?.toStringAsFixed(2) ?? '0.00'}'),
            if ((billingDetails!['minimum_cart_fee']?.toDouble() ?? 0.0) > 0)
              _buildBillRow('Minimum Cart Fee', '₹${billingDetails!['minimum_cart_fee']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow('Platform Fee', '₹${billingDetails!['platform_fee']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow('Service Tax', '₹${billingDetails!['service_tax']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow(
                'Delivery Fee (${billingDetails!['delivery_type'] == 'express' ? 'Express' : 'Standard'})',
                '₹${billingDetails!['delivery_fee']?.toStringAsFixed(2) ?? '0.00'}'
            ),
            if ((billingDetails!['discount_amount']?.toDouble() ?? 0.0) > 0)
              _buildBillRow('Discount', '-₹${billingDetails!['discount_amount']?.toStringAsFixed(2) ?? '0.00'}', color: Colors.green),
            if (billingDetails!['applied_coupon_code'] != null)
              _buildBillRow('Coupon Applied', billingDetails!['applied_coupon_code'], color: Colors.green),
          ] else ...[
            _buildBillRow('Subtotal', '₹${(widget.totalAmount + widget.discount).toStringAsFixed(2)}'),
            if (widget.discount > 0)
              _buildBillRow('Discount', '-₹${widget.discount.toStringAsFixed(2)}', color: Colors.green),
            if (widget.appliedCouponCode != null)
              _buildBillRow('Coupon Applied', widget.appliedCouponCode!, color: Colors.green),
          ],

          const Divider(height: 16),
          _buildBillRow(
            'Total Amount',
            '₹${billingDetails?['total_amount']?.toStringAsFixed(2) ?? widget.totalAmount.toStringAsFixed(2)}',
            isTotal: true,
          ),
          const SizedBox(height: 8),
          _buildBillRow('Payment Method', widget.paymentMethod == 'online' ? 'Online Payment' : 'Cash on Delivery'),
          if (widget.paymentId != null)
            _buildBillRow('Payment ID', widget.paymentId!),
        ],
      ),
    );
  }

  Widget _buildBillRow(String label, String value, {Color? color, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 15 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.schedule_rounded,
            'Your items will be picked up as scheduled',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.notifications_active_rounded,
            'You\'ll receive updates via SMS and notifications',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.support_agent_rounded,
            '24/7 customer support available',
          ),
          if (widget.isExpressDelivery) ...[
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.flash_on_rounded,
              'Express delivery selected for faster service',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade700,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundCircle(int index) {
    final random = (index * 234) % 1000;
    final size = 60.0 + (random % 80);
    final left = (random % 100) / 100.0;
    final top = ((random * 3) % 100) / 100.0;
    final opacity = 0.02 + (random % 3) / 100.0;

    return Positioned(
      left: MediaQuery.of(context).size.width * left - size / 2,
      top: MediaQuery.of(context).size.height * top - size / 2,
      child: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_gradientAnimation.value * 0.2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryColor.withOpacity(opacity),
                    kPrimaryColor.withOpacity(opacity * 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfettiParticle(int index) {
    final random = (index * 456) % 1000;
    final startX = (random % 100) / 100.0;
    final size = 4.0 + (random % 6);
    final colors = [
      kPrimaryColor,
      kPrimaryColor.withOpacity(0.8),
      Colors.white,
      Colors.yellow.shade400,
    ];
    final color = colors[random % colors.length];

    return Positioned(
      left: MediaQuery.of(context).size.width * startX,
      top: -20 + (_confettiAnimation.value * (MediaQuery.of(context).size.height + 40)),
      child: Transform.rotate(
        angle: _confettiAnimation.value * 6.28 * 3,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: random % 2 == 0 ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: random % 2 != 0 ? BorderRadius.circular(2) : null,
          ),
        ),
      ),
    );
  }
}