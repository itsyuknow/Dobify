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
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;

    // Calculate responsive values
    final isSmallScreen = screenHeight < 700;
    final navBarHeight = isSmallScreen ? 60.0 : 70.0;
    final iconSize = isSmallScreen ? 22.0 : 24.0;
    final fontSize = isSmallScreen ? 10.0 : 12.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 14.0;
    final verticalPadding = isSmallScreen ? 4.0 : 6.0;

    return Container(
      // Use padding instead of fixed height to handle safe area properly
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.zero,
        child: Container(
          height: navBarHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, -2),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  context,
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                ),
                _buildNavItem(
                  context,
                  index: 1,
                  icon: MdiIcons.ironOutline,
                  activeIcon: MdiIcons.iron,
                  label: 'Services',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                ),
                _buildNavItem(
                  context,
                  index: 2,
                  icon: Icons.person_outlined,
                  activeIcon: Icons.person,
                  label: 'Profile',
                  iconSize: iconSize,
                  fontSize: fontSize,
                  horizontalPadding: horizontalPadding,
                  verticalPadding: verticalPadding,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, {
        required int index,
        required IconData icon,
        required IconData activeIcon,
        required String label,
        required double iconSize,
        required double fontSize,
        required double horizontalPadding,
        required double verticalPadding,
      }) {
    final isSelected = index == currentIndex;

    return Expanded(
      child: GestureDetector(
        onTap: () => _navigateTo(context, index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey(isSelected),
                  size: iconSize,
                  color: isSelected ? kPrimaryColor : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: isSelected ? kPrimaryColor : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}