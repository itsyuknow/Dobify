import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'colors.dart'; // Replace with your actual theme import

class AddressBookScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddressSelected;

  const AddressBookScreen({super.key, required this.onAddressSelected});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> addresses = [];
  bool isLoading = true;
  String? selectedAddressId;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      setState(() {
        addresses = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print("Error loading addresses: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load addresses'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _setDefaultAddress(String addressId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // First, unset all addresses as default
      await supabase
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', userId);

      // Then set the selected address as default
      await supabase
          .from('user_addresses')
          .update({'is_default': true})
          .eq('id', addressId)
          .eq('user_id', userId);

      _loadAddresses();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default address updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error setting default address: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating address: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAddress(String addressId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('user_addresses')
          .delete()
          .eq('id', addressId)
          .eq('user_id', userId);

      _loadAddresses();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Address deleted'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print("Error deleting address: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting address: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddressOptions(Map<String, dynamic> address) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              if (!address['is_default'])
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Set as default'),
                  onTap: () {
                    Navigator.pop(context);
                    _setDefaultAddress(address['id']);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit address'),
                onTap: () {
                  Navigator.pop(context);
                  _openAddAddressScreen(address);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete address', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(address);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> address) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Address'),
          content: const Text('Are you sure you want to delete this address?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteAddress(address['id']);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _openAddAddressScreen([Map<String, dynamic>? existingAddress]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(
          existingAddress: existingAddress,
          onAddressSaved: () {
            _loadAddresses();
          },
        ),
      ),
    );
  }

  void _selectAddress(Map<String, dynamic> address) {
    setState(() {
      selectedAddressId = address['id'];
    });
  }

  void _confirmSelection() {
    if (selectedAddressId != null) {
      final selectedAddress = addresses.firstWhere(
            (address) => address['id'] == selectedAddressId,
      );
      widget.onAddressSelected(selectedAddress);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue,
        automaticallyImplyLeading: true,
        title: const Text(
          "Address Book",
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _openAddAddressScreen(),
            icon: const Icon(
              Icons.add,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : addresses.isEmpty
          ? _buildEmptyState()
          : Column(
        children: [
          Expanded(child: _buildAddressList()),
          if (selectedAddressId != null) _buildSelectionFooter(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No addresses found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first address to get started',
              style: TextStyle(
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openAddAddressScreen(),
              icon: const Icon(Icons.add),
              label: const Text('Add Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: addresses.length,
      itemBuilder: (context, index) {
        final address = addresses[index];
        return _buildAddressCard(address);
      },
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> address) {
    final isSelected = selectedAddressId == address['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blue
              : address['is_default']
              ? kPrimaryColor
              : Colors.grey.shade200,
          width: isSelected ? 2 : address['is_default'] ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectAddress(address),
          onLongPress: () => _showAddressOptions(address),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getAddressTypeColor(address['address_type']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getAddressTypeIcon(address['address_type']),
                        color: _getAddressTypeColor(address['address_type']),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  address['address_type'] ?? 'Address',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (address['is_default']) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'DEFAULT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (address['latitude'] != null && address['longitude'] != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 10,
                                        color: Colors.green.shade700,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'MAP',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (address['recipient_name'] != null)
                            Text(
                              address['recipient_name'],
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showAddressOptions(address),
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  address['address_line_1'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (address['address_line_2'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    address['address_line_2'],
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${address['city']}, ${address['state']} - ${address['pincode']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (address['phone_number'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.phone,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address['phone_number'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isSelected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.blue, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Selected',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _confirmSelection,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Use This Address',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getAddressTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'office':
      case 'work':
        return Icons.business;
      case 'other':
        return Icons.location_on;
      default:
        return Icons.location_on;
    }
  }

  Color _getAddressTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'home':
        return Colors.blue;
      case 'office':
      case 'work':
        return Colors.orange;
      case 'other':
        return Colors.purple;
      default:
        return kPrimaryColor;
    }
  }
}

class AddAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? existingAddress;
  final VoidCallback onAddressSaved;
  final LatLng? preselectedLocation;
  final String? preselectedAddress;

  const AddAddressScreen({
    super.key,
    this.existingAddress,
    required this.onAddressSaved,
    this.preselectedLocation,
    this.preselectedAddress,
  });

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _recipientNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _landmarkController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _searchController = TextEditingController();

  String selectedAddressType = 'Home';
  bool isDefault = false;
  bool isLoading = false;
  bool isServiceAvailable = true;
  bool isCheckingService = false;
  bool isDetectingLocation = false;

  // Location variables
  Position? currentPosition;
  double? latitude;
  double? longitude;
  bool _showMap = false;
  bool _hasSelectedLocation = false;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  bool _isLoadingAddress = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingAddress != null) {
      _showMap = false;
      _populateFields();
    } else {
      _showMap = true;
      _getCurrentLocationOnInit();
    }

    if (widget.preselectedLocation != null) {
      _populateFromMapSelection();
    }
  }

  Future<void> _getCurrentLocationOnInit() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        currentPosition = position;
        latitude = position.latitude;
        longitude = position.longitude;
      });

      _addMarker(LatLng(position.latitude, position.longitude));
    } catch (e) {
      print('Auto location detection failed: $e');
    }
  }

  void _populateFields() {
    final address = widget.existingAddress!;
    _recipientNameController.text = address['recipient_name'] ?? '';
    _phoneController.text = address['phone_number'] ?? '';
    _addressLine1Controller.text = address['address_line_1'] ?? '';
    _addressLine2Controller.text = address['address_line_2'] ?? '';
    _landmarkController.text = address['landmark'] ?? '';
    _pincodeController.text = address['pincode'] ?? '';
    _cityController.text = address['city'] ?? '';
    _stateController.text = address['state'] ?? '';
    selectedAddressType = address['address_type'] ?? 'Home';
    isDefault = address['is_default'] ?? false;
    latitude = address['latitude']?.toDouble();
    longitude = address['longitude']?.toDouble();

    if (latitude != null && longitude != null) {
      _addMarker(LatLng(latitude!, longitude!));
      _hasSelectedLocation = true;
    }
  }

  void _populateFromMapSelection() {
    if (widget.preselectedLocation != null) {
      latitude = widget.preselectedLocation!.latitude;
      longitude = widget.preselectedLocation!.longitude;
      _addMarker(widget.preselectedLocation!);
      _hasSelectedLocation = true;

      if (widget.preselectedAddress != null) {
        _parseAddressString(widget.preselectedAddress!);
      }
    }
  }

  void _parseAddressString(String addressString) {
    List<String> parts = addressString.split(', ');
    if (parts.isNotEmpty) {
      _addressLine1Controller.text = parts[0];
      if (parts.length > 1) {
        _addressLine2Controller.text = parts[1];
      }
      if (parts.length > 2) {
        _cityController.text = parts[2];
      }

      if (parts.isNotEmpty) {
        String lastPart = parts.last;
        RegExp pincodeRegex = RegExp(r'\b\d{6}\b');
        Match? match = pincodeRegex.firstMatch(lastPart);
        if (match != null) {
          _pincodeController.text = match.group(0)!;
          String stateText = lastPart.replaceAll(match.group(0)!, '').trim();
          stateText = stateText.replaceAll('-', '').trim();
          _stateController.text = stateText;
        }
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        LatLng newPosition = LatLng(location.latitude, location.longitude);

        _addMarker(newPosition);

        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(newPosition, 15),
          );
        }

        setState(() {
          _searchController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location found successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not find location: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _checkServiceAvailability(String pincode) async {
    if (pincode.length != 6) return;

    setState(() {
      isCheckingService = true;
    });

    try {
      final response = await supabase
          .from('service_areas')
          .select()
          .eq('pincode', pincode)
          .eq('is_active', true)
          .maybeSingle();

      setState(() {
        isServiceAvailable = response != null;
        isCheckingService = false;
      });
    } catch (e) {
      print("Error checking service availability: $e");
      setState(() {
        isServiceAvailable = false;
        isCheckingService = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isDetectingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable them in settings.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        setState(() {
          currentPosition = position;
          latitude = position.latitude;
          longitude = position.longitude;

          _addressLine1Controller.text =
              '${place.street ?? ''} ${place.name ?? ''}'.trim();
          _addressLine2Controller.text =
              '${place.subLocality ?? ''} ${place.locality ?? ''}'.trim();
          _landmarkController.text = place.subThoroughfare ?? '';
          _cityController.text = place.locality ?? '';
          _stateController.text = place.administrativeArea ?? '';
          _pincodeController.text = place.postalCode ?? '';

          isDetectingLocation = false;
          _hasSelectedLocation = true;
        });

        _addMarker(LatLng(position.latitude, position.longitude));

        if (place.postalCode != null && place.postalCode!.length == 6) {
          _checkServiceAvailability(place.postalCode!);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location detected successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isDetectingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error detecting location: ${e.toString()}'),
          backgroundColor: Colors.red,
          action: e.toString().contains('disabled')
              ? SnackBarAction(
            label: 'Settings',
            onPressed: () => Geolocator.openLocationSettings(),
          )
              : null,
        ),
      );
    }
  }

  void _proceedToForm() {
    if (!_hasSelectedLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _showMap = false;
    });
  }

  void _goBackToMap() {
    setState(() {
      _showMap = true;
    });
  }

  void _addMarker(LatLng position) {
    setState(() {
      latitude = position.latitude;
      longitude = position.longitude;
      _hasSelectedLocation = true;
      _markers.clear();
      _markers.add(Marker(
        markerId: const MarkerId('selectedLocation'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        draggable: true,
        onDragEnd: (newPosition) {
          _addMarker(newPosition);
          _getAddressFromCoordinates(newPosition);
        },
      ));
    });

    _getAddressFromCoordinates(position);
  }

  Future<void> _getAddressFromCoordinates(LatLng position) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _addressLine1Controller.text =
              '${place.street ?? ''} ${place.name ?? ''}'.trim();
          _addressLine2Controller.text =
              '${place.subLocality ?? ''} ${place.locality ?? ''}'.trim();
          _landmarkController.text = place.subThoroughfare ?? '';
          _cityController.text = place.locality ?? '';
          _stateController.text = place.administrativeArea ?? '';
          _pincodeController.text = place.postalCode ?? '';
        });

        if (place.postalCode != null && place.postalCode!.length == 6) {
          _checkServiceAvailability(place.postalCode!);
        }
      }
    } catch (e) {
      print('Error getting address: $e');
    } finally {
      setState(() {
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    if (!isServiceAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service not available in this pincode'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final addressData = {
        'user_id': userId,
        'recipient_name': _recipientNameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'address_line_1': _addressLine1Controller.text.trim(),
        'address_line_2': _addressLine2Controller.text.trim().isEmpty
            ? null : _addressLine2Controller.text.trim(),
        'landmark': _landmarkController.text.trim().isEmpty
            ? null : _landmarkController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'address_type': selectedAddressType,
        'is_default': isDefault,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.existingAddress != null) {
        await supabase
            .from('user_addresses')
            .update(addressData)
            .eq('id', widget.existingAddress!['id'])
            .eq('user_id', userId);
      } else {
        addressData['created_at'] = DateTime.now().toIso8601String();
        await supabase.from('user_addresses').insert(addressData);
      }

      if (isDefault) {
        await supabase
            .from('user_addresses')
            .update({'is_default': false})
            .eq('user_id', userId)
            .neq('id', widget.existingAddress?['id'] ?? '');
      }

      widget.onAddressSaved();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existingAddress != null
              ? 'Address updated successfully'
              : 'Address added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error saving address: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving address: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue,
        automaticallyImplyLeading: true,
        title: Text(
          _showMap
              ? "Select Location"
              : (widget.existingAddress != null ? "Edit Address" : "Add Address"),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
        actions: _showMap ? [
          IconButton(
            onPressed: isDetectingLocation ? null : _getCurrentLocation,
            icon: isDetectingLocation
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.my_location, color: Colors.white),
            tooltip: 'Detect current location',
          ),
        ] : [
          IconButton(
            onPressed: _goBackToMap,
            icon: const Icon(Icons.map, color: Colors.white),
            tooltip: 'Select on map',
          ),
        ],
      ),
      body: _showMap ? _buildMapView() : _buildFormView(),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        GoogleMap(
          onMapCreated: (controller) {
            _mapController = controller;
          },
          initialCameraPosition: CameraPosition(
            target: latitude != null && longitude != null
                ? LatLng(latitude!, longitude!)
                : const LatLng(28.6139, 77.2090),
            zoom: 15,
          ),
          markers: _markers,
          onTap: _addMarker,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
        ),

        // Search bar
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for a location...',
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                suffixIcon: _isSearching
                    ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  ),
                )
                    : _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: _searchLocation,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),

        // Location status card
        if (_markers.isNotEmpty)
          Positioned(
            top: 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Location Selected',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  if (_isLoadingAddress)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Getting address...',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  else if (_addressLine1Controller.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${_addressLine1Controller.text}, ${_cityController.text}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),

        // Continue button
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: ElevatedButton(
              onPressed: _hasSelectedLocation && !_isLoadingAddress
                  ? _proceedToForm
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 8,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue with this location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    return Form(
        key: _formKey,
        child: Column(
            children: [
        Expanded(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        if (latitude != null && longitude != null)
        Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.green.shade50,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.green.shade200),
    ),
    child: InkWell(
    onTap: _goBackToMap,
    child: Row(
    children: [
    Icon(Icons.location_on, color: Colors.green.shade600, size: 20),
    const SizedBox(width: 8),
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Text(
    'Location selected from map',
    style: TextStyle(
    color: Colors.green.shade700,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    ),
    ),
    Text(
    'Tap to change location',
    style: TextStyle(
    color: Colors.green.shade600,
    fontSize: 11,
    ),
    ),
    ],
    ),
    ),
    Icon(
    Icons.edit,
    color: Colors.green.shade600,
    size: 16,
    ),
    ],
    ),
    ),
    ),

    _buildSectionTitle('Contact Information'),
    _buildTextField(
    controller: _recipientNameController,
    label: 'Full Name',
    hint: 'Enter recipient name',
    icon: Icons.person_outline,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'Name is required';
    }
    return null;
    },
    ),
    const SizedBox(height: 16),
    _buildTextField(
    controller: _phoneController,
    label: 'Phone Number',
    hint: 'Enter 10-digit phone number',
    icon: Icons.phone_outlined,
    keyboardType: TextInputType.phone,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'Phone number is required';
    }
    if (value!.length != 10) {
    return 'Enter valid 10-digit phone number';
    }
    return null;
    },
    ),
    const SizedBox(height: 24),

    _buildSectionTitle('Address Details'),
    _buildTextField(
    controller: _addressLine1Controller,
    label: 'Address Line 1',
    hint: 'House/Flat/Office No, Building Name',
    icon: Icons.home_outlined,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'Address is required';
    }
    return null;
    },
    ),
    const SizedBox(height: 16),
    _buildTextField(
    controller: _addressLine2Controller,
    label: 'Address Line 2 (Optional)',
    hint: 'Area, Street, Sector, Village',
    icon: Icons.location_on_outlined,
    ),
    const SizedBox(height: 16),
    _buildTextField(
    controller: _landmarkController,
    label: 'Landmark (Optional)',
    hint: 'Nearby landmark',
    icon: Icons.place_outlined,
    ),
    const SizedBox(height: 16),

    Row(
    children: [
    Expanded(
    flex: 2,
    child: _buildTextField(
    controller: _pincodeController,
    label: 'Pincode',
    hint: '000000',
    icon: Icons.pin_drop_outlined,
    keyboardType: TextInputType.number,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'Pincode is required';
    }
    if (value!.length != 6) {
    return 'Enter valid 6-digit pincode';
    }
    return null;
    },
    onChanged: (value) {
    if (value.length == 6) {
    _checkServiceAvailability(value);
    } else {
    setState(() {
    isServiceAvailable = true;
    isCheckingService = false;
    });
    }
    },
    ),
    ),
    const SizedBox(width: 16),
    Expanded(
    flex: 3,
    child: _buildTextField(
    controller: _cityController,
    label: 'City',
    hint: 'Enter city',
    icon: Icons.location_city_outlined,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'City is required';
    }
    return null;
    },
    ),
    ),
    ],
    ),
    const SizedBox(height: 16),
    _buildTextField(
    controller: _stateController,
    label: 'State',
    hint: 'Enter state',
    icon: Icons.map_outlined,
    validator: (value) {
    if (value?.trim().isEmpty ?? true) {
    return 'State is required';
    }
    return null;
    },
    ),


              if (_pincodeController.text.length == 6) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCheckingService
                        ? Colors.orange.shade50
                        : isServiceAvailable
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCheckingService
                          ? Colors.orange.shade200
                          : isServiceAvailable
                          ? Colors.green.shade200
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isCheckingService)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          isServiceAvailable ? Icons.check_circle : Icons.cancel,
                          color: isServiceAvailable ? Colors.green : Colors.red,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCheckingService
                              ? 'Checking service availability...'
                              : isServiceAvailable
                              ? 'Service available in this area'
                              : 'Service not available in this pincode',
                          style: TextStyle(
                            color: isCheckingService
                                ? Colors.orange.shade700
                                : isServiceAvailable
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              _buildSectionTitle('Address Type'),
              _buildAddressTypeSelector(),
              const SizedBox(height: 16),

              CheckboxListTile(
                value: isDefault,
                onChanged: (value) {
                  setState(() {
                    isDefault = value ?? false;
                  });
                },
                title: const Text('Set as default address'),
                subtitle: const Text('Use this address for future orders'),
                activeColor: kPrimaryColor,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 32),
            ],
        ),
        ),
        ),
              Container(
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  color: Colors.white,
                ),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _saveAddress,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 8,
                        shadowColor: kPrimaryColor.withOpacity(0.3),
                      ),
                      child: isLoading
                          ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                          : Text(
                        widget.existingAddress != null ? 'Update Address' : 'Save Address',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
        ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kPrimaryColor),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildAddressTypeSelector() {
    final types = ['Home', 'Office', 'Other'];

    return Row(
      children: types.map((type) {
        bool isSelected = selectedAddressType == type;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                selectedAddressType = type;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? kPrimaryColor : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? kPrimaryColor : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type == 'Home'
                        ? Icons.home
                        : type == 'Office'
                        ? Icons.business
                        : Icons.location_on,
                    color: isSelected ? Colors.white : Colors.grey.shade600,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    type,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _recipientNameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}