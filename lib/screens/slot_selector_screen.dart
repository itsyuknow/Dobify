import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../widgets/notification_service.dart';
import 'colors.dart';
import 'address_book_screen.dart';
import 'order_success_screen.dart';

class SlotSelectorScreen extends StatefulWidget {
  final double totalAmount;
  final List<Map<String, dynamic>> cartItems;
  final String? appliedCouponCode;
  final double discount;

  const SlotSelectorScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
    this.appliedCouponCode,
    this.discount = 0.0,
  });

  @override
  State<SlotSelectorScreen> createState() => _SlotSelectorScreenState();
}

class _SlotSelectorScreenState extends State<SlotSelectorScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool isExpressDelivery = false;
  Map<String, dynamic>? selectedAddress;
  bool isServiceAvailable = true;
  bool isLoadingServiceAvailability = false;
  bool onlinePaymentEnabled = true;

  Map<String, dynamic>? selectedPickupSlot;
  Map<String, dynamic>? selectedDeliverySlot;

  List<Map<String, dynamic>> pickupSlots = [];
  List<Map<String, dynamic>> deliverySlots = [];
  bool isLoadingSlots = true;

  // Billing settings
  double minimumCartFee = 100.0;
  double platformFee = 0.0;
  double serviceTaxPercent = 0.0;
  double expressDeliveryFee = 0.0;
  double standardDeliveryFee = 0.0;
  bool isLoadingBillingSettings = true;
  bool _isBillingSummaryExpanded = false;
  double deliveryGstPercent = 0.0;      // % GST on delivery fee
  double freeStandardThreshold = 300.0;
  // free standard delivery threshold (after discount)


  Map<String, Map<String, String>> _billingNotes = {}; // {key: {title, content}}


  // Animation controllers
  late AnimationController _billingAnimationController;
  late Animation<double> _billingExpandAnimation;

  int currentStep = 0; // 0: pickup date/slot, 1: delivery date/slot

  DateTime selectedPickupDate = DateTime.now();
  DateTime selectedDeliveryDate = DateTime.now();
  final ScrollController _pickupDateScrollController = ScrollController();
  final ScrollController _deliveryDateScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();
  final GlobalKey _deliverySlotSectionKey = GlobalKey();
  final GlobalKey _paymentSectionKey = GlobalKey();
  late List<DateTime> pickupDates;
  late List<DateTime> deliveryDates;

  // Payment related variables
  String _selectedPaymentMethod = 'online'; // Default to online
  bool _isProcessingPayment = false;
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _loadBillingSettings();
    _loadSlots();
    _loadDefaultAddress();
    _initializeRazorpay();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _billingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _billingExpandAnimation = CurvedAnimation(
      parent: _billingAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pickupDateScrollController.dispose();
    _deliveryDateScrollController.dispose();
    _billingAnimationController.dispose();
    _mainScrollController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  // Initialize Razorpay
  void _initializeRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  // Razorpay Event Handlers
  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    print('✅ Payment Success: ${response.paymentId}');
    _processOrderCompletion(paymentId: response.paymentId);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print('❌ Payment Error: ${response.code} - ${response.message}');
    setState(() {
      _isProcessingPayment = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('🔄 External Wallet: ${response.walletName}');
  }

  void _initializeDates() {
    // Pickup dates: 7 days from today
    pickupDates = List.generate(7, (index) => DateTime.now().add(Duration(days: index)));

    // Delivery dates: Initially same as pickup, will be updated when pickup date is selected
    deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));
  }

  void _updateDeliveryDates() {
    // Delivery dates: 7 days starting from selected pickup date
    deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));

    // Ensure selected delivery date is not before pickup date
    if (selectedDeliveryDate.isBefore(selectedPickupDate)) {
      selectedDeliveryDate = selectedPickupDate;
    }
  }

  // NEW METHOD: Check if a specific date has available delivery slots
  bool _hasAvailableDeliverySlots(DateTime date) {
    int dayOfWeek = date.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == dayOfWeek ||
          (dayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && dayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    if (daySlots.isEmpty) return false;

    // Check if any slot would be available for this date
    for (var slot in daySlots) {
      // Create a temporary selected delivery date to test availability
      DateTime tempDeliveryDate = selectedDeliveryDate;
      setState(() {
        selectedDeliveryDate = date;
      });

      bool isAvailable = _isDeliverySlotAvailable(slot);

      // Restore original date
      setState(() {
        selectedDeliveryDate = tempDeliveryDate;
      });

      if (isAvailable) return true;
    }

    return false;
  }

  // NEW METHOD: Find next available delivery date
  DateTime? _findNextAvailableDeliveryDate() {
    for (int i = 0; i < deliveryDates.length; i++) {
      DateTime date = deliveryDates[i];
      if (_hasAvailableDeliverySlots(date)) {
        return date;
      }
    }
    return null;
  }

  // UPDATED METHOD: Filter delivery dates to only show those with available slots
  List<DateTime> _getAvailableDeliveryDates() {
    return deliveryDates.where((date) => _hasAvailableDeliverySlots(date)).toList();
  }

  Future<void> _loadBillingSettings() async {
    try {
      // 1) settings
      final response = await supabase.from('billing_settings').select().single();

      // 2) notes (include delivery_gst so the info icon can explain GST on delivery)
      final List<dynamic> notesResp = await supabase
          .from('billing_notes')
          .select()
          .or(
          'key.eq.minimum_cart_fee,'
              'key.eq.platform_fee,'
              'key.eq.service_tax,'
              'key.eq.delivery_standard,'
              'key.eq.delivery_standard_free,'
              'key.eq.delivery_express,'
              'key.eq.delivery_gst'
      );

      // 3) map to {key: {title, content}}
      final Map<String, Map<String, String>> notesMap = {
        for (final row in notesResp)
          (row['key'] as String): {
            'title': row['title']?.toString() ?? '',
            'content': row['content']?.toString() ?? '',
          }
      };

      final bool onlineEnabled = (response['online_payment_enabled'] ?? true) as bool;

      setState(() {
        minimumCartFee        = (response['minimum_cart_fee'] ?? 100).toDouble();
        platformFee           = (response['platform_fee'] ?? 0).toDouble();
        serviceTaxPercent     = (response['service_tax_percent'] ?? 0).toDouble();
        expressDeliveryFee    = (response['express_delivery_fee'] ?? 0).toDouble();
        standardDeliveryFee   = (response['standard_delivery_fee'] ?? 0).toDouble();
        deliveryGstPercent    = (response['delivery_gst_percent'] ?? 0).toDouble();
        freeStandardThreshold = (response['free_standard_threshold'] ?? 300).toDouble();

        onlinePaymentEnabled  = onlineEnabled;

        // If online is OFF but user had 'online' selected, force COD
        if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
          _selectedPaymentMethod = 'cod';
        }

        _billingNotes = notesMap;
        isLoadingBillingSettings = false;
      });
    } catch (e) {
      setState(() => isLoadingBillingSettings = false);
    }
  }





  Future<void> _loadSlots() async {
    try {
      final pickupResponse = await supabase
          .from('pickup_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      final deliveryResponse = await supabase
          .from('delivery_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      setState(() {
        pickupSlots = List<Map<String, dynamic>>.from(pickupResponse);
        deliverySlots = List<Map<String, dynamic>>.from(deliveryResponse);
        isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => isLoadingSlots = false);
    }
  }

  Future<void> _loadDefaultAddress() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .eq('is_default', true)
          .maybeSingle();
      if (response != null) {
        setState(() {
          selectedAddress = response;
        });
        _checkServiceAvailability(response['pincode']);
      }
    } catch (e) {}
  }

  Future<void> _checkServiceAvailability(String pincode) async {
    setState(() => isLoadingServiceAvailability = true);
    try {
      final response = await supabase
          .from('service_areas')
          .select()
          .eq('pincode', pincode)
          .eq('is_active', true)
          .maybeSingle();
      setState(() {
        isServiceAvailable = response != null;
        isLoadingServiceAvailability = false;
      });
    } catch (e) {
      setState(() {
        isServiceAvailable = false;
        isLoadingServiceAvailability = false;
      });
    }
  }

  // SAME DIALOG AS ReviewCartScreen
  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.blue.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.info_outline, color: kPrimaryColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  content,
                  style: const TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.35),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  // Calculate billing breakdown
  // Calculate billing breakdown (merged service taxes + free standard on discounted subtotal)
  Map<String, double> _calculateBilling() {
    // 1) Original subtotal from items
    final double itemSubtotal = widget.cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    // 2) Apply coupon/discount only on items subtotal
    final double discountApplied   = widget.discount.clamp(0.0, itemSubtotal);
    final double discountedSubtotal = itemSubtotal - discountApplied;

    // 3) Minimum cart fee (compare against ORIGINAL subtotal)
    final double minCartFeeApplied =
    itemSubtotal < minimumCartFee ? (minimumCartFee - itemSubtotal) : 0.0;

    // 4) Delivery fee (Standard can be free if discounted subtotal ≥ threshold)
    final bool isStandard = !isExpressDelivery;
    final bool qualifiesFreeStandard = isStandard && (discountedSubtotal >= freeStandardThreshold);
    final double deliveryFee = isStandard
        ? (qualifiesFreeStandard ? 0.0 : standardDeliveryFee)
        : expressDeliveryFee; // Express is never free

    // 5) Service taxes = (discountedSubtotal × serviceTax%) + (deliveryFee × deliveryGST%)
    final double serviceTaxItems    = (discountedSubtotal * serviceTaxPercent) / 100.0;
    final double serviceTaxDelivery = deliveryFee > 0 ? (deliveryFee * deliveryGstPercent) / 100.0 : 0.0;
    final double serviceTax         = serviceTaxItems + serviceTaxDelivery;

    // 6) Total = (Subtotal − Discount) + Min Cart + Platform + Delivery + Service Taxes
    double totalAmount = discountedSubtotal + minCartFeeApplied + platformFee + deliveryFee + serviceTax;
    if (totalAmount < 0) totalAmount = 0;

    return {
      'subtotal'       : itemSubtotal,
      'discount'       : discountApplied,
      'minimumCartFee' : minCartFeeApplied,
      'platformFee'    : platformFee,
      'deliveryFee'    : deliveryFee,
      'serviceTax'     : serviceTax,
      'totalAmount'    : totalAmount,
    };
  }



  double _calculateTotalAmount() {
    final billing = _calculateBilling();
    return billing['totalAmount']!;
  }

  // Save billing details to Supabase
  Future<void> _saveBillingDetails(String orderId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final billing = _calculateBilling();

      await supabase.from('order_billing_details').insert({
        'order_id': orderId,
        'user_id': user.id,
        'subtotal': billing['subtotal'],
        'minimum_cart_fee': billing['minimumCartFee'],
        'platform_fee': billing['platformFee'],
        'service_tax': billing['serviceTax'],
        'delivery_fee': billing['deliveryFee'],
        'express_delivery_fee': expressDeliveryFee,
        'standard_delivery_fee': standardDeliveryFee,
        'discount_amount': billing['discount'],
        'total_amount': billing['totalAmount'],
        'delivery_type': isExpressDelivery ? 'express' : 'standard',
        'applied_coupon_code': widget.appliedCouponCode,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving billing details: $e');
    }
  }

  void _onAddressSelected(Map<String, dynamic> address) {
    setState(() {
      selectedAddress = address;
    });
    _checkServiceAvailability(address['pincode']);
  }

  void _onPickupDateSelected(DateTime date) {
    setState(() {
      selectedPickupDate = date;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
      _updateDeliveryDates();
    });
  }

  void _onDeliveryDateSelected(DateTime date) {
    setState(() {
      selectedDeliveryDate = date;
      selectedDeliverySlot = null;
    });
  }

  // UPDATED METHOD: Auto-select next available delivery date when pickup is selected
  void _onPickupSlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedPickupSlot = slot;
      selectedDeliverySlot = null;
      currentStep = 1;
      // Update delivery dates based on pickup date
      _updateDeliveryDates();

      // Auto-select next available delivery date
      DateTime? nextAvailableDate = _findNextAvailableDeliveryDate();
      if (nextAvailableDate != null) {
        selectedDeliveryDate = nextAvailableDate;
      } else {
        selectedDeliveryDate = selectedPickupDate; // Fallback to pickup date
      }
    });

    // Auto-scroll to delivery slot section
    _autoScrollToDeliverySection();
  }

  void _onDeliverySlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedDeliverySlot = slot;
    });

    // Auto-scroll to payment section after delivery slot selection
    _autoScrollToPaymentSection();
  }

  // Scroll to delivery slot section
  void _autoScrollToDeliverySection() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_deliverySlotSectionKey.currentContext != null && _mainScrollController.hasClients) {
        final RenderBox renderBox = _deliverySlotSectionKey.currentContext!.findRenderObject() as RenderBox;
        final position = renderBox.localToGlobal(Offset.zero);
        final screenHeight = MediaQuery.of(context).size.height;

        // Calculate scroll position to center the delivery section
        double scrollOffset = _mainScrollController.offset + position.dy - (screenHeight * 0.2);

        _mainScrollController.animateTo(
          scrollOffset.clamp(0.0, _mainScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

// Scroll to payment section (scroll to bottom)
  void _autoScrollToPaymentSection() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_mainScrollController.hasClients) {
        _mainScrollController.animateTo(
          _mainScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _openAddressBook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressBookScreen(
          onAddressSelected: _onAddressSelected,
        ),
      ),
    );
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      List<String> parts = timeString.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return TimeOfDay(hour: 0, minute: 0);
    }
  }

  // Find which slot the current time falls into
  Map<String, dynamic>? _getCurrentTimeSlot(List<Map<String, dynamic>> slots) {
    final currentTime = TimeOfDay.now();

    for (var slot in slots) {
      final startTime = _parseTimeString(slot['start_time']);
      final endTime = _parseTimeString(slot['end_time']);

      if (_isTimeInRange(currentTime, startTime, endTime)) {
        return slot;
      }
    }
    return null;
  }

  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    int currentMinutes = current.hour * 60 + current.minute;
    int startMinutes = start.hour * 60 + start.minute;
    int endMinutes = end.hour * 60 + end.minute;

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  List<Map<String, dynamic>> _getAllPickupSlots() {
    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    int selectedDayOfWeek = selectedPickupDate.weekday;

    List<Map<String, dynamic>> daySlots = pickupSlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == selectedDayOfWeek ||
          (selectedDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && selectedDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    // Sort slots by time
    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  List<Map<String, dynamic>> _getFilteredPickupSlots() {
    List<Map<String, dynamic>> allSlots = _getAllPickupSlots();

    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    if (!isToday) {
      return allSlots;
    }

    // For today, filter based on current time and delivery type
    final currentTime = TimeOfDay.now();

    // Find the slot that current time falls into OR the last passed slot
    Map<String, dynamic>? currentSlot = _getCurrentTimeSlot(allSlots);
    int currentSlotIndex = -1;

    if (currentSlot != null) {
      // Find current slot index
      for (int i = 0; i < allSlots.length; i++) {
        if (allSlots[i]['id'] == currentSlot['id']) {
          currentSlotIndex = i;
          break;
        }
      }
    } else {
      // If no current slot found, find the last passed slot
      for (int i = allSlots.length - 1; i >= 0; i--) {
        final slotStart = _parseTimeString(allSlots[i]['start_time']);
        int currentMinutes = currentTime.hour * 60 + currentTime.minute;
        int slotMinutes = slotStart.hour * 60 + slotStart.minute;

        if (slotMinutes <= currentMinutes) {
          currentSlotIndex = i;
          break;
        }
      }
    }

    // If no slot found or before all slots, start from beginning with logic
    if (currentSlotIndex == -1) {
      // Apply delivery type logic from the beginning
      if (isExpressDelivery) {
        // Express: show all future slots
        return allSlots.where((slot) {
          final slotStart = _parseTimeString(slot['start_time']);
          int currentMinutes = currentTime.hour * 60 + currentTime.minute;
          int slotMinutes = slotStart.hour * 60 + slotStart.minute;
          return slotMinutes > currentMinutes;
        }).toList();
      } else {
        // Standard: skip first future slot, show from second future slot onwards
        List<Map<String, dynamic>> futureSlots = allSlots.where((slot) {
          final slotStart = _parseTimeString(slot['start_time']);
          int currentMinutes = currentTime.hour * 60 + currentTime.minute;
          int slotMinutes = slotStart.hour * 60 + slotStart.minute;
          return slotMinutes > currentMinutes;
        }).toList();
        return futureSlots.skip(1).toList();
      }
    }

    // Apply filtering logic based on delivery type
    int startIndex;
    if (isExpressDelivery) {
      // Express: show from next slot onwards
      startIndex = currentSlotIndex + 1;
    } else {
      // Standard: skip next slot, show from slot after that
      startIndex = currentSlotIndex + 2;
    }

    return allSlots.skip(startIndex).toList();
  }

  List<Map<String, dynamic>> _getAllDeliverySlots() {
    if (selectedPickupSlot == null) return [];

    final deliveryDate = selectedDeliveryDate;
    int deliveryDayOfWeek = deliveryDate.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == deliveryDayOfWeek ||
          (deliveryDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && deliveryDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    // Sort slots by time
    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  List<Map<String, dynamic>> _getFilteredDeliverySlots() {
    List<Map<String, dynamic>> allSlots = _getAllDeliverySlots();

    if (selectedPickupSlot == null) return [];

    final pickupDate = selectedPickupDate;
    final deliveryDate = selectedDeliveryDate;

    // If delivery is on a different day, apply express/standard logic from morning slots
    if (pickupDate.day != deliveryDate.day ||
        pickupDate.month != deliveryDate.month ||
        pickupDate.year != deliveryDate.year) {

      // For different day delivery, apply the skip logic from the beginning of the day
      if (isExpressDelivery) {
        // Express: start from first slot (8am-10am)
        return allSlots;
      } else {
        // Standard: skip first slot, start from second slot (10am-12pm onwards)
        return allSlots.skip(1).toList();
      }
    }

    // Same day delivery - apply filtering logic based on pickup slot
    int pickupSlotIndex = -1;
    for (int i = 0; i < allSlots.length; i++) {
      if (allSlots[i]['start_time'] == selectedPickupSlot!['start_time'] &&
          allSlots[i]['end_time'] == selectedPickupSlot!['end_time']) {
        pickupSlotIndex = i;
        break;
      }
    }

    if (pickupSlotIndex == -1) return allSlots;

    int startIndex;
    if (isExpressDelivery) {
      // Express: show from next slot onwards
      startIndex = pickupSlotIndex + 1;
    } else {
      // Standard: skip next slot, show from slot after that
      startIndex = pickupSlotIndex + 2;
    }

    return allSlots.skip(startIndex).toList();
  }

  bool _isPickupSlotAvailable(Map<String, dynamic> slot) {
    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    if (!isToday) return true; // All slots available for future dates

    // For today, check if slot has passed
    final currentTime = TimeOfDay.now();
    String timeString = slot['start_time'];
    TimeOfDay slotTime = _parseTimeString(timeString);

    // Check if slot has passed
    if (slotTime.hour < currentTime.hour) return false;
    if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return false;

    // Check if slot meets delivery type requirements
    List<Map<String, dynamic>> availableSlots = _getFilteredPickupSlots();
    return availableSlots.any((availableSlot) => availableSlot['id'] == slot['id']);
  }

  bool _isDeliverySlotAvailable(Map<String, dynamic> slot) {
    if (selectedPickupSlot == null) return false;

    final pickupDate = selectedPickupDate;
    final deliveryDate = selectedDeliveryDate;

    // Check if slot has passed (only for same day as today)
    final now = DateTime.now();
    final isToday = deliveryDate.day == now.day &&
        deliveryDate.month == now.month &&
        deliveryDate.year == now.year;

    if (isToday) {
      final currentTime = TimeOfDay.now();
      String timeString = slot['start_time'];
      TimeOfDay slotTime = _parseTimeString(timeString);

      if (slotTime.hour < currentTime.hour) return false;
      if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return false;
    }

    // For Standard delivery ONLY - check specific skip case
    if (!isExpressDelivery) {
      String pickupStartTime = selectedPickupSlot!['start_time'];
      String pickupEndTime = selectedPickupSlot!['end_time'];

      // ONLY skip 8AM-10AM slot if pickup was 8PM-10PM and delivery is exactly tomorrow
      if (pickupStartTime == '20:00:00' && pickupEndTime == '22:00:00') {
        DateTime tomorrow = pickupDate.add(Duration(days: 1));
        if (deliveryDate.day == tomorrow.day &&
            deliveryDate.month == tomorrow.month &&
            deliveryDate.year == tomorrow.year) {
          // Skip ONLY the 8AM-10AM slot
          if (slot['start_time'] == '08:00:00' && slot['end_time'] == '10:00:00') {
            return false;
          }
        }
      }

      // For same day standard delivery, check if we should skip based on position
      if (pickupDate.day == deliveryDate.day &&
          pickupDate.month == deliveryDate.month &&
          pickupDate.year == deliveryDate.year) {

        // Get all slots for the day
        List<Map<String, dynamic>> allDaySlots = _getAllDeliverySlots();

        // Find pickup slot index
        int pickupSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['start_time'] == selectedPickupSlot!['start_time'] &&
              allDaySlots[i]['end_time'] == selectedPickupSlot!['end_time']) {
            pickupSlotIndex = i;
            break;
          }
        }

        // Find current slot index
        int currentSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['id'] == slot['id']) {
            currentSlotIndex = i;
            break;
          }
        }

        // For same day standard, skip next 2 slots after pickup
        if (pickupSlotIndex != -1 && currentSlotIndex != -1) {
          if (currentSlotIndex <= pickupSlotIndex + 1) {
            return false; // Skip this slot and the next one
          }
        }
      }
    } else {
      // Express delivery - simpler logic
      if (pickupDate.day == deliveryDate.day &&
          pickupDate.month == deliveryDate.month &&
          pickupDate.year == deliveryDate.year) {

        // Get all slots for the day
        List<Map<String, dynamic>> allDaySlots = _getAllDeliverySlots();

        // Find pickup slot index
        int pickupSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['start_time'] == selectedPickupSlot!['start_time'] &&
              allDaySlots[i]['end_time'] == selectedPickupSlot!['end_time']) {
            pickupSlotIndex = i;
            break;
          }
        }

        // Find current slot index
        int currentSlotIndex = -1;
        for (int i = 0; i < allDaySlots.length; i++) {
          if (allDaySlots[i]['id'] == slot['id']) {
            currentSlotIndex = i;
            break;
          }
        }

        // For same day express, skip only the pickup slot itself
        if (pickupSlotIndex != -1 && currentSlotIndex != -1) {
          if (currentSlotIndex <= pickupSlotIndex) {
            return false; // Skip this slot
          }
        }
      }
    }

    // All other cases - slot is available
    return true;
  }

  bool _isSlotPassed(Map<String, dynamic> slot, DateTime selectedDate) {
    final now = DateTime.now();
    if (selectedDate.day != now.day ||
        selectedDate.month != now.month ||
        selectedDate.year != now.year) {
      return false;
    }
    try {
      final currentTime = TimeOfDay.now();
      String timeString = slot['start_time'];
      TimeOfDay slotTime = _parseTimeString(timeString);
      if (slotTime.hour < currentTime.hour) return true;
      if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return true;
      return false;
    } catch (e) {
      return false;
    }
  }

  void _goBackToPickup() {
    setState(() {
      currentStep = 0;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
    });
  }

  // Enhanced handleProceed with payment logic
  void _handleProceed() {
    if (selectedAddress == null ||
        selectedPickupSlot == null ||
        selectedDeliverySlot == null ||
        !isServiceAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all selections and ensure service is available.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Safety: if online is disabled, force COD even if UI state was stale
    if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
      setState(() => _selectedPaymentMethod = 'cod');
    }


    // Process order based on payment method
    if (_selectedPaymentMethod == 'online') {
      _initiateOnlinePayment();
    } else {
      _processOrderCompletion(); // Cash on delivery
    }
  }

  // Initiate Razorpay payment
  Future<void> _initiateOnlinePayment() async {
    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final totalAmount = _calculateTotalAmount();

      final options = {
        'key': 'rzp_test_rlTCKVx6XrfqtS', // Replace with your Razorpay key
        'amount': (totalAmount * 100).toInt(), // Amount in paise
        'name': 'ironXpress',
        'description': 'Ironing Service Payment',
        'prefill': {
          'contact': user.phone ?? '',
          'email': user.email ?? '',
        },
        'theme': {
          'color': '#${kPrimaryColor.value.toRadixString(16).substring(2)}',
        }
      };

      _razorpay.open(options);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to initiate payment: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Process order completion (both online and COD)
  Future<void> _processOrderCompletion({String? paymentId}) async {
    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final totalAmount = _calculateTotalAmount();

      // Generate unique order ID
      final orderId = 'ORD${DateTime.now().millisecondsSinceEpoch}';

      // ✅ FIXED: Create order with proper slot details stored
      await supabase.from('orders').insert({
        'id': orderId,
        'user_id': user.id,
        'total_amount': totalAmount,
        'payment_method': _selectedPaymentMethod,
        'payment_status': _selectedPaymentMethod == 'online' ? 'paid' : 'pending',
        'payment_id': paymentId,
        'order_status': 'confirmed',
        'status': 'confirmed', // ✅ FIXED: Set both status fields
        'pickup_date': selectedPickupDate.toIso8601String().split('T')[0],
        'pickup_slot_id': selectedPickupSlot!['id'],
        'delivery_date': selectedDeliveryDate.toIso8601String().split('T')[0],
        'delivery_slot_id': selectedDeliverySlot!['id'],
        'delivery_type': isExpressDelivery ? 'express' : 'standard',
        'delivery_address': selectedAddress!['address_line_1'],
        'address_details': selectedAddress,
        'applied_coupon_code': widget.appliedCouponCode,
        'discount_amount': widget.discount,
        // ✅ FIXED: Store slot details in order for reschedule functionality
        'pickup_slot_display_time': selectedPickupSlot!['display_time'],
        'pickup_slot_start_time': selectedPickupSlot!['start_time'],
        'pickup_slot_end_time': selectedPickupSlot!['end_time'],
        'delivery_slot_display_time': selectedDeliverySlot!['display_time'],
        'delivery_slot_start_time': selectedDeliverySlot!['start_time'],
        'delivery_slot_end_time': selectedDeliverySlot!['end_time'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });



      // Create order items
      for (final item in widget.cartItems) {
        await supabase.from('order_items').insert({
          'order_id': orderId,
          'product_name': item['product_name'],
          'product_image': item['product_image'],
          'product_price': item['product_price'],
          'service_type': item['service_type'],
          'service_price': item['service_price'],
          'quantity': item['product_quantity'],
          'total_price': item['total_price'],
        });
      }

      // Save billing details
      await _saveBillingDetails(orderId);

      // Clear cart
      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      // Navigate to success screen
      _navigateToSuccessScreen(orderId, paymentId);

    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Navigate to success screen
  void _navigateToSuccessScreen(String orderId, String? paymentId) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OrderSuccessScreen(
          orderId: orderId,
          totalAmount: _calculateTotalAmount(),
          cartItems: widget.cartItems,
          paymentMethod: _selectedPaymentMethod,
          paymentId: paymentId,
          appliedCouponCode: widget.appliedCouponCode,
          discount: widget.discount,
          selectedAddress: selectedAddress!,
          pickupDate: selectedPickupDate,
          pickupSlot: selectedPickupSlot!,
          deliveryDate: selectedDeliveryDate,
          deliverySlot: selectedDeliverySlot!,
          isExpressDelivery: isExpressDelivery,
        ),
      ),
    );
  }

  // Auto-scroll function to smoothly scroll to specific sections
  void _autoScrollToSection(double offset, {int delay = 300}) {
    Future.delayed(Duration(milliseconds: delay), () {
      if (_mainScrollController.hasClients) {
        _mainScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ RESPONSIVE: Get screen dimensions for universal phone display
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isSmallScreen = screenWidth < 360;
    final isTablet = screenWidth > 600;
    final cardMargin = isSmallScreen ? 12.0 : 16.0;
    final cardPadding = isSmallScreen ? 12.0 : 16.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        title: Text(
          "Select Slot",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: isSmallScreen ? 18 : 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: cardMargin / 2),
                    child: Column(
                      children: [
                        _buildAddressSection(cardMargin, cardPadding, isSmallScreen),
                        _buildDeliveryTypeToggle(cardMargin, cardPadding, isSmallScreen),
                        _buildProgressIndicator(cardMargin, isSmallScreen),
                        if (currentStep == 0) ...[
                          _buildDateSelector(true, cardMargin, isSmallScreen),
                          if (isLoadingSlots)
                            Container(
                              padding: EdgeInsets.all(cardPadding * 2),
                              child: Center(
                                child: CircularProgressIndicator(color: kPrimaryColor),
                              ),
                            )
                          else
                            _buildPickupSlotsSection(cardMargin, cardPadding, isSmallScreen),
                        ],
                        if (currentStep == 1) ...[
                          _buildDateSelector(false, cardMargin, isSmallScreen),
                          if (isLoadingSlots)
                            Container(
                              padding: EdgeInsets.all(cardPadding * 2),
                              child: Center(
                                child: CircularProgressIndicator(color: kPrimaryColor),
                              ),
                            )
                          else
                            Container(
                              key: _deliverySlotSectionKey, // Add this line
                              child: _buildDeliverySlotsSection(cardMargin, cardPadding, isSmallScreen),
                            ),
                        ],
                        if (selectedPickupSlot != null || selectedDeliverySlot != null)
                          _buildSelectionSummary(cardMargin, cardPadding, isSmallScreen),

                        // Billing Summary Section
                        if (selectedPickupSlot != null && selectedDeliverySlot != null)
                          _buildBillingSummary(cardMargin, cardPadding, isSmallScreen),

                        // Payment Method Selection
                        // Payment Method Selection
                        if (selectedPickupSlot != null && selectedDeliverySlot != null)
                          Container(
                            key: _paymentSectionKey, // Add this line
                            child: _buildPaymentMethodSelection(cardMargin, cardPadding, isSmallScreen),
                          ),

                        SizedBox(height: 16), // Reduced bottom spacing
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!isServiceAvailable && selectedAddress != null)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  margin: EdgeInsets.all(cardMargin * 2),
                  padding: EdgeInsets.all(cardPadding * 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: isSmallScreen ? 48 : 64, color: Colors.red.shade400),
                      SizedBox(height: cardPadding),
                      Text(
                        'Service Unavailable',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: cardPadding / 2),
                      Text(
                        'Sorry, we are currently not available in ${selectedAddress!['pincode']}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.black54,
                        ),
                      ),
                      SizedBox(height: cardPadding),
                      ElevatedButton(
                        onPressed: _openAddressBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          padding: EdgeInsets.symmetric(
                            horizontal: cardPadding * 1.5,
                            vertical: cardPadding,
                          ),
                        ),
                        child: Text(
                          'Change Address',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isSmallScreen),
    );
  }

  // Billing Summary Widget (uses merged service taxes + free standard logic)
  Widget _buildBillingSummary(double cardMargin, double cardPadding, bool isSmallScreen) {
    if (isLoadingBillingSettings) {
      return Container(
        margin: EdgeInsets.all(cardMargin),
        padding: EdgeInsets.all(cardPadding * 2),
        child: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    final billing = _calculateBilling();
    final bool isStandard = !isExpressDelivery;

    // discount label like: Discount (SAVE10)
    final bool hasDiscount = (billing['discount'] ?? 0) > 0;
    final String discountLabel = hasDiscount && (widget.appliedCouponCode?.isNotEmpty ?? false)
        ? 'Discount (${widget.appliedCouponCode})'
        : 'Discount';

    // compute “free standard delivery” on the discounted subtotal
    final double sub = billing['subtotal'] ?? 0;
    final double disc = billing['discount'] ?? 0;
    final bool qualifiesFreeStandard = isStandard && ((sub - disc) >= freeStandardThreshold);

    return Container(
      margin: EdgeInsets.all(cardMargin),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () {
              setState(() {
                _isBillingSummaryExpanded = !_isBillingSummaryExpanded;
              });
              if (_isBillingSummaryExpanded) {
                _billingAnimationController.forward();
              } else {
                _billingAnimationController.reverse();
              }
            },
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.05),
                borderRadius: _isBillingSummaryExpanded
                    ? const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                )
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.receipt_long, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
                  ),
                  SizedBox(width: cardPadding * 0.75),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bill Summary',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Total: ₹${billing['totalAmount']!.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isBillingSummaryExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: kPrimaryColor,
                      size: isSmallScreen ? 20 : 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable Content
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isBillingSummaryExpanded ? null : 0,
            child: _isBillingSummaryExpanded
                ? Container(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                children: [
                  // Subtotal (ⓘ not needed)
                  _buildBillingRow(
                    'Subtotal',
                    billing['subtotal'] ?? 0,
                    isSmallScreen: isSmallScreen,
                  ),

                  // Discount (green)
                  if (hasDiscount)
                    _buildBillingRow(
                      discountLabel,
                      -(billing['discount'] ?? 0),
                      color: Colors.green,
                      isSmallScreen: isSmallScreen,
                    ),

                  // Minimum Cart Fee (ⓘ)
                  if ((billing['minimumCartFee'] ?? 0) > 0)
                    _buildBillingRow(
                      'Minimum Cart Fee',
                      billing['minimumCartFee'] ?? 0,
                      infoKey: 'minimum_cart_fee',
                      isSmallScreen: isSmallScreen,
                    ),

                  // Platform Fee (ⓘ)
                  _buildBillingRow(
                    'Platform Fee',
                    billing['platformFee'] ?? 0,
                    infoKey: 'platform_fee',
                    isSmallScreen: isSmallScreen,
                  ),

                  // Delivery Fee (ⓘ) with Standard/Express + override title for Free Standard
                  _buildBillingRow(
                    'Delivery Fee (${isStandard ? 'Standard' : 'Express'})',
                    billing['deliveryFee'] ?? 0,
                    infoKey: isStandard
                        ? (qualifiesFreeStandard
                        ? 'delivery_standard_free'
                        : 'delivery_standard')
                        : 'delivery_express',
                    overrideTitle:
                    (isStandard && qualifiesFreeStandard) ? 'Standard Delivery — Free' : null,
                    isSmallScreen: isSmallScreen,
                  ),

                  // Service Taxes (ⓘ) — merged: items tax + delivery GST
                  _buildBillingRow(
                    'Service Taxes',
                    billing['serviceTax'] ?? 0,
                    infoKey: 'service_tax', // your notes can explain item tax + delivery GST
                    isSmallScreen: isSmallScreen,
                  ),

                  const Divider(height: 20),

                  // Total
                  _buildBillingRow(
                    'Total Amount',
                    billing['totalAmount'] ?? 0,
                    isTotal: true,
                    color: kPrimaryColor,
                    isSmallScreen: isSmallScreen,
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }




  Widget _buildBillingRow(
      String label,
      double amount, {
        bool isTotal = false,
        Color? color,
        String? customValue,

        // NEW (match ReviewCartScreen)
        String? infoKey,
        String? overrideTitle,

        // keep existing API need:
        required bool isSmallScreen,
      }) {
    final bool clickable = infoKey != null && (_billingNotes[infoKey] != null);

    final TextStyle labelStyle = TextStyle(
      fontSize: isTotal ? (isSmallScreen ? 14 : 16) : (isSmallScreen ? 12 : 14),
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: color ?? Colors.black87,
    );

    final TextStyle valueStyle = TextStyle(
      fontSize: isTotal ? (isSmallScreen ? 14 : 16) : (isSmallScreen ? 12 : 14),
      fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
      color: color ?? Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: clickable
                ? () {
              final note = _billingNotes[infoKey]!;
              _showInfoDialog(
                overrideTitle ?? (note['title'] ?? label),
                note['content'] ?? '',
              );
            }
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: labelStyle),
                if (clickable) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 14, color: color ?? Colors.black54),
                ],
              ],
            ),
          ),
          Text(
            customValue ?? '₹${amount.toStringAsFixed(2)}',
            style: valueStyle,
          ),
        ],
      ),
    );
  }


  Widget _buildPaymentMethodSelection(double cardMargin, double cardPadding, bool isSmallScreen) {
    // Ensure UI state stays consistent with toggle
    if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
      _selectedPaymentMethod = 'cod';
    }

    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),

          // If online payments are OFF, show a small info banner
          if (!onlinePaymentEnabled)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: cardPadding * 0.75),
              padding: EdgeInsets.all(cardPadding * 0.75),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: isSmallScreen ? 16 : 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Online payment is temporarily unavailable. Please choose Pay on Delivery.',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10.5 : 12,
                        color: Colors.orange.shade800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Online Payment Option (only if enabled)
          if (onlinePaymentEnabled)
            Container(
              margin: EdgeInsets.only(bottom: cardPadding * 0.75),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedPaymentMethod == 'online' ? kPrimaryColor : Colors.grey.shade300,
                  width: 2,
                ),
                color: _selectedPaymentMethod == 'online'
                    ? kPrimaryColor.withOpacity(0.05)
                    : Colors.white,
              ),
              child: RadioListTile<String>(
                value: 'online',
                groupValue: _selectedPaymentMethod,
                onChanged: (value) {
                  setState(() {
                    _selectedPaymentMethod = value!;
                  });
                },
                title: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.payment,
                        color: kPrimaryColor,
                        size: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    SizedBox(width: cardPadding * 0.6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pay Online',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          Text(
                            'UPI, Card, Net Banking, Wallet',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedPaymentMethod == 'online')
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 4 : 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'RECOMMENDED',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: isSmallScreen ? 7 : 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                activeColor: kPrimaryColor,
              ),
            ),

          // Cash on Delivery Option (always)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedPaymentMethod == 'cod' ? kPrimaryColor : Colors.grey.shade300,
                width: 2,
              ),
              color: _selectedPaymentMethod == 'cod'
                  ? kPrimaryColor.withOpacity(0.05)
                  : Colors.white,
            ),
            child: RadioListTile<String>(
              value: 'cod',
              groupValue: _selectedPaymentMethod,
              onChanged: (value) {
                setState(() {
                  _selectedPaymentMethod = value!;
                });
              },
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.money,
                      color: Colors.orange,
                      size: isSmallScreen ? 14 : 16,
                    ),
                  ),
                  SizedBox(width: cardPadding * 0.6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay on Delivery',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                        Text(
                          'Cash payment when order is delivered',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              activeColor: kPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSelectionSummary(double cardMargin, double cardPadding, bool isSmallScreen) {
    if (selectedPickupSlot == null) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: kPrimaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Selection Summary',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: isSmallScreen ? 14 : 16,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding * 0.75),
          Container(
            padding: EdgeInsets.all(cardPadding * 0.75),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, color: kPrimaryColor, size: isSmallScreen ? 14 : 16),
                    SizedBox(width: cardPadding / 2),
                    Expanded(
                      child: Text(
                        'Pickup: ${_formatDate(selectedPickupDate)} at ${selectedPickupSlot!['display_time'] ?? '${selectedPickupSlot!['start_time']} - ${selectedPickupSlot!['end_time']}'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectedDeliverySlot != null) ...[
                  SizedBox(height: cardPadding / 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_shipping, color: kPrimaryColor, size: isSmallScreen ? 14 : 16),
                      SizedBox(width: cardPadding / 2),
                      Expanded(
                        child: Text(
                          'Delivery: ${_formatDate(selectedDeliveryDate)} at ${selectedDeliverySlot!['display_time'] ?? '${selectedDeliverySlot!['start_time']} - ${selectedDeliverySlot!['end_time']}'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return 'Today';
    } else if (date.day == now.add(const Duration(days: 1)).day &&
        date.month == now.add(const Duration(days: 1)).month &&
        date.year == now.add(const Duration(days: 1)).year) {
      return 'Tomorrow';
    } else {
      return '${date.day}/${date.month}';
    }
  }

  // UPDATED METHOD: Only show delivery dates that have available slots
  Widget _buildDateSelector(bool isPickup, double cardMargin, bool isSmallScreen) {
    DateTime selectedDate = isPickup ? selectedPickupDate : selectedDeliveryDate;
    ScrollController controller = isPickup ? _pickupDateScrollController : _deliveryDateScrollController;
    List<DateTime> availableDates = isPickup ? pickupDates : _getAvailableDeliveryDates();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardMargin / 2),
              Text(
                'Select ${isPickup ? 'Pickup' : 'Delivery'} Date',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: cardMargin * 0.75),
          SizedBox(
            height: isSmallScreen ? 70 : 80,
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: availableDates.length,
              itemBuilder: (context, index) {
                final date = availableDates[index];
                final isSelected = date.day == selectedDate.day &&
                    date.month == selectedDate.month &&
                    date.year == selectedDate.year;
                final isToday = date.day == DateTime.now().day &&
                    date.month == DateTime.now().month &&
                    date.year == DateTime.now().year;

                // For delivery date, don't allow dates before pickup date
                bool isDisabled = false;
                if (!isPickup) {
                  isDisabled = date.isBefore(selectedPickupDate);
                }

                return GestureDetector(
                  onTap: isDisabled ? null : () {
                    if (isPickup) {
                      _onPickupDateSelected(date);
                    } else {
                      _onDeliveryDateSelected(date);
                    }
                  },
                  child: Container(
                    width: isSmallScreen ? 50 : 60,
                    margin: EdgeInsets.only(right: cardMargin / 2),
                    decoration: BoxDecoration(
                      color: isDisabled
                          ? Colors.grey.shade200
                          : isSelected ? kPrimaryColor : Colors.white,
                      border: Border.all(
                        color: isDisabled
                            ? Colors.grey.shade300
                            : isSelected ? kPrimaryColor : Colors.grey.shade300,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected && !isDisabled
                          ? [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getDayName(date.weekday),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 10,
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 2 : 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 1 : 2),
                        if (isToday)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 4 : 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? Colors.grey.shade400
                                  : isSelected ? Colors.white : kPrimaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 7 : 8,
                                fontWeight: FontWeight.w600,
                                color: isDisabled
                                    ? Colors.white
                                    : isSelected ? kPrimaryColor : Colors.white,
                              ),
                            ),
                          )
                        else
                          Text(
                            _getMonthName(date.month),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 7 : 8,
                              fontWeight: FontWeight.w500,
                              color: isDisabled
                                  ? Colors.grey.shade500
                                  : isSelected ? Colors.white70 : Colors.black45,
                            ),
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
    );
  }

  String _getDayName(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[month - 1];
  }

  Widget _buildProgressIndicator(double cardMargin, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
      child: Row(
        children: [
          Container(
            width: isSmallScreen ? 20 : 24,
            height: isSmallScreen ? 20 : 24,
            decoration: BoxDecoration(
              color: currentStep >= 0 ? kPrimaryColor : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selectedPickupSlot != null ? Icons.check : Icons.schedule,
              color: Colors.white,
              size: isSmallScreen ? 12 : 16,
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
            ),
          ),
          Container(
            width: isSmallScreen ? 20 : 24,
            height: isSmallScreen ? 20 : 24,
            decoration: BoxDecoration(
              color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selectedDeliverySlot != null ? Icons.check : Icons.local_shipping,
              color: Colors.white,
              size: isSmallScreen ? 12 : 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Delivery Address',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _openAddressBook,
                child: Text(
                  selectedAddress == null ? 'Select' : 'Change',
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding / 2),
          if (selectedAddress != null) ...[
            Text(
              selectedAddress!['address_line_1'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: isSmallScreen ? 12 : 14,
              ),
            ),
            if (selectedAddress!['address_line_2'] != null)
              Text(
                selectedAddress!['address_line_2'],
                style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
              ),
            Text(
              '${selectedAddress!['city']}, ${selectedAddress!['state']} - ${selectedAddress!['pincode']}',
              style: TextStyle(
                color: Colors.black54,
                fontSize: isSmallScreen ? 11 : 13,
              ),
            ),
            if (isLoadingServiceAvailability)
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Text(
                  'Checking availability...',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: isSmallScreen ? 10 : 12,
                  ),
                ),
              )
            else if (!isServiceAvailable)
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Text(
                  '❌ Service not available',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Text(
                  '✅ Service available',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ] else ...[
            GestureDetector(
              onTap: _openAddressBook,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_location, color: Colors.grey.shade600, size: isSmallScreen ? 18 : 20),
                    SizedBox(width: cardPadding * 0.75),
                    Text(
                      'Select delivery address',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 14 : 16, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryTypeToggle(double cardMargin, double cardPadding, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Delivery Type:',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isExpressDelivery = false;
                          selectedPickupSlot = null;
                          selectedDeliverySlot = null;
                          currentStep = 0;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 16 : 20,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: !isExpressDelivery ? kPrimaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Standard',
                          style: TextStyle(
                            color: !isExpressDelivery ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isExpressDelivery = true;
                          selectedPickupSlot = null;
                          selectedDeliverySlot = null;
                          currentStep = 0;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 16 : 20,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: isExpressDelivery ? kPrimaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Express',
                          style: TextStyle(
                            color: isExpressDelivery ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding / 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  isExpressDelivery
                      ? 'Faster Pick Up & Delivery Options'
                      : 'Choose Express Delivery for Quicker service',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              // ✅ FIXED: Change express delivery fee color to dark red
              if (isExpressDelivery && !isLoadingBillingSettings)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 6 : 8,
                    vertical: isSmallScreen ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green, // ✅ CHANGED: Light red background
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)), // ✅ CHANGED: Dark red border
                  ),
                  child: Text(
                    '+₹${(expressDeliveryFee - standardDeliveryFee).toStringAsFixed(0)} extra',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 9 : 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white, // ✅ CHANGED: Dark red text
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPickupSlotsSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    List<Map<String, dynamic>> allSlots = _getAllPickupSlots();
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Schedule Pickup',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryColor, // 👈 make title blue
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),
          _buildTimeSlots(allSlots, true, isSmallScreen),
        ],
      ),
    );
  }


  Widget _buildDeliverySlotsSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    List<Map<String, dynamic>> allSlots = _getAllDeliverySlots();
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _goBackToPickup,
                icon: Icon(Icons.arrow_back, size: isSmallScreen ? 18 : 20, color: kPrimaryColor), // 👈 blue arrow
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(width: cardPadding / 2),
              Icon(Icons.local_shipping, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Expanded(
                child: Text(
                  'Schedule Delivery ${isExpressDelivery ? '(Express)' : '(Standard)'}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: kPrimaryColor, // 👈 make title blue
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),
          _buildTimeSlots(allSlots, false, isSmallScreen),
        ],
      ),
    );
  }


  Widget _buildTimeSlots(List<Map<String, dynamic>> slots, bool isPickup, bool isSmallScreen) {
    if (slots.isEmpty) {
      return Container(
        padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
        child: Column(
          children: [
            Icon(Icons.schedule, size: isSmallScreen ? 40 : 48, color: Colors.grey.shade400),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              'No ${isPickup ? 'pickup' : 'delivery'} slots available',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: isSmallScreen ? 12 : 14,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isSmallScreen ? 1 : 2, // ✅ RESPONSIVE: Single column for small screens
        childAspectRatio: isSmallScreen ? 4 : 3,
        crossAxisSpacing: isSmallScreen ? 6 : 8,
        mainAxisSpacing: isSmallScreen ? 6 : 8,
      ),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        bool isSelected = isPickup
            ? (selectedPickupSlot?['id'] == slot['id'])
            : (selectedDeliverySlot?['id'] == slot['id']);

        bool isSlotAvailable = isPickup
            ? _isPickupSlotAvailable(slot)
            : _isDeliverySlotAvailable(slot);

        DateTime selectedDate = isPickup ? selectedPickupDate : selectedDeliveryDate;
        bool isSlotPassed = _isSlotPassed(slot, selectedDate);

        return GestureDetector(
          onTap: (!isSlotAvailable || isSlotPassed) ? null : () {
            if (isPickup) {
              _onPickupSlotSelected(slot);
            } else {
              _onDeliverySlotSelected(slot);
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 8 : 12,
              vertical: isSmallScreen ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: (!isSlotAvailable || isSlotPassed)
                  ? Colors.grey.shade100
                  : isSelected ? kPrimaryColor : Colors.white,
              border: Border.all(
                color: (!isSlotAvailable || isSlotPassed)
                    ? Colors.grey.shade300
                    : isSelected ? kPrimaryColor : Colors.grey.shade300,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: isSelected && isSlotAvailable && !isSlotPassed
                  ? [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    slot['display_time'] ?? '${slot['start_time']} - ${slot['end_time']}',
                    style: TextStyle(
                      color: (!isSlotAvailable || isSlotPassed)
                          ? Colors.grey.shade500
                          : isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: isSmallScreen ? 11 : 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isSlotAvailable || isSlotPassed)
                    Text(
                      'Unavailable',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: isSmallScreen ? 9 : 10,
                        fontWeight: FontWeight.w500,
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

  // Enhanced bottom bar with payment button text
  Widget _buildBottomBar(bool isSmallScreen) {
    double totalAmount = _calculateTotalAmount();
    bool canProceed = selectedAddress != null &&
        selectedPickupSlot != null &&
        selectedDeliverySlot != null &&
        isServiceAvailable &&
        !isLoadingBillingSettings;

    // Dynamic button text and icon based on payment method
    final buttonText = _selectedPaymentMethod == 'online' ? 'Pay Now' : 'Place Order';
    final buttonIcon = _selectedPaymentMethod == 'online' ? Icons.payment : Icons.shopping_bag;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 20,
        vertical: isSmallScreen ? 10 : 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Total Amount",
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 2 : 4),
                  if (isLoadingBillingSettings)
                    SizedBox(
                      width: isSmallScreen ? 16 : 20,
                      height: isSmallScreen ? 16 : 20,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      "₹${totalAmount.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),

            // Enhanced rounded button with payment functionality
            Container(
              height: isSmallScreen ? 44 : 50,
              child: ElevatedButton(
                onPressed: (canProceed && !_isProcessingPayment) ? _handleProceed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 20 : 24,
                    vertical: isSmallScreen ? 12 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25), // Rounded button
                  ),
                  elevation: canProceed ? 8 : 0,
                  shadowColor: kPrimaryColor.withOpacity(0.3),
                ),
                child: _isProcessingPayment
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: isSmallScreen ? 14 : 16,
                      height: isSmallScreen ? 14 : 16,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      buttonIcon,
                      color: Colors.white,
                      size: isSmallScreen ? 16 : 18,
                    ),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    Text(
                      isLoadingBillingSettings ? "Loading..." : buttonText,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}