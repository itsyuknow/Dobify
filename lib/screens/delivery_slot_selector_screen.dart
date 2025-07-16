import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'colors.dart';

class DeliverySlotSelectorScreen extends StatefulWidget {
  final String deliveryType; // "Express" or "Standard"
  final DateTime selectedDate;

  const DeliverySlotSelectorScreen({
    super.key,
    required this.deliveryType,
    required this.selectedDate,
  });

  @override
  State<DeliverySlotSelectorScreen> createState() => _DeliverySlotSelectorScreenState();
}

class _DeliverySlotSelectorScreenState extends State<DeliverySlotSelectorScreen> {
  final supabase = Supabase.instance.client;
  Map<String, List<Map<String, dynamic>>> slotMap = {}; // pickup_slot => list of delivery_slot
  List<String> bannerUrls = []; // To hold banner images
  String? backgroundImageUrl; // To hold background image URL
  bool loading = true;
  String? selectedPickupSlot;
  String? selectedDeliverySlot;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    fetchSlots();
    fetchBanners(); // Fetch banners from Supabase
    fetchBackgroundImage(); // Fetch background image URL from Supabase
  }

  // Fetch delivery slots
  Future<void> fetchSlots() async {
    try {
      final List result = await supabase
          .from('delivery_slot_matrix')
          .select()
          .eq('delivery_type', widget.deliveryType)
          .eq('is_available', true); // Only fetch available slots

      if (result.isEmpty) {
        debugPrint("No data found for this delivery type.");
        setState(() {
          loading = false;
        });
        return;
      }

      Map<String, List<Map<String, dynamic>>> map = {};

      for (final row in result) {
        final pickup = row['pickup_slot'] ?? 'Unknown';
        final delivery = row['delivery_slot'] ?? 'Unknown';
        final nextDay = row['is_next_day'] ?? false;

        map.putIfAbsent(pickup, () => []);
        map[pickup]!.add({
          'slot': delivery,
          'nextDay': nextDay,
        });
      }

      setState(() {
        slotMap = map;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading slots: $e");
      setState(() => loading = false);
    }
  }

  // Fetch dynamic banners from Supabase
  Future<void> fetchBanners() async {
    try {
      final List bannerResult = await supabase
          .from('banners')
          .select()
          .eq('is_active', true);

      setState(() {
        bannerUrls = bannerResult.map<String>((e) => e['image_url'] as String).toList();
      });
    } catch (e) {
      debugPrint("Error loading banners: $e");
    }
  }

  // Fetch background image from Supabase
  Future<void> fetchBackgroundImage() async {
    try {
      final List result = await supabase
          .from('ui_assets')
          .select()
          .eq('key', 'home_bg') // Filter by the 'home_bg' key for the background image
          .limit(1); // Fetch one background image

      if (result.isNotEmpty) {
        setState(() {
          backgroundImageUrl = result[0]['background_url']; // Assume the column name is 'background_url'
        });
      }
    } catch (e) {
      debugPrint("Error loading background image: $e");
    }
  }

  // Handle button click with animation
  void onConfirmPressed() {
    setState(() {
      _isAnimating = true;
    });

    Future.delayed(Duration(milliseconds: 800), () {
      setState(() {
        _isAnimating = false;
      });
      // Use Navigator.pop() to go back with the selected data
      Navigator.pop(context, {
        'pickup_slot': selectedPickupSlot,
        'delivery_slot': selectedDeliverySlot,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deliveryType} Slots'),
        backgroundColor: kPrimaryColor,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: backgroundImageUrl != null
                ? NetworkImage(backgroundImageUrl!)
                : const AssetImage('assets/default_background.jpg') as ImageProvider, // Default image if URL is not available
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Banner carousel
              if (bannerUrls.isNotEmpty)
                CarouselSlider(
                  options: CarouselOptions(
                    height: 150,
                    autoPlay: true,
                    enlargeCenterPage: true,
                    viewportFraction: 0.9,
                  ),
                  items: bannerUrls.map((url) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    );
                  }).toList(),
                ),
              SizedBox(height: 20),
              Row(
                children: const [
                  Text("Pickup Slot", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  SizedBox(width: 8),
                ],
              ),
              Expanded(
                child: Row(
                  children: [
                    // Left Column: Pickup Slots
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.deliveryType == "Express")
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                "Choose your comfortable pickup slot time",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.yellow.shade700,
                                ),
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: slotMap.keys.length,
                              itemBuilder: (context, index) {
                                final pickupSlot = slotMap.keys.elementAt(index);
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedPickupSlot = pickupSlot;
                                      selectedDeliverySlot = null; // Reset delivery slot if pickup is changed
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: selectedPickupSlot == pickupSlot
                                          ? Colors.blue.shade100
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.2),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.access_time, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            pickupSlot,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: selectedPickupSlot == pickupSlot
                                                  ? Colors.blue
                                                  : Colors.black,
                                            ),
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
                    ),
                    const SizedBox(width: 12),
                    // Right Column: Delivery Slots based on selected Pickup Slot
                    Expanded(
                      flex: 3,
                      child: selectedPickupSlot == null
                          ? const Center(child: Text("Please select a pickup slot"))
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              "Choose your comfortable delivery slot",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700, // Changed to green
                              ),
                            )

                          ),
                          Expanded(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: slotMap[selectedPickupSlot]!.map((slot) {
                                final slotLabel = slot['slot'];
                                final nextDay = slot['nextDay'] == true;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedDeliverySlot = slotLabel;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: selectedDeliverySlot == slotLabel
                                          ? Colors.blue.shade100
                                          : (nextDay ? Colors.orange.shade100 : Colors.green.shade100),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.3),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                        ),
                                      ],
                                      border: Border.all(
                                        color: nextDay ? Colors.orange : Colors.green,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          slotLabel,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: nextDay
                                                ? Colors.orange.shade800
                                                : Colors.green.shade800,
                                          ),
                                        ),
                                        if (nextDay)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: Text(
                                              "Next Day",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.orange,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Confirm Button with Animation
              GestureDetector(
                onTap: selectedPickupSlot != null && selectedDeliverySlot != null ? onConfirmPressed : null,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                  width: double.infinity, // Full width
                  decoration: BoxDecoration(
                    color: _isAnimating ? Colors.grey : Colors.blue,
                    borderRadius: BorderRadius.circular(12), // Rounded corners for premium look
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        spreadRadius: 2,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Text(
                    'Confirm Selection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Create CheckoutScreen (or any page you need to go after confirming)
class CheckoutScreen extends StatelessWidget {
  final String pickupSlot;
  final String deliverySlot;

  const CheckoutScreen({
    Key? key,
    required this.pickupSlot,
    required this.deliverySlot,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Checkout"),
        backgroundColor: kPrimaryColor,
      ),
      body: Center(
        child: Text(
          "Checkout with Pickup Slot: $pickupSlot\nDelivery Slot: $deliverySlot",
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
