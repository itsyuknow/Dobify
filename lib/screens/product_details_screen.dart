import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import 'colors.dart';
import 'order_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String productId;
  const ProductDetailsScreen({Key? key, required this.productId}) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _services = [];
  int _quantity = 1;
  int _currentCartQuantity = 0; // ✅ NEW: Track current cart quantity
  String _selectedService = '';
  int _selectedServicePrice = 0;
  bool _addedToCart = false;
  bool _isLoading = false;
  bool _isAddingToCart = false;

  // ✅ REFINED: Compact animation controllers
  late AnimationController _fadeController;
  late AnimationController _buttonController;
  late AnimationController _successController;
  late AnimationController _floatController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _buttonScale;
  late Animation<double> _successScale;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchProductDetails();
    _fetchServices();

    // ✅ NEW: Listen to cart changes
    cartCountNotifier.addListener(_onCartCountChanged);
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _buttonScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    _floatAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    _fadeController.forward();
    _floatController.repeat(reverse: true);
  }

  Future<void> _fetchProductDetails() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('🔄 Fetching product details for ID: ${widget.productId}');

      // ✅ FIXED: Use the same pattern as OrdersScreen with better query handling
      final response = await supabase
          .from('products')
          .select('id, product_name, product_price, image_url, category_id, is_enabled, created_at, categories(name)')
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      debugPrint('📦 Product response: $response');

      if (response != null) {
        setState(() {
          _product = response;
          _isLoading = false;
        });

        debugPrint('✅ Product loaded: ${response['product_name']}');

        // ✅ FIXED: Fetch cart quantity after product is loaded
        await _fetchCurrentCartQuantity();
      } else {
        debugPrint('⚠️ No product found, trying fallback query...');
        await _fetchProductDetailsFallback();
      }
    } catch (e) {
      debugPrint('❌ Error fetching product with categories: $e');
      // ✅ FIXED: Try fallback query without categories join
      await _fetchProductDetailsFallback();
    }
  }

  // ✅ NEW: Fallback method without categories join
  Future<void> _fetchProductDetailsFallback() async {
    try {
      debugPrint('🔄 Trying fallback query without categories join...');

      final response = await supabase
          .from('products')
          .select('*')
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      debugPrint('📦 Fallback response: $response');

      if (response != null) {
        // ✅ FIXED: Fetch category separately and map it
        String categoryName = 'General';
        if (response['category_id'] != null) {
          try {
            final categoryResponse = await supabase
                .from('categories')
                .select('name')
                .eq('id', response['category_id'])
                .eq('is_active', true)
                .maybeSingle();

            if (categoryResponse != null) {
              categoryName = categoryResponse['name'] ?? 'General';
            }
          } catch (e) {
            debugPrint('Could not fetch category: $e');
          }
        }

        // Add categories object to product
        response['categories'] = {'name': categoryName};

        setState(() {
          _product = response;
          _isLoading = false;
        });

        debugPrint('✅ Fallback successful: ${response['product_name']} - Category: $categoryName');

        // ✅ FIXED: Fetch cart quantity after product is loaded
        await _fetchCurrentCartQuantity();
      } else {
        debugPrint('❌ Product not found in fallback query');
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Product not found'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Fallback query also failed: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading product: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _fetchServices() async {
    try {
      debugPrint('🔄 Fetching services...');

      final response = await supabase
          .from('services')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      debugPrint('📋 Services response: ${response.length} services found');

      final serviceList = List<Map<String, dynamic>>.from(response);
      setState(() {
        _services = serviceList;
        if (_services.isNotEmpty) {
          _selectedService = _services[0]['name'];
          _selectedServicePrice = _services[0]['price'];
          debugPrint('✅ Default service selected: $_selectedService (₹$_selectedServicePrice)');
        }
      });
    } catch (e) {
      debugPrint('❌ Error fetching services: $e');
    }
  }

  // ✅ NEW: Fetch current cart quantity for this product
  Future<void> _fetchCurrentCartQuantity() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) return;

    try {
      debugPrint('🔄 Fetching current cart quantity for: ${_product!['product_name']}');

      final response = await supabase
          .from('cart')
          .select('product_quantity, service_type, service_price')
          .eq('user_id', user.id)
          .eq('product_name', _product!['product_name']);

      debugPrint('🛒 Cart response: ${response.length} items found');

      if (response.isNotEmpty) {
        // Get total quantity across all services for this product
        final totalQuantity = response.fold<int>(0, (sum, item) => sum + (item['product_quantity'] as int? ?? 0));

        // Set the first service found as selected (or keep default if none match)
        final firstCartItem = response.first;
        final serviceInCart = firstCartItem['service_type'] as String?;
        final servicePriceInCart = firstCartItem['service_price'] as int?;

        if (serviceInCart != null && _services.any((s) => s['name'] == serviceInCart)) {
          setState(() {
            _currentCartQuantity = totalQuantity;
            _quantity = totalQuantity > 0 ? totalQuantity : 1;
            _selectedService = serviceInCart;
            _selectedServicePrice = servicePriceInCart ?? _selectedServicePrice;
          });
          debugPrint('✅ Found in cart: $_currentCartQuantity x $_selectedService');
        } else {
          setState(() {
            _currentCartQuantity = totalQuantity;
            _quantity = totalQuantity > 0 ? totalQuantity : 1;
          });
          debugPrint('✅ Found in cart: $_currentCartQuantity items (different service)');
        }
      } else {
        debugPrint('ℹ️ Product not in cart');
      }
    } catch (e) {
      debugPrint('❌ Error fetching current cart quantity: $e');
    }
  }

  // ✅ NEW: Handle cart count changes from other screens
  void _onCartCountChanged() {
    _fetchCurrentCartQuantity();
  }

  Future<void> _addToCart() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add items to cart')),
      );
      return;
    }

    setState(() => _isAddingToCart = true);
    _buttonController.forward();

    try {
      final name = _product!['product_name'];
      final basePrice = (_product!['product_price'] as num?)?.toDouble() ?? 0.0;
      final image = _product!['image_url'] ?? '';
      final category = _product!['categories']?['name'] ?? 'General';
      final totalPrice = (basePrice + _selectedServicePrice) * _quantity;

      debugPrint('🔄 Adding to cart: $name x $_quantity with $_selectedService (₹$_selectedServicePrice each)');

      // ✅ FIXED: Check for existing item with same service
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_name', name)
          .eq('service_type', _selectedService)
          .maybeSingle();

      if (existing != null) {
        // ✅ FIXED: Update to new quantity instead of adding
        await supabase.from('cart').update({
          'product_quantity': _quantity,
          'total_price': totalPrice,
        }).eq('id', existing['id']);

        debugPrint('✅ Updated existing cart item to quantity: $_quantity');
      } else {
        // ✅ FIXED: Remove any existing items with different services for this product
        await supabase
            .from('cart')
            .delete()
            .eq('user_id', user.id)
            .eq('product_name', name);

        // Add new item
        await supabase.from('cart').insert({
          'user_id': user.id,
          'product_name': name,
          'product_price': basePrice,
          'product_image': image,
          'product_quantity': _quantity,
          'category': category,
          'service_type': _selectedService,
          'service_price': _selectedServicePrice.toDouble(),
          'total_price': totalPrice,
        });

        debugPrint('✅ Added new cart item with quantity: $_quantity');
      }

      // ✅ FIXED: Update current cart quantity
      setState(() {
        _currentCartQuantity = _quantity;
      });

      await _updateCartCount();

      setState(() => _addedToCart = true);
      _successController.forward();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Cart updated!', style: TextStyle(fontSize: 14)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        Navigator.pop(context, true);
      }

    } catch (e) {
      debugPrint('❌ Error updating cart: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating cart: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      setState(() => _isAddingToCart = false);
      _buttonController.reverse();
    }
  }

  Future<void> _updateCartCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('cart')
          .select('product_quantity')
          .eq('user_id', user.id);

      final totalCount = data.fold<int>(0, (sum, item) => sum + (item['product_quantity'] as int? ?? 0));
      cartCountNotifier.value = totalCount;
      debugPrint('🛒 Updated global cart count: $totalCount');
    } catch (e) {
      debugPrint('❌ Error updating cart count: $e');
    }
  }

  IconData _getServiceIcon(String serviceName) {
    switch (serviceName.toLowerCase().trim()) {
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
        return Icons.compress_rounded;
      default:
        return Icons.cleaning_services_rounded;
    }
  }

  @override
  void dispose() {
    // ✅ FIXED: Remove cart listener
    cartCountNotifier.removeListener(_onCartCountChanged);

    _fadeController.dispose();
    _buttonController.dispose();
    _successController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: kPrimaryColor,
          title: const Text('Loading...'),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              const Text('Loading product details...'),
            ],
          ),
        ),
      );
    }

    if (_product == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: kPrimaryColor,
          title: const Text('Product Not Found'),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Product not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                child: const Text('Go Back', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        title: Text(
          _product!['product_name'] ?? 'Product',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompactProductImage(),
                  const SizedBox(height: 16),
                  _buildServiceSelection(),         // 🔁 MOVED UP
                  const SizedBox(height: 16),
                  _buildProductInfo(),              // 🔁 Moved down, now shows selected service description and total
                  const SizedBox(height: 20),
                  _buildQuantityAndPrice(),
                  const SizedBox(height: 24),
                  _buildCompactAddButton(),
                  const SizedBox(height: 20),
                ],
              ),

            ),
          );
        },
      ),
    );
  }

  // ✅ COMPACT: Smaller, elegant product image
  Widget _buildCompactProductImage() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _product!['image_url'] ?? '',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade50,
                  child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 40),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ REFINED: Clean product info
  Widget _buildProductInfo() {
    final singleItemPrice = (_product!['product_price'] ?? 0) + _selectedServicePrice;

    final selectedService = _services.firstWhere(
          (s) => s['name'] == _selectedService,
      orElse: () => {'service_full_description': 'No description available'},
    );

    final selectedServiceDesc = selectedService['service_full_description'] ?? 'No description available';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.currency_rupee, color: kPrimaryColor, size: 14),
                Text(
                  '$singleItemPrice',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            selectedServiceDesc,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }




  // ✅ ELEGANT: Compact service selection
  Widget _buildServiceSelection() {
    if (_services.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade600, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Loading services...',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Service',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF42A5F5),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _services.map((service) {
              final name = service['name'];
              final price = service['price'];
              final selected = _selectedService == name;

              return Container(
                margin: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedService = name;
                    _selectedServicePrice = price;
                    debugPrint('🔧 Service selected: $name (₹$price)');
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? kPrimaryColor : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? kPrimaryColor : Colors.grey.shade300,
                        width: 1,
                      ),
                      boxShadow: selected
                          ? [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                          : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 5,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getServiceIcon(name),
                          size: 16,
                          color: selected ? Colors.white : kPrimaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }


  // ✅ COMPACT: Quantity and price in one row
  Widget _buildQuantityAndPrice() {
    final totalPrice = ((_product!['product_price'] ?? 0) + _selectedServicePrice) * _quantity;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Quantity controls
              Row(
                children: [
                  Text(
                    'Quantity',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (_quantity > 1) _quantity--;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _quantity > 1 ? kPrimaryColor : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.remove,
                            color: _quantity > 1 ? Colors.white : Colors.grey.shade600,
                            size: 16,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_quantity',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _quantity++),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: kPrimaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Total price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '₹$totalPrice',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ✅ NEW: Show current cart status
          if (_currentCartQuantity > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Currently in cart: $_currentCartQuantity item${_currentCartQuantity > 1 ? 's' : ''} with $_selectedService',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ SLEEK: Compact add to cart button
  Widget _buildCompactAddButton() {
    final bool hasChanged = _currentCartQuantity != _quantity;
    final bool isInCart = _currentCartQuantity > 0;

    return AnimatedBuilder(
      animation: Listenable.merge([_buttonController, _successController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _addedToCart ? _successScale.value : _buttonScale.value,
          child: Container(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isAddingToCart || !hasChanged) ? null : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: _addedToCart
                    ? Colors.green
                    : (hasChanged ? kPrimaryColor : Colors.grey.shade400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: _addedToCart ? 6 : (hasChanged ? 3 : 1),
                shadowColor: _addedToCart
                    ? Colors.green.withOpacity(0.3)
                    : kPrimaryColor.withOpacity(0.3),
              ),
              child: _isAddingToCart
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _addedToCart
                        ? Icons.check_circle_rounded
                        : (isInCart ? Icons.refresh_rounded : Icons.shopping_cart_rounded),
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _addedToCart
                        ? 'Updated!'
                        : (hasChanged
                        ? (isInCart ? 'Update Cart' : 'Add to Cart')
                        : 'No Changes'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
}