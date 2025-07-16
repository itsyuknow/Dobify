import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  final supabase = Supabase.instance.client;

  Future<void> resetPassword() async {
    try {
      await supabase.auth.resetPasswordForEmail(emailController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset email sent!')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Enter your email'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Send Reset Email'),
            ),
          ],
        ),
      ),
    );
  }
}
