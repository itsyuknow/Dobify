import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'colors.dart'; // Your theme colors

class SlotSelectionScreen extends StatefulWidget {
  final double totalAmount;
  final Function(double) onDeliveryTypeChanged;
  final double standardDeliveryFee;
  final double expressDeliveryFee;

  const SlotSelectionScreen({
    super.key,
    required this.totalAmount,
    required this.onDeliveryTypeChanged,
    required this.standardDeliveryFee,
    required this.expressDeliveryFee,
  });

  @override
  State<SlotSelectionScreen> createState() => _SlotSelectionScreenState();
}

class _SlotSelectionScreenState extends State<SlotSelectionScreen> {
  final supabase = Supabase.instance.client;
  bool _isExpressDelivery = false;
  String? _selectedPickupSlot;
  String? _selectedDeliverySlot;
  DateTime _selectedDate = DateTime.now();
  List<DateTime> _availableDates = [];
  List<String> _availablePickupSlots = [];
  List<String> _availableDeliverySlots = [];
  bool _loadingSlots = true;
  bool _loadingAddress = true;
  List<Map<String, dynamic>> _addresses = [];
  Map<String, dynamic>? _selectedAddress;
  final TextEditingController _addressController = TextEditingController();
  LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _generateAvailableDates(),
      _loadUserAddresses(),
    ]);
    await _loadAvailableSlots();
  }

  Future<void> _generateAvailableDates() async {
    final now = DateTime.now();
    _availableDates = List.generate(7, (index) {
      return DateTime(now.year, now.month, now.day + index);
    });
    _selectedDate = _availableDates.firstWhere(
          (date) => date.day >= now.day,
      orElse: () => _availableDates.first,
    );
  }

  Future<void> _loadUserAddresses() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('address_book')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false);

      setState(() {
        _addresses = List<Map<String, dynamic>>.from(response);
        _selectedAddress = _addresses.isNotEmpty ? _addresses.first : null;
        _loadingAddress = false;
      });
    } catch (e) {
      print("Error loading addresses: $e");
      setState(() {
        _loadingAddress = false;
      });
    }
  }

  // In your slot_selection_screen.dart file
  Future<void> _loadAvailableSlots() async {
    setState(() {
      _loadingSlots = true;
      _selectedPickupSlot = null;
      _selectedDeliverySlot = null;
      _availablePickupSlots = [];
      _availableDeliverySlots = [];
    });

    try {
      // All possible slots
      final allSlots = _isExpressDelivery
          ? [
        '08:00 AM - 10:00 AM',
        '10:00 AM - 12:00 PM',
        '12:00 PM - 02:00 PM',
        '02:00 PM - 04:00 PM',
        '04:00 PM - 06:00 PM',
        '06:00 PM - 08:00 PM',
        '08:00 PM - 10:00 PM',
      ]
          : [
        '08:00 AM - 10:00 AM',
        '10:00 AM - 12:00 PM',
        '12:00 PM - 02:00 PM',
        '02:00 PM - 04:00 PM',
        '04:00 PM - 06:00 PM',
        '06:00 PM - 08:00 PM',
        '08:00 PM - 10:00 PM',
      ];

      final now = DateTime.now();
      final isToday = _selectedDate.day == now.day &&
          _selectedDate.month == now.month &&
          _selectedDate.year == now.year;

      if (isToday) {
        // For today, filter slots that haven't passed yet
        _availablePickupSlots = allSlots.where((slot) {
          final startTimeStr = slot.split(' - ')[0];
          final startTime = _parseTimeOfDay(startTimeStr);
          final currentTime = TimeOfDay.fromDateTime(now);

          return startTime.hour > currentTime.hour ||
              (startTime.hour == currentTime.hour && startTime.minute >= currentTime.minute);
        }).toList();
      } else {
        // For future dates, show all slots
        _availablePickupSlots = List.from(allSlots);
      }

      setState(() {
        _loadingSlots = false;
      });
    } catch (e) {
      print("Error loading slots: $e");
      setState(() {
        _loadingSlots = false;
        _availablePickupSlots = [];
      });
    }
  }

// Helper function to parse time string into TimeOfDay
  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(' ');
    if (parts.length != 2) throw FormatException('Invalid time format');

    final timeParts = parts[0].split(':');
    if (timeParts.length != 2) throw FormatException('Invalid time format');

    int hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final period = parts[1].toUpperCase();

    // Convert to 24-hour format
    if (period == 'PM' && hour != 12) {
      hour += 12;
    } else if (period == 'AM' && hour == 12) {
      hour = 0;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _loadDeliverySlots(String pickupSlot) async {
    setState(() {
      _loadingSlots = true;
      _selectedDeliverySlot = null;
      _availableDeliverySlots = [];
    });

    try {
      // Split the pickup slot into start and end times
      final times = pickupSlot.split(' - ');
      if (times.length != 2) {
        throw Exception('Invalid pickup slot format');
      }

      final pickupStartTime = times[0];
      final pickupEndTime = times[1];

      // Parse the start time
      final startTime = _parseTime(pickupStartTime);

      if (_isExpressDelivery) {
        // Express delivery slots (4-6 hours after pickup start)
        final slot1Start = _addHours(startTime, 4);
        final slot1End = _addHours(startTime, 6);
        final slot2Start = _addHours(startTime, 6);
        final slot2End = _addHours(startTime, 8);

        _availableDeliverySlots = [
          '${_formatTime(slot1Start)} - ${_formatTime(slot1End)}',
          '${_formatTime(slot2Start)} - ${_formatTime(slot2End)}',
        ];
      } else {
        // Standard delivery slots (8-12 hours after pickup start)
        final slot1Start = _addHours(startTime, 8);
        final slot1End = _addHours(startTime, 10);
        final slot2Start = _addHours(startTime, 10);
        final slot2End = _addHours(startTime, 12);

        _availableDeliverySlots = [
          '${_formatTime(slot1Start)} - ${_formatTime(slot1End)}',
          '${_formatTime(slot2Start)} - ${_formatTime(slot2End)}',
        ];
      }

      setState(() {
        _loadingSlots = false;
      });
    } catch (e) {
      print("Error loading delivery slots: $e");
      setState(() {
        _loadingSlots = false;
        _availableDeliverySlots = ['Error loading slots'];
      });
    }
  }

  DateTime _parseTime(String timeStr) {
    final parts = timeStr.split(' ');
    if (parts.length != 2) throw Exception('Invalid time format');

    final timeParts = parts[0].split(':');
    if (timeParts.length != 2) throw Exception('Invalid time format');

    int hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final period = parts[1].toUpperCase();

    // Convert to 24-hour format
    if (period == 'PM' && hour != 12) {
      hour += 12;
    } else if (period == 'AM' && hour == 12) {
      hour = 0;
    }

    // Use the selected date as base
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour,
      minute,
    );
  }

  DateTime _addHours(DateTime time, int hours) {
    return time.add(Duration(hours: hours));
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : hour == 0 ? 12 : hour;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _toggleDeliveryType(bool value) async {
    setState(() {
      _isExpressDelivery = value;
      _selectedPickupSlot = null;
      _selectedDeliverySlot = null;
      _availableDeliverySlots = [];
    });

    // Update the total amount with new delivery fee
    widget.onDeliveryTypeChanged(
      value ? widget.expressDeliveryFee : widget.standardDeliveryFee,
    );

    await _loadAvailableSlots();
  }

  Future<void> _selectAddress() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return AddressSelectionBottomSheet(
          addresses: _addresses,
          selectedAddress: _selectedAddress,
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedAddress = result;
      });
    }
  }

  Future<void> _addNewAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(),
      ),
    );

    if (result == true) {
      await _loadUserAddresses();
    }
  }

  Future<void> _proceedToPayment() async {
    if (_selectedPickupSlot == null || _selectedDeliverySlot == null || _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select pickup slot, delivery slot, and address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Reserve the slots
    try {
      await supabase.rpc('reserve_slots', params: {
        'pickup_date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'pickup_slot': _selectedPickupSlot,
        'delivery_slot': _selectedDeliverySlot,
      });

      // Navigate to payment screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            totalAmount: widget.totalAmount,
            pickupSlot: '${DateFormat('EEE, MMM d').format(_selectedDate)} - $_selectedPickupSlot',
            deliverySlot: '${DateFormat('EEE, MMM d').format(_selectedDate)} - $_selectedDeliverySlot',
            deliveryType: _isExpressDelivery ? 'Express' : 'Standard',
            address: _selectedAddress!,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reserve slots: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = widget.totalAmount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Select Delivery Slot'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Address Section
                  _buildAddressSection(),

                  const SizedBox(height: 24),

                  // Delivery Type Toggle
                  _buildDeliveryTypeToggle(),

                  const SizedBox(height: 24),

                  // Date Selection
                  _buildDateSelector(),

                  const SizedBox(height: 24),

                  // Pickup Slot Selection
                  _buildSlotSelection(
                    title: 'Select Pickup Slot',
                    slots: _availablePickupSlots,
                    selectedSlot: _selectedPickupSlot,
                    onSelected: (slot) async {
                      setState(() {
                        _selectedPickupSlot = slot;
                        _selectedDeliverySlot = null;
                      });
                      await _loadDeliverySlots(slot);
                    },
                  ),

                  const SizedBox(height: 24),

                  // Delivery Slot Selection
                  if (_selectedPickupSlot != null)
                    _buildSlotSelection(
                      title: 'Select Delivery Slot',
                      slots: _availableDeliverySlots,
                      selectedSlot: _selectedDeliverySlot,
                      onSelected: (slot) {
                        setState(() {
                          _selectedDeliverySlot = slot;
                        });
                      },
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Bottom Payment Bar
          _buildBottomPaymentBar(totalAmount),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Address',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (_loadingAddress)
          const Center(child: CircularProgressIndicator()),

        if (!_loadingAddress && _selectedAddress != null)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedAddress!['address_type'] == 'home'
                            ? Icons.home
                            : _selectedAddress!['address_type'] == 'work'
                            ? Icons.work
                            : Icons.location_on,
                        color: kPrimaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedAddress!['address_type'].toString().toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                      if (_selectedAddress!['is_default'] == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedAddress!['full_address'],
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedAddress!['city']}, ${_selectedAddress!['pincode']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _selectAddress,
                        child: const Text('Change Address'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _addNewAddress,
                        child: const Text('Add New'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        if (!_loadingAddress && _selectedAddress == null)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.location_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  const Text(
                    'No Address Added',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _addNewAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Add Address'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDeliveryTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Type',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleDeliveryType(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isExpressDelivery ? kPrimaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'Standard',
                        style: TextStyle(
                          color: !_isExpressDelivery ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _toggleDeliveryType(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isExpressDelivery ? kPrimaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'Express',
                        style: TextStyle(
                          color: _isExpressDelivery ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isExpressDelivery
              ? 'Express delivery will arrive within 4-6 hours after pickup'
              : 'Standard delivery will arrive within 8-12 hours after pickup',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableDates.length,
            itemBuilder: (context, index) {
              final date = _availableDates[index];
              final isSelected = date.day == _selectedDate.day;
              final isToday = date.day == DateTime.now().day;

              return GestureDetector(
                onTap: () async {
                  setState(() {
                    _selectedDate = date;
                    _selectedPickupSlot = null;
                    _selectedDeliverySlot = null;
                  });
                  await _loadAvailableSlots();
                },
                child: Container(
                  width: 60,
                  margin: EdgeInsets.only(right: index < _availableDates.length - 1 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: isSelected ? kPrimaryColor : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date.day.toString(),
                        style: TextStyle(
                          fontSize: 20,
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          height: 4,
                          width: 4,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
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
    );
  }

  Widget _buildSlotSelection({
    required String title,
    required List<String> slots,
    required String? selectedSlot,
    required Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (_loadingSlots)
          const Center(child: CircularProgressIndicator()),

        if (!_loadingSlots && slots.isEmpty)
          const Text(
            'No slots available for selected date',
            style: TextStyle(color: Colors.grey),
          ),

        if (!_loadingSlots && slots.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((slot) {
              final isSelected = slot == selectedSlot;
              return GestureDetector(
                onTap: () => onSelected(slot),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? kPrimaryColor : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? kPrimaryColor : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    slot,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildBottomPaymentBar(double totalAmount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                '₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: _proceedToPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Proceed to Payment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

extension on PostgrestFilterBuilder<PostgrestList> {
  in_(String s, List<String> deliverySlots) {}
}

// Address Selection Bottom Sheet
class AddressSelectionBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> addresses;
  final Map<String, dynamic>? selectedAddress;

  const AddressSelectionBottomSheet({
    super.key,
    required this.addresses,
    this.selectedAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select Address',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final address = addresses[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      address['address_type'] == 'home'
                          ? Icons.home
                          : address['address_type'] == 'work'
                          ? Icons.work
                          : Icons.location_on,
                      color: kPrimaryColor,
                    ),
                    title: Text(address['full_address']),
                    subtitle: Text(
                        '${address['city']}, ${address['pincode']}'),
                    trailing: selectedAddress?['id'] == address['id']
                        ? const Icon(Icons.check_circle, color: kPrimaryColor)
                        : null,
                    onTap: () => Navigator.pop(context, address),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddAddressScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add New Address'),
          ),
        ],
      ),
    );
  }
}

// Add Address Screen
class AddAddressScreen extends StatefulWidget {
  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullAddressController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  String _addressType = 'home';
  bool _isDefault = false;
  bool _loadingLocation = false;
  LatLng? _selectedLocation;

  @override
  void dispose() {
    _fullAddressController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
    });

    try {
      // Check permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition();
      _selectedLocation = LatLng(position.latitude, position.longitude);

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        _fullAddressController.text =
        '${place.street}, ${place.subLocality}, ${place.locality}';
        _cityController.text = place.locality ?? '';
        _stateController.text = place.administrativeArea ?? '';
        _pincodeController.text = place.postalCode ?? '';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _loadingLocation = false;
      });
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // If marking as default, first unset any existing default
      if (_isDefault) {
        await supabase
            .from('address_book')
            .update({'is_default': false})
            .eq('user_id', userId)
            .eq('is_default', true);
      }

      // Insert new address
      await supabase.from('address_book').insert({
        'user_id': userId,
        'address_type': _addressType,
        'full_address': _fullAddressController.text,
        'landmark': _landmarkController.text.isNotEmpty ? _landmarkController.text : null,
        'city': _cityController.text,
        'state': _stateController.text,
        'pincode': _pincodeController.text,
        'latitude': _selectedLocation?.latitude,
        'longitude': _selectedLocation?.longitude,
        'is_default': _isDefault,
      });

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save address: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Address'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Address Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildAddressTypeButton('Home', Icons.home, 'home'),
                  const SizedBox(width: 8),
                  _buildAddressTypeButton('Work', Icons.work, 'work'),
                  const SizedBox(width: 8),
                  _buildAddressTypeButton('Other', Icons.location_on, 'other'),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _fullAddressController,
                decoration: const InputDecoration(
                  labelText: 'Full Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter full address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _landmarkController,
                decoration: const InputDecoration(
                  labelText: 'Landmark (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter city';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter state';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pincodeController,
                decoration: const InputDecoration(
                  labelText: 'Pincode',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter pincode';
                  }
                  if (value.length != 6) {
                    return 'Pincode must be 6 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Checkbox(
                    value: _isDefault,
                    onChanged: (value) {
                      setState(() {
                        _isDefault = value ?? false;
                      });
                    },
                  ),
                  const Text('Set as default address'),
                ],
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: _loadingLocation
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.location_on),
                label: const Text('Use Current Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saveAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Save Address'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressTypeButton(String label, IconData icon, String type) {
    final isSelected = _addressType == type;
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _addressType = type;
          });
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? kPrimaryColor.withOpacity(0.1) : null,
          side: BorderSide(
            color: isSelected ? kPrimaryColor : Colors.grey.shade300,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? kPrimaryColor : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? kPrimaryColor : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Payment Screen (Placeholder - you'll need to implement this based on your payment gateway)
class PaymentScreen extends StatelessWidget {
  final double totalAmount;
  final String pickupSlot;
  final String deliverySlot;
  final String deliveryType;
  final Map<String, dynamic> address;

  const PaymentScreen({
    super.key,
    required this.totalAmount,
    required this.pickupSlot,
    required this.deliverySlot,
    required this.deliveryType,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Total Amount: ₹$totalAmount'),
            Text('Pickup Slot: $pickupSlot'),
            Text('Delivery Slot: $deliverySlot'),
            Text('Delivery Type: $deliveryType'),
            Text('Address: ${address['full_address']}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Implement payment logic
              },
              child: const Text('Pay Now'),
            ),
          ],
        ),
      ),
    );
  }
}