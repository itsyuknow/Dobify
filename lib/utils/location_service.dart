import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static Future<String?> getAddressFromLatLng(Position position) async {
    List<Placemark> placemarks = await placemarkFromCoordinates(
      position.latitude, position.longitude,
    );

    if (placemarks.isEmpty) return null;

    final place = placemarks.first;
    return "${place.name}, ${place.locality}, ${place.administrativeArea}, ${place.postalCode}, ${place.country}";
  }
}
