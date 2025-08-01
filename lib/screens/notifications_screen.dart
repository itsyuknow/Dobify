import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> filteredNotifications = [];
  bool isLoading = true;
  String selectedFilter = 'All';
  int unreadCount = 0;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> filterOptions = ['All', 'Unread', 'Orders', 'Promotions', 'System'];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadNotifications();
    _setupRealtimeSubscription();
  }

  void _initAnimations() {
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
    _slideAnimation = Tween<Offset>(begin: const Offset(0.0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => isLoading = true);

      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        notifications = List<Map<String, dynamic>>.from(response);
        _filterNotifications();
        unreadCount = notifications.where((n) => !(n['is_read'] ?? false)).length;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() => isLoading = false);
    }
  }

  void _setupRealtimeSubscription() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    supabase
        .channel('notifications_channel')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: user.id,
      ),
      callback: (payload) {
        print('Notification change detected: ${payload.eventType}');
        _loadNotifications();
      },
    )
        .subscribe();
  }

  void _filterNotifications() {
    switch (selectedFilter) {
      case 'Unread':
        filteredNotifications = notifications.where((n) => !(n['is_read'] ?? false)).toList();
        break;
      case 'Orders':
        filteredNotifications = notifications.where((n) => n['type'] == 'order').toList();
        break;
      case 'Promotions':
        filteredNotifications = notifications.where((n) => n['type'] == 'promotion').toList();
        break;
      case 'System':
        filteredNotifications = notifications.where((n) => n['type'] == 'system').toList();
        break;
      default:
        filteredNotifications = notifications;
    }
  }

  Future<void> _markAsRead(String notificationId, bool isRead) async {
    try {
      await supabase
          .from('notifications')
          .update({'is_read': isRead, 'read_at': isRead ? DateTime.now().toIso8601String() : null})
          .eq('id', notificationId);

      HapticFeedback.lightImpact();
      _loadNotifications();
    } catch (e) {
      print('Error updating notification: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('notifications')
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', user.id)
          .eq('is_read', false);

      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('All notifications marked as read!');
      _loadNotifications();
    } catch (e) {
      print('Error marking all as read: $e');
      _showErrorSnackBar('Failed to mark all as read');
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);

      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('Notification deleted');
      _loadNotifications();
    } catch (e) {
      print('Error deleting notification: $e');
      _showErrorSnackBar('Failed to delete notification');
    }
  }

  Future<void> _clearAllNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600),
            const SizedBox(width: 12),
            const Text('Clear All Notifications'),
          ],
        ),
        content: const Text('Are you sure you want to delete all notifications? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await supabase
                    .from('notifications')
                    .delete()
                    .eq('user_id', user.id);

                HapticFeedback.heavyImpact();
                _showSuccessSnackBar('All notifications cleared!');
                _loadNotifications();
              } catch (e) {
                _showErrorSnackBar('Failed to clear notifications');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.error_outline, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildFilterTabs(),
                Expanded(child: _buildNotificationsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Notifications',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 24),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) => [
            if (unreadCount > 0)
              PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 12),
                    Text('Mark All Read', style: TextStyle(color: Colors.blue.shade600, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'clear_all',
              child: Row(
                children: [
                  Icon(Icons.clear_all_rounded, color: Colors.red.shade600, size: 20),
                  const SizedBox(width: 12),
                  Text('Clear All', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'mark_all_read') {
              _markAllAsRead();
            } else if (value == 'clear_all') {
              _clearAllNotifications();
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filterOptions.map((filter) {
            final isSelected = selectedFilter == filter;
            final count = _getFilterCount(filter);

            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  selectedFilter = filter;
                  _filterNotifications();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)])
                      : LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isSelected ? kPrimaryColor : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ] : [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.3)
                              : kPrimaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected ? Colors.white : kPrimaryColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  int _getFilterCount(String filter) {
    switch (filter) {
      case 'Unread':
        return notifications.where((n) => !(n['is_read'] ?? false)).length;
      case 'Orders':
        return notifications.where((n) => n['type'] == 'order').length;
      case 'Promotions':
        return notifications.where((n) => n['type'] == 'promotion').length;
      case 'System':
        return notifications.where((n) => n['type'] == 'system').length;
      default:
        return notifications.length;
    }
  }

  Widget _buildNotificationsList() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading notifications...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    if (filteredNotifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade100, Colors.grey.shade50],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  selectedFilter == 'Unread'
                      ? Icons.mark_email_read_rounded
                      : Icons.notifications_off_rounded,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _getEmptyMessage(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _getEmptySubtitle(),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filteredNotifications.length,
      itemBuilder: (context, index) {
        final notification = filteredNotifications[index];
        return _buildNotificationCard(notification, index);
      },
    );
  }

  String _getEmptyMessage() {
    switch (selectedFilter) {
      case 'Unread':
        return 'All caught up!';
      case 'Orders':
        return 'No order updates';
      case 'Promotions':
        return 'No promotions yet';
      case 'System':
        return 'No system notifications';
      default:
        return 'No notifications yet';
    }
  }

  String _getEmptySubtitle() {
    switch (selectedFilter) {
      case 'Unread':
        return 'You\'ve read all your notifications.\nGreat job staying updated!';
      case 'Orders':
        return 'Order notifications will appear here\nwhen your orders are updated.';
      case 'Promotions':
        return 'We\'ll notify you about exciting\noffers and promotions here.';
      case 'System':
        return 'Important app updates and\nsystem messages will appear here.';
      default:
        return 'We\'ll notify you about orders,\npromotions, and updates here.';
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, int index) {
    final isRead = notification['is_read'] ?? false;
    final type = notification['type'] ?? 'general';
    final title = notification['title'] ?? 'Notification';
    final body = notification['body'] ?? '';
    final createdAt = DateTime.tryParse(notification['created_at'] ?? '') ?? DateTime.now();
    final timeAgo = _formatTimeAgo(createdAt);

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 50)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(notification['id']),
        // Support both directions
        direction: DismissDirection.horizontal,

        // Background for swipe right (mark as read)
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green, Colors.green.shade700]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text(
                'Mark Read',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        // Secondary background for swipe left (delete)
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.red, Colors.red.shade700]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_rounded, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart) {
            // Swipe left - Delete confirmation
            HapticFeedback.mediumImpact();
            return await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Delete Notification'),
                content: const Text('Are you sure you want to delete this notification?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Delete', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          } else {
            // Swipe right - Mark as read (no confirmation needed)
            HapticFeedback.lightImpact();
            if (!isRead) {
              _markAsRead(notification['id'], true);
              _showSuccessSnackBar('Notification marked as read');
            } else {
              _showSuccessSnackBar('Notification already read');
            }
            return false; // Don't actually dismiss the card
          }
        },

        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            // Only delete on left swipe
            _deleteNotification(notification['id']);
          }
        },

        child: GestureDetector(
          onTap: () {
            if (!isRead) {
              _markAsRead(notification['id'], true);
            }
            _showNotificationDetail(notification);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isRead ? Colors.grey.shade200 : kPrimaryColor.withOpacity(0.3),
                width: isRead ? 1 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isRead
                      ? Colors.grey.withOpacity(0.1)
                      : kPrimaryColor.withOpacity(0.1),
                  blurRadius: isRead ? 6 : 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _getTypeGradient(type),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _getTypeGradient(type)[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getTypeIcon(type),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isRead ? Colors.grey.shade700 : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: kPrimaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getTypeGradient(type)[0].withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getTypeLabel(type),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _getTypeGradient(type)[0],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _markAsRead(notification['id'], !isRead);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _getTypeGradient(String type) {
    switch (type) {
      case 'order':
        return [kPrimaryColor, kPrimaryColor.withOpacity(0.8)];
      case 'promotion':
        return [Colors.orange, Colors.orange.shade700];
      case 'system':
        return [Colors.blue, Colors.blue.shade700];
      case 'warning':
        return [Colors.red, Colors.red.shade700];
      default:
        return [Colors.grey.shade600, Colors.grey.shade700];
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'order':
        return Icons.shopping_bag_rounded;
      case 'promotion':
        return Icons.local_offer_rounded;
      case 'system':
        return Icons.settings_rounded;
      case 'warning':
        return Icons.warning_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'order':
        return 'Order Update';
      case 'promotion':
        return 'Promotion';
      case 'system':
        return 'System';
      case 'warning':
        return 'Alert';
      default:
        return 'General';
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(dateTime);
    }
  }

  void _showNotificationDetail(Map<String, dynamic> notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationDetailSheet(notification: notification),
    );
  }
}

class NotificationDetailSheet extends StatelessWidget {
  final Map<String, dynamic> notification;

  const NotificationDetailSheet({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final type = notification['type'] ?? 'general';
    final title = notification['title'] ?? 'Notification';
    final body = notification['body'] ?? '';
    final createdAt = DateTime.tryParse(notification['created_at'] ?? '') ?? DateTime.now();
    final formattedDate = DateFormat('EEEE, MMMM dd, yyyy • hh:mm a').format(createdAt);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 5,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _getTypeGradient(type),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _getTypeGradient(type)[0].withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _getTypeIcon(type),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getTypeGradient(type)[0].withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _getTypeLabel(type),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _getTypeGradient(type)[0],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      body,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  List<Color> _getTypeGradient(String type) {
    switch (type) {
      case 'order':
        return [kPrimaryColor, kPrimaryColor.withOpacity(0.8)];
      case 'promotion':
        return [Colors.orange, Colors.orange.shade700];
      case 'system':
        return [Colors.blue, Colors.blue.shade700];
      case 'warning':
        return [Colors.red, Colors.red.shade700];
      default:
        return [Colors.grey.shade600, Colors.grey.shade700];
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'order':
        return Icons.shopping_bag_rounded;
      case 'promotion':
        return Icons.local_offer_rounded;
      case 'system':
        return Icons.settings_rounded;
      case 'warning':
        return Icons.warning_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'order':
        return 'Order Update';
      case 'promotion':
        return 'Promotion';
      case 'system':
        return 'System';
      case 'warning':
        return 'Alert';
      default:
        return 'General';
    }
  }
}