import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'colors.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  Future<void> _signUp() async {
    try {
      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = response.user;
      if (user != null) {
        // Insert user profile into 'profiles' table
        await supabase.from('ironXpress').insert({
          'id': user.id,
          'full_name': fullNameController.text.trim(),
          'avatar_url': '',
        });

        // Show message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Please login.')),
        );

        // Redirect to LoginScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signup failed: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryColor.withAlpha(26),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 12,
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 4,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign up to get started',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline, color: kPrimaryColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: kPrimaryColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline, color: kPrimaryColor),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _signUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Create Account',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: const Text(
                      "Already have an account? Login",
                      style: TextStyle(color: kPrimaryColor),
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
}
