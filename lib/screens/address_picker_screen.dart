import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

class AddressPickerScreen extends StatefulWidget {
  final LatLng? initial;
  AddressPickerScreen({this.initial, super.key});
  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  late LatLng loc = widget.initial ?? LatLng(28.6, 77.2);
  String addressLabel = 'Tap map to select';
  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial==null?'Add Address':'Edit Address')),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: loc, zoom: 14),
          onTap: (ll) async {
            List<Placemark> p = await placemarkFromCoordinates(ll.latitude, ll.longitude);
            setState(() {
              loc = ll;
              addressLabel = p.isNotEmpty ?
              '${p.first.street}, ${p.first.locality}, ${p.first.postalCode}, ${p.first.country}' : 'Unknown location';
            });
          },
          markers: {Marker(markerId: MarkerId('pick'), position: loc)},
        ),
        Positioned(
          bottom: 20, left: 20, right: 20,
          child: ElevatedButton(
              onPressed: () {
                if(addressLabel.startsWith('Unknown')) return;
                Navigator.pop(ctx, {'lat': loc.latitude, 'lng': loc.longitude, 'address':addressLabel});
              },
              child: const Text('Use This Location')),
        )
      ]),
    );
  }
}
