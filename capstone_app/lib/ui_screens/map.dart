import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'dart:async';

class MapPage extends StatefulWidget {
  final double incidentLat;
  final double incidentLng;
  final String incidentType;
  final String userRole; // 'bfp', 'pnp', or 'mdrrmo'
  final String? incidentLocationText;

  const MapPage({
    Key? key,
    required this.incidentLat,
    required this.incidentLng,
    required this.incidentType,
    required this.userRole,
    this.incidentLocationText,
  }) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Position? _currentPosition;
  bool _isLoading = true;
  String _errorMessage = '';
  List<LatLng> _polylinePoints = [];
  bool _showRoute = true;
  bool _isTracking = true; // Track if live tracking is enabled
  final MapController _mapController = MapController();
  
  // Location streaming
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocationStreamActive = false;

  // Victoria, Laguna coordinates (center point)
  static const double VICTORIA_LAT = 14.2264;
  static const double VICTORIA_LNG = 121.3252;

  // Agency locations in Victoria, Laguna (for reference only)
  final Map<String, Map<String, dynamic>> _agencyLocations = {
    'bfp': {
      'name': 'Bureau of Fire Protection - Victoria Station',
      'lat': 14.2270,
      'lng': 121.3270,
      'address': 'Poblacion, Victoria, Laguna',
      'icon': Icons.local_fire_department,
      'color': Colors.red,
    },
    'pnp': {
      'name': 'Philippine National Police - Victoria Station',
      'lat': 14.2250,
      'lng': 121.3230,
      'address': 'Municipal Compound, Victoria, Laguna',
      'icon': Icons.security,
      'color': Colors.blue,
    },
    'mdrrmo': {
      'name': 'MDRRMO - Victoria Office',
      'lat': 14.2245,
      'lng': 121.3240,
      'address': 'Municipal Hall, Victoria, Laguna',
      'icon': Icons.emergency,
      'color': Colors.green,
    },
  };

  // Get responsive dimensions based on screen size
  double get screenWidth => MediaQuery.of(context).size.width;
  double get screenHeight => MediaQuery.of(context).size.height;
  double get screenDiagonal => math.sqrt(math.pow(screenWidth, 2) + math.pow(screenHeight, 2));
  
  // More granular screen size detection
  bool get isExtraSmallScreen => screenWidth < 340;
  bool get isSmallScreen => screenWidth >= 340 && screenWidth < 400;
  bool get isMediumScreen => screenWidth >= 400 && screenWidth < 500;
  bool get isLargeScreen => screenWidth >= 500;
  
  bool get isPortrait => screenHeight > screenWidth;
  bool get isLandscape => screenWidth > screenHeight;

  // Responsive font sizes based on screen diagonal
  double get headerFontSize {
    if (isExtraSmallScreen) return 16;
    if (isSmallScreen) return 18;
    if (isMediumScreen) return 20;
    return 22;
  }

  double get cardTitleFontSize {
    if (isExtraSmallScreen) return 12;
    if (isSmallScreen) return 14;
    return 16;
  }

  double get bodyFontSize {
    if (isExtraSmallScreen) return 10;
    if (isSmallScreen) return 12;
    return 14;
  }

  double get smallFontSize {
    if (isExtraSmallScreen) return 8;
    if (isSmallScreen) return 10;
    return 12;
  }

  // Responsive padding and margins
  double get horizontalPadding {
    if (isExtraSmallScreen) return 8;
    if (isSmallScreen) return 12;
    if (isMediumScreen) return 16;
    return 20;
  }

  double get verticalPadding {
    if (isExtraSmallScreen) return 6;
    if (isSmallScreen) return 8;
    if (isMediumScreen) return 12;
    return 16;
  }

  double get cardMargin {
    if (isExtraSmallScreen) return 6;
    if (isSmallScreen) return 8;
    if (isMediumScreen) return 12;
    return 16;
  }

  // Button sizes
  double get buttonHeight {
    if (isExtraSmallScreen) return 40;
    if (isSmallScreen) return 44;
    if (isMediumScreen) return 48;
    return 52;
  }

  double get iconSize {
    if (isExtraSmallScreen) return 16;
    if (isSmallScreen) return 18;
    if (isMediumScreen) return 20;
    return 22;
  }

  // Map height calculation
  double get mapHeight {
    if (isLandscape) return screenHeight * 0.6;
    if (isExtraSmallScreen) return screenHeight * 0.3;
    if (isSmallScreen) return screenHeight * 0.35;
    if (isMediumScreen) return screenHeight * 0.4;
    return screenHeight * 0.45;
  }

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    // Clean up the stream subscription when the widget is disposed
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    try {
      await _getCurrentLocation();
      if (mounted) {
        await _calculateRoute();
        _startLocationTracking(); // Start live tracking after initial setup
      }
    } catch (e) {
      print('Error initializing location: $e');
      setState(() {
        _errorMessage = 'Unable to get current location: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied, we cannot request permissions.';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print('Error getting current location: $e');
      throw e;
    }
  }

  void _startLocationTracking() {
    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10, // Update every 10 meters
          timeLimit: Duration(seconds: 30), // Timeout after 30 seconds
        ),
      ).listen(
        (Position position) {
          print('Location update: ${position.latitude}, ${position.longitude}');
          
          if (mounted) {
            setState(() {
              _currentPosition = position;
              _isLocationStreamActive = true;
            });
            
            // Recalculate route with new position
            _recalculateRoute();
            
            // Auto-center map if tracking is enabled
            if (_isTracking) {
              _centerMapOnCurrentLocation();
            }
          }
        },
        onError: (error) {
          print('Location stream error: $error');
          if (mounted) {
            setState(() {
              _isLocationStreamActive = false;
            });
          }
        },
      );
    } catch (e) {
      print('Error starting location tracking: $e');
    }
  }

  void _stopLocationTracking() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _isLocationStreamActive = false;
    });
  }

  void _toggleTracking() {
    setState(() {
      _isTracking = !_isTracking;
    });
    
    if (_isTracking && _currentPosition != null) {
      _centerMapOnCurrentLocation();
    }
  }

  void _centerMapOnCurrentLocation() {
    if (_currentPosition == null) return;
    
    final currentLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    
    _mapController.move(currentLatLng, _mapController.zoom);
  }

  // OSRM Route Calculation
  Future<List<LatLng>> _getOSRMRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        
        if (jsonResponse['code'] == 'Ok' && jsonResponse['routes'].isNotEmpty) {
          final geometry = jsonResponse['routes'][0]['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          return coordinates.map<LatLng>((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();
        }
      }
    } catch (e) {
      print('OSRM routing error: $e');
    }
    
    return [start, end];
  }

  Future<void> _calculateRoute() async {
    try {
      if (_currentPosition == null) {
        throw 'Current location not available';
      }

      final startLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final endLatLng = LatLng(widget.incidentLat, widget.incidentLng);

      final routePoints = await _getOSRMRoute(startLatLng, endLatLng);
      
      setState(() {
        _polylinePoints = routePoints;
        _isLoading = false;
      });

      _fitMapToRoute();
    } catch (e) {
      print('Error calculating route: $e');
      setState(() {
        _errorMessage = 'Error calculating route: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _recalculateRoute() async {
    try {
      if (_currentPosition == null) return;

      final startLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final endLatLng = LatLng(widget.incidentLat, widget.incidentLng);

      final routePoints = await _getOSRMRoute(startLatLng, endLatLng);
      
      if (mounted) {
        setState(() {
          _polylinePoints = routePoints;
        });
      }
    } catch (e) {
      print('Error recalculating route: $e');
    }
  }

  void _fitMapToRoute() {
    if (_currentPosition == null) return;

    final startLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final endLatLng = LatLng(widget.incidentLat, widget.incidentLng);

    final bounds = LatLngBounds(startLatLng, endLatLng);
    
    Future.delayed(Duration(milliseconds: 100), () {
      _mapController.fitBounds(
        bounds,
        options: FitBoundsOptions(
          padding: EdgeInsets.all(50),
        ),
      );
    });
  }

  void _toggleRoute() {
    setState(() {
      _showRoute = !_showRoute;
    });
  }

  void _centerMap() {
    if (_currentPosition == null) return;

    final startLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final endLatLng = LatLng(widget.incidentLat, widget.incidentLng);
    
    final bounds = LatLngBounds(startLatLng, endLatLng);
    _mapController.fitBounds(
      bounds,
      options: FitBoundsOptions(padding: EdgeInsets.all(50)),
    );
  }

  Map<String, dynamic> get _startingPoint {
    if (_currentPosition != null) {
      return {
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
        'name': 'Your Current Location',
        'address': 'Your current position',
      };
    } else {
      return _agencyLocations[widget.userRole] ?? _agencyLocations['bfp']!;
    }
  }

  String get _agencyName {
    return _currentPosition != null ? 'Your Location' : 
      widget.userRole == 'bfp' ? 'BFP Victoria Station' :
      widget.userRole == 'pnp' ? 'PNP Victoria Station' : 'MDRRMO Victoria Office';
  }

  IconData get _agencyIcon {
    return _currentPosition != null ? Icons.my_location : 
      _agencyLocations[widget.userRole]?['icon'] ?? Icons.local_fire_department;
  }

  Color get _agencyColor {
    return _currentPosition != null ? Colors.blue : 
      _agencyLocations[widget.userRole]?['color'] ?? Colors.red;
  }

  String _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    final distance = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    
    if (distance < 1000) {
      return '${distance.round()} meters';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  String _calculateEstimatedTime(double distanceMeters) {
    final distanceKm = distanceMeters / 1000;
    final hours = distanceKm / 40;
    final minutes = (hours * 60).round();
    
    if (minutes < 1) {
      return 'Less than 1 minute';
    } else if (minutes < 60) {
      return '$minutes minutes';
    } else {
      final hrs = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '$hrs hrs $mins mins' : '$hrs hrs';
    }
  }

  Future<void> _openOSMRouting() async {
    final startPoint = _startingPoint;
    final url = 'https://www.openstreetmap.org/directions?'
        'engine=fossgis_osrm_car&'
        'route=${startPoint['lat'].toStringAsFixed(6)}%2C${startPoint['lng'].toStringAsFixed(6)}%3B'
        '${widget.incidentLat.toStringAsFixed(6)}%2C${widget.incidentLng.toStringAsFixed(6)}';

    await _launchUrl(url);
  }

  Future<void> _openGoogleMapsRouting() async {
    final startPoint = _startingPoint;
    final url = 'https://www.google.com/maps/dir/'
        '${startPoint['lat'].toStringAsFixed(6)},${startPoint['lng'].toStringAsFixed(6)}/'
        '${widget.incidentLat.toStringAsFixed(6)},${widget.incidentLng.toStringAsFixed(6)}';

    await _launchUrl(url);
  }

  Future<void> _openWazeNavigation() async {
    final url = 'https://waze.com/ul?ll=${widget.incidentLat.toStringAsFixed(6)}%2C${widget.incidentLng.toStringAsFixed(6)}&navigate=yes';
    await _launchUrl(url);
  }

  Future<void> _openMapView() async {
    final url = 'https://www.openstreetmap.org/?'
        'mlat=${widget.incidentLat.toStringAsFixed(6)}&'
        'mlon=${widget.incidentLng.toStringAsFixed(6)}&'
        'zoom=16&'
        'marker=${widget.incidentLat.toStringAsFixed(6)}%2C${widget.incidentLng.toStringAsFixed(6)}';

    await _launchUrl(url);
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      _showError('Unable to open map: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildLocationCard() {
    final startPoint = _startingPoint;
    final distance = Geolocator.distanceBetween(
      startPoint['lat'], startPoint['lng'],
      widget.incidentLat, widget.incidentLng,
    );

    return Card(
      margin: EdgeInsets.all(cardMargin),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(horizontalPadding * 0.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Incident Type
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: iconSize),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.incidentType.toUpperCase(),
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Live tracking indicator
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isLocationStreamActive ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLocationStreamActive ? Icons.location_on : Icons.location_off,
                        color: Colors.white,
                        size: iconSize * 0.7,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: smallFontSize,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            
            // Incident Location
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on, color: Colors.red, size: iconSize * 0.8),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.incidentLocationText ?? 'Incident Location',
                    style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            
            // Coordinates
            Row(
              children: [
                Icon(Icons.my_location, color: Colors.blue, size: iconSize * 0.8),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.incidentLat.toStringAsFixed(6)}, ${widget.incidentLng.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: smallFontSize,
                      fontFamily: 'monospace',
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            
            Divider(height: 1),
            SizedBox(height: 8),
            
            // Starting Point
            Row(
              children: [
                Icon(_agencyIcon, color: _agencyColor, size: iconSize * 0.8),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'From: $_agencyName',
                    style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            
            // Current location coordinates
            if (_currentPosition != null)
              Row(
                children: [
                  Icon(Icons.gps_fixed, color: Colors.green, size: iconSize * 0.8),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: smallFontSize,
                        fontFamily: 'monospace',
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            
            SizedBox(height: 8),
            
            // Distance and Time in a compact row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alt_route, color: Colors.purple, size: iconSize * 0.8),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _calculateDistance(
                            startPoint['lat'], startPoint['lng'],
                            widget.incidentLat, widget.incidentLng,
                          ),
                          style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, color: Colors.orange, size: iconSize * 0.8),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _calculateEstimatedTime(distance),
                          style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return Flexible(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: iconSize * 0.8),
          label: Text(
            title,
            style: TextStyle(fontSize: isExtraSmallScreen ? 8 : 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              vertical: isExtraSmallScreen ? 6 : 8,
              horizontal: 4,
            ),
            minimumSize: Size(0, buttonHeight * 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
      child: Column(
        children: [
          Text(
            'Navigation:',
            style: TextStyle(
              fontSize: cardTitleFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          
          
          
          // Control buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: buttonHeight * 0.7,
                  child: ElevatedButton.icon(
                    onPressed: _toggleRoute,
                    icon: Icon(
                      _showRoute ? Icons.route : Icons.route_outlined,
                      size: iconSize * 0.8,
                    ),
                    label: Text(
                      _showRoute ? 'Hide Route' : 'Show Route',
                      style: TextStyle(fontSize: bodyFontSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showRoute ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: buttonHeight * 0.7,
                  child: ElevatedButton.icon(
                    onPressed: _toggleTracking,
                    icon: Icon(
                      _isTracking ? Icons.gps_fixed : Icons.gps_off,
                      size: iconSize * 0.8,
                    ),
                    label: Text(
                      _isTracking ? 'Tracking ON' : 'Tracking OFF',
                      style: TextStyle(fontSize: bodyFontSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTracking ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          
          // Center map button
          SizedBox(
            width: double.infinity,
            height: buttonHeight * 0.7,
            child: ElevatedButton.icon(
              onPressed: _centerMap,
              icon: Icon(Icons.center_focus_strong, size: iconSize * 0.8),
              label: Text('Center Map on Route', style: TextStyle(fontSize: bodyFontSize)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveMap() {
    final startPoint = _startingPoint;
    final startLatLng = LatLng(startPoint['lat'], startPoint['lng']);
    final endLatLng = LatLng(widget.incidentLat, widget.incidentLng);

    return Container(
      height: mapHeight,
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            center: LatLng(VICTORIA_LAT, VICTORIA_LNG),
            zoom: 14.0,
            interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.emergency_app',
            ),
            
            if (_showRoute && _polylinePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _polylinePoints,
                    strokeWidth: isExtraSmallScreen ? 2 : 3,
                    color: Colors.blue.withOpacity(0.7),
                  ),
                ],
              ),
            
            MarkerLayer(
              markers: [
                // Start Marker (Current Location) - Animated if tracking
                Marker(
                  point: startLatLng,
                  width: isExtraSmallScreen ? 30 : 35,
                  height: isExtraSmallScreen ? 30 : 35,
                  child: _isTracking && _isLocationStreamActive 
                      ? _buildAnimatedLocationMarker()
                      : Column(
                          children: [
                            Icon(
                              Icons.my_location,
                              color: _isLocationStreamActive ? Colors.green : Colors.blue,
                              size: isExtraSmallScreen ? 20 : 25,
                            ),
                            Text(
                              'YOU',
                              style: TextStyle(
                                fontSize: isExtraSmallScreen ? 6 : 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
                
                // End Marker (Incident)
                Marker(
                  point: endLatLng,
                  width: isExtraSmallScreen ? 30 : 35,
                  height: isExtraSmallScreen ? 30 : 35,
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: Colors.red,
                        size: isExtraSmallScreen ? 20 : 25,
                      ),
                      Text(
                        'INCIDENT',
                        style: TextStyle(
                          fontSize: isExtraSmallScreen ? 6 : 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing circle effect
        Container(
          width: isExtraSmallScreen ? 25 : 30,
          height: isExtraSmallScreen ? 25 : 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(0.3),
          ),
        ),
        // Main icon
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.my_location,
              color: Colors.green,
              size: isExtraSmallScreen ? 18 : 22,
            ),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: isExtraSmallScreen ? 5 : 6,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(horizontalPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_agencyColor),
            ),
            SizedBox(height: 16),
            Text(
              'Getting your location...',
              style: TextStyle(
                fontSize: bodyFontSize,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: EdgeInsets.all(horizontalPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: iconSize * 2,
          ),
          SizedBox(height: 16),
          Text(
            'Error Loading Map',
            style: TextStyle(
              fontSize: headerFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.red[700],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _initializeLocation,
            icon: Icon(Icons.refresh, size: iconSize),
            label: Text('Try Again', style: TextStyle(fontSize: bodyFontSize)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _agencyColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Emergency Route',
          style: TextStyle(fontSize: headerFontSize),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _agencyColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: iconSize),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : SafeArea(
                  child: Column(
                    children: [
                      // Location card
                      _buildLocationCard(),
                      
                      // Action buttons
                      _buildActionButtons(),
                      
                      // Interactive map
                      Expanded(
                        child: _buildInteractiveMap(),
                      ),
                    ],
                  ),
                ),
    );
  }
}