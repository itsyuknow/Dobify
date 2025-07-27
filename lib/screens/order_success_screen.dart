import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import 'profile_screen.dart';
import 'order_screen.dart'; // Import the OrdersScreen

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

  // Dropdown states
  bool _isOrderDetailsExpanded = false;
  bool _isScheduleExpanded = false;
  bool _isBillExpanded = false;
  bool _isInfoExpanded = false;

  // Animation Controllers
  late AnimationController _fullScreenController;
  late AnimationController _contentController;
  late AnimationController _particleController;
  late AnimationController _pulseController;
  late AnimationController _continuousCheckController;

  // Full Screen Animations
  late Animation<double> _backgroundAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoGlowAnimation;
  late Animation<double> _textRevealAnimation;
  late Animation<double> _particleSpreadAnimation;

  // Content Animations
  late Animation<double> _contentFadeAnimation;
  late Animation<Offset> _contentSlideAnimation;
  late Animation<double> _cardStaggerAnimation;

  // Continuous Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _continuousCheckAnimation;

  bool _showFullScreen = true;
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBillingDetails();
    _startAnimationSequence();
  }

  void _initializeAnimations() {
    // Full Screen Controller (5 seconds)
    _fullScreenController = AnimationController(
      duration: const Duration(milliseconds: 5000),
      vsync: this,
    );

    // Content Controller (1.5 seconds)
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Continuous Controllers
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _continuousCheckController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Full Screen Animations
    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fullScreenController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
    ));

    _logoScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fullScreenController,
      curve: const Interval(0.2, 0.6, curve: Curves.elasticOut),
    ));

    _logoGlowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fullScreenController,
      curve: const Interval(0.3, 0.8, curve: Curves.easeInOut),
    ));

    _textRevealAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fullScreenController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
    ));

    _particleSpreadAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fullScreenController,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    ));

    // Content Animations
    _contentFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    ));

    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
    ));

    _cardStaggerAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    ));

    // Continuous Animations
    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _continuousCheckAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_continuousCheckController);
  }

  void _startAnimationSequence() async {
    // Start continuous animations
    _particleController.repeat();
    _pulseController.repeat(reverse: true);

    // Start full screen animation
    _fullScreenController.forward();

    // Wait 5 seconds then show content
    await Future.delayed(const Duration(milliseconds: 5000));
    if (mounted) {
      setState(() {
        _showFullScreen = false;
        _showContent = true;
      });
      _contentController.forward();
      // Start continuous check animation for the header
      _continuousCheckController.repeat();
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

  // Handle back button press
  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        elevation: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            const Flexible(
              child: Text(
                'Order Confirmed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your order has been placed successfully. Where would you like to go?',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              'Stay Here',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 4,
            ),
            child: const Text(
              'Continue Shopping',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      _navigateToOrderScreen();
      return false;
    }
    return false;
  }

  // Navigate to profile screen
  void _navigateToProfile() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      ),
          (route) => false,
    );
  }

  // Navigate to order screen - FIXED: Direct navigation instead of named route
  void _navigateToOrderScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const OrdersScreen(),
      ),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _fullScreenController.dispose();
    _contentController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    _continuousCheckController.dispose();
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
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _fullScreenController,
              _contentController,
              _particleController,
              _pulseController,
              _continuousCheckController,
            ]),
            builder: (context, child) {
              return Stack(
                children: [
                  // Full Screen Success Animation (5 seconds)
                  if (_showFullScreen) _buildPremiumFullScreenAnimation(),

                  // Main Content (after animation)
                  if (_showContent) _buildMainContent(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumFullScreenAnimation() {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: AnimatedBuilder(
        animation: _backgroundAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  kPrimaryColor.withOpacity(0.95 * _backgroundAnimation.value),
                  kPrimaryColor.withOpacity(0.90 * _backgroundAnimation.value),
                  kPrimaryColor.withOpacity(0.85 * _backgroundAnimation.value),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Enhanced Background Particles
                ...List.generate(60, (index) => _buildCelebrationParticle(index)),

                // Main Success Content
                Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Premium Logo Container
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Enhanced Glow Effect
                              AnimatedBuilder(
                                animation: _logoGlowAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 300 * _logoGlowAnimation.value,
                                    height: 300 * _logoGlowAnimation.value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.6 * _logoGlowAnimation.value),
                                          Colors.white.withOpacity(0.3 * _logoGlowAnimation.value),
                                          Colors.white.withOpacity(0.1 * _logoGlowAnimation.value),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Pulsing Ring
                              ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  width: 180,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.4),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),

                              // Main Success Icon
                              ScaleTransition(
                                scale: _logoScaleAnimation,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Colors.white, Color(0xFFF8F8F8)],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withOpacity(0.8),
                                        blurRadius: 40,
                                        spreadRadius: 15,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 30,
                                        offset: const Offset(0, 15),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: AnimatedBuilder(
                                      animation: _logoScaleAnimation,
                                      builder: (context, child) {
                                        return CustomPaint(
                                          size: const Size(70, 70),
                                          painter: PremiumCheckMarkPainter(
                                            _logoScaleAnimation.value,
                                            kPrimaryColor,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 50),

                          // Enhanced Success Text
                          FadeTransition(
                            opacity: _textRevealAnimation,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: [
                                  // Main Success Text
                                  ShaderMask(
                                    shaderCallback: (bounds) => const LinearGradient(
                                      colors: [Colors.white, Color(0xFFF5F5F5), Colors.white],
                                    ).createShader(bounds),
                                    child: const Text(
                                      '✨ SUCCESS ✨',
                                      style: TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 6,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black26,
                                            offset: Offset(0, 6),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  // Order Confirmation Message
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.4),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Text(
                                      'Your Order Has Been Confirmed',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // Order ID
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.receipt_long_outlined,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Order #${widget.orderId}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white.withOpacity(0.95),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCelebrationParticle(int index) {
    final random = (index * 789) % 1000;
    final startX = (random % 100) / 100.0;
    final startY = (random * 3 % 100) / 100.0;
    final size = 6.0 + (random % 10);
    final colors = [
      Colors.white,
      Colors.yellow.shade100,
      Colors.pink.shade50,
      Colors.blue.shade50,
    ];

    return Positioned(
      left: MediaQuery.of(context).size.width * startX,
      top: MediaQuery.of(context).size.height * startY,
      child: AnimatedBuilder(
        animation: _particleSpreadAnimation,
        builder: (context, child) {
          // Constrain particle movement to stay within screen bounds
          final maxMovement = 150.0;
          final moveX = (startX - 0.5) * maxMovement * _particleSpreadAnimation.value;
          final moveY = (startY - 0.5) * maxMovement * _particleSpreadAnimation.value;

          return Transform.translate(
            offset: Offset(
              moveX.clamp(-MediaQuery.of(context).size.width * 0.4, MediaQuery.of(context).size.width * 0.4),
              moveY.clamp(-MediaQuery.of(context).size.height * 0.4, MediaQuery.of(context).size.height * 0.4),
            ),
            child: Transform.rotate(
              angle: _particleSpreadAnimation.value * 4 * pi + index,
              child: Opacity(
                opacity: (1 - _particleSpreadAnimation.value) * 0.7,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: colors[random % colors.length],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors[random % colors.length].withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    return FadeTransition(
      opacity: _contentFadeAnimation,
      child: SlideTransition(
        position: _contentSlideAnimation,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Premium Success Header
                _buildAnimatedCard(
                  delay: 0,
                  child: _buildHeaderCard(),
                ),

                const SizedBox(height: 16),

                // Professional Dropdown Cards
                _buildAnimatedCard(
                  delay: 0.1,
                  child: _buildProfessionalDropdownCard(
                    'Order Details',
                    Icons.shopping_bag_outlined,
                    _isOrderDetailsExpanded,
                        () => setState(() => _isOrderDetailsExpanded = !_isOrderDetailsExpanded),
                    _buildOrderDetailsContent(),
                  ),
                ),

                const SizedBox(height: 12),

                _buildAnimatedCard(
                  delay: 0.2,
                  child: _buildProfessionalDropdownCard(
                    'Schedule Details',
                    Icons.schedule_outlined,
                    _isScheduleExpanded,
                        () => setState(() => _isScheduleExpanded = !_isScheduleExpanded),
                    _buildScheduleContent(),
                  ),
                ),

                const SizedBox(height: 12),

                _buildAnimatedCard(
                  delay: 0.3,
                  child: _buildProfessionalDropdownCard(
                    'Bill Summary',
                    Icons.receipt_outlined,
                    _isBillExpanded,
                        () => setState(() => _isBillExpanded = !_isBillExpanded),
                    _buildBillContent(),
                  ),
                ),

                const SizedBox(height: 12),

                _buildAnimatedCard(
                  delay: 0.4,
                  child: _buildProfessionalDropdownCard(
                    'What\'s Next?',
                    Icons.info_outline,
                    _isInfoExpanded,
                        () => setState(() => _isInfoExpanded = !_isInfoExpanded),
                    _buildInfoContent(),
                  ),
                ),

                const SizedBox(height: 32),

                // Action Buttons
                _buildAnimatedCard(
                  delay: 0.5,
                  child: _buildActionButtons(),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.85)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated Check Icon
          ScaleTransition(
            scale: Animation.fromValueListenable(
              ValueNotifier(0.9 + (_continuousCheckAnimation.value * 0.1)),
            ),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: AnimatedBuilder(
                animation: _continuousCheckAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(30, 30),
                    painter: ContinuousCheckMarkPainter(
                      _continuousCheckAnimation.value,
                      Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Order Confirmed! 🎉',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thank you for choosing our service',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Order ID: ${widget.orderId}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedCard({required double delay, required Widget child}) {
    return AnimatedBuilder(
      animation: _cardStaggerAnimation,
      builder: (context, _) {
        final animationValue = (_cardStaggerAnimation.value - delay).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, (1 - animationValue) * 20),
          child: Opacity(
            opacity: animationValue,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildProfessionalDropdownCard(
      String title,
      IconData icon,
      bool isExpanded,
      VoidCallback onTap,
      Widget content,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: kPrimaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF64748B),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: content,
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ENHANCED: Order details with proper image display using same logic as order history
  Widget _buildOrderDetailsContent() {
    return Column(
      children: [
        const SizedBox(height: 8),
        ...widget.cartItems.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              // ENHANCED: Product Image Container with same logic as order history
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.grey.shade100,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildProductImage(item),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['product_name'] ?? 'Unknown Product',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Qty: ${item['product_quantity'] ?? 0}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ENHANCED: Product image builder with same logic as order history screen
  Widget _buildProductImage(Map<String, dynamic> item) {
    // Try to get image from multiple sources like in order history
    String? imageUrl;

    // First check if item has product_image (from cart/order_items)
    if (item['product_image'] != null &&
        item['product_image'].toString().isNotEmpty &&
        item['product_image'].toString() != 'null') {
      imageUrl = item['product_image'];
    }
    // Then check if item has image_url (from products table)
    else if (item['image_url'] != null &&
        item['image_url'].toString().isNotEmpty &&
        item['image_url'].toString() != 'null') {
      imageUrl = item['image_url'];
    }

    // If we have a valid image URL, display it
    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.all(12),
            child: Icon(
              Icons.local_laundry_service,
              color: kPrimaryColor,
              size: 24,
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      );
    }

    // Fallback to icon if no image
    return Container(
      padding: const EdgeInsets.all(12),
      child: Icon(
        Icons.local_laundry_service,
        color: kPrimaryColor,
        size: 24,
      ),
    );
  }

  Widget _buildScheduleContent() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildScheduleItem(
          Icons.local_laundry_service,
          'Pickup',
          '${_formatDate(widget.pickupDate)} at ${widget.pickupSlot['display_time'] ?? '${widget.pickupSlot['start_time']} - ${widget.pickupSlot['end_time']}'}',
        ),
        const SizedBox(height: 8),
        _buildScheduleItem(
          Icons.local_shipping,
          'Delivery',
          '${_formatDate(widget.deliveryDate)} at ${widget.deliverySlot['display_time'] ?? '${widget.deliverySlot['start_time']} - ${widget.deliverySlot['end_time']}'}',
        ),
        const SizedBox(height: 8),
        _buildScheduleItem(
          Icons.flash_on,
          'Delivery Type',
          widget.isExpressDelivery ? 'Express Delivery ⚡' : 'Standard Delivery 📦',
        ),
        const SizedBox(height: 8),
        _buildScheduleItem(
          Icons.location_on,
          'Address',
          '${widget.selectedAddress['address_line_1']}, ${widget.selectedAddress['city']} - ${widget.selectedAddress['pincode']}',
        ),
      ],
    );
  }

  Widget _buildScheduleItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: kPrimaryColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillContent() {
    if (isLoadingBilling) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
          ),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              if (billingDetails != null) ...[
                _buildBillRow('Subtotal', '₹${billingDetails!['subtotal']?.toStringAsFixed(2) ?? '0.00'}'),
                if ((billingDetails!['minimum_cart_fee']?.toDouble() ?? 0.0) > 0)
                  _buildBillRow('Minimum Cart Fee', '₹${billingDetails!['minimum_cart_fee']?.toStringAsFixed(2) ?? '0.00'}'),
                _buildBillRow('Platform Fee', '₹${billingDetails!['platform_fee']?.toStringAsFixed(2) ?? '0.00'}'),
                _buildBillRow('Service Tax', '₹${billingDetails!['service_tax']?.toStringAsFixed(2) ?? '0.00'}'),
                _buildBillRow(
                  'Delivery Fee',
                  '₹${billingDetails!['delivery_fee']?.toStringAsFixed(2) ?? '0.00'}',
                ),
                if ((billingDetails!['discount_amount']?.toDouble() ?? 0.0) > 0)
                  _buildBillRow('Discount', '-₹${billingDetails!['discount_amount']?.toStringAsFixed(2) ?? '0.00'}', color: Colors.green.shade700),
                if (billingDetails!['applied_coupon_code'] != null)
                  _buildBillRow('Coupon Applied', billingDetails!['applied_coupon_code'], color: Colors.green.shade700),
              ] else ...[
                _buildBillRow('Subtotal', '₹${(widget.totalAmount + widget.discount).toStringAsFixed(2)}'),
                if (widget.discount > 0)
                  _buildBillRow('Discount', '-₹${widget.discount.toStringAsFixed(2)}', color: Colors.green.shade700),
                if (widget.appliedCouponCode != null)
                  _buildBillRow('Coupon Applied', widget.appliedCouponCode!, color: Colors.green.shade700),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPrimaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
          ),
          child: _buildBillRow(
            '💰 Total Amount',
            '₹${billingDetails?['total_amount']?.toStringAsFixed(2) ?? widget.totalAmount.toStringAsFixed(2)}',
            isTotal: true,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildBillRow(
                'Payment Method',
                widget.paymentMethod == 'online' ? '💳 Online Payment' : '💰 Cash on Delivery',
              ),
              if (widget.paymentId != null) ...[
                const SizedBox(height: 6),
                _buildBillRow('Payment ID', widget.paymentId!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBillRow(String label, String value, {Color? color, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 14 : 12,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: color ?? const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: color ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoContent() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildInfoItem(
          Icons.schedule_rounded,
          'Your items will be picked up as scheduled',
          '🕐',
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          Icons.notifications_active_rounded,
          'You\'ll receive updates via SMS and notifications',
          '📱',
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          Icons.support_agent_rounded,
          '24/7 customer support available',
          '🎧',
        ),
        if (widget.isExpressDelivery) ...[
          const SizedBox(height: 8),
          _buildInfoItem(
            Icons.flash_on_rounded,
            'Express delivery selected for faster service',
            '⚡',
          ),
        ],
        const SizedBox(height: 8),
        _buildInfoItem(
          Icons.star_rounded,
          'Thank you for choosing our service!',
          '⭐',
        ),
      ],
    );
  }

  Widget _buildInfoItem(IconData icon, String text, String emoji) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: kPrimaryColor, size: 14),
          ),
          const SizedBox(width: 10),
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: kPrimaryColor,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // View Your Orders Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _navigateToProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              shadowColor: kPrimaryColor.withOpacity(0.3),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_rounded, size: 20),
                SizedBox(width: 12),
                Text(
                  'View Your Orders',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Continue Shopping Button - FIXED: Navigate to OrdersScreen directly
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _navigateToOrderScreen,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kPrimaryColor, width: 2),
              backgroundColor: Colors.white,
              foregroundColor: kPrimaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_rounded, size: 20),
                SizedBox(width: 12),
                Text(
                  'Continue Shopping',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Premium CheckMark Painter for smooth animated check mark
class PremiumCheckMarkPainter extends CustomPainter {
  final double animationValue;
  final Color color;

  PremiumCheckMarkPainter(this.animationValue, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Define check mark coordinates
    final firstLineEnd = Offset(size.width * 0.35, size.height * 0.65);
    final secondLineEnd = Offset(size.width * 0.8, size.height * 0.25);

    if (animationValue > 0.0) {
      // First line of check mark (40% of animation)
      if (animationValue <= 0.4) {
        final progress = animationValue / 0.4;
        path.moveTo(size.width * 0.2, size.height * 0.5);
        path.lineTo(
          size.width * 0.2 + (firstLineEnd.dx - size.width * 0.2) * progress,
          size.height * 0.5 + (firstLineEnd.dy - size.height * 0.5) * progress,
        );
      } else {
        // Complete first line and animate second line
        path.moveTo(size.width * 0.2, size.height * 0.5);
        path.lineTo(firstLineEnd.dx, firstLineEnd.dy);

        // Second line of check mark
        final progress = (animationValue - 0.4) / 0.6;
        path.lineTo(
          firstLineEnd.dx + (secondLineEnd.dx - firstLineEnd.dx) * progress,
          firstLineEnd.dy + (secondLineEnd.dy - firstLineEnd.dy) * progress,
        );
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PremiumCheckMarkPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// Continuous CheckMark Painter for the header icon
class ContinuousCheckMarkPainter extends CustomPainter {
  final double animationValue;
  final Color color;

  ContinuousCheckMarkPainter(this.animationValue, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Define check mark coordinates
    final firstLineEnd = Offset(size.width * 0.35, size.height * 0.65);
    final secondLineEnd = Offset(size.width * 0.8, size.height * 0.25);

    // Always show complete check mark
    path.moveTo(size.width * 0.2, size.height * 0.5);
    path.lineTo(firstLineEnd.dx, firstLineEnd.dy);
    path.lineTo(secondLineEnd.dx, secondLineEnd.dy);

    // Add glow effect based on animation
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3 + (animationValue * 0.5))
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ContinuousCheckMarkPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}