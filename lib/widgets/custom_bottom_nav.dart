import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../screens/home_screen.dart';
import '../screens/order_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/colors.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  const CustomBottomNav({super.key, required this.currentIndex});

  void _navigateTo(BuildContext context, int index) {
    if (index == currentIndex) return;
    Widget dest;
    switch (index) {
      case 0:
        dest = const HomeScreen();
        break;
      case 1:
        dest = const OrdersScreen(category: 'All');
        break;
      case 2:
        dest = const ProfileScreen();
        break;
      default:
        return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => dest),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context,
            index: 0,
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Home',
          ),
          _buildNavItem(
            context,
            index: 1,
            icon: MdiIcons.ironOutline,
            activeIcon: MdiIcons.iron,
            label: 'Services',
          ),
          _buildNavItem(
            context,
            index: 2,
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, {
        required int index,
        required IconData icon,
        required IconData activeIcon,
        required String label,
      }) {
    final isSelected = index == currentIndex;

    return GestureDetector(
      onTap: () => _navigateTo(context, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? activeIcon : icon,
                size: 24, color: isSelected ? kPrimaryColor : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? kPrimaryColor : Colors.grey,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
