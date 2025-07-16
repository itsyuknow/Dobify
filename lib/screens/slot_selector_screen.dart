import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'colors.dart';
import 'address_book_screen.dart';

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

class _SlotSelectorScreenState extends State<SlotSelectorScreen> {
  final supabase = Supabase.instance.client;

  bool isExpressDelivery = false;
  Map<String, dynamic>? selectedAddress;
  bool isServiceAvailable = true;
  bool isLoadingServiceAvailability = false;

  Map<String, dynamic>? selectedPickupSlot;
  Map<String, dynamic>? selectedDeliverySlot;

  List<Map<String, dynamic>> pickupSlots = [];
  List<Map<String, dynamic>> deliverySlots = [];
  bool isLoadingSlots = true;

  double expressDeliveryFee = 0.0;
  double standardDeliveryFee = 0.0;
  bool isLoadingBillingSettings = true;

  int currentStep = 0; // 0: pickup date/slot, 1: delivery date/slot

  DateTime selectedPickupDate = DateTime.now();
  DateTime selectedDeliveryDate = DateTime.now();
  final ScrollController _pickupDateScrollController = ScrollController();
  final ScrollController _deliveryDateScrollController = ScrollController();
  late List<DateTime> pickupDates;
  late List<DateTime> deliveryDates;

  // ✅ NEW: Payment related variables
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
  }

  @override
  void dispose() {
    _pickupDateScrollController.dispose();
    _deliveryDateScrollController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  // ✅ NEW: Initialize Razorpay
  void _initializeRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  // ✅ NEW: Razorpay Event Handlers
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

  Future<void> _loadBillingSettings() async {
    try {
      final response = await supabase.from('billing_settings').select().single();
      setState(() {
        expressDeliveryFee = response['express_delivery_fee']?.toDouble() ?? 0.0;
        standardDeliveryFee = response['standard_delivery_fee']?.toDouble() ?? 0.0;
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

  double _calculateTotalAmount() {
    double baseAmount = widget.totalAmount;
    double deliveryFee = isExpressDelivery ? (expressDeliveryFee - standardDeliveryFee) : 0.0;
    return baseAmount + deliveryFee - widget.discount;
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

  void _onPickupSlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedPickupSlot = slot;
      selectedDeliverySlot = null;
      currentStep = 1;
      // Update delivery dates based on pickup date
      _updateDeliveryDates();
      selectedDeliveryDate = selectedPickupDate; // Start from pickup date
    });
  }

  void _onDeliverySlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedDeliverySlot = slot;
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

  int _parseTimeToHour(String timeString) {
    try {
      return int.parse(timeString.split(':')[0]);
    } catch (e) {
      return 0;
    }
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

  // ✅ MODIFIED: Enhanced handleProceed with payment logic
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

    // Process order based on payment method
    if (_selectedPaymentMethod == 'online') {
      _initiateOnlinePayment();
    } else {
      _processOrderCompletion(); // Cash on delivery
    }
  }

  // ✅ NEW: Initiate Razorpay payment
  Future<void> _initiateOnlinePayment() async {
    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final totalAmount = _calculateTotalAmount();

      final options = {
        'key': 'rzp_test_your_key_here', // Replace with your Razorpay key
        'amount': (totalAmount * 100).toInt(), // Amount in paise
        'name': 'ironXpress',
        'description': 'Laundry Service Payment',
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

  // ✅ NEW: Process order completion (both online and COD)
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

      // Create order in database
      await supabase.from('orders').insert({
        'id': orderId,
        'user_id': user.id,
        'total_amount': totalAmount,
        'payment_method': _selectedPaymentMethod,
        'payment_status': _selectedPaymentMethod == 'online' ? 'paid' : 'pending',
        'payment_id': paymentId,
        'order_status': 'confirmed',
        'pickup_date': selectedPickupDate.toIso8601String().split('T')[0],
        'pickup_slot_id': selectedPickupSlot!['id'],
        'delivery_date': selectedDeliveryDate.toIso8601String().split('T')[0],
        'delivery_slot_id': selectedDeliverySlot!['id'],
        'delivery_type': isExpressDelivery ? 'express' : 'standard',
        'delivery_address': selectedAddress!['address_line_1'],
        'address_details': selectedAddress,
        'applied_coupon_code': widget.appliedCouponCode,
        'discount_amount': widget.discount,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Create order items
      for (final item in widget.cartItems) {
        await supabase.from('order_items').insert({
          'order_id': orderId,
          'product_name': item['product_name'],
          'product_price': item['product_price'],
          'service_type': item['service_type'],
          'service_price': item['service_price'],
          'quantity': item['product_quantity'],
          'total_price': item['total_price'],
        });
      }

      // Clear cart
      await supabase
          .from('cart')
          .delete()
          .eq('user_id', user.id);

      // Show success animation and navigate
      await _showOrderSuccessAnimation(orderId);

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

  // ✅ NEW: Show order success animation
  Future<void> _showOrderSuccessAnimation(String orderId) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderSuccessDialog(orderId: orderId),
    );

    // Navigate to home screen
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: true,
        title: const Text(
          "Select Slot",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildAddressSection(),
                      _buildDeliveryTypeToggle(),
                      _buildProgressIndicator(),
                      if (currentStep == 0) ...[
                        _buildDateSelector(true),
                        if (isLoadingSlots)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          _buildPickupSlotsSection(),
                      ],
                      if (currentStep == 1) ...[
                        _buildDateSelector(false),
                        if (isLoadingSlots)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          _buildDeliverySlotsSection(),
                      ],
                      if (selectedPickupSlot != null || selectedDeliverySlot != null)
                        _buildSelectionSummary(),

                      // ✅ NEW: Payment Method Selection
                      if (selectedPickupSlot != null && selectedDeliverySlot != null)
                        _buildPaymentMethodSelection(),

                      const SizedBox(height: 100),
                    ],
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
                  margin: const EdgeInsets.all(32),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: 64, color: Colors.red.shade400),
                      const SizedBox(height: 16),
                      const Text('Service Unavailable', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        'Sorry, we are currently not available in ${selectedAddress!['pincode']}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _openAddressBook,
                        style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                        child: const Text('Change Address'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ✅ NEW: Payment method selection widget
  Widget _buildPaymentMethodSelection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.payment, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Payment Method',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Online Payment Option
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.payment,
                      color: kPrimaryColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay Online',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'UPI, Card, Net Banking, Wallet',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedPaymentMethod == 'online')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'RECOMMENDED',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              activeColor: kPrimaryColor,
            ),
          ),

          // Cash on Delivery Option
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
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.money,
                      color: Colors.orange,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay on Delivery',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Cash payment when order is delivered',
                          style: TextStyle(
                            fontSize: 11,
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

  Widget _buildSelectionSummary() {
    if (selectedPickupSlot == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.check_circle, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Selection Summary',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, color: kPrimaryColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pickup: ${_formatDate(selectedPickupDate)} at ${selectedPickupSlot!['display_time'] ?? '${selectedPickupSlot!['start_time']} - ${selectedPickupSlot!['end_time']}'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectedDeliverySlot != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: kPrimaryColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Delivery: ${_formatDate(selectedDeliveryDate)} at ${selectedDeliverySlot!['display_time'] ?? '${selectedDeliverySlot!['start_time']} - ${selectedDeliverySlot!['end_time']}'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
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

  Widget _buildDateSelector(bool isPickup) {
    DateTime selectedDate = isPickup ? selectedPickupDate : selectedDeliveryDate;
    ScrollController controller = isPickup ? _pickupDateScrollController : _deliveryDateScrollController;
    List<DateTime> availableDates = isPickup ? pickupDates : deliveryDates;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Select ${isPickup ? 'Pickup' : 'Delivery'} Date',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
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
                    width: 60,
                    margin: const EdgeInsets.only(right: 8),
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
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? Colors.grey.shade400
                                  : isSelected ? Colors.white : kPrimaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 8,
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
                              fontSize: 8,
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

  Widget _buildProgressIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: currentStep >= 0 ? kPrimaryColor : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selectedPickupSlot != null ? Icons.check : Icons.schedule,
              color: Colors.white,
              size: 16,
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selectedDeliverySlot != null ? Icons.check : Icons.local_shipping,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.location_on, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('Delivery Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: _openAddressBook,
                child: Text(selectedAddress == null ? 'Select' : 'Change', style: TextStyle(color: kPrimaryColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedAddress != null) ...[
            Text(selectedAddress!['address_line_1'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
            if (selectedAddress!['address_line_2'] != null) Text(selectedAddress!['address_line_2']),
            Text('${selectedAddress!['city']}, ${selectedAddress!['state']} - ${selectedAddress!['pincode']}', style: const TextStyle(color: Colors.black54)),
            if (isLoadingServiceAvailability)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Checking availability...', style: TextStyle(color: Colors.orange, fontSize: 12)),
              )
            else if (!isServiceAvailable)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('❌ Service not available', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500)),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('✅ Service available', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
          ] else ...[
            GestureDetector(
              onTap: _openAddressBook,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_location, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    const Text('Select delivery address', style: TextStyle(color: Colors.black54, fontSize: 16)),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryTypeToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Delivery Type:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: !isExpressDelivery ? kPrimaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Standard',
                          style: TextStyle(
                            color: !isExpressDelivery ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.w600,
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: isExpressDelivery ? kPrimaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          'Express',
                          style: TextStyle(
                            color: isExpressDelivery ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isExpressDelivery
                ? 'Faster Pick Up & Delivery Options'
                : 'Standard delivery with regular timings',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupSlotsSection() {
    List<Map<String, dynamic>> allSlots = _getAllPickupSlots();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.schedule, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('Schedule Pickup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          _buildTimeSlots(allSlots, true),
        ],
      ),
    );
  }

  Widget _buildDeliverySlotsSection() {
    List<Map<String, dynamic>> allSlots = _getAllDeliverySlots();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
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
                icon: const Icon(Icons.arrow_back, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Icon(Icons.local_shipping, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Schedule Delivery ${isExpressDelivery ? '(Express)' : '(Standard)'}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTimeSlots(allSlots, false),
        ],
      ),
    );
  }

  Widget _buildTimeSlots(List<Map<String, dynamic>> slots, bool isPickup) {
    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.schedule, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No ${isPickup ? 'pickup' : 'delivery'} slots available',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isSlotAvailable || isSlotPassed)
                    Text(
                      'Unavailable',
                      style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ MODIFIED: Enhanced bottom bar with payment button text
  Widget _buildBottomBar() {
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Total Amount", style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 4),
                if (isLoadingBillingSettings)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Text("₹${totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // ✅ Enhanced rounded button with payment functionality
          Container(
            height: 50,
            child: ElevatedButton(
              onPressed: (canProceed && !_isProcessingPayment) ? _handleProceed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25), // ✅ Rounded button
                ),
                elevation: canProceed ? 8 : 0,
                shadowColor: kPrimaryColor.withOpacity(0.3),
              ),
              child: _isProcessingPayment
                  ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Processing...',
                    style: TextStyle(
                      fontSize: 14,
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
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isLoadingBillingSettings ? "Loading..." : buttonText,
                    style: const TextStyle(
                      fontSize: 15,
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
    );
  }
}

// ✅ NEW: Premium Full-Screen Order Success Animation
class OrderSuccessDialog extends StatefulWidget {
  final String orderId;

  const OrderSuccessDialog({super.key, required this.orderId});

  @override
  State<OrderSuccessDialog> createState() => _OrderSuccessDialogState();
}

class _OrderSuccessDialogState extends State<OrderSuccessDialog>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _checkController;
  late AnimationController _textController;
  late AnimationController _confettiController;
  late AnimationController _pulseController;
  late AnimationController _backgroundController;

  // Background animations
  late Animation<double> _backgroundFadeAnimation;
  late Animation<double> _gradientAnimation;

  // Main animations
  late Animation<double> _cardScaleAnimation;
  late Animation<Offset> _cardSlideAnimation;

  // Check mark animations
  late Animation<double> _checkScaleAnimation;
  late Animation<double> _checkFadeAnimation;
  late Animation<double> _checkRotationAnimation;

  // Text animations
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _titleFadeAnimation;
  late Animation<Offset> _subtitleSlideAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<Offset> _detailsSlideAnimation;
  late Animation<double> _detailsFadeAnimation;

  // Confetti and effects
  late Animation<double> _confettiAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimationSequence();
  }

  void _initializeAnimations() {
    // Background controller for gradient effects
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Main controller for overall flow
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Check mark controller
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Text animations controller
    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Confetti controller
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    // Pulse controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Background animations
    _backgroundFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));

    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    // Card animations
    _cardScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));

    // Check mark animations
    _checkScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    _checkFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _checkRotationAnimation = Tween<double>(
      begin: -0.8,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    // Text animations
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _titleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
    ));

    _subtitleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
    ));

    _detailsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
    ));

    _detailsFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeIn),
    ));

    // Confetti animation
    _confettiAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _confettiController,
      curve: Curves.easeOut,
    ));

    // Pulse animation
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.4,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _startAnimationSequence() async {
    // Start background animation
    _backgroundController.repeat(reverse: true);

    // Start main animation
    _mainController.forward();

    // Start check animation after delay
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      _checkController.forward();

      // Start pulse animation
      _pulseController.repeat(reverse: true);
    }

    // Start text animations
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      _textController.forward();
    }

    // Start confetti
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _confettiController.forward();
    }

    // Auto close after 5 seconds
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _mainController.dispose();
    _checkController.dispose();
    _textController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _backgroundController,
        _mainController,
        _checkController,
        _textController,
        _confettiController,
        _pulseController,
      ]),
      builder: (context, child) {
        return Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kPrimaryColor.withOpacity(0.1 + (_gradientAnimation.value * 0.15)),
                  kPrimaryColor.withOpacity(0.05 + (_gradientAnimation.value * 0.1)),
                  Colors.white,
                  kPrimaryColor.withOpacity(0.05 + (_gradientAnimation.value * 0.1)),
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Animated Background Circles
                ...List.generate(6, (index) => _buildBackgroundCircle(index)),

                // Confetti Effect
                if (_confettiAnimation.value > 0)
                  ...List.generate(40, (index) => _buildConfettiParticle(index)),

                // Main Content
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: SlideTransition(
                          position: _cardSlideAnimation,
                          child: ScaleTransition(
                            scale: _cardScaleAnimation,
                            child: FadeTransition(
                              opacity: _backgroundFadeAnimation,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white,
                                      Colors.white.withOpacity(0.95),
                                      Colors.white.withOpacity(0.9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimaryColor.withOpacity(0.15),
                                      blurRadius: 40,
                                      offset: const Offset(0, 20),
                                      spreadRadius: 0,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: kPrimaryColor.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Success Icon with Enhanced Pulse Effect
                                    ScaleTransition(
                                      scale: _pulseAnimation,
                                      child: RotationTransition(
                                        turns: _checkRotationAnimation,
                                        child: FadeTransition(
                                          opacity: _checkFadeAnimation,
                                          child: ScaleTransition(
                                            scale: _checkScaleAnimation,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                // Outer ring
                                                Container(
                                                  width: 140,
                                                  height: 140,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: kPrimaryColor.withOpacity(0.2),
                                                      width: 3,
                                                    ),
                                                  ),
                                                ),
                                                // Main success circle
                                                Container(
                                                  width: 120,
                                                  height: 120,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                      colors: [
                                                        kPrimaryColor,
                                                        kPrimaryColor.withOpacity(0.8),
                                                      ],
                                                    ),
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: kPrimaryColor.withOpacity(0.4),
                                                        blurRadius: 25,
                                                        offset: const Offset(0, 12),
                                                      ),
                                                      BoxShadow(
                                                        color: kPrimaryColor.withOpacity(0.2),
                                                        blurRadius: 40,
                                                        offset: const Offset(0, 20),
                                                      ),
                                                    ],
                                                  ),
                                                  child: const Icon(
                                                    Icons.check_rounded,
                                                    color: Colors.white,
                                                    size: 60,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 30),

                                    // Success Title
                                    SlideTransition(
                                      position: _titleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _titleFadeAnimation,
                                        child: ShaderMask(
                                          shaderCallback: (bounds) => LinearGradient(
                                            colors: [
                                              kPrimaryColor,
                                              kPrimaryColor.withOpacity(0.8),
                                            ],
                                          ).createShader(bounds),
                                          child: const Text(
                                            '🎉 Order Placed Successfully!',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              height: 1.2,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 20),

                                    // Order ID with Enhanced Design
                                    SlideTransition(
                                      position: _subtitleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _subtitleFadeAnimation,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                kPrimaryColor.withOpacity(0.1),
                                                kPrimaryColor.withOpacity(0.05),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: kPrimaryColor.withOpacity(0.3),
                                              width: 1.5,
                                            ),
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
                                              Text(
                                                'Order ID',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: kPrimaryColor.withOpacity(0.8),
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                widget.orderId,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: kPrimaryColor,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Enhanced Details Section
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                kPrimaryColor.withOpacity(0.05),
                                                kPrimaryColor.withOpacity(0.02),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: kPrimaryColor.withOpacity(0.15),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              _buildDetailRow(
                                                Icons.schedule_rounded,
                                                'Your laundry will be picked up as scheduled',
                                                kPrimaryColor,
                                              ),
                                              const SizedBox(height: 12),
                                              _buildDetailRow(
                                                Icons.notifications_active_rounded,
                                                'You\'ll receive updates via SMS and notifications',
                                                kPrimaryColor.withOpacity(0.8),
                                              ),
                                              const SizedBox(height: 12),
                                              _buildDetailRow(
                                                Icons.support_agent_rounded,
                                                '24/7 customer support available',
                                                kPrimaryColor.withOpacity(0.7),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 30),

                                    // Enhanced Action Buttons
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(20),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: kPrimaryColor.withOpacity(0.2),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: OutlinedButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  style: OutlinedButton.styleFrom(
                                                    side: BorderSide(
                                                      color: kPrimaryColor,
                                                      width: 2,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                                    backgroundColor: Colors.white,
                                                  ),
                                                  child: Text(
                                                    'Track Order',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: kPrimaryColor,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              flex: 2,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(20),
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      kPrimaryColor,
                                                      kPrimaryColor.withOpacity(0.8),
                                                    ],
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: kPrimaryColor.withOpacity(0.4),
                                                      blurRadius: 15,
                                                      offset: const Offset(0, 6),
                                                    ),
                                                  ],
                                                ),
                                                child: ElevatedButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.transparent,
                                                    shadowColor: Colors.transparent,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                                  ),
                                                  child: const Text(
                                                    'Continue Shopping',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundCircle(int index) {
    final random = (index * 234) % 1000;
    final size = 80.0 + (random % 120);
    final left = (random % 100) / 100.0;
    final top = ((random * 3) % 100) / 100.0;
    final opacity = 0.03 + (random % 5) / 100.0;

    return Positioned(
      left: MediaQuery.of(context).size.width * left - size / 2,
      top: MediaQuery.of(context).size.height * top - size / 2,
      child: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_gradientAnimation.value * 0.3),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kPrimaryColor.withOpacity(opacity),
                    kPrimaryColor.withOpacity(opacity * 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfettiParticle(int index) {
    final random = (index * 456) % 1000;
    final startX = (random % 100) / 100.0;
    final duration = 3000 + (random % 1500);
    final size = 6.0 + (random % 8);
    final colors = [
      kPrimaryColor,
      kPrimaryColor.withOpacity(0.8),
      kPrimaryColor.withOpacity(0.6),
      Colors.white,
      Colors.yellow.shade400,
      Colors.orange.shade400,
    ];
    final color = colors[random % colors.length];

    return Positioned(
      left: MediaQuery.of(context).size.width * startX,
      top: -30 + (_confettiAnimation.value * (MediaQuery.of(context).size.height + 60)),
      child: Transform.rotate(
        angle: _confettiAnimation.value * 6.28 * 4, // 4 full rotations
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color,
                color.withOpacity(0.7),
              ],
            ),
            shape: random % 3 == 0 ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: random % 3 != 0 ? BorderRadius.circular(3) : null,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}