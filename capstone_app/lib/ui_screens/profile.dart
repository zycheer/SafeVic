import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'pnppage.dart';
import 'bfppage.dart';
import 'mdrrmopage.dart';
import 'userpage.dart';

class UserProfileSetupPage extends StatefulWidget {
  final bool isFirstTime;

  const UserProfileSetupPage({Key? key, required this.isFirstTime}) : super(key: key);

  @override
  _UserProfileSetupPageState createState() => _UserProfileSetupPageState();
}

class _UserProfileSetupPageState extends State<UserProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Form controllers
  final _firstNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  
  // Form state
  String _selectedGender = 'Male';
  String? _selectedProvince;
  String? _selectedMunicipality;
  String? _selectedBarangay;
  List<dynamic> _provinces = [];
  List<dynamic> _municipalities = [];
  List<dynamic> _barangays = [];
  
  String _errorMessage = '';
  bool _isLoading = false;
  bool _isLoadingProvinces = false;
  bool _isLoadingMunicipalities = false;
  bool _isLoadingBarangays = false;
  bool _isEditing = false;
  bool _isUpdating = false;
  
  // Store original data for comparison
  Map<String, dynamic> _originalData = {};

  @override
  void initState() {
    super.initState();
    _loadProvinces();
    _loadUserProfile();
  }

  // Load user profile from Firestore
  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        _originalData = Map<String, dynamic>.from(userData);
        
        setState(() {
          _firstNameController.text = userData['firstName'] ?? '';
          _middleInitialController.text = userData['middleInitial'] ?? '';
          _lastNameController.text = userData['lastName'] ?? '';
          _phoneController.text = userData['phoneNumber'] ?? '';
          _selectedGender = userData['gender'] ?? 'Male';
          
          // Address information
          if (userData['address'] != null) {
            Map<String, dynamic> address = userData['address'];
            _streetController.text = address['street'] ?? '';
            _selectedProvince = address['provinceCode'];
            _selectedMunicipality = address['municipalityCode'];
            _selectedBarangay = address['barangayCode'];
            
            // Load municipalities and barangays if codes exist
            if (_selectedProvince != null) {
              _loadMunicipalities(_selectedProvince!).then((_) {
                if (_selectedMunicipality != null) {
                  _loadBarangays(_selectedMunicipality!);
                }
              });
            }
          }
        });
      }
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() {
        _errorMessage = 'Failed to load profile data';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ✅ Consolidated save/update profile function
  Future<void> _saveUserProfile() async {
  if (!_formKey.currentState!.validate()) return;

  // Validate required fields
  if (_selectedProvince == null || _selectedMunicipality == null || _selectedBarangay == null) {
    setState(() {
      _errorMessage = 'Please select province, municipality, and barangay';
    });
    return;
  }

  setState(() {
    _errorMessage = '';
    _isUpdating = true;
  });

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get province, municipality, and barangay names
    final selectedProvince = _provinces.firstWhere(
      (province) => province['code'] == _selectedProvince,
      orElse: () => {'name': 'Unknown', 'code': _selectedProvince}
    );

    final selectedMunicipality = _municipalities.firstWhere(
      (municipality) => municipality['code'] == _selectedMunicipality,
      orElse: () => {'name': 'Unknown', 'code': _selectedMunicipality}
    );

    final selectedBarangay = _barangays.firstWhere(
      (barangay) => barangay['code'] == _selectedBarangay,
      orElse: () => {'name': 'Unknown', 'code': _selectedBarangay}
    );

    // First, get the existing user document to preserve the role
    DocumentSnapshot existingDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    String userRole = 'user'; // default
    if (existingDoc.exists) {
      final existingData = existingDoc.data() as Map<String, dynamic>;
      userRole = existingData['role'] ?? 'user';
      print('Preserving existing role: $userRole');
    }

    // Prepare user data with all necessary fields
    final userData = {
      'firstName': _firstNameController.text.trim(),
      'middleInitial': _middleInitialController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'name': '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
      'phoneNumber': _phoneController.text.trim(),
      'phone': _phoneController.text.trim(),
      'gender': _selectedGender,
      'address': {
        'province': selectedProvince['name'],
        'provinceCode': selectedProvince['code'],
        'municipality': selectedMunicipality['name'],
        'municipalityCode': selectedMunicipality['code'],
        'barangay': selectedBarangay['name'],
        'barangayCode': selectedBarangay['code'],
        'street': _streetController.text.trim(),
      },
      'role': userRole, // Preserve the existing role
      'profileComplete': true, // Mark profile as complete
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    // Save to Firestore and WAIT for completion
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(userData, SetOptions(merge: true));

    // Update original data for comparison (for edit mode)
    _originalData = Map<String, dynamic>.from(userData);

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text(widget.isFirstTime ? 'Profile completed successfully!' : 'Profile updated successfully!'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    setState(() {
      _isEditing = false;
    });

    // Navigate to appropriate page based on role (only for first-time users)
    if (widget.isFirstTime) {
      print('Navigating to role-based page for role: $userRole');
      _navigateToRolePage(userRole);
    }

  } catch (e) {
    print('Error saving profile: $e');
    setState(() {
      _errorMessage = 'Failed to ${widget.isFirstTime ? 'complete' : 'update'} profile. Please try again.';
    });
  } finally {
    setState(() {
      _isUpdating = false;
    });
  }
}

Future<void> _navigateToRolePage(String uid) async {
  try {
    // Add a small delay to ensure Firestore write has propagated
    await Future.delayed(Duration(milliseconds: 500));
    
    // Fetch the updated user document to get the role
    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>;
      final role = data['role'] ?? 'user';

      print('User role: $role'); // Debug print to see what role is being retrieved

      Widget targetPage;
      switch (role.toLowerCase()) { // Convert to lowercase for consistency
        case 'bfp':
          targetPage = BFPPage();
          print('Navigating to BFP Page'); // Debug print
          break;
        case 'pnp':
          targetPage = PnpPage();
          print('Navigating to PNP Page'); // Debug print
          break;
        case 'mdrrmo':
          targetPage = MdrrmoPage();
          print('Navigating to MDRRMO Page'); // Debug print
          break;
        case 'user':
        default:
          targetPage = HomePage();
          print('Navigating to Home Page (default/user)'); // Debug print
          break;
      }

      // Use pushAndRemoveUntil to clear the entire navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => targetPage),
        (route) => false,
      );
    } else {
      print('User document does not exist, navigating to home'); // Debug print
      // Fallback to home if user document doesn't exist
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => HomePage()),
        (route) => false,
      );
    }
  } catch (e) {
    print('Error navigating to role page: $e');
    // Fallback navigation
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => HomePage()),
      (route) => false,
    );
  }
}

  // Load provinces from API
  Future<void> _loadProvinces() async {
    setState(() {
      _isLoadingProvinces = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/provinces/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _provinces = data;
        });
      } else {
        print('Failed to load provinces: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading provinces: $e');
    } finally {
      setState(() {
        _isLoadingProvinces = false;
      });
    }
  }

  // Load municipalities based on selected province
  Future<void> _loadMunicipalities(String provinceCode) async {
    setState(() {
      _isLoadingMunicipalities = true;
      _municipalities = [];
      if (_selectedMunicipality != null && 
          !_municipalities.any((m) => m['code'] == _selectedMunicipality)) {
        _selectedMunicipality = null;
      }
      _barangays = [];
      if (_selectedBarangay != null && 
          !_barangays.any((b) => b['code'] == _selectedBarangay)) {
        _selectedBarangay = null;
      }
    });

    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _municipalities = data;
        });
      } else {
        print('Failed to load municipalities: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading municipalities: $e');
    } finally {
      setState(() {
        _isLoadingMunicipalities = false;
      });
    }
  }

  // Load barangays based on selected municipality
  Future<void> _loadBarangays(String municipalityCode) async {
    setState(() {
      _isLoadingBarangays = true;
      _barangays = [];
      if (_selectedBarangay != null && 
          !_barangays.any((b) => b['code'] == _selectedBarangay)) {
        _selectedBarangay = null;
      }
    });

    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _barangays = data;
        });
      } else {
        print('Failed to load barangays: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading barangays: $e');
    } finally {
      setState(() {
        _isLoadingBarangays = false;
      });
    }
  }

  // Logout function
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      print('Error logging out: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show logout confirmation dialog
  Future<void> _showLogoutDialog() async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(screenWidth * 0.04)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.015),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout, color: Color(0xFF6B8E23), size: screenWidth * 0.06),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Text(
                  'Logout', 
                  style: TextStyle(
                    color: Color(0xFF2D3436),
                    fontSize: screenWidth * 0.045,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              color: Color(0xFF2D3436),
              fontSize: screenWidth * 0.04,
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: screenHeight * 0.06,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        ),
                      ),
                      child: Text(
                        'Cancel', 
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: screenWidth * 0.04,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.03),
                Expanded(
                  child: Container(
                    height: screenHeight * 0.06,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
                      ),
                      borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _logout();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        ),
                      ),
                      child: Text(
                        'Logout', 
                        style: TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.w600,
                          fontSize: screenWidth * 0.04,
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
    );
  }

  // Get full address string
  String _getFullAddress() {
    if (_originalData['address'] != null) {
      Map<String, dynamic> address = _originalData['address'];
      List<String> addressParts = [];
      
      if (address['street'] != null && address['street'].isNotEmpty) {
        addressParts.add(address['street']);
      }
      if (address['barangay'] != null && address['barangay'].isNotEmpty) {
        addressParts.add('Brgy. ${address['barangay']}');
      }
      if (address['municipality'] != null && address['municipality'].isNotEmpty) {
        addressParts.add(address['municipality']);
      }
      if (address['province'] != null && address['province'].isNotEmpty) {
        addressParts.add(address['province']);
      }
      
      return addressParts.join(', ');
    }
    return 'Address not provided';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF355E3B), // deep rice field green
                Color(0xFF6B8E23), // softer olive green
              ],
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF355E3B), // deep rice field green
              Color(0xFF6B8E23), // softer olive green
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 🌾 Background rice-field inspired shapes (same as homepage)
              IgnorePointer(
                child: Stack(
                  children: [
                    Positioned(
                      top: 40,
                      left: 16,
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Icon(
                          Icons.eco,
                          size: 72,
                          color: Colors.white.withOpacity(0.09),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 140,
                      right: 32,
                      child: Transform.rotate(
                        angle: 0.15,
                        child: Icon(
                          Icons.grass,
                          size: 60,
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 120,
                      left: 48,
                      child: Transform.rotate(
                        angle: -0.1,
                        child: Icon(
                          Icons.eco,
                          size: 90,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      right: 20,
                      child: Transform.rotate(
                        angle: 0.05,
                        child: Icon(
                          Icons.grass,
                          size: 68,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Column(
                children: [
                  // Custom App Bar
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.05,
                      vertical: screenHeight * 0.02,
                    ),
                    child: Row(
                      children: [
                        if (!widget.isFirstTime)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(true),
                            ),
                          ),
                        if (!widget.isFirstTime) SizedBox(width: screenWidth * 0.04),
                        Expanded(
                          child: Text(
                            widget.isFirstTime ? 'Complete Your Profile' : 'Profile',
                            style: TextStyle(
                              fontSize: screenWidth * 0.05,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (!widget.isFirstTime && !_isEditing)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(Icons.logout, color: Colors.white),
                              onPressed: _showLogoutDialog,
                            ),
                          ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        children: [
                          // Profile Header (View Mode)
                          if (!_isEditing && !widget.isFirstTime) ...[
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                              padding: EdgeInsets.all(screenWidth * 0.06),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(screenWidth * 0.05),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(screenWidth * 0.05),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      size: screenWidth * 0.1,
                                      color: Color(0xFF355E3B), // Changed to match rice field green
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.02),
                                  Text(
                                    '${_firstNameController.text} ${_lastNameController.text}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: screenWidth * 0.06,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: screenHeight * 0.01),
                                  Text(
                                    _phoneController.text.isEmpty ? 'Phone not provided' : _phoneController.text,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: screenWidth * 0.04,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: screenHeight * 0.03),

                            // Profile Information Cards
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                              child: Column(
                                children: [
                                  // Personal Information Card
                                  _buildInfoCard(
                                    title: 'Personal Information',
                                    icon: Icons.person_outline,
                                    children: [
                                      _buildInfoRow('First Name', _firstNameController.text),
                                      if (_middleInitialController.text.isNotEmpty)
                                        _buildInfoRow('Middle Initial', _middleInitialController.text),
                                      _buildInfoRow('Last Name', _lastNameController.text),
                                      _buildInfoRow('Gender', _selectedGender),
                                      _buildInfoRow('Phone Number', _phoneController.text),
                                    ],
                                  ),
                                  SizedBox(height: screenHeight * 0.02),

                                  // Address Information Card
                                  _buildInfoCard(
                                    title: 'Address Information',
                                    icon: Icons.location_on_outlined,
                                    children: [
                                      _buildInfoRow('Full Address', _getFullAddress(), isLongText: true),
                                    ],
                                  ),
                                  SizedBox(height: screenHeight * 0.03),

                                  // Edit Profile Button
                                  Container(
                                    width: double.infinity,
                                    height: screenHeight * 0.07,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
                                      ),
                                      borderRadius: BorderRadius.circular(screenWidth * 0.04),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF355E3B).withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = true;
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(screenWidth * 0.04),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.edit, color: Colors.white, size: screenWidth * 0.05),
                                          SizedBox(width: screenWidth * 0.03),
                                          Text(
                                            'Edit Profile',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: screenWidth * 0.045,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // Edit Form (Edit Mode or First Time)
                          if (_isEditing || widget.isFirstTime) ...[
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                              padding: EdgeInsets.all(screenWidth * 0.06),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(screenWidth * 0.05),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Personal Information Section
                                    _buildSectionHeader('Personal Information', Icons.person),
                                    
                                    _buildTextFormField(
                                      controller: _firstNameController,
                                      labelText: 'First Name',
                                      icon: Icons.person_outline,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'First name is required';
                                        }
                                        return null;
                                      },
                                    ),

                                    _buildTextFormField(
                                      controller: _middleInitialController,
                                      labelText: 'Middle Initial (Optional)',
                                      icon: Icons.person_outline,
                                      maxLength: 1,
                                    ),

                                    _buildTextFormField(
                                      controller: _lastNameController,
                                      labelText: 'Last Name',
                                      icon: Icons.person_outline,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Last name is required';
                                        }
                                        return null;
                                      },
                                    ),

                                    _buildDropdownField(
                                      value: _selectedGender,
                                      labelText: 'Gender',
                                      icon: Icons.wc,
                                      items: ['Male', 'Female', 'Other'],
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedGender = value!;
                                        });
                                      },
                                    ),

                                    _buildTextFormField(
                                      controller: _phoneController,
                                      labelText: 'Phone Number',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Phone number is required';
                                        }
                                        return null;
                                      },
                                    ),

                                    SizedBox(height: 24),

                                    // Address Information Section
                                    _buildSectionHeader('Address Information', Icons.location_on),

                                    _buildProvinceDropdown(),
                                    _buildMunicipalityDropdown(),
                                    _buildBarangayDropdown(),

                                    _buildTextFormField(
                                      controller: _streetController,
                                      labelText: 'Street Address',
                                      icon: Icons.home_outlined,
                                      maxLines: 2,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Street address is required';
                                        }
                                        return null;
                                      },
                                    ),

                                    SizedBox(height: 24),

                                    // Error Message
                                    if (_errorMessage.isNotEmpty)
                                      Container(
                                        margin: EdgeInsets.only(bottom: 16),
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.red.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _errorMessage,
                                                style: TextStyle(
                                                  color: Colors.red.shade700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Action Buttons
                                    Row(
                                      children: [
                                        if (!widget.isFirstTime) ...[
                                          Expanded(
                                            child: Container(
                                              height: screenHeight * 0.07,
                                              child: OutlinedButton(
                                                onPressed: _isUpdating ? null : () {
                                                  setState(() {
                                                    _isEditing = false;
                                                    _errorMessage = '';
                                                  });
                                                },
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(color: Color(0xFF355E3B)),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(screenWidth * 0.04),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Cancel',
                                                  style: TextStyle(
                                                    color: Color(0xFF355E3B),
                                                    fontSize: screenWidth * 0.04,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: screenWidth * 0.04),
                                        ],
                                        Expanded(
                                          child: Container(
                                            height: screenHeight * 0.07,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
                                              ),
                                              borderRadius: BorderRadius.circular(screenWidth * 0.04),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Color(0xFF355E3B).withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: ElevatedButton(
                                              onPressed: _isUpdating ? null : _saveUserProfile,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(screenWidth * 0.04),
                                                ),
                                              ),
                                              child: _isUpdating
                                                  ? Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child: CircularProgressIndicator(
                                                            color: Colors.white,
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                        SizedBox(width: 12),
                                                        Text(
                                                          'Updating...',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: screenWidth * 0.04,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Text(
                                                      widget.isFirstTime ? 'Complete Profile' : 'Update Profile',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: screenWidth * 0.045,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          SizedBox(height: screenHeight * 0.05),
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

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(screenWidth * 0.04),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.02),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF355E3B).withOpacity(0.1), Color(0xFF6B8E23).withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(screenWidth * 0.02),
                ),
                child: Icon(
                  icon,
                  size: screenWidth * 0.05,
                  color: Color(0xFF355E3B),
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: screenWidth * 0.045,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3436),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.02),
          ...children,
        ],
      ),
      );
  }

  Widget _buildInfoRow(String label, String value, {bool isLongText = false}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      margin: EdgeInsets.only(bottom: screenHeight * 0.015),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: screenWidth * 0.032,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: screenHeight * 0.005),
          Text(
            value.isEmpty ? 'Not provided' : value,
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              color: value.isEmpty ? Colors.grey[400] : Color(0xFF2D3436),
              fontWeight: FontWeight.w600,
            ),
            maxLines: isLongText ? null : 1,
            overflow: isLongText ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF355E3B).withOpacity(0.1), Color(0xFF6B8E23).withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Color(0xFF355E3B),
            ),
          ),
          SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3436),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    int maxLines = 1,
    int? maxLength,
    bool enabled = true,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: enabled ? Colors.grey[50] : Colors.grey[100],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        maxLength: maxLength,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: enabled ? Color(0xFF355E3B) : Colors.grey[400]),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: enabled ? Colors.grey[50] : Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required String labelText,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Color(0xFF355E3B)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: items.map((String item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item),
          );
        }).toList(),
       
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select an option';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildProvinceDropdown() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedProvince,
        decoration: InputDecoration(
          labelText: 'Province',
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.location_city_outlined, color: Color(0xFF355E3B)),
          suffixIcon: _isLoadingProvinces 
            ? Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF355E3B),
                  ),
                ),
              )
            : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: _provinces.map<DropdownMenuItem<String>>((province) {
          return DropdownMenuItem<String>(
            value: province['code'],
            child: Text(province['name']),
          );
        }).toList(),
        onChanged: _isLoadingProvinces ? null : (value) {
          setState(() {
            _selectedProvince = value;
            _selectedMunicipality = null;
            _selectedBarangay = null;
          });
          if (value != null) {
            _loadMunicipalities(value);
          }
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a province';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildMunicipalityDropdown() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedMunicipality,
        decoration: InputDecoration(
          labelText: 'Municipality/City',
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.location_on_outlined, color: Color(0xFF355E3B)),
          suffixIcon: _isLoadingMunicipalities 
            ? Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF355E3B),
                  ),
                ),
              )
            : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: _municipalities.map<DropdownMenuItem<String>>((municipality) {
          return DropdownMenuItem<String>(
            value: municipality['code'],
            child: Text(municipality['name']),
          );
        }).toList(),
        onChanged: (_isLoadingMunicipalities || _selectedProvince == null) ? null : (value) {
          setState(() {
            _selectedMunicipality = value;
            _selectedBarangay = null;
          });
          if (value != null) {
            _loadBarangays(value);
          }
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a municipality/city';
          }
          return null;
        },
        hint: _selectedProvince == null 
          ? Text('Select a province first', style: TextStyle(color: Colors.grey[400]))
          : _municipalities.isEmpty
            ? Text('Loading municipalities...', style: TextStyle(color: Colors.grey[400]))
            : Text('Select Municipality/City', style: TextStyle(color: Colors.grey[400])),
      ),
    );
  }

  Widget _buildBarangayDropdown() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedBarangay,
        decoration: InputDecoration(
          labelText: 'Barangay',
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.location_city_outlined, color: Color(0xFF355E3B)),
          suffixIcon: _isLoadingBarangays 
            ? Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF355E3B),
                  ),
                ),
              )
            : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: _barangays.map<DropdownMenuItem<String>>((barangay) {
          return DropdownMenuItem<String>(
            value: barangay['code'],
            child: Text(barangay['name']),
          );
        }).toList(),
        onChanged: (_isLoadingBarangays || _selectedMunicipality == null) ? null : (value) {
          setState(() {
            _selectedBarangay = value;
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a barangay';
          }
          return null;
        },
        hint: _selectedProvince == null 
          ? Text('Select a province first', style: TextStyle(color: Colors.grey[400]))
          : _selectedMunicipality == null
            ? Text('Select a municipality first', style: TextStyle(color: Colors.grey[400]))
            : _barangays.isEmpty
              ? Text('Loading barangays...', style: TextStyle(color: Colors.grey[400]))
              : Text('Select Barangay', style: TextStyle(color: Colors.grey[400])),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    super.dispose();
  }
}