import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
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
  final DateTime timestamp;
  _ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class _AiChatScreenState extends State<AiChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;

  late String conversationId;
  late String userId;
  String? supportPhone;

  // ✅ PREMIUM ANIMATIONS
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ API Configuration
  static const String _baseUrl = 'https://qehtgclgjhzdlqcjujpp.supabase.co';
  static const String _apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo';

  @override
  void initState() {
    super.initState();
    conversationId = _generateConversationId();
    userId = _generateUserId();
    fetchSupportPhone();
    _initializeAnimations();
    _addWelcomeMessage();

    // Test API connectivity on startup
    Future.delayed(const Duration(seconds: 2), () {
      _testApiConnectivity();
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  void _addWelcomeMessage() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: "👋 Hello! I'm IronBot, your AI assistant. How can I help you with your laundry services today?",
          ));
        });
      }
    });
  }

  // ✅ FIXED UUID GENERATION
  String _generateConversationId() {
    const uuid = Uuid();
    return uuid.v4();
  }

  String _generateUserId() {
    const uuid = Uuid();
    return uuid.v4();
  }

  // ✅ IMPROVED ERROR HANDLING FOR SUPPORT PHONE
  Future<void> fetchSupportPhone() async {
    try {
      print('Fetching support phone...');
      final response = await http.get(
        Uri.parse('$_baseUrl/rest/v1/ui_contacts?key=eq.support'),
        headers: {
          'apikey': _apiKey,
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('Support phone response status: ${response.statusCode}');
      print('Support phone response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          setState(() {
            supportPhone = data[0]['value'];
          });
          print('Support phone fetched: $supportPhone');
        } else {
          print('No support phone data found');
        }
      } else {
        print('Failed to fetch support phone: ${response.statusCode}');
        print('Error body: ${response.body}');
      }
    } catch (e) {
      print('Error fetching support phone: $e');
    }
  }

  // ✅ IMPROVED MESSAGE SENDING WITH COMPREHENSIVE DEBUGGING
  Future<void> _sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    final trimmedMessage = userMessage.trim();
    print('🚀 SENDING MESSAGE');
    print('📝 Message: $trimmedMessage');
    print('🔑 Conversation ID: $conversationId');
    print('👤 User ID: $userId');
    print('🌐 API URL: $_baseUrl/functions/v1/chat');

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: trimmedMessage));
      _isLoading = true;
    });
    _controller.clear();

    // ✅ SMOOTH SCROLL TO BOTTOM
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    try {
      final requestBody = {
        "conversation_id": conversationId,
        "user_id": userId,
        "message": trimmedMessage,
      };

      print('📦 Request Body: ${jsonEncode(requestBody)}');
      print('🔐 API Key (first 20 chars): ${_apiKey.substring(0, 20)}...');

      final response = await http.post(
        Uri.parse('$_baseUrl/functions/v1/chat'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Flutter-IronBot/1.0',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      print('📡 RESPONSE RECEIVED');
      print('📊 Status Code: ${response.statusCode}');
      print('📋 Response Headers: ${response.headers}');
      print('📄 Response Body: ${response.body}');
      print('📏 Response Length: ${response.body.length}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          print('✅ Parsed Response Data: $data');

          final botResponse = data['response'] ?? data['message'] ?? 'Sorry, I could not process your request.';

          setState(() {
            _messages.add(_ChatMessage(
              role: 'assistant',
              content: botResponse.toString().trim(),
            ));
          });
          _scrollToBottom();
        } catch (parseError) {
          print('❌ JSON Parse Error: $parseError');
          setState(() {
            _messages.add(_ChatMessage(
              role: 'assistant',
              content: 'Received invalid response format from server.',
            ));
          });
        }
      } else {
        // Enhanced error handling with response body details
        print('❌ ERROR RESPONSE');
        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');

        String errorMessage;
        String technicalDetails = '';

        // Try to parse error response
        try {
          final errorData = json.decode(response.body);
          technicalDetails = errorData['error'] ?? errorData['message'] ?? '';
          print('🔍 Error Details: $technicalDetails');
        } catch (e) {
          technicalDetails = response.body;
        }

        switch (response.statusCode) {
          case 400:
            errorMessage = 'Bad Request: Invalid message format or missing parameters.';
            if (technicalDetails.isNotEmpty) {
              errorMessage += '\nDetails: $technicalDetails';
            }
            break;
          case 401:
            errorMessage = 'Unauthorized: Invalid API key or expired token.';
            break;
          case 403:
            errorMessage = 'Forbidden: Access denied. Check your permissions.';
            break;
          case 404:
            errorMessage = 'Not Found: Chat function not deployed or incorrect URL.';
            break;
          case 429:
            errorMessage = 'Rate Limited: Too many requests. Please wait.';
            break;
          case 500:
            errorMessage = 'Internal Server Error: Issue with the chat function.';
            if (technicalDetails.isNotEmpty) {
              errorMessage += '\nServer Details: $technicalDetails';
            }
            break;
          case 502:
            errorMessage = 'Bad Gateway: Function deployment or connection issue.';
            break;
          case 503:
            errorMessage = 'Service Unavailable: Function temporarily down.';
            break;
          case 504:
            errorMessage = 'Gateway Timeout: Function took too long to respond.';
            break;
          default:
            errorMessage = 'HTTP Error ${response.statusCode}: Unexpected server response.';
            if (technicalDetails.isNotEmpty) {
              errorMessage += '\nDetails: $technicalDetails';
            }
        }

        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: errorMessage,
          ));
        });
        _showErrorSnackBar('Server Error (${response.statusCode})');
      }
    } catch (e) {
      print('💥 EXCEPTION OCCURRED');
      print('Exception Type: ${e.runtimeType}');
      print('Exception Details: $e');
      print('Stack Trace: ${StackTrace.current}');

      String errorMessage;

      if (e.toString().contains('TimeoutException')) {
        errorMessage = "⏰ Request timed out after 30 seconds.\n\nThis usually means:\n• The server is overloaded\n• Your internet is slow\n• The function is taking too long to process";
      } else if (e.toString().contains('SocketException')) {
        errorMessage = "🌐 No internet connection.\n\nPlease check:\n• WiFi/Mobile data is on\n• You have internet access\n• Try again in a moment";
      } else if (e.toString().contains('FormatException')) {
        errorMessage = "📄 Invalid response format from server.\n\nThe server returned malformed data.";
      } else if (e.toString().contains('HandshakeException')) {
        errorMessage = "🔒 SSL/TLS connection failed.\n\nThis might be a network security issue.";
      } else {
        errorMessage = "❌ Unexpected error occurred.\n\nError: ${e.toString()}";
      }

      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: errorMessage,
        ));
      });
      _showErrorSnackBar('Connection Error');
    }

    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  // ✅ ADD FUNCTION TO TEST API CONNECTIVITY
  Future<void> _testApiConnectivity() async {
    print('🧪 TESTING API CONNECTIVITY');
    try {
      final testResponse = await http.get(
        Uri.parse('$_baseUrl/rest/v1/'),
        headers: {
          'apikey': _apiKey,
          'Authorization': 'Bearer $_apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      print('🔍 Base API Test - Status: ${testResponse.statusCode}');
      print('🔍 Base API Test - Body: ${testResponse.body}');

      // Test the functions endpoint specifically with proper OPTIONS request
      final functionsResponse = await http.Request(
        'OPTIONS',
        Uri.parse('$_baseUrl/functions/v1/chat'),
      )
        ..headers.addAll({
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        });

      final streamedResponse = await functionsResponse.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('🔍 Functions Test - Status: ${response.statusCode}');
      print('🔍 Functions Test - Headers: ${response.headers}');

    } catch (e) {
      print('🔍 Connectivity Test Failed: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ✅ PREMIUM MESSAGE BUBBLE
  Widget _buildBubble(_ChatMessage message, bool isUser, int index) {
    return Container(
      margin: EdgeInsets.only(
        top: index == 0 ? 16 : 8,
        left: isUser ? 60 : 16,
        right: isUser ? 16 : 60,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) _buildAvatarBot(),
          if (!isUser) const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(
                      colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : LinearGradient(
                      colors: [Colors.white, Colors.grey.shade50],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? kPrimaryColor.withOpacity(0.2)
                            : Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 1,
                      ),
                    ],
                    border: !isUser ? Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ) : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                // ✅ TIMESTAMP
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 12),
          if (isUser) _buildAvatarUser(),
        ],
      ),
    );
  }

  // ✅ PREMIUM BOT AVATAR
  Widget _buildAvatarBot() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: kPrimaryColor,
        size: 20,
      ),
    );
  }

  // ✅ PREMIUM USER AVATAR
  Widget _buildAvatarUser() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade200, Colors.grey.shade100],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.person_rounded,
        color: Colors.grey.shade600,
        size: 20,
      ),
    );
  }

  // ✅ PREMIUM TYPING INDICATOR
  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAvatarBot(),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(color: Colors.grey.shade200, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTypingDots(),
                  const SizedBox(width: 8),
                  Text(
                    "IronBot is typing...",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
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

  // ✅ ANIMATED TYPING DOTS
  Widget _buildTypingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: Duration(milliseconds: 500 + (index * 200)),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kPrimaryColor.withOpacity(0.6 - (index * 0.15)),
          ),
        );
      }),
    );
  }

  // ✅ PREMIUM INPUT BAR
  Widget _buildInputBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kPrimaryColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ✅ EMOJI BUTTON
          Container(
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.emoji_emotions_outlined, color: kPrimaryColor, size: 20),
              onPressed: () {},
              tooltip: "Add emoji",
            ),
          ),

          // ✅ TEXT FIELD
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                enabled: !_isLoading,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask me anything about laundry...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: _isLoading ? null : _sendMessage,
              ),
            ),
          ),

          // ✅ ATTACH BUTTON
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.attach_file_rounded, color: Colors.grey.shade600, size: 20),
              onPressed: () {},
              tooltip: "Attach file (coming soon)",
            ),
          ),

          // ✅ SEND BUTTON
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: _isLoading
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _isLoading ? null : () {
                final text = _controller.text.trim();
                if (text.isNotEmpty) {
                  _sendMessage(text);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ✅ PREMIUM FLOATING ACTION BUTTON
  Widget _buildCallSupportFAB() {
    if (supportPhone == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 80),
      child: FloatingActionButton.extended(
        backgroundColor: Colors.green.shade600,
        onPressed: () async {
          final telUrl = 'tel:$supportPhone';
          if (await canLaunchUrl(Uri.parse(telUrl))) {
            await launchUrl(Uri.parse(telUrl));
          }
        },
        icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 20),
        label: const Text(
          "Call Support",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ✅ PREMIUM APP BAR
  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      title: Row(
        children: [
          _buildAvatarBot(),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "IronBot",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                "AI Assistant • Online",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      actions: [
        // Debug menu for testing
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            switch (value) {
              case 'test_connection':
                _testApiConnectivity();
                break;
              case 'clear_chat':
                setState(() {
                  _messages.clear();
                  _addWelcomeMessage();
                });
                break;
              case 'show_debug':
                _showDebugInfo();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'test_connection',
              child: Row(
                children: [
                  Icon(Icons.wifi_find, size: 20),
                  SizedBox(width: 8),
                  Text('Test Connection'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.clear_all, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'show_debug',
              child: Row(
                children: [
                  Icon(Icons.bug_report, size: 20),
                  SizedBox(width: 8),
                  Text('Debug Info'),
                ],
              ),
            ),
          ],
        ),
        if (supportPhone != null)
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.phone_rounded, color: Colors.green.shade600, size: 20),
              tooltip: 'Call Support',
              onPressed: () async {
                final telUrl = 'tel:$supportPhone';
                if (await canLaunchUrl(Uri.parse(telUrl))) {
                  await launchUrl(Uri.parse(telUrl));
                }
              },
            ),
          ),
      ],
    );
  }

  // ✅ SHOW DEBUG INFORMATION
  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDebugRow('Base URL', _baseUrl),
              _buildDebugRow('API Key (first 20)', '${_apiKey.substring(0, 20)}...'),
              _buildDebugRow('Conversation ID', conversationId),
              _buildDebugRow('User ID', userId),
              _buildDebugRow('Support Phone', supportPhone ?? 'Not loaded'),
              _buildDebugRow('Messages Count', '${_messages.length}'),
              _buildDebugRow('Is Loading', '$_isLoading'),
              const SizedBox(height: 16),
              const Text(
                'Common Server Error Solutions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Check if Edge Function is deployed\n'
                    '2. Verify API key has correct permissions\n'
                    '3. Check function logs in Supabase dashboard\n'
                    '4. Ensure function accepts POST requests\n'
                    '5. Verify CORS settings\n'
                    '6. Check function timeout settings',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _testApiConnectivity();
            },
            child: const Text('Test Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildPremiumAppBar(),
      floatingActionButton: _buildCallSupportFAB(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              // ✅ CHAT MESSAGES
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isLoading && index == _messages.length) {
                      return _buildTypingIndicator();
                    }
                    final msg = _messages[index];
                    final isUser = msg.role == 'user';
                    return _buildBubble(msg, isUser, index);
                  },
                ),
              ),

              // ✅ INPUT BAR
              SafeArea(child: _buildInputBar()),
            ],
          ),
        ),
      ),
    );
  }
}