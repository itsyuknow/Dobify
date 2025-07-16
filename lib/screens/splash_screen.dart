import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();

    // Wait and check if user is logged in
    Future.delayed(const Duration(milliseconds: 3000), () {
      final session = Supabase.instance.client.auth.currentSession;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => session == null ? const LoginScreen() : const HomeScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 130,
                  height: 130,
                ),
                const SizedBox(height: 20),
                const Text(
                  'IronXpress',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'Fast Ironing & Laundry',
                  style: TextStyle(
                    fontSize: 14,
                    letterSpacing: 2,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
