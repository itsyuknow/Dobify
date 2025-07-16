// Import statements remain the same
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';

class AddAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? existingData;
  const AddAddressScreen({Key? key, this.existingData}) : super(key: key);

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final localityCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final stateCtrl = TextEditingController();
  final zipCtrl = TextEditingController();
  final countryCtrl = TextEditingController();
  final otherTitleCtrl = TextEditingController();

  LatLng? selectedLocation;
  bool isDefault = false;
  String selectedType = 'home';

  bool get isEditing => widget.existingData != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final data = widget.existingData!;
      nameCtrl.text = data['contact_name'] ?? '';
      phoneCtrl.text = data['phone'] ?? '';
      selectedType = data['title'] ?? 'home';
      if (!['home', 'work'].contains(selectedType)) {
        otherTitleCtrl.text = selectedType;
        selectedType = 'other';
      }
      streetCtrl.text = data['street'] ?? '';
      localityCtrl.text = data['locality'] ?? '';
      cityCtrl.text = data['city'] ?? '';
      stateCtrl.text = data['state'] ?? '';
      zipCtrl.text = data['zip_code'] ?? '';
      countryCtrl.text = data['country'] ?? '';
      isDefault = data['is_default'] ?? false;
      final lat = data['lat'] ?? 0.0;
      final lng = data['lng'] ?? 0.0;
      selectedLocation = LatLng(lat, lng);
    }
  }

  Future<void> _fetchFromPincode() async {
    final pincode = zipCtrl.text.trim();
    if (pincode.isEmpty) return _showSnackBar('Please enter a pincode');

    final url = 'https://api.postalpincode.in/pincode/$pincode';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = json.decode(response.body);
        if (jsonResponse.isNotEmpty && jsonResponse[0]['Status'] == 'Success') {
          final po = jsonResponse[0]['PostOffice'][0];
          setState(() {
            cityCtrl.text = po['District'] ?? '';
            stateCtrl.text = po['State'] ?? '';
            countryCtrl.text = po['Country'] ?? 'India';
            localityCtrl.text = po['Name'] ?? '';
          });
          await _updateLocationFromAddress('$pincode, ${po['State']}, ${po['Country']}');
        } else {
          _showSnackBar('Invalid pincode or no data found');
        }
      } else {
        _showSnackBar('Failed to fetch data');
      }
    } catch (e) {
      debugPrint('Pincode API error: $e');
      _showSnackBar('Error fetching data');
    }
  }

  Future<void> _updateLocationFromAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        selectedLocation = LatLng(loc.latitude, loc.longitude);
        setState(() {});
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    }
  }

  Future<void> _showMapSelector() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectFromMapScreen(initialLocation: selectedLocation),
      ),
    );

    if (result != null && result is Map) {
      selectedLocation = result['latlng'];
      streetCtrl.text = result['street'] ?? '';
      localityCtrl.text = result['locality'] ?? '';
      cityCtrl.text = result['city'] ?? '';
      stateCtrl.text = result['state'] ?? '';
      zipCtrl.text = result['zip'] ?? '';
      countryCtrl.text = result['country'] ?? '';
      setState(() {});
    }
  }


  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        streetCtrl.text = place.street ?? '';
        localityCtrl.text = place.subLocality ?? '';
        cityCtrl.text = place.locality ?? '';
        stateCtrl.text = place.administrativeArea ?? '';
        zipCtrl.text = place.postalCode ?? '';
        countryCtrl.text = place.country ?? '';
        setState(() {});
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate() || selectedLocation == null) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final title = selectedType == 'other' ? otherTitleCtrl.text.trim() : selectedType;

    final data = {
      'user_id': userId,
      'contact_name': nameCtrl.text.trim(),
      'phone': phoneCtrl.text.trim(),
      'title': title,
      'street': streetCtrl.text.trim(),
      'locality': localityCtrl.text.trim(),
      'city': cityCtrl.text.trim(),
      'state': stateCtrl.text.trim(),
      'zip_code': zipCtrl.text.trim(),
      'country': countryCtrl.text.trim(),
      'lat': selectedLocation!.latitude,
      'lng': selectedLocation!.longitude,
      'is_default': isDefault,
    };

    dynamic newId;
    if (isEditing) {
      await supabase.from('user_addresses').update(data).eq('id', widget.existingData!['id']);
      newId = widget.existingData!['id'];
    } else {
      final res = await supabase.from('user_addresses').insert(data).select().single();
      newId = res['id'];
    }

    if (!mounted) return;
    Navigator.pop(context, {'refresh': true, 'selected': newId});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Address' : 'Add Address'),
        backgroundColor: kPrimaryColor,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ElevatedButton.icon(
              onPressed: _showMapSelector,
              icon: const Icon(Icons.location_on),
              label: const Text("Select Location on Map"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(zipCtrl, 'Pincode', TextInputType.number, suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _fetchFromPincode,
            )),
            _buildTextField(nameCtrl, 'Full Name', TextInputType.text),
            _buildTextField(phoneCtrl, 'Phone Number', TextInputType.phone),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['home', 'work', 'other']
                  .map((type) => _buildTypeChip(type))
                  .toList(),
            ),
            if (selectedType == 'other')
              _buildTextField(
                  otherTitleCtrl, 'Custom Label (e.g. Friend\'s House)', TextInputType.text),
            _buildTextField(streetCtrl, 'Street Address', TextInputType.streetAddress),
            _buildTextField(localityCtrl, 'Locality', TextInputType.text),
            _buildTextField(cityCtrl, 'City', TextInputType.text),
            _buildTextField(stateCtrl, 'State', TextInputType.text),
            _buildTextField(countryCtrl, 'Country', TextInputType.text),
            const SizedBox(height: 12),
            SwitchListTile(
              value: isDefault,
              onChanged: (val) => setState(() => isDefault = val),
              title: const Text('Set as default address'),
              activeColor: kPrimaryColor,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                isEditing ? 'Update Address' : 'Save Address',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, TextInputType type,
      {Widget? suffixIcon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    final isSelected = selectedType == type;
    final icons = {
      'home': Icons.home,
      'work': Icons.work,
      'other': Icons.more_horiz,
    };
    return ChoiceChip(
      label: Row(
        children: [
          Icon(icons[type]!, size: 16, color: isSelected ? Colors.white : kPrimaryColor),
          const SizedBox(width: 4),
          Text(type[0].toUpperCase() + type.substring(1)),
        ],
      ),
      selected: isSelected,
      selectedColor: kPrimaryColor,
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      onSelected: (_) => setState(() => selectedType = type),
    );
  }
}

class SelectFromMapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const SelectFromMapScreen({Key? key, this.initialLocation}) : super(key: key);

  @override
  State<SelectFromMapScreen> createState() => _SelectFromMapScreenState();
}

class _SelectFromMapScreenState extends State<SelectFromMapScreen> {
  GoogleMapController? _mapController;
  LatLng? selected;
  bool isMapReady = false;

  @override
  void initState() {
    super.initState();
    _setInitialLocation();
  }

  Future<void> _setInitialLocation() async {
    if (widget.initialLocation != null) {
      selected = widget.initialLocation!;
    } else {
      final pos = await Geolocator.getCurrentPosition();
      selected = LatLng(pos.latitude, pos.longitude);
    }
    setState(() {});
  }

  Future<void> _reverseGeocodeToParent(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Send updated data back to parent screen
        Navigator.pop(context, {
          'latlng': location,
          'street': place.street ?? '',
          'locality': place.subLocality ?? '',
          'city': place.locality ?? '',
          'state': place.administrativeArea ?? '',
          'zip': place.postalCode ?? '',
          'country': place.country ?? '',
        });
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() => isMapReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick Location'), backgroundColor: kPrimaryColor),
      body: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: selected!, zoom: 16),
            onCameraMove: (pos) => selected = pos.target,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Static center pin
          const Icon(Icons.location_on, size: 40, color: Colors.redAccent),

          // Floating Refresh Pin Button
          Positioned(
            top: 90,
            right: 15,
            child: FloatingActionButton.small(
              heroTag: "refresh_pin",
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: () async {
                final pos = await Geolocator.getCurrentPosition();
                final current = LatLng(pos.latitude, pos.longitude);
                setState(() => selected = current);
                _mapController?.animateCamera(CameraUpdate.newLatLng(current));
              },
              child: const Icon(Icons.refresh, color: Colors.black87),
            ),
          ),

          // Bottom Buttons
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () async {
                      final pos = await Geolocator.getCurrentPosition();
                      final current = LatLng(pos.latitude, pos.longitude);
                      selected = current;
                      _mapController?.animateCamera(CameraUpdate.newLatLng(current));
                      await _reverseGeocodeToParent(current);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kPrimaryColor, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.my_location, color: kPrimaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Use My Current Location',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => _reverseGeocodeToParent(selected!),
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text("Confirm Location"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
