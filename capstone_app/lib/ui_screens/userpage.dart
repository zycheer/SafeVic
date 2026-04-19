import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'profile.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Position? _currentPosition;
  bool _isLocationEnabled = false;
  String _userDisplayName = 'User';
  final ImagePicker _picker = ImagePicker();

  final Map<String, Map<String, dynamic>> departments = {
    'Police Department': {
      'icon': Icons.security,
      'color': Color(0xFF90A4AE),
      'incidents': [
        'Theft/Robbery',
        'Assault',
        'Domestic Violence',
        'Drug-related Crime',
        'Vandalism',
        'Fraud/Scam',
        'Public Disturbance',
        'Missing Person',
        'Traffic Accident',
        'Burglary',
        'Fight',
        'Hit and Run',
        'Suspicious Activity',
        'Property Damage'
      ]
    },
    'Fire Department': {
      'icon': Icons.local_fire_department,
      'color': Color(0xFF90A4AE),
      'incidents': [
        'Building Fire',
        'Vehicle Fire',
        'Wildfire/Grass Fire',
        'Gas Leak',
        'Chemical Spill',
        'Electrical Fire',
        'Smoke',
        'Kitchen Fire',
        'Industrial Fire',
        'Forest Fire'
      ]
    },
    'Medical Department': {
      'icon': Icons.medical_services,
      'color': Color(0xFF90A4AE),
      'incidents': [
        'Heart Attack',
        'Stroke',
        'Severe Injury',
        'Road Accident Injury',
        'Difficulty Breathing',
        'Poisoning',
        'Severe Allergic Reaction',
        'Mental Health Crisis',
        'Medical Emergency',
        'Fall',
        'Bleeding',
        'Unconscious Person',
        'Burns',
        'Fracture',
        'Choking',
        'Cardiac Arrest'
      ]
    },
    'Disaster Management': {
      'icon': Icons.warning,
      'color': Color(0xFF90A4AE),
      'incidents': [
        'Flood',
        'Landslide',
        'Earthquake',
        'Typhoon/Storm',
        'Building Collapse',
        'Power Outage',
        'Water System Failure',
        'Tree Fall',
        'Road Damage',
        'Infrastructure Damage',
        'Sinkhole',
        'Bridge Collapse',
        'Dam Failure'
      ]
    },
  };

  String _mapIncidentToValidOption(String aiIncident, List<String> validOptions) {
  final Map<String, String> incidentMap = {
    'Road Accident Injury': 'Road Accident Injury',
    'Severe Injury': 'Severe Injury',
    'Medical Emergency': 'Medical Emergency',
    'Medical Emergency Response': 'Medical Emergency',
    'Fall/Unconscious Person': 'Fall',
    'Traffic Accident': 'Traffic Accident',       // ← keep only once
    'Traffic Incident': 'Traffic Accident',       // ← maps TO Traffic Accident
    'Traffic Accident with Injuries': 'Road Accident Injury',
    'Building Fire': 'Building Fire',
    'Vehicle Fire': 'Vehicle Fire',
    'Wildfire/Grass Fire': 'Wildfire/Grass Fire',
    'Fire': 'Building Fire',
    'Fire Hazard': 'Building Fire',
    'Smoke in Building': 'Smoke',
    'Vehicle Smoke': 'Vehicle Fire',
    'Outdoor Fire': 'Wildfire/Grass Fire',
    'Flood': 'Flood',
    'Severe Flood': 'Flood',
    'Water Accumulation': 'Flood',
    'Landslide': 'Landslide',
    'Mudslide': 'Landslide',
    'Soil Erosion': 'Landslide',
    'Building Collapse': 'Building Collapse',
    'Structural Damage': 'Building Collapse',
    'Storm Damage': 'Typhoon/Storm',
    'Vandalism': 'Vandalism',
    'Property Damage': 'Property Damage',
    'Public Disturbance': 'Public Disturbance',
    'Suspicious Activity': 'Suspicious Activity',
    'Building Issue': 'Property Damage',
    'Public Concern': 'Public Disturbance',
    'Incident Report': 'Suspicious Activity',
  };

  if (validOptions.contains(aiIncident)) return aiIncident;

  // If mapped value exists in validOptions, return it
  final mapped = incidentMap[aiIncident];
  if (mapped != null && validOptions.contains(mapped)) return mapped;

  // Fallback to first valid option
  return validOptions.first;
}

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _loadUserName();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final String displayName =
            (userData['fullName'] as String?)?.trim() ??
                ('${(userData['firstName'] as String?) ?? ''} ${(userData['lastName'] as String?) ?? ''}'
                        .trim()) ??
                user.displayName ??
                'User';
        _safeSetState(() => _userDisplayName = displayName);
      } else {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileSetupPage(isFirstTime: true),
              ),
            );
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user name: $e');
      _safeSetState(() => _userDisplayName = user.displayName ?? 'User');
    }
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showEnableLocationDialog();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDeniedDialog();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showPermissionDeniedForeverDialog();
        return;
      }

      setState(() => _isLocationEnabled = true);
      await _getCurrentLocation();
    } catch (e) {
      print('Error checking location permission: $e');
      setState(() => _isLocationEnabled = false);
    }
  }

  void _showPermissionDeniedDialog() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(size.width * 0.04)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.015),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.location_disabled,
                    color: Colors.red,
                    size: isSmallScreen ? 20 : (isMediumScreen ? 22 : 24)),
              ),
              SizedBox(width: size.width * 0.03),
              Expanded(
                child: Text('Permission Denied',
                    style: TextStyle(
                        color: Color(0xFF2D3436),
                        fontSize:
                            isSmallScreen ? 16 : (isMediumScreen ? 17 : 18),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Text(
            'Location permission is required for emergency reporting. You can try again or enable it manually in app settings.',
            style: TextStyle(
                color: Color(0xFF2D3436),
                fontSize: isSmallScreen ? 13 : (isMediumScreen ? 14 : 15)),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: isSmallScreen ? 42 : 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
                SizedBox(width: size.width * 0.03),
                Expanded(
                  child: Container(
                    height: isSmallScreen ? 42 : 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
                      borderRadius: BorderRadius.circular(size.width * 0.03),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _checkLocationPermission();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Try Again',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showEnableLocationDialog() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(size.width * 0.04)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.015),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.location_off,
                    color: Colors.orange,
                    size: isSmallScreen ? 20 : (isMediumScreen ? 22 : 24)),
              ),
              SizedBox(width: size.width * 0.03),
              Expanded(
                child: Text('Location Services Disabled',
                    style: TextStyle(
                        color: Color(0xFF2D3436),
                        fontSize:
                            isSmallScreen ? 15 : (isMediumScreen ? 16 : 17),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Text(
            'This app needs location services to report emergencies accurately. Please enable location services in your device settings.',
            style: TextStyle(
                color: Color(0xFF2D3436),
                fontSize: isSmallScreen ? 13 : (isMediumScreen ? 14 : 15)),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: isSmallScreen ? 42 : 48,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() => _isLocationEnabled = false);
                      },
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Skip',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
                SizedBox(width: size.width * 0.03),
                Expanded(
                  child: Container(
                    height: isSmallScreen ? 42 : 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
                      borderRadius: BorderRadius.circular(size.width * 0.03),
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await Geolocator.openLocationSettings();
                        Future.delayed(Duration(seconds: 2),
                            () => _checkLocationPermission());
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Open Settings',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDeniedForeverDialog() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(size.width * 0.04)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(size.width * 0.015),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.block,
                    color: Colors.red,
                    size: isSmallScreen ? 20 : (isMediumScreen ? 22 : 24)),
              ),
              SizedBox(width: size.width * 0.03),
              Expanded(
                child: Text('Permission Required',
                    style: TextStyle(
                        color: Color(0xFF2D3436),
                        fontSize:
                            isSmallScreen ? 16 : (isMediumScreen ? 17 : 18),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: Text(
            'Location permission has been permanently denied. Please go to app settings and manually enable location permission for emergency features to work.',
            style: TextStyle(
                color: Color(0xFF2D3436),
                fontSize: isSmallScreen ? 13 : (isMediumScreen ? 14 : 15)),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: isSmallScreen ? 42 : 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Cancel',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
                SizedBox(width: size.width * 0.03),
                Expanded(
                  child: Container(
                    height: isSmallScreen ? 42 : 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
                      borderRadius: BorderRadius.circular(size.width * 0.03),
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openAppSettings();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.03))),
                      child: Text('Open Settings',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 13 : 15)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() => _currentPosition = position);
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  Future<void> _analyzeImageAndReport(File imageFile) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final size = MediaQuery.of(context).size;
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(size.width * 0.04)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF667eea))),
                SizedBox(height: 20),
                Text('Analyzing image with AI...',
                    style: TextStyle(
                        fontSize: size.width < 360 ? 14 : 16,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 10),
                Text('Please wait',
                    style: TextStyle(
                        fontSize: size.width < 360 ? 12 : 14,
                        color: Colors.grey[600])),
              ],
            ),
          );
        },
      );

      List<int> imageBytes = await imageFile.readAsBytes();
      String base64Image = base64Encode(imageBytes);
      Map<String, String> requestBody = {
        'image_data': 'data:image/jpeg;base64,$base64Image',
      };

      print('📸 Sending image for AI analysis (${imageBytes.length} bytes)');

      final response = await http.post(
        Uri.parse(
            'https://unvociferous-microscopic-jamari.ngrok-free.dev/api/analyze_image'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(Duration(seconds: 30));

      if (mounted) Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ AI Analysis Response: $data');

        if (data['success'] == true) {
          final detectedIncident = data['detected_incident'] as String?;
          final department = data['department'] as String?;
          final confidence =
              (data['confidence'] as num?)?.toDouble() ?? 0.5;
          final subcategories =
              List<String>.from(data['subcategories'] ?? []);
          final confidenceLevel =
              data['confidence_level'] as String? ?? 'low';

          if (detectedIncident == null || department == null) {
            throw Exception('Invalid response from AI server');
          }

          await _showEnhancedDetectionResultsDialog(
            imageFile: imageFile,
            detectedIncident: detectedIncident,
            department: department,
            confidence: confidence,
            confidenceLevel: confidenceLevel,
            subcategories: subcategories.isNotEmpty
                ? subcategories
                : _getDefaultSubcategories(department),
          );
        } else {
          _showErrorDialog(
              'AI analysis failed: ${data['error'] ?? "Unknown error"}');
        }
      } else {
        _showErrorDialog(
            'Failed to connect to AI server (Status: ${response.statusCode})');
        await _showManualIncidentSelection(imageFile);
      }
    } on TimeoutException {
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog(
            'AI analysis timed out. Please try again or select manually.');
        await _showManualIncidentSelection(imageFile);
      }
    } catch (e) {
      print('❌ Error analyzing image: $e');
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog(
            'Failed to analyze image. Please select incident type manually.');
        await _showManualIncidentSelection(imageFile);
      }
    }
  }

  Future<void> _showManualIncidentSelection(File imageFile) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(size.width * 0.04)),
          title: Text('Manual Selection',
              style: TextStyle(fontSize: size.width < 360 ? 16 : 18)),
          content: Text(
              'AI analysis failed. Would you like to select the incident type manually?',
              style: TextStyle(fontSize: size.width < 360 ? 13 : 15)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea)),
              child: Text('Select Manually'),
            ),
          ],
        );
      },
    );
    if (result == true) await _showIncidentSelectionDialog(imageFile);
  }

  List<String> _getDefaultSubcategories(String department) {
    for (var dept in departments.keys) {
      if (dept == department) {
        return List<String>.from(departments[dept]!['incidents'] ?? []);
      }
    }
    return [];
  }

  Future<void> _showEnhancedDetectionResultsDialog({
    required File imageFile,
    required String detectedIncident,
    required String department,
    required double confidence,
    required String confidenceLevel,
    required List<String> subcategories,
  }) async {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    String? selectedIncident =
        _mapIncidentToValidOption(detectedIncident, subcategories);
    TextEditingController descriptionController = TextEditingController();

    Color confidenceColor = confidenceLevel == 'high'
        ? Colors.green
        : (confidenceLevel == 'medium' ? Colors.orange : Colors.red);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size.width * 0.04)),
              title: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: Colors.blue,
                      size: isSmallScreen ? 20 : 24),
                  SizedBox(width: size.width * 0.02),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Detection Results',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallScreen
                                    ? 16
                                    : (isMediumScreen ? 17 : 18))),
                        Row(
                          children: [
                            Icon(Icons.shield,
                                color: confidenceColor, size: 14),
                            SizedBox(width: 4),
                            Text(
                                '${(confidence * 100).toStringAsFixed(1)}% confidence',
                                style: TextStyle(
                                    fontSize: isSmallScreen ? 11 : 13,
                                    color: confidenceColor,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: size.height * 0.15,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(size.width * 0.03),
                        image: DecorationImage(
                            image: FileImage(imageFile),
                            fit: BoxFit.cover),
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    Container(
                      padding: EdgeInsets.all(size.width * 0.03),
                      decoration: BoxDecoration(
                        color: confidenceColor.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(size.width * 0.02),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Confidence Level:',
                                  style: TextStyle(
                                      fontSize: isSmallScreen ? 12 : 14,
                                      fontWeight: FontWeight.w500)),
                              Text(confidenceLevel.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: isSmallScreen ? 12 : 14,
                                      fontWeight: FontWeight.bold,
                                      color: confidenceColor)),
                            ],
                          ),
                          SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: confidence,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  confidenceColor),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    Container(
                      padding: EdgeInsets.all(size.width * 0.04),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(size.width * 0.03),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified,
                                  color: Colors.green,
                                  size: isSmallScreen ? 18 : 20),
                              SizedBox(width: size.width * 0.02),
                              Expanded(
                                child: Text(
                                    'AI Detected: $detectedIncident',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize:
                                            isSmallScreen ? 13 : 15)),
                              ),
                            ],
                          ),
                          SizedBox(height: size.height * 0.01),
                          Row(
                            children: [
                              Icon(
                                  departments[department]!['icon']
                                      as IconData,
                                  color: departments[department]!['color'],
                                  size: isSmallScreen ? 16 : 18),
                              SizedBox(width: size.width * 0.02),
                              Expanded(
                                child: Text('Department: $department',
                                    style: TextStyle(
                                        fontSize:
                                            isSmallScreen ? 12 : 14)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    Text('Verify or correct the detection:',
                        style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: size.height * 0.01),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.04),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius:
                            BorderRadius.circular(size.width * 0.03),
                      ),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedIncident,
                        underline: SizedBox(),
                        style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 15,
                            color: Colors.black87),
                        onChanged: (value) =>
                            setState(() => selectedIncident = value),
                        items: subcategories
                            .map((incident) => DropdownMenuItem(
                                value: incident, child: Text(incident)))
                            .toList(),
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    Text('Description (Optional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: isSmallScreen ? 12 : 14)),
                    SizedBox(height: size.height * 0.01),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      style:
                          TextStyle(fontSize: isSmallScreen ? 13 : 15),
                      decoration: InputDecoration(
                        hintText: 'Add any additional details...',
                        hintStyle: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                size.width * 0.03)),
                        contentPadding:
                            EdgeInsets.all(size.width * 0.03),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: isSmallScreen ? 42 : 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey)),
                          child: Text('Cancel',
                              style: TextStyle(
                                  fontSize: isSmallScreen ? 13 : 15)),
                        ),
                      ),
                    ),
                    SizedBox(width: size.width * 0.03),
                    Expanded(
                      child: Container(
                        height: isSmallScreen ? 42 : 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Colors.red, Colors.red.shade700]),
                          borderRadius:
                              BorderRadius.circular(size.width * 0.03),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _processEmergencyReport(
                              imageFile: imageFile,
                              department: department,
                              incidentType: selectedIncident!,
                              description:
                                  descriptionController.text.trim(),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent),
                          child: Text('Confirm',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 13 : 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showIncidentSelectionDialog(File imageFile) async {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    String? selectedDepartment;
    String? selectedIncident;
    TextEditingController descriptionController = TextEditingController();

    final Map<String, List<String>> groupedIncidents = {};
    for (var deptEntry in departments.entries) {
      groupedIncidents[deptEntry.key] =
          deptEntry.value['incidents'] as List<String>;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size.width * 0.04)),
              title: Row(
                children: [
                  Icon(Icons.photo_camera,
                      color: Colors.blue,
                      size: isSmallScreen ? 20 : 24),
                  SizedBox(width: size.width * 0.03),
                  Expanded(
                    child: Text('Report Emergency',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen
                                ? 16
                                : (isMediumScreen ? 17 : 18))),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: size.height * 0.15,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(size.width * 0.03),
                        image: DecorationImage(
                            image: FileImage(imageFile),
                            fit: BoxFit.cover),
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    Text('Select Department',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: isSmallScreen ? 12 : 14)),
                    SizedBox(height: size.height * 0.01),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.04),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius:
                            BorderRadius.circular(size.width * 0.03),
                      ),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: Text('Choose department',
                            style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14)),
                        value: selectedDepartment,
                        underline: SizedBox(),
                        style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 15,
                            color: Colors.black87),
                        onChanged: (value) => setState(() {
                          selectedDepartment = value;
                          selectedIncident = null;
                        }),
                        items: departments.keys
                            .map((department) => DropdownMenuItem(
                                  value: department,
                                  child: Row(
                                    children: [
                                      Icon(
                                          departments[department]!['icon']
                                              as IconData,
                                          color: departments[department]![
                                              'color'] as Color,
                                          size: isSmallScreen ? 16 : 18),
                                      SizedBox(width: size.width * 0.03),
                                      Expanded(
                                          child: Text(department,
                                              style: TextStyle(
                                                  fontSize: isSmallScreen
                                                      ? 12
                                                      : 14))),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    SizedBox(height: size.height * 0.02),
                    if (selectedDepartment != null) ...[
                      Text('Select Incident Type',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: isSmallScreen ? 12 : 14)),
                      SizedBox(height: size.height * 0.01),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: size.width * 0.04),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius:
                              BorderRadius.circular(size.width * 0.03),
                        ),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: Text('Choose incident type',
                              style: TextStyle(
                                  fontSize: isSmallScreen ? 12 : 14)),
                          value: selectedIncident,
                          underline: SizedBox(),
                          style: TextStyle(
                              fontSize: isSmallScreen ? 13 : 15,
                              color: Colors.black87),
                          onChanged: (value) =>
                              setState(() => selectedIncident = value),
                          items: groupedIncidents[selectedDepartment!]!
                              .map((incident) => DropdownMenuItem(
                                  value: incident,
                                  child: Text(incident,
                                      style: TextStyle(
                                          fontSize:
                                              isSmallScreen ? 12 : 14))))
                              .toList(),
                        ),
                      ),
                    ],
                    SizedBox(height: size.height * 0.02),
                    Text('Description (Optional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: isSmallScreen ? 12 : 14)),
                    SizedBox(height: size.height * 0.01),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      style:
                          TextStyle(fontSize: isSmallScreen ? 13 : 15),
                      decoration: InputDecoration(
                        hintText: 'Add any additional details...',
                        hintStyle: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                size.width * 0.03)),
                        contentPadding:
                            EdgeInsets.all(size.width * 0.03),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: isSmallScreen ? 42 : 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Cancel',
                              style: TextStyle(
                                  fontSize: isSmallScreen ? 13 : 15)),
                        ),
                      ),
                    ),
                    SizedBox(width: size.width * 0.03),
                    Expanded(
                      child: Container(
                        height: isSmallScreen ? 42 : 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Colors.red, Colors.red.shade700]),
                          borderRadius:
                              BorderRadius.circular(size.width * 0.03),
                        ),
                        child: ElevatedButton(
                          onPressed: selectedDepartment != null &&
                                  selectedIncident != null
                              ? () {
                                  Navigator.of(context).pop();
                                  _processEmergencyReport(
                                    imageFile: imageFile,
                                    department: selectedDepartment!,
                                    incidentType: selectedIncident!,
                                    description:
                                        descriptionController.text.trim(),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor:
                                  Colors.grey.withOpacity(0.3)),
                          child: Text('Report',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 13 : 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processEmergencyReport({
    required File imageFile,
    required String department,
    required String incidentType,
    required String description,
  }) async {
    if (!_isLocationEnabled || _currentPosition == null) {
      bool shouldEnableLocation = await _showLocationRequiredDialog();
      if (shouldEnableLocation) {
        await _checkLocationPermission();
        return;
      } else {
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncidentProcessingPage(
          imageFile: imageFile,
          department: department,
          incidentType: incidentType,
          description: description,
          currentPosition: _currentPosition!,
        ),
      ),
    );
  }

  Future<void> _reportEmergency() async {
    if (!_isLocationEnabled || _currentPosition == null) {
      bool shouldEnableLocation = await _showLocationRequiredDialog();
      if (shouldEnableLocation) {
        await _checkLocationPermission();
        return;
      } else {
        return;
      }
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (image != null) await _analyzeImageAndReport(File(image.path));
    } catch (e) {
      print('Error taking photo: $e');
      _showErrorDialog('Failed to capture photo. Please try again.');
    }
  }

  Widget _buildEmergencyButton() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    return Container(
      width: double.infinity,
      height: isSmallScreen ? size.height * 0.12 : size.height * 0.15,
      margin: EdgeInsets.symmetric(
          horizontal: size.width * 0.05, vertical: size.height * 0.02),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.red, Colors.red.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size.width * 0.05),
        boxShadow: [
          BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 15,
              offset: Offset(0, 5))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _reportEmergency,
          borderRadius: BorderRadius.circular(size.width * 0.05),
          child: Container(
            padding: EdgeInsets.all(size.width * 0.04),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emergency,
                    color: Colors.white,
                    size: isSmallScreen
                        ? size.width * 0.10
                        : size.width * 0.12),
                SizedBox(height: size.height * 0.008),
                Text('REPORT EMERGENCY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize:
                            isSmallScreen ? 16 : (isMediumScreen ? 18 : 20),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2)),
                SizedBox(height: size.height * 0.003),
                Text('Take photo of incident',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize:
                            isSmallScreen ? 11 : (isMediumScreen ? 12 : 14),
                        color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showLocationRequiredDialog() async {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size.width * 0.04)),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(size.width * 0.015),
                    decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: Icon(Icons.location_on,
                        color: Colors.orange,
                        size: isSmallScreen ? 20 : 24),
                  ),
                  SizedBox(width: size.width * 0.03),
                  Expanded(
                    child: Text('Location Required',
                        style: TextStyle(
                            color: Color(0xFF2D3436),
                            fontSize: isSmallScreen ? 16 : 18)),
                  ),
                ],
              ),
              content: Text(
                'Emergency reporting requires your location to send help to the right place. Would you like to enable location services now?',
                style: TextStyle(
                    color: Color(0xFF2D3436),
                    fontSize: isSmallScreen ? 13 : 15),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: isSmallScreen ? 42 : 48,
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Color(0xFF667eea)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      size.width * 0.03))),
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: Color(0xFF667eea),
                                  fontSize: isSmallScreen ? 13 : 15)),
                        ),
                      ),
                    ),
                    SizedBox(width: size.width * 0.03),
                    Expanded(
                      child: Container(
                        height: isSmallScreen ? 42 : 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [
                                Color(0xFF667eea),
                                Color(0xFF764ba2)
                              ]),
                          borderRadius:
                              BorderRadius.circular(size.width * 0.03),
                        ),
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      size.width * 0.03))),
                          child: Text('Enable',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 13 : 15)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showErrorDialog(String message) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size.width * 0.04)),
        title: Row(
          children: [
            Icon(Icons.error_outline,
                color: Colors.red, size: isSmallScreen ? 20 : 24),
            SizedBox(width: size.width * 0.03),
            Text('Error',
                style: TextStyle(fontSize: isSmallScreen ? 16 : 18)),
          ],
        ),
        content: Text(message,
            style: TextStyle(fontSize: isSmallScreen ? 13 : 15)),
        actions: [
          SizedBox(
            width: double.infinity,
            height: isSmallScreen ? 42 : 48,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea)),
              child: Text('OK',
                  style: TextStyle(fontSize: isSmallScreen ? 13 : 15)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;
    final isMediumScreen = size.width >= 360 && size.width < 400;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              IgnorePointer(
                child: Stack(
                  children: [
                    Positioned(
                      top: 40,
                      left: 16,
                      child: Transform.rotate(
                          angle: -0.2,
                          child: Icon(Icons.eco,
                              size: isSmallScreen ? 60 : 72,
                              color: Colors.white.withOpacity(0.09))),
                    ),
                    Positioned(
                      top: 140,
                      right: 32,
                      child: Transform.rotate(
                          angle: 0.15,
                          child: Icon(Icons.grass,
                              size: isSmallScreen ? 50 : 60,
                              color: Colors.white.withOpacity(0.10))),
                    ),
                    Positioned(
                      bottom: 120,
                      left: 48,
                      child: Transform.rotate(
                          angle: -0.1,
                          child: Icon(Icons.eco,
                              size: isSmallScreen ? 75 : 90,
                              color: Colors.white.withOpacity(0.06))),
                    ),
                    Positioned(
                      bottom: 40,
                      right: 20,
                      child: Transform.rotate(
                          angle: 0.05,
                          child: Icon(Icons.grass,
                              size: isSmallScreen ? 58 : 68,
                              color: Colors.white.withOpacity(0.08))),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  // App Bar
                  Container(
                    height: isSmallScreen
                        ? size.height * 0.07
                        : size.height * 0.08,
                    padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.05,
                        vertical: isSmallScreen
                            ? size.height * 0.015
                            : size.height * 0.02),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Image.asset('assets/images/viclogo.png',
                                  height: isSmallScreen
                                      ? 32
                                      : (isMediumScreen ? 36 : 40),
                                  width: isSmallScreen
                                      ? 32
                                      : (isMediumScreen ? 36 : 40),
                                  fit: BoxFit.contain),
                              SizedBox(width: size.width * 0.02),
                              Flexible(
                                child: Text('SafeVictoria',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: isSmallScreen
                                            ? 18
                                            : (isMediumScreen ? 20 : 22),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: isSmallScreen ? 40 : 48,
                          height: isSmallScreen ? 40 : 48,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                            iconSize: isSmallScreen ? 22 : 26,
                            icon: Icon(Icons.account_circle,
                                color: Colors.white),
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        UserProfileSetupPage(
                                            isFirstTime: false)),
                              );
                              if (result == true) _loadUserName();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Header card
                          Container(
                            margin: EdgeInsets.symmetric(
                                horizontal: size.width * 0.05),
                            padding: EdgeInsets.all(isSmallScreen
                                ? size.width * 0.05
                                : size.width * 0.06),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.05),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1),
                            ),
                            child: Column(
                              children: [
                                Image.asset('assets/images/logo.png',
                                    width: isSmallScreen
                                        ? size.width * 0.20
                                        : size.width * 0.25,
                                    height: isSmallScreen
                                        ? size.width * 0.20
                                        : size.width * 0.25,
                                    fit: BoxFit.contain),
                                SizedBox(height: size.height * 0.02),
                                Text('Welcome back,',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: isSmallScreen
                                            ? 13
                                            : (isMediumScreen ? 14 : 15))),
                                Text(_userDisplayName,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isSmallScreen
                                            ? 20
                                            : (isMediumScreen ? 22 : 24),
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: size.height * 0.02),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: size.width * 0.04,
                                      vertical: size.height * 0.01),
                                  decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(
                                          size.width * 0.05)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          _isLocationEnabled
                                              ? Icons.location_on
                                              : Icons.location_off,
                                          color: Colors.white,
                                          size: isSmallScreen ? 14 : 16),
                                      SizedBox(width: size.width * 0.015),
                                      Flexible(
                                        child: Text(
                                            _isLocationEnabled &&
                                                    _currentPosition != null
                                                ? 'Victoria, Laguna'
                                                : 'Location Disabled',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    isSmallScreen ? 11 : 13,
                                                fontWeight:
                                                    FontWeight.w500)),
                                      ),
                                      if (!_isLocationEnabled) ...[
                                        SizedBox(width: size.width * 0.02),
                                        GestureDetector(
                                          onTap: () =>
                                              _checkLocationPermission(),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: size.width * 0.02,
                                                vertical:
                                                    size.height * 0.002),
                                            decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.3),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        size.width * 0.025)),
                                            child: Text('Enable',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize:
                                                        isSmallScreen ? 10 : 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_isLocationEnabled &&
                                    _currentPosition != null) ...[
                                  SizedBox(height: size.height * 0.008),
                                  Text(
                                      '${_currentPosition!.latitude.toStringAsFixed(4)}°N, ${_currentPosition!.longitude.toStringAsFixed(4)}°E',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: isSmallScreen ? 10 : 12)),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(height: size.height * 0.03),
                          _buildEmergencyButton(),
                          // Instructions card
                          Container(
                            margin: EdgeInsets.symmetric(
                                horizontal: size.width * 0.05),
                            padding: EdgeInsets.all(isSmallScreen
                                ? size.width * 0.05
                                : size.width * 0.06),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(size.width * 0.05),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: Offset(0, 10))
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('How to Report an Emergency',
                                    style: TextStyle(
                                        fontSize: isSmallScreen
                                            ? 18
                                            : (isMediumScreen ? 20 : 22),
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2D3436))),
                                SizedBox(height: size.height * 0.02),
                                _buildInstructionStep(
                                    icon: Icons.camera_alt,
                                    text:
                                        'Take a clear photo of the incident',
                                    color: Colors.blue,
                                    size: size,
                                    isSmallScreen: isSmallScreen),
                                SizedBox(height: size.height * 0.01),
                                _buildInstructionStep(
                                    icon: Icons.analytics,
                                    text:
                                        'AI will analyze and suggest incident type',
                                    color: Colors.green,
                                    size: size,
                                    isSmallScreen: isSmallScreen),
                                SizedBox(height: size.height * 0.01),
                                _buildInstructionStep(
                                    icon: Icons.send,
                                    text: 'Verify details and submit report',
                                    color: Colors.red,
                                    size: size,
                                    isSmallScreen: isSmallScreen),
                              ],
                            ),
                          ),
                          SizedBox(height: size.height * 0.05),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep({
    required IconData icon,
    required String text,
    required Color color,
    required Size size,
    required bool isSmallScreen,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(size.width * 0.02),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), shape: BoxShape.circle),
          child:
              Icon(icon, color: color, size: isSmallScreen ? 18 : 20),
        ),
        SizedBox(width: size.width * 0.03),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Color(0xFF2D3436))),
        ),
      ],
    );
  }
}

// ============================================================
// INCIDENT PROCESSING PAGE
// ============================================================
class IncidentProcessingPage extends StatefulWidget {
  final File imageFile;
  final String department;
  final String incidentType;
  final String description;
  final Position currentPosition;

  const IncidentProcessingPage({
    Key? key,
    required this.imageFile,
    required this.department,
    required this.incidentType,
    required this.description,
    required this.currentPosition,
  }) : super(key: key);

  @override
  _IncidentProcessingPageState createState() =>
      _IncidentProcessingPageState();
}

class _IncidentProcessingPageState extends State<IncidentProcessingPage> {
  bool isUploading = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // 1. INITIALIZE LOCAL NOTIFICATIONS
  // ─────────────────────────────────────────────────────────
  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin
        .initialize(const InitializationSettings(android: android));
  }

  // ─────────────────────────────────────────────────────────
  // 2. SUBMIT INCIDENT
  // ─────────────────────────────────────────────────────────
  Future<void> _submitIncident() async {
    setState(() => isUploading = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Text('Processing Incident'),
        ]),
        content: Text('Uploading details and photo...'),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'User not authenticated';

      // Fetch user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String userFirstName = 'User';
      String userLastName = '';
      String userContact = 'N/A';

      if (userDoc.exists) {
        final d = userDoc.data() as Map<String, dynamic>;
        userFirstName = d['firstName'] ?? d['fname'] ?? 'User';
        userLastName  = d['lastName']  ?? d['lname'] ?? '';
        userContact   = d['phoneNumber'] ?? d['contact'] ??
                        d['phone'] ?? user.phoneNumber ?? 'N/A';
      }

      // Create incident document
      final docRef =
          await FirebaseFirestore.instance.collection('incidents').add({
        'userId':       user.uid,
        'userName':     user.displayName ?? '$userFirstName $userLastName',
        'userEmail':    user.email,
        'fname':        userFirstName,
        'lname':        userLastName,
        'contact':      userContact,
        'department':   widget.department,
        'incidentType': widget.incidentType,
        'incidents':    widget.incidentType,
        'description':  widget.description,
        'status':       'reported',
        'timestamp':    FieldValue.serverTimestamp(),
        'location': {
          'latitude':  widget.currentPosition.latitude,
          'longitude': widget.currentPosition.longitude,
          'address': 'Victoria, Laguna '
              '(${widget.currentPosition.latitude.toStringAsFixed(4)}°N, '
              '${widget.currentPosition.longitude.toStringAsFixed(4)}°E)',
        },
        'isActive':  true,
        'archived':  false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Incident created: ${docRef.id}');

      // Upload photo
      final photoUrl =
          await _uploadImageWithDocId(docRef.id, widget.imageFile);
      if (photoUrl != null) {
        await docRef.update({'photoUrl': photoUrl});
        print('✅ Photo uploaded: $photoUrl');
      }

      // ── SEND ALL NOTIFICATIONS ────────────────────────────
      await _sendAllNotifications(
        incidentId:  docRef.id,
        userName:    '$userFirstName $userLastName',
        userEmail:   user.email ?? 'N/A',
        userContact: userContact,
        photoUrl:    photoUrl,
      );
      // ─────────────────────────────────────────────────────

      if (mounted) Navigator.of(context).pop();
      setState(() => isUploading = false);
      _showSuccessDialog(docRef.id);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => isUploading = false);
      print('❌ Error: $e');
      _showErrorDialog('Failed to report emergency. Please try again.');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 3. MASTER NOTIFICATION DISPATCHER
  //    Routes to the correct agencies based on department
  // ─────────────────────────────────────────────────────────
  Future<void> _sendAllNotifications({
    required String incidentId,
    required String userName,
    required String userEmail,
    required String userContact,
    String? photoUrl,
  }) async {
    // Department → agency role mapping
    // 'role' must match the value stored in Firestore users collection
    const Map<String, List<String>> departmentToRoles = {
      'Police Department':   ['pnp'],
      'Fire Department':     ['bfp'],
      'Medical Department':  ['pnp', 'bfp'], // both agencies respond
      'Disaster Management': ['mdrrmo'],
    };

    final List<String> targetRoles =
        departmentToRoles[widget.department] ?? ['pnp'];

    print('📢 ${widget.department} → notifying: $targetRoles');

    // Layer 1 – Firestore in-app notifications
    await _sendFirestoreNotificationsToResponders(
      incidentId:  incidentId,
      targetRoles: targetRoles,
      photoUrl:    photoUrl,
    );

    // Layer 2 – Flask/FCM push to responder devices
    await _sendFlaskPushNotification(
      incidentId:  incidentId,
      targetRoles: targetRoles,
      userName:    userName,
      userEmail:   userEmail,
      userContact: userContact,
      photoUrl:    photoUrl,
    );

    // Layer 3 – Local confirmation on citizen's device
    await _showLocalDeviceNotification();
  }

  // ─────────────────────────────────────────────────────────
  // 4. FIRESTORE IN-APP NOTIFICATIONS
  //    Writes to each responder's notifications sub-collection
  // ─────────────────────────────────────────────────────────
  Future<void> _sendFirestoreNotificationsToResponders({
    required String incidentId,
    required List<String> targetRoles,
    String? photoUrl,
  }) async {
    try {
      for (final role in targetRoles) {
        final responderQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: role)
            .get();

        if (responderQuery.docs.isEmpty) {
          print('⚠️ No users with role: $role');
          continue;
        }

        for (final responderDoc in responderQuery.docs) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(responderDoc.id)
              .collection('notifications')
              .add({
            'incidentId':   incidentId,
            'title':        _getNotificationTitle(role),
            'message':      _getNotificationMessage(),
            'type':         'incident',
            'department':   widget.department,
            'incidentType': widget.incidentType,
            'photoUrl':     photoUrl,
            'timestamp':    FieldValue.serverTimestamp(),
            'read':         false,
          });

          print('✅ Firestore notification → '
              '${role.toUpperCase()}: '
              '${responderDoc.data()['email'] ?? responderDoc.id}');
        }
      }
    } catch (e) {
      print('❌ Firestore notification error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 5. FLASK / FCM PUSH NOTIFICATION
  //    Sends targetRoles to backend so it knows which
  //    agency devices to push to
  // ─────────────────────────────────────────────────────────
  Future<void> _sendFlaskPushNotification({
    required String incidentId,
    required List<String> targetRoles,
    required String userName,
    required String userEmail,
    required String userContact,
    String? photoUrl,
  }) async {
    const String flaskUrl =
        'https://unvociferous-microscopic-jamari.ngrok-free.dev/api/report_incident';

    try {
      final payload = {
        'incidentId':    incidentId,
        'emergencyType': widget.incidentType,
        'department':    widget.department,
        'targetRoles':   targetRoles,
        'userName':      userName,
        'userEmail':     userEmail,
        'contactNumber': userContact,
        'location': {
          'latitude':    widget.currentPosition.latitude,
          'longitude':   widget.currentPosition.longitude,
          'coordinates': '${widget.currentPosition.latitude.toStringAsFixed(4)}°N, '
              '${widget.currentPosition.longitude.toStringAsFixed(4)}°E',
          'address': 'Victoria, Laguna',
        },
        'description': widget.description.isNotEmpty
            ? widget.description
            : 'Emergency reported via mobile app',
        'priority': _getPriorityLevel(widget.incidentType),
        'photoUrl': photoUrl,
      };

      print('📡 Sending to Flask → roles: $targetRoles');

      final response = await http
          .post(Uri.parse(flaskUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(payload))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print('✅ Flask push sent to: $targetRoles');
          SystemSound.play(SystemSoundType.alert);
        } else {
          print('⚠️ Flask success=false: ${responseData['error']}');
        }
      } else {
        print('⚠️ Flask status: ${response.statusCode}');
      }
    } on TimeoutException {
      print('⚠️ Flask timeout (non-critical)');
    } catch (e) {
      print('⚠️ Flask error (non-critical): $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 6. LOCAL DEVICE NOTIFICATION (citizen confirmation)
  // ─────────────────────────────────────────────────────────
  Future<void> _showLocalDeviceNotification() async {
    try {
      await _notificationsPlugin.show(
        0,
        'Emergency Reported Successfully',
        '${widget.incidentType} reported to ${widget.department}. '
            'Responders have been notified.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_channel',
            'Emergency Notifications',
            channelDescription: 'Notifications for emergency incidents',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
      print('✅ Local notification shown');
    } catch (e) {
      print('⚠️ Local notification error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // 7. HELPERS
  // ─────────────────────────────────────────────────────────
  String _getNotificationTitle(String role) {
    switch (role) {
      case 'bfp':    return '🔥 BFP – New Fire Incident';
      case 'pnp':    return '🚔 PNP – New Incident Report';
      case 'mdrrmo': return '⚠️ MDRRMO – Disaster Alert';
      default:       return '🚨 New Emergency Report';
    }
  }

  String _getNotificationMessage() =>
      '${widget.incidentType} reported in Victoria, Laguna. '
      'Tap to view details.';

  String _getPriorityLevel(String emergencyType) {
    const critical = [
      'Severe Allergic Reaction', 'Mental Health Crisis',
      'Wildfire/Grass Fire', 'Typhoon/Storm',
      'Cardiac Arrest', 'Choking',
    ];
    const high = [
      'Heart Attack', 'Stroke', 'Severe Injury', 'Road Accident Injury',
      'Difficulty Breathing', 'Poisoning', 'Building Fire', 'Vehicle Fire',
      'Gas Leak', 'Chemical Spill', 'Assault', 'Domestic Violence',
      'Robbery', 'Flood', 'Landslide', 'Earthquake', 'Building Collapse',
      'Bleeding', 'Unconscious Person', 'Burns', 'Fracture',
    ];
    if (critical.contains(emergencyType)) return 'critical';
    if (high.contains(emergencyType))     return 'high';
    return 'medium';
  }

  Future<String?> _uploadImageWithDocId(
      String incidentId, File imageFile) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('incident_photos')
          .child(user.uid)
          .child(incidentId)
          .child(fileName);

      final snapshot = await storageRef.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploadedBy': user.uid,
            'incidentId': incidentId,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('❌ Image upload error: $e');
      return null;
    }
  }

  void _showSuccessDialog(String incidentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 28),
          SizedBox(width: 12),
          Text('Success!'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your emergency report has been submitted successfully.'),
            SizedBox(height: 12),
            Text('Incident ID: $incidentId',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            SizedBox(height: 8),
            Text(
                'Emergency responders have been notified and will respond shortly.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.error_outline, color: Colors.red, size: 28),
          SizedBox(width: 12),
          Text('Error'),
        ]),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360;

    return Scaffold(
      backgroundColor: Color(0xFF355E3B),
      appBar: AppBar(
        title: Text('Review & Submit'),
        backgroundColor: Color(0xFF355E3B),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(size.width * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image preview
              Container(
                width: double.infinity,
                height: size.height * 0.25,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(widget.imageFile, fit: BoxFit.cover),
                ),
              ),
              SizedBox(height: size.height * 0.03),
              _buildDetailCard(
                  icon: Icons.business,
                  title: 'Department',
                  value: widget.department),
              _buildDetailCard(
                  icon: Icons.warning,
                  title: 'Incident Type',
                  value: widget.incidentType),
              if (widget.description.isNotEmpty)
                _buildDetailCard(
                    icon: Icons.description,
                    title: 'Description',
                    value: widget.description),
              _buildDetailCard(
                icon: Icons.location_on,
                title: 'Location',
                value: 'Lat: ${widget.currentPosition.latitude.toStringAsFixed(4)}, '
                    'Lng: ${widget.currentPosition.longitude.toStringAsFixed(4)}',
              ),
              SizedBox(height: size.height * 0.04),
              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: isUploading ? null : _submitIncident,
                  icon: Icon(Icons.send),
                  label: Text(
                    isUploading ? 'Submitting...' : 'Submit Report',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}