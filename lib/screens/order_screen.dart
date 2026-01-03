// Imports
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import 'colors.dart';
import 'product_details_screen.dart';
import '../widgets/custom_bottom_nav.dart';
import '../screens/cart_screen.dart';
import 'dart:convert'; // <-- needed for jsonDecode
import 'package:flutter/foundation.dart' show kIsWeb;



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
  List<String> _categories = ['All']; // tabs
  String _selectedCategory = 'All';

  final List<Map<String, dynamic>> _products = [];

  // ✅ CHANGED: Key by productId instead of productName
  final Map<String, int> _productQuantities = {};
  final Map<String, AnimationController> _controllers = {};
  final Map<String, AnimationController> _qtyAnimControllers = {};
  final Map<String, bool> _addedStatus = {};

  final ScrollController _scrollController = ScrollController();

  String? _backgroundImageUrl;
  bool _isInitialLoadDone = false;
  bool _isLoading = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchActive = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchSuggestions = [];
  bool _showSearchSuggestions = false;
  late AnimationController _searchAnimationController;
  late Animation<double> _searchSlideAnimation;
  late Animation<double> _searchFadeAnimation;

  // Animation controllers (unchanged)
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

  bool _hasFetchedProducts = false;
  List<Map<String, dynamic>> _cachedProducts = [];
  List<String> _cachedCategories = ['All'];

  Offset _fabOffset = const Offset(300, 400);
  bool _isDragging = false;
  bool _showClearZone = false;
  bool _isNearClearZone = false;
  bool _showDragHint = false;

  Offset _clearZoneCenter = Offset.zero;

  // Add this near your other fields
  final Map<String, GlobalKey> _categoryKeys = {};

// Add this helper method in _OrdersScreenState
  void _centerSelectedCategoryByName(String name) {
    final key = _categoryKeys[name];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5, // center in the viewport
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }



  Future<void> _fetchCategoriesAndProducts() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      // ✅ UPDATED: Added recommended_service_id to the query
      final response = await supabase
          .from('products')
          .select(
          'id, product_name,image_url, category_id, is_enabled, created_at, sort_order,recommended_service_id, services_provided, categories(name)'
      )

          .eq('is_enabled', true)
          .order('sort_order', ascending: true) // ✅ Primary sort by sort_order
          .order('product_name', ascending: true); // ✅ Secondary sort by name

      final productList = List<Map<String, dynamic>>.from(response);
      _products
        ..clear()
        ..addAll(productList);

      if (_categories.length == 1) {
        final unique = _products
            .map((p) => p['categories']?['name']?.toString())
            .where((name) => name != null && name!.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList()
          ..sort();
        _categories = ['All', ...unique];
      }

      _cachedProducts = List<Map<String, dynamic>>.from(_products);
      _cachedCategories = List<String>.from(_categories);
      _hasFetchedProducts = true;
    } catch (e) {
      try {
        // ✅ UPDATED: Fallback query also includes recommended_service_id
        final fallbackResponse = await supabase
            .from('products')
            .select('*')
            .eq('is_enabled', true)
            .order('sort_order', ascending: true)
            .order('created_at', ascending: false);

        if (fallbackResponse.isNotEmpty) {
          final productList = List<Map<String, dynamic>>.from(fallbackResponse);
          _products
            ..clear()
            ..addAll(productList);

          final categoriesResponse = await supabase
              .from('categories')
              .select('id, name')
              .eq('is_active', true)
              .order('sort_order', ascending: true); // ✅ Also sort categories

          final categoriesMap = <String, String>{};
          for (var category in categoriesResponse) {
            categoriesMap[category['id']] = category['name'];
          }
          for (var product in _products) {
            final categoryId = product['category_id'];
            final categoryName = categoriesMap[categoryId] ?? 'General';
            product['categories'] = {'name': categoryName};
          }

          if (_categories.length == 1) {
            final orderedNames =
            List<Map<String, dynamic>>.from(categoriesResponse)
                .map((e) => (e['name'] as String?)?.trim())
                .where((e) => e != null && e!.isNotEmpty)
                .cast<String>()
                .toList();
            _categories = ['All', ...orderedNames];
          }

          _cachedProducts = List<Map<String, dynamic>>.from(_products);
          _cachedCategories = List<String>.from(_categories);
          _hasFetchedProducts = true;
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isLoading = false);

    // ✅ NEW: Center the initial category chip using the GlobalKey + ensureVisible approach
    if (widget.category != null &&
        widget.category!.trim().isNotEmpty &&
        widget.category != 'All') {
      final catName = widget.category!;
      if (_categories.contains(catName)) {
        if (mounted) setState(() => _selectedCategory = catName);
        // Wait for the next frame so that the tabs are built and keys attached,
        // then center the selected chip.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerSelectedCategoryByName(catName);
        });
      }
    }
  }


  Future<void> _loadCategoriesForTabs() async {
    try {
      // ✅ UPDATED: Added sort_order to category loading
      final rows = await supabase
          .from('categories')
          .select('name,is_active')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final names = List<Map<String, dynamic>>.from(rows)
          .map((e) => (e['name'] as String?)?.trim())
          .where((e) => e != null && e!.isNotEmpty)
          .cast<String>()
          .toList();

      if (mounted && names.isNotEmpty) {
        setState(() {
          _categories = ['All', ...names];
        });
      }
    } catch (_) {}
  }

  // ✅ UPDATED: Search + Category filter with sorting maintained
  List<Map<String, dynamic>> _getFilteredProducts() {
    List<Map<String, dynamic>> filteredProducts;

    if (_selectedCategory == 'All') {
      filteredProducts = _products;
    } else {
      filteredProducts = _products
          .where((p) => p['categories']?['name'] == _selectedCategory)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredProducts = filteredProducts
          .where((product) =>
          product['product_name'].toString().toLowerCase().contains(query))
          .toList();
    }

    // ✅ Maintain sorting even after filtering
    filteredProducts.sort((a, b) {
      final aOrder = (a['sort_order'] as int?) ?? 999;
      final bOrder = (b['sort_order'] as int?) ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);

      final aName = (a['product_name'] as String?) ?? '';
      final bName = (b['product_name'] as String?) ?? '';
      return aName.compareTo(bName);
    });

    return filteredProducts;
  }


  Widget _buildPremiumProductGrid(BuildContext context, List<Map<String, dynamic>> products) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemBuilder: (ctx, idx) {
        final item = products[idx];
        final productId = (item['id'] ?? '').toString();
        final name = item['product_name'];
        // ✅ REMOVED: tag variable and usage
        final qty = _productQuantities[productId] ?? 0;

        _controllers[productId] ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 150),
          lowerBound: 0.95,
          upperBound: 1.05,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _controllers[productId]?.reverse();
          }
        });

        _qtyAnimControllers[productId] ??= AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
          lowerBound: 0.9,
          upperBound: 1.1,
        );

        return ScaleTransition(
          scale: _controllers[productId]!,
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
              // ✅ CHANGED: Back to simple Column instead of Stack (no tags needed)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image
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
                  // Name + Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: _buildProductButton(item, productId),
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

  @override
  void initState() {
    super.initState();
    _initializeSmoothAnimations();

    _selectedCategory = widget.category ?? 'All';
    _fetchBackgroundImage();
    _testDatabaseConnection();

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    _loadCategoriesForTabs().then((_) {
      _fetchCategoriesAndProducts();
    });

    _fetchCartData();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && cartCountNotifier.value > 0) {
        _showDragHintTemporarily();
      }
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _generateSearchSuggestions();
      _showSearchSuggestions = _searchController.text.isNotEmpty;
    });
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      setState(() => _showSearchSuggestions = true);
    }
  }

  void _generateSearchSuggestions() {
    if (_searchQuery.isEmpty) {
      _searchSuggestions.clear();
      return;
    }
    final query = _searchQuery.toLowerCase();
    _searchSuggestions = _products
        .where((product) =>
        product['product_name'].toString().toLowerCase().contains(query))
        .take(8)
        .toList();
  }

  void _selectSearchSuggestion(Map<String, dynamic> product) {
    final categoryName = product['categories']?['name']?.toString() ?? 'All';
    final productName = product['product_name']?.toString() ?? '';

    _searchController.text = productName;
    setState(() {
      _searchQuery = productName;
      _showSearchSuggestions = false;
      // Switch to the product's category
      if (_categories.contains(categoryName)) {
        _selectedCategory = categoryName;
      } else {
        _selectedCategory = 'All';
      }
    });
    _searchFocusNode.unfocus();

    // Center the selected category chip
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelectedCategoryByName(_selectedCategory);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showSearchSuggestions = false;
    });
  }


  Future<void> _testDatabaseConnection() async {
    try {
      await supabase.from('categories').select('count').single();
      await supabase.from('products').select('count').single();
      await supabase
          .from('products')
          .select('product_name, product_price')
          .eq('is_enabled', true)
          .limit(1);
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final screenSize = MediaQuery.of(context).size;
    final bottomNavHeight = kBottomNavigationBarHeight;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final maxBottom = screenSize.height - bottomNavHeight - safeAreaBottom - 70;

    _fabOffset = Offset(
      screenSize.width - 80,
      (maxBottom * 0.7).clamp(100.0, maxBottom),
    );
  }

  void _initializeSmoothAnimations() {
    _floatingCartController =
        AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _fadeController =
        AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _smoothFloatController =
        AnimationController(duration: const Duration(milliseconds: 8000), vsync: this);
    _breathingController =
        AnimationController(duration: const Duration(milliseconds: 5000), vsync: this);
    _bounceController =
        AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _clearZoneController =
        AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _dragHintController =
        AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _continuousFloatController =
        AnimationController(duration: const Duration(milliseconds: 10000), vsync: this);

    _searchAnimationController =
        AnimationController(duration: const Duration(milliseconds: 300), vsync: this);

    _floatingCartScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _floatingCartController, curve: Curves.easeOutCubic),
    );
    _floatingCartSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _floatingCartController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic));
    _smoothFloatAnimation = Tween<double>(begin: -3.0, end: 3.0)
        .animate(CurvedAnimation(parent: _smoothFloatController, curve: Curves.easeInOutSine));
    _breathingAnimation = Tween<double>(begin: 0.99, end: 1.01)
        .animate(CurvedAnimation(parent: _breathingController, curve: Curves.easeInOutSine));
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeOutBack));
    _colorAnimation = ColorTween(
      begin: kPrimaryColor,
      end: kPrimaryColor.withOpacity(0.9),
    ).animate(CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut));
    _clearZoneScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _clearZoneController, curve: Curves.easeOutBack));
    _clearZoneOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _clearZoneController, curve: Curves.easeOut));
    _dragHintOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _dragHintController, curve: Curves.easeInOut));
    _continuousFloatAnimation = Tween<double>(begin: -2.0, end: 2.0)
        .animate(CurvedAnimation(parent: _continuousFloatController, curve: Curves.easeInOutSine));
    _continuousScaleAnimation = Tween<double>(begin: 0.98, end: 1.02)
        .animate(CurvedAnimation(parent: _continuousFloatController, curve: Curves.easeInOutSine));

    _searchSlideAnimation = Tween<double>(begin: -1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _searchAnimationController, curve: Curves.easeOutCubic));
    _searchFadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _searchAnimationController, curve: Curves.easeOut));

    _fadeController.forward();
    _smoothFloatController.repeat(reverse: true);
    _breathingController.repeat(reverse: true);
    _continuousFloatController.repeat(reverse: true);
  }

  void _showDragHintTemporarily() {
    if (!mounted) return;
    setState(() => _showDragHint = true);
    _dragHintController.forward();
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      _dragHintController.reverse().then((_) {
        if (mounted) setState(() => _showDragHint = false);
      });
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
        setState(() => _backgroundImageUrl = result['background_url'] as String?);
      }
    } catch (_) {}
  }




  // ✅ CHANGED: read by product_id and sum counts by product_id (considering wash types)
  Future<void> _fetchCartData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('cart')
          .select('product_id, product_quantity, service_type')
          .eq('user_id', user.id);

      _productQuantities.clear();

      for (final item in data) {
        final pid = (item['product_id'] ?? '').toString();
        if (pid.isEmpty) continue; // ignore legacy rows without product_id
        final quantity = item['product_quantity'] as int? ?? 0;
        final serviceType = item['service_type'] as String? ?? '';

        // For wash services, we need to check if it's the same service without wash type
        if (serviceType.contains(' - ')) {
          // This is a wash service with wash type, we still count it for the product
          _productQuantities[pid] = (_productQuantities[pid] ?? 0) + quantity;
        } else {
          // Regular service
          _productQuantities[pid] = (_productQuantities[pid] ?? 0) + quantity;
        }
      }

      final totalCount =
      _productQuantities.values.fold<int>(0, (sum, qty) => sum + qty);
      cartCountNotifier.value = totalCount;

      if (totalCount > 0) {
        _floatingCartController.forward();
        _bounceController.forward(from: 0.0);
      } else {
        _floatingCartController.reverse();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ✅ CHANGED: qty update by product_id (and optionally service_type if you pass it)
  Future<void> _updateCartQty(Map<String, dynamic> product, int delta,
      {String? serviceType}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final productId = (product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    try {
      var query = supabase
          .from('cart')
          .select()
          .eq('user_id', user.id)
          .eq('product_id', productId);



      final existingItems = await query;

      if (existingItems.isEmpty) return;

      final currentQty = _productQuantities[productId] ?? 0;
      final newQty = currentQty + delta;

      if (newQty <= 0) {
        for (final item in existingItems) {
          await supabase.from('cart').delete().eq('id', item['id']);
        }
        _productQuantities.remove(productId);
      } else {
        final firstItem = existingItems.first;
        final productPrice =
            (firstItem['product_price'] as num?)?.toDouble() ?? 0.0;
        final servicePrice =
            (firstItem['service_price'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = (productPrice + servicePrice) * newQty;

        await supabase
            .from('cart')
            .update({'product_quantity': newQty, 'total_price': totalPrice})
            .eq('id', firstItem['id']);

        for (int i = 1; i < existingItems.length; i++) {
          await supabase.from('cart').delete().eq('id', existingItems[i]['id']);
        }
        _productQuantities[productId] = newQty;
      }

      await _fetchCartData();
      _triggerAnimations(productId);
    } catch (_) {}
  }

  // ✅ CHANGED: add by product_id (+ service_type uniqueness with wash type)
  Future<void> _addToCartWithService(
      Map<String, dynamic> product,
      String serviceId,
      String serviceName,
      int finalPrice,
      String washType) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to add items to cart')),
        );
      }
      return;
    }

    final productId = (product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    final name = product['product_name'] ?? '';
    final image = product['image_url'] ?? '';
    final category = product['categories']?['name'] ?? '';

    try {
      if (mounted) setState(() => _addedStatus[productId] = true);

      // Determine if this is a wash service
      final bool isWashService = washType.contains('Wash');

      // Prepare service type with wash type
      final String fullServiceType = isWashService
          ? '$serviceName - $washType'
          : serviceName;

      // Check if item already exists in cart
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .eq('service_id', serviceId)
          .eq('service_type', fullServiceType) // Match exact service type including wash type
          .maybeSingle();

      if (existing != null) {
        // Update existing cart item
        final newQty = (existing['product_quantity'] as int) + 1;
        final newTotalPrice = finalPrice * newQty;
        await supabase
            .from('cart')
            .update({
          'product_quantity': newQty,
          'total_price': newTotalPrice,
        })
            .eq('id', existing['id']);
      } else {
        // Insert new cart item
        await supabase.from('cart').insert({
          'user_id': user.id,
          'product_id': productId,
          'product_name': name,
          'product_image': image,
          'product_price': finalPrice.toDouble(), // Store the final price
          'service_id': serviceId,
          'service_type': fullServiceType, // Store with wash type
          'wash_type': isWashService ? washType : null, // Store wash type separately if needed
          'service_price': 0.0, // No separate service price anymore
          'product_quantity': 1,
          'total_price': finalPrice.toDouble(),
          'category': category,
        });
      }

      _productQuantities[productId] = (_productQuantities[productId] ?? 0) + 1;
      _triggerAnimations(productId);

      await _fetchCartData();

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => _addedStatus[productId] = false);
    } catch (e) {
      debugPrint('Error adding to cart: $e');
      if (mounted) setState(() => _addedStatus[productId] = false);
    }
  }

  void _triggerAnimations(String productId) {
    _controllers[productId]?.forward(from: 0.0);
    _qtyAnimControllers[productId]?.forward(from: 0.9);
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
        return Icons.miscellaneous_services;
    }
  }

  Future<void> _onRefresh() async {
    await _fetchCategoriesAndProducts();
    await _fetchCartData();
  }

  // Replace _showServiceSelectionPopup method with this:

  Future<void> _showServiceSelectionPopup(Map<String, dynamic> product) async {
    final productId = (product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    try {
      // Fetch available services with their prices for this specific product
      final resp = await supabase
          .from('product_service_prices')
          .select('*, services:service_id(id, name, service_description, icon_name, color_hex)')
          .eq('product_id', productId)
          .eq('is_available', true)
          .order('price', ascending: true);

      final servicePrices = List<Map<String, dynamic>>.from(resp ?? []);

      if (servicePrices.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No services available for this product'),
            ),
          );
        }
        return;
      }

      final productName = product['product_name'] ?? '';

      if (!mounted) return;
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
                    'Select service for $productName',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: servicePrices.length,
                      itemBuilder: (context, index) {
                        final priceData = servicePrices[index];
                        final serviceData = priceData['services'];

                        final serviceId = serviceData['id']?.toString() ?? '';
                        final serviceName = serviceData['name'] ?? '';
                        final int regularPrice = (priceData['regular_wash_price'] as num?)?.toInt() ??
                            (priceData['price'] as num?)?.toInt() ?? 0;
                        final int? heavyPrice = (priceData['heavy_wash_price'] as num?)?.toInt();
                        final description = (serviceData['service_description'] ?? '').toString();
                        final iconName = serviceData['icon_name'];

                        return GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            // Show wash type selection
                            await _showWashTypeSelection(product, serviceId, serviceName, regularPrice, heavyPrice, priceData);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200, width: 1),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        serviceName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 4),
                                      if (description.isNotEmpty)
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
                                const SizedBox(width: 6),
                                Text(
                                  'From ₹$regularPrice',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: kPrimaryColor,
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load services: $e')),
      );
    }
  }

  // ✅ UPDATED: Show wash type selection and store wash type
  Future<void> _showWashTypeSelection(
      Map<String, dynamic> product,
      String serviceId,
      String serviceName,
      int regularPrice,
      int? heavyPrice,
      Map<String, dynamic> priceData) async {
    if (!mounted) return;

    // ✅ FIXED: Check if this is a wash service by checking if it's actually a WASH service
    // Only show wash type selection for services that contain "Wash" in the name AND have heavyPrice
    final isWashService = serviceName.toLowerCase().contains('wash') && heavyPrice != null;

    // ✅ If NOT a wash service, directly add to cart with service name
    if (!isWashService) {
      await _addToCartWithService(product, serviceId, serviceName, regularPrice, serviceName);
      return;
    }

    // ✅ If IS a wash service (and has heavyPrice), show the wash type selection modal
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle at top
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Text(
                'Select Wash Type',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                serviceName,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),

              // Regular Wash Option
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _addToCartWithService(product, serviceId, serviceName, regularPrice, 'Regular Wash');
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPrimaryColor, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.water_drop_outlined,
                          color: kPrimaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Regular Wash',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Standard cleaning',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹$regularPrice',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Heavy Wash Option
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _addToCartWithService(product, serviceId, serviceName, heavyPrice!, 'Heavy Wash');
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.water_damage,
                          color: Colors.orange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Heavy Wash',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Deep cleaning for tough stains',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹$heavyPrice',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cancel Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }



  Future<void> _clearCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase.from('cart').delete().eq('user_id', user.id);
      _productQuantities.clear();
      cartCountNotifier.value = 0;
      for (final c in _qtyAnimControllers.values) {
        c.reset();
      }
      _floatingCartController.reverse();
      if (!mounted) return;
      setState(() {
        _showClearZone = false;
        _isNearClearZone = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('Cart cleared successfully')],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
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

  bool _isCartNearClearZone() {
    final screenSize = MediaQuery.of(context).size;
    final clearZoneLeft = screenSize.width * 0.5 - 40;
    final clearZoneTop = screenSize.height * 0.65;
    final clearZoneCenter = Offset(clearZoneLeft + 40, clearZoneTop + 40);
    final cartCenter = Offset(_fabOffset.dx + 30, _fabOffset.dy + 30);
    final distance = (cartCenter - clearZoneCenter).distance;
    return distance < 80;
  }

  Widget _buildFloatingCart() {
    // ✅ On web we use the AppBar cart icon; hide the floating cart completely
    if (kIsWeb) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: cartCountNotifier,
      builder: (context, count, child) {
        if (count == 0) return const SizedBox.shrink();

        final screenSize = MediaQuery.of(context).size;
        final appBarHeight = (Scaffold.maybeOf(context)?.appBarMaxHeight ?? kToolbarHeight);
        final bottomNavHeight = kBottomNavigationBarHeight;
        final safeAreaBottom = MediaQuery.of(context).padding.bottom;
        final maxBottom = screenSize.height - bottomNavHeight - safeAreaBottom - 70;
        final minTop = (appBarHeight > 0 ? appBarHeight : kToolbarHeight) + 20;

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
                if (_showClearZone)
                  Positioned(
                    left: screenSize.width * 0.5 - 40,
                    top: screenSize.height * 0.65,
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
                              if (_isNearClearZone)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withOpacity(0.8), width: 3),
                                    ),
                                  ),
                                ),
                              const Center(
                                child: Icon(Icons.delete_forever, color: Colors.white, size: 42),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_showDragHint)
                  Positioned(
                    left: _fabOffset.dx > screenSize.width / 2 ? _fabOffset.dx - 140 : _fabOffset.dx + 70,
                    top: _fabOffset.dy - 10,
                    child: FadeTransition(
                      opacity: _dragHintOpacity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.black.withOpacity(0.9), Colors.black.withOpacity(0.8)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swipe, color: Colors.white.withOpacity(0.9), size: 18),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Drag to clear cart', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                Text('Drop on 🗑️ to delete all items', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: _isDragging
                      ? _fabOffset.dx.clamp(0, screenSize.width - 60)
                      : (_fabOffset.dx + _continuousFloatAnimation.value).clamp(0, screenSize.width - 60),
                  top: _isDragging
                      ? _fabOffset.dy.clamp(minTop, maxBottom)
                      : (_fabOffset.dy + _smoothFloatAnimation.value).clamp(minTop, maxBottom),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))
                          .then((_) => _fetchCartData());
                    },
                    onPanStart: (_) {
                      setState(() {
                        _isDragging = true;
                        _showClearZone = true;
                        _showDragHint = false;
                      });
                      _clearZoneController.forward();
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _fabOffset = Offset(
                          (_fabOffset.dx + details.delta.dx).clamp(0, screenSize.width - 60),
                          (_fabOffset.dy + details.delta.dy).clamp(minTop, maxBottom),
                        );
                        _isNearClearZone = _isCartNearClearZone();
                      });
                    },
                    onPanEnd: (_) {
                      if (_isNearClearZone) _clearCart();
                      setState(() {
                        _isDragging = false;
                        _isNearClearZone = false;
                        final targetX = _fabOffset.dx < screenSize.width / 2 ? 20.0 : screenSize.width - 80.0;
                        _fabOffset = Offset(targetX, _fabOffset.dy.clamp(minTop, maxBottom));
                      });
                      _clearZoneController.reverse();
                      Future.delayed(const Duration(milliseconds: 400), () {
                        if (mounted) setState(() => _showClearZone = false);
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
                                  _isNearClearZone ? Colors.red.shade400 : (_colorAnimation.value ?? kPrimaryColor),
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
                                  color: (_isNearClearZone ? Colors.red.shade400 : (_colorAnimation.value ?? kPrimaryColor))
                                      .withOpacity(0.5),
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
                                          gradient: const LinearGradient(colors: [Colors.white, Color(0xFFF7F7F7)]),
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
                                          child: ValueListenableBuilder<int>(
                                            valueListenable: cartCountNotifier,
                                            builder: (_, count, __) => Text(
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
                                  ),
                                if (_isDragging)
                                  Positioned.fill(
                                    child: Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
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
    _searchController.dispose();
    _searchFocusNode.dispose();

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: _buildPremiumAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            if (_backgroundImageUrl != null)
              Positioned.fill(
                child: Image.network(
                  _backgroundImageUrl!,
                  fit: BoxFit.cover,
                  color: Colors.white.withOpacity(0.15),
                  colorBlendMode: BlendMode.srcATop,
                ),
              ),
            Column(
              children: [
                const SizedBox(height: 12),
                _buildPremiumCategoryTabs(),
                const SizedBox(height: 16),
                Expanded(
                  child: RefreshIndicator(
                    color: kPrimaryColor,
                    displacement: 72,
                    onRefresh: _onRefresh,
                    child: Stack(
                      children: [
                        _buildContent(),
                        if (_showSearchSuggestions && _searchSuggestions.isNotEmpty)
                          _buildSearchSuggestions(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _buildFloatingCart(),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
    );
  }

  // Search Suggestions
  Widget _buildSearchSuggestions() {
    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200, width: 1),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor.withOpacity(0.1), Colors.transparent],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: kPrimaryColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Suggestions (${_searchSuggestions.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kPrimaryColor,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _showSearchSuggestions = false),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),

              // List
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchSuggestions.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final product = _searchSuggestions[index];
                    final productName = product['product_name'] as String;
                    final categoryName = product['categories']?['name'] ?? '';
                    final imageUrl = product['image_url'] ?? '';
                    final price = (product['product_price'] as num?)?.toInt() ?? 0;

                    return InkWell(
                      onTap: () => _selectSearchSuggestion(product),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center, // ⬅️ centers vertically
                          children: [
                            // Thumbnail
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                                color: Colors.grey.shade50,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    Icons.image_outlined,
                                    color: Colors.grey.shade400,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Title + chip (no price here anymore)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    productName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  if (categoryName.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: kPrimaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        categoryName,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: kPrimaryColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Price + chevron on the RIGHT, centered
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'For ₹$price',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: kPrimaryColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildContent() {
    final products = _getFilteredProducts();

    if (_isLoading) {
      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(
            child: Text(
              'Loading products...',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ),
          SizedBox(height: 120),
        ],
      );
    }

    if (products.isEmpty) {
      final isSearchResult = _searchQuery.isNotEmpty;
      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 120),
          Icon(
            isSearchResult ? Icons.search_off : Icons.shopping_bag_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              isSearchResult ? 'No products found' : 'No products found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              isSearchResult
                  ? 'No products match "$_searchQuery"'
                  : _selectedCategory == 'All'
                  ? 'No products available'
                  : 'No products in "$_selectedCategory" category',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          if (isSearchResult)
            Center(
              child: ElevatedButton.icon(
                onPressed: _clearSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.clear, color: Colors.white),
                label: const Text('Clear Search', style: TextStyle(color: Colors.white)),
              ),
            )
          else
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  _hasFetchedProducts = false;
                  _cachedProducts.clear();
                  _cachedCategories = ['All'];
                  _fetchCategoriesAndProducts();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Reload Products', style: TextStyle(color: Colors.white)),
              ),
            ),
          const SizedBox(height: 120),
        ],
      );
    }

    return _buildPremiumProductGrid(context, products);
  }

  @override
  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 0,
      toolbarHeight: 76,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 16,
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
      title: SafeArea(
        bottom: false,
        child: Theme(
          // kill splash/hover/focus paints and default input highlights
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            inputDecorationTheme: const InputDecorationTheme(
              // we’ll also set explicit borders below, but this keeps defaults quiet
              isCollapsed: true,
            ),
          ),
          child: ClipRRect(
            // hard-clip everything to pill radius so shape never changes
            borderRadius: BorderRadius.circular(25),
            child: Material(
              color: Colors.transparent,
              child: Container(
                height: 42, // same as cart button
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.grey.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    height: 1.2,
                  ),
                  cursorColor: kPrimaryColor,
                  decoration: InputDecoration(
                    // ⬇️ Force identical rounded outline in ALL states (and invisible)
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.transparent, width: 0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.transparent, width: 0),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.transparent, width: 0),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.transparent, width: 0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.transparent, width: 0),
                    ),
                    // keep the interior clean
                    filled: true,
                    fillColor: Colors.transparent,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.only(top: 1),

                    hintText: 'Search Products...',
                    hintStyle: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF42A5F5),
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),

                    // LEFT icon lane (centered)
                    prefixIcon: const SizedBox(
                      width: 42, height: 42,
                      child: Center(
                        child: Icon(Icons.search, size: 20, color: kPrimaryColor),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),

                    // RIGHT clear lane (only when text exists)
                    suffixIcon: (_searchQuery.isNotEmpty)
                        ? SizedBox(
                      width: 42, height: 42,
                      child: Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(21),
                          onTap: _clearSearch,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.black54),
                          ),
                        ),
                      ),
                    )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                  ),
                  onChanged: (_) {
                    setState(() {
                      _searchQuery = _searchController.text;
                      _generateSearchSuggestions();
                      _showSearchSuggestions = _searchController.text.isNotEmpty;
                    });
                  },
                  onSubmitted: (value) {
                    setState(() => _showSearchSuggestions = false);
                    _searchFocusNode.unfocus();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (kIsWeb)
          Container(
            margin: const EdgeInsets.only(right: 12),
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
                            _fetchCartData();
                          },
                          child: const Center(
                            child: Icon(Icons.shopping_cart_outlined, size: 22, color: kPrimaryColor),
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
                                offset: Offset(0, 2),
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
      ],
    );
  }


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

          // Ensure each category has a stable GlobalKey
          final key = _categoryKeys.putIfAbsent(cat, () => GlobalKey());

          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategory = cat);
              // Center the tapped chip
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _centerSelectedCategoryByName(cat);
              });
            },
            child: Container(
              key: key, // <-- important: attach the key to a wrapping widget
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                constraints: const BoxConstraints(minWidth: 80),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)])
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : Colors.grey.shade200,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected ? kPrimaryColor.withOpacity(0.3) : Colors.black.withOpacity(0.05),
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
            ),
          );
        },
      ),
    );
  }



  Widget _buildProductButton(Map<String, dynamic> item, String productId) {
    if (_addedStatus[productId] == true) {
      return Container(
        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text('Added!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: () => _showServiceSelectionPopup(item),
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        padding: EdgeInsets.zero,
      ),
      child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}
