import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _loadBillingSettings();
    _loadSlots();
    _loadDefaultAddress();
  }

  @override
  void dispose() {
    _pickupDateScrollController.dispose();
    _deliveryDateScrollController.dispose();
    super.dispose();
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
    // Proceed to next step (e.g., payment)
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

  Widget _buildBottomBar() {
    double totalAmount = _calculateTotalAmount();
    bool canProceed = selectedAddress != null &&
        selectedPickupSlot != null &&
        selectedDeliverySlot != null &&
        isServiceAvailable &&
        !isLoadingBillingSettings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        color: Colors.white,
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
          ElevatedButton(
            onPressed: canProceed ? _handleProceed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: canProceed ? 6 : 0,
            ),
            child: Text(isLoadingBillingSettings ? "Loading..." : "Proceed", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}