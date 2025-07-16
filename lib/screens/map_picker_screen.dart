import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _pickedLocation;
  String _address = 'Fetching address...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserLocation();
  }

  Future<void> _fetchUserLocation() async {
    final hasPermission = await _handlePermission();
    if (!hasPermission) return;

    final position = await Geolocator.getCurrentPosition();
    final latLng = LatLng(position.latitude, position.longitude);

    setState(() {
      _pickedLocation = latLng;
      _isLoading = false;
    });

    _getAddressFromLatLng(latLng);

    // Optional: move camera after controller is ready
    _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
  }

  Future<bool> _handlePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return false;
    }

    return true;
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    try {
      List<Placemark> placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _address =
          '${place.name}, ${place.locality}, ${place.postalCode}, ${place.administrativeArea}';
        });
      }
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
    }
  }

  void _onMapTap(LatLng tappedPoint) {
    setState(() {
      _pickedLocation = tappedPoint;
    });
    _getAddressFromLatLng(tappedPoint);
  }

  void _confirmSelection() {
    if (_pickedLocation == null) return;
    Navigator.pop(context, {
      'lat': _pickedLocation!.latitude,
      'lng': _pickedLocation!.longitude,
      'address': _address,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pick Delivery Location")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pickedLocation!,
              zoom: 16,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _onMapTap,
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _pickedLocation!,
              ),
            },
          ),
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _address,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Confirm Location'),
            ),
          ),
        ],
      ),
    );
  }
}