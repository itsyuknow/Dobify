import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'colors.dart';
import 'login_screen.dart';
import 'support_screen.dart';
import 'address_book_screen.dart';
import '../widgets/custom_bottom_nav.dart';
import 'order_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool openOrderHistory;

  const ProfileScreen({super.key, this.openOrderHistory = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();

  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? orderStats;
  List<Map<String, dynamic>> userAddresses = [];
  bool isLoading = true;
  bool isUploadingImage = false;
  double uploadProgress = 0.0;
  bool _disposed = false;
  bool _isPersonalInfoExpanded = false; // New state for expansion

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _expansionController; // New controller for expansion
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _expansionAnimation; // New animation for expansion

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadProfileData();

    // Open order history if requested
    if (widget.openOrderHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToOrderHistory();
      });
    }
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expansionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _expansionAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expansionController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _scaleController.forward();
  }

  @override
  void dispose() {
    _disposed = true;
    _fadeController.dispose();
    _scaleController.dispose();
    _expansionController.dispose();
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

      // Get profile data
      final profileResponse = await supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      // Auto-fill data based on login method
      Map<String, dynamic> profileData = profileResponse ?? {'user_id': user.id};

      // If profile doesn't exist or missing data, try to auto-fill from auth
      if (profileResponse == null || profileData['phone_number'] == null) {
        // Check if user logged in with phone (phone will be in user.phone)
        if (user.phone != null && user.phone!.isNotEmpty) {
          profileData['phone_number'] = user.phone;
        }

        // Try to extract name from email or user metadata
        if (profileData['first_name'] == null || profileData['first_name'].toString().isEmpty) {
          if (user.userMetadata?['full_name'] != null) {
            List<String> nameParts = user.userMetadata!['full_name'].toString().split(' ');
            profileData['first_name'] = nameParts.isNotEmpty ? nameParts.first : '';
            profileData['last_name'] = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
          } else if (user.email != null) {
            // Extract name from email (before @)
            String emailName = user.email!.split('@').first;
            profileData['first_name'] = emailName.replaceAll('.', ' ').replaceAll('_', ' ');
          }
        }

        // Auto-save the profile if we have new data
        if (user.phone != null || user.userMetadata?['full_name'] != null) {
          try {
            await supabase.from('user_profiles').upsert({
              'user_id': user.id,
              'first_name': profileData['first_name'],
              'last_name': profileData['last_name'],
              'phone_number': profileData['phone_number'],
              'updated_at': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            print('Error auto-saving profile: $e');
          }
        }
      }

      // Calculate order stats with proper data handling
      Map<String, dynamic> orderStatsData = {'total_orders': 0, 'completed_orders': 0, 'total_spent': 0.0, 'total_saved': 0.0};

      try {
        print('Calculating order stats for user: ${user.id}');

        // Get all orders for the user
        final ordersResponse = await supabase
            .from('orders')
            .select('id, status, total_amount, discount_amount, created_at')
            .eq('user_id', user.id);

        print('Found ${ordersResponse.length} orders for stats calculation');

        if (ordersResponse.isNotEmpty) {
          orderStatsData['total_orders'] = ordersResponse.length;

          int completedCount = 0;
          double totalSpent = 0.0;
          double totalSaved = 0.0;

          for (var order in ordersResponse) {
            print('Processing order: ${order['id']} - Status: ${order['status']} - Amount: ${order['total_amount']} - Discount: ${order['discount_amount']}');

            // Count completed/delivered orders
            final status = order['status']?.toString().toLowerCase() ?? '';
            if (status == 'delivered' || status == 'completed') {
              completedCount++;
            }

            // Sum total amount - handle different data types
            final totalAmountRaw = order['total_amount'];
            double orderAmount = 0.0;

            if (totalAmountRaw != null) {
              if (totalAmountRaw is String) {
                orderAmount = double.tryParse(totalAmountRaw) ?? 0.0;
              } else if (totalAmountRaw is int) {
                orderAmount = totalAmountRaw.toDouble();
              } else if (totalAmountRaw is double) {
                orderAmount = totalAmountRaw;
              } else if (totalAmountRaw is num) {
                orderAmount = totalAmountRaw.toDouble();
              }
            }

            totalSpent += orderAmount;
            print('Order amount: $orderAmount, Running total: $totalSpent');

            // Sum total savings from discount_amount
            final discountAmountRaw = order['discount_amount'];
            double discountAmount = 0.0;

            if (discountAmountRaw != null) {
              if (discountAmountRaw is String) {
                discountAmount = double.tryParse(discountAmountRaw) ?? 0.0;
              } else if (discountAmountRaw is int) {
                discountAmount = discountAmountRaw.toDouble();
              } else if (discountAmountRaw is double) {
                discountAmount = discountAmountRaw;
              } else if (discountAmountRaw is num) {
                discountAmount = discountAmountRaw.toDouble();
              }
            }

            totalSaved += discountAmount;
            print('Discount amount: $discountAmount, Running total saved: $totalSaved');
          }

          orderStatsData['completed_orders'] = completedCount;
          orderStatsData['total_spent'] = totalSpent;
          orderStatsData['total_saved'] = totalSaved;

          print('Final calculated stats: $orderStatsData');
        }

        // Alternative: Try to get from order_billing_details table for more accurate data
        if (ordersResponse.isNotEmpty) {
          try {
            final orderIds = ordersResponse.map((order) => order['id']).toList();
            final billingResponse = await supabase
                .from('order_billing_details')
                .select('total_amount, discount_amount, order_id')
                .inFilter('order_id', orderIds);

            if (billingResponse.isNotEmpty) {
              double billingTotalSpent = 0.0;
              double billingTotalSaved = 0.0;

              for (var billing in billingResponse) {
                // Total amount from billing
                final billingAmountRaw = billing['total_amount'];
                if (billingAmountRaw != null) {
                  double amount = 0.0;
                  if (billingAmountRaw is String) {
                    amount = double.tryParse(billingAmountRaw) ?? 0.0;
                  } else if (billingAmountRaw is num) {
                    amount = billingAmountRaw.toDouble();
                  }
                  billingTotalSpent += amount;
                }

                // Discount amount from billing
                final billingDiscountRaw = billing['discount_amount'];
                if (billingDiscountRaw != null) {
                  double discount = 0.0;
                  if (billingDiscountRaw is String) {
                    discount = double.tryParse(billingDiscountRaw) ?? 0.0;
                  } else if (billingDiscountRaw is num) {
                    discount = billingDiscountRaw.toDouble();
                  }
                  billingTotalSaved += discount;
                }
              }

              // Use billing data if it seems more accurate (has more data)
              if (billingTotalSpent > 0 || billingTotalSaved > 0) {
                orderStatsData['total_spent'] = billingTotalSpent;
                orderStatsData['total_saved'] = billingTotalSaved;
                print('Using billing data - Spent: $billingTotalSpent, Saved: $billingTotalSaved');
              }
            }
          } catch (e) {
            print('Could not fetch from billing details: $e');
          }
        }

      } catch (e) {
        print('Error calculating order stats: $e');
        // Set default values on error
        orderStatsData = {'total_orders': 0, 'completed_orders': 0, 'total_spent': 0.0, 'total_saved': 0.0};
      }

      final addressResponse = await supabase
          .from('user_addresses')
          .select('id')
          .eq('user_id', user.id);

      _safeSetState(() {
        userProfile = profileData;
        orderStats = orderStatsData;
        userAddresses = List<Map<String, dynamic>>.from(addressResponse ?? []);
        isLoading = false;
      });

      print('Final profile data loaded:');
      print('Profile: $profileData');
      print('Stats: $orderStatsData');
      print('Addresses: ${userAddresses.length}');

    } catch (e) {
      print('Error loading profile data: $e');
      _safeSetState(() {
        userProfile = {'user_id': user.id};
        orderStats = {'total_orders': 0, 'completed_orders': 0, 'total_spent': 0.0, 'total_saved': 0.0};
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

    // Haptic feedback for better UX
    HapticFeedback.lightImpact();

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Choose Profile Picture',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select how you want to add your photo',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.camera_alt,
                    title: 'Camera',
                    subtitle: 'Take a new photo',
                    gradient: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.photo_library,
                    title: 'Gallery',
                    subtitle: 'Choose from photos',
                    gradient: [Colors.purple, Colors.purple.withOpacity(0.8)],
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      _safeSetState(() {
        isUploadingImage = true;
        uploadProgress = 0.0;
      });

      print('📸 Starting upload process...');
      print('📁 File path: ${pickedFile.path}');

      // Simulate smooth progress for better UX
      _simulateUploadProgress();

      final file = File(pickedFile.path);
      if (!await file.exists()) {
        throw Exception('Selected file does not exist');
      }

      final fileSize = await file.length();
      print('📊 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('File size too large (max 5MB)');
      }

      final fileExt = p.extension(file.path).toLowerCase();
      if (fileExt.isEmpty || !['.jpg', '.jpeg', '.png', '.webp'].contains(fileExt)) {
        throw Exception('Invalid file format. Please use JPG, PNG, or WebP');
      }

      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}$fileExt';

      print(' Uploading to avatars bucket with filename: $fileName');

      // Check if avatars bucket exists
      try {
        await supabase.storage.from('avatars').list();
      } catch (e) {
        print('⚠️ Avatars bucket might not exist or RLS policy issue');
        throw Exception('Storage bucket "avatars" not accessible. Please check bucket exists and RLS policies.');
      }

      // Upload file to Supabase Storage
      final uploadResponse = await supabase.storage
          .from('avatars')
          .upload(
        fileName,
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );

      print('✅ Upload response: $uploadResponse');

      // Get public URL
      final publicUrl = supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);

      print('🔗 Public URL generated: $publicUrl');

      _safeSetState(() => uploadProgress = 1.0);

      // Update user profile in database
      print('💾 Updating user profile with avatar URL...');
      await supabase
          .from('user_profiles')
          .upsert({
        'user_id': user.id,
        'avatar_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      print('✅ Profile updated successfully');

      await Future.delayed(const Duration(milliseconds: 300));
      await _loadProfileData();

      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('Profile picture updated successfully!');

    } catch (e) {
      print('❌ Upload error: $e');
      _showErrorSnackBar(_getErrorMessage(e.toString()));
    } finally {
      _safeSetState(() {
        isUploadingImage = false;
        uploadProgress = 0.0;
      });
    }
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _simulateUploadProgress() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!isUploadingImage) {
        timer.cancel();
        return;
      }
      _safeSetState(() {
        uploadProgress += 0.15;
        if (uploadProgress >= 0.9) {
          timer.cancel();
        }
      });
    });
  }

  String _getErrorMessage(String error) {
    if (error.contains('row-level security') || error.contains('RLS')) {
      return 'Storage permission denied. Please check your Supabase RLS policies for the avatars bucket.';
    } else if (error.contains('bucket') || error.contains('not accessible')) {
      return 'Storage bucket not found. Please create "avatars" bucket in Supabase Storage.';
    } else if (error.contains('network') || error.contains('connection')) {
      return 'Network error. Check your connection.';
    } else if (error.contains('size')) {
      return 'File too large. Max 5MB allowed.';
    } else if (error.contains('format')) {
      return 'Invalid file format. Use JPG, PNG, or WebP.';
    } else if (error.contains('not authenticated')) {
      return 'Authentication error. Please login again.';
    }
    return 'Upload failed: ${error.length > 100 ? error.substring(0, 100) + '...' : error}';
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error_outline, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
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
    final fields = ['first_name', 'last_name', 'phone_number', 'avatar_url', 'date_of_birth', 'gender'];
    for (String field in fields) {
      if (userProfile![field] != null && userProfile![field].toString().isNotEmpty) {
        completed++;
      }
    }
    // Also count email as it's always available from auth
    if (supabase.auth.currentUser?.email != null) {
      completed++;
    }
    return ((completed / (fields.length + 1)) * 100).round();
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
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 16),
                    _buildQuickStats(),
                    const SizedBox(height: 16),
                    _buildMenuSection(),
                    const SizedBox(height: 24),
                    _buildPremiumLogoutSection(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: kPrimaryColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
                Colors.purple.withOpacity(0.3),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                _buildAvatarSection(),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  supabase.auth.currentUser?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: _showEditDialog,
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
          ),
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
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white,
            backgroundImage: userProfile?['avatar_url'] != null
                ? NetworkImage(userProfile!['avatar_url'])
                : null,
            child: userProfile?['avatar_url'] == null
                ? Icon(Icons.person_rounded, size: 60, color: kPrimaryColor)
                : null,
          ),
        ),
        if (isUploadingImage)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        value: uploadProgress,
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(uploadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 4,
          right: 4,
          child: GestureDetector(
            onTap: isUploadingImage ? null : _pickAndUploadImage,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor, Colors.purple],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isUploadingImage ? Icons.hourglass_empty : Icons.camera_alt_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Completion Header with Dropdown Arrow
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _isPersonalInfoExpanded = !_isPersonalInfoExpanded;
                if (_isPersonalInfoExpanded) {
                  _expansionController.forward();
                } else {
                  _expansionController.reverse();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: profileCompleteness < 50
                      ? [Colors.orange.withOpacity(0.1), Colors.orange.withOpacity(0.05)]
                      : [kPrimaryColor.withOpacity(0.1), kPrimaryColor.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: profileCompleteness < 50
                      ? Colors.orange.withOpacity(0.3)
                      : kPrimaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: profileCompleteness < 50
                            ? [Colors.orange, Colors.orange.withOpacity(0.8)]
                            : [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (profileCompleteness < 50 ? Colors.orange : kPrimaryColor)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(Icons.trending_up_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Profile Completion',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                              turns: _isPersonalInfoExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isPersonalInfoExpanded
                              ? 'Tap to collapse personal info'
                              : 'Tap to view personal info',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: profileCompleteness < 50
                            ? [Colors.orange, Colors.orange.withOpacity(0.8)]
                            : [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: (profileCompleteness < 50 ? Colors.orange : kPrimaryColor)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      '$profileCompleteness%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: profileCompleteness / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                profileCompleteness < 50 ? Colors.orange : kPrimaryColor,
              ),
              minHeight: 8,
            ),
          ),

          // Expanded Personal Information Section
          AnimatedBuilder(
            animation: _expansionAnimation,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  heightFactor: _expansionAnimation.value,
                  child: child,
                ),
              );
            },
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Personal Information Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.grey.shade50,
                        Colors.white,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [kPrimaryColor.withOpacity(0.2), kPrimaryColor.withOpacity(0.1)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.person_rounded, color: kPrimaryColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _showEditDialog,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    backgroundColor: kPrimaryColor.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: kPrimaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildEnhancedInfoRow(Icons.person_rounded, 'Name',
                          '${userProfile?['first_name'] ?? ''} ${userProfile?['last_name'] ?? ''}'.trim().isEmpty
                              ? 'Not set'
                              : '${userProfile!['first_name'] ?? ''} ${userProfile!['last_name'] ?? ''}'.trim()),
                      _buildEnhancedInfoRow(Icons.email_rounded, 'Email',
                          supabase.auth.currentUser?.email ?? 'Not set'),
                      _buildEnhancedInfoRow(Icons.phone_rounded, 'Phone', userProfile?['phone_number'] ?? 'Not set'),
                      _buildEnhancedInfoRow(Icons.cake_rounded, 'Birthday', userProfile?['date_of_birth'] ?? 'Not set'),
                      _buildEnhancedInfoRow(Icons.person_outline_rounded, 'Gender', userProfile?['gender'] ?? 'Not set'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor.withOpacity(0.1), Colors.purple.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: kPrimaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedInfoRow(IconData icon, String label, String value) {
    bool hasValue = value != 'Not set' && value.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasValue ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasValue ? kPrimaryColor.withOpacity(0.2) : Colors.grey.shade300,
        ),
        boxShadow: hasValue ? [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasValue
                    ? [kPrimaryColor.withOpacity(0.15), kPrimaryColor.withOpacity(0.08)]
                    : [Colors.grey.shade200, Colors.grey.shade100],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: hasValue ? kPrimaryColor : Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: hasValue ? Colors.black87 : Colors.grey.shade500,
                    fontWeight: hasValue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!hasValue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Add',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (hasValue)
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Colors.green.shade600,
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
          Expanded(
            child: _buildStatCard(
              '${orderStats?['total_orders'] ?? 0}',
              'Total Orders',
              Icons.shopping_bag_rounded,
              [Colors.blue, Colors.blue.withOpacity(0.8)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              '₹${(orderStats?['total_saved'] ?? 0.0).toStringAsFixed(0)}',
              'Total Saved',
              Icons.local_offer_rounded,
              [Colors.green, Colors.green.withOpacity(0.8)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              '₹${(orderStats?['total_spent'] ?? 0.0).toStringAsFixed(0)}',
              'Total Spent',
              Icons.currency_rupee_rounded,
              [Colors.purple, Colors.purple.withOpacity(0.8)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String count, String label, IconData icon, List<Color> gradient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection() {
    final menuItems = [
      {
        'icon': Icons.history_rounded,
        'title': 'Order History',
        'subtitle': 'View past orders & track status',
        'gradient': [Colors.orange, Colors.orange.withOpacity(0.8)],
        'onTap': () => _navigateToOrderHistory(),
      },
      {
        'icon': Icons.location_on_rounded,
        'title': 'My Addresses',
        'subtitle': 'Manage delivery addresses',
        'gradient': [Colors.green, Colors.green.withOpacity(0.8)],
        'onTap': () => _navigateToAddressBook(),
      },
      {
        'icon': Icons.notifications_rounded,
        'title': 'Notifications',
        'subtitle': 'App preferences & alerts',
        'gradient': [Colors.blue, Colors.blue.withOpacity(0.8)],
        'onTap': () => _navigateToNotifications(),
      },
      {
        'icon': Icons.support_agent_rounded,
        'title': 'Help & Support',
        'subtitle': 'Get assistance & contact us',
        'gradient': [Colors.purple, Colors.purple.withOpacity(0.8)],
        'onTap': () => _navigateToSupport(),
      },
      {
        'icon': Icons.privacy_tip_rounded,
        'title': 'Privacy Policy',
        'subtitle': 'Read our privacy policy',
        'gradient': [Colors.teal, Colors.teal.withOpacity(0.8)],
        'onTap': () => _openPrivacyPolicy(),
      },
      {
        'icon': Icons.description_rounded,
        'title': 'Terms & Conditions',
        'subtitle': 'Read terms of service',
        'gradient': [Colors.indigo, Colors.indigo.withOpacity(0.8)],
        'onTap': () => _openTermsConditions(),
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: menuItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildMenuItem(
            icon: item['icon'] as IconData,
            title: item['title'] as String,
            subtitle: item['subtitle'] as String,
            gradient: item['gradient'] as List<Color>,
            onTap: item['onTap'] as VoidCallback,
            isFirst: index == 0,
            isLast: index == menuItems.length - 1,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(20) : Radius.zero,
          bottom: isLast ? const Radius.circular(20) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: gradient[0].withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumLogoutSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showLogoutDialog();
          },
          borderRadius: BorderRadius.circular(25),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626), // Solid red color
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFFDC2626).withOpacity(0.2),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sign out of your account securely',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Navigation methods remain the same...
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
        _showErrorSnackBar('Could not open link');
      }
    }
  }

  void _showEditDialog() {
    final firstNameController = TextEditingController(text: userProfile?['first_name'] ?? '');
    final lastNameController = TextEditingController(text: userProfile?['last_name'] ?? '');
    final phoneController = TextEditingController(text: userProfile?['phone_number'] ?? '');
    final dobController = TextEditingController(text: userProfile?['date_of_birth'] ?? '');

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String selectedGender = userProfile?['gender'] ?? '';

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 700),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    kPrimaryColor.withOpacity(0.02),
                    Colors.white,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Premium Header
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 24
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Profile',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Update your personal information',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                                firstNameController.dispose();
                                lastNameController.dispose();
                                phoneController.dispose();
                                dobController.dispose();
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Form Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            // Name Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPremiumEditField(
                                    firstNameController,
                                    'First Name',
                                    Icons.person_rounded,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildPremiumEditField(
                                    lastNameController,
                                    'Last Name',
                                    Icons.person_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Phone Number
                            _buildPremiumEditField(
                              phoneController,
                              'Phone Number',
                              Icons.phone_rounded,
                              TextInputType.phone,
                            ),
                            const SizedBox(height: 20),

                            // Date of Birth
                            GestureDetector(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: userProfile?['date_of_birth'] != null
                                      ? DateTime.tryParse(userProfile!['date_of_birth']) ?? DateTime.now()
                                      : DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  dobController.text = picked.toIso8601String().split('T')[0];
                                }
                              },
                              child: AbsorbPointer(
                                child: _buildPremiumEditField(
                                    dobController,
                                    'Date of Birth',
                                    Icons.cake_rounded,
                                    null,
                                    'Tap to select date'
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Gender Selection - Premium Design
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.grey.shade50,
                                    Colors.white,
                                    kPrimaryColor.withOpacity(0.02),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: kPrimaryColor.withOpacity(0.15),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimaryColor.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [kPrimaryColor.withOpacity(0.15), kPrimaryColor.withOpacity(0.08)],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                            Icons.person_outline_rounded,
                                            color: kPrimaryColor,
                                            size: 20
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Gender',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Gender Options
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildGenderOption(
                                          'Male',
                                          Icons.male_rounded,
                                          selectedGender == 'Male',
                                              () {
                                            setDialogState(() {
                                              selectedGender = 'Male';
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildGenderOption(
                                          'Female',
                                          Icons.female_rounded,
                                          selectedGender == 'Female',
                                              () {
                                            setDialogState(() {
                                              selectedGender = 'Female';
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.grey.shade100, Colors.grey.shade50],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        firstNameController.dispose();
                                        lastNameController.dispose();
                                        phoneController.dispose();
                                        dobController.dispose();
                                      },
                                      style: TextButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kPrimaryColor.withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        Map<String, dynamic> updateData = {
                                          'first_name': firstNameController.text.trim(),
                                          'last_name': lastNameController.text.trim(),
                                          'phone_number': phoneController.text.trim(),
                                        };

                                        if (dobController.text.trim().isNotEmpty) {
                                          updateData['date_of_birth'] = dobController.text.trim();
                                        }

                                        if (selectedGender.isNotEmpty) {
                                          updateData['gender'] = selectedGender;
                                        }

                                        await _updateProfile(updateData);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                        firstNameController.dispose();
                                        lastNameController.dispose();
                                        phoneController.dispose();
                                        dobController.dispose();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.save_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Save Changes',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
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
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPremiumEditField(
      TextEditingController controller,
      String label,
      IconData icon,
      [TextInputType? keyboardType, String? hintText]
      ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: TextStyle(
            color: kPrimaryColor.withOpacity(0.7),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 14,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor.withOpacity(0.15), kPrimaryColor.withOpacity(0.08)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPrimaryColor, size: 20),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildGenderOption(String gender, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
            colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          )
              : LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ]
              : [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : kPrimaryColor,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              gender,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField(TextEditingController controller, String label, IconData icon, [TextInputType? keyboardType, String? hintText]) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kPrimaryColor.withOpacity(0.1), Colors.purple.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 20),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: kPrimaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Clean up the updates - remove null or empty values
      Map<String, dynamic> cleanUpdates = {};
      updates.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          cleanUpdates[key] = value;
        }
      });

      cleanUpdates['user_id'] = user.id;
      cleanUpdates['updated_at'] = DateTime.now().toIso8601String();

      print('Updating profile with data: $cleanUpdates');

      await supabase.from('user_profiles').upsert(
        cleanUpdates,
        onConflict: 'user_id',
      );

      print('Profile update successful');
      await _loadProfileData();

      HapticFeedback.mediumImpact();
      _showSuccessSnackBar('Profile updated successfully!');
    } catch (e) {
      print('Error updating profile: $e');
      _showErrorSnackBar('Failed to update profile: ${e.toString()}');
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFFFF5F5)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.red, Color(0xFFE91E63)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              const Text(
                'Logout Confirmation',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to logout from your account? You\'ll need to sign in again to access your profile.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Logout',
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
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================
// NOTIFICATION SETTINGS SCREEN
// ========================================

class _NotificationSettingsScreen extends StatelessWidget {
  const _NotificationSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Notification Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back_ios_rounded, color: kPrimaryColor, size: 16),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor.withOpacity(0.1), Colors.purple.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.notifications_rounded,
                size: 80,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Notification Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming Soon!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'We\'re working on bringing you\npersonalized notification preferences.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}