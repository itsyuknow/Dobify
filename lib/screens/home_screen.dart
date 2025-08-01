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
import '/widgets/delivery_address_widget.dart';

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
  int _notificationCount = 0;

  final PageController _bannerPageController = PageController(viewportFraction: 1.0);
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _bannerPageController.addListener(_onBannerPageChanged);
    _loadAllContent();
    _fetchCartCount();
    _fetchNotificationCount();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
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
        final key = c['key']?.toString().toLowerCase() ?? '';
        return ['facebook', 'website', 'instagram'].contains(key) &&
            (c['label']?.toString().isNotEmpty ?? false) &&
            (c['value']?.toString().isNotEmpty ?? false);
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
    if (userId == null) {
      cartCountNotifier.value = 0;
      return;
    }

    try {
      final response = await supabase
          .from('cart')
          .select('product_quantity')
          .eq('user_id', userId);

      final items = List<Map<String, dynamic>>.from(response);
      final totalCount = items.fold<int>(
        0,
            (sum, item) => sum + (item['product_quantity'] as int? ?? 0),
      );

      cartCountNotifier.value = totalCount;
    } catch (e) {
      print('❌ Error fetching cart count: $e');
      cartCountNotifier.value = 0;
    }
  }

  Future<void> _fetchNotificationCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _notificationCount = 0);
      return;
    }

    try {
      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      setState(() {
        _notificationCount = response.length;
      });
    } catch (e) {
      print('❌ Error fetching notification count: $e');
      setState(() => _notificationCount = 0);
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
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
      backgroundColor: Colors.grey.shade50,
      appBar: _buildPremiumAppBar(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: screens[_selectedIndex],
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 0),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      title: const Text(
        'ironXpress',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          fontSize: 22,
        ),
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
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: ValueListenableBuilder<int>(
            valueListenable: cartCountNotifier,
            builder: (_, count, __) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.8),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(21),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CartScreen()),
                          );
                          _fetchCartCount();
                        },
                        child: Center(
                          child: Icon(
                            Icons.shopping_cart_outlined,
                            size: 22,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.shade600, Colors.red.shade800],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.6),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(21),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                      _fetchNotificationCount();
                    },
                    child: Center(
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 22,
                        color: kPrimaryColor,
                      ),
                    ),
                  ),
                ),
              ),
              if (_notificationCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade500, Colors.orange.shade700],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.6),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _notificationCount > 99 ? '99+' : '$_notificationCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(21),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
                child: Center(
                  child: Icon(
                    Icons.headset_mic_outlined,
                    size: 22,
                    color: kPrimaryColor,
                  ),
                ),
              ),
            ),
          ),
        ),
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
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const DeliveryAddressWidget(),
                const SizedBox(height: 16),
                _buildPremiumBannerCarousel(),
                const SizedBox(height: 16),
                _buildPremiumCategoriesSection(),
                const SizedBox(height: 16),
                _buildPremiumContactSection(),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withOpacity(0.2),
                      kPrimaryColor.withOpacity(0.1)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.category_outlined, color: kPrimaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Our Categories',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _isCategoriesLoading
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: CircularProgressIndicator(color: kPrimaryColor, strokeWidth: 3),
            ),
          )
              : _categories.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No categories available',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ),
          )
              : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.80, // Back to original ratio to keep card dimensions
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

              return _buildPremiumCategoryCard(
                title,
                imageUrl,
                isNetwork: true,
                label: feature['label'],
              );
            },
          ),
        ),
      ],
    );
  }



  Widget _buildPremiumCategoryCard(String title, String imagePath,
      {bool isNetwork = false, String? label}) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrdersScreen(category: title)),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6), // Reduced from 12
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image Container with rounded corners
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: isNetwork
                          ? CachedNetworkImage(
                        imageUrl: imagePath,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kPrimaryColor,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 30,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                          : Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8), // Reduced from 12

                // Text Content with proper spacing
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Reduced padding
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14, // Slightly smaller
                      color: Colors.black87,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            // Label Tag - Positioned top right
            if (label != null && label.isNotEmpty)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: label.toLowerCase() == 'popular'
                          ? [Colors.orange.shade500, Colors.orange.shade700]
                          : label.toLowerCase() == 'new'
                          ? [Colors.green.shade500, Colors.green.shade700]
                          : [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (label.toLowerCase() == 'popular'
                            ? Colors.orange
                            : label.toLowerCase() == 'new'
                            ? Colors.green
                            : kPrimaryColor)
                            .withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBannerCarousel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        height: 200,
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
                      borderRadius: BorderRadius.circular(20),
                      child: isVideo
                          ? VideoPlayer(_videoControllers[index]!)
                          : CachedNetworkImage(
                        imageUrl: _carouselImages[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade100,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: kPrimaryColor,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _carouselImages.length,
                    (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentBannerIndex == index ? 32 : 8,
                  decoration: BoxDecoration(
                    gradient: _currentBannerIndex == index
                        ? LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.7)])
                        : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade300]),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: _currentBannerIndex == index
                        ? [
                      BoxShadow(
                        color: kPrimaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                        : [],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumContactSection() {
    if (_contacts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                    colors: [kPrimaryColor.withOpacity(0.2), kPrimaryColor.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.connect_without_contact, color: kPrimaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Connect With Us',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _contacts.map((contact) => _buildPremiumContactTile(contact)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumContactTile(Map<String, dynamic> contact) {
    final key = contact['key']?.toString().toLowerCase() ?? '';
    final color = _getPremiumColor(key);
    final icon = _getPremiumIcon(key);

    return GestureDetector(
      onTap: () => _launchUrl(contact['link']),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.1),
                      color.withOpacity(0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            contact['label'] ?? '',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _getPremiumIcon(String key) {
    switch (key) {
      case 'website':
        return Icons.language_rounded;
      case 'instagram':
        return Icons.camera_alt_rounded;
      case 'facebook':
        return Icons.facebook_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  Color _getPremiumColor(String key) {
    switch (key) {
      case 'instagram':
        return const Color(0xFFE1306C);
      case 'facebook':
        return const Color(0xFF1877f3);
      case 'website':
        return const Color(0xFF6366f1);
      default:
        return kPrimaryColor;
    }
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
}