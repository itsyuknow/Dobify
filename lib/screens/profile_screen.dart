import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

import 'colors.dart';
import 'personal_info_screen.dart';
import 'login_screen.dart'; // For navigating to login after logout
import '../widgets/custom_bottom_nav.dart'; // ✅ Added for bottom navigation

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final path = 'avatars/${user.id}.jpg';
    final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

    setState(() {
      _imageUrl = publicUrl;
    });
  }

  Future<void> _pickAndUploadImage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final fileExt = p.extension(file.path);
    final fileName = '${user.id}$fileExt';
    final filePath = 'avatars/$fileName';

    try {
      await supabase.storage.from('avatars').upload(
        filePath,
        file,
        fileOptions: const FileOptions(upsert: true),
      );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);
      setState(() => _imageUrl = publicUrl);
    } catch (e) {
      print('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Account"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _imageUrl != null ? NetworkImage(_imageUrl!) : null,
                  child: _imageUrl == null
                      ? const Icon(Icons.person, size: 40, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 2,
                  child: GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: kPrimaryColor,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.add, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              user.email ?? "No email",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildOption(
              context,
              Icons.person,
              'Personal Information',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                );
              },
            ),
            _buildOption(context, Icons.history, 'Order History'),
            _buildOption(context, Icons.privacy_tip_outlined, 'Privacy Policy'),
            _buildOption(context, Icons.description_outlined, 'Terms & Conditions'),
            _buildOption(context, Icons.support_agent, 'Support'),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () async {
                  await supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                    );
                  }
                },
                child: const Text(
                  'Log out',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomNav(currentIndex: 2), // ✅ Bottom Nav added here
    );
  }

  Widget _buildOption(BuildContext context, IconData icon, String label, {VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.5,
      child: ListTile(
        leading: Icon(icon, color: kPrimaryColor),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
