import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart'; // Your kPrimaryColor

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _gender = 'Male';
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    if (response != null) {
      setState(() {
        _nameController.text = response['full_name'] ?? '';
        _phoneController.text = response['phone'] ?? '';
        _gender = response['gender'] ?? 'Male';
        if (response['dob'] != null) {
          _dob = DateTime.tryParse(response['dob']);
        }
      });
    }
  }

  Future<void> _saveUserInfo() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('profiles').upsert({
      'id': user.id,
      'full_name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'gender': _gender,
      'dob': _dob?.toIso8601String(),
    });

    if (mounted) {
      Navigator.pop(context); // Close screen immediately
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Personal Information")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) =>
                value!.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: user?.email ?? '',
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: ['Male', 'Female', 'Other']
                    .map((gender) => DropdownMenuItem(
                  value: gender,
                  child: Text(gender),
                ))
                    .toList(),
                onChanged: (value) => setState(() => _gender = value!),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _dob == null
                      ? 'Select Date of Birth'
                      : 'DOB: ${_dob!.toLocal().toString().split(' ')[0]}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(2000),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    setState(() {
                      _dob = pickedDate;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveUserInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
