// ✅ UPDATED PREMIUM LOCATION SELECTION SCREEN
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'colors.dart';

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

  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _scaleAnimation;

  // Auth subscription
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeSupabase();
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationError('Please enable location services for ironXpress pickup/delivery');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _handleLocationError('Location permission needed for ironXpress ');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _handleLocationError('Please enable location in settings for ironXpress ');
        return;
      }

      if (mounted) {
        setState(() {
          _currentLocation = 'Getting your location...';
        });
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      print('📍 Got coordinates: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

      List<Placemark> placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        final address = '${place.name ?? place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}';

        if (mounted) {
          setState(() {
            _currentLocation = address;
            _selectedLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
            _selectedAddress = address;
            _isLocationLoading = false;
            _showMap = true;
            _markers = {
              Marker(
                markerId: const MarkerId('selected_location'),
                position: _selectedLocation!,
                infoWindow: InfoWindow(title: 'Your Location', snippet: address),
              ),
            };
          });
        }

        _pulseController.stop();
        print('✅ Location detected: $address');
      } else {
        await _handleLocationError('Unable to get address for ironXpress ');
      }
    } catch (e) {
      _pulseController.stop();
      print('❌ Location error: $e');
      await _handleLocationError('Unable to get your location. Please try again.');
    }
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

      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isEmpty) {
        print('❌ No area details found');
        return false;
      }

      final place = placemarks[0];
      final pincode = place.postalCode;

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

      bool isAvailable = response != null;
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
      List<Placemark> placemarks = await placemarkFromCoordinates(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
      );

      String? pincode;
      if (placemarks.isNotEmpty) {
        pincode = placemarks[0].postalCode?.replaceAll(RegExp(r'[^0-9]'), '');
      }

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
    if (mounted) {
      setState(() {
        _selectedLocation = location;
        _markers = {
          Marker(
            markerId: const MarkerId('selected_location'),
            position: location,
            infoWindow: const InfoWindow(title: 'Selected Location'),
          ),
        };
      });
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        final address = '${place.name ?? place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}';
        if (mounted) {
          setState(() {
            _selectedAddress = address;
            _markers = {
              Marker(
                markerId: const MarkerId('selected_location'),
                position: location,
                infoWindow: InfoWindow(title: 'Selected Location', snippet: address),
              ),
            };
          });
        }
      }
    } catch (e) {
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
    _mapController?.dispose();
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;

    // Calculate dynamic padding based on screen size
    final dynamicBottomPadding = screenHeight < 600 ? 16.0 : 24.0;
    final totalBottomPadding = bottomPadding + dynamicBottomPadding;

    // ✅ SHOW LOADING WHILE SUPABASE INITIALIZES
    if (!isSupabaseReady) {
      return Scaffold(
        body: Container(
            decoration: _buildIronBackgroundGradient(),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kPrimaryColor),
                  SizedBox(height: 20),
                  Text(
                    'Setting up ironXpress...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
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
            decoration: _buildIronBackgroundGradient(),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kPrimaryColor),
                  SizedBox(height: 20),
                  Text(
                    'Checking your account...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
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
          decoration: _buildIronBackgroundGradient(),
          child: _buildLocationScreen(),
        ),
      );
    }

    // ✅ LOGIN STATE (NO SESSION FOUND)
    return const LoginScreen();
  }

  BoxDecoration _buildIronBackgroundGradient() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1565C0).withOpacity(0.1), // Electric blue
          const Color(0xFF2196F3).withOpacity(0.05), // Blue
          Colors.white.withOpacity(0.9),
          const Color(0xFF42A5F5).withOpacity(0.02), // Light blue
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
    );
  }

  Widget _buildLocationScreen() {
    if (!_hasLocationChecked || _isLocationLoading) {
      return _showMap ? _buildMapSelectionScreen() : _buildLocationDetectionScreen();
    }

    return !_isServiceAvailable ? _buildServiceNotAvailableScreen() : _buildLocationDetectionScreen();
  }

  Widget _buildLocationDetectionScreen() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1565C0).withOpacity(0.2),
                          const Color(0xFF2196F3).withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.iron,
                      size: 70,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
              ).createShader(bounds),
              child: const Text(
                'Setting up ironXpress area',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Text(
                _currentLocation,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            if (_isLocationLoading)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFF1565C0),
                  strokeWidth: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSelectionScreen() {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final bottomPadding = mediaQuery.padding.bottom;

    // Calculate dynamic values based on screen size
    final bottomSheetHeight = screenHeight * 0.35;
    final buttonBottomPadding = screenHeight < 600 ? 16.0 : 24.0;
    final totalBottomPadding = bottomPadding + buttonBottomPadding;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: _selectedLocation ?? const LatLng(20.2961, 85.8245),
              zoom: 15.0,
            ),
            markers: _markers,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: EdgeInsets.only(
              top: screenHeight * 0.15,
              bottom: bottomSheetHeight,
            ),
          ),

          // Fixed location pin at center
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_pin,
                    size: 48,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          // Search bar at top
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TypeAheadField<Location>(
                controller: _searchController,
                builder: (context, controller, focusNode) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Search for area, street name...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade600,
                      ),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                        icon: Icon(
                          Icons.close,
                          color: Colors.grey.shade600,
                        ),
                        onPressed: () {
                          controller.clear();
                          // Removed setState since controller is managed internally
                        },
                      )
                          : null,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  );
                },
                suggestionsCallback: (pattern) async {
                  if (pattern.length < 3) return [];
                  try {
                    return await locationFromAddress(pattern);
                  } catch (e) {
                    return [];
                  }
                },
                itemBuilder: (context, Location suggestion) {
                  return FutureBuilder<List<Placemark>>(
                    future: placemarkFromCoordinates(suggestion.latitude, suggestion.longitude),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const ListTile(
                          leading: Icon(Icons.location_on),
                          title: Text('Loading address...'),
                        );
                      }
                      final placemark = snapshot.data!.first;
                      return ListTile(
                        leading: const Icon(Icons.location_on),
                        title: Text(
                          placemark.street?.isNotEmpty == true
                              ? '${placemark.street}, ${placemark.locality}'
                              : placemark.locality ?? 'Unknown location',
                        ),
                        subtitle: Text(
                            '${placemark.subAdministrativeArea ?? ''} ${placemark.postalCode ?? ''}'
                        ),
                      );
                    },
                  );
                },
                onSelected: (Location selectedLocation) async {
                  final placemarks = await placemarkFromCoordinates(
                    selectedLocation.latitude,
                    selectedLocation.longitude,
                  );

                  if (placemarks.isEmpty) return;

                  final placemark = placemarks.first;
                  final latLng = LatLng(
                    selectedLocation.latitude,
                    selectedLocation.longitude,
                  );

                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: latLng,
                        zoom: 15.0,
                      ),
                    ),
                  );

                  await _onMapTap(latLng);
                  _searchController.clear();

                  setState(() {
                    _selectedAddress = placemark.street?.isNotEmpty == true
                        ? '${placemark.street}, ${placemark.locality}'
                        : placemark.locality ?? 'Selected location';
                  });
                },
                // ✅ FIXED: Changed from noItemsFoundBuilder to emptyBuilder
                emptyBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No locations found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
                // ✅ FIXED: Updated loadingBuilder syntax
                loadingBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Searching...'),
                    ],
                  ),
                ),
                // ✅ NEW: Added decoration for suggestions dropdown
                decorationBuilder: (context, child) {
                  return Material(
                    type: MaterialType.card,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  );
                },
                // ✅ NEW: Position offset for suggestions
                offset: const Offset(0, 12),
                // ✅ NEW: Constraints for suggestions height
                constraints: const BoxConstraints(maxHeight: 500),
              ),
            ),
          ),
          // My location button
          Positioned(
            bottom: bottomSheetHeight + totalBottomPadding + 20,
            right: 16,
            child: GestureDetector(
              onTap: () async {
                if (_currentPosition != null) {
                  final currentLatLng = LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  );

                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: currentLatLng,
                        zoom: 15.0,
                      ),
                    ),
                  );

                  await _onMapTap(currentLatLng);
                }
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xFF1565C0),
                  size: 24,
                ),
              ),
            ),
          ),

          // Bottom sheet with address and confirm button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: bottomSheetHeight,
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: totalBottomPadding,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 25,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.place,
                          color: Color(0xFF1565C0),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Your Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedAddress.isNotEmpty ? _selectedAddress : 'Move map to select location',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _selectedLocation != null && !_isLocationLoading
                          ? _confirmLocationAndCheckService
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLocationLoading
                          ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
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

    // Calculate dynamic values based on screen size
    final buttonBottomPadding = screenHeight < 600 ? 16.0 : 24.0;
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
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.withOpacity(0.2),
                              Colors.orange.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.iron_outlined,
                          size: 70,
                          color: Colors.orange,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [Colors.orange, Colors.orange.withOpacity(0.8)],
                  ).createShader(bounds),
                  child: const Text(
                    'IronXpress Not Available',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'We don\'t provide our services in this area yet, but we\'re expanding rapidly!',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
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
                            color: Colors.black87,
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
                      height: 56,
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
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, color: Colors.white),
                            SizedBox(width: 12),
                            Text(
                              'Try Different Location',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () {
                          _bounceController.reset();
                          setState(() {
                            _locationVerifiedSuccessfully = false;
                          });
                          _checkLocationAndService();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1565C0),
                          side: const BorderSide(color: Color(0xFF1565C0), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Color(0xFF1565C0)),
                            SizedBox(width: 12),
                            Text(
                              'Check Again',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}