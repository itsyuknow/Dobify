import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'colors.dart';

class PremiumSupportScreen extends StatefulWidget {
  final String? userId;

  const PremiumSupportScreen({super.key, this.userId});

  @override
  State<PremiumSupportScreen> createState() => _PremiumSupportScreenState();
}

class _PremiumSupportScreenState extends State<PremiumSupportScreen>
    with TickerProviderStateMixin {
  String? supportPhone;
  String? supportEmail;
  String? supportWhatsApp;
  bool _isLoading = true;
  bool _showChat = false;
  bool _showEmojiPicker = false;

  // Chat functionality
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  List<ChatMessage> _messages = [];
  bool _isSendingMessage = false;
  String _conversationId = const Uuid().v4();

  // Premium animations
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _chatController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _chatAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  // Emoji data
  final List<String> _recentEmojis = ['😊', '👍', '❤️', '😢', '😂'];
  final List<List<String>> _emojiCategories = [
    ['😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇'],
    ['👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '👏', '🙌', '👐'],
    ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💕'],
    ['😢', '😭', '😤', '😠', '😡', '🤬', '😱', '😨', '😰', '😥'],
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchSupportContacts();
    _initializeChat();
    _messageFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_messageFocusNode.hasFocus && _showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _chatController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    _chatAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _chatController, curve: Curves.easeOutCubic),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
    _shimmerController.repeat();
  }

  void _initializeChat() {
    _messages.add(ChatMessage(
      text: "👋 Hello! I'm IronBot, your premium AI assistant. I'm here to provide you with exceptional support for all your laundry service needs. Whether you have questions about orders, services, or your account, I'm ready to help! ✨",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _fetchSupportContacts() async {
    try {
      final response = await http.get(
        Uri.parse('https://qehtgclgjhzdlqcjujpp.supabase.co/rest/v1/ui_contacts'),
        headers: {
          'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
        },
      );

      if (response.statusCode == 200) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(response.body));
        for (final contact in data) {
          final key = contact['key']?.toString().toLowerCase();
          if (key == 'support') {
            supportPhone = contact['value'];
          } else if (key == 'mail') {
            supportEmail = contact['value'];
          } else if (key == 'whatsapp') {
            supportWhatsApp = contact['value'];
          }
        }
      }
    } catch (e) {
      print('Error fetching support contacts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openWhatsApp() async {
    if (supportWhatsApp != null) {
      HapticFeedback.lightImpact();
      final whatsappUrl = 'https://wa.me/${supportWhatsApp!.replaceAll('+', '').replaceAll(' ', '')}?text=Hello, I need assistance with my laundry service.';
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isSendingMessage = true;
      _showEmojiPicker = false;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('https://qehtgclgjhzdlqcjujpp.supabase.co/functions/v1/chat'),
        headers: {
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlaHRnY2xnamh6ZGxxY2p1anBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4NDk2NzYsImV4cCI6MjA2NjQyNTY3Nn0.P7buCrNPIBShznBQgkdEHx6BG5Bhv9HOq7pn6e0HfLo',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'conversation_id': _conversationId,
          'user_id': widget.userId ?? '0926603f-4b26-44b8-9726-2d7a830cdbe0',
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _messages.add(ChatMessage(
            text: data['response'] ?? 'Sorry, I couldn\'t process that request.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(
            text: 'I apologize, but I\'m experiencing technical difficulties. Please try again in a moment or contact our support team directly. 🔧',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        _messages.add(ChatMessage(
          text: 'Connection issue detected. Please check your internet connection and try again. 📶',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _toggleChat() {
    HapticFeedback.mediumImpact();
    setState(() {
      _showChat = !_showChat;
    });
    if (_showChat) {
      _chatController.forward();
    } else {
      _chatController.reverse();
      setState(() {
        _showEmojiPicker = false;
      });
    }
  }

  void _toggleEmojiPicker() {
    HapticFeedback.selectionClick();
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (_showEmojiPicker) {
      _messageFocusNode.unfocus();
    } else {
      _messageFocusNode.requestFocus();
    }
  }

  void _addEmoji(String emoji) {
    final currentText = _messageController.text;
    final selection = _messageController.selection;
    final newText = currentText.replaceRange(
      selection.start,
      selection.end,
      emoji,
    );
    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(
      offset: selection.start + emoji.length,
    );
    setState(() {});
  }

  Future<void> _makePhoneCall() async {
    if (supportPhone != null) {
      HapticFeedback.lightImpact();
      final telUrl = 'tel:$supportPhone';
      if (await canLaunchUrl(Uri.parse(telUrl))) {
        await launchUrl(Uri.parse(telUrl));
      }
    }
  }

  Future<void> _sendEmail() async {
    if (supportEmail != null) {
      HapticFeedback.lightImpact();
      final emailUrl = 'mailto:$supportEmail?subject=Customer Support Request';
      if (await canLaunchUrl(Uri.parse(emailUrl))) {
        await launchUrl(Uri.parse(emailUrl));
      }
    }
  }

  PreferredSizeWidget _buildAppBar() {
    if (_showChat) {
      // AppBar while chat is open
      return AppBar(
        elevation: 0,
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        titleSpacing: 12,
        title: Row(
          children: [
            // Bot avatar
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.white, Colors.white70]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(Icons.smart_toy_rounded, color: kPrimaryColor, size: 18),
            ),
            const SizedBox(width: 12),
            // Title + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'IronBot AI Assistant',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 3, spreadRadius: 1)],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Online • Ready to assist',
                      style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _toggleChat,
            icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
            tooltip: 'Close chat',
          ),
        ],
      );
    }

    // Normal support app bar (when chat is closed)
    return AppBar(
      title: const Text(
        'Customer Support',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.5),
      ),
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(
        color: Colors.white,
        size: 22, // tweak if you want slightly bigger/smaller arrow
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      leadingWidth: 44, // bring arrow closer to edge like screenshot
      leading: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          splashRadius: 22,
          tooltip: 'Back',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          // straight back arrow (not iOS chevron)
          icon: const Icon(Icons.arrow_back_rounded),
          // If you prefer even simpler arrow:
          // icon: const Icon(Icons.arrow_back),
        ),
      ),
    );
  }


  Widget _buildSupportCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.white.withOpacity(0.95),
            Colors.grey.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kPrimaryColor.withOpacity(0.1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shimmerAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          kPrimaryColor.withOpacity(0.03),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        begin: Alignment(-1.0 + _shimmerAnimation.value, -1.0),
                        end: Alignment(1.0 + _shimmerAnimation.value, 1.0),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPremiumLogo(),
                  const SizedBox(height: 24),
                  _buildTitleSection(),
                  const SizedBox(height: 28),
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                  _buildContactOptions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumLogo() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value * 0.05 + 0.95,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kPrimaryColor,
                  kPrimaryColor.withOpacity(0.8),
                  kPrimaryColor.withOpacity(0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: kPrimaryColor.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_laundry_service_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'IronXpress',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleSection() {
    return Column(
      children: [
        const Text(
          'At your service',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withOpacity(0.1),
                kPrimaryColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
          ),
          child: Text(
            "Experience our AI-powered support with instant responses, 24/7 availability, and personalized assistance for all your ironing needs! 🚀",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
                kPrimaryColor.withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.2),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            label: const Text(
              "Start Chat with IronBot",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: _toggleChat,
          ),
        ),
      ],
    );
  }

  Widget _buildContactOptions() {
    // Count available contact methods
    final availableContacts = [
      if (supportPhone != null) 'phone',
      if (supportWhatsApp != null) 'whatsapp',
      if (supportEmail != null) 'email'
    ];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        kPrimaryColor.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
                ),
                child: Text(
                  'Alternative Support',
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        kPrimaryColor.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Dynamic contact buttons layout
        if (availableContacts.length == 1)
        // Single contact method - full width
          _buildSingleContactRow(availableContacts.first)
        else if (availableContacts.length == 2)
        // Two contact methods - side by side
          _buildTwoContactsRow(availableContacts)
        else if (availableContacts.length == 3)
          // Three contact methods - stacked layout
            _buildThreeContactsLayout()
          else
            const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildSingleContactRow(String contactType) {
    return Row(
      children: [
        Expanded(child: _getContactButton(contactType)),
      ],
    );
  }

  Widget _buildThreeContactsLayout() {
    return Column(
      children: [
        // Top row with two buttons (smaller)
        Row(
          children: [
            Expanded(child: _buildCompactContactButton('phone')),
            const SizedBox(width: 8),
            Expanded(child: _buildCompactContactButton('whatsapp')),
          ],
        ),
        const SizedBox(height: 8),
        // Bottom row with single email button (full width but compact)
        _buildCompactContactButton('email'),
      ],
    );
  }

  Widget _buildTwoContactsRow(List<String> contacts) {
    return Row(
      children: [
        Expanded(child: _getContactButton(contacts[0])),
        const SizedBox(width: 12),
        Expanded(child: _getContactButton(contacts[1])),
      ],
    );
  }

  Widget _getContactButton(String contactType) {
    switch (contactType) {
      case 'phone':
        return _buildContactButton(
          icon: Icons.phone_rounded,
          label: 'Call Now',
          subtitle: 'Instant Support',
          color: Colors.green,
          onTap: _makePhoneCall,
        );
      case 'whatsapp':
        return _buildContactButton(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          subtitle: 'Quick Chat',
          color: const Color(0xFF25D366), // WhatsApp green
          onTap: _openWhatsApp,
        );
      case 'email':
        return _buildContactButton(
          icon: Icons.email_rounded,
          label: 'Send Email',
          subtitle: 'Detailed Query',
          color: Colors.blue,
          onTap: _sendEmail,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // ↑ extra vertical padding
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        // ↑ taller minimum height
        constraints: const BoxConstraints(minHeight: 112),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ↑ slightly bigger icon bubble for vertical feel
            Container(
              padding: const EdgeInsets.all(16), // was 14
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.8)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22), // was 20
            ),
            const SizedBox(height: 14), // was 12
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 6), // was 4
            Text(
              subtitle,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildCompactContactButton(String contactType) {
    IconData icon;
    String label;
    String subtitle;
    Color color;
    VoidCallback onTap;

    switch (contactType) {
      case 'phone':
        if (supportPhone == null) return const SizedBox.shrink();
        icon = Icons.phone_rounded;
        label = 'Call Now';
        subtitle = 'Instant Support';
        color = Colors.green;
        onTap = _makePhoneCall;
        break;
      case 'whatsapp':
        if (supportWhatsApp == null) return const SizedBox.shrink();
        icon = Icons.chat_rounded;
        label = 'WhatsApp';
        subtitle = 'Quick Chat';
        color = const Color(0xFF25D366);
        onTap = _openWhatsApp;
        break;
      case 'email':
        if (supportEmail == null) return const SizedBox.shrink();
        icon = Icons.email_rounded;
        label = 'Send Email';
        subtitle = 'Detailed Query';
        color = Colors.blue;
        onTap = _sendEmail;
        break;
      default:
        return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        // ↑ extra vertical padding
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18), // was 14
        // ↑ taller minimum height
        constraints: const BoxConstraints(minHeight: 72), // was 60
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ↑ slightly bigger icon bubble
            Container(
              padding: const EdgeInsets.all(10), // was 9
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.8)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18), // was 16
            ),
            const SizedBox(width: 12), // was 10
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3), // was 2
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFullScreenChat() {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true, // ← cancel the SafeArea from the parent Scaffold
      child: Column(
        children: [
          Expanded(child: _buildChatMessages()),
          if (_showEmojiPicker) _buildEmojiPicker(),
          // Apply exactly one SafeArea only at the bottom of the chat
          SafeArea(
            top: false,
            bottom: true,
            child: _buildChatInput(), // ← this version below has NO SafeArea inside
          ),
        ],
      ),
    );
  }

  Widget _buildChatHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Colors.white.withOpacity(0.9)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.smart_toy_rounded, color: kPrimaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'IronBot AI Assistant',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent,
                            blurRadius: 3,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Online • Ready to assist',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: _toggleChat,
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessages() {
    return Container(
      color: Colors.grey.shade50,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        itemCount: _messages.length + (_isSendingMessage ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length && _isSendingMessage) {
            return _buildTypingIndicator();
          }
          return _buildChatBubble(_messages[index], index);
        },
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message, int index) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!message.isUser) ...[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: message.isUser
                              ? LinearGradient(
                            colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                              : LinearGradient(
                            colors: [Colors.white, Colors.grey.shade50],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(message.isUser ? 16 : 6),
                            bottomRight: Radius.circular(message.isUser ? 6 : 16),
                          ),
                          border: message.isUser
                              ? null
                              : Border.all(color: Colors.grey.shade200, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: message.isUser
                                  ? kPrimaryColor.withOpacity(0.2)
                                  : Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: message.isUser ? Colors.white : Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                              softWrap: true,
                              overflow: TextOverflow.visible,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(message.timestamp),
                              style: TextStyle(
                                color: message.isUser
                                    ? Colors.white.withOpacity(0.7)
                                    : Colors.grey.shade500,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (message.isUser) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey.shade300, Colors.grey.shade200],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.person_rounded, color: Colors.grey.shade600, size: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kPrimaryColor.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.grey.shade50],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(6),
                ),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAnimatedDot(),
                  const SizedBox(width: 3),
                  _buildAnimatedDot(),
                  const SizedBox(width: 3),
                  _buildAnimatedDot(),
                  const SizedBox(width: 6),
                  const Flexible(
                    child: Text(
                      'IronBot is typing...',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildAnimatedDot() {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 0.4, end: 1.0),
      builder: (context, value, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: kPrimaryColor.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildChatInput() {
    return Container(
      // was: EdgeInsets.fromLTRB(12, 8, 12, 8)
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_messageController.text.trim().isEmpty && !_isSendingMessage)
            _buildQuickResponses(),
          if (_messageController.text.trim().isEmpty && !_isSendingMessage)
            const SizedBox(height: 4),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Emoji button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _showEmojiPicker
                        ? [kPrimaryColor.withOpacity(0.2), kPrimaryColor.withOpacity(0.1)]
                        : [Colors.grey.shade100, Colors.grey.shade50],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _showEmojiPicker
                        ? kPrimaryColor.withOpacity(0.3)
                        : Colors.grey.shade300,
                  ),
                ),
                child: IconButton(
                  onPressed: _toggleEmojiPicker,
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_rounded,
                    color: _showEmojiPicker ? kPrimaryColor : Colors.grey.shade600,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 6),

              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 92, minHeight: 36),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey.shade50, Colors.white],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Type your message...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      hintStyle: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: !_isSendingMessage,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      final msg = v.trim();
                      if (msg.isNotEmpty) _sendMessage(msg);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Send button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _messageController.text.trim().isNotEmpty && !_isSendingMessage
                        ? [kPrimaryColor, kPrimaryColor.withOpacity(0.8)]
                        : [Colors.grey.shade300, Colors.grey.shade400],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_messageController.text.trim().isNotEmpty && !_isSendingMessage
                          ? kPrimaryColor
                          : Colors.grey)
                          .withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _isSendingMessage || _messageController.text.trim().isEmpty
                      ? null
                      : () {
                    final msg = _messageController.text.trim();
                    if (msg.isNotEmpty) _sendMessage(msg);
                  },
                  padding: EdgeInsets.zero,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isSendingMessage
                        ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(
                      Icons.send_rounded,
                      key: ValueKey('send'),
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickResponses() {
    final quickResponses = [
      '📦 Track my order',
      '💰 Pricing info',
      '🕐 Service hours',
      '📍 Pickup locations',
    ];

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: quickResponses.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return IntrinsicWidth(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _messageController.text = quickResponses[index];
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withOpacity(0.1),
                      kPrimaryColor.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
                ),
                child: Center(
                  child: Text(
                    quickResponses[index],
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showEmojiPicker ? 250 : 0,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: _showEmojiPicker
          ? DefaultTabController(
        length: 5,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: TabBar(
                indicatorColor: kPrimaryColor,
                indicatorWeight: 2.5,
                labelColor: kPrimaryColor,
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(text: '🕒'),
                  Tab(text: '😊'),
                  Tab(text: '👋'),
                  Tab(text: '❤️'),
                  Tab(text: '😢'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildEmojiGrid(_recentEmojis),
                  _buildEmojiGrid(_emojiCategories[0]),
                  _buildEmojiGrid(_emojiCategories[1]),
                  _buildEmojiGrid(_emojiCategories[2]),
                  _buildEmojiGrid(_emojiCategories[3]),
                ],
              ),
            ),
          ],
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _addEmoji(emojis[index]);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                emojis[index],
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: kPrimaryColor,
                strokeWidth: 3,
                backgroundColor: kPrimaryColor.withOpacity(0.1),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading premium support...',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Preparing your personalized experience',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _chatController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      // ⬇️ Only top safe area here, let the chat handle bottom insets itself
      body: SafeArea(
        top: true,
        bottom: false,
        child: _isLoading
            ? _buildLoadingWidget()
            : Stack(
          children: [
            // Main Support Content
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildSupportCard(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Chat Overlay - Full Screen Chat
            if (_showChat)
              Positioned.fill(
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _chatController,
                    curve: Curves.easeOutCubic,
                  )),
                  child: FadeTransition(
                    opacity: _chatAnimation,
                    child: _buildFullScreenChat(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Enhanced Chat Message Model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? id;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.id,
  });
}