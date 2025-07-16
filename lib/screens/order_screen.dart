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

  // ✅ Premium animation controllers
  late AnimationController _floatingCartController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _bounceController;

  late Animation<double> _floatingCartScale;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _floatingCartSlide;
  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<Color?> _colorAnimation;

  // ✅ NEW: In-memory cache flags
  bool _hasFetchedProducts = false;
  List<Map<String, dynamic>> _cachedProducts = [];
  List<String> _cachedCategories = ['All'];
  bool _showClearCart = false;

  // ✅ FIXED: Initialize with default values
  Offset _fabOffset = const Offset(300, 400); // Default position
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _initializePremiumAnimations();

    if (!_isInitialLoadDone) {
      _selectedCategory = widget.category ?? 'All';
      _fetchBackgroundImage();
      _fetchCategoriesAndProducts();
      _fetchCartData();
      _isInitialLoadDone = true;
    }
  }

  // ✅ FIXED: Initialize FAB position after first build
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Now we can safely access MediaQuery
    final screenSize = MediaQuery.of(context).size;
    _fabOffset = Offset(screenSize.width - 72, screenSize.height * 0.7);
  }

  // ✅ Premium animations initialization
  void _initializePremiumAnimations() {
    _floatingCartController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _floatingCartScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _floatingCartController, curve: Curves.elasticOut),
    );

    _floatingCartSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _floatingCartController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _colorAnimation = ColorTween(
      begin: kPrimaryColor,
      end: Colors.deepPurple,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
    _pulseController.repeat(reverse: true);
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
    // ✅ Use cache if already fetched
    if (_hasFetchedProducts) {
      _products.clear();
      _products.addAll(_cachedProducts);
      setState(() {
        _categories = _cachedCategories;
      });
      return;
    }

    try {
      final response = await supabase
          .from('products')
          .select('*, categories (name)')
          .eq('is_enabled', true);

      final productList = List<Map<String, dynamic>>.from(response);
      _products.clear();
      _products.addAll(productList);

      final uniqueCategories = _products
          .map((p) => p['categories']?['name']?.toString() ?? '')
          .toSet()
          .where((name) => name.isNotEmpty)
          .toList();

      _categories = ['All', ...uniqueCategories];

      // ✅ Save to cache
      _cachedProducts = List<Map<String, dynamic>>.from(_products);
      _cachedCategories = List<String>.from(_categories);
      _hasFetchedProducts = true;

      setState(() {});

      // Auto-scroll to selected category
      if (widget.category != null && widget.category != 'All') {
        final index = _categories.indexOf(widget.category!);
        if (index != -1) {
          await Future.delayed(const Duration(milliseconds: 300));
          _scrollController.animateTo(
            index * 120.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      }
    } catch (e) {
      print('❌ Error fetching products: $e');
    }
  }

  List<Map<String, dynamic>> _getFilteredProducts() {
    if (_selectedCategory == 'All') return _products;
    return _products.where((p) => p['categories']?['name'] == _selectedCategory).toList();
  }

  // ✅ FIXED: Cart data fetching
  Future<void> _fetchCartData() async {
    print('🔄 Fetching cart data...');
    final user = supabase.auth.currentUser;
    if (user == null) {
      print('❌ No user found');
      return;
    }

    try {
      final data = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id);

      print('📦 Cart data fetched: ${data.length} items');

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

      print('✅ Product quantities: $_productQuantities');
      print('✅ Total cart count: $totalCount');

      // Animate floating cart
      if (totalCount > 0) {
        _floatingCartController.forward();
        _bounceController.forward(from: 0.0); // Bounce when items added
      } else {
        _floatingCartController.reverse();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Error fetching cart: $e');
    }
  }

  // ✅ FIXED: Update cart quantity
  Future<void> _updateCartQty(Map<String, dynamic> product, int delta) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final name = product['product_name'];
    print('🔄 Updating cart quantity for $name by $delta');

    try {
      // Get existing cart items for this product
      final existingItems = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id)
          .eq('product_name', name);

      if (existingItems.isEmpty) {
        print('❌ No existing cart items found for $name');
        return;
      }

      final currentQty = _productQuantities[name] ?? 0;
      final newQty = currentQty + delta;

      print('📊 Current: $currentQty, Delta: $delta, New: $newQty');

      if (newQty <= 0) {
        // Remove all items
        for (final item in existingItems) {
          await supabase
              .from('cart')
              .delete()
              .eq('id', item['id']);
        }
        _productQuantities.remove(name);
        print('🗑️ Removed all $name items from cart');
      } else {
        // Update quantity for first item, remove others
        final firstItem = existingItems.first;
        final productPrice = (firstItem['product_price'] as num?)?.toDouble() ?? 0.0;
        final servicePrice = (firstItem['service_price'] as num?)?.toDouble() ?? 0.0;
        final totalPrice = (productPrice + servicePrice) * newQty;

        // Update first item
        await supabase.from('cart').update({
          'product_quantity': newQty,
          'total_price': totalPrice,
        }).eq('id', firstItem['id']);

        // Remove other items
        for (int i = 1; i < existingItems.length; i++) {
          await supabase
              .from('cart')
              .delete()
              .eq('id', existingItems[i]['id']);
        }

        _productQuantities[name] = newQty;
        print('✅ Updated $name quantity to $newQty');
      }

      // Refresh cart and update UI
      await _fetchCartData();
      _triggerAnimations(name);

    } catch (e) {
      print('❌ Error updating cart quantity: $e');
    }
  }

  // ✅ FIXED: Add product to cart with service
  Future<void> _addToCartWithService(Map<String, dynamic> product, String service, int servicePrice) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      print('❌ No user found');
      return;
    }

    final name = product['product_name'];
    final basePrice = (product['product_price'] as num?)?.toDouble() ?? 0.0;
    final image = product['image_url'] ?? '';
    final category = product['categories']?['name'] ?? '';
    final totalPrice = basePrice + servicePrice;

    print('🔄 Adding $name to cart with $service service (₹$servicePrice)');

    try {
      // Show loading state
      setState(() {
        _addedStatus[name] = true;
      });

      // Check if product with same service already exists
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_name', name)
          .eq('service_type', service)
          .maybeSingle();

      if (existing != null) {
        // Update existing item
        final newQty = (existing['product_quantity'] as int) + 1;
        final newTotalPrice = (basePrice + servicePrice) * newQty;

        await supabase.from('cart').update({
          'product_quantity': newQty,
          'total_price': newTotalPrice,
        }).eq('id', existing['id']);

        print('✅ Updated existing cart item: $name, qty: $newQty');
      } else {
        // Insert new item
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

        print('✅ Added new cart item: $name');
      }

      // Update local quantities
      _productQuantities[name] = (_productQuantities[name] ?? 0) + 1;

      // Trigger animations
      _triggerAnimations(name);

      // Reset added status after delay
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _addedStatus[name] = false;
        });
      }

      // Refresh cart data
      await _fetchCartData();

    } catch (e) {
      print('❌ Error adding to cart: $e');

      // Reset state on error
      if (mounted) {
        setState(() {
          _addedStatus[name] = false;
        });
      }
    }
  }

  // ✅ Helper method for animations
  void _triggerAnimations(String productName) {
    _controllers[productName]?.forward(from: 0.0);
    _qtyAnimControllers[productName]?.forward(from: 0.9);
  }

  // ✅ Service icons
  IconData _getServiceIcon(String? serviceName) {
    switch (serviceName?.toLowerCase().trim()) {
      case 'wash & iron':
      case 'wash and iron':
      case 'wash+iron':
        return Icons.local_laundry_service_rounded;
      case 'dry clean':
      case 'dry cleaning':
        return Icons.dry_cleaning_rounded;
      case 'steam iron':
      case 'ironing':
      case 'iron':
      case 'only iron':
        return Icons.iron_rounded;
      case 'pressing':
        return Icons.compress;
      default:
        return Icons.cleaning_services_rounded;
    }
  }

  // ✅ FIXED: Smaller service selection popup
  Future<void> _showServiceSelectionPopup(Map<String, dynamic> product) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add items to cart')),
      );
      return;
    }

    print('🔄 Loading services...');

    try {
      // Show loading dialog first
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final response = await supabase
          .from('services')
          .select('*')
          .eq('is_active', true)
          .order('sort_order');

      final services = List<Map<String, dynamic>>.from(response);

      // Close loading dialog
      Navigator.pop(context);

      if (services.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No services available')),
        );
        return;
      }

      print('✅ Services loaded: ${services.length}');

      // Show service selection dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(
                maxWidth: 300,
                maxHeight: 400,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Text(
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
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Services list
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: services.length,
                      itemBuilder: (context, index) {
                        final service = services[index];
                        final name = service['name'];
                        final price = service['price'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                Navigator.pop(context);
                                await _addToCartWithService(product, name, price);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: kPrimaryColor.withOpacity(0.1),
                                      ),
                                      child: Icon(
                                        _getServiceIcon(name),
                                        size: 20,
                                        color: kPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Base + ₹$price',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '+₹$price',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: kPrimaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Cancel button
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
      // Close loading dialog if open
      Navigator.pop(context);

      print('❌ Error loading services: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load services: $e')),
      );
    }
  }

  // ✅ PREMIUM FLOATING CART - Enhanced with multiple animations
  Widget _buildFloatingCart() {
    return ValueListenableBuilder<int>(
      valueListenable: cartCountNotifier,
      builder: (context, count, child) {
        if (count == 0) {
          _showClearCart = false;
          return const SizedBox.shrink();
        }

        final screenSize = MediaQuery.of(context).size;
        final appBarHeight = Scaffold.of(context).appBarMaxHeight ?? kToolbarHeight;
        final maxBottom = screenSize.height - kBottomNavigationBarHeight - 80;

        return AnimatedBuilder(
          animation: Listenable.merge([
            _floatingCartController,
            _pulseController,
            _bounceController,
          ]),
          builder: (context, child) {
            return Stack(
              children: [
                // ✅ PREMIUM Clear Cart Zone (appears when dragging)
                if (_showClearCart)
                  Positioned(
                    bottom: kBottomNavigationBarHeight + 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 300),
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: GestureDetector(
                              onTap: () {
                                _clearCart();
                                setState(() => _showClearCart = false);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.red.shade400,
                                      Colors.red.shade600,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                                    SizedBox(width: 12),
                                    Text(
                                      'Clear Cart',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // ✅ PREMIUM Draggable Cart Icon with enhanced animations
                Positioned(
                  left: _fabOffset.dx,
                  top: _fabOffset.dy.clamp(appBarHeight + 20, maxBottom),
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
                        _showClearCart = true;
                      });
                    },
                    onPanUpdate: (details) {
                      final newDx = details.globalPosition.dx - 30;
                      final newDy = details.globalPosition.dy - 30;

                      setState(() {
                        _fabOffset = Offset(
                          newDx.clamp(0, screenSize.width - 60),
                          newDy.clamp(appBarHeight + 20, maxBottom),
                        );
                      });
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isDragging = false;
                        // Snap to nearest side with smooth animation
                        _fabOffset = Offset(
                          _fabOffset.dx < screenSize.width / 2 ? 20 : screenSize.width - 80,
                          _fabOffset.dy,
                        );

                        Future.delayed(const Duration(seconds: 3), () {
                          if (mounted) setState(() => _showClearCart = false);
                        });
                      });
                    },
                    child: SlideTransition(
                      position: _floatingCartSlide,
                      child: ScaleTransition(
                        scale: _floatingCartScale,
                        child: Transform.scale(
                          scale: _isDragging ? 1.2 : _bounceAnimation.value,
                          child: Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _colorAnimation.value ?? kPrimaryColor,
                                  (_colorAnimation.value ?? kPrimaryColor).withOpacity(0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_colorAnimation.value ?? kPrimaryColor).withOpacity(0.4),
                                  blurRadius: _isDragging ? 20 : 15,
                                  spreadRadius: _isDragging ? 4 : 2,
                                  offset: Offset(0, _isDragging ? 8 : 6),
                                ),
                                // Additional inner glow
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.2),
                                  blurRadius: 8,
                                  spreadRadius: -2,
                                  offset: const Offset(-2, -2),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Cart Icon with pulse effect
                                Center(
                                  child: Transform.scale(
                                    scale: _pulseAnimation.value,
                                    child: Icon(
                                      Icons.shopping_bag_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),

                                // Premium count badge with enhanced styling
                                Positioned(
                                  top: -8,
                                  right: -8,
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
                                          color: Colors.black.withOpacity(0.15),
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

                                // ✅ Premium ripple effect when dragging
                                if (_isDragging)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
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

  Future<void> _clearCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      // Reset all cart-related states
      _productQuantities.clear();
      cartCountNotifier.value = 0;

      if (mounted) {
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
    _pulseController.dispose();
    _bounceController.dispose();
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
                Expanded(child: _buildPremiumProductGrid(products)),
              ],
            ),

            // Premium Floating cart
            _buildFloatingCart(),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 1),
    );
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

  // ✅ Product grid
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
                        const SizedBox(height: 6),

                        // Price badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '₹${item['product_price'] ?? 0}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Button section
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: _buildProductButton(item, name, qty),
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
  Widget _buildProductButton(Map<String, dynamic> item, String name, int qty) {
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

    // Show quantity controls
    if (qty > 0) {
      return ScaleTransition(
        scale: _qtyAnimControllers[name]!,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _updateCartQty(item, -1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              Text(
                '$qty',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () => _updateCartQty(item, 1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 16,
                  ),
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
        print('🔘 Add button pressed for: $name');
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