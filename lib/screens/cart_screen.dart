import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';
import 'review_cart_screen.dart';
import '../utils/globals.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = true;
  bool _isClearingCart = false;

  // Individual item loading states
  Map<String, bool> _itemLoadingStates = {};

  // Animation controllers
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

  // Simplified cart loading logic
  Future<void> _loadCart() async {
    print('🛒 Loading cart...');
    final user = supabase.auth.currentUser;
    if (user == null) {
      print('❌ No user found');
      setState(() {
        _cartItems = [];
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
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      print('📦 Cart response: $response');
      setState(() {
        _cartItems = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      await _updateGlobalCartCount();
      print('✅ Cart loaded: ${_cartItems.length} items');

    } catch (e) {
      print('❌ Error loading cart: $e');
      setState(() {
        _cartItems = [];
        _isLoading = false;
      });
      _showSnackBar('Failed to load cart', Colors.red);
      _updateGlobalCartCount();
    }
  }

  // Update global cart count
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
          .eq('user_id', user.id);

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

  // Calculate total cart value
  double get totalCartValue {
    return _cartItems.fold(0.0, (sum, item) => sum + ((item['total_price'] ?? 0).toDouble()));
  }

  // Clear entire cart
  Future<void> _clearCart() async {
    final confirmed = await _showClearCartDialog();
    if (!confirmed) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() {
        _isClearingCart = true;
      });

      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      setState(() {
        _cartItems.clear();
        _isClearingCart = false;
      });

      await _updateGlobalCartCount();
      _showSnackBar('Cart cleared successfully', Colors.green);

    } catch (e) {
      print('❌ Error clearing cart: $e');
      setState(() {
        _isClearingCart = false;
      });
      _showSnackBar('Failed to clear cart', Colors.red);
    }
  }

  // Show clear cart confirmation dialog
  Future<bool> _showClearCartDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Clear Cart?'),
          ],
        ),
        content: Text('Are you sure you want to remove all items from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  // Update quantity with simplified logic - NO ANIMATIONS OR SNACKBARS
  Future<void> _updateQuantity(Map<String, dynamic> item, int delta) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final itemId = item['id'].toString();
    final currentQuantity = item['product_quantity'] as int;
    final newQuantity = currentQuantity + delta;

    print('🔄 Updating quantity for ${item['product_name']} by $delta');

    if (newQuantity <= 0) {
      await _removeItem(item);
      return;
    }

    try {
      setState(() {
        _itemLoadingStates[itemId] = true;
      });

      final unitPrice = (item['product_price'] ?? 0).toDouble() +
          (item['service_price'] ?? 0).toDouble();
      final newTotalPrice = newQuantity * unitPrice;

      await supabase
          .from('cart')
          .update({
        'product_quantity': newQuantity,
        'total_price': newTotalPrice,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', item['id']);

      // Update local state immediately - NO ANIMATIONS
      setState(() {
        final itemIndex = _cartItems.indexWhere((cartItem) => cartItem['id'] == item['id']);
        if (itemIndex != -1) {
          _cartItems[itemIndex]['product_quantity'] = newQuantity;
          _cartItems[itemIndex]['total_price'] = newTotalPrice;
        }
        _itemLoadingStates.remove(itemId);
      });

      await _updateGlobalCartCount();
      // REMOVED GREEN SNACKBAR

    } catch (e) {
      print('❌ Error updating quantity: $e');
      setState(() {
        _itemLoadingStates.remove(itemId);
      });
      _showSnackBar('Failed to update quantity', Colors.red);
    }
  }

  // Remove single item - NO ANIMATIONS OR SNACKBARS
  Future<void> _removeItem(Map<String, dynamic> item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('cart')
          .delete()
          .eq('id', item['id']);

      // Remove item immediately without animation
      setState(() {
        _cartItems.removeWhere((cartItem) => cartItem['id'] == item['id']);
      });

      await _updateGlobalCartCount();
      // REMOVED ORANGE SNACKBAR

    } catch (e) {
      print('❌ Error removing item: $e');
      _showSnackBar('Failed to remove item', Colors.red);
    }
  }

  // Proceed to checkout
  void _onProceedPressed() {
    if (_isLoading) {
      _showSnackBar("Cart is still loading...", Colors.orange);
      return;
    }

    if (_cartItems.isEmpty) {
      _showSnackBar("Your cart is empty!", Colors.red);
      return;
    }

    print('🚀 Proceeding to checkout with ${_cartItems.length} items');
    print('💰 Total value: ₹${totalCartValue.toStringAsFixed(2)}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewCartScreen(
          cartItems: List<Map<String, dynamic>>.from(_cartItems),
          subtotal: totalCartValue,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green ? Icons.check_circle :
              color == Colors.red ? Icons.error :
              color == Colors.orange ? Icons.warning : Icons.info,
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
              : _cartItems.isEmpty
              ? _buildEmptyState()
              : Column(
            children: [
              // Swipe hint
              if (_cartItems.isNotEmpty) _buildSwipeHint(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cartItems.length,
                  itemBuilder: (context, index) {
                    // REMOVED ANIMATION CONTAINER
                    return _buildDismissibleCartItem(_cartItems[index]);
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

  Widget _buildSwipeHint() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.1), Colors.red.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.swipe, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text(
            "Swipe left on any item to remove it",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Spacer(),
          Icon(Icons.delete_sweep, color: Colors.red.withOpacity(0.7), size: 18),
        ],
      ),
    );
  }

  Widget _buildDismissibleCartItem(Map<String, dynamic> item) {
    return Dismissible(
      key: Key(item['id'].toString()),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        _removeItem(item);
      },
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Remove Item?'),
            content: Text('Remove "${item['product_name']}" from your cart?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Remove', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ?? false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.withOpacity(0.8), Colors.red],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      child: _buildCartItem(item),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
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
      // REMOVED CART ICON FROM TITLE
      title: const Text(
        "My Cart",
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      actions: [
        // Clear cart button
        if (_cartItems.isNotEmpty)
          IconButton(
            onPressed: _isClearingCart ? null : _clearCart,
            icon: _isClearingCart
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.delete_sweep, color: Colors.white),
            tooltip: 'Clear Cart',
          ),
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
    final itemId = item['id'].toString();
    final isItemLoading = _itemLoadingStates[itemId] ?? false;

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

            // Compact Quantity Controls
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isItemLoading
                      ? [Colors.grey.shade400, Colors.grey.shade300]
                      : [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isItemLoading
                        ? Colors.grey.withOpacity(0.3)
                        : kPrimaryColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQuantityButton(
                    icon: Icons.remove,
                    onTap: () => _updateQuantity(item, -1),
                    isLoading: isItemLoading,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: isItemLoading
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : Text(
                      '${item['product_quantity']}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _buildQuantityButton(
                    icon: Icons.add,
                    onTap: () => _updateQuantity(item, 1),
                    isLoading: isItemLoading,
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
    required bool isLoading,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 16,
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