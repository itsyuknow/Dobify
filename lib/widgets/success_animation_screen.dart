import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/colors.dart';
import '../screens/home_screen.dart';

class SuccessAnimationScreen extends StatefulWidget {
  const SuccessAnimationScreen({super.key});

  @override
  State<SuccessAnimationScreen> createState() => _SuccessAnimationScreenState();
}

class _SuccessAnimationScreenState extends State<SuccessAnimationScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _opacity = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();

    _clearCartAndGoHome(); // Start next step after animation
  }

  Future<void> _clearCartAndGoHome() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      await Future.delayed(const Duration(milliseconds: 1800));
      try {
        await supabase.from('cart').delete().eq('id', user.id);
      } catch (e) {
        debugPrint('Cart clear error: $e');
      }
    }

    // Delay before navigating to Home
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPrimaryColor,
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryColor.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(30),
                  child: const Icon(Icons.check_circle_outline, size: 80, color: Colors.white),
                ),
                const SizedBox(height: 30),
                const Text(
                  "Order Placed!",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Thanks for choosing IronXpress!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
