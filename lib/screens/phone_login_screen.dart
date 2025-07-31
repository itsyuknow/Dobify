import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'colors.dart';
import 'app_wrapper.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> with TickerProviderStateMixin {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final supabase = Supabase.instance.client;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  bool _isLoading = false;
  bool _otpSent = false;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupAuthListener();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _fadeController.forward();
    _slideController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _scaleController.forward();
    });
  }

  void _setupAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      print('🔐 Phone Auth event: $event');
      print('🔐 Session: ${session?.user?.phone}');

      if (event == AuthChangeEvent.signedIn && session != null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          // Haptic feedback for success
          HapticFeedback.lightImpact();

          _showMessage('🎉 Welcome! You\'re now signed in.', isError: false);
          print('✅ Phone login successful, user: ${session.user.phone}');

          // Navigate to AppWrapper after successful login
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              // ✅ NAVIGATE TO APP WRAPPER - NOT DIRECTLY TO HOME
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AppWrapper()),
                    (route) => false,
              );

              print('✅ Navigated to AppWrapper for location verification');
            }
          });
        }
      }
    });
  }

  void _startResendCountdown() {
    setState(() {
      _resendCountdown = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCountdown--;
      });

      if (_resendCountdown <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOTP() async {
    if (phoneController.text.trim().isEmpty) {
      _showMessage('Please enter your phone number', isError: true);
      return;
    }

    String phoneNumber = phoneController.text.trim();

    // Add +91 if not present
    if (!phoneNumber.startsWith('+91')) {
      phoneNumber = '+91$phoneNumber';
    }

    // Validate Indian phone number
    if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(phoneNumber)) {
      _showMessage('Please enter a valid Indian phone number (10 digits starting with 6-9)', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await supabase.auth.signInWithOtp(
        phone: phoneNumber,
      );

      setState(() {
        _isLoading = false;
        _otpSent = true;
      });

      // Start countdown for resend
      _startResendCountdown();

      // Haptic feedback
      HapticFeedback.selectionClick();

      _showMessage('📱 OTP sent to $phoneNumber!', isError: false);

      // Focus on OTP field
      Future.delayed(const Duration(milliseconds: 500), () {
        FocusScope.of(context).nextFocus();
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Failed to send OTP: ${e.toString()}', isError: true);
    }
  }

  Future<void> _verifyOTP() async {
    if (otpController.text.trim().isEmpty) {
      _showMessage('Please enter the OTP', isError: true);
      return;
    }

    if (otpController.text.trim().length != 6) {
      _showMessage('Please enter the complete 6-digit OTP', isError: true);
      return;
    }

    String phoneNumber = phoneController.text.trim();
    if (!phoneNumber.startsWith('+91')) {
      phoneNumber = '+91$phoneNumber';
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔐 Verifying OTP: ${otpController.text.trim()}');
      print('🔐 Phone number: $phoneNumber');

      final response = await supabase.auth.verifyOTP(
        phone: phoneNumber,
        token: otpController.text.trim(),
        type: OtpType.sms,
      );

      print('🔐 Verify response: ${response.user?.id}');
      print('🔐 Session: ${response.session?.accessToken != null}');

      if (response.user != null && response.session != null) {
        print('✅ OTP verification successful');
        // Show immediate success message
        _showMessage('✅ Verification successful! Signing you in...', isError: false);

        // Force navigation after successful verification
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            // Navigate to AppWrapper instead of home
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AppWrapper()),
                  (route) => false,
            );

            print('✅ Manual navigation to AppWrapper completed');
          }
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        _showMessage('Verification failed. Please try again.', isError: true);
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      // Haptic feedback for error
      HapticFeedback.heavyImpact();

      print('❌ OTP verification error: $e');
      _showMessage('Invalid OTP. Please try again.', isError: true);

      // Clear OTP field for retry
      otpController.clear();
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
        duration: Duration(milliseconds: isError ? 4000 : 3000),
        elevation: 8,
      ),
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kPrimaryColor.withOpacity(0.08),
              Colors.white,
              Colors.white,
              kPrimaryColor.withOpacity(0.05),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: 450,
                        minHeight: MediaQuery.of(context).size.height * 0.7,
                      ),
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.12),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 15),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 25,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Back button
                          _buildBackButton(),
                          const SizedBox(height: 20),

                          // Logo & Title Section
                          _buildHeaderSection(),
                          const SizedBox(height: 40),

                          if (!_otpSent) ...[
                            // Phone number input
                            _buildPhoneField(),
                            const SizedBox(height: 32),

                            // Send OTP button
                            _buildSendOTPButton(),
                          ] else ...[
                            // OTP input
                            _buildOTPField(),
                            const SizedBox(height: 24),

                            // Resend OTP section
                            _buildResendSection(),
                            const SizedBox(height: 32),

                            // Verify button
                            _buildVerifyButton(),
                          ],

                          const SizedBox(height: 32),

                          // Back to login options
                          _buildBackToLoginOptions(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.grey.shade700,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        // Premium logo with animation
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
                kPrimaryColor.withOpacity(0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.3),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.15),
                blurRadius: 50,
                offset: const Offset(0, 25),
              ),
            ],
          ),
          child: Icon(
            _otpSent ? Icons.security_rounded : Icons.phone_android_rounded,
            color: Colors.white,
            size: 45,
          ),
        ),
        const SizedBox(height: 28),

        // Title with gradient effect
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              kPrimaryColor,
              kPrimaryColor.withOpacity(0.7),
            ],
          ).createShader(bounds),
          child: Text(
            _otpSent ? 'Verify Code' : 'Phone Login',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Subtitle
        Text(
          _otpSent
              ? 'Enter the 6-digit verification code\nsent to ${phoneController.text.trim()}'
              : 'Enter your phone number to receive\na verification code',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: phoneController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
          FilteringTextInputFormatter.allow(RegExp(r'^[6-9][0-9]*')),
        ],
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
        decoration: InputDecoration(
          labelText: 'Phone Number',
          hintText: 'Enter 10-digit number',
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kPrimaryColor.withOpacity(0.15),
                  kPrimaryColor.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              color: kPrimaryColor,
              size: 22,
            ),
          ),
          prefix: Container(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '+91 ',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: kPrimaryColor, width: 2.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        ),
      ),
    );
  }

  Widget _buildOTPField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: otpController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 8,
        ),
        decoration: InputDecoration(
          labelText: 'Verification Code',
          hintText: '• • • • • •',
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 24,
            letterSpacing: 12,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kPrimaryColor.withOpacity(0.15),
                  kPrimaryColor.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.security_rounded,
              color: kPrimaryColor,
              size: 22,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: kPrimaryColor, width: 2.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        ),
      ),
    );
  }

  Widget _buildSendOTPButton() {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            kPrimaryColor,
            kPrimaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.2),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _sendOTP,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _isLoading
                ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Sending...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            )
                : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  'Send Verification Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyButton() {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            kPrimaryColor,
            kPrimaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.2),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _verifyOTP,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _isLoading
                ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Verifying...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            )
                : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  'Verify & Sign In',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResendSection() {
    return Column(
      children: [
        Text(
          "Didn't receive the code?",
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        if (_resendCountdown > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              'Resend in ${_resendCountdown}s',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: kPrimaryColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _sendOTP,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: kPrimaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Resend Code',
                        style: TextStyle(
                          color: kPrimaryColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBackToLoginOptions() {
    return Column(
      children: [
        Container(
          height: 1,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Prefer other options? ",
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
              },
              child: Text(
                'Back to Login',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: kPrimaryColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}