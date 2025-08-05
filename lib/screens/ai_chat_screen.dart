import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'colors.dart';

class PremiumAiChatScreen extends StatefulWidget {
  const PremiumAiChatScreen({super.key});
  @override
  State<PremiumAiChatScreen> createState() => _PremiumAiChatScreenState();
}

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isError;

  _ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class _PremiumAiChatScreenState extends State<PremiumAiChatScreen>
    with TickerProviderStateMixin {

  // Controllers
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // State variables
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isTyping = false;
  late String conversationId;
  late String userId;
  String? supportPhone;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _typingController;
  late AnimationController _pulseController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _typingAnimation;
  late Animation<double> _pulseAnimation;

  // Constants
  static const String _supabaseUrl = 'https://qehtgclgjhzdlqcjujpp.supabase.co';
  static const String _apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _typingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeApp() {
    // Generate IDs
    conversationId = _generateConversationId();
    userId = _generateUserId();

    // Initialize animations
    _initializeAnimations();

    // Fetch support phone
    _fetchSupportPhone();

    // Add welcome message after delay
    _addWelcomeMessage();

    // Debug logs
    debugPrint('🔑 Generated Conversation ID: $conversationId');
    debugPrint('👤 Generated User ID: $userId');
  }

  void _initializeAnimations() {
    // Fade animation for screen entrance
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Slide animation for messages
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Typing indicator animation
    _typingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Pulse animation for send button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    _typingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _typingController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start entrance animations
    _fadeController.forward();
    _slideController.forward();

    // Setup repeating animations
    _typingController.repeat(reverse: true);
  }

  void _addWelcomeMessage() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: "👋 Welcome to IronBot Premium! I'm your advanced AI assistant for all laundry services. I can help you with:\n\n🔸 Order tracking & history\n🔸 Service information\n🔸 Pricing & packages\n🔸 Support & troubleshooting\n\nHow can I assist you today?",
          ));
        });
        _scrollToBottom();
      }
    });
  }

  String _generateConversationId() {
    const uuid = Uuid();
    final id = uuid.v4();
    debugPrint('🆔 Generated conversation ID: $id');
    return id;
  }

  String _generateUserId() {
    const uuid = Uuid();
    final id = uuid.v4();
    debugPrint('👤 Generated user ID: $id');
    return id;
  }

  Future<void> _fetchSupportPhone() async {
    try {
      debugPrint('📞 Fetching support phone...');

      final response = await http.get(
        Uri.parse('$_supabaseUrl/rest/v1/ui_contacts?key=eq.support'),
        headers: {
          'apikey': _apiKey,
          'Authorization': 'Bearer $_apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📞 Support phone response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('📞 Support phone data: $data');

        if (data is List && data.isNotEmpty) {
          if (mounted) {
            setState(() {
              supportPhone = data[0]['value'];
            });
          }
          debugPrint('📞 Support phone set: $supportPhone');
        }
      }
    } catch (e) {
      debugPrint('📞 Error fetching support phone: $e');
    }
  }

  Future<void> _sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    final trimmedMessage = userMessage.trim();
    debugPrint('📤 Sending message: "$trimmedMessage"');

    // Add user message to UI
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: trimmedMessage));
      _isLoading = true;
      _isTyping = true;
    });

    _controller.clear();
    _scrollToBottom();

    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount <= maxRetries) {
      try {
        final response = await http.post(
          Uri.parse('$_supabaseUrl/functions/v1/chat'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "conversation_id": conversationId,
            "user_id": userId,
            "message": trimmedMessage,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          await _handleSuccessResponse(response);
          return;
        } else {
          await _handleErrorResponse(response);
          if (response.statusCode == 500 &&
              response.body.contains('JSON object requested') &&
              retryCount < maxRetries) {
            retryCount++;
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          return;
        }
      } catch (e) {
        if (retryCount >= maxRetries) {
          await _handleException(e);
          return;
        }
        retryCount++;
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isTyping = false;
      });
    }
  }

  Future<void> _handleSuccessResponse(http.Response response) async {
    try {
      final responseData = jsonDecode(response.body);
      debugPrint('✅ Parsed response data: $responseData');

      String botMessage = _extractBotMessage(responseData);

      // Simulate typing delay for better UX
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: botMessage.trim(),
          ));
        });
      }

    } catch (jsonError) {
      debugPrint('❌ JSON parsing error: $jsonError');

      // Handle case where response is not JSON
      final plainTextResponse = response.body.trim();
      if (plainTextResponse.isNotEmpty) {
        // Check if this is a Supabase log message we should ignore
        if (_isSupabaseLogMessage(plainTextResponse)) {
          if (mounted) {
            setState(() {
              _messages.add(_ChatMessage(
                role: 'assistant',
                content: "Sorry, I encountered a technical issue. Please try again or contact support if the problem persists.",
                isError: true,
              ));
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _messages.add(_ChatMessage(
                role: 'assistant',
                content: plainTextResponse,
              ));
            });
          }
        }
      } else {
        throw Exception('Empty response from server');
      }
    }
  }

  bool _isSupabaseLogMessage(String message) {
    return message.contains('event_message') ||
        message.contains('Listening on http://') ||
        message.contains('served_by') ||
        message.contains('project_ref');
  }

  String _extractBotMessage(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      // First try to get the direct response
      if (responseData['response'] != null) {
        return responseData['response'].toString();
      }

      // If no direct response, check for choices array (common in AI APIs)
      if (responseData['choices'] != null && responseData['choices'] is List && responseData['choices'].isNotEmpty) {
        final firstChoice = responseData['choices'][0];
        if (firstChoice is Map && firstChoice['message'] != null && firstChoice['message'] is Map) {
          return firstChoice['message']['content']?.toString() ?? 'Sorry, I received an empty response.';
        }
        return firstChoice['text']?.toString() ?? 'Sorry, I received an empty response.';
      }

      // Fallback to other possible fields
      return responseData['message']?.toString() ??
          responseData['reply']?.toString() ??
          responseData['answer']?.toString() ??
          'Sorry, I received an unexpected response format.';
    } else if (responseData is String) {
      return responseData;
    } else {
      return 'Sorry, I received an unexpected response format.';
    }
  }

  Future<void> _handleErrorResponse(http.Response response) async {
    String errorMessage = 'Server error (${response.statusCode})';
    String userFriendlyMessage = 'An error occurred while processing your request.';

    try {
      final errorData = jsonDecode(response.body);
      if (errorData is Map<String, dynamic>) {
        errorMessage = errorData['error']?.toString() ??
            errorData['message']?.toString() ??
            errorData['detail']?.toString() ??
            'HTTP ${response.statusCode}: ${response.reasonPhrase}';

        // Handle specific Supabase error message
        if (errorMessage.contains('JSON object requested')) {
          userFriendlyMessage = 'We\'re having trouble processing your request. '
              'Please try again in a moment.';
        }
      }
    } catch (e) {
      debugPrint('Error parsing error response: $e');
      final bodyText = response.body.trim();
      if (bodyText.isNotEmpty && bodyText.length < 200) {
        errorMessage = 'Server error: $bodyText';
      }
    }

    debugPrint('❌ Server error: $errorMessage');

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: userFriendlyMessage,
          isError: true,
        ));
      });
    }

    _showErrorSnackBar('Server Error (${response.statusCode})');
  }

  Future<void> _handleException(dynamic e) async {
    debugPrint('❌ Exception during message sending: $e');

    String userFriendlyMessage = 'We\'re having trouble connecting to our services. '
        'Please check your internet connection and try again.';

    if (e.toString().contains('JSON object requested')) {
      userFriendlyMessage = 'We\'re experiencing high demand. '
          'Please try again in a moment.';
    }

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: userFriendlyMessage,
          isError: true,
        ));
      });
    }

    _showErrorSnackBar('Connection failed');
  }

  String _getUserFriendlyErrorMessage(dynamic e) {
    String errorString = e.toString();

    if (errorString.contains('timeout') || errorString.contains('TimeoutException')) {
      return "⏱️ Request timed out. The server is taking too long to respond. Please try again.";
    } else if (errorString.contains('SocketException') || errorString.contains('HandshakeException')) {
      return "🔌 Connection failed. Please check your internet connection and try again.";
    } else if (errorString.contains('FormatException')) {
      return "📋 Server returned invalid data. Please try again.";
    } else {
      return "❌ An unexpected error occurred. Please try again or contact support.";
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 100,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'DISMISS',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _launchPhone() async {
    if (supportPhone != null) {
      final uri = Uri(scheme: 'tel', path: supportPhone);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          _showErrorSnackBar('Cannot make phone call');
        }
      } catch (e) {
        _showErrorSnackBar('Error launching phone app');
      }
    }
  }

  void _showOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Chat Options',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Icon(Icons.refresh, color: kPrimaryColor),
                title: const Text('Clear Chat'),
                subtitle: const Text('Start a new conversation'),
                onTap: () {
                  Navigator.pop(context);
                  _clearChat();
                },
              ),
              if (supportPhone != null)
                ListTile(
                  leading: Icon(Icons.phone, color: kPrimaryColor),
                  title: const Text('Contact Support'),
                  subtitle: Text(supportPhone!),
                  onTap: () {
                    Navigator.pop(context);
                    _launchPhone();
                  },
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
    });
    _addWelcomeMessage();
  }

  Widget _buildMessageBubble(_ChatMessage message, bool isUser, int index) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(
        top: index == 0 ? 20 : 12,
        left: isUser ? 64 : 16,
        right: isUser ? 16 : 64,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) _buildBotAvatar(),
          if (!isUser) const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _buildMessageContainer(message, isUser),
                _buildMessageTimestamp(message, isUser),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 12),
          if (isUser) _buildUserAvatar(),
        ],
      ),
    );
  }

  Widget _buildMessageContainer(_ChatMessage message, bool isUser) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        gradient: _getMessageGradient(message, isUser),
        borderRadius: _getMessageBorderRadius(isUser),
        boxShadow: _getMessageShadow(message, isUser),
        border: !isUser && !message.isError ? Border.all(
          color: Colors.grey.shade200,
          width: 1.5,
        ) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: _getMessageTextColor(message, isUser),
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            height: 1.5,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  LinearGradient _getMessageGradient(_ChatMessage message, bool isUser) {
    if (isUser) {
      return LinearGradient(
        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (message.isError) {
      return LinearGradient(
        colors: [Colors.red.shade50, Colors.red.shade100],
      );
    } else {
      return LinearGradient(
        colors: [Colors.white, Colors.grey.shade50],
      );
    }
  }

  BorderRadius _getMessageBorderRadius(bool isUser) {
    return BorderRadius.only(
      topLeft: const Radius.circular(24),
      topRight: const Radius.circular(24),
      bottomRight: Radius.circular(isUser ? 6 : 24),
      bottomLeft: Radius.circular(isUser ? 24 : 6),
    );
  }

  List<BoxShadow> _getMessageShadow(_ChatMessage message, bool isUser) {
    if (isUser) {
      return [
        BoxShadow(
          color: kPrimaryColor.withOpacity(0.25),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: 1,
        ),
      ];
    } else if (message.isError) {
      return [
        BoxShadow(
          color: Colors.red.withOpacity(0.15),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
    } else {
      return [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 14,
          offset: const Offset(0, 4),
          spreadRadius: 1,
        ),
      ];
    }
  }

  Color _getMessageTextColor(_ChatMessage message, bool isUser) {
    if (isUser) {
      return Colors.white;
    } else if (message.isError) {
      return Colors.red.shade700;
    } else {
      return Colors.black87;
    }
  }

  Widget _buildMessageTimestamp(_ChatMessage message, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
      child: Text(
        _formatTime(message.timestamp),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBotAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kPrimaryColor.withOpacity(0.15),
            kPrimaryColor.withOpacity(0.08)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: kPrimaryColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: kPrimaryColor,
        size: 22,
      ),
    );
  }

  Widget _buildUserAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade300, Colors.grey.shade200],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.person_rounded,
        color: Colors.grey.shade700,
        size: 22,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildBotAvatar(),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                  bottomLeft: Radius.circular(6),
                ),
                border: Border.all(color: Colors.grey.shade200, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAnimatedTypingDots(),
                  const SizedBox(width: 12),
                  Text(
                    "IronBot is thinking...",
                    style: TextStyle(
                      fontSize: 15,
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

  Widget _buildAnimatedTypingDots() {
    return AnimatedBuilder(
      animation: _typingAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            double delay = index * 0.2;
            double animValue = (_typingAnimation.value + delay) % 1.0;
            double scale = 0.5 + (0.5 * (1 - (animValue - 0.5).abs() * 2).clamp(0.0, 1.0));

            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimaryColor.withOpacity(0.7),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildPremiumInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: _focusNode.hasFocus
                  ? kPrimaryColor.withOpacity(0.4)
                  : kPrimaryColor.withOpacity(0.2),
              width: 2
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Text Input Field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 140),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !_isLoading,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything about your laundry...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  onSubmitted: _isLoading ? null : _sendMessage,
                  onChanged: (text) {
                    setState(() {}); // Rebuild to update send button state
                  },
                ),
              ),
            ),

            // Send Button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      gradient: _controller.text.trim().isNotEmpty && !_isLoading
                          ? LinearGradient(
                        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                          : LinearGradient(
                        colors: [Colors.grey.shade300, Colors.grey.shade400],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: _controller.text.trim().isNotEmpty && !_isLoading
                          ? [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                          : [],
                    ),
                    child: IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                          : Icon(
                        Icons.send_rounded,
                        color: _controller.text.trim().isNotEmpty && !_isLoading
                            ? Colors.white
                            : Colors.grey.shade600,
                        size: 22,
                      ),
                      onPressed: _isLoading || _controller.text.trim().isEmpty
                          ? null
                          : () {
                        final text = _controller.text.trim();
                        if (text.isNotEmpty) {
                          _sendMessage(text);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      title: Row(
        children: [
          _buildBotAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "IronBot Premium",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
                Text(
                  _isTyping ? "Typing..." : "AI Assistant • Online",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kPrimaryColor,
              kPrimaryColor.withOpacity(0.85),
              kPrimaryColor.withOpacity(0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      actions: [
        if (supportPhone != null)
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1),
            ),
            child: IconButton(
              icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 20),
              tooltip: 'Call Support',
              onPressed: () => _launchPhone(),
            ),
          ),

        // Settings/Menu button
        Container(
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: IconButton(
            icon: const Icon(
                Icons.more_vert_rounded, color: Colors.white, size: 20),
            tooltip: 'Menu',
            onPressed: () => _showOptionsBottomSheet(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildPremiumAppBar(),
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                // Messages List
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
                        return _buildTypingIndicator();
                      }

                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      return _buildMessageBubble(message, isUser, index);
                    },
                  ),
                ),

                // Input Bar
                _buildPremiumInputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}