import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'colors.dart';
import 'login_screen.dart';
import 'support_screen.dart';
import 'address_book_screen.dart';
import '../widgets/custom_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();

  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? orderStats;
  List<Map<String, dynamic>> userAddresses = [];
  bool isLoading = true;
  bool isUploadingImage = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  Future<void> _loadProfileData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      _safeSetState(() => isLoading = true);

      final profileResponse = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      final statsResponse = await supabase
          .rpc('get_user_order_stats', params: {'user_uuid': user.id});

      final addressResponse = await supabase
          .from('user_addresses')
          .select('id')
          .eq('user_id', user.id);

      _safeSetState(() {
        userProfile = profileResponse ?? {'user_id': user.id};
        orderStats = statsResponse.isNotEmpty ? statsResponse[0] : {
          'total_orders': 0,
          'completed_orders': 0,
          'total_spent': 0.0
        };
        userAddresses = List<Map<String, dynamic>>.from(addressResponse ?? []);
        isLoading = false;
      });
    } catch (e) {
      print('Error loading profile data: $e');
      _safeSetState(() {
        userProfile = {'user_id': user.id};
        orderStats = {'total_orders': 0, 'completed_orders': 0, 'total_spent': 0.0};
        userAddresses = [];
        isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('User not authenticated');
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Image Source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.camera_alt, color: kPrimaryColor, size: 30),
                          const SizedBox(height: 8),
                          Text(
                            'Camera',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.photo_library, color: kPrimaryColor, size: 30),
                          const SizedBox(height: 8),
                          Text(
                            'Gallery',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        _showErrorSnackBar('No image selected');
        return;
      }

      _safeSetState(() => isUploadingImage = true);

      // Check if file exists and is readable
      final file = File(pickedFile.path);
      if (!await file.exists()) {
        throw Exception('Selected file does not exist');
      }

      // Check file size (limit to 5MB)
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('File size too large (max 5MB)');
      }

      print('📸 Starting upload process...');
      print('📁 File path: ${pickedFile.path}');
      print('📊 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      final fileExt = p.extension(file.path).toLowerCase();
      if (fileExt.isEmpty) {
        throw Exception('Invalid file format');
      }

      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}$fileExt';
      final filePath = fileName; // Remove 'avatars/' prefix, it's handled by the bucket

      print('🚀 Uploading to path: $filePath');

      // Step 1: Upload file to Supabase Storage
      final uploadResponse = await supabase.storage
          .from('avatars')
          .upload(
        filePath,
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );

      print('✅ Upload successful: ${uploadResponse}');

      // Step 2: Get public URL
      final publicUrl = supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);

      print('🔗 Public URL generated: $publicUrl');

      // Step 3: Update user profile in database
      final updateResponse = await supabase
          .from('user_profiles')
          .upsert({
        'user_id': user.id,
        'avatar_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('💾 Profile updated successfully');

      // Step 4: Reload profile data
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Profile picture updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

    } catch (e) {
      print('❌ Upload error: $e');

      String errorMessage = 'Failed to upload image';

      if (e.toString().contains('row-level security')) {
        errorMessage = 'Storage permission denied. Please check your Supabase policies.';
      } else if (e.toString().contains('bucket')) {
        errorMessage = 'Storage bucket not found. Please create "avatars" bucket in Supabase.';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('size')) {
        errorMessage = 'File too large. Please select a smaller image.';
      } else if (e.toString().contains('format')) {
        errorMessage = 'Invalid file format. Please select a valid image.';
      }

      _showErrorSnackBar(errorMessage);

    } finally {
      _safeSetState(() => isUploadingImage = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String get displayName {
    final firstName = userProfile?['first_name'] ?? '';
    final lastName = userProfile?['last_name'] ?? '';
    if (firstName.isEmpty && lastName.isEmpty) {
      return supabase.auth.currentUser?.email?.split('@').first.toUpperCase() ?? 'USER';
    }
    return '$firstName $lastName'.trim().toUpperCase();
  }

  int get profileCompleteness {
    if (userProfile == null) return 0;
    int completed = 0;
    final fields = ['first_name', 'last_name', 'phone_number', 'avatar_url'];
    for (String field in fields) {
      if (userProfile![field] != null && userProfile![field].toString().isNotEmpty) {
        completed++;
      }
    }
    return ((completed / fields.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Please log in to view profile', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              const Text('Loading profile...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildProfileCard(),
                const SizedBox(height: 16),
                _buildQuickStats(),
                const SizedBox(height: 16),
                _buildMenuSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: kPrimaryColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                _buildAvatarSection(),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  supabase.auth.currentUser?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _showEditDialog,
          icon: const Icon(Icons.edit, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildAvatarSection() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 45,
            backgroundColor: Colors.white,
            backgroundImage: userProfile?['avatar_url'] != null
                ? NetworkImage(userProfile!['avatar_url'])
                : null,
            child: userProfile?['avatar_url'] == null
                ? Icon(Icons.person, size: 50, color: kPrimaryColor)
                : null,
          ),
        ),
        if (isUploadingImage)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: isUploadingImage ? null : _pickAndUploadImage,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: kPrimaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.camera_alt,
                size: 16,
                color: kPrimaryColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Completion',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: profileCompleteness / 100,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$profileCompleteness%',
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.person, 'Name',
              '${userProfile?['first_name'] ?? ''} ${userProfile?['last_name'] ?? ''}'.trim().isEmpty
                  ? 'Not set' : '${userProfile!['first_name'] ?? ''} ${userProfile!['last_name'] ?? ''}'.trim()),
          _buildInfoRow(Icons.phone, 'Phone', userProfile?['phone_number'] ?? 'Not set'),
          _buildInfoRow(Icons.cake, 'Birthday', userProfile?['date_of_birth'] ?? 'Not set'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: kPrimaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildStatCard(
              '${orderStats?['total_orders'] ?? 0}',
              'Orders',
              Icons.shopping_bag
          )),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard(
              '${userAddresses.length}',
              'Addresses',
              Icons.location_on
          )),
        ],
      ),
    );
  }

  Widget _buildStatCard(String count, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: kPrimaryColor, size: 24),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection() {
    const isFirstItem = true;
    const isLastItem = false;

    final menuItems = [
      {
        'icon': Icons.history,
        'title': 'Order History',
        'subtitle': 'View past orders',
        'onTap': () => _navigateToOrderHistory(),
      },
      {
        'icon': Icons.location_on,
        'title': 'My Addresses',
        'subtitle': 'Manage addresses',
        'onTap': () => _navigateToAddressBook(),
      },
      {
        'icon': Icons.notifications,
        'title': 'Notifications',
        'subtitle': 'App preferences',
        'onTap': () => _navigateToNotifications(),
      },
      {
        'icon': Icons.support_agent,
        'title': 'Help & Support',
        'subtitle': 'Get assistance',
        'onTap': () => _navigateToSupport(),
      },
      {
        'icon': Icons.privacy_tip,
        'title': 'Privacy Policy',
        'subtitle': 'Read privacy policy',
        'onTap': () => _openPrivacyPolicy(),
      },
      {
        'icon': Icons.description,
        'title': 'Terms & Conditions',
        'subtitle': 'Read terms',
        'onTap': () => _openTermsConditions(),
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ...menuItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return _buildMenuItem(
              icon: item['icon'] as IconData,
              title: item['title'] as String,
              subtitle: item['subtitle'] as String,
              onTap: item['onTap'] as VoidCallback,
              isFirst: index == 0,
              isLast: index == menuItems.length - 1,
            );
          }),
          const Divider(height: 1),
          _buildLogoutTile(),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(16) : Radius.zero,
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kPrimaryColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showLogoutDialog,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      'Sign out of your account',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // Navigation methods
  void _navigateToOrderHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OrderHistoryScreen()),
    );
  }

  void _navigateToAddressBook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressBookScreen(
          onAddressSelected: (Map<String, dynamic> address) {
            // Handle address selection if needed
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _navigateToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const _NotificationSettingsScreen()),
    );
  }

  void _navigateToSupport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SupportScreen()),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    await _openUrlFromSupabase('privacy_policy_url');
  }

  Future<void> _openTermsConditions() async {
    await _openUrlFromSupabase('terms_conditions_url');
  }

  Future<void> _openUrlFromSupabase(String settingKey) async {
    try {
      final response = await supabase
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', settingKey)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        final url = response['setting_value'] as String;
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch $url';
        }
      } else {
        throw 'URL not found';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showEditDialog() {
    final firstNameController = TextEditingController(text: userProfile?['first_name'] ?? '');
    final lastNameController = TextEditingController(text: userProfile?['last_name'] ?? '');
    final phoneController = TextEditingController(text: userProfile?['phone_number'] ?? '');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit, color: kPrimaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: firstNameController,
                decoration: InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: lastNameController,
                decoration: InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        firstNameController.dispose();
                        lastNameController.dispose();
                        phoneController.dispose();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _updateProfile({
                          'first_name': firstNameController.text.trim(),
                          'last_name': lastNameController.text.trim(),
                          'phone_number': phoneController.text.trim(),
                        });
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                        firstNameController.dispose();
                        lastNameController.dispose();
                        phoneController.dispose();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Save', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      updates['user_id'] = user.id;
      await supabase.from('user_profiles').upsert(updates);
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Profile updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Text('Failed to update profile'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 12),
            Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout from your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ========================================
// ORDER HISTORY SCREEN
// ========================================

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          orders = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading orders: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: kPrimaryColor))
          : orders.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('No orders yet', style: TextStyle(fontSize: 18)),
            Text('Start shopping to see your orders here!'),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _buildOrderCard(order);
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${order['order_number'] ?? 'N/A'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(order['status']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  order['status']?.toString().toUpperCase() ?? 'UNKNOWN',
                  style: TextStyle(
                    color: _getStatusColor(order['status']),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total: ₹${order['total_amount'] ?? '0.00'}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            'Date: ${_formatDate(order['created_at'])}',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (order['order_items'] != null && order['order_items'].isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Items: ${order['order_items'].length}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString.toString());
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  Color _getStatusColor(dynamic status) {
    final statusString = status?.toString().toLowerCase() ?? '';
    switch (statusString) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}

// ========================================
// SIMPLE NOTIFICATION SCREEN
// ========================================

class _NotificationSettingsScreen extends StatelessWidget {
  const _NotificationSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: const Center(
        child: Text('Notification Settings - Coming Soon'),
      ),
    );
  }
}