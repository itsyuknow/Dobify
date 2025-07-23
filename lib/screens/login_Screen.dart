// ✅ COMPLETE OAUTH REDIRECT FIX
// Replace your existing login screen with this updated version

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart'; // Add this dependency
import 'dart:async';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'phone_login_screen.dart';
import 'colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoggingIn = false;
  bool _isGoogleLoggingIn = false;
  bool _passwordVisible = false;

  // ✅ NEW: App Links for handling OAuth redirects
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupAuthListener();
    _initDeepLinks(); // ✅ NEW: Initialize deep link handling
  }

  // ✅ NEW: Setup deep link handling for OAuth
  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Listen for incoming links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
          (Uri uri) {
        print('📱 Deep link received: $uri');
        _handleIncomingLink(uri);
      },
      onError: (err) {
        print('❌ Deep link error: $err');
      },
    );

    // Handle link when app is launched from terminated state
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        print('📱 Initial deep link: $uri');
        _handleIncomingLink(uri);
      }
    });
  }

  // ✅ NEW: Handle OAuth redirect links
  void _handleIncomingLink(Uri uri) {
    print('🔗 Processing link: ${uri.toString()}');

    // Check if this is a Supabase auth callback
    if (uri.scheme == 'com.yuknow.ironly' && uri.host == 'auth-callback') {
      print('✅ OAuth callback detected');

      // Extract the fragment which contains the auth tokens
      final fragment = uri.fragment;
      if (fragment.isNotEmpty) {
        // Parse the fragment to get auth tokens
        final params = Uri.splitQueryString(fragment);
        final accessToken = params['access_token'];
        final refreshToken = params['refresh_token'];

        if (accessToken != null) {
          print('✅ Access token found in callback');
          _handleOAuthSuccess();
        } else {
          print('❌ No access token in callback');
          _handleOAuthError('No access token received');
        }
      }
    }
  }

  void _handleOAuthSuccess() {
    setState(() {
      _isGoogleLoggingIn = false;
    });
    _showMessage('Successfully signed in with Google!', isError: false);
    print('✅ OAuth login successful');
  }

  void _handleOAuthError(String error) {
    setState(() {
      _isGoogleLoggingIn = false;
    });
    _showMessage('Google login failed: $error', isError: true);
    print('❌ OAuth error: $error');
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _slideController = AnimationController(
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

    _fadeController.forward();
    _slideController.forward();
  }

  void _setupAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      print('🔐 Auth event: $event');

      if (event == AuthChangeEvent.signedIn && session != null) {
        setState(() {
          _isLoggingIn = false;
          _isGoogleLoggingIn = false;
        });
        _showMessage('Welcome back!', isError: false);
        print('✅ Login successful, user: ${session.user.email}');

        // ✅ Navigate to home screen or handle successful login
        // Navigator.pushReplacementNamed(context, '/home');
      } else if (event == AuthChangeEvent.signedOut) {
        setState(() {
          _isLoggingIn = false;
          _isGoogleLoggingIn = false;
        });
      }
    });
  }

  Future<void> _loginWithEmail() async {
    if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      _showMessage('Please fill in all fields', isError: true);
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final res = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (res.user != null) {
        // Success will be handled by auth listener
      }
    } catch (e) {
      setState(() {
        _isLoggingIn = false;
      });
      _showMessage('Login failed: ${e.toString()}', isError: true);
    }
  }

  // ✅ UPDATED: Google OAuth with better redirect handling
  Future<void> _loginWithGoogle() async {
    setState(() {
      _isGoogleLoggingIn = true;
    });

    try {
      print('🔐 Starting Google OAuth...');

      // ✅ Use the correct redirect URL that matches your Supabase settings
      final authResponse = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.yuknow.ironly://auth-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      print('🔐 OAuth initiated: ${authResponse.toString()}');

      // Note: Don't set loading to false here, let the auth listener handle it

    } catch (e) {
      setState(() {
        _isGoogleLoggingIn = false;
      });
      _showMessage('Google login failed: ${e.toString()}', isError: true);
      print('❌ Google login error: $e');
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _linkSubscription?.cancel(); // ✅ NEW: Cancel deep link subscription
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              kPrimaryColor.withOpacity(0.03),
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 500,
                      minHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.1),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 15),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ WELCOME SECTION
                          _buildWelcomeSection(),
                          const SizedBox(height: 40),

                          // ✅ EMAIL FIELD
                          _buildPremiumTextField(
                            controller: emailController,
                            label: 'Email Address',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 20),

                          // ✅ PASSWORD FIELD WITH EYE BUTTON
                          _buildPasswordField(),
                          const SizedBox(height: 16),

                          // ✅ FORGOT PASSWORD
                          _buildForgotPassword(),
                          const SizedBox(height: 32),

                          // ✅ LOGIN BUTTON
                          _buildLoginButton(),
                          const SizedBox(height: 24),

                          // ✅ OR DIVIDER
                          _buildOrDivider(),
                          const SizedBox(height: 24),

                          // ✅ SOCIAL LOGIN BUTTONS
                          _buildSocialLoginButtons(),
                          const SizedBox(height: 32),

                          // ✅ SIGN UP LINK
                          _buildSignUpLink(),
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

  // ✅ WELCOME SECTION
  Widget _buildWelcomeSection() {
    return Column(
      children: [
        // Premium logo with subtle shine effect
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.3),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_laundry_service_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 24),

        // Welcome text with centered alignment
        Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
              ).createShader(bounds),
              child: const Text(
                'Welcome to ironXpress',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to continue your laundry journey',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ✅ PASSWORD FIELD WITH EYE BUTTON
  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: passwordController,
        obscureText: !_passwordVisible,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: 'Password',
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.lock_outline,
              color: kPrimaryColor,
              size: 20,
            ),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _passwordVisible ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey.shade600,
            ),
            onPressed: () {
              setState(() {
                _passwordVisible = !_passwordVisible;
              });
            },
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  // ✅ FORGOT PASSWORD
  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
          );
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Forgot Password?',
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // ✅ LOGIN BUTTON
  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoggingIn ? null : _loginWithEmail,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoggingIn
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        )
            : const Text(
          'Sign In',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ✅ OR DIVIDER
  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.grey.shade300,
            thickness: 1,
            height: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Colors.grey.shade300,
            thickness: 1,
            height: 1,
          ),
        ),
      ],
    );
  }

  // ✅ SOCIAL LOGIN BUTTONS
  Widget _buildSocialLoginButtons() {
    return Column(
      children: [
        // Google Login
        _buildSocialButton(
          onPressed: _isGoogleLoggingIn ? null : _loginWithGoogle,
          icon: Icons.g_mobiledata,
          label: 'Continue with Google',
          color: Colors.red,
          isLoading: _isGoogleLoggingIn,
        ),
        const SizedBox(height: 12),

        // Phone Login
        _buildSocialButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
            );
          },
          icon: Icons.phone_android_rounded,
          label: 'Continue with Phone',
          color: Colors.green,
          isLoading: false,
        ),
      ],
    );
  }

  // ✅ SOCIAL BUTTON
  Widget _buildSocialButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required bool isLoading,
  }) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.05),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: color,
            strokeWidth: 2,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ SIGN UP LINK
  Widget _buildSignUpLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpScreen()),
            );
          },
          child: Text(
            'Sign Up',
            style: TextStyle(
              color: kPrimaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.underline,
              decorationThickness: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ✅ PREMIUM TEXT FIELD (for email)
  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: kPrimaryColor,
              size: 20,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }
}