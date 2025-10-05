import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import 'colors.dart';
import 'order_screen.dart';
import 'dart:convert'; // <-- needed for jsonDecode
import 'package:flutter/services.dart';



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
  String? _recommendedServiceId; // NEW: Track recommended service ID
  int _quantity = 0;
  int _currentCartQuantity = 0;
  String _selectedService = '';
  int _selectedServicePrice = 0;
  bool _addedToCart = false;
  bool _isLoading = false;
  bool _isAddingToCart = false;

  // Animations (keep existing)
  late AnimationController _fadeController;
  late AnimationController _buttonController;
  late AnimationController _successController;
  late AnimationController _floatController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _buttonScale;
  late Animation<double> _successScale;
  late Animation<double> _floatAnimation;

  List<String> _parseServiceIds(dynamic raw) {
    try {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (raw is String) {
        final s = raw.trim();
        if (s.isEmpty) return [];
        if ((s.startsWith('[') && s.endsWith(']')) ||
            (s.startsWith('"') && s.endsWith('"'))) {
          final decoded = jsonDecode(s);
          if (decoded is List) {
            return decoded.map((e) => e?.toString().trim() ?? '')
                .where((x) => x.isNotEmpty)
                .toList();
          }
        }
        if (s.contains(',')) {
          return s.split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return [s]; // single id as plain string
      }
      return [];
    } catch (_) {
      return [];
    }
  }


  Future<void> _fetchProductDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('products')
          .select(
          'id, product_name, product_price, image_url, category_id, is_enabled, created_at, recommended_service_id, services_provided, categories(name)'
      )
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _product = response;
          _recommendedServiceId = response['recommended_service_id']?.toString(); // ensure string
          _isLoading = false;
        });

        // 👇 load services only AFTER product is set
        await _fetchServices();
        // selected service is chosen in _fetchServices(); now read cart qty for that service
        await _fetchCurrentCartQuantity();
      } else {
        await _fetchProductDetailsFallback();
      }
    } catch (e) {
      await _fetchProductDetailsFallback();
    }
  }


  Future<void> _fetchProductDetailsFallback() async {
    try {
      final response = await supabase
          .from('products')
          .select('*')
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      if (response != null) {
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
          } catch (_) {}
        }
        response['categories'] = {'name': categoryName};

        setState(() {
          _product = response;
          _recommendedServiceId = response['recommended_service_id']?.toString();
          _isLoading = false;
        });

        // 👇 load services AFTER product is set
        await _fetchServices();
        await _fetchCurrentCartQuantity();
      } else {
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
      // Parse allowed service UUIDs from product (uuid[] / JSON string / csv / single)
      final allowedServiceIds = _parseServiceIds(_product?['services_provided']);

      var query = supabase
          .from('services')
          .select('*')
          .eq('is_active', true);

      if (allowedServiceIds.isNotEmpty) {
        query = query.inFilter('id', allowedServiceIds); // correct Supabase filter
      }

      final response = await query.order('sort_order');
      final serviceList = List<Map<String, dynamic>>.from(response ?? []);

      setState(() {
        _services = serviceList;

        if (_services.isNotEmpty) {
          // prefer recommended if present and in filtered list
          final recId = (_recommendedServiceId ?? '').toString();
          Map<String, dynamic>? recommendedService;
          if (recId.isNotEmpty) {
            try {
              recommendedService = _services.firstWhere(
                    (s) => (s['id']?.toString() ?? '') == recId,
              );
            } catch (_) {}
          }

          final chosen = recommendedService ?? _services.first;
          _selectedService = chosen['name'] ?? '';
          _selectedServicePrice = (chosen['price'] as num?)?.toInt() ?? 0;
        } else {
          _selectedService = '';
          _selectedServicePrice = 0;
        }
      });

      await _fetchCurrentCartQuantity();
    } catch (_) {
      // silent as per your style
    }
  }



// NEW: Helper method to check if a service is recommended
  bool _isRecommendedService(String serviceId) {
    return _recommendedServiceId != null && _recommendedServiceId == serviceId;
  }


  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchProductDetails(); // this will now chain to _fetchServices()
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



  // 🔁 only for the selected service
  Future<void> _fetchCurrentCartQuantity() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null || _selectedService.isEmpty) return;

    try {
      final response = await supabase
          .from('cart')
          .select('id, product_quantity')
          .eq('user_id', user.id)
          .eq('product_id', _product!['id'].toString())
          .eq('service_type', _selectedService)
          .maybeSingle();

      if (response != null) {
        final quantity = response['product_quantity'] as int? ?? 0;
        setState(() {
          _currentCartQuantity = quantity;
          _quantity = quantity;
        });
      } else {
        setState(() {
          _currentCartQuantity = 0;
          _quantity = 0;
        });
      }
    } catch (_) {}
  }


  void _onCartCountChanged() async {
    await _fetchCurrentCartQuantity();
  }

  Future<void> _addToCart() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add items to cart')),
      );
      return;
    }
    if (_selectedService.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service')),
      );
      return;
    }

    setState(() => _isAddingToCart = true);
    _buttonController.forward();

    try {
      final productId = _product!['id'].toString();
      final name = _product!['product_name'];
      final basePrice = (_product!['product_price'] as num?)?.toDouble() ?? 0.0;
      final image = _product!['image_url'] ?? '';
      final category = _product!['categories']?['name'] ?? 'General';
      final totalPrice = (basePrice + _selectedServicePrice) * _quantity;

      // 🔁 Look up existing row by product_id + service_type (not product_name)
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .eq('service_type', _selectedService)
          .maybeSingle();

      if (existing != null) {
        if (_quantity <= 0) {
          // quantity 0 => remove row
          await supabase.from('cart').delete().eq('id', existing['id']);
          setState(() {
            _currentCartQuantity = 0;
            _addedToCart = true;
          });
        } else {
          await supabase.from('cart').update({
            'product_quantity': _quantity,
            'total_price': totalPrice,
          }).eq('id', existing['id']);
          setState(() {
            _currentCartQuantity = _quantity;
            _addedToCart = true;
          });
        }
      } else {
        if (_quantity <= 0) {
          // nothing to add when 0
          setState(() {
            _currentCartQuantity = 0;
            _addedToCart = true;
          });
        } else {
          await supabase.from('cart').insert({
            'user_id': user.id,
            'product_id': productId,                       // ✅ key for joins
            // The following are display fields (optional but handy for UI):
            'product_name': name,
            'product_price': basePrice,
            'product_image': image,
            'category': category,
            // Selection
            'service_type': _selectedService,
            'service_price': _selectedServicePrice.toDouble(),
            'product_quantity': _quantity,
            'total_price': totalPrice,
          });
          setState(() {
            _currentCartQuantity = _quantity;
            _addedToCart = true;
          });
        }
      }

      _successController.forward();
      await _updateCartCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
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
        setState(() => _addedToCart = false);
        _successController.reset();
      }
    } catch (e) {
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

      final totalCount =
      data.fold<int>(0, (sum, item) => sum + (item['product_quantity'] as int? ?? 0));
      cartCountNotifier.value = totalCount;
    } catch (_) {}
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
          iconTheme: const IconThemeData(color: Colors.white), // 👈 arrow white
          title: const Text(
            'Loading...',
            style: TextStyle(
              color: Colors.white, // 👈 title white
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: kPrimaryColor),
              SizedBox(height: 16),
              Text('Loading product details...'),
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
          iconTheme: const IconThemeData(color: Colors.white), // 👈 arrow white
          title: const Text(
            'Product Not Found',
            style: TextStyle(
              color: Colors.white, // 👈 title white
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
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
        iconTheme: const IconThemeData(color: Colors.white), // 👈 arrow white
        title: Text(
          _product!['product_name'] ?? 'Product',
          style: const TextStyle(
            color: Colors.white, // 👈 title white
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        // ❌ centerTitle removed → left aligned (default on Android)
      ),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScrollConfiguration(
              behavior: const _NoGlowBouncingBehavior(), // 👈 removes glow + keeps bounce
              child: SafeArea(
                bottom: true,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), // 👈 fixed bottom padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCompactProductImage(),
                      const SizedBox(height: 16),
                      _buildServiceSelection(),
                      const SizedBox(height: 16),
                      _buildProductInfo(),
                      const SizedBox(height: 20),
                      _buildQuantityAndPrice(),
                      const SizedBox(height: 20),
                      _buildCompactAddButton(), // 👈 scrolls with content and settles nicely
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      // ⛔️ No bottomNavigationBar (CTA scrolls within content)
    );
  }



  // Image
  // Image (1:1 square, no extra space)
  Widget _buildCompactProductImage() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Container(
            width: double.infinity, // takes full width available
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
              child: AspectRatio(
                aspectRatio: 1, // 👈 forces a perfect square (1:1)
                child: Image.network(
                  _product!['image_url'] ?? '',
                  fit: BoxFit.cover,      // 👈 fills the square (no gaps)
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey.shade50,
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.grey.shade400,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  // Product info / service description
  Widget _buildProductInfo() {
    final singleItemPrice = (_product!['product_price'] ?? 0) + _selectedServicePrice;

    final selectedService = _services.firstWhere(
          (s) => s['name'] == _selectedService,
      orElse: () => {
        'service_full_description': 'No description available',
        'tag': '',
        'service_description': '',
        'id': ''
      },
    );

    final selectedServiceDesc =
        selectedService['service_full_description'] ?? 'No description available';
    final serviceDescription = selectedService['service_description'] ?? '';

    // Check if current selected service is recommended
    final selectedServiceId = selectedService['id'] ?? '';
    final isCurrentServiceRecommended = _isRecommendedService(selectedServiceId);

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
          // Top row with price on left, tag on right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Price container (left side)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.currency_rupee, size: 14, color: kPrimaryColor),
                    Text(
                      '$singleItemPrice',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              // RECOMMENDED or Service Tag (right side) — compact
              if (isCurrentServiceRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Recommended',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                )
              else if (selectedService['tag'] != null &&
                  selectedService['tag'].isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    selectedService['tag'],
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (serviceDescription.isNotEmpty)
            Text(
              serviceDescription,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            selectedServiceDesc,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }



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
              child: Text('Loading services...', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
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
              final String name = (service['name'] ?? '').toString();
              final int price = (service['price'] as num?)?.toInt() ?? 0; // ✅ ensure int
              final bool selected = _selectedService == name;

              return Container(
                margin: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedService = name;
                    _selectedServicePrice = price; // ✅ use int
                    _fetchCurrentCartQuantity();
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


  // Quantity & total
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
                          if (_quantity > 0) _quantity--; // ✅ stops at 0
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _quantity > 0 ? kPrimaryColor : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.remove,
                            color: _quantity > 0 ? Colors.white : Colors.grey.shade600,
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
                          style: const TextStyle(
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
                          decoration: const BoxDecoration(
                            color: kPrimaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 16),
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
                  Text('Total', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(
                    '₹$totalPrice',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
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

  // Bottom CTA
  Widget _buildCompactAddButton() {
    final bool hasChanged = _currentCartQuantity != _quantity;
    final bool isInCart = _currentCartQuantity > 0;

    return AnimatedBuilder(
      animation: Listenable.merge([_buttonController, _successController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _addedToCart ? _successScale.value : _buttonScale.value,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isAddingToCart || !hasChanged) ? null : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                _addedToCart ? Colors.green : (hasChanged ? kPrimaryColor : Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: _addedToCart ? 6 : (hasChanged ? 3 : 1),
                shadowColor:
                _addedToCart ? Colors.green.withOpacity(0.3) : kPrimaryColor.withOpacity(0.3),
              ),
              child: _isAddingToCart
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
                        : (hasChanged ? (isInCart ? 'Update Cart' : 'Add to Cart') : 'No Changes'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
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

// 👇 iOS-like bounce & no-glow behavior for this screen
class _NoGlowBouncingBehavior extends ScrollBehavior {
  const _NoGlowBouncingBehavior();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child; // disables glow, keeps bounce
  }
}
