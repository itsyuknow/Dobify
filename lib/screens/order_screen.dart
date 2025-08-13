// Imports
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import 'colors.dart';
import 'product_details_screen.dart';
import '../widgets/custom_bottom_nav.dart';
import '../screens/cart_screen.dart';

class OrdersScreen extends StatefulWidget {
  final String? category;
  const OrdersScreen({Key? key, this.category}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final supabase = Supabase.instance.client;
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';

  final List<Map<String, dynamic>> _products = [];
  final Map<String, int> _productQuantities = {};
  final Map<String, AnimationController> _controllers = {};
  final Map<String, AnimationController> _qtyAnimControllers = {};
  final Map<String, bool> _addedStatus = {};
  final ScrollController _scrollController = ScrollController();

  String? _backgroundImageUrl;
  bool _isInitialLoadDone = false;
  // ✅ NEW: Loading and empty states
  bool _isLoading = false;

  // ✅ ENHANCED: Premium smooth animation controllers
  late AnimationController _floatingCartController;
  late AnimationController _fadeController;
  late AnimationController _smoothFloatController;
  late AnimationController _breathingController;
  late AnimationController _bounceController;
  late AnimationController _clearZoneController;
  late AnimationController _dragHintController;
  late AnimationController _continuousFloatController;

  late Animation<double> _floatingCartScale;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _floatingCartSlide;
  late Animation<double> _smoothFloatAnimation;
  late Animation<double> _breathingAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _clearZoneScale;
  late Animation<double> _clearZoneOpacity;
  late Animation<double> _dragHintOpacity;
  late Animation<double> _continuousFloatAnimation;
  late Animation<double> _continuousScaleAnimation;

  // ✅ NEW: In-memory cache flags
  bool _hasFetchedProducts = false;
  List<Map<String, dynamic>> _cachedProducts = [];
  List<String> _cachedCategories = ['All'];

  // ✅ FIXED: Floating cart state management
  Offset _fabOffset = const Offset(300, 400);
  bool _isDragging = false;
  bool _showClearZone = false;
  bool _isNearClearZone = false;
  bool _showDragHint = false;

  // ✅ NEW: Track clear zone position globally
  Offset _clearZoneCenter = Offset.zero;

  @override
  void initState() {
    super.initState();
    _initializeSmoothAnimations();

    // ✅ FIXED: Always fetch fresh data on init
    _selectedCategory = widget.category ?? 'All';
    _fetchBackgroundImage();
    _testDatabaseConnection(); // Add test first
    _fetchCategoriesAndProducts();
    _fetchCartData();

    // Show drag hint after 3 seconds if cart has items, for longer duration
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && cartCountNotifier.value > 0) {
        _showDragHintTemporarily();
      }
    });
  }

  // ✅ NEW: Test database connection
  Future<void> _testDatabaseConnection() async {
    try {
      debugPrint('🔍 Testing database connection...');

      // Test categories
      final categoriesTest = await supabase.from('categories').select('count').single();
      debugPrint('📊 Categories test: $categoriesTest');

      // Test products
      final productsTest = await supabase.from('products').select('count').single();
      debugPrint('📊 Products test: $productsTest');

      // Test simple products query
      final simpleProducts = await supabase
          .from('products')
          .select('product_name, product_price')
          .eq('is_enabled', true)
          .limit(3);
      debugPrint('📊 Simple products: $simpleProducts');

    } catch (e) {
      debugPrint('❌ Database connection test failed: $e');
    }
  }

  // ✅ FIXED: Initialize FAB position with proper footer boundaries
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenSize = MediaQuery.of(context).size;
    final bottomNavHeight = kBottomNavigationBarHeight;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final maxBottom = screenSize.height - bottomNavHeight - safeAreaBottom - 70;

    _fabOffset = Offset(
        screenSize.width - 80,
        (maxBottom * 0.7).clamp(100.0, maxBottom) // Ensure it's within bounds
    );
  }

  // ✅ SMOOTH: Enhanced premium animations initialization
  void _initializeSmoothAnimations() {
    // ✅ SMOOTH: Longer durations for smoother motion
    _floatingCartController = AnimationController(
      duration: const Duration(milliseconds: 1200), // ✅ Increased for smoothness
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // ✅ SMOOTH: Much longer for ultra-smooth sine wave motion
    _smoothFloatController = AnimationController(
      duration: const Duration(milliseconds: 8000), // ✅ Increased for ultra-smooth motion
      vsync: this,
    );

    // ✅ SMOOTH: Longer breathing for smoother scale
    _breathingController = AnimationController(
      duration: const Duration(milliseconds: 5000), // ✅ Increased for smoother breathing
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 600), // ✅ Slightly faster bounce
      vsync: this,
    );

    _clearZoneController = AnimationController(
      duration: const Duration(milliseconds: 300), // ✅ Faster clear zone response
      vsync: this,
    );

    _dragHintController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // ✅ SMOOTH: Ultra-slow for natural floating motion
    _continuousFloatController = AnimationController(
      duration: const Duration(milliseconds: 10000), // ✅ Much longer for smoother motion
      vsync: this,
    );

    // ✅ SMOOTH: Enhanced animations with ultra-smooth curves
    _floatingCartScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _floatingCartController,
        curve: Curves.easeOutCubic, // ✅ Smoother than elastic
      ),
    );

    _floatingCartSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _floatingCartController,
      curve: Curves.easeOutCubic, // ✅ Ultra-smooth curve
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOutCubic,
      ),
    );

    // ✅ SMOOTH: Smaller range for subtle floating motion
    _smoothFloatAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(
        parent: _smoothFloatController,
        curve: Curves.easeInOutSine, // ✅ Perfect sine wave
      ),
    );

    // ✅ SMOOTH: More subtle breathing scale
    _breathingAnimation = Tween<double>(begin: 0.99, end: 1.01).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOutSine,
      ),
    );

    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeOutBack, // ✅ Smoother bounce
      ),
    );

    // ✅ SMOOTH: Gentle color transition
    _colorAnimation = ColorTween(
      begin: kPrimaryColor,
      end: kPrimaryColor.withOpacity(0.9),
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));

    _clearZoneScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _clearZoneController,
        curve: Curves.easeOutBack, // ✅ Smoother scale
      ),
    );

    _clearZoneOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _clearZoneController,
        curve: Curves.easeOut,
      ),
    );

    _dragHintOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _dragHintController,
        curve: Curves.easeInOut,
      ),
    );

    // ✅ SMOOTH: Ultra-subtle continuous floating animations
    _continuousFloatAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _continuousFloatController,
        curve: Curves.easeInOutSine,
      ),
    );

    _continuousScaleAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(
        parent: _continuousFloatController,
        curve: Curves.easeInOutSine,
      ),
    );

    // ✅ SMOOTH: Start animations
    _fadeController.forward();

    // ✅ SMOOTH: Continuous repeating animations with ultra-smooth sine waves
    _smoothFloatController.repeat(reverse: true);
    _breathingController.repeat(reverse: true);
    _continuousFloatController.repeat(reverse: true);
  }

  // ✅ NEW: Show drag hint temporarily with longer duration
  void _showDragHintTemporarily() {
    if (!mounted) return;
    setState(() {
      _showDragHint = true;
    });
    _dragHintController.forward();

    Future.delayed(const Duration(seconds: 5), () { // Increased from 3 to 5 seconds
      if (mounted) {
        _dragHintController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _showDragHint = false;
            });
          }
        });
      }
    });
  }

  Future<void> _fetchBackgroundImage() async {
    try {
      final result = await supabase
          .from('ui_assets')
          .select('background_url')
          .eq('key', 'home_bg')
          .maybeSingle();

      if (mounted && result != null && result['background_url'] != null) {
        setState(() {
          _backgroundImageUrl = result['background_url'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error fetching background image: $e');
      }
    }
  }

  Future<void> _fetchCategoriesAndProducts() async {
    // ✅ FIXED: Set loading state
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      debugPrint('🔄 Fetching products from database...');

      // ✅ FIXED: Use the correct Supabase query syntax for your data
      final response = await supabase
          .from('products')
          .select('id, product_name, product_price, image_url, category_id, is_enabled, created_at, categories(name)')
          .eq('is_enabled', true)
          .order('created_at', ascending: false);

      debugPrint('📦 Raw products response: $response');
      debugPrint('📦 Products count: ${response.length}');

      if (response.isEmpty) {
        debugPrint('⚠️ No products returned from query');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final productList = List<Map<String, dynamic>>.from(response);
      _products.clear();
      _products.addAll(productList);

      debugPrint('✅ Products loaded: ${_products.length}');
      for (var product in _products) {
        debugPrint('Product: ${product['product_name']} - ₹${product['product_price']} - Category: ${product['categories']?['name'] ?? 'No Category'}');
      }

      // ✅ FIXED: Extract categories from products (Male, Female, Boys, Girls, Essential)
      final uniqueCategories = _products
          .map((p) => p['categories']?['name']?.toString())
          .where((name) => name != null && name.isNotEmpty)
          .cast<String>() // ✅ FIXED: Cast to String to fix type error
          .toSet()
          .toList();

      _categories = ['All', ...uniqueCategories];
      debugPrint('📂 Categories: $_categories');

      // ✅ Save to cache
      _cachedProducts = List<Map<String, dynamic>>.from(_products);
      _cachedCategories = List<String>.from(_categories);
      _hasFetchedProducts = true;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      // Auto-scroll to selected category
      if (widget.category != null && widget.category != 'All') {
        final index = _categories.indexOf(widget.category!);
        if (index != -1) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              index * 120.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching products with categories: $e');

      // ✅ FIXED: Fallback - fetch products without categories join
      try {
        debugPrint('🔄 Trying fallback query without categories join...');
        final fallbackResponse = await supabase
            .from('products')
            .select('*')
            .eq('is_enabled', true)
            .order('created_at', ascending: false);

        debugPrint('📦 Fallback response: ${fallbackResponse.length} products');

        if (fallbackResponse.isNotEmpty) {
          final productList = List<Map<String, dynamic>>.from(fallbackResponse);
          _products.clear();
          _products.addAll(productList);

          // ✅ FIXED: Fetch categories separately and map them
          final categoriesResponse = await supabase
              .from('categories')
              .select('id, name')
              .eq('is_active', true);

          final categoriesMap = <String, String>{};
          for (var category in categoriesResponse) {
            categoriesMap[category['id']] = category['name'];
          }

          // Add categories object to each product
          for (var product in _products) {
            final categoryId = product['category_id'];
            final categoryName = categoriesMap[categoryId] ?? 'General';
            product['categories'] = {'name': categoryName};
          }

          final uniqueCategories = _products
              .map((p) => p['categories']?['name']?.toString())
              .where((name) => name != null && name.isNotEmpty)
              .cast<String>() // ✅ FIXED: Cast to String to fix type error
              .toSet()
              .toList();

          _categories = ['All', ...uniqueCategories];
          _cachedProducts = List<Map<String, dynamic>>.from(_products);
          _cachedCategories = List<String>.from(_categories);
          _hasFetchedProducts = true;

          debugPrint('✅ Fallback successful: ${_products.length} products with categories mapped');
          debugPrint('📂 Fallback categories: $_categories');
        }

      } catch (fallbackError) {
        debugPrint('❌ Fallback query also failed: $fallbackError');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ REMOVED: Sample products function since you have real data

  List<Map<String, dynamic>> _getFilteredProducts() {
    if (_selectedCategory == 'All') return _products;
    return _products.where((p) => p['categories']?['name'] == _selectedCategory).toList();
  }

  // ✅ FIXED: Cart data fetching
  Future<void> _fetchCartData() async {
    debugPrint('🔄 Fetching cart data...');
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No user found');
      return;
    }

    try {
      final data = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id);

      debugPrint('📦 Cart data fetched: ${data.length} items');

      // Clear and rebuild quantities
      _productQuantities.clear();
      for (final item in data) {
        final productName = item['product_name'] as String;
        final quantity = item['product_quantity'] as int? ?? 0;
        _productQuantities[productName] = (_productQuantities[productName] ?? 0) + quantity;
      }

      // Update global cart count
      final totalCount = _productQuantities.values.fold<int>(0, (sum, qty) => sum + qty);
      cartCountNotifier.value = totalCount;

      debugPrint('✅ Product quantities: $_productQuantities');
      debugPrint('✅ Total cart count: $totalCount');

      // Animate floating cart
      if (totalCount > 0) {
        _floatingCartController.forward();
        _bounceController.forward(from: 0.0);
      } else {
        _floatingCartController.reverse();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error fetching cart: $e');
    }
  }

  // ✅ FIXED: Update cart quantity
  Future<void> _updateCartQty(Map<String, dynamic> product, int delta) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final name = product['product_name'];
    debugPrint('🔄 Updating cart quantity for $name by $delta');

    try {
      final existingItems = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id)
          .eq('product_name', name);

      if (existingItems.isEmpty) {
        debugPrint('❌ No existing cart items found for $name');
        return;
      }

      final currentQty = _productQuantities[name] ?? 0;
      final newQty = currentQty + delta;

      debugPrint('📊 Current: $currentQty, Delta: $delta, New: $newQty');

      if (newQty <= 0) {
        for (final item in existingItems) {
          await supabase
              .from('cart')
              .delete()
              .eq('id', item['id']);
        }
        _productQuantities.remove(name);
        debugPrint('🗑️ Removed all $name items from cart');
      } else {
        final firstItem = existingItems.first;
        final productPrice = (firstItem['product_price'] as num?)?.toDouble() ?? 0.0;
        final servicePrice = (firstItem['service_price'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = (productPrice + servicePrice) * newQty;

        await supabase.from('cart').update({
          'product_quantity': newQty,
          'total_price': totalPrice,
        }).eq('id', firstItem['id']);

        for (int i = 1; i < existingItems.length; i++) {
          await supabase
              .from('cart')
              .delete()
              .eq('id', existingItems[i]['id']);
        }

        _productQuantities[name] = newQty;
        debugPrint('✅ Updated $name quantity to $newQty');
      }

      await _fetchCartData();
      _triggerAnimations(name);

    } catch (e) {
      debugPrint('❌ Error updating cart quantity: $e');
    }
  }

  // ✅ FIXED: Add product to cart with service
  Future<void> _addToCartWithService(Map<String, dynamic> product, String service, int servicePrice) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No user found');
      return;
    }

    final name = product['product_name'];
    final basePrice = (product['product_price'] as num?)?.toDouble() ?? 0.0;
    final image = product['image_url'] ?? '';
    final category = product['categories']?['name'] ?? '';
    final totalPrice = basePrice + servicePrice;

    debugPrint('🔄 Adding $name to cart with $service service (₹$servicePrice)');

    try {
      if (mounted) {
        setState(() {
          _addedStatus[name] = true;
        });
      }

      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_name', name)
          .eq('service_type', service)
          .maybeSingle();

      if (existing != null) {
        final newQty = (existing['product_quantity'] as int) + 1;
        final newTotalPrice = (basePrice + servicePrice) * newQty;

        await supabase.from('cart').update({
          'product_quantity': newQty,
          'total_price': newTotalPrice,
        }).eq('id', existing['id']);

        debugPrint('✅ Updated existing cart item: $name, qty: $newQty');
      } else {
        await supabase.from('cart').insert({
          'user_id': user.id,
          'product_name': name,
          'product_image': image,
          'product_price': basePrice,
          'service_type': service,
          'service_price': servicePrice.toDouble(),
          'product_quantity': 1,
          'total_price': totalPrice,
          'category': category,
        });

        debugPrint('✅ Added new cart item: $name');
      }

      _productQuantities[name] = (_productQuantities[name] ?? 0) + 1;
      _triggerAnimations(name);

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _addedStatus[name] = false;
        });
      }

      await _fetchCartData();

    } catch (e) {
      debugPrint('❌ Error adding to cart: $e');
      if (mounted) {
        setState(() {
          _addedStatus[name] = false;
        });
      }
    }
  }

  void _triggerAnimations(String productName) {
    _controllers[productName]?.forward(from: 0.0);
    _qtyAnimControllers[productName]?.forward(from: 0.9);
  }

  IconData _getServiceIcon(String? iconString) {
    switch (iconString) {
      case 'cloud':
        return Icons.cloud;
      case 'flash_on':
        return Icons.flash_on;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'water_drop':
        return Icons.water_drop;
      case 'bolt':
        return Icons.bolt;
      case 'local_laundry_service':
        return Icons.local_laundry_service;
      default:
        return Icons.miscellaneous_services; // fallback icon
    }
  }

  Future<void> _showServiceSelectionPopup(Map<String, dynamic> product) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to add items to cart')),
        );
      }
      return;
    }

    debugPrint('🔄 Loading services...');

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      final response = await supabase
          .from('services')
          .select('*')
          .eq('is_active', true)
          .order('sort_order');

      final services = List<Map<String, dynamic>>.from(response);

      if (mounted) Navigator.pop(context);

      if (services.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No services available')),
          );
        }
        return;
      }

      debugPrint('✅ Services loaded: ${services.length}');

      final basePrice = (product['product_price'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxWidth: 300, maxHeight: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Choose Service',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select service for ${product['product_name']}',
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: services.length,
                        itemBuilder: (context, index) {
                          final service = services[index];
                          final name = service['name'] ?? '';
                          final price = service['price'] ?? 0;
                          final description = service['service_description'] ?? '';
                          final tag = service['tag'] ?? '';
                          final iconName = service['icon_name'];
                          final totalPrice = basePrice + price;

                          return GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              await _addToCartWithService(product, name, price);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200, width: 1),
                              ),
                              child: Stack(
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Icon
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: kPrimaryColor.withOpacity(0.1),
                                        ),
                                        child: Icon(
                                          _getServiceIcon(iconName),
                                          size: 20,
                                          color: kPrimaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Name & Description
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              description,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Tag and Price at Top-Right
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (tag.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              tag,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${totalPrice.toInt()}',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: kPrimaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        debugPrint('❌ Error loading services: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load services: $e')),
        );
      }
    }
  }

  // ✅ FIXED: Clear cart with proper state management
  Future<void> _clearCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Clear from database
      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      // ✅ FIXED: Clear all local state properly
      _productQuantities.clear();
      cartCountNotifier.value = 0;

      // Force rebuild of all animation controllers
      for (final controller in _qtyAnimControllers.values) {
        controller.reset();
      }

      // Reset floating cart
      _floatingCartController.reverse();

      // ✅ FIXED: Force complete UI refresh
      if (mounted) {
        setState(() {
          _showClearZone = false;
          _isNearClearZone = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Cart cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cart: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ✅ COMPLETELY REWRITTEN: Simple and accurate clear zone detection
  bool _isCartNearClearZone() {
    // Clear zone position - center of screen horizontally, lower third vertically
    final screenSize = MediaQuery.of(context).size;
    final clearZoneLeft = screenSize.width * 0.5 - 40;
    final clearZoneTop = screenSize.height * 0.65; // Position in lower third of screen
    final clearZoneCenter = Offset(clearZoneLeft + 40, clearZoneTop + 40);

    // Cart center (60x60 widget)
    final cartCenter = Offset(_fabOffset.dx + 30, _fabOffset.dy + 30);

    // Calculate distance
    final distance = (cartCenter - clearZoneCenter).distance;

    // Debug output
    debugPrint('🎯 Cart: $cartCenter, Clear Zone: $clearZoneCenter, Distance: $distance');

    // Return true if within 80 pixels
    return distance < 80;
  }

  // ✅ SMOOTH FLOATING CART - Enhanced with multiple smooth animations
  Widget _buildFloatingCart() {
    return ValueListenableBuilder<int>(
      valueListenable: cartCountNotifier,
      builder: (context, count, child) {
        if (count == 0) {
          return const SizedBox.shrink();
        }

        final screenSize = MediaQuery.of(context).size;
        final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;

        // ✅ FIXED: Proper bottom boundary calculation to stay above footer
        final bottomNavHeight = kBottomNavigationBarHeight;
        final safeAreaBottom = MediaQuery.of(context).padding.bottom;
        final maxBottom = screenSize.height - bottomNavHeight - safeAreaBottom - 70; // Proper margin above footer
        final minTop = appBarHeight + 20;

        return AnimatedBuilder(
          animation: Listenable.merge([
            _floatingCartController,
            _smoothFloatController,
            _breathingController,
            _bounceController,
            _clearZoneController,
            _dragHintController,
            _continuousFloatController,
          ]),
          builder: (context, child) {
            return Stack(
              children: [
                // ✅ Clear Zone positioned in lower third of screen
                if (_showClearZone)
                  Positioned(
                    left: screenSize.width * 0.5 - 40, // Center horizontally
                    top: screenSize.height * 0.65, // Lower third of screen
                    child: ScaleTransition(
                      scale: _clearZoneScale,
                      child: FadeTransition(
                        opacity: _clearZoneOpacity,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                (_isNearClearZone ? Colors.red.shade400 : Colors.red.shade500).withOpacity(0.4),
                                (_isNearClearZone ? Colors.red.shade600 : Colors.red.shade700).withOpacity(0.6),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.red.withOpacity(_isNearClearZone ? 0.9 : 0.6),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(_isNearClearZone ? 0.6 : 0.4),
                                blurRadius: _isNearClearZone ? 35 : 25,
                                spreadRadius: _isNearClearZone ? 8 : 4,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Animated pulse effect when near
                              if (_isNearClearZone)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.8),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),

                              // Delete icon
                              Center(
                                child: Transform.scale(
                                  scale: _isNearClearZone ? 1.4 : 1.0,
                                  child: Icon(
                                    Icons.delete_forever,
                                    color: Colors.white,
                                    size: 42,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // ✅ ENHANCED: Improved drag hint with better positioning and text
                if (_showDragHint)
                  Positioned(
                    left: _fabOffset.dx > screenSize.width / 2 ? _fabOffset.dx - 140 : _fabOffset.dx + 70,
                    top: _fabOffset.dy - 10,
                    child: FadeTransition(
                      opacity: _dragHintOpacity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swipe,
                              color: Colors.white.withOpacity(0.9),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Drag to clear cart',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Drop on 🗑️ to delete all items',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ✅ COMPLETELY REWRITTEN: Draggable Cart with simplified positioning
                Positioned(
                  left: _isDragging
                      ? _fabOffset.dx.clamp(0, screenSize.width - 60)
                      : (_fabOffset.dx + _continuousFloatAnimation.value).clamp(0, screenSize.width - 60),
                  top: _isDragging
                      ? _fabOffset.dy.clamp(minTop, maxBottom)
                      : (_fabOffset.dy + _smoothFloatAnimation.value).clamp(minTop, maxBottom),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CartScreen()),
                      ).then((_) => _fetchCartData());
                    },
                    onPanStart: (details) {
                      setState(() {
                        _isDragging = true;
                        _showClearZone = true;
                        _showDragHint = false;
                      });
                      _clearZoneController.forward();
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        // Update position to follow finger
                        _fabOffset = Offset(
                          (_fabOffset.dx + details.delta.dx).clamp(0, screenSize.width - 60),
                          (_fabOffset.dy + details.delta.dy).clamp(minTop, maxBottom),
                        );

                        // Check if near clear zone
                        _isNearClearZone = _isCartNearClearZone();
                      });
                    },
                    onPanEnd: (details) {
                      debugPrint('🎯 PAN END: Cart at ${_fabOffset}, Near clear zone: $_isNearClearZone');

                      // Clear cart if in clear zone
                      if (_isNearClearZone) {
                        debugPrint('✅ CLEARING CART - Cart was in clear zone!');
                        _clearCart();
                      } else {
                        debugPrint('❌ NOT CLEARING - Cart not in clear zone');
                      }

                      setState(() {
                        _isDragging = false;
                        _isNearClearZone = false;

                        // Snap to nearest side
                        final targetX = _fabOffset.dx < screenSize.width / 2 ? 20.0 : screenSize.width - 80.0;
                        _fabOffset = Offset(
                          targetX,
                          _fabOffset.dy.clamp(minTop, maxBottom),
                        );
                      });

                      _clearZoneController.reverse();

                      // Hide clear zone after animation
                      Future.delayed(const Duration(milliseconds: 400), () {
                        if (mounted) {
                          setState(() => _showClearZone = false);
                        }
                      });
                    },
                    child: SlideTransition(
                      position: _floatingCartSlide,
                      child: ScaleTransition(
                        scale: _floatingCartScale,
                        child: Transform.scale(
                          scale: _isDragging
                              ? 1.1
                              : (_bounceAnimation.value * _breathingAnimation.value * _continuousScaleAnimation.value),
                          child: Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _isNearClearZone
                                      ? Colors.red.shade400
                                      : (_colorAnimation.value ?? kPrimaryColor),
                                  _isNearClearZone
                                      ? Colors.red.shade600
                                      : (_colorAnimation.value ?? kPrimaryColor).withOpacity(0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isNearClearZone
                                      ? Colors.red.shade400
                                      : (_colorAnimation.value ?? kPrimaryColor)).withOpacity(0.5),
                                  blurRadius: _isDragging ? 25 : 15,
                                  spreadRadius: _isDragging ? 5 : 2,
                                  offset: Offset(0, _isDragging ? 10 : 6),
                                ),
                                if (_isDragging)
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: -2,
                                    offset: const Offset(-2, -2),
                                  ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Cart Icon
                                Center(
                                  child: Transform.scale(
                                    scale: _isDragging ? 1.0 : _breathingAnimation.value,
                                    child: Icon(
                                      _isNearClearZone ? Icons.delete : Icons.shopping_bag_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),

                                // Count badge
                                if (!_isNearClearZone)
                                  Positioned(
                                    top: -8,
                                    right: -8,
                                    child: Transform.scale(
                                      scale: _isDragging ? 0.9 : _breathingAnimation.value,
                                      child: Container(
                                        height: 28,
                                        width: 28,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white,
                                              Colors.grey.shade100,
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: (_colorAnimation.value ?? kPrimaryColor).withOpacity(0.3),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            count > 99 ? '99+' : '$count',
                                            style: TextStyle(
                                              fontSize: count > 99 ? 9 : 12,
                                              fontWeight: FontWeight.bold,
                                              color: _colorAnimation.value ?? kPrimaryColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Drag indicator ring
                                if (_isDragging)
                                  Positioned.fill(
                                    child: Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.5),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _qtyAnimControllers.values) {
      c.dispose();
    }
    _floatingCartController.dispose();
    _fadeController.dispose();
    _smoothFloatController.dispose();
    _breathingController.dispose();
    _bounceController.dispose();
    _clearZoneController.dispose();
    _dragHintController.dispose();
    _continuousFloatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final products = _getFilteredProducts();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: _buildPremiumAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Background
            if (_backgroundImageUrl != null)
              Positioned.fill(
                child: Image.network(
                  _backgroundImageUrl!,
                  fit: BoxFit.cover,
                  color: Colors.white.withOpacity(0.15),
                  colorBlendMode: BlendMode.srcATop,
                ),
              ),

            // Main content
            Column(
              children: [
                const SizedBox(height: 12),
                _buildPremiumCategoryTabs(),
                const SizedBox(height: 16),
                Expanded(child: _buildContent()),
              ],
            ),

            // ✅ SMOOTH: Premium Floating cart with enhanced animations
            _buildFloatingCart(),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
    );
  }

  // ✅ NEW: Content builder with states
  Widget _buildContent() {
    final products = _getFilteredProducts();

    // ✅ Loading state
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading products...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Empty state
    if (products.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedCategory == 'All'
                  ? 'No products available'
                  : 'No products in "$_selectedCategory" category',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _hasFetchedProducts = false;
                _cachedProducts.clear();
                _cachedCategories = ['All'];
                _fetchCategoriesAndProducts();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                'Reload Products',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Normal grid
    return _buildPremiumProductGrid(products);
  }

  // ✅ Premium AppBar
  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor.withOpacity(0.95), kPrimaryColor.withOpacity(0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ironXpress',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _selectedCategory == 'All' ? 'All Categories' : _selectedCategory,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      // Removed the debug refresh button from actions
      actions: [],
    );
  }

  // ✅ Premium category tabs
  Widget _buildPremiumCategoryTabs() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              constraints: const BoxConstraints(minWidth: 80),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                  colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                )
                    : null,
                color: isSelected ? null : Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? kPrimaryColor.withOpacity(0.3)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: isSelected ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  cat,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ✅ Product grid - REMOVED PRICE DISPLAY
  Widget _buildPremiumProductGrid(List<Map<String, dynamic>> products) {
    return GridView.builder(
      itemCount: products.length,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (ctx, idx) {
        final item = products[idx];
        final name = item['product_name'];
        final qty = _productQuantities[name] ?? 0;

        // Initialize animation controllers
        _controllers[name] ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 150),
          lowerBound: 0.95,
          upperBound: 1.05,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _controllers[name]?.reverse();
          }
        });

        _qtyAnimControllers[name] ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
          lowerBound: 0.9,
          upperBound: 1.1,
        );

        return ScaleTransition(
          scale: _controllers[name]!,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetailsScreen(productId: item['id']),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item['image_url'] ?? '',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.image_outlined,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Product details
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product name
                        Text(
                          name ?? 'Unknown Product',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16), // ✅ CHANGED: Increased spacing since price is removed

                        // Button section
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: _buildProductButton(item, name),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ FIXED: Product button with proper state management
  Widget _buildProductButton(Map<String, dynamic> item, String name) {
    // Show "Added!" state
    if (_addedStatus[name] == true) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                'Added!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show "Add" button
    return ElevatedButton(
      onPressed: () {
        debugPrint('🔘 Add button pressed for: $name');
        _showServiceSelectionPopup(item);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        padding: EdgeInsets.zero,
      ),
      child: const Text(
        'Add',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}