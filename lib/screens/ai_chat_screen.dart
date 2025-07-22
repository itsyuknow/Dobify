import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'colors.dart';

const Color kChatBg = Color(0xFFF7FAFC);
const Color kSenderBubble = Color(0xFFBBDEFB); // bubble for AI
const Color kReceiverBubble = Colors.white;    // bubble for user

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  late String conversationId;
  @override
  void initState() {
    super.initState();
    conversationId = _generateConversationId();
  }

  String _generateConversationId() {
    return "conv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}";
  }

  Future<void> _sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: userMessage.trim()));
      _isLoading = true;
    });
    _controller.clear();

    try {
      final response = await http.post(
        Uri.parse('https://tszgyfzkymgyyvmktmqd.supabase.co/functions/v1/chat'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "message": userMessage.trim(),
          "conversation_id": conversationId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', content: (data['response'] ?? '').trim()));
        });
        await Future.delayed(const Duration(milliseconds: 100));
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        throw Exception('API Error');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to get response from IronBot!')),
      );
    }

    setState(() => _isLoading = false);
  }

  Widget _buildBubble(_ChatMessage message, bool isUser) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: kPrimaryColor,
              child: const Icon(Icons.local_laundry_service, color: Colors.white, size: 20),
              radius: 18,
            ),
          if (!isUser)
            const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? kPrimaryColor : kSenderBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.07),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              backgroundColor: kPrimaryColor,
              child: const Icon(Icons.person, color: kIconColor, size: 20),
              radius: 18,
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            backgroundColor: kPrimaryColor,
            child: const Icon(Icons.local_laundry_service, color: Colors.white, size: 20),
            radius: 18,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: kSenderBubble,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('IronBot is replying...', style: TextStyle(fontSize: 15, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kChatBg,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: kPrimaryColor,
        // Title is now text only, no icon
        title: const Text(
          "IronBot Support",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 12, bottom: 14),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return _buildTypingIndicator();
                }
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return _buildBubble(msg, isUser);
              },
            ),
          ),
          const Divider(height: 0, color: Colors.transparent),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_isLoading,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                        onSubmitted: _isLoading ? null : _sendMessage,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send_rounded, color: _isLoading ? Colors.grey : kPrimaryColor, size: 26),
                      onPressed: _isLoading
                          ? null
                          : () {
                        final text = _controller.text.trim();
                        if (text.isNotEmpty) {
                          _sendMessage(text);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  _ChatMessage({required this.role, required this.content});
}
