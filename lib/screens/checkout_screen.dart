import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'colors.dart';
import 'package:ironly/widgets/success_animation_screen.dart';
import 'address_book_screen.dart';
import 'package:intl/intl.dart';
import 'delivery_slot_selector_screen.dart';


class CheckoutScreen extends StatefulWidget {
  final double subtotal;
  const CheckoutScreen({super.key, required this.subtotal});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

Map<String, String> serviceColorMap = {};

Future<void> fetchServiceColors() async {
  try {
    final result = await Supabase.instance.client
        .from('services')
        .select('name, color_hex');

    for (final item in result) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final colorHex = item['color_hex']?.toString();
      if (name.isNotEmpty && colorHex != null && colorHex.isNotEmpty) {
        serviceColorMap[name] = colorHex;
      }
    }
  } catch (e) {
    debugPrint("Error fetching service colors: $e");
  }
}


Color getServiceTypeColor(String? name) {
  final hex = serviceColorMap[name?.toLowerCase() ?? ''];
  return (hex != null && hex.isNotEmpty)
      ? HexColor.fromHexColor(hex)
      : Colors.grey;
}


class HexColor extends Color {
  HexColor(final int hexColor) : super(hexColor);

  static int fromHex(String hex) {
    hex = hex.replaceAll("#", "").toUpperCase();
    if (hex.length == 6) hex = "FF$hex"; // Add alpha if not present
    return int.parse(hex, radix: 16);
  }

  static Color fromHexColor(String hex) {
    return Color(fromHex(hex));
  }
}


class _CheckoutScreenState extends State<CheckoutScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  String _selectedPayment = 'Pay on Delivery';
  final TextEditingController _promoCodeController = TextEditingController();
  double discount = 0.0;
  late Razorpay _razorpay;

  late AnimationController _buttonAnimController;
  late Animation<Color?> _buttonColorAnimation;
  bool _isPlacingOrder = false;

  List<Map<String, dynamic>> cartItems = [];
  bool _cartLoading = true;
  Map<String, dynamic>? _selectedAddress;
  String _selectedDeliveryType = 'Express';






  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _buttonColorAnimation = ColorTween(
      begin: kPrimaryColor,
      end: Colors.white,
    ).animate(_buttonAnimController);

    _fetchCartItems();
    _fetchDefaultAddress();
  }
  Future<void> _fetchCartItems() async {
    setState(() => _cartLoading = true);

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final List data = await supabase
          .from('cart')
          .select()
          .eq('id', userId); // ✅ make sure 'user_id' is your correct column

      final rawItems = data.map((item) => Map<String, dynamic>.from(item)).toList();
      final Map<String, Map<String, dynamic>> grouped = {};

      for (var item in rawItems) {
        final key = "${item['product_name']}_${item['service_type']}";
        if (grouped.containsKey(key)) {
          grouped[key]!['product_quantity'] += item['product_quantity'];
          grouped[key]!['total_price'] += item['total_price'];
        } else {
          grouped[key] = Map<String, dynamic>.from(item);
        }
      }

      setState(() {
        cartItems = grouped.values.toList();
        _cartLoading = false;
      });

    } catch (e, st) {
      debugPrint("Cart Fetch Error: $e\n$st");
      setState(() {
        cartItems = [];
        _cartLoading = false;
      });
    }
  }

  IconData getAddressIcon(String? title) {
    switch (title?.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      default:
        return Icons.location_on;
    }
  }

  Color getAddressColor(String? title) {
    switch (title?.toLowerCase()) {
      case 'home':
        return Colors.blue;
      case 'work':
        return Colors.deepPurple;
      default:
        return Colors.orange;
    }
  }


  @override
  void dispose() {
    _razorpay.clear();
    _promoCodeController.dispose();
    _buttonAnimController.dispose();
    super.dispose();
  }



  // CART POPUP using showDialog (safe, null-checked)
  void _showCartPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 18, top: 16, bottom: 8),
                        child: Text(
                          "Cart Details",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 0),
                  if (_cartLoading)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    )
                  else if (cartItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('No items in cart.'),
                    )
                  else
                    SizedBox(
                      height: (cartItems.length * 62).clamp(62, 300).toDouble(),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: cartItems.length,
                        itemBuilder: (context, i) {
                          final item = cartItems[i];
                          final imageUrl = item['product_image'];
                          final name = item['product_name']?.toString() ?? "Item";
                          final qty = item['product_quantity']?.toString() ?? "1";
                          final price = item['total_price'];
                          final serviceType = item['service_type']?.toString() ?? "";

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: (imageUrl is String && imageUrl.isNotEmpty)
                                  ? Image.network(
                                imageUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (context, err, st) => const Icon(Icons.image, size: 36),
                              )
                                  : const Icon(Icons.image, size: 36),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(name, style: const TextStyle(fontSize: 14)),
                                ),
                                if (serviceType.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: getServiceTypeColor(serviceType).withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: getServiceTypeColor(serviceType),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Text(
                                      serviceType,
                                      style: TextStyle(
                                        color: getServiceTypeColor(serviceType),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),

                                  ),
                              ],
                            ),
                            subtitle: Text("Qty: $qty", style: const TextStyle(fontSize: 13)),
                            trailing: Text(
                              "₹${price != null ? price.toString() : "--"}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Main tap handler: starts looping animation, then logic, then stop
  Future<void> _onButtonPressed() async {
    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a delivery address."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedDate == null || _selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a delivery date and time slot."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isPlacingOrder) return;
    setState(() => _isPlacingOrder = true);

    _buttonAnimController.repeat(reverse: true);

    if (_selectedPayment == 'Online (UPI/Card)') {
      await Future.delayed(const Duration(milliseconds: 900));
      _openRazorpay();
      _buttonAnimController.reset();
      setState(() => _isPlacingOrder = false);
    } else {
      await _placeOrderInSupabase();
      _buttonAnimController.reset();
      setState(() => _isPlacingOrder = false);
    }
  }

  void _openRazorpay() {
    final values = _calculateValues();
    var options = {
        'key': 'rzp_test_rlTCKVx6XrfqtS',
      'amount': (values['total']! * 100).toInt(),
      'name': 'IronXpress',
      'description': 'Ironing Service Payment',
      'prefill': {
        'contact': '8888888888',
        'email': 'test@ironxpress.com',
      },
      'theme': {
        'color': '#007BFF',
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Razorpay Error: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint("Payment Success: ${response.paymentId}");
    _placeOrderInSupabase(paymentId: response.paymentId);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint("Payment Failed: ${response.message}");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Payment failed. Please try again."),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint("External Wallet: ${response.walletName}");
  }

  Future<void> _placeOrderInSupabase({String? paymentId}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final values = _calculateValues();

    try {
      await supabase.from('orders').insert({
        'user_id': user.id,
        'payment_method': _selectedPayment,
        'payment_id': paymentId ?? 'CashOnDelivery',
        'subtotal': values['originalSubtotal'],
        'minimum_cart_fee': values['minimumCartFee'],
        'platform_fee': values['platformFee'],
        'service_tax': values['serviceTax'],
        'delivery_fee': values['deliveryFee'],
        'delivery_address': {
          'name': _selectedAddress?['contact_name'],
          'phone': _selectedAddress?['phone'],
          'address_line': _selectedAddress?['street'],
          'city': _selectedAddress?['city'],
          'state': _selectedAddress?['state'],
          'pincode': _selectedAddress?['zip_code'],
        },
        'discount': discount,
        'total': values['total'],
        'status': 'Placed',
      });

      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SuccessAnimationScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Order Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to place order. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyPromoCode() {
    final code = _promoCodeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    setState(() {
      if (code == 'iron10') {
        discount = 10.0;
        _promoCodeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✔️ Promo Applied'), backgroundColor: Colors.green),
        );
      } else if (code == 'iron50') {
        discount = 50.0;
        _promoCodeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✔️ Promo Applied'), backgroundColor: Colors.green),
        );
      } else {
        discount = 0.0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid Promo Code'),
            backgroundColor: Colors.redAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Map<String, double> _calculateValues() {
    final originalSubtotal = widget.subtotal;
    double subtotal = originalSubtotal;
    double minimumCartFee = 0.0;

    if (subtotal < 100.0) {
      minimumCartFee = 100.0 - subtotal;
      subtotal = 100.0;
    }

    const double platformFee = 7.0;
    const double deliveryFee = 15.0;
    final double serviceTax = subtotal * 0.18;

    double total = subtotal + platformFee + deliveryFee + serviceTax + minimumCartFee - discount;
    if (total < 0) total = 0;

    return {
      'originalSubtotal': originalSubtotal,
      'minimumCartFee': minimumCartFee,
      'platformFee': platformFee,
      'deliveryFee': deliveryFee,
      'serviceTax': serviceTax,
      'total': total,
    };
  }

  Widget _buildPaymentSelector() {
    List<String> methods = ['Pay on Delivery', 'Online (UPI/Card)'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: methods.map((method) {
        bool isSelected = _selectedPayment == method;
        return GestureDetector(
          onTap: () => setState(() => _selectedPayment = method),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            width: MediaQuery.of(context).size.width * 0.42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: isSelected
                  ? LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)])
                  : LinearGradient(colors: [Colors.grey.shade200, Colors.grey.shade100]),
              boxShadow: isSelected
                  ? [BoxShadow(color: kPrimaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
                  : [],
              border: Border.all(
                color: isSelected ? kPrimaryColor : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  method == 'Pay on Delivery' ? Icons.money : Icons.credit_card,
                  color: isSelected ? Colors.white : kPrimaryColor,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  method,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _fetchDefaultAddress() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final List data = await supabase
        .from('user_addresses')
        .select()
        .eq('user_id', userId)
        .eq('is_default', true)
        .limit(1);

    if (data.isNotEmpty) {
      setState(() {
        _selectedAddress = data.first;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final values = _calculateValues();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: kPrimaryColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 👇 Inside your build() method, right before the "Select Payment Method" section
            _selectedAddress != null
                ? Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50, // ✅ Matches 'No address selected' tile
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.location_on_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🏷️ Type Badge (Home, Work, Other)
                        if (_selectedAddress!['title'] != null && _selectedAddress!['title'].toString().isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                _selectedAddress!['title'].toString().toLowerCase() == 'home'
                                    ? Icons.home_rounded
                                    : _selectedAddress!['title'].toString().toLowerCase() == 'work'
                                    ? Icons.work_rounded
                                    : Icons.location_city_rounded,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _selectedAddress!['title'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedAddress!['contact_name'] ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          "${_selectedAddress!['street']}, ${_selectedAddress!['city']}",
                          style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        Text(
                          "${_selectedAddress!['state']} - ${_selectedAddress!['zip_code']}",
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      final selected = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddressBookScreen(selectMode: true),
                        ),
                      );
                      if (selected != null && selected is Map<String, dynamic>) {
                        setState(() => _selectedAddress = selected);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_location_alt_rounded,
                        size: 24,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            )
                : GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddressBookScreen(selectMode: true)),
                ).then((selected) {
                  if (selected != null && selected is Map<String, dynamic>) {
                    setState(() {
                      _selectedAddress = selected;
                    });
                  } else {
                    _fetchDefaultAddress();
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.add_location_alt_rounded, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "No delivery address found.\nTap here to add or select one.",
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),


            const Text('Select Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildPaymentSelector(),
            const SizedBox(height: 24),
            const Text('Delivery Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDeliveryTypeSelector(),
            _buildDatePicker(),
            const SizedBox(height: 24),


            const Text('Promo Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promoCodeController,
                    decoration: InputDecoration(
                      hintText: 'Enter code',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _applyPromoCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
            const Divider(height: 32),

            // Subtotal Row with Info Icon and Cart Popup
            _buildSubtotalRow(values['originalSubtotal']!.toStringAsFixed(2)),

            if (values['minimumCartFee']! > 0)
              _buildBillTile('Minimum Cart Fee', '+ ₹${values['minimumCartFee']!.toStringAsFixed(2)}'),
            _buildBillTile('Platform Fee', '₹${values['platformFee']!.toStringAsFixed(2)}'),
            _buildBillTile('Service Tax (18%)', '₹${values['serviceTax']!.toStringAsFixed(2)}'),
            _buildBillTile('Delivery Fee', '₹${values['deliveryFee']!.toStringAsFixed(2)}'),
            _buildBillTile('Discount', '- ₹${discount.toStringAsFixed(2)}'),
            const Divider(height: 32),
            Card(
              color: kPrimaryColor.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildBillTile('Total', '₹${values['total']!.toStringAsFixed(2)}', isBold: true),
              ),
            ),
            const SizedBox(height: 24),
            // ---- ANIMATED BUTTON BELOW ----
            AnimatedBuilder(
              animation: _buttonAnimController,
              builder: (context, child) {
                Color mainColor = (_isPlacingOrder)
                    ? (_buttonColorAnimation.value ?? kPrimaryColor)
                    : kPrimaryColor;
                Color secondaryColor = (_isPlacingOrder)
                    ? (mainColor == kPrimaryColor ? Colors.white : kPrimaryColor)
                    : kPrimaryColor;

                return GestureDetector(

                  onTap: _isPlacingOrder ? null : _onButtonPressed,
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(
                        colors: [mainColor, secondaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _selectedPayment == 'Online (UPI/Card)' ? 'Pay Now' : 'Place Order',
                        style: TextStyle(
                          fontSize: 16,
                          color: (_isPlacingOrder)
                              ? (mainColor == kPrimaryColor ? Colors.white : kPrimaryColor)
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // ---- END ANIMATED BUTTON ----
          ],
        ),
      ),
    );
  }

  Widget _buildSubtotalRow(String subtotalValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('Subtotal', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18, color: Colors.blueAccent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _cartLoading ? null : _showCartPopup,
              ),
            ],
          ),
          Text('₹$subtotalValue',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
        ],
      ),
    );
  }

  // --- Delivery Type & Date ---
  String _selectedType = 'Standard';
  DateTime? _selectedDate;
  Map<String, dynamic>? _selectedSlot;

  Widget _buildDeliveryTypeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.blue, width: 2), // Blue border around toggle
      ),
      child: Stack(
        children: [
          // Sliding background (blue background)
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: _selectedDeliveryType == 'Express'
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: MediaQuery.of(context).size.width / 2 - 8,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.blue, // Blue active color for selected tab
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          Row(
            children: ['Express', 'Standard'].map((type) {
              final isSelected = _selectedDeliveryType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedDeliveryType = type;
                  }),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    child: Text(
                      type,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? Colors.white : Colors.blue, // Text color change on selection
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }


  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Schedule your Pickup', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 6)),
              builder: (context, child) => Theme(data: ThemeData.light().copyWith(primaryColor: kPrimaryColor), child: child!),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
              final slot = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeliverySlotSelectorScreen(
                    deliveryType: _selectedType,
                    selectedDate: picked,
                  ),
                ),
              );
              if (slot != null) {
                setState(() => _selectedSlot = slot);
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDate != null
                      ? DateFormat('EEE, MMM d').format(_selectedDate!)
                      : 'Tap to pick date',
                  style: TextStyle(color: _selectedDate != null ? Colors.black : Colors.grey),
                ),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
        if (_selectedSlot != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              "Pickup: ${_selectedSlot!['pickup_slot']}  ➝  Delivery: ${_selectedSlot!['delivery_slot']} ${_selectedSlot!['is_next_day'] == true ? '(Next Day)' : ''}",
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }


  Widget _buildBillTile(String title, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
