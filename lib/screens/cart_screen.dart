import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import 'review_cart_screen.dart';
import '../utils/globals.dart'; // ✅ Added for global cart count

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _groupedItems = [];
  bool _isLoading = true;

  // ✅ Animation controllers for premium UI
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadCart();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  // ✅ FIXED: Updated to use user_id instead of id
  Future<void> _loadCart() async {
    print('🛒 Loading cart...');
    final user = supabase.auth.currentUser;
    if (user == null) {
      print('❌ No user found');
      setState(() {
        _groupedItems = [];
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final response = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id) // ✅ Fixed: Changed from 'id' to 'user_id'
          .order('created_at');

      print('📦 Cart response: $response');
      final rawItems = List<Map<String, dynamic>>.from(response);

      final Map<String, Map<String, dynamic>> groupedMap = {};
      for (var item in rawItems) {
        final key = "${item['product_name']}|${item['product_image']}|${item['service_type']}|${item['product_price']}|${item['service_price']}";
        if (groupedMap.containsKey(key)) {
          groupedMap[key]!['product_quantity'] += item['product_quantity'];
          groupedMap[key]!['total_price'] += item['total_price'];
          // Store multiple cart IDs for proper deletion
          if (groupedMap[key]!['cart_ids'] == null) {
            groupedMap[key]!['cart_ids'] = [groupedMap[key]!['id']];
          }
          groupedMap[key]!['cart_ids'].add(item['id']);
        } else {
          final newItem = Map<String, dynamic>.from(item);
          newItem['cart_ids'] = [item['id']]; // Store cart ID for deletion
          groupedMap[key] = newItem;
        }
      }

      setState(() {
        _groupedItems = groupedMap.values.toList();
        _isLoading = false;
      });

      // ✅ Update global cart count
      await _updateGlobalCartCount();
      print('✅ Cart loaded: ${_groupedItems.length} unique items');

    } catch (e) {
      print('❌ Error loading cart: $e');
      setState(() {
        _groupedItems = [];
        _isLoading = false;
      });
      _updateGlobalCartCount();
    }
  }

  // ✅ Update global cart count for app-wide sync
  Future<void> _updateGlobalCartCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      cartCountNotifier.value = 0;
      return;
    }

    try {
      final response = await supabase
          .from('cart')
          .select('product_quantity')
          .eq('user_id', user.id); // ✅ Fixed: Changed from 'id' to 'user_id'

      final items = List<Map<String, dynamic>>.from(response);
      final totalCount = items.fold<int>(
        0,
            (sum, item) => sum + (item['product_quantity'] as int? ?? 0),
      );

      cartCountNotifier.value = totalCount;
      print('🔢 Global cart count updated: $totalCount');
    } catch (e) {
      print('❌ Error updating cart count: $e');
      cartCountNotifier.value = 0;
    }
  }

  double get totalCartValue {
    return _groupedItems.fold(0.0, (sum, item) => sum + ((item['total_price'] ?? 0).toDouble()));
  }

  void _onProceedPressed() {
    if (_isLoading) {
      _showSnackBar("Cart is still loading...", Colors.orange);
      return;
    }

    if (_groupedItems.isEmpty) {
      _showSnackBar("Your cart is empty!", Colors.red);
      return;
    }

    print('🚀 Proceeding to checkout with ${_groupedItems.length} items');
    print('💰 Total value: ₹${totalCartValue.toStringAsFixed(2)}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewCartScreen(
          cartItems: List<Map<String, dynamic>>.from(_groupedItems),
          subtotal: totalCartValue,
        ),
      ),
    );
  }

  // ✅ COMPLETELY REWRITTEN: Fixed quantity update logic
  Future<void> _updateQuantity(Map<String, dynamic> item, int delta) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    print('🔄 Updating quantity for ${item['product_name']} by $delta');

    try {
      // Show loading state
      setState(() {
        _isLoading = true;
      });

      // Get current quantity
      final currentQuantity = item['product_quantity'] as int;
      final newQuantity = currentQuantity + delta;

      print('📊 Current: $currentQuantity, New: $newQuantity');

      // Get all cart items that match this product
      final response = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id) // ✅ Fixed: Changed from 'id' to 'user_id'
          .eq('product_name', item['product_name'])
          .eq('service_type', item['service_type'])
          .eq('product_price', item['product_price'])
          .eq('service_price', item['service_price']);

      final matchingItems = List<Map<String, dynamic>>.from(response);
      print('🔍 Found ${matchingItems.length} matching cart items');

      // Delete all existing items of this type
      for (var cartItem in matchingItems) {
        await supabase
            .from('cart')
            .delete()
            .eq('id', cartItem['id']);
      }
      print('🗑️ Deleted existing items');

      // If new quantity is positive, insert new item
      if (newQuantity > 0) {
        final unitPrice = (item['product_price'] ?? 0).toDouble() + (item['service_price'] ?? 0).toDouble();
        final newTotalPrice = newQuantity * unitPrice;

        await supabase.from('cart').insert({
          'user_id': user.id, // ✅ Fixed: Changed from 'id' to 'user_id'
          'product_name': item['product_name'],
          'product_image': item['product_image'],
          'product_price': item['product_price'],
          'service_type': item['service_type'],
          'service_price': item['service_price'],
          'product_quantity': newQuantity,
          'total_price': newTotalPrice,
          'created_at': DateTime.now().toIso8601String(),
        });
        print('✅ Inserted new item with quantity: $newQuantity');
      }

      // Reload cart and update global count
      await _loadCart();

      // Show success feedback
      _showSnackBar(
        newQuantity <= 0
            ? 'Item removed from cart'
            : 'Quantity updated to $newQuantity',
        newQuantity <= 0 ? Colors.red : Colors.green,
      );

    } catch (e) {
      print('❌ Error updating quantity: $e');
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to update quantity', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green ? Icons.check_circle :
              color == Colors.red ? Icons.error : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FC),
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: _isLoading
              ? _buildLoadingState()
              : _groupedItems.isEmpty
              ? _buildEmptyState()
              : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groupedItems.length,
                  itemBuilder: (context, index) {
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 300 + (index * 100)),
                      curve: Curves.easeOutCubic,
                      child: _buildCartItem(_groupedItems[index]),
                    );
                  },
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor.withOpacity(0.2), kPrimaryColor.withOpacity(0.1)],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CircularProgressIndicator(
                color: kPrimaryColor,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Loading your cart...",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade200, Colors.grey.shade100],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_outlined,
              size: 60,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Your cart is empty!",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Add some items to get started",
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            child: const Text(
              "Continue Shopping",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kPrimaryColor.withOpacity(0.95),
              kPrimaryColor.withOpacity(0.85),
            ],
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
            child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            "My Cart",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _loadCart,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          tooltip: 'Refresh Cart',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Total Amount",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "₹${totalCartValue.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: _onProceedPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                elevation: 8,
                shadowColor: kPrimaryColor.withOpacity(0.3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    "Proceed",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Product Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.network(
                  item['product_image'] ?? '',
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.image_outlined,
                    size: 35,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['product_name'] ?? 'Unknown Product',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${item['service_type']} (+₹${item['service_price']})",
                      style: TextStyle(
                        fontSize: 13,
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "₹${item['total_price']}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Quantity Controls
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQuantityButton(
                    icon: Icons.remove,
                    onTap: () => _updateQuantity(item, -1),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '${item['product_quantity']}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _buildQuantityButton(
                    icon: Icons.add,
                    onTap: () => _updateQuantity(item, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }
}