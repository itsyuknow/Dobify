import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'colors.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  _ChatMessage({required this.role, required this.content});
}

class _AiChatScreenState extends State<AiChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  late String conversationId;
  String? supportPhone;

  @override
  void initState() {
    super.initState();
    conversationId = _generateConversationId();
    fetchSupportPhone();
  }

  String _generateConversationId() {
    return "conv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}";
  }

  Future<void> fetchSupportPhone() async {
    final response = await http.get(
      Uri.parse('https://qehtglgjhzdlqcjujpp.supabase.co/rest/v1/ui_contacts?key=eq.support'),
      headers: {
        'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List && data.isNotEmpty) {
        setState(() {
          supportPhone = data[0]['value'];
        });
      }
    }
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
        headers: { 'Content-Type': 'application/json' },
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
        await Future.delayed(const Duration(milliseconds: 110));
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
      padding: EdgeInsets.only(
        top: 12,
        left: isUser ? 60 : 10,
        right: isUser ? 10 : 60,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.smart_toy_rounded, color: kPrimaryColor, size: 23),
              radius: 17,
            ),
          if (!isUser) const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? kPrimaryColor : Colors.white,
                    gradient: isUser
                        ? LinearGradient(colors: [
                      kPrimaryColor.withOpacity(0.95), kPrimaryColor,
                    ])
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(22),
                      topRight: const Radius.circular(22),
                      bottomRight: Radius.circular(isUser ? 7 : 22),
                      bottomLeft: Radius.circular(isUser ? 22 : 7),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? kPrimaryColor.withOpacity(0.17)
                            : kPrimaryColor.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        height: 1.22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 7),
          if (isUser)
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: kPrimaryColor, size: 22),
              radius: 17,
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 13, bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.smart_toy_rounded, color: kPrimaryColor, size: 18),
            radius: 15,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    height: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 470 + i * 100),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kPrimaryColor.withOpacity(0.7 - i * 0.2),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 11),
                  // Prevent overflow forever:
                  Expanded(
                    child: Text(
                      "IronBot is typing...",
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          child: IntrinsicHeight(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kPrimaryColor.withOpacity(0.12), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.10),
                    blurRadius: 15,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.emoji_emotions, color: kPrimaryColor.withOpacity(0.67)),
                    onPressed: () {},
                    splashRadius: 24,
                    tooltip: "Send Emoji",
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_isLoading,
                        style: const TextStyle(fontSize: 16.5),
                        decoration: const InputDecoration(
                          hintText: 'Type your message…',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                          isDense: true,
                        ),
                        onSubmitted: _isLoading ? null : _sendMessage,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file, color: kPrimaryColor.withOpacity(0.60)),
                    onPressed: () {},
                    splashRadius: 23,
                    tooltip: "Attach file or image (coming soon)",
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: IconButton(
                      key: ValueKey(_isLoading),
                      icon: Icon(Icons.send_rounded,
                          color: _isLoading ? Colors.grey : kPrimaryColor,
                          size: 28),
                      onPressed: _isLoading
                          ? null
                          : () {
                        final text = _controller.text.trim();
                        if (text.isNotEmpty) {
                          _sendMessage(text);
                        }
                      },
                      splashRadius: 24,
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

  Widget _quickActionFAB() {
    return supportPhone == null
        ? SizedBox.shrink()
        : FloatingActionButton.extended(
      backgroundColor: kPrimaryColor,
      onPressed: () async {
        final telUrl = 'tel:$supportPhone';
        if (await canLaunchUrl(Uri.parse(telUrl))) {
          await launchUrl(Uri.parse(telUrl));
        }
      },
      icon: const Icon(Icons.phone_forwarded, color: Colors.white),
      label: const Text(
        "Call Support",
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      elevation: 4,
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
      floatingActionButton: _quickActionFAB(),
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, Colors.white],
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.18),
                blurRadius: 9,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            titleSpacing: 0,
            centerTitle: false,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.smart_toy_rounded, color: kPrimaryColor, size: 23),
                  radius: 18,
                ),
                const SizedBox(width: 10),
                const Text(
                  "IronBot Support",
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
            actions: [
              if (supportPhone != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.phone, color: Color(0xFF1977D5), size: 21),
                      tooltip: 'Call Support',
                      onPressed: () async {
                        final telUrl = 'tel:$supportPhone';
                        if (await canLaunchUrl(Uri.parse(telUrl))) {
                          await launchUrl(Uri.parse(telUrl));
                        }
                      },
                    ),
                    radius: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 12, bottom: 8),
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
          _inputBar(),
        ],
      ),
    );
  }
}