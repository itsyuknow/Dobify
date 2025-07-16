import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  Future<void> _sendMessage(String userMessage) async {
    setState(() {
      _messages.add({'role': 'user', 'content': userMessage});
      _isLoading = true;
    });

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer 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', // replace this
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "model": "gpt-3.5-turbo",
        "messages": [
          {"role": "system", "content": "You are a helpful laundry service support bot."},
          ..._messages,
        ]
      }),
    );

    if (response.statusCode == 200) {
      final aiReply = json.decode(response.body)['choices'][0]['message']['content'];
      setState(() {
        _messages.add({'role': 'assistant', 'content': aiReply.trim()});
        _isLoading = false;
        _controller.clear();
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to get response from AI')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Support')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue[100] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(message['content'] ?? ''),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type your message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(text);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
