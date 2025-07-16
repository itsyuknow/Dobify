import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';

class AddEditAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? address;

  const AddEditAddressScreen({
    super.key,
    this.address,
  });

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;
  final _addressTypeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  bool _isDefault = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.address != null) {
      _addressTypeController.text = widget.address!['type'] ?? 'home';
      _nameController.text = widget.address!['name'] ?? '';
      _phoneController.text = widget.address!['phone'] ?? '';
      _addressLine1Controller.text = widget.address!['address_line1'] ?? '';
      _addressLine2Controller.text = widget.address!['address_line2'] ?? '';
      _landmarkController.text = widget.address!['landmark'] ?? '';
      _cityController.text = widget.address!['city'] ?? '';
      _stateController.text = widget.address!['state'] ?? '';
      _postalCodeController.text = widget.address!['postal_code'] ?? '';
      _isDefault = widget.address!['is_default'] ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.address == null ? 'Add New Address' : 'Edit Address'),
        actions: [
          if (widget.address != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveAddress,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _addressTypeController.text.isEmpty
                    ? 'home'
                    : _addressTypeController.text,
                decoration: const InputDecoration(
                  labelText: 'Address Type',
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'home',
                    child: Text('Home'),
                  ),
                  DropdownMenuItem(
                    value: 'work',
                    child: Text('Work'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _addressTypeController.text = value ?? 'home';
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select address type';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter phone number';
                  }
                  if (value.length < 10) {
                    return 'Enter valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressLine1Controller,
                decoration: const InputDecoration(
                  labelText: 'Address Line 1',
                  prefixIcon: Icon(Icons.home),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressLine2Controller,
                decoration: const InputDecoration(
                  labelText: 'Address Line 2 (Optional)',
                  prefixIcon: Icon(Icons.home_work),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _landmarkController,
                decoration: const InputDecoration(
                  labelText: 'Landmark (Optional)',
                  prefixIcon: Icon(Icons.place),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter city';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stateController,
                decoration: const InputDecoration(
                  labelText: 'State',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter state';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _postalCodeController,
                decoration: const InputDecoration(
                  labelText: 'Postal Code',
                  prefixIcon: Icon(Icons.markunread_mailbox),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter postal code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Set as default address'),
                value: _isDefault,
                onChanged: (value) {
                  setState(() {
                    _isDefault = value;
                  });
                },
                secondary: const Icon(Icons.star_border),
              ),
              const SizedBox(height: 24),
              if (widget.address == null)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'SAVE ADDRESS',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
          return;
        }

        final addressData = {
          'type': _addressTypeController.text,
          'name': _nameController.text,
          'phone': _phoneController.text,
          'address_line1': _addressLine1Controller.text,
          'address_line2': _addressLine2Controller.text,
          'landmark': _landmarkController.text,
          'city': _cityController.text,
          'state': _stateController.text,
          'postal_code': _postalCodeController.text,
          'is_default': _isDefault,
          'user_id': userId,
        };

        if (_isDefault) {
          // First remove default from all other addresses
          await supabase
              .from('user_addresses')
              .update({'is_default': false})
              .eq('user_id', userId);
        }

        if (widget.address == null) {
          // Add new address
          await supabase.from('user_addresses').insert(addressData);
        } else {
          // Update existing address
          await supabase
              .from('user_addresses')
              .update(addressData)
              .eq('id', widget.address!['id']);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.address == null
                ? 'Address added successfully'
                : 'Address updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _addressTypeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }
}