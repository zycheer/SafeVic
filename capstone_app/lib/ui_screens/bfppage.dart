import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'map.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class BFPPage extends StatefulWidget {
  @override
  _BFPPageState createState() => _BFPPageState();
}

class _BFPPageState extends State<BFPPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Location-related variables
  Position? _currentPosition;
  bool _locationPermissionGranted = false;
  
  // Debug flag to show all incidents or just fire incidents
  bool _showDebugInfo = true;
  bool _showAllIncidents = false;

  // Fire incident categories
  static const List<String> fireIncidentTypes = [
    'Building Fire', 'Vehicle Fire', 'Wildfire/Grass Fire', 
            'Gas Leak', 'Chemical Spill', 'Electrical Fire', 'Smoke',
            'Kitchen Fire', 'Industrial Fire', 'Forest Fire'
  ];

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkAuthAndPermissions();
    _requestLocationPermission();

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    _notificationsPlugin.initialize(initSettings);

    // Subscribe to department topic
    FirebaseMessaging.instance.subscribeToTopic('bfp'); // Use 'pnp' or 'mdrrmo' for other pages

    // Listen for FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // Check department match
      if (message.data['department'] == 'Fire Department') { // Change for each page
        final emergencyType = message.data['emergencyType'] ?? 'Emergency';
        final userName = message.data['userName'] ?? 'Unknown';

        // Show local notification
        await _notificationsPlugin.show(
          0,
          'New Fire Emergency',
          '$emergencyType reported by $userName',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'fire_channel',
              'Fire Emergencies',
              channelDescription: 'Notifications for fire emergencies',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
          ),
        );

        // Play alert sound
        await _audioPlayer.play(AssetSource('sounds/alert2.mp3')); // Place your alert sound in assets/sounds/alert.mp3

        // Show snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔥 New Fire Emergency: $emergencyType by $userName'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  // Get responsive dimensions based on screen size
  double get screenWidth => MediaQuery.of(context).size.width;
  double get screenHeight => MediaQuery.of(context).size.height;
  bool get isSmallScreen => screenWidth < 360;
  bool get isMediumScreen => screenWidth >= 360 && screenWidth < 410;
  bool get isLargeScreen => screenWidth >= 410;

  // Responsive font sizes
  double get headerFontSize => isSmallScreen ? 18 : isMediumScreen ? 20 : 22;
  double get subHeaderFontSize => isSmallScreen ? 12 : isMediumScreen ? 14 : 14;
  double get cardTitleFontSize => isSmallScreen ? 14 : isMediumScreen ? 16 : 16;
  double get bodyFontSize => isSmallScreen ? 12 : isMediumScreen ? 14 : 14;
  double get smallFontSize => isSmallScreen ? 10 : isMediumScreen ? 11 : 12;

  // Responsive padding and margins
  double get horizontalPadding => isSmallScreen ? 12 : isMediumScreen ? 16 : 20;
  double get verticalPadding => isSmallScreen ? 8 : isMediumScreen ? 12 : 16;
  double get cardMargin => isSmallScreen ? 8 : isMediumScreen ? 12 : 16;

  // Method to send notifications to users when disaster responders take action
  Future<void> _sendResponderNotificationToUser(
  String incidentId, 
  Map<String, dynamic> incidentData, 
  String actionType,
  String incidentCategory
) async {
  try {
    const String flaskUrl = 'https://capstone-production-9474.up.railway.app/api/responder_update';
    
    final user = FirebaseAuth.instance.currentUser;
    final responderName = user?.displayName ?? user?.email ?? 'BFP Responder';
    
    final notificationData = {
      'incidentId': incidentId,
      'actionType': actionType, // 'responded' or 'resolved'
      'responderName': responderName,
      'department': 'Fire Department',
      'incidentCategory': incidentCategory,
      'emergencyType': incidentData['emergencyType'] ?? incidentCategory,
      'userName': incidentData['userName'] ?? 'User',
      'userContact': incidentData['contactNumber'] ?? incidentData['contact'] ?? 'No contact',
      'responseTeam': _getResponseTeamForIncident(incidentCategory),
      'responseMessage': _getResponseMessage(incidentCategory),
      'timestamp': DateTime.now().toIso8601String(),
    };

    print('Sending responder notification to Flask backend...');
    
    final response = await http.post(
      Uri.parse(flaskUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode(notificationData),
    ).timeout(Duration(seconds: 10));

    print('Flask response status: ${response.statusCode}');
    print('Flask response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      if (responseData['success'] == true) {
        print('✓ Responder notification sent successfully to user');
        
        // Show local success notification
        await _notificationsPlugin.show(
          1,
          'User Notified',
          'User has been notified that you are responding',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'responder_channel',
              'Responder Actions',
              channelDescription: 'Notifications for responder actions',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      } else {
        throw Exception('Flask returned error: ${responseData['error']}');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('Error sending responder notification: $e');
    
    // Show warning but don't block the action
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('User notification failed, but response was recorded'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }
}


  Future<void> _makePhoneCallAndroid(String phoneNumber) async {
  try {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: phoneNumber.replaceAll(RegExp(r'[^\d+]'), ''),
    );
    
    await launchUrl(
      phoneUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    print('Failed to make call: $e');
  }
}

  // Request location permission and get current position
  Future<void> _requestLocationPermission() async {
    try {
      final permission = await Permission.location.request();
      
      if (permission == PermissionStatus.granted) {
        _locationPermissionGranted = true;
        await _getCurrentLocation();
      } else {
        _locationPermissionGranted = false;
        print('Location permission denied');
      }
    } catch (e) {
      print('Error requesting location permission: $e');
    }
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    try {
      if (!_locationPermissionGranted) {
        print('Location permission not granted');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      setState(() {
        _currentPosition = position;
      });

      print('Current location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  // Parse location from various formats
  Map<String, double>? _parseLocation(dynamic locationData) {
    if (locationData == null) return null;
    
    try {
      if (locationData is Map) {
        final locMap = locationData as Map<String, dynamic>;
        
        // Check for coordinates object
        if (locMap['coordinates'] != null) {
          final coords = locMap['coordinates'];
          if (coords is Map) {
            final lat = coords['latitude']?.toDouble();
            final lng = coords['longitude']?.toDouble();
            if (lat != null && lng != null) {
              return {'latitude': lat, 'longitude': lng};
            }
          }
        }
        
        // Check for direct lat/lng fields
        final lat = locMap['latitude']?.toDouble() ?? locMap['lat']?.toDouble();
        final lng = locMap['longitude']?.toDouble() ?? locMap['lng']?.toDouble();
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
      
      // Check if it's a string with coordinates
      if (locationData is String) {
        final coordPattern = RegExp(r'(-?\d+\.?\d*),\s*(-?\d+\.?\d*)');
        final match = coordPattern.firstMatch(locationData);
        if (match != null) {
          final lat = double.tryParse(match.group(1)!);
          final lng = double.tryParse(match.group(2)!);
          if (lat != null && lng != null) {
            return {'latitude': lat, 'longitude': lng};
          }
        }
      }
    } catch (e) {
      print('Error parsing location: $e');
    }
    
    return null;
  }

  // Get location text for display
  String _getLocationText(dynamic locationData) {
    if (locationData == null) return 'Unknown Location';
    
    if (locationData is Map) {
      final locationMap = locationData as Map<String, dynamic>;
      return locationMap['address']?.toString() ?? 
             locationMap['description']?.toString() ??
             locationMap['coordinates']?.toString() ??
             'Map Location';
    }
    
    return locationData.toString();
  }

  // Open location in map with routing
  Future<void> _openLocationInMap(dynamic locationData, String incidentType) async {
    final coordinates = _parseLocation(locationData);
    
    if (coordinates == null) {
      _showErrorDialog('Location data is not available or invalid for this incident.');
      return;
    }

    final lat = coordinates['latitude']!;
    final lng = coordinates['longitude']!;
    
    // Show responsive loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Container(
          width: screenWidth * 0.8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(width: horizontalPadding),
              Flexible(
                child: Text(
                  'Opening map...',
                  style: TextStyle(fontSize: bodyFontSize),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      String mapUrl;
      
      if (_currentPosition != null) {
        final currentLat = _currentPosition!.latitude;
        final currentLng = _currentPosition!.longitude;
        
        mapUrl = 'https://www.openstreetmap.org/directions?'
            'engine=fossgis_osrm_car&'
            'route=${currentLat.toStringAsFixed(6)}%2C${currentLng.toStringAsFixed(6)}%3B'
            '${lat.toStringAsFixed(6)}%2C${lng.toStringAsFixed(6)}&'
            'zoom=15&'
            'marker=${lat.toStringAsFixed(6)}%2C${lng.toStringAsFixed(6)}';
      } else {
        mapUrl = 'https://www.openstreetmap.org/?'
            'mlat=${lat.toStringAsFixed(6)}&'
            'mlon=${lng.toStringAsFixed(6)}&'
            'zoom=15&'
            'layers=M';
      }

      Navigator.of(context).pop();

      final uri = Uri.parse(mapUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showMapDialog(lat, lng, incidentType);
      }
    } catch (e) {
      Navigator.of(context).pop();
      print('Error opening map: $e');
      
      if (coordinates != null) {
        _showMapDialog(coordinates['latitude']!, coordinates['longitude']!, incidentType);
      } else {
        _showErrorDialog('Unable to open map. Please check your internet connection.');
      }
    }
  }

  // Show responsive map dialog
  void _showMapDialog(double lat, double lng, String incidentType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.red, size: isSmallScreen ? 20 : 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '$incidentType Location',
                style: TextStyle(fontSize: cardTitleFontSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Container(
          width: screenWidth * 0.85,
          constraints: BoxConstraints(maxHeight: screenHeight * 0.6),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.my_location, color: Colors.blue, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Coordinates:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: bodyFontSize,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      SelectableText(
                        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: smallFontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentPosition != null) ...[
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.navigation, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Distance from your location:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: bodyFontSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          _calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng),
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 16),
                Text(
                  'Choose how to view the location:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: bodyFontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Column(
            children: [
              // Responsive button layout
              if (isSmallScreen) ...[
                // Stack buttons vertically on small screens
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final googleUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                      final uri = Uri.parse(googleUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: Icon(Icons.map, color: Colors.green, size: 16),
                    label: Text('Google Maps', style: TextStyle(fontSize: smallFontSize)),
                  ),
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final osmUrl = 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng&zoom=15';
                      final uri = Uri.parse(osmUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: Icon(Icons.public, color: Colors.blue, size: 16),
                    label: Text('OpenStreetMap', style: TextStyle(fontSize: smallFontSize)),
                  ),
                ),
              ] else ...[
                // Side by side on larger screens
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final googleUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                          final uri = Uri.parse(googleUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: Icon(Icons.map, color: Colors.green),
                        label: Text('Google Maps'),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final osmUrl = 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng&zoom=15';
                          final uri = Uri.parse(osmUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: Icon(Icons.public, color: Colors.blue),
                        label: Text('OpenStreetMap'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_currentPosition != null) ...[
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final wazeUrl = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
                      final uri = Uri.parse(wazeUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
                    ),
                    icon: Icon(Icons.navigation, color: Colors.white, size: 16),
                    label: Text(
                      'Navigate with Waze',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: bodyFontSize,
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close', style: TextStyle(fontSize: bodyFontSize)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Calculate distance between two points
  String _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    final distance = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    
    if (distance < 1000) {
      return '${distance.round()} meters away';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km away';
    }
  }

  // Add logout method
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print('Error signing out: $e');
      _showErrorDialog('Failed to logout: $e');
    }
  }

  // Check authentication and permissions
  void _checkAuthAndPermissions() {
    final user = FirebaseAuth.instance.currentUser;
    print('=== AUTH DEBUG ===');
    print('User: ${user?.email}');
    print('UID: ${user?.uid}');
    print('Signed in: ${user != null}');
    
    if (user != null) {
      user.getIdToken().then((token) {
        print('Token obtained successfully');
      }).catchError((error) {
        print('Error getting token: $error');
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Fetch incidents - simplified query
  Stream<QuerySnapshot> _getFireIncidents() {
    print('=== QUERY DEBUG ===');
    print('Filter: $_selectedFilter');
    
    Query query = FirebaseFirestore.instance
        .collection('incidents')
        .orderBy('timestamp', descending: true)
        .limit(500);

    print('Executing query for all incidents, will filter client-side');
    return query.snapshots();
  }

  // Check if an incident is fire-related
  bool _isFireIncident(Map<String, dynamic> data) {
    final category = data['category']?.toString().toLowerCase() ?? '';
    final incidentCategory = data['incidentCategory']?.toString().toLowerCase() ?? '';
    final emergencyType = data['emergencyType']?.toString().toLowerCase() ?? '';
    final type = data['type']?.toString().toLowerCase() ?? '';
    final incidents = data['incidents']?.toString().toLowerCase() ?? '';
    final description = data['description']?.toString().toLowerCase() ?? '';
    
    final allText = '$category $incidentCategory $emergencyType $type $incidents $description'.toLowerCase();
    
    bool isFire = false;
    
    for (String fireType in fireIncidentTypes) {
      if (category == fireType.toLowerCase() || 
          incidentCategory == fireType.toLowerCase() ||
          emergencyType == fireType.toLowerCase() ||
          type == fireType.toLowerCase()) {
        isFire = true;
        break;
      }
    }
    
    if (!isFire) {
      isFire = _containsFireKeywords(allText);
    }
    
    if (_showDebugInfo && isFire) {
      print('✓ BFP Incident found: category="$category", emergencyType="$emergencyType", type="$type"');
    }
    
    return isFire;
  }

  // Comprehensive keyword checking
  bool _containsFireKeywords(String text) {
    if (text.isEmpty) return false;
    
    final fireKeywords = [
      'building fire', 'house fire', 'residential fire', 'commercial fire', 'structure fire', 'apartment fire',
      'vehicle fire', 'car fire', 'truck fire', 'motorcycle fire', 'bus fire', 'auto fire',
      'wildfire', 'wild fire', 'grass fire', 'forest fire', 'brush fire', 'vegetation fire', 'outdoor fire',
      'gas leak', 'gas emergency', 'lpg leak', 'natural gas', 'propane leak', 'gas explosion',
      'chemical spill', 'chemical leak', 'hazmat', 'hazardous material', 'toxic spill', 'chemical emergency',
      'rescue', 'trapped', 'stuck', 'confined space', 'elevator rescue', 'technical rescue', 'emergency rescue',
      'water rescue', 'drowning', 'flood rescue', 'river rescue', 'swimming accident', 'water emergency',
      'fire', 'burning', 'smoke', 'flame', 'blaze'
    ];
    
    return fireKeywords.any((keyword) => text.contains(keyword));
  }

  // Better incident categorization
  String _categorizeIncident(Map<String, dynamic> data) {
    final category = data['category']?.toString() ?? '';
    final incidentCategory = data['incidentCategory']?.toString() ?? '';
    final emergencyType = data['emergencyType']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    final incidents = data['incidents']?.toString() ?? '';
    final description = data['description']?.toString().toLowerCase() ?? '';
    
    final fieldsToCheck = [category, incidentCategory, emergencyType, type, incidents];
    for (String field in fieldsToCheck) {
      if (fireIncidentTypes.contains(field)) {
        return field;
      }
    }
    
    final allText = '$emergencyType $incidents $type $description $category'.toLowerCase();
    
    if (_containsKeywords(allText, ['building fire', 'house fire', 'residential fire', 'commercial fire', 'structure fire', 'apartment fire'])) {
      return 'Building Fire';
    }
    if (_containsKeywords(allText, ['vehicle fire', 'car fire', 'truck fire', 'motorcycle fire', 'bus fire', 'auto fire'])) {
      return 'Vehicle Fire';  
    }
    if (_containsKeywords(allText, ['wildfire', 'wild fire', 'grass fire', 'forest fire', 'brush fire', 'vegetation fire'])) {
      return 'Wildfire/Grass Fire';
    }
    if (_containsKeywords(allText, ['gas leak', 'gas emergency', 'lpg leak', 'natural gas', 'propane leak'])) {
      return 'Gas Leak';
    }
    if (_containsKeywords(allText, ['chemical spill', 'chemical leak', 'hazmat', 'hazardous material', 'toxic spill'])) {
      return 'Chemical Spill';
    }
    if (_containsKeywords(allText, ['rescue', 'trapped', 'stuck', 'confined space', 'elevator rescue', 'technical rescue']) && !_containsKeywords(allText, ['water', 'drowning', 'flood', 'river'])) {
      return 'Rescue Operation';
    }
    if (_containsKeywords(allText, ['water rescue', 'drowning', 'flood rescue', 'river rescue', 'swimming accident'])) {
      return 'Water Rescue';
    }
    if (_containsKeywords(allText, ['fire', 'burning', 'smoke', 'flame', 'blaze'])) {
      return 'Other Fire Emergency';
    }
    
    return 'Other Fire Emergency';
  }
  
  // Helper method to check if text contains any of the keywords
  bool _containsKeywords(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword.toLowerCase()));
  }

  // Helper method to check if incident matches the selected filter
  bool _matchesStatusFilter(Map<String, dynamic> data) {
    if (_selectedFilter == 'all') return true;
    
    final status = (data['status'] ?? 'reported').toString().toLowerCase();
    return status == _selectedFilter.toLowerCase();
  }

  Future<void> _respondToIncident(String incidentId, Map<String, dynamic> incidentData) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorDialog('You must be signed in to respond to incidents');
      return;
    }

    final incidentCategory = _categorizeIncident(incidentData);

    // Update incident status in Firestore
    await FirebaseFirestore.instance.collection('incidents').doc(incidentId).update({
      'status': 'active',
      'assignedTo': 'BFP Team',
      'assignedResponder': user.displayName ?? user.email ?? 'BFP Responder',
      'responseTime': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedBy': user.email ?? 'BFP',
      'isActive': true,
      'incidentCategory': incidentCategory,
      'responseTeam': _getResponseTeamForIncident(incidentCategory),
    });

    // Send notification to user that responder is on the way
    await _sendResponderNotificationToUser(
      incidentId, 
      incidentData, 
      'responded',
      incidentCategory
    );

    _showSuccessDialog('Response Confirmed', 
        'You have successfully responded to this ${incidentCategory.toLowerCase()}. ${_getResponseMessage(incidentCategory)}');

  } catch (e) {
    print('Error responding to incident: $e');
    _showErrorDialog('Failed to respond to incident: $e');
  }
}

  // Get appropriate response team based on incident type
  String _getResponseTeamForIncident(String incidentCategory) {
    switch (incidentCategory) {
      case 'Building Fire':
      case 'Vehicle Fire':
      case 'Wildfire/Grass Fire':
        return 'Fire Suppression Team';
      case 'Gas Leak':
      case 'Chemical Spill':
        return 'Hazmat Response Team';
      case 'Rescue Operation':
      case 'Water Rescue':
        return 'Rescue Operations Team';
      default:
        return 'Fire Response Team';
    }
  }

  // Get appropriate response message based on incident type
String _getResponseMessage(String incidentCategory) {
  switch (incidentCategory) {
    case 'Building Fire':
      return 'Fire trucks and ladder company are dispatched. Help is on the way!';
    case 'Vehicle Fire':
      return 'Fire engine and foam unit are dispatched. Emergency team is coming!';
    case 'Wildfire/Grass Fire':
      return 'Wildfire suppression units are dispatched. Firefighters are responding!';
    case 'Gas Leak':
      return 'Hazmat team and gas company notified. Specialized team is en route!';
    case 'Chemical Spill':
      return 'Hazmat response team is dispatched. Experts are on their way!';
    case 'Rescue Operation':
      return 'Technical rescue team is dispatched. Rescue team is coming!';
    case 'Water Rescue':
      return 'Water rescue team and divers are dispatched. Help is arriving soon!';
    default:
      return 'Fire truck and rescue team are dispatched. Help is on the way!';
  }
}

  Future<void> _resolveIncident(String incidentId) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorDialog('You must be signed in to resolve incidents');
      return;
    }

    // Get incident data first to include in notification
    final incidentDoc = await FirebaseFirestore.instance
        .collection('incidents')
        .doc(incidentId)
        .get();
    final incidentData = incidentDoc.data() as Map<String, dynamic>;
    final incidentCategory = _categorizeIncident(incidentData);

    // Update incident status
    await FirebaseFirestore.instance.collection('incidents').doc(incidentId).update({
      'status': 'resolved',
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedBy': user.email ?? 'BFP',
      'isActive': false,
      'resolvedTime': FieldValue.serverTimestamp(),
    });

    // Send notification to user that incident is resolved
    await _sendResponderNotificationToUser(
      incidentId, 
      incidentData, 
      'resolved',
      incidentCategory
    );

    _showSuccessDialog('Incident Resolved', 
        'The emergency has been successfully resolved and marked as completed.');

  } catch (e) {
    print('Error resolving incident: $e');
    _showErrorDialog('Failed to resolve incident: $e');
  }
}

  // Enhanced test method to create sample fire incidents with categories
  Future<void> _createTestIncident() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final testIncidents = [
        {
          'emergencyType': 'Building Fire',
          'userName': 'Test User - Building Fire',
          'contactNumber': '+639123456789',
          'location': {
            'address': '123 Test Street, Victoria, Laguna',
            'coordinates': {
              'latitude': 14.2264,
              'longitude': 121.3252
            }
          },
          'status': 'reported',
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
          'priority': 'high',
          'description': 'Fire in residential building',
          'category': 'Building Fire',
        },
        {
          'emergencyType': 'Vehicle Fire',
          'userName': 'Test User - Car Fire',
          'contactNumber': '+639123456790',
          'location': {
            'address': 'National Highway, Victoria, Laguna',
            'coordinates': {
              'latitude': 14.2150,
              'longitude': 121.3100
            }
          },
          'status': 'active',
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
          'priority': 'high',
          'description': 'Car caught fire on highway',
          'category': 'Vehicle Fire',
          'assignedResponder': 'BFP Team',
        },
        {
          'emergencyType': 'Gas Leak',
          'userName': 'Test User - Gas Emergency',
          'contactNumber': '+639123456791',
          'location': {
            'address': 'Commercial Center, Victoria, Laguna',
            'coordinates': {
              'latitude': 14.2300,
              'longitude': 121.3300
            }
          },
          'status': 'reported',
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
          'priority': 'critical',
          'description': 'Gas leak detected in commercial area',
          'category': 'Gas Leak',
        },
        {
          'emergencyType': 'Rescue Operation',
          'userName': 'Test User - Rescue',
          'contactNumber': '+639123456792',
          'location': {
            'address': 'Office Building, Victoria, Laguna',
            'coordinates': {
              'latitude': 14.2200,
              'longitude': 121.3200
            }
          },
          'status': 'resolved',
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
          'priority': 'medium',
          'description': 'Person trapped in elevator',
          'category': 'Rescue Operation',
          'assignedResponder': 'BFP Rescue Team',
        },
      ];

      for (var incident in testIncidents) {
        await FirebaseFirestore.instance.collection('incidents').add(incident);
      }

      _showSuccessDialog('Test Created', 'Created test incidents with different categories and locations');
    } catch (e) {
      _showErrorDialog('Failed to create test incidents: $e');
    }
  }

  Future<bool> _showConfirmationDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_fire_department, 
                  color: Colors.orange, 
                  size: isSmallScreen ? 20 : 24
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title, 
                  style: TextStyle(
                    color: Color(0xFF2D3436),
                    fontSize: cardTitleFontSize,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            width: screenWidth * 0.8,
            child: Text(
              message, 
              style: TextStyle(
                color: Color(0xFF2D3436),
                fontSize: bodyFontSize,
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12),
                    ),
                    child: Text(
                      'Cancel', 
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: bodyFontSize,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12),
                      ),
                      child: Text(
                        'Confirm', 
                        style: TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.w600,
                          fontSize: bodyFontSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ) ?? false;
  }

  void _showSuccessDialog(String title, String message) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle, 
                color: Colors.green, 
                size: isSmallScreen ? 20 : 24
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title, 
                style: TextStyle(
                  color: Color(0xFF2D3436),
                  fontSize: cardTitleFontSize,
                ),
              ),
            ),
          ],
        ),
        content: Container(
          width: screenWidth * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message, 
                style: TextStyle(
                  color: Color(0xFF2D3436),
                  fontSize: bodyFontSize,
                ),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'User has been notified',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontSize: smallFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green, Colors.green.shade600]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
              ),
              child: Text(
                'OK', 
                style: TextStyle(
                  color: Colors.white, 
                  fontWeight: FontWeight.w600,
                  fontSize: bodyFontSize,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline, 
                  color: Colors.red, 
                  size: isSmallScreen ? 20 : 24
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Error', 
                style: TextStyle(
                  color: Color(0xFF2D3436),
                  fontSize: cardTitleFontSize,
                ),
              ),
            ],
          ),
          content: Container(
            width: screenWidth * 0.8,
            child: Text(
              message, 
              style: TextStyle(
                color: Color(0xFF2D3436),
                fontSize: bodyFontSize,
              ),
            ),
          ),
          actions: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red, Colors.red.shade600]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
                ),
                child: Text(
                  'OK', 
                  style: TextStyle(
                    color: Colors.white, 
                    fontWeight: FontWeight.w600,
                    fontSize: bodyFontSize,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'reported':
        return Colors.orange;
      case 'active':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Get icon for incident category
  IconData _getIncidentIcon(String category) {
    switch (category) {
      case 'Building Fire':
        return Icons.home;
      case 'Vehicle Fire':
        return Icons.directions_car;
      case 'Wildfire/Grass Fire':
        return Icons.forest;
      case 'Gas Leak':
        return Icons.warning;
      case 'Chemical Spill':
        return Icons.science;
      case 'Rescue Operation':
        return Icons.emergency;
      case 'Water Rescue':
        return Icons.water;
      default:
        return Icons.local_fire_department;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown time';
    
    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is String) {
      dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return 'Unknown time';
    }

    Duration difference = DateTime.now().difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Widget _buildIncidentCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final incidentId = doc.id;
    final status = data['status'] ?? 'reported';
    final emergencyType = data['emergencyType'] ?? data['incidents'] ?? data['type'] ?? 'Fire Emergency';
    final userName = data['userName'] ?? data['name'] ?? 'Unknown User';
    final contact = data['contactNumber'] ?? data['contact'] ?? data['phoneNumber'] ?? 'No contact';
    final priority = data['priority'] ?? 'medium';
    
    // Get incident category
    final incidentCategory = data['category'] ?? data['incidentCategory'] ?? _categorizeIncident(data);
    final responseTeam = data['responseTeam'] ?? _getResponseTeamForIncident(incidentCategory);
    
    // Handle location display - more flexible
    String locationText = _getLocationText(data['location']);
    bool hasLocationData = _parseLocation(data['location']) != null;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: cardMargin, 
        vertical: cardMargin / 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Header with status and priority
          Container(
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getStatusColor(status).withOpacity(0.1),
                  _getStatusColor(status).withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIncidentIcon(incidentCategory),
                    color: Colors.orange,
                    size: isSmallScreen ? 20 : 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              incidentCategory.toUpperCase(),
                              style: TextStyle(
                                fontSize: cardTitleFontSize,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3436),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          if (priority == 'critical' || priority == 'high')
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 4 : 6, 
                                vertical: 2
                              ),
                              decoration: BoxDecoration(
                                color: priority == 'critical' ? Colors.red : Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                priority.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 8 : 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text(
                        _formatTimestamp(data['timestamp']),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: smallFontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8 : 12, 
                    vertical: isSmallScreen ? 4 : 6
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 9 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Incident details
          Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              children: [
                // Reporter info
                Row(
                  children: [
                    Icon(
                      Icons.person, 
                      color: Colors.grey[600], 
                      size: isSmallScreen ? 16 : 18
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        userName,
                        style: TextStyle(
                          fontSize: bodyFontSize,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D3436),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                
                // Contact info
                Container(
  padding: EdgeInsets.symmetric(
    horizontal: screenWidth * 0.04,
    vertical: screenHeight * 0.012,
  ),
  decoration: BoxDecoration(
    color: Colors.green.withOpacity(0.07), // change per department
    borderRadius: BorderRadius.circular(screenWidth * 0.03),
    border: Border.all(
      color: Colors.green.withOpacity(0.2),
    ),
  ),
  child: Row(
    children: [
      Icon(
        Icons.phone,
        color: Colors.green,
        size: screenWidth * 0.06,
      ),
      SizedBox(width: screenWidth * 0.03),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Incident Contact',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
                fontSize: screenWidth * 0.035,
              ),
            ),
            Text(
              contact.isNotEmpty ? contact : "No contact",
              style: TextStyle(
                color: const Color(0xFF2D3436),
                fontWeight: FontWeight.bold,
                fontSize: screenWidth * 0.045,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
      if (contact.isNotEmpty && contact != "No contact") 
        Container(
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              Icons.call,
              color: Colors.white,
              size: screenWidth * 0.05,
            ),
            onPressed: () => _makePhoneCallAndroid(contact),
            tooltip: 'Call $contact',
          ),
        ),
    ],
  ),
),
SizedBox(height: screenHeight * 0.015),
                
                // Enhanced Location info with clickable functionality - UPDATED FOR MAPPAGE
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      hasLocationData ? Icons.location_on : Icons.location_off, 
                      color: hasLocationData ? Colors.red[600] : Colors.grey[600], 
                      size: isSmallScreen ? 16 : 18
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: hasLocationData ? () {
                          final coordinates = _parseLocation(data['location']);
                          if (coordinates != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapPage(
                                  incidentLat: coordinates['latitude']!,
                                  incidentLng: coordinates['longitude']!,
                                  incidentType: incidentCategory,
                                  userRole: 'bfp', // Change this based on actual user role
                                  incidentLocationText: locationText,
                                ),
                              ),
                            );
                          } else {
                            // Fallback to old method if coordinates parsing fails
                            _openLocationInMap(data['location'], incidentCategory);
                          }
                        } : null,
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                locationText,
                                style: TextStyle(
                                  fontSize: bodyFontSize,
                                  color: hasLocationData ? Colors.blue[700] : Colors.grey[700],
                                  decoration: hasLocationData ? TextDecoration.underline : null,
                                  fontWeight: hasLocationData ? FontWeight.w600 : FontWeight.normal,
                                ),
                                maxLines: isSmallScreen ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (hasLocationData) ...[
                                SizedBox(height: 4),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isSmallScreen ? 4 : 6, 
                                    vertical: 2
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.map, 
                                        size: isSmallScreen ? 10 : 12, 
                                        color: Colors.blue[700]
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'VIEW MAP',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 8 : 10,
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Response team info
                if (data['responseTeam'] != null || status == 'active') ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.groups, 
                        color: Colors.blue[600], 
                        size: isSmallScreen ? 16 : 18
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Team: $responseTeam',
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                
                // Debug info - Show all data fields (remove this after debugging)
                if (_showDebugInfo)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEBUG INFO:',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.grey[600]
                          ),
                        ),
                        Text(
                          'Category: $incidentCategory | Status: $status | Priority: $priority',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10, 
                            color: Colors.grey[600]
                          ),
                        ),
                        Text(
                          'Is Fire: ${_isFireIncident(data)} | Matches Filter: ${_matchesStatusFilter(data)}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10, 
                            color: Colors.grey[600]
                          ),
                        ),
                        Text(
                          'Has Location: $hasLocationData',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10, 
                            color: Colors.grey[600]
                          ),
                        ),
                        Text(
                          'ID: $incidentId',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 8 : 10, 
                            color: Colors.grey[600]
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                
                if (data['assignedResponder'] != null) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.assignment_ind, 
                        color: Colors.blue[600], 
                        size: isSmallScreen ? 16 : 18
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Assigned to: ${data['assignedResponder']}',
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                
                SizedBox(height: 16),
                
                // Action buttons - responsive layout
                if (status == 'reported') ...[
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          bool confirmed = await _showConfirmationDialog(
                            'Respond to $incidentCategory',
                            'Are you sure you want to respond to this $incidentCategory? ${_getResponseMessage(incidentCategory)}',
                          );
                          if (confirmed) {
                            await _respondToIncident(incidentId, data);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 10 : 12
                          ),
                        ),
                        icon: Icon(
                          _getIncidentIcon(incidentCategory), 
                          color: Colors.white,
                          size: isSmallScreen ? 16 : 20,
                        ),
                        label: Text(
                          'RESPOND',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: bodyFontSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else if (status == 'active') ...[
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green, Colors.green.shade700],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          bool confirmed = await _showConfirmationDialog(
                            'Mark as Resolved',
                            'Are you sure you want to mark this $incidentCategory as resolved? This indicates that the situation has been successfully handled.',
                          );
                          if (confirmed) {
                            await _resolveIncident(incidentId);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 10 : 12
                          ),
                        ),
                        icon: Icon(
                          Icons.check_circle, 
                          color: Colors.white,
                          size: isSmallScreen ? 16 : 20,
                        ),
                        label: Text(
                          'RESOLVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: bodyFontSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: isSmallScreen ? 10 : 12
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle, 
                          color: Colors.green, 
                          size: isSmallScreen ? 16 : 20
                        ),
                        SizedBox(width: 8),
                        Text(
                          'RESOLVED',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: bodyFontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: isSmallScreen ? 50 : 60,
      padding: EdgeInsets.symmetric(vertical: verticalPadding / 2),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        children: [
          _buildFilterChip('all', 'All', Icons.list),
          SizedBox(width: 8),
          _buildFilterChip('reported', 'New', Icons.notification_important),
          SizedBox(width: 8),
          _buildFilterChip('active', 'Active', Icons.local_fire_department),
          SizedBox(width: 8),
          _buildFilterChip('resolved', 'Resolved', Icons.check_circle),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isSmallScreen ? 14 : 16),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: smallFontSize),
          ),
        ],
      ),
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: Colors.orange.withOpacity(0.2),
      checkmarkColor: Colors.orange,
      backgroundColor: Colors.grey[200],
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 4 : 8,
        vertical: isSmallScreen ? 2 : 4,
      ),
    );
  }

  Widget _buildIncidentCategoryStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFireIncidents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final allDocs = snapshot.data!.docs;
        final Map<String, int> categoryStats = {};
        
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (_showAllIncidents || _isFireIncident(data)) {
            final category = data['category'] ?? data['incidentCategory'] ?? _categorizeIncident(data);
            categoryStats[category] = (categoryStats[category] ?? 0) + 1;
          }
        }
        
        if (categoryStats.isEmpty) return SizedBox.shrink();
        
        return Container(
          margin: EdgeInsets.all(cardMargin),
          padding: EdgeInsets.all(horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bar_chart, 
                    color: Colors.orange,
                    size: isSmallScreen ? 18 : 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Incident Categories',
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              ...categoryStats.entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _getIncidentIcon(entry.key), 
                        size: isSmallScreen ? 14 : 16,
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            color: Color(0xFF2D3436),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 6 : 8,
                          vertical: isSmallScreen ? 2 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.all(cardMargin),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
        style: TextStyle(fontSize: bodyFontSize),
        decoration: InputDecoration(
          hintText: 'Search incidents...',
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: bodyFontSize,
          ),
          prefixIcon: Icon(
            Icons.search, 
            color: Colors.grey[400],
            size: isSmallScreen ? 20 : 24,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: Icon(
                    Icons.clear, 
                    color: Colors.grey[400],
                    size: isSmallScreen ? 18 : 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFireIncidents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
                SizedBox(height: 16),
                Text(
                  'Loading incidents...',
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Container(
              margin: EdgeInsets.all(cardMargin),
              padding: EdgeInsets.all(horizontalPadding),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: isSmallScreen ? 40 : 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Error loading incidents',
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      color: Colors.red[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {});
                    },
                    icon: Icon(Icons.refresh, size: isSmallScreen ? 16 : 18),
                    label: Text(
                      'Retry',
                      style: TextStyle(fontSize: bodyFontSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Container(
              margin: EdgeInsets.all(cardMargin),
              padding: EdgeInsets.all(horizontalPadding * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: Colors.grey[400],
                    size: isSmallScreen ? 60 : 80,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No incidents found',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No fire incidents match your current filter.',
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allDocs = snapshot.data!.docs;
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          
          // Filter by fire incidents or show all if debug enabled
          bool isFireRelated = _showAllIncidents || _isFireIncident(data);
          if (!isFireRelated) return false;
          
          // Filter by status
          bool matchesStatus = _matchesStatusFilter(data);
          if (!matchesStatus) return false;
          
          // Filter by search query
          if (_searchQuery.isNotEmpty) {
            final searchableText = [
              data['userName']?.toString() ?? '',
              data['emergencyType']?.toString() ?? '',
              data['category']?.toString() ?? '',
              data['incidentCategory']?.toString() ?? '',
              data['type']?.toString() ?? '',
              data['incidents']?.toString() ?? '',
              data['description']?.toString() ?? '',
              _getLocationText(data['location']),
              _categorizeIncident(data),
            ].join(' ').toLowerCase();
            
            if (!searchableText.contains(_searchQuery)) return false;
          }
          
          return true;
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Container(
              margin: EdgeInsets.all(cardMargin),
              padding: EdgeInsets.all(horizontalPadding * 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    color: Colors.grey[400],
                    size: isSmallScreen ? 60 : 80,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No matching incidents',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _searchQuery.isNotEmpty 
                        ? 'No incidents match your search for "$_searchQuery"'
                        : 'No incidents match your current filter ($_selectedFilter)',
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: Icon(Icons.clear, size: isSmallScreen ? 16 : 18),
                      label: Text(
                        'Clear Search',
                        style: TextStyle(fontSize: bodyFontSize),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // Results count
            Container(
              margin: EdgeInsets.symmetric(horizontal: cardMargin),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding / 2,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: Colors.orange,
                    size: isSmallScreen ? 16 : 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '${filteredDocs.length} incident${filteredDocs.length != 1 ? 's' : ''} found',
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 6 : 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Search: "$_searchQuery"',
                        style: TextStyle(
                          fontSize: smallFontSize,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Incident cards
            ...filteredDocs.map((doc) => _buildIncidentCard(doc)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildStatisticsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top: verticalPadding,
        bottom: verticalPadding * 2,
      ),
      child: Column(
        children: [
          _buildIncidentCategoryStats(),
          _buildStatusStats(),
          _buildPriorityStats(),
          _buildResponseTimeStats(),
        ],
      ),
    );
  }

  Widget _buildStatusStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFireIncidents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final allDocs = snapshot.data!.docs;
        final Map<String, int> statusStats = {'reported': 0, 'active': 0, 'resolved': 0};
        
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (_showAllIncidents || _isFireIncident(data)) {
            final status = (data['status'] ?? 'reported').toString().toLowerCase();
            if (statusStats.containsKey(status)) {
              statusStats[status] = statusStats[status]! + 1;
            }
          }
        }
        
        return Container(
          margin: EdgeInsets.all(cardMargin),
          padding: EdgeInsets.all(horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.pie_chart,
                    color: Colors.blue,
                    size: isSmallScreen ? 18 : 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Status Overview',
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'New Reports',
                      statusStats['reported']!,
                      Colors.orange,
                      Icons.notification_important,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    child: _buildStatCard(
                      'Active',
                      statusStats['active']!,
                      Colors.blue,
                      Icons.local_fire_department,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    child: _buildStatCard(
                      'Resolved',
                      statusStats['resolved']!,
                      Colors.green,
                      Icons.check_circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriorityStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFireIncidents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final allDocs = snapshot.data!.docs;
        final Map<String, int> priorityStats = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
        
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (_showAllIncidents || _isFireIncident(data)) {
            final priority = (data['priority'] ?? 'medium').toString().toLowerCase();
            if (priorityStats.containsKey(priority)) {
              priorityStats[priority] = priorityStats[priority]! + 1;
            }
          }
        }
        
        return Container(
          margin: EdgeInsets.all(cardMargin),
          padding: EdgeInsets.all(horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.priority_high,
                    color: Colors.red,
                    size: isSmallScreen ? 18 : 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Priority Levels',
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              if (isSmallScreen) ...[
                // Stack vertically on small screens
                _buildStatCard(
                  'Critical',
                  priorityStats['critical']!,
                  Colors.red,
                  Icons.warning,
                ),
                SizedBox(height: 8),
                _buildStatCard(
                  'High',
                  priorityStats['high']!,
                  Colors.orange,
                  Icons.error,
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Medium',
                        priorityStats['medium']!,
                        Colors.yellow[700]!,
                        Icons.info,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Low',
                        priorityStats['low']!,
                        Colors.green,
                        Icons.low_priority,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Side by side on larger screens
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Critical',
                        priorityStats['critical']!,
                        Colors.red,
                        Icons.warning,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'High',
                        priorityStats['high']!,
                        Colors.orange,
                        Icons.error,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Medium',
                        priorityStats['medium']!,
                        Colors.yellow[700]!,
                        Icons.info,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Low',
                        priorityStats['low']!,
                        Colors.green,
                        Icons.low_priority,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildResponseTimeStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getFireIncidents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return SizedBox.shrink();
        
        final allDocs = snapshot.data!.docs;
        int totalIncidents = 0;
        int respondedIncidents = 0;
        Duration totalResponseTime = Duration.zero;
        
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (_showAllIncidents || _isFireIncident(data)) {
            totalIncidents++;
            
            if (data['responseTime'] != null && data['timestamp'] != null) {
              respondedIncidents++;
              
              final timestamp = (data['timestamp'] as Timestamp).toDate();
              final responseTime = (data['responseTime'] as Timestamp).toDate();
              final diff = responseTime.difference(timestamp);
              totalResponseTime += diff;
            }
          }
        }
        
        final averageResponseMinutes = respondedIncidents > 0 
            ? totalResponseTime.inMinutes / respondedIncidents
            : 0.0;
        
        return Container(
          margin: EdgeInsets.all(cardMargin),
          padding: EdgeInsets.all(horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Colors.purple,
                    size: isSmallScreen ? 18 : 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Response Metrics',
                    style: TextStyle(
                      fontSize: cardTitleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3436),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total\nIncidents',
                      totalIncidents,
                      Colors.blue,
                      Icons.list,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    child: _buildStatCard(
                      'Response\nRate',
                      totalIncidents > 0 
                          ? ((respondedIncidents / totalIncidents) * 100).round()
                          : 0,
                      Colors.green,
                      Icons.trending_up,
                      suffix: '%',
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    child: _buildStatCard(
                      'Avg Response\nTime',
                      averageResponseMinutes.round(),
                      Colors.orange,
                      Icons.timer,
                      suffix: 'min',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, int value, Color color, IconData icon, {String suffix = ''}) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: isSmallScreen ? 24 : 28,
          ),
          SizedBox(height: 8),
          Text(
            '$value$suffix',
            style: TextStyle(
              fontSize: isSmallScreen ? 18 : 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: isSmallScreen ? 10 : 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(cardMargin),
      child: Column(
        children: [
          // Account Info Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        color: Colors.orange,
                        size: isSmallScreen ? 24 : 32,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account Information',
                            style: TextStyle(
                              fontSize: cardTitleFontSize,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3436),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            FirebaseAuth.instance.currentUser?.email ?? 'No email',
                            style: TextStyle(
                              fontSize: bodyFontSize,
                              color: Colors.grey[600],
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
          
          SizedBox(height: 16),
          
          // Location Settings Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Location Settings',
                      style: TextStyle(
                        fontSize: cardTitleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Location Permission: ${_locationPermissionGranted ? 'Granted' : 'Denied'}',
                        style: TextStyle(
                          fontSize: bodyFontSize,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    Icon(
                      _locationPermissionGranted ? Icons.check_circle : Icons.cancel,
                      color: _locationPermissionGranted ? Colors.green : Colors.red,
                      size: isSmallScreen ? 16 : 18,
                    ),
                  ],
                ),
                if (_currentPosition != null) ...[
                  SizedBox(height: 8),
                  Text(
                    'Current Location: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: smallFontSize,
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _requestLocationPermission,
                    icon: Icon(
                      Icons.refresh,
                      size: isSmallScreen ? 16 : 18,
                    ),
                    label: Text(
                      'Refresh Location',
                      style: TextStyle(fontSize: bodyFontSize),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Debug Settings Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Colors.purple,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Debug Settings',
                      style: TextStyle(
                        fontSize: cardTitleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SwitchListTile(
                  title: Text(
                    'Show Debug Info',
                    style: TextStyle(fontSize: bodyFontSize),
                  ),
                  subtitle: Text(
                    'Display technical information on incident cards',
                    style: TextStyle(fontSize: smallFontSize),
                  ),
                  value: _showDebugInfo,
                  onChanged: (value) {
                    setState(() {
                      _showDebugInfo = value;
                    });
                  },
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: Text(
                    'Show All Incidents',
                    style: TextStyle(fontSize: bodyFontSize),
                  ),
                  subtitle: Text(
                    'Display all incidents, not just fire-related ones',
                    style: TextStyle(fontSize: smallFontSize),
                  ),
                  value: _showAllIncidents,
                  onChanged: (value) {
                    setState(() {
                      _showAllIncidents = value;
                    });
                  },
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Test Actions Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(horizontalPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.science,
                      color: Colors.green,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Test Actions',
                      style: TextStyle(
                        fontSize: cardTitleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _createTestIncident,
                    icon: Icon(
                      Icons.add_box,
                      size: isSmallScreen ? 16 : 18,
                    ),
                    label: Text(
                      'Create Test Incidents',
                      style: TextStyle(fontSize: bodyFontSize),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Logout Card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red, Colors.red.shade700],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: () async {
                bool confirmed = await _showConfirmationDialog(
                  'Logout',
                  'Are you sure you want to logout from the BFP Emergency Response System?',
                );
                if (confirmed) {
                  await _logout();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: isSmallScreen ? 14 : 16,
                ),
              ),
              icon: Icon(
                Icons.logout,
                color: Colors.white,
                size: isSmallScreen ? 18 : 20,
              ),
              label: Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: bodyFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          SizedBox(height: 32),
          
          // App Info
          Container(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              children: [
                Text(
                  'BFP SafeVictoria System',
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: smallFontSize,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      title: Row(
        children: [
          // 🔹 BFP Logo on Left
          Image.asset(
            'assets/images/bfplogo.png',
            height: isSmallScreen ? 28 : 34, // adjust for responsiveness
            width: isSmallScreen ? 28 : 34,
            fit: BoxFit.contain,
          ),
          SizedBox(width: 12),

          // 🔹 Title Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BFP Emergency',
                  style: TextStyle(
                    color: Color(0xFF2D3436),
                    fontSize: headerFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Response System',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: subHeaderFontSize,
                  ),
                ),
              ],
            ),
          ),

          // 🔹 GPS Indicator
          if (_currentPosition != null)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 6 : 8,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.gps_fixed,
                    color: Colors.green,
                    size: isSmallScreen ? 12 : 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'GPS',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: isSmallScreen ? 10 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    

        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          labelStyle: TextStyle(
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: bodyFontSize,
          ),
          tabs: [
            Tab(
              icon: Icon(Icons.list, size: isSmallScreen ? 18 : 20),
              text: 'Incidents',
            ),
            Tab(
              icon: Icon(Icons.analytics, size: isSmallScreen ? 18 : 20),
              text: 'Statistics',
            ),
            Tab(
              icon: Icon(Icons.settings, size: isSmallScreen ? 18 : 20),
              text: 'Settings',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Incidents Tab
          Column(
            children: [
              _buildSearchBar(),
              _buildFilterChips(),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildIncidentsList(),
                ),
              ),
            ],
          ),
          
          // Statistics Tab
          _buildStatisticsTab(),
          
          // Settings Tab
          _buildSettingsTab(),
        ],
      ),
    );
  }
}