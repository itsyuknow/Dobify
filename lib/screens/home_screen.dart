// ✅ FIXED HOME SCREEN - Proper Integration with Auto-Loading Widget & RenderFlex Fix
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '/widgets/colors.dart';
import 'notifications_screen.dart';
import 'support_screen.dart';
import 'profile_screen.dart';
import 'order_screen.dart';
import '../screens/cart_screen.dart';
import '../utils/globals.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/custom_bottom_nav.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ✅ Import your FIXED DeliveryAddressWidget
import '/widgets/delivery_address_widget.dart'; // Update this import path

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  int _selectedIndex = 0;
  final supabase = Supabase.instance.client;

  List<String> _carouselImages = [];
  List<VideoPlayerController?> _videoControllers = [];
  List<Map<String, dynamic>> _categoryFeatures = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isCategoriesLoading = true;
  Timer? _carouselTimer;
  int _currentBannerIndex = 0;

  String? _backgroundUrl;
  List<Map<String, dynamic>> _contacts = [];

  final PageController _bannerPageController = PageController(
      viewportFraction: 0.94);

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _bannerPageController.addListener(_onBannerPageChanged);
    _loadAllContent();
    _fetchCartCount();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
  }

  Future<void> _loadAllContent() async {
    await Future.wait([
      _loadBanners(),
      _loadCategoryFeatures(),
      _loadCategories(),
      _fetchBackgroundUrl(),
      _fetchContacts(),
    ]);
    _startAutoSlide();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _isCategoriesLoading = true;
      });

      final response = await supabase
          .from('categories')
          .select()
          .eq('is_active', true);

      setState(() {
        _categories = List<Map<String, dynamic>>.from(response);
        _isCategoriesLoading = false;
      });

      print('✅ Categories loaded: ${_categories.length} items');
    } catch (e) {
      print('❌ Error loading categories: $e');
      setState(() {
        _categories = [];
        _isCategoriesLoading = false;
      });
    }
  }

  void _onBannerPageChanged() {
    int newPage = _bannerPageController.page?.round() ?? 0;
    if (_currentBannerIndex != newPage) {
      setState(() {
        _currentBannerIndex = newPage;
      });
      _restartAutoSlide();
    }
  }

  void _startAutoSlide() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_carouselImages.isEmpty) return;
      final nextIndex = (_currentBannerIndex + 1) % _carouselImages.length;
      _bannerPageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _restartAutoSlide() {
    _carouselTimer?.cancel();
    _startAutoSlide();
  }

  Future<void> _fetchBackgroundUrl() async {
    final result = await supabase
        .from('ui_assets')
        .select('background_url')
        .eq('key', 'home_bg')
        .maybeSingle();
    setState(() {
      _backgroundUrl = result?['background_url'] as String?;
    });
  }

  Future<void> _fetchContacts() async {
    try {
      final data = await supabase
          .from('ui_contacts')
          .select('key, label, value, icon, link, color');

      final filtered = List<Map<String, dynamic>>.from(data).where((c) {
        return (c['label']
            ?.toString()
            .isNotEmpty ?? false) &&
            (c['value']
                ?.toString()
                .isNotEmpty ?? false);
      }).toList();

      setState(() => _contacts = filtered);
    } catch (e) {
      print('❌ Error fetching contacts: $e');
    }
  }

  Future<void> _loadBanners() async {
    try {
      final response = await supabase
          .from('banners')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final fetched = List<Map<String, dynamic>>.from(response);
      _carouselImages = [];
      _videoControllers = [];

      for (final banner in fetched) {
        final url = banner['image_url'] as String;
        if (url.endsWith('.mp4')) {
          final controller = VideoPlayerController.networkUrl(Uri.parse(url));
          await controller.initialize();
          controller.setLooping(true);
          controller.setVolume(0);
          _videoControllers.add(controller);
          _carouselImages.add(url);
        } else {
          _videoControllers.add(null);
          _carouselImages.add(url);
        }
      }
      setState(() {});
    } catch (e) {
      print('Error loading banners: $e');
    }
  }

  Future<void> _loadCategoryFeatures() async {
    final data = await supabase
        .from('ui_features')
        .select()
        .eq('tile_type', 'category');
    setState(() => _categoryFeatures = List<Map<String, dynamic>>.from(data));
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _bannerPageController.removeListener(_onBannerPageChanged);
    _fadeController.dispose();
    for (final controller in _videoControllers) {
      controller?.dispose();
    }
    _bannerPageController.dispose();
    super.dispose();
  }

  Future<void> _fetchCartCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final response = await supabase.from('cart').select().eq('id', userId);
    cartCountNotifier.value = response.length;
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // ✅ CALLBACK FUNCTION - Called when DeliveryAddressWidget updates location
  void _onDeliveryLocationUpdated() {
    print('🔄 HomeScreen: Delivery location updated, refreshing home content...');
    // The DeliveryAddressWidget handles its own refresh via real-time subscription
    // You can add additional refresh logic here if needed
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screens = [
      _buildHomeView(),
      const OrdersScreen(category: 'All'),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC), // Premium background
      appBar: _buildAppBar(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: screens[_selectedIndex],
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 0),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
          'ironXpress',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          )
      ),
      backgroundColor: kPrimaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        ValueListenableBuilder<int>(
          valueListenable: cartCountNotifier,
          builder: (_, count, __) {
            return Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CartScreen()),
                    );
                    _fetchCartCount();
                  },
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text('$count',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () =>
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
        ),
        IconButton(
          icon: const Icon(Icons.headset_mic_outlined),
          onPressed: () =>
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHomeView() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        children: [
          if (_backgroundUrl != null)
            Positioned.fill(
              child: Image.network(
                _backgroundUrl!,
                fit: BoxFit.cover,
                color: Colors.white.withOpacity(0.08),
                colorBlendMode: BlendMode.srcATop,
              ),
            ),

          // ✅ FIXED SCROLLVIEW - Better space management
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ✅ FIXED DELIVERY ADDRESS WIDGET - Auto-loads & updates
                const DeliveryAddressWidget(),

                const SizedBox(height: 24),

                // Banner carousel
                _buildBannerCarousel(),

                const SizedBox(height: 28),

                // Categories section
                _buildCategoriesSection(),

                const SizedBox(height: 28),

                // Contact tiles section
                _buildContactTilesSection(),

                const SizedBox(height: 36), // Extra bottom padding
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ EXTRACTED CATEGORIES SECTION - Better organization
  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Categories',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildCategoryGrid(),
      ],
    );
  }

  Widget _buildBannerCarousel() {
    return SizedBox(
      height: 250,
      child: _carouselImages.isEmpty
          ? Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CircularProgressIndicator(
            color: kPrimaryColor,
            strokeWidth: 3,
          ),
        ),
      )
          : Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _bannerPageController,
              itemCount: _carouselImages.length,
              itemBuilder: (context, index) {
                final isVideo = _videoControllers[index] != null;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: isVideo
                        ? VideoPlayer(_videoControllers[index]!)
                        : CachedNetworkImage(
                      imageUrl: _carouselImages[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) =>
                          Container(
                            color: Colors.grey.shade100,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: kPrimaryColor,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                      errorWidget: (context, url, error) =>
                          Container(
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 50,
                            ),
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _carouselImages.length,
                  (index) =>
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 8,
                    width: _currentBannerIndex == index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: _currentBannerIndex == index
                          ? kPrimaryColor
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED CATEGORY GRID - Better responsive design
  Widget _buildCategoryGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _isCategoriesLoading
          ? Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: CircularProgressIndicator(
            color: kPrimaryColor,
            strokeWidth: 3,
          ),
        ),
      )
          : _categories.isEmpty
          ? Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No categories available',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ),
      )
          : GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 20,
          childAspectRatio: 0.76, // ✅ Fixed aspect ratio
        ),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final title = cat['name'];
          final imageUrl = cat['image_url'];
          final feature = _categoryFeatures.firstWhere(
                (f) => f['key'] == title,
            orElse: () => {},
          );

          if (feature['is_visible'] == false) {
            return const SizedBox.shrink();
          }

          return _buildWideCategoryCard(
            title,
            imageUrl,
            isNetwork: true,
            label: feature['label'],
          );
        },
      ),
    );
  }

  // ✅ FIXED CONTACT TILES - Better responsive design
  Widget _buildContactTilesSection() {
    if (_contacts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Contact Us',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            itemCount: _contacts.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 20,
              crossAxisSpacing: 14,
              childAspectRatio: 0.8, // ✅ Fixed aspect ratio
            ),
            itemBuilder: (context, index) {
              final c = _contacts[index];
              final color = _getColor(c['key'], c['color']);
              final icon = _getIcon(c['key']);

              return GestureDetector(
                onTap: () => _launchUrl(c['link']),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // ✅ Prevents overflow
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withOpacity(0.2),
                            color.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(2, 4),
                          )
                        ],
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(height: 8),
                    // ✅ FLEXIBLE TEXT - Prevents overflow
                    Flexible(
                      child: Text(
                        c['label'] ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIcon(String key) {
    switch (key) {
      case 'website':
        return Icons.language;
      case 'mail':
        return Icons.email_outlined;
      case 'support':
        return Icons.phone;
      case 'whatsapp':
        return Icons.chat_bubble_outline;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'facebook':
        return Icons.facebook;
      default:
        return Icons.info_outline;
    }
  }

  Color _getColor(String key, String? colorStr) {
    if (key == 'instagram') return const Color(0xFFE1306C);
    if (key == 'facebook') return const Color(0xFF1877f3);
    if (key == 'whatsapp') return const Color(0xFF25D366);
    if (colorStr != null && colorStr.isNotEmpty) {
      try {
        return Color(int.parse(colorStr.replaceAll('#', '0xff')));
      } catch (_) {}
    }
    return kPrimaryColor;
  }

  void _launchUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      print('❌ Could not launch: $url');
    }
  }

  // ✅ FIXED CATEGORY CARD - Better space management
  Widget _buildWideCategoryCard(String title, String imagePath,
      {bool isNetwork = false, String? label}) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrdersScreen(category: title)),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 6),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // ✅ Prevents overflow
            children: [
              // ✅ FLEXIBLE IMAGE CONTAINER
              Flexible(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(
                    minHeight: 80,
                    maxHeight: 120,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: isNetwork
                        ? CachedNetworkImage(
                      imageUrl: imagePath,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          Container(
                            color: Colors.grey.shade100,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kPrimaryColor,
                              ),
                            ),
                          ),
                      errorWidget: (context, url, error) =>
                          Container(
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.image,
                              size: 40,
                              color: Colors.grey,
                            ),
                          ),
                    )
                        : Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ✅ FLEXIBLE TITLE
              Flexible(
                flex: 1,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // ✅ OPTIONAL LABEL
              if (label != null && label.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}