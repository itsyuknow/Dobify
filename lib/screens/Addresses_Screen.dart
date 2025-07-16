import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'address_picker_screen.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> addresses = [];

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('user_addresses')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    if (response is List) {
      setState(() {
        addresses = List<Map<String, dynamic>>.from(response);
      });
    } else {
      debugPrint('Error loading addresses');
    }
  }

  Future<void> _deleteAddress(String id) async {
    await supabase.from('user_addresses').delete().eq('id', id);
    await _loadAddresses();
  }

  Future<void> _editOrAddAddress({Map<String, dynamic>? existing}) async {
    final LatLng? initialLatLng = existing != null
        ? LatLng(existing['lat'] as double, existing['lng'] as double)
        : null;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressPickerScreen(initial: initialLatLng),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = {
        'user_id': user.id,
        'title': 'Home',
        'street': result['address'],
        'locality': '',
        'city': '',
        'state': '',
        'zip_code': '',
        'country': '',
        'lat': result['lat'],
        'lng': result['lng'],
      };

      if (existing == null) {
        await supabase.from('user_addresses').insert(data);
      } else {
        await supabase
            .from('user_addresses')
            .update(data)
            .eq('id', existing['id']);
      }

      await _loadAddresses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Addresses')),
      body: addresses.isEmpty
          ? const Center(child: Text('No addresses found.'))
          : ListView.builder(
        itemCount: addresses.length,
        itemBuilder: (context, index) {
          final address = addresses[index];
          return Card(
            margin:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(address['street'] ?? ''),
              subtitle: Text(
                  'Lat: ${address['lat']}, Lng: ${address['lng']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () =>
                        _editOrAddAddress(existing: address),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteAddress(address['id']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editOrAddAddress(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
