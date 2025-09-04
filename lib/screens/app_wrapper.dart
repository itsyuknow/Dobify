
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'colors.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;

// Same key you loaded in web/index.html
const String _gmapsKey = 'AIzaSyDjxtVK1EXQuaYOc0-a0V5-Wb8xR-koHZ0';


class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with TickerProviderStateMixin {
  // Supabase initialization
  SupabaseClient? supabase;
  bool isSupabaseReady = false;

  // App state
  bool _isCheckingSession = true;
  bool _isLocationStep = false;
  bool _isLocationLoading = false;
  bool _isServiceAvailable = false;
  bool _hasLocationChecked = false;
  bool _showMap = false;
  bool _locationVerifiedSuccessfully = false;

  String _currentLocation = 'Finding your location...';
  String _selectedAddress = '';
  Position? _currentPosition;
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  final TextEditingController _searchController = TextEditingController();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late AnimationController _scaleController;
  late AnimationController _slideController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  // Auth subscription
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeSupabase();
  }

  Future<String?> _reverseAddress(double lat, double lng) async {
    if (kIsWeb) {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_gmapsKey',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty) return null;
      return results.first['formatted_address'] as String?;
    } else {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      return [
        if ((p.street ?? '').isNotEmpty) p.street,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality,
        if ((p.locality ?? '').isNotEmpty) p.locality,
        if ((p.postalCode ?? '').isNotEmpty) p.postalCode,
      ].where((e) => e != null && e!.isNotEmpty).join(', ');
    }
  }

  Future<String?> _pinFromLatLng(double lat, double lng) async {
    if (kIsWeb) {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_gmapsKey',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty) return null;
      for (final comp in results.first['address_components'] as List<dynamic>) {
        final types = List<String>.from(comp['types'] as List);
        if (types.contains('postal_code')) {
          return (comp['long_name'] as String?)?.replaceAll(RegExp(r'[^0-9]'), '');
        }
      }
      return null;
    } else {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      return placemarks.first.postalCode?.replaceAll(RegExp(r'[^0-9]'), '');
    }
  }


  /// Move camera so the center pin's TIP aligns with [target].
  /// [tipOffsetPx] ≈ distance in screen pixels from pin center to its tip.
  /// Tune if your pin asset height changes (70px pin → ~34–40px tip offset).
  Future<void> _animateToWithPinTip(LatLng target,
      {double zoom = 16.0, double tipOffsetPx = 36}) async {
    if (_mapController == null) return;

    // Let the map render a tick so projection is valid.
    await Future.delayed(const Duration(milliseconds: 16));

    // Convert the real target to screen coords, then shift UP by the tip offset.
    final screenPoint = await _mapController!.getScreenCoordinate(target);
    final shifted = ScreenCoordinate(
      x: screenPoint.x,
      y: (screenPoint.y - tipOffsetPx).round(),
    );

    // Convert back to LatLng and animate.
    final adjustedLatLng = await _mapController!.getLatLng(shifted);
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: adjustedLatLng, zoom: zoom),
      ),
    );
  }

  Future<void> _snapPinTipToCurrentLocation({
    double? zoom,                 // when null, we preserve current zoom
    double tipOffsetPx = 52,      // ← keep your offset
  }) async {
    if (!mounted || _mapController == null || _currentPosition == null) return;

    // Real current position (blue dot)
    final LatLng target = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    // Keep selection in sync with the real location
    setState(() {
      _selectedLocation = target;
    });

    try {
      // Give the map a moment so projection is valid
      await Future.delayed(const Duration(milliseconds: 100));

      if (_mapController == null || !mounted) return;

      // ✅ Preserve current zoom if none provided
      final double currentZoom = await _mapController!.getZoomLevel();
      final double useZoom = zoom ?? currentZoom;

      // Real target -> screen coords
      final screenPoint = await _mapController!.getScreenCoordinate(target);

      // Shift UP by the pin-tip offset (in device px)
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final shifted = ScreenCoordinate(
        x: screenPoint.x,
        y: (screenPoint.y - (tipOffsetPx * dpr)).round(),
      );

      // Back to LatLng and animate so the pin TIP hits the real target
      final adjustedLatLng = await _mapController!.getLatLng(shifted);

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: adjustedLatLng, zoom: useZoom),
        ),
      );

      // Wait for animation to complete before updating address
      await Future.delayed(const Duration(milliseconds: 300));

      // Update address/markers from the REAL location (not the adjusted camera target)
      if (mounted) {
        await _onMapTap(target);
      }
    } catch (e) {
      // Fallback: still preserve zoom level
      if (_mapController != null && mounted) {
        try {
          final double currentZoom = await _mapController!.getZoomLevel();
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: target, zoom: currentZoom),
            ),
          );
        } catch (_) {
          // If getZoomLevel() fails on some platforms, just re-center without specifying zoom
          await _mapController!.animateCamera(CameraUpdate.newLatLng(target));
        }
        await _onMapTap(target);
      }
    }
  }





  Future<void> _initializeSupabase() async {
    try {
      int attempts = 0;
      while (!isSupabaseReady && attempts < 10 && mounted) {
        try {
          supabase = Supabase.instance.client;
          isSupabaseReady = true;
          print('✅ Supabase ready in AppWrapper');

          if (mounted) {
            _setupAuthListener();
            _checkInitialSession();
          }
          break;
        } catch (e) {
          attempts++;
          print('⚠️ Supabase not ready yet, attempt $attempts: $e');
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (!isSupabaseReady) {
        print('❌ Failed to initialize Supabase in AppWrapper after 10 attempts');
        if (mounted) {
          setState(() {
            _isCheckingSession = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error initializing Supabase in AppWrapper: $e');
      if (mounted) {
        setState(() {
          _isCheckingSession = false;
        });
      }
    }
  }

  void _setupAuthListener() {
    if (supabase == null) return;

    _authSubscription = supabase!.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      print('🔔 Auth state changed: $event');

      if (event == AuthChangeEvent.signedIn && session != null) {
        print('✅ signed in, Verifying your location ');
        _handleUserLoggedIn();
      } else if (event == AuthChangeEvent.signedOut) {
        print('❌ User signed out, showing login');
        if (mounted) {
          setState(() {
            _isCheckingSession = false;
            _isLocationStep = false;
            _hasLocationChecked = false;
            _locationVerifiedSuccessfully = false;
          });
        }
      }
    });
  }

  Future<void> _checkInitialSession() async {
    if (supabase == null) {
      if (mounted) {
        setState(() {
          _isCheckingSession = false;
        });
      }
      return;
    }

    print('🔍 Checking initial session...');
    try {
      final session = supabase!.auth.currentSession;
      print('Current session: ${session != null ? "exists" : "null"}');

      if (session != null) {
        print('🔑 Initial session found,  starting location verification');
        _handleUserLoggedIn();
      } else {
        print('🔑 No initial session found, showing login');
        if (mounted) {
          setState(() {
            _isCheckingSession = false;
            _isLocationStep = false;
          });
        }
      }
    } catch (e) {
      print('Error checking initial session: $e');
      if (mounted) {
        setState(() {
          _isCheckingSession = false;
          _isLocationStep = false;
        });
      }
    }
  }

  void _handleUserLoggedIn() {
    print('🚀 Starting location verification process...');
    if (mounted) {
      setState(() {
        _isCheckingSession = false;
        _isLocationStep = true;
        _hasLocationChecked = false;
        _locationVerifiedSuccessfully = false;
        _showMap = false;
        _isLocationLoading = false;
      });

      _scaleController.forward();
      _slideController.forward();

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startLocationVerification();
        }
      });
    }
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _bounceAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.elasticOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
  }

  Future<void> _startLocationVerification() async {
    print('📍 Starting location verification for iron services...');
    await _checkLocationAndService();
  }

  Future<void> _checkLocationAndService() async {
    if (mounted) {
      setState(() {
        _isLocationLoading = true;
        _currentLocation = 'Detecting your area...';
        _hasLocationChecked = false;
        _showMap = false;
        _locationVerifiedSuccessfully = false;
      });
    }

    _pulseController.repeat(reverse: true);

    try {
      // Check if location services enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationError('Please enable location services for ironXpress pickup/delivery');
        return;
      }

      // Check & request permissions (mobile only)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _handleLocationError('Location permission needed for ironXpress');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _handleLocationError('Please enable location in settings for ironXpress');
        return;
      }

      if (mounted) {
        setState(() {
          _currentLocation = 'Getting your location...';
        });
      }

      // Get current position
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      print('📍 Got coordinates: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;

      // ✅ Get human-readable address
      String? address = await _reverseAddress(lat, lng);

      if (address != null && mounted) {
        setState(() {
          _currentLocation = address;
          _selectedLocation = LatLng(lat, lng);
          _selectedAddress = address;
          _isLocationLoading = false;
          _showMap = true;
          _markers = {
            Marker(
              markerId: const MarkerId('selected_location'),
              position: _selectedLocation!,
              icon: _createCustomMarker(),
              infoWindow: InfoWindow(title: 'Your Location', snippet: address),
            ),
          };
        });
        _pulseController.stop();
        print('✅ Location detected: $address');
      } else {
        await _handleLocationError('Unable to get address for ironXpress');
      }
    } catch (e) {
      _pulseController.stop();
      print('❌ Location error: $e');
      await _handleLocationError('Unable to get your location. Please try again.');
    }
  }


  BitmapDescriptor _createCustomMarker() {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }

  Future<void> _confirmLocationAndCheckService() async {
    if (supabase == null) {
      print('❌ Supabase not ready');
      return;
    }

    print('🔥 CONFIRM BUTTON PRESSED - Checking ironXpress availability');
    print('📍 Selected location: $_selectedLocation');
    print('📍 Selected address: $_selectedAddress');

    if (_selectedLocation == null) {
      print('❌ No location selected');
      if (mounted) {
        setState(() {
          _currentLocation = 'Please select your location on the map';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLocationLoading = true;
        _currentLocation = 'Checking ironXpress availability...';
      });
    }

    try {
      print('🔍 Checking if we provide ironXpress in this area...');

      bool serviceAvailable = false;
      try {
        serviceAvailable = await _checkIronServiceAvailability(
          _selectedLocation!.latitude,
          _selectedLocation!.longitude,
        ).timeout(const Duration(seconds: 8));
        print('🔍 IronXpress available: $serviceAvailable');
      } catch (e) {
        print('⚠️ Service check timeout: $e');
        serviceAvailable = false;
      }

      print('💾 Saving location to profile...');
      try {
        await _saveLocationToProfile().timeout(const Duration(seconds: 8));
        print('✅ Location saved successfully');
      } catch (e) {
        print('⚠️ Save location error but continuing: $e');
      }

      if (mounted) {
        setState(() {
          _isServiceAvailable = serviceAvailable;
          _isLocationLoading = false;
          _hasLocationChecked = true;
          _showMap = false;
          _locationVerifiedSuccessfully = serviceAvailable;
        });
      }

      if (serviceAvailable) {
        print('✅ IronXpress available, navigating to home');
        if (mounted) {
          setState(() {
            _currentLocation = 'Welcome to ironXpress';
          });
        }
        await Future.delayed(const Duration(milliseconds: 1500));
        _navigateToHome();
      } else {
        print('⚠️ IronXpress not available at this location');
        _bounceController.forward();
      }

    } catch (e) {
      print('❌ Critical error in ironXpress check: $e');
      if (mounted) {
        setState(() {
          _isServiceAvailable = false;
          _isLocationLoading = false;
          _hasLocationChecked = true;
          _showMap = false;
          _locationVerifiedSuccessfully = false;
        });
      }
      _bounceController.forward();
    }
  }

  Future<bool> _checkIronServiceAvailability(double latitude, double longitude) async {
    if (supabase == null) return false;

    try {
      print('🔍 Getting area details for your service...');

      // ✅ Get PIN code (web-safe)
      final String? pincode = await _pinFromLatLng(latitude, longitude);

      if (pincode == null || pincode.isEmpty) {
        print('❌ No pincode found for ironXpress area check');
        return false;
      }

      final cleanPincode = pincode.replaceAll(RegExp(r'[^0-9]'), '');
      print('🔍 Checking ironXpress for pincode: $pincode (cleaned: $cleanPincode)');

      final response = await supabase!
          .from('service_areas')
          .select()
          .or('pincode.eq.$pincode,pincode.eq.$cleanPincode')
          .eq('is_active', true)
          .maybeSingle();

      final isAvailable = response != null;
      print('🔍 IronXpress check result: $isAvailable');

      if (isAvailable) {
        print('✅ Excellent! We provide pickup/delivery service in this area');
      } else {
        print('❌ Sorry, ironXpress not available in this pincode yet');
      }

      return isAvailable;
    } catch (e) {
      print('❌ Error checking ironXpress availability: $e');
      return false;
    }
  }


  Future<void> _saveLocationToProfile() async {
    if (supabase == null) {
      print('❌ Supabase not ready for saving location');
      return;
    }

    final user = supabase!.auth.currentUser;
    if (user == null || _selectedLocation == null) return;

    try {
      // ✅ Get pincode (web-safe)
      final pincode = await _pinFromLatLng(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
      );

      print('🔄 Saving ironXpress location...');
      print('📍 Location: $_selectedAddress');
      print('📍 Coordinates: ${_selectedLocation!.latitude}, ${_selectedLocation!.longitude}');
      print('📍 Pincode: $pincode');

      await supabase!.from('profiles').upsert({
        'id': user.id,
        'location': _selectedAddress,
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'pincode': pincode,
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('✅ IronXpress location saved successfully');
    } catch (e) {
      print('❌ Error saving location: $e');
      throw e;
    }
  }


  Future<void> _onMapTap(LatLng location) async {
    // 1) Immediately reflect the tap in UI
    if (mounted) {
      setState(() {
        _selectedLocation = location;
        _markers = {
          Marker(
            markerId: const MarkerId('selected_location'),
            position: location,
            icon: _createCustomMarker(),
            infoWindow: const InfoWindow(title: 'Selected Location'),
          ),
        };
      });
    }

    // 2) Resolve a human-readable address (web-safe)
    try {
      final addr = await _reverseAddress(location.latitude, location.longitude);

      if (mounted) {
        setState(() {
          _selectedAddress = addr ?? 'Selected location';
          _markers = {
            Marker(
              markerId: const MarkerId('selected_location'),
              position: location,
              icon: _createCustomMarker(),
              infoWindow: InfoWindow(
                title: 'Selected Location',
                snippet: _selectedAddress,
              ),
            ),
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _selectedAddress = 'Selected location';
        });
      }
    }
  }


  Future<void> _handleLocationError(String errorMessage) async {
    if (mounted) {
      setState(() {
        _currentLocation = errorMessage;
        _isLocationLoading = false;
        _isServiceAvailable = false;
        _hasLocationChecked = true;
        _locationVerifiedSuccessfully = false;
        _showMap = false;
      });
    }
    _bounceController.forward();
  }

  void _navigateToHome() {
    if (!mounted) return;

    print('🏠 Navigating to Home Screen');
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    _scaleController.dispose();
    _slideController.dispose();
    _mapController?.dispose();
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ SHOW LOADING WHILE SUPABASE INITIALIZES
    if (!isSupabaseReady) {
      return Scaffold(
        body: Container(
            decoration: _buildPremiumBackgroundGradient(),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    'Setting up ironXpress...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )),
      );
    }

    // ✅ CHECKING SESSION STATE
    if (_isCheckingSession) {
      return Scaffold(
        body: Container(
            decoration: _buildPremiumBackgroundGradient(),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF42A5F5)),
                  SizedBox(height: 20),
                  Text(
                    'Checking your account...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )),
      );
    }

    // ✅ LOCATION VERIFICATION STATE (ALWAYS SHOWN AFTER LOGIN)
    if (_isLocationStep) {
      return Scaffold(
        body: Container(
          decoration: _buildPremiumBackgroundGradient(),
          child: _buildLocationScreen(),
        ),
      );
    }

    // ✅ LOGIN STATE (NO SESSION FOUND)
    return const LoginScreen();
  }

  BoxDecoration _buildPremiumBackgroundGradient() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF42A5F5), // Your exact primary color
          Color(0xFF42A5F5), // Keep same color
          Color(0xFF64B5F6), // Slightly lighter
          Color(0xFF90CAF9), // Light blue
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ),
    );
  }

  Widget _buildLocationScreen() {
    if (!_hasLocationChecked || _isLocationLoading) {
      return _showMap ? _buildPremiumMapSelectionScreen() : _buildPremiumLocationDetectionScreen();
    }

    return !_isServiceAvailable ? _buildServiceNotAvailableScreen() : _buildPremiumLocationDetectionScreen();
  }

  Widget _buildPremiumLocationDetectionScreen() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white, // <-- This sets the full-screen background to white
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.3), // Changed from blue to white
                          Colors.white.withOpacity(0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3), // Changed from blue to grey
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.iron,
                      size: 80,
                      color: Colors.blue, // Kept blue icon (adjust if needed)
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 50),
            const Text(
              'Setting up ironXpress area',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue, // Changed from ShaderMask to plain blue
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                _currentLocation,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 50),
            if (_isLocationLoading)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.2), // Changed from blue to white
                      Colors.white.withOpacity(0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2), // Changed from blue to grey
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const SizedBox(
                  height: 32,
                  width: 32,
                  child: CircularProgressIndicator(
                    color: Colors.blue, // Kept blue progress indicator
                    strokeWidth: 3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumMapSelectionScreen() {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomPadding = mediaQuery.padding.bottom; // kept if you need elsewhere
    final topPadding = mediaQuery.padding.top;

    final bottomSheetHeight = screenHeight * 0.25;
    final searchBarTop = topPadding + 10;

    // How much to lift the PIN image so its TIP sits at the visual center (in logical px).
    // For a 70px-tall pin, ~28–32 works best. Tune if you change the asset.
    const double pinTipLift = 30;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 🗺️ Google Map
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: _selectedLocation ?? const LatLng(20.2961, 85.8245),
              zoom: 15.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: EdgeInsets.only(
              top: searchBarTop + 60,
              bottom: bottomSheetHeight,
            ),
            onCameraMove: (CameraPosition position) {
              setState(() {
                // This is the MAP center (visual center), not the pin tip.
                _selectedLocation = position.target;
              });
            },
            onCameraIdle: () async {
              if (_selectedLocation == null || _mapController == null) return;

              // Convert the map center to screen coords, then shift UP by the amount
              // we visually lifted the pin so we get the TIP position.
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final centerScreen =
              await _mapController!.getScreenCoordinate(_selectedLocation!);
              final tipScreen = ScreenCoordinate(
                x: centerScreen.x,
                y: (centerScreen.y - (pinTipLift * dpr)).round(),
              );

              final tipLatLng = await _mapController!.getLatLng(tipScreen);

              // Now reverse-geocode / update markers based on the TIP’s LatLng.
              await _onMapTap(tipLatLng);
            },
          ),

          // 📍 Fixed Blue Pin Icon (center) — shifted up so TIP sits at visual center
          Center(
            child: IgnorePointer(
              ignoring: true,
              child: Transform.translate(
                offset: const Offset(0, -pinTipLift),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/blue_pin.png', width: 70, height: 70),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),

          // 🔍 Premium Search Bar
          Positioned(
            top: searchBarTop,
            left: 16,
            right: 16,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.transparent, width: 0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TypeAheadField<Location>(
                    controller: _searchController,
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(
                          color: Color(0xFF42A5F5),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'Search area, street...',
                          hintStyle: TextStyle(
                            color: const Color(0xFF42A5F5).withOpacity(0.7),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: const Color(0xFF42A5F5).withOpacity(0.8),
                            size: 20,
                          ),
                          suffixIcon: controller.text.isNotEmpty
                              ? GestureDetector(
                            onTap: () {
                              controller.clear();
                              FocusScope.of(context).unfocus();
                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.all(6),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF42A5F5).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF42A5F5),
                                size: 14,
                              ),
                            ),
                          )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          isDense: true,
                        ),
                      );
                    },
                    suggestionsCallback: (pattern) async {
                      if (pattern.length < 2) return [];
                      try {
                        final results = await locationFromAddress(pattern);
                        final sorted = results
                            .where((loc) =>
                        loc.latitude.toString().contains(pattern) ||
                            loc.longitude.toString().contains(pattern))
                            .toList();
                        return sorted.isNotEmpty ? sorted.take(3).toList() : results.take(3).toList();
                      } catch (e) {
                        return [];
                      }
                    },
                    itemBuilder: (context, Location suggestion) {
                      return FutureBuilder<List<Placemark>>(
                        future: placemarkFromCoordinates(
                          suggestion.latitude,
                          suggestion.longitude,
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return _loadingSuggestionTile();

                          final placemark = snapshot.data!.first;
                          String mainAddress = '';
                          String subAddress = '';

                          if (placemark.street?.isNotEmpty == true) {
                            mainAddress = placemark.street!;
                            if (placemark.subLocality?.isNotEmpty == true) {
                              mainAddress = '$mainAddress, ${placemark.subLocality}';
                            }
                            subAddress = '${placemark.locality ?? ''} ${placemark.postalCode ?? ''}'.trim();
                          } else if (placemark.subLocality?.isNotEmpty == true) {
                            mainAddress = placemark.subLocality!;
                            subAddress = '${placemark.locality ?? ''} ${placemark.postalCode ?? ''}'.trim();
                          } else {
                            mainAddress = placemark.locality ?? 'Unknown location';
                            subAddress = '${placemark.administrativeArea ?? ''} ${placemark.postalCode ?? ''}'.trim();
                          }

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: Color(0xFF42A5F5), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        mainAddress,
                                        style: const TextStyle(
                                          color: Color(0xFF42A5F5),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (subAddress.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            subAddress,
                                            style: TextStyle(
                                              color: const Color(0xFF42A5F5).withOpacity(0.7),
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    onSelected: (Location selectedLocation) async {
                      // Just center the camera; onCameraIdle will compute the TIP latlng.
                      final latLng = LatLng(selectedLocation.latitude, selectedLocation.longitude);
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: latLng, zoom: 16.0),
                        ),
                      );
                      _searchController.clear();

                      // Keep the visible address text tidy; final address sync happens onCameraIdle.
                      final placemarks = await placemarkFromCoordinates(
                        selectedLocation.latitude,
                        selectedLocation.longitude,
                      );
                      if (placemarks.isNotEmpty) {
                        final p = placemarks.first;
                        String selectedAddress = '';
                        if (p.street?.isNotEmpty == true) {
                          selectedAddress = '${p.street}, ${p.locality ?? ''}';
                        } else if (p.subLocality?.isNotEmpty == true) {
                          selectedAddress = '${p.subLocality}, ${p.locality ?? ''}';
                        } else {
                          selectedAddress = p.locality ?? 'Selected location';
                        }
                        setState(() {
                          _selectedAddress = selectedAddress;
                        });
                      }
                    },
                    emptyBuilder: (context) => const SizedBox.shrink(),
                    loadingBuilder: (context) => _loadingSuggestionTile(),
                    errorBuilder: (context, error) => Container(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No locations found',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    decorationBuilder: (context, child) {
                      return Material(
                        type: MaterialType.transparency,
                        child: Container(
                          constraints: BoxConstraints(maxHeight: screenHeight * 0.3),
                          padding: const EdgeInsets.only(top: 6),
                          child: child,
                        ),
                      );
                    },
                    offset: const Offset(0, 6),
                  ),
                ),
              ),
            ),
          ),

          // 📍 My Location Button
          Positioned(
            bottom: bottomSheetHeight + mediaQuery.padding.bottom + 32,
            right: 16,
            child: GestureDetector(
              onTap: () async {
                if (_currentPosition != null) {
                  // ⬇️ No zoom passed — we’ll preserve whatever zoom the map already has
                  await _snapPinTipToCurrentLocation();
                }
              },

              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF42A5F5).withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded, color: Color(0xFF42A5F5), size: 24),
              ),
            ),
          ),

          // 🔽 Premium Bottom Sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: SafeArea(
                top: false,
                bottom: true, // SafeArea supplies system inset
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: const Color(0xFF42A5F5).withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 25,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  // ✅ EXACT same visual gap as _buildMapView: 16dp inside SafeArea
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF42A5F5).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Location Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFF42A5F5).withOpacity(0.2),
                                  Colors.white.withOpacity(0.05),
                                ],
                                radius: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.place_rounded, color: Color(0xFF42A5F5), size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Delivery Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF42A5F5),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Address Display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF42A5F5).withOpacity(0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_rounded, color: Color(0xFF42A5F5), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedAddress.isNotEmpty ? _selectedAddress : 'Move map to select location',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF42A5F5),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Confirm Button (solid blue; stays blue when disabled)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _selectedLocation != null && !_isLocationLoading
                              ? _confirmLocationAndCheckService
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF42A5F5),
                            disabledBackgroundColor: const Color(0xFF42A5F5),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white70,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLocationLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                              : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Confirm Location',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildServiceNotAvailableScreen() {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomPadding = mediaQuery.padding.bottom;

    final buttonBottomPadding = screenHeight < 600 ? 12.0 : 16.0;
    final totalBottomPadding = bottomPadding + buttonBottomPadding;

    return Container(
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: totalBottomPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - 200,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _bounceAnimation.value,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.orange.withOpacity(0.3),
                              Colors.orange.withOpacity(0.1),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.7, 1.0],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.3),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.iron_outlined,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [Colors.white, Colors.orange.withOpacity(0.8)],
                  ).createShader(bounds),
                  child: const Text(
                    'IronXpress Not Available',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'We don\'t provide our services in this area yet, but we\'re expanding rapidly!',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.3),
                              Colors.white.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.iron,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _selectedAddress.isNotEmpty ? _selectedAddress : _currentLocation,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          _bounceController.reset();
                          setState(() {
                            _showMap = true;
                            _hasLocationChecked = false;
                            _isLocationLoading = false;
                            _locationVerifiedSuccessfully = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF42A5F5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map_rounded, color: Color(0xFF42A5F5), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Try Different Location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF42A5F5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          _bounceController.reset();
                          setState(() {
                            _locationVerifiedSuccessfully = false;
                          });
                          _checkLocationAndService();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(0.5), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Check Again',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
Widget _loadingSuggestionTile() {
  return Container(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.location_on_rounded,
            color: Color(0xFF42A5F5),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Loading...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}
  
  