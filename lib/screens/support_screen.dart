import 'package:flutter/material.dart';
import 'ai_chat_screen.dart'; // Make sure this file exists
import 'colors.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Support'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Need help? Our AI assistant is ready to help you!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AiChatScreen()),
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text(
                  'Chat with AI Support',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
