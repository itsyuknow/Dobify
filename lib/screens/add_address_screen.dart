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
  final searchCtrl = TextEditingController();

  LatLng? selectedLocation;
  bool isDefault = false;
  String selectedType = 'home';
  List<Map<String, dynamic>> searchSuggestions = [];
  bool isSearching = false;

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

  // Enhanced search with suggestions using Nominatim API
  Future<void> _searchAddress(String query) async {
    if (query.length < 3) {
      setState(() {
        searchSuggestions = [];
      });
      return;
    }

    setState(() {
      isSearching = true;
    });

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&countrycodes=in';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'IronXpress/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          searchSuggestions = data.map((item) => {
            'display_name': item['display_name'] as String,
            'lat': double.parse(item['lat'] as String),
            'lon': double.parse(item['lon'] as String),
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      setState(() {
        isSearching = false;
      });
    }
  }

  Future<void> _selectSearchSuggestion(Map<String, dynamic> suggestion) async {
    final lat = suggestion['lat'] as double;
    final lon = suggestion['lon'] as double;

    selectedLocation = LatLng(lat, lon);
    searchCtrl.text = suggestion['display_name'];

    await _reverseGeocode(lat, lon);

    setState(() {
      searchSuggestions = [];
    });

    _showSnackBar('Location selected from search');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: kPrimaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate() || selectedLocation == null) {
      _showSnackBar('Please select a location');
      return;
    }

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

    try {
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
      _showSnackBar(isEditing ? 'Address updated successfully' : 'Address saved successfully');
    } catch (e) {
      _showSnackBar('Error saving address: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Address' : 'Add Address',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Search Section
            Container(
              color: Colors.blue,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: searchCtrl,
                      onChanged: _searchAddress,
                      decoration: InputDecoration(
                        hintText: 'Search for area, street name...',
                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                        suffixIcon: isSearching
                            ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kPrimaryColor,
                            ),
                          ),
                        )
                            : searchCtrl.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            searchCtrl.clear();
                            setState(() {
                              searchSuggestions = [];
                            });
                          },
                        )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  // Search Suggestions
                  if (searchSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: searchSuggestions.map((suggestion) {
                          return ListTile(
                            leading: Icon(Icons.location_on, color: kPrimaryColor),
                            title: Text(
                              suggestion['display_name'],
                              style: const TextStyle(fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSearchSuggestion(suggestion),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Map Selector Button
                  Container(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _showMapSelector,
                      icon: const Icon(Icons.location_on, color: Colors.white),
                      label: const Text(
                        "Select Location on Map",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        elevation: 5,
                        shadowColor: kPrimaryColor.withOpacity(0.3),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Location indicator
                  if (selectedLocation != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Location selected successfully',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  _buildTextField(zipCtrl, 'Pincode', TextInputType.number, suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _fetchFromPincode,
                  )),
                  _buildTextField(nameCtrl, 'Full Name', TextInputType.text),
                  _buildTextField(phoneCtrl, 'Phone Number', TextInputType.phone),

                  const SizedBox(height: 16),
                  const Text(
                    'Address Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
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

                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      value: isDefault,
                      onChanged: (val) => setState(() => isDefault = val),
                      title: const Text('Set as default address'),
                      activeColor: kPrimaryColor,
                    ),
                  ),

                  const SizedBox(height: 30),

                  Container(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _saveAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        elevation: 8,
                        shadowColor: kPrimaryColor.withOpacity(0.3),
                      ),
                      child: Text(
                        isEditing ? 'Update Address' : 'Save Address',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, TextInputType type,
      {Widget? suffixIcon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icons[type]!, size: 16, color: isSelected ? Colors.white : kPrimaryColor),
              const SizedBox(width: 4),
              Text(type[0].toUpperCase() + type.substring(1)),
            ],
          ),
          selected: isSelected,
          selectedColor: kPrimaryColor,
          backgroundColor: Colors.grey.shade200,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) => setState(() => selectedType = type),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }
}

class SelectFromMapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const SelectFromMapScreen({Key? key, this.initialLocation}) : super(key: key);

  @override
  State<SelectFromMapScreen> createState() => _SelectFromMapScreenState();
}

class _SelectFromMapScreenState extends State<SelectFromMapScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? selected;
  bool isMapReady = false;
  bool isGettingAddress = false;
  String currentAddress = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _setInitialLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _setInitialLocation() async {
    if (widget.initialLocation != null) {
      selected = widget.initialLocation!;
    } else {
      try {
        final pos = await Geolocator.getCurrentPosition();
        selected = LatLng(pos.latitude, pos.longitude);
      } catch (e) {
        selected = const LatLng(28.6139, 77.2090); // Default to Delhi
      }
    }
    if (selected != null) {
      _getAddressFromLocation(selected!);
    }
    setState(() {});
  }

  Future<void> _getAddressFromLocation(LatLng location) async {
    setState(() {
      isGettingAddress = true;
    });

    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          currentAddress = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}';
        });
      }
    } catch (e) {
      debugPrint("Reverse geocoding failed: $e");
    } finally {
      setState(() {
        isGettingAddress = false;
      });
    }
  }

  Future<void> _reverseGeocodeToParent(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

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
      Navigator.pop(context, {'latlng': location});
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    setState(() => isMapReady = true);
  }

  void _onCameraMove(CameraPosition position) {
    selected = position.target;
    _getAddressFromLocation(position.target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pick Location',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      body: selected == null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimaryColor),
            const SizedBox(height: 16),
            const Text('Loading map...'),
          ],
        ),
      )
          : Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(target: selected!, zoom: 16),
            onCameraMove: _onCameraMove,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Custom Animated Pin
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryColor.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              );
            },
          ),

          // Address Info Card
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: kPrimaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Selected Location',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isGettingAddress)
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Getting address...'),
                      ],
                    )
                  else
                    Text(
                      currentAddress.isNotEmpty ? currentAddress : 'Tap confirm to select this location',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),

          // Current Location Button
          Positioned(
            top: 120,
            right: 15,
            child: FloatingActionButton.small(
              heroTag: "current_location",
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: () async {
                try {
                  final pos = await Geolocator.getCurrentPosition();
                  final current = LatLng(pos.latitude, pos.longitude);
                  setState(() => selected = current);
                  _mapController?.animateCamera(CameraUpdate.newLatLng(current));
                  _getAddressFromLocation(current);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unable to get current location')),
                  );
                }
              },
              child: Icon(Icons.my_location, color: kPrimaryColor),
            ),
          ),

          // Bottom Action Buttons
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                // Use Current Location Button
                Container(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final pos = await Geolocator.getCurrentPosition();
                        final current = LatLng(pos.latitude, pos.longitude);
                        await _reverseGeocodeToParent(current);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to get current location')),
                        );
                      }
                    },
                    icon: const Icon(Icons.my_location, color: Colors.white),
                    label: const Text(
                      'Use My Current Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 5,
                      shadowColor: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // Confirm Location Button
                Container(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () => _reverseGeocodeToParent(selected!),
                    icon: const Icon(Icons.check, size: 22, color: Colors.white),
                    label: const Text(
                      "Confirm Location",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 8,
                      shadowColor: kPrimaryColor.withOpacity(0.3),
                    ),
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