import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:math' as math;
import 'phone_login_screen.dart';
import 'colors.dart';
import 'app_wrapper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late AnimationController _floatController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _floatAnimation;

  bool _isGoogleLoggingIn = false;

  // App Links for handling OAuth redirects
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupAuthListener();
    _initDeepLinks();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.linear,
    ));
    _floatAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
    _slideController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _scaleController.forward();
    });

    // Start continuous animations
    _rotationController.repeat();
    _floatController.repeat(reverse: true);
  }

  void _initDeepLinks() {
    if (kIsWeb) {
      return;
    }

    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen(
          (Uri uri) {
        debugPrint('📱 Deep link received: $uri');
        _handleIncomingLink(uri);
      },
      onError: (err) {
        debugPrint('❌ Deep link error: $err');
      },
    );

    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('📱 Initial deep link: $uri');
        _handleIncomingLink(uri);
      }
    });
  }

  void _handleIncomingLink(Uri uri) async {
    print('🔗 Processing link: ${uri.toString()}');

    if (uri.scheme == 'com.yuknow.ironly' && uri.host == 'oauth-callback') {
      print('✅ OAuth callback received - letting Supabase handle it automatically');

      Timer(const Duration(seconds: 10), () {
        if (mounted && _isGoogleLoggingIn) {
          setState(() {
            _isGoogleLoggingIn = false;
          });
        }
      });
      return;
    }

    print('🔗 Non-OAuth deep link: $uri');
  }

  String _extractGoogleName(User user) {
    final meta = user.userMetadata;
    if (meta is Map) {
      final candidates = [
        'full_name',
        'name',
        'given_name',
        'preferred_username',
      ];
      for (final key in candidates) {
        final value = meta?[key];
        if (value != null) {
          final s = value.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    }
    return '';
  }

  void _setupAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      print('🔐 Auth event: $event');
      print('🔐 Session exists: ${session != null}');
      print('🔐 User: ${session?.user?.email ?? session?.user?.phone}');

      if (event == AuthChangeEvent.signedIn && session != null) {
        if (mounted) {
          setState(() {
            _isGoogleLoggingIn = false;
          });

          HapticFeedback.lightImpact();

          final googleName = _extractGoogleName(session.user);
          String userName = googleName.isNotEmpty
              ? googleName
              : (session.user.email?.split('@')[0]
              ?? session.user.phone?.replaceAll('+91', '')
              ?? 'User');

          _showMessage('Welcome back, $userName!', isError: false);
          print('✅ Login successful');

          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AppWrapper()),
                    (route) => false,
              );
              print('✅ Navigated to AppWrapper for location verification');
            }
          });
        }
      } else if (event == AuthChangeEvent.signedOut) {
        if (mounted) {
          setState(() {
            _isGoogleLoggingIn = false;
          });
        }
      }
    });
  }

  Future<void> _loginWithGoogle() async {
    HapticFeedback.mediumImpact();

    setState(() => _isGoogleLoggingIn = true);

    try {
      final String webRedirect = const String.fromEnvironment('WEB_REDIRECT_URL',
          defaultValue: 'https://www.dobify.in/');

      const String mobileRedirect = 'com.yuknow.ironly://oauth-callback';

      final String redirectUrl = kIsWeb ? webRedirect : mobileRedirect;
      debugPrint('🔐 Using redirect URL: $redirectUrl');

      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode:
        kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGoogleLoggingIn = false);

      String errorMessage = e.toString();
      if (errorMessage.contains('OAuth state mismatch')) {
        errorMessage = 'Authentication session expired. Please try again.';
      } else if (errorMessage.contains('localhost') ||
          errorMessage.contains('127.0.0.1')) {
        errorMessage =
        'Please add your correct Redirect URL in Supabase (no localhost on production).';
      } else if (errorMessage.contains('CANCELLED')) {
        errorMessage = 'Login was cancelled';
      } else if (errorMessage.contains('PlatformException')) {
        errorMessage =
        'Unable to launch authentication. Please try again.';
      } else if (errorMessage.contains('404')) {
        errorMessage =
        'OAuth callback URL not found. Check your Supabase Redirect URL.';
      }

      _showMessage('Google login failed: $errorMessage', isError: true);
      debugPrint('❌ Google login error: $e');
    }
  }

  void _navigateToPhoneLogin() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const PhoneLoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;

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
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
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
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    _floatController.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 3D Background with floating elements
          _build3DBackground(),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kPrimaryColor.withOpacity(0.1),
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.9),
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
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001) // Perspective
                            ..rotateX(0.05) // Slight 3D tilt
                            ..rotateY(-0.02),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: 450,
                              minHeight: MediaQuery.of(context).size.height * 0.75,
                            ),
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                // Primary 3D shadow (bottom-right)
                                BoxShadow(
                                  color: kPrimaryColor.withOpacity(0.25),
                                  blurRadius: 60,
                                  spreadRadius: 8,
                                  offset: const Offset(15, 25),
                                ),
                                // Secondary depth shadow
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 40,
                                  spreadRadius: 2,
                                  offset: const Offset(8, 15),
                                ),
                                // Ambient shadow
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 80,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 30),
                                ),
                                // Inner highlight (top-left)
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.8),
                                  blurRadius: 20,
                                  spreadRadius: -5,
                                  offset: const Offset(-5, -8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Premium Welcome Section (no logo)
                                _buildWelcomeSection(),
                                const SizedBox(height: 60),

                                // Google Login Button
                                _buildGoogleLoginButton(),
                                const SizedBox(height: 20),

                                // OR Divider
                                _buildORDivider(),
                                const SizedBox(height: 20),

                                // Phone Login Button
                                _buildPhoneLoginButton(),
                                const SizedBox(height: 50),

                                // Premium Footer
                                _buildPremiumFooter(),
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
          ),
        ],
      ),
    );
  }

  Widget _build3DBackground() {
    return AnimatedBuilder(
      animation: Listenable.merge([_rotationAnimation, _floatAnimation]),
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              // Floating geometric shapes
              Positioned(
                top: 100 + (_floatAnimation.value * 20),
                left: 50,
                child: Transform.rotate(
                  angle: _rotationAnimation.value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kPrimaryColor.withOpacity(0.1),
                          kPrimaryColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(5, 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 200 + (_floatAnimation.value * -15),
                right: 30,
                child: Transform.rotate(
                  angle: -_rotationAnimation.value * 0.5,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withOpacity(0.1),
                          Colors.blue.withOpacity(0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.1),
                          blurRadius: 25,
                          offset: const Offset(-5, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 150 + (_floatAnimation.value * 25),
                left: 30,
                child: Transform.rotate(
                  angle: _rotationAnimation.value * 0.3,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.withOpacity(0.1),
                          Colors.red.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(3, 6),
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
    );
  }

  // ADD THIS inside _LoginScreenState (above _buildWelcomeSection)
  Widget _gradientHeadline(
      String text, {
        required double size,
        required FontWeight weight,
        double letterSpacing = -0.5,
      }) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = kPrimaryColor.withOpacity(0.55);

    final outline = Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: 1.1,
        foreground: strokePaint,
      ),
    );

    final fill = ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          kPrimaryColor,
          kPrimaryColor.withOpacity(0.85),
        ],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          height: 1.1,
          color: Colors.white,
          shadows: [
            Shadow(
              color: kPrimaryColor.withOpacity(0.28),
              offset: const Offset(0, 2),
              blurRadius: 10,
            ),
            Shadow(
              color: kPrimaryColor.withOpacity(0.20),
              offset: const Offset(0, 6),
              blurRadius: 18,
            ),
          ],
        ),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        outline,
        fill,
      ],
    );
  }


  // REPLACE your existing _buildWelcomeSection with this
  Widget _buildWelcomeSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final smallSize = w < 360 ? 22.0 : (w < 420 ? 26.0 : 30.0);
        final bigSize   = w < 360 ? 34.0 : (w < 420 ? 40.0 : 46.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Headline with slight 3D tilt
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(0.015),
              child: Column(
                children: [
                  _gradientHeadline(
                    'Welcome to',
                    size: smallSize,
                    weight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  const SizedBox(height: 6),
                  _gradientHeadline(
                    'Dobify',
                    size: bigSize,
                    weight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ],
              ),
            ),

            // ↓ Small gap before subtitle
            const SizedBox(height: 8),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'Your premium Ironing service awaits.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  shadows: [
                    Shadow(
                      color: kPrimaryColor.withOpacity(0.18),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                overflow: TextOverflow.visible,
                softWrap: true,
              ),
            ),

            // ↓ Final spacing before the next widget (Google button)
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }






  Widget _buildGoogleLoginButton() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // Perspective
        ..rotateX(0.02)
        ..rotateY(-0.01),
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.grey.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            // Main 3D shadow
            BoxShadow(
              color: Colors.grey.withOpacity(0.25),
              blurRadius: 25,
              offset: const Offset(6, 12),
            ),
            // Depth shadow
            BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 45,
              offset: const Offset(12, 25),
            ),
            // Ambient shadow
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isGoogleLoggingIn ? null : _loginWithGoogle,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _isGoogleLoggingIn
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: kPrimaryColor,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Signing in...',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Enhanced 3D Google logo container
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY(0.1),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(3, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 15,
                            offset: const Offset(6, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: FutureBuilder<bool>(
                          future: _checkImageExists(),
                          builder: (context, snapshot) {
                            if (snapshot.data == true) {
                              return Image.asset(
                                'assets/images/google_logo.png',
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildGoogleLogoFallback();
                                },
                              );
                            } else {
                              return _buildGoogleLogoFallback();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Continue with Google',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced Google logo fallback with 3D effect
  Widget _buildGoogleLogoFallback() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateY(0.05),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            colors: [
              Colors.red.shade600,
              Colors.orange.shade500,
              Colors.yellow.shade500,
              Colors.green.shade500,
              Colors.blue.shade600,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(2, 3),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'G',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Roboto',
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _checkImageExists() async {
    try {
      await rootBundle.load('assets/images/google_logo.png');
      return true;
    } catch (e) {
      print('❌ Google logo image not found: $e');
      return false;
    }
  }

  Widget _buildORDivider() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(0.01),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey.shade300,
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'OR',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey.shade300,
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLoginButton() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // Perspective
        ..rotateX(0.02)
        ..rotateY(0.01),
      child: Container(
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
          border: Border.all(
            color: kPrimaryColor.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            // Main 3D shadow
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.25),
              blurRadius: 25,
              offset: const Offset(6, 12),
            ),
            // Depth shadow
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.15),
              blurRadius: 45,
              offset: const Offset(12, 25),
            ),
            // Ambient shadow
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _navigateToPhoneLogin,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY(-0.1),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(2, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: kPrimaryColor,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Continue with Phone',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumFooter() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(0.01),
      child: Column(
        children: [
          Container(
            height: 1,
            width: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.grey.shade300,
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(0.02),
            child: Text(
              'Doorstep • Instant • Reliable',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFeatureIcon(Icons.security_rounded, 'Secure'),
              const SizedBox(width: 32),
              _buildFeatureIcon(Icons.flash_on_rounded, 'Fast'),
              const SizedBox(width: 32),
              _buildFeatureIcon(Icons.verified_rounded, 'Trusted'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureIcon(IconData icon, String label) {
    return Flexible(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateX(0.1)
          ..rotateY(icon == Icons.security_rounded ? -0.1 :
          icon == Icons.flash_on_rounded ? 0.0 : 0.1),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(3, 5),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.8),
                    blurRadius: 4,
                    offset: const Offset(-1, -2),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: kPrimaryColor,
                size: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}