// lib/widgets/mobile_wrapper.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MobileWrapper extends StatelessWidget {
  final Widget child;
  // Samsung Galaxy S21 Ultra dimensions (larger for better web viewing)
  // Increased size for better visibility and usability
  static const double mobileWidth = 450.0;  // Increased horizontal width
  static const double mobileHeight = 950.0; // Increased vertical height (20:9 aspect ratio maintained)

  const MobileWrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Debug print to see if wrapper is being called
    print('🔥 MobileWrapper build called - kIsWeb: $kIsWeb');

    if (!kIsWeb) {
      // On mobile platforms, just return the child
      print('📱 Running on mobile - returning child directly');
      return child;
    }

    // On web, ALWAYS force mobile container view for ENTIRE APP
    print('🌐 Running on web - applying Samsung S21 Ultra style mobile container');

    return Material(
      color: Colors.black, // ⬅️ solid black background
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.black, // ⬅️ remove gradient, keep pure black
        ),
        child: Center(
          child: Container(
            width: mobileWidth,
            height: mobileHeight,
            decoration: BoxDecoration(
              color: Colors.black, // Phone frame color
              borderRadius: BorderRadius.zero, // ⬅️ make edges straight (no rounding)
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: const Color(0xFF0f3460).withOpacity(0.3),
                  blurRadius: 50,
                  spreadRadius: 10,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4), // Phone frame thickness
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.zero, // ⬅️ inner screen straight
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.zero, // ⬅️ no rounded clip
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: const Size(mobileWidth - 8, mobileHeight - 8), // Account for frame
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
