import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Form controllers
  final _firstNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // New requirement controllers
  final _idNumberController = TextEditingController();
  final _dateIssuedController = TextEditingController();
  final _expirationDateController = TextEditingController();
  final _rankPositionController = TextEditingController();
  final _stationUnitController = TextEditingController();
  
  // Form state
  String _selectedGender = 'Male';
  String? _selectedRole;

  // --- LOCKED: Province = Laguna, Municipality = Victoria ---
  // These are the PSGC codes for Laguna and Victoria, Laguna.
  // Laguna province code: 0434600000
  // Victoria, Laguna code: 043460400
  static const String _laguna_Province_Code = '0434600000';
  static const String _laguna_Province_Name = 'LAGUNA';
  static const String _victoria_Municipality_Code = '0403430000';
  static const String _victoria_Municipality_Name = 'VICTORIA';

  String _selectedProvince = _laguna_Province_Code;
  String _selectedMunicipality = _victoria_Municipality_Code;
  String? _selectedBarangay;

  List<dynamic> _barangays = [];
  
  // New requirement state
  File? _idFile;
  File? _clearanceFile;
  DateTime? _selectedDateIssued;
  DateTime? _selectedExpirationDate;
  
  String _errorMessage = '';
  bool _isLoading = false;
  bool _isLoadingBarangays = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  static const String BACKEND_URL = 'https://unvociferous-microscopic-jamari.ngrok-free.dev';

  @override
  void initState() {
    super.initState();
    // Load barangays for Victoria, Laguna immediately on start
    _loadBarangays(_victoria_Municipality_Code);
  }

  // Hardcoded barangays of Victoria, Laguna (9 barangays)
  void _loadBarangays(String municipalityCode) {
    setState(() {
      _barangays = [
        {'code': '0403430001', 'name': 'Bancabanca'},
        {'code': '0403430002', 'name': 'Daniw'},
        {'code': '0403430003', 'name': 'Masapang'},
        {'code': '0403430004', 'name': 'Nanhaya (Poblacion)'},
        {'code': '0403430005', 'name': 'Pagalangan'},
        {'code': '0403430006', 'name': 'San Benito'},
        {'code': '0403430007', 'name': 'San Felix'},
        {'code': '0403430008', 'name': 'San Francisco'},
        {'code': '0403430009', 'name': 'San Roque'},
      ];
      _isLoadingBarangays = false;
      _selectedBarangay = null;
    });
  }

  // File picker methods
  Future<void> _pickIdFile() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _idFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _pickClearanceFile() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _clearanceFile = File(pickedFile.path);
      });
    }
  }

  // Date picker methods
  Future<void> _selectDateIssued() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDateIssued) {
      setState(() {
        _selectedDateIssued = picked;
        _dateIssuedController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _selectExpirationDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedExpirationDate) {
      setState(() {
        _selectedExpirationDate = picked;
        _expirationDateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // Clear requirement fields when role changes
  void _clearRequirementFields() {
    _idNumberController.clear();
    _dateIssuedController.clear();
    _expirationDateController.clear();
    _rankPositionController.clear();
    _stationUnitController.clear();
    setState(() {
      _idFile = null;
      _clearanceFile = null;
      _selectedDateIssued = null;
      _selectedExpirationDate = null;
    });
  }

  // Registration function
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate requirement fields for specific roles
    if (_selectedRole == 'pnp' || _selectedRole == 'bfp' || _selectedRole == 'mdrrmo') {
      if (_idNumberController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = '${_getRoleDisplayName()} ID Number is required';
        });
        return;
      }
      if (_dateIssuedController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Date Issued is required';
        });
        return;
      }
      if (_expirationDateController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Expiration Date is required';
        });
        return;
      }
      if (_idFile == null) {
        setState(() {
          _errorMessage = '${_getRoleDisplayName()} ID upload is required';
        });
        return;
      }
      if (_clearanceFile == null) {
        setState(() {
          _errorMessage = '${_getClearanceDocumentName()} upload is required';
        });
        return;
      }
    }

    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      if (_selectedBarangay == null) {
        setState(() {
          _errorMessage = 'Please select a barangay';
          _isLoading = false;
        });
        return;
      }

      if (_selectedRole == null) {
        setState(() {
          _errorMessage = 'Please select a role';
          _isLoading = false;
        });
        return;
      }

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // Create Firebase user first
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        setState(() {
          _errorMessage = 'Failed to create user account';
          _isLoading = false;
        });
        return;
      }

      final idToken = await userCredential.user!.getIdToken(true);
      
      if (idToken == null || idToken.isEmpty) {
        setState(() {
          _errorMessage = 'Failed to get authentication token';
          _isLoading = false;
        });
        return;
      }

      // Get barangay name
      final selectedBarangay = _barangays.firstWhere(
        (barangay) => barangay['code'] == _selectedBarangay,
        orElse: () => {'name': 'Unknown', 'code': _selectedBarangay}
      );

      String barangayName = selectedBarangay['name'];
      String barangayCode = selectedBarangay['code'];

      // Prepare requirement data
      Map<String, dynamic> requirementData = {};
      if (_selectedRole == 'pnp' || _selectedRole == 'bfp' || _selectedRole == 'mdrrmo') {
        requirementData = {
          'idNumber': _idNumberController.text.trim(),
          'dateIssued': _dateIssuedController.text.trim(),
          'expirationDate': _expirationDateController.text.trim(),
          'rankPosition': _rankPositionController.text.trim(),
          'stationUnit': _stationUnitController.text.trim(),
          'hasIdFile': _idFile != null,
          'hasClearanceFile': _clearanceFile != null,
        };
      }

      // Prepare registration data
      final registrationData = {
        'idToken': idToken,
        'firstName': _firstNameController.text.trim(),
        'middleInitial': _middleInitialController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': email,
        'phoneNumber': _phoneController.text.trim(),
        'gender': _selectedGender,
        'role': _selectedRole,
        'address': {
          'province': _laguna_Province_Name,
          'provinceCode': _laguna_Province_Code,
          'municipality': _victoria_Municipality_Name,
          'municipalityCode': _victoria_Municipality_Code,
          'barangay': barangayName,
          'barangayCode': barangayCode,
          'street': _streetController.text.trim(),
        },
        'requirements': requirementData,
      };

      final response = await http.post(
        Uri.parse('$BACKEND_URL/api/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(registrationData),
      ).timeout(Duration(seconds: 15));

      if (response.body.isEmpty) {
        setState(() {
          _errorMessage = 'Empty response from server. Check if your Flask server is running.';
          _isLoading = false;
        });
        return;
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 && responseData['success'] == true) {
        await FirebaseAuth.instance.signOut();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text("Account created successfully! Please sign in with your credentials."),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: Duration(seconds: 4),
          ),
        );

        Navigator.pop(context);
        
      } else {
        final errorMsg = responseData['error'] ?? 'Registration failed';
        setState(() {
          _errorMessage = errorMsg;
        });
      }

    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'email-already-in-use':
            _errorMessage = 'An account with this email already exists.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email address format.';
            break;
          case 'weak-password':
            _errorMessage = 'Password is too weak. Please choose a stronger password.';
            break;
          case 'network-request-failed':
            _errorMessage = 'Network error. Please check your internet connection.';
            break;
          default:
            _errorMessage = 'Registration failed: ${e.message ?? e.code}';
        }
      });
    } on http.ClientException catch (e) {
      setState(() {
        _errorMessage = 'Network error: Cannot reach server. Please check if your Flask server is running.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected error occurred: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getRoleDisplayName() {
    switch (_selectedRole) {
      case 'pnp': return 'PNP';
      case 'bfp': return 'BFP';
      case 'mdrrmo': return 'MDRRMO';
      default: return '';
    }
  }

  String _getClearanceDocumentName() {
    switch (_selectedRole) {
      case 'pnp': return 'PNP Clearance';
      case 'bfp': return 'BFP Certification';
      case 'mdrrmo': return 'MDRRMO Certification';
      default: return 'Clearance';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isMobile = screenSize.width <= 480;
    
    final horizontalPadding = isTablet ? 32.0 : (isMobile ? 16.0 : 24.0);
    final cardPadding = isTablet ? 40.0 : (isMobile ? 24.0 : 32.0);
    final logoSize = isTablet ? 100.0 : (isMobile ? 70.0 : 80.0);
    final titleFontSize = isTablet ? 32.0 : (isMobile ? 24.0 : 28.0);
    final subtitleFontSize = isTablet ? 22.0 : (isMobile ? 16.0 : 20.0);
    final buttonHeight = isTablet ? 60.0 : (isMobile ? 50.0 : 54.0);
    final buttonFontSize = isTablet ? 18.0 : 16.0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: Image.asset('assets/images/vic.jpg').image,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.4),
              BlendMode.darken,
            ),
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isTablet ? 600.0 : (isMobile ? screenSize.width * 0.95 : screenSize.width * 0.9),
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isMobile) Flexible(child: SizedBox(height: 20)),
                          _buildHeader(logoSize, titleFontSize, subtitleFontSize),
                          SizedBox(height: isTablet ? 30 : (isMobile ? 20 : 25)),
                          _buildRegistrationCard(cardPadding, isMobile, isTablet, buttonHeight, buttonFontSize),
                          if (!isMobile) Flexible(child: SizedBox(height: 20)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double logoSize, double titleFontSize, double subtitleFontSize) {
    return Column(
      children: [
        Hero(
          tag: 'app_logo',
          child: Container(
            width: logoSize + 20,
            height: logoSize + 20,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/viclogo.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'SAFEVictoria',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: Offset(2, 2)),
            ],
          ),
        ),
        Text(
          'Registration',
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w300,
            color: Colors.white.withOpacity(0.95),
            letterSpacing: 0.8,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: Offset(1, 1)),
            ],
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Create your responder account',
          style: TextStyle(
            fontSize: subtitleFontSize * 0.6,
            color: Colors.white.withOpacity(0.8),
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: Offset(1, 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationCard(double cardPadding, bool isMobile, bool isTablet, double buttonHeight, double buttonFontSize) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
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
            _buildAppBar(isTablet, isMobile),
            SizedBox(height: isTablet ? 30 : (isMobile ? 20 : 25)),

            // Personal Information
            _buildSectionHeader('Personal Information', Icons.person, isTablet),
            _buildTextFormField(
              controller: _firstNameController,
              labelText: 'First Name',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'First name is required';
                if (value.trim().length < 2) return 'First name must be at least 2 characters';
                return null;
              },
            ),
            _buildTextFormField(
              controller: _middleInitialController,
              labelText: 'Middle Initial (Optional)',
              icon: Icons.person_outline,
              maxLength: 1,
              validator: (value) {
                if (value != null && value.isNotEmpty && value.length != 1) {
                  return 'Middle initial should be 1 character';
                }
                return null;
              },
            ),
            _buildTextFormField(
              controller: _lastNameController,
              labelText: 'Last Name',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Last name is required';
                if (value.trim().length < 2) return 'Last name must be at least 2 characters';
                return null;
              },
            ),
            _buildDropdownField(
              value: _selectedGender,
              labelText: 'Gender',
              icon: Icons.wc,
              items: ['Male', 'Female', 'Other'],
              onChanged: (value) => setState(() => _selectedGender = value!),
            ),

            SizedBox(height: isTablet ? 25 : (isMobile ? 15 : 20)),

            // Contact Information
            _buildSectionHeader('Contact Information', Icons.contact_phone, isTablet),
            _buildTextFormField(
              controller: _emailController,
              labelText: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Email is required';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            _buildTextFormField(
              controller: _phoneController,
              labelText: 'Phone Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Phone number is required';
                if (value.trim().length < 10) return 'Phone number must be at least 10 digits';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 25 : (isMobile ? 15 : 20)),

            // Address Information
            _buildSectionHeader('Address Information', Icons.location_on, isTablet),

            // LOCKED Province field (read-only display)
            _buildLockedLocationField(
              labelText: 'Province',
              value: 'LAGUNA',
              icon: Icons.location_city_outlined,
            ),

            // LOCKED Municipality field (read-only display)
            _buildLockedLocationField(
              labelText: 'Municipality',
              value: 'VICTORIA',
              icon: Icons.location_on_outlined,
            ),

            // Barangay Dropdown (still selectable)
            _buildBarangayDropdown(),

            // Street Address
            _buildTextFormField(
              controller: _streetController,
              labelText: 'Street Address (House No., Street Name)',
              icon: Icons.home_outlined,
              maxLines: 2,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Street address is required';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 25 : (isMobile ? 15 : 20)),

            // Account Information
            _buildSectionHeader('Account Information', Icons.work, isTablet),
            _buildRoleDropdown(),

            if (_selectedRole == 'pnp' || _selectedRole == 'bfp' || _selectedRole == 'mdrrmo')
              _buildRequirementSection(),

            _buildTextFormField(
              controller: _passwordController,
              labelText: 'Password',
              icon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Color(0xFF6B8E23),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                if (value.length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
            _buildTextFormField(
              controller: _confirmPasswordController,
              labelText: 'Confirm Password',
              icon: Icons.lock_outline,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Color(0xFF6B8E23),
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please confirm your password';
                if (value != _passwordController.text) return 'Passwords do not match';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 30 : (isMobile ? 20 : 25)),

            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              height: _errorMessage.isNotEmpty ? null : 0,
              child: _errorMessage.isNotEmpty ? _buildErrorMessage() : SizedBox.shrink(),
            ),
            if (_errorMessage.isNotEmpty) SizedBox(height: 16),

            _buildRegisterButton(buttonHeight, buttonFontSize),
            SizedBox(height: 24),
            _buildLoginLink(isTablet, isMobile),
          ],
        ),
      ),
    );
  }

  // Locked (read-only) display field for Province and Municipality
  Widget _buildLockedLocationField({
    required String labelText,
    required String value,
    required IconData icon,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[100],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        enabled: false,
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Color(0xFF355E3B)),
          suffixIcon: Icon(Icons.lock_outline, color: Colors.grey[400], size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildRequirementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20),
        _buildSectionHeader('${_getRoleDisplayName()} Requirements', Icons.assignment, false),
        _buildTextFormField(
          controller: _idNumberController,
          labelText: '${_getRoleDisplayName()} ID Number',
          icon: Icons.badge_outlined,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '${_getRoleDisplayName()} ID Number is required';
            }
            return null;
          },
        ),
        _buildDateField(
          controller: _dateIssuedController,
          labelText: 'Date Issued',
          onTap: _selectDateIssued,
        ),
        _buildDateField(
          controller: _expirationDateController,
          labelText: 'Expiration Date',
          onTap: _selectExpirationDate,
        ),
        _buildTextFormField(
          controller: _rankPositionController,
          labelText: 'Rank / Position (Optional)',
          icon: Icons.work_outline,
        ),
        _buildTextFormField(
          controller: _stationUnitController,
          labelText: _selectedRole == 'mdrrmo'
              ? 'Municipality (Optional)'
              : '${_getRoleDisplayName()} Station / Unit (Optional)',
          icon: Icons.location_city_outlined,
        ),
        _buildFileUploadField(
          labelText: '${_getRoleDisplayName()} ID Upload',
          file: _idFile,
          onPressed: _pickIdFile,
        ),
        _buildFileUploadField(
          labelText: '${_getClearanceDocumentName()} Upload',
          file: _clearanceFile,
          onPressed: _pickClearanceFile,
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String labelText,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        enabled: !_isLoading,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.calendar_today_outlined, color: Color(0xFF355E3B)),
          suffixIcon: Icon(Icons.arrow_drop_down, color: Color(0xFF355E3B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return '$labelText is required';
          return null;
        },
      ),
    );
  }

  Widget _buildFileUploadField({
    required String labelText,
    required File? file,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              labelText,
              style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file != null ? file.path.split('/').last : 'No file selected',
                    style: TextStyle(
                      color: file != null ? Colors.grey[800] : Colors.grey[500],
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(Icons.upload_file, size: 18),
                  label: Text('Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF355E3B),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isTablet, bool isMobile) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Color(0xFF355E3B)),
            onPressed: () => Navigator.pop(context),
            iconSize: isTablet ? 28 : (isMobile ? 20 : 24),
          ),
        ),
        SizedBox(width: 16),
        Text(
          'Create Account',
          style: TextStyle(
            fontSize: isTablet ? 24 : (isMobile ? 18 : 20),
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3436),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isTablet) {
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
            child: Icon(icon, size: isTablet ? 24 : 20, color: Color(0xFF355E3B)),
          ),
          SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: isTablet ? 20 : 18,
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
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        maxLength: maxLength,
        autocorrect: false,
        textCapitalization: obscureText ? TextCapitalization.none : TextCapitalization.words,
        enabled: !_isLoading,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Color(0xFF355E3B)),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
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
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(icon, color: Color(0xFF355E3B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        items: items.map((item) {
          return DropdownMenuItem<String>(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.isEmpty) return 'Please select an option';
          return null;
        },
      ),
    );
  }

  // FIXED Role Dropdown — removed FittedBox + isExpanded combo that broke tap detection
  Widget _buildRoleDropdown() {
    final List<Map<String, String>> roles = [
      {'value': 'user',    'label': 'Resident'},
      {'value': 'pnp',     'label': 'Philippine National Police (PNP)'},
      {'value': 'bfp',     'label': 'Bureau of Fire Protection (BFP)'},
      {'value': 'mdrrmo',  'label': 'MDRRMO'},
    ];

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedRole,
        isExpanded: true,   // keeps long text from overflowing
        decoration: InputDecoration(
          labelText: 'Agency / Role',
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.work_outline, color: Color(0xFF355E3B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFF355E3B), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        hint: Text('Choose Role', style: TextStyle(color: Colors.grey[400])),
        // KEY FIX: plain Text widget only — no FittedBox, no Flexible
        items: roles.map((role) {
          return DropdownMenuItem<String>(
            value: role['value'],
            child: Text(
              role['label']!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14),
            ),
          );
        }).toList(),
        onChanged: (value) {
          _clearRequirementFields();
          setState(() => _selectedRole = value);
        },
        validator: (value) {
          if (value == null || value.isEmpty) return 'Please select a role';
          return null;
        },
      ),
    );
  }

  // Opens a searchable bottom sheet for barangay selection
  void _openBarangayPicker() {
    if (_isLoadingBarangays || _barangays.isEmpty) return;
    String searchQuery = '';
    List<dynamic> filtered = List.from(_barangays);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Select Barangay',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3436)),
                      ),
                    ),
                    SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Search barangay...',
                          prefixIcon: Icon(Icons.search, color: Color(0xFF355E3B)),
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.toLowerCase();
                            filtered = _barangays
                                .where((b) => b['name'].toString().toLowerCase().contains(searchQuery))
                                .toList();
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 8),
                    Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final barangay = filtered[index];
                          final isSelected = _selectedBarangay == barangay['code'];
                          return ListTile(
                            title: Text(
                              barangay['name'],
                              style: TextStyle(
                                fontSize: 15,
                                color: isSelected ? Color(0xFF355E3B) : Color(0xFF2D3436),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isSelected ? Icon(Icons.check_circle, color: Color(0xFF355E3B)) : null,
                            onTap: () {
                              setState(() => _selectedBarangay = barangay['code']);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBarangayDropdown() {
    String displayText = 'Select Barangay';
    if (_selectedBarangay != null && _barangays.isNotEmpty) {
      final found = _barangays.cast<Map>().firstWhere(
        (b) => b['code'] == _selectedBarangay,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) displayText = found['name'];
    }

    return FormField<String>(
      validator: (_) => _selectedBarangay == null ? 'Please select a barangay' : null,
      builder: (formState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _isLoadingBarangays ? null : _openBarangayPicker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: EdgeInsets.only(bottom: formState.hasError ? 4 : 16),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[50],
                  border: Border.all(
                    color: formState.hasError ? Colors.red : Colors.transparent,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.home_work_outlined, color: Color(0xFF355E3B)),
                    SizedBox(width: 12),
                    Expanded(
                      child: _isLoadingBarangays
                          ? Row(children: [
                              SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF355E3B))),
                              SizedBox(width: 10),
                              Text('Loading barangays...', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                            ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Barangay', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                SizedBox(height: 2),
                                Text(
                                  displayText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _selectedBarangay == null ? Colors.grey[400] : Color(0xFF2D3436),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Color(0xFF355E3B)),
                  ],
                ),
              ),
            ),
            if (formState.hasError)
              Padding(
                padding: EdgeInsets.only(left: 16, bottom: 12),
                child: Text(formState.errorText!, style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          SizedBox(width: 12),
          Expanded(
            child: Text(_errorMessage, style: TextStyle(color: Colors.red.shade800)),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterButton(double buttonHeight, double buttonFontSize) {
    return Container(
      height: buttonHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
        ),
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                'Create Account',
                style: TextStyle(
                  fontSize: buttonFontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink(bool isTablet, bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account?',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: isTablet ? 16 : (isMobile ? 14 : 15),
          ),
        ),
        SizedBox(width: 8),
        GestureDetector(
          onTap: _isLoading ? null : () => Navigator.pop(context),
          child: Text(
            'Sign In',
            style: TextStyle(
              color: Color(0xFF355E3B),
              fontWeight: FontWeight.bold,
              fontSize: isTablet ? 16 : (isMobile ? 14 : 15),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleInitialController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _idNumberController.dispose();
    _dateIssuedController.dispose();
    _expirationDateController.dispose();
    _rankPositionController.dispose();
    _stationUnitController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}