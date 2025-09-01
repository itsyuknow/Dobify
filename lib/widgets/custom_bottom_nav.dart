import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../screens/home_screen.dart';
import '../screens/order_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ADD: Persist dismissals so the review bar doesn't show again after refresh
import 'package:shared_preferences/shared_preferences.dart';

class CustomBottomNav extends StatefulWidget {
  final int currentIndex;
  const CustomBottomNav({super.key, required this.currentIndex});

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  bool _showReview = false;
  bool _reviewExpanded = false;
  int _selectedRating = 0;
  String? _lastOrderId;
  List<String> _selectedFeedback = [];
  List<Map<String, dynamic>> _feedbackOptions = [];
  TextEditingController _customFeedbackController = TextEditingController();

  // KEY PREFIX for local persistence of dismissals
  static const String _dismissedKeyPrefix = 'dismissed_review_';

  @override
  void initState() {
    super.initState();
    _checkForPendingReview();
    _loadFeedbackOptions();
  }

  @override
  void dispose() {
    _customFeedbackController.dispose();
    super.dispose();
  }

  Future<void> _checkForPendingReview() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      print('Debug: User ID = $userId');
      if (userId == null) return;

      // Get the last delivered order
      final response = await Supabase.instance.client
          .from('orders')
          .select('id, order_status')
          .eq('user_id', userId)
          .eq('order_status', 'Delivered')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      print('Debug: Order response = $response');

      if (response != null) {
        final orderId = response['id'] as String?;

        // Check local dismissal first
        if (orderId != null) {
          final prefs = await SharedPreferences.getInstance();
          final dismissed = prefs.getBool('$_dismissedKeyPrefix$orderId') ?? false;
          print('Debug: Dismissed locally for $orderId = $dismissed');
          if (dismissed) {
            // User has dismissed this already; don't show
            return;
          }
        }

        // Check if review already exists for this order
        final existingReview = await Supabase.instance.client
            .from('reviews')
            .select('id')
            .eq('order_id', orderId as Object)
            .maybeSingle();

        print('Debug: Existing review = $existingReview');

        if (existingReview == null) {
          print('Debug: Setting _showReview to true');
          setState(() {
            _lastOrderId = orderId;
            _showReview = true;
          });
          print('Debug: _showReview is now $_showReview');
        } else {
          print('Debug: Review already exists for this order');
        }
      } else {
        print('Debug: No delivered orders found');
      }
    } catch (e) {
      print('Error checking for pending review: $e');
    }
  }

  Future<void> _loadFeedbackOptions() async {
    try {
      final response = await Supabase.instance.client
          .from('review_feedback_options')
          .select('*')
          .order('id');

      setState(() {
        _feedbackOptions = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading feedback options: $e');
    }
  }

  Future<void> _submitReview() async {
    if (_selectedRating == 0 || _lastOrderId == null) return;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.from('reviews').insert({
        'order_id': _lastOrderId,
        'user_id': userId,
        'rating': _selectedRating,
        'feedback_options': _selectedFeedback,
        'custom_feedback': _customFeedbackController.text.trim().isEmpty
            ? null
            : _customFeedbackController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });

      // Also mark as dismissed locally, just in case
      await _markDismissedForCurrentOrder();

      await _dismissReview();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your review!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markDismissedForCurrentOrder() async {
    try {
      if (_lastOrderId == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_dismissedKeyPrefix$_lastOrderId', true);
      print('Debug: Persisted dismissal for order: $_lastOrderId');
    } catch (e) {
      print('Error persisting dismissal: $e');
    }
  }

  Future<void> _dismissReview() async {
    // Persist the dismissal so it doesn't show again on refresh
    await _markDismissedForCurrentOrder();

    if (!mounted) return;
    setState(() {
      _showReview = false;
      _reviewExpanded = false;
      _selectedRating = 0;
      _selectedFeedback.clear();
      _customFeedbackController.clear();
    });
  }

  void _onStarTap(int rating) {
    setState(() {
      _selectedRating = rating;
      _reviewExpanded = true;
    });
  }

  void _navigateTo(BuildContext context, int index) {
    if (index == widget.currentIndex) return;
    Widget dest;
    switch (index) {
      case 0:
        dest = const HomeScreen();
        break;
      case 1:
        dest = const OrdersScreen(category: 'All');
        break;
      case 2:
        dest = const ProfileScreen();
        break;
      default:
        return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => dest),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;

    // Calculate responsive values
    final isSmallScreen = screenHeight < 700;
    final navBarHeight = isSmallScreen ? 60.0 : 70.0;
    final iconSize = isSmallScreen ? 22.0 : 24.0;
    final fontSize = isSmallScreen ? 10.0 : 12.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 14.0;
    final verticalPadding = isSmallScreen ? 4.0 : 6.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expanded review section
        if (_showReview && _reviewExpanded) _buildExpandedReview(),
        // Bottom navigation
        Container(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.zero,
            child: Container(
              height: navBarHeight,
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _showReview
                    ? _buildReviewNavBar()
                    : _buildNormalNavBar(
                  iconSize: iconSize,
                  fontSize: fontSize,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewNavBar() {
    return Row(
      children: [
        // Rate your experience text
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Text(
              'Rate your experience',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // Star Rating
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            return GestureDetector(
              onTap: () => _onStarTap(starIndex),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  starIndex <= _selectedRating ? Icons.star : Icons.star_border,
                  color: starIndex <= _selectedRating ? Colors.orange : Colors.grey[400],
                  size: 24,
                ),
              ),
            );
          }),
        ),
        // Close button
        GestureDetector(
          onTap: () async {
            await _dismissReview();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.close,
              size: 24,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalNavBar({
    required double iconSize,
    required double fontSize,
    required double horizontalPadding,
    required double verticalPadding,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildNavItem(
          context,
          index: 0,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Home',
          iconSize: iconSize,
          fontSize: fontSize,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
        ),
        _buildNavItem(
          context,
          index: 1,
          icon: MdiIcons.ironOutline,
          activeIcon: MdiIcons.iron,
          label: 'Services',
          iconSize: iconSize,
          fontSize: fontSize,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
        ),
        _buildNavItem(
          context,
          index: 2,
          icon: Icons.person_outlined,
          activeIcon: Icons.person,
          label: 'Profile',
          iconSize: iconSize,
          fontSize: fontSize,
          horizontalPadding: horizontalPadding,
          verticalPadding: verticalPadding,
        ),
      ],
    );
  }

  Widget _buildExpandedReview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected rating display
            Text(
              _getRatingText(_selectedRating),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _getRatingColor(_selectedRating),
              ),
            ),
            const SizedBox(height: 16),
            // Feedback options
            if (_feedbackOptions.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'What went well?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _feedbackOptions.map((option) {
                  final isSelected = _selectedFeedback.contains(option['text']);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedFeedback.remove(option['text']);
                        } else {
                          _selectedFeedback.add(option['text']);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? kPrimaryColor.withOpacity(0.1) : Colors.grey[100],
                        border: Border.all(
                          color: isSelected ? kPrimaryColor : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        option['text'],
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? kPrimaryColor : Colors.grey[700],
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            // Custom feedback
            TextField(
              controller: _customFeedbackController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: kPrimaryColor),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Submit Review',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Color _getRatingColor(int rating) {
    switch (rating) {
      case 1:
      case 2:
        return Colors.red;
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildNavItem(
      BuildContext context, {
        required int index,
        required IconData icon,
        required IconData activeIcon,
        required String label,
        required double iconSize,
        required double fontSize,
        required double horizontalPadding,
        required double verticalPadding,
      }) {
    final isSelected = index == widget.currentIndex;

    return Expanded(
      child: GestureDetector(
        onTap: () => _navigateTo(context, index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey(isSelected),
                  size: iconSize,
                  color: isSelected ? kPrimaryColor : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: isSelected ? kPrimaryColor : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
