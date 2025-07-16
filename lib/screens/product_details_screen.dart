import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import 'colors.dart';
import 'order_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String productId; // ✅ Changed from int to String
  const ProductDetailsScreen({Key? key, required this.productId}) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _services = [];
  int _quantity = 1;
  String _selectedService = '';
  int _selectedServicePrice = 0;
  bool _addedToCart = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _fetchProductDetails();
    _fetchServices();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.9,
      upperBound: 1.1,
      vsync: this,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.reverse();
      }
    });
  }

  Future<void> _fetchProductDetails() async {
    final response = await supabase
        .from('products')
        .select('*, categories (name)')
        .eq('id', widget.productId)
        .maybeSingle();

    if (response != null) {
      setState(() {
        _product = response;
      });
    }
  }

  Future<void> _fetchServices() async {
    final response = await supabase
        .from('services')
        .select()
        .eq('is_active', true)
        .order('sort_order');

    final serviceList = List<Map<String, dynamic>>.from(response);
    setState(() {
      _services = serviceList;
      if (_services.isNotEmpty) {
        _selectedService = _services[0]['name'];
        _selectedServicePrice = _services[0]['price'];
      }
    });
  }

  Future<void> _addToCart() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) return;

    final basePrice = _product!['product_price'] ?? 0;
    final total = (basePrice + _selectedServicePrice) * _quantity;

    await supabase.from('cart').insert({
      'id': user.id,
      'product_name': _product!['product_name'],
      'product_price': basePrice,
      'product_image': _product!['image_url'],
      'product_quantity': _quantity,
      'category': _product!['categories']?['name'] ?? 'General',
      'service_type': _selectedService,
      'service_price': _selectedServicePrice,
      'total_price': total,
    });

    cartCountNotifier.value++;
    setState(() => _addedToCart = true);
    _animationController.forward(from: 0.0);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OrdersScreen()),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_product == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final double tileWidth = MediaQuery.of(context).size.width / 3 - 24;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        title: Text(_product!['product_name'] ?? 'Product'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _product!['image_url'] ?? '',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                _product!['description'] ??
                    'This item is made of premium fabric. Select your desired service and quantity to proceed.',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 20),
              const Text('Select Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _services.map((service) {
                  final name = service['name'];
                  final price = service['price'];
                  final selected = _selectedService == name;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedService = name;
                      _selectedServicePrice = price;
                    }),
                    child: Container(
                      width: tileWidth,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? kPrimaryColor : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? kPrimaryColor : Colors.grey.shade300,
                        ),
                        boxShadow: selected
                            ? [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                            : [],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '+ ₹$price',
                            style: TextStyle(
                              color: selected ? Colors.white70 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              const Text('Select Quantity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: kPrimaryColor),
                    onPressed: () => setState(() {
                      if (_quantity > 1) _quantity--;
                    }),
                  ),
                  Text('$_quantity', style: const TextStyle(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: kPrimaryColor),
                    onPressed: () => setState(() => _quantity++),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: ScaleTransition(
                  scale: _animationController,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    onPressed: _addToCart,
                    child: Text(
                      _addedToCart ? 'Added' : 'Add to Cart',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
