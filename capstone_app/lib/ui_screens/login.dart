import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'userpage.dart'; 
import 'bfppage.dart';
import 'pnppage.dart';
import 'mdrrmopage.dart';  
import 'register.dart';
import 'forgotpage.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _errorMessage = '';
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Update your backend URL here - make sure it matches your Flask server
  static const String BACKEND_URL = 'https://capstone-production-9474.up.railway.app';

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
    
    // Test image loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(AssetImage('assets/images/vic.jpg'), context).catchError((error) {
        print('Image precache error: $error');
      });
    });
  }

  Future<void> _checkCurrentUser() async {
  // Check if user is already signed in
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    print('Found existing authenticated user: ${user.email}');
    // Force sign out to ensure clean state for new login
    await FirebaseAuth.instance.signOut();
    print('Signed out existing user for clean login state');
  }
}

  Future<void> _login() async {
  // Clear previous error messages and validate inputs
  setState(() {
    _errorMessage = '';
    _isLoading = true;
  });

  try {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both email and password';
        _isLoading = false;
      });
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    print('=== LOGIN ATTEMPT ===');
    print('Email: $email');
    print('Password length: ${password.length}');

    // Ensure we start with a clean Firebase Auth state
    await FirebaseAuth.instance.signOut();
    await Future.delayed(Duration(milliseconds: 500));

    // Authenticate with Firebase
    print('Attempting Firebase authentication...');
    final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (userCredential.user == null) {
      setState(() {
        _errorMessage = 'Authentication failed - no user returned';
        _isLoading = false;
      });
      return;
    }

    print('✓ Firebase authentication successful');
    print('User: ${userCredential.user?.email}');
    print('UID: ${userCredential.user?.uid}');

    // Get fresh ID token
    print('Getting fresh ID token...');
    final idToken = await userCredential.user!.getIdToken(true);
    
    if (idToken == null || idToken.isEmpty) {
      setState(() {
        _errorMessage = 'Failed to get authentication token';
        _isLoading = false;
      });
      return;
    }

    print('✓ Firebase ID Token obtained');

    // Small delay to ensure token is ready
    await Future.delayed(Duration(milliseconds: 500));

    // Send request to backend
    print('Sending request to backend: $BACKEND_URL/api/login');
    final response = await http.post(
      Uri.parse('$BACKEND_URL/api/login'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'idToken': idToken,
      }),
    ).timeout(Duration(seconds: 15));

    print('Backend response status: ${response.statusCode}');

    if (response.body.isEmpty) {
      setState(() {
        _errorMessage = 'Empty response from server. Check if your Flask server is running.';
        _isLoading = false;
      });
      return;
    }

    final responseData = jsonDecode(response.body);
    print('Backend response: $responseData');

    // Handle different response status codes
    if (response.statusCode == 200 && responseData['success'] == true) {
      // SUCCESSFUL LOGIN
      final userRole = responseData['user']['role'];
      final userEmail = responseData['user']['email'];
      
      print('✓ Login successful - Role: $userRole, Email: $userEmail');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text("Welcome back, $userEmail!"),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Navigate based on user role with clean navigation
        Widget destinationPage;
        
        switch (userRole.toLowerCase()) {
          case 'bfp':
            destinationPage = BFPPage();
            break;
          case 'pnp':
            destinationPage = PnpPage(); 
            break;
          case 'mdrrmo':
            destinationPage = MdrrmoPage();
            break;
          case 'user':
          default:
            destinationPage = HomePage(); 
            break;
        }
        
        // Clear navigation stack and navigate to destination
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => destinationPage),
          (route) => false,
        );
      }
      
    } else if (response.statusCode == 403) {
      // ACCOUNT PENDING OR REJECTED - BLOCK LOGIN
      final errorMsg = responseData['error'] ?? 'Account not approved';
      
      // Sign out from Firebase since account is not approved
      await FirebaseAuth.instance.signOut();
      
      setState(() {
        _errorMessage = errorMsg;
      });
      print('✗ Account not approved: $errorMsg');
      
      // Show appropriate message based on account status
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text(errorMsg)),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: Duration(seconds: 4),
          ),
        );
      }
      
    } else {
      // OTHER ERRORS (401, 500, etc.)
      final errorMsg = responseData['error'] ?? 'Login failed with status ${response.statusCode}';
      
      // Sign out from Firebase on other errors
      await FirebaseAuth.instance.signOut();
      
      setState(() {
        _errorMessage = errorMsg;
      });
      print('✗ Backend login failed: $errorMsg (Status: ${response.statusCode})');
    }

  } on FirebaseAuthException catch (e) {
    print('✗ FirebaseAuthException: ${e.code} - ${e.message}');
    
    if (mounted) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No user found with this email. Please check the email or sign up first.';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password. Please try again.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email address format.';
            break;
          case 'user-disabled':
            _errorMessage = 'This user account has been disabled.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many failed attempts. Please wait and try again later.';
            break;
          case 'network-request-failed':
            _errorMessage = 'Network error. Please check your internet connection.';
            break;
          case 'invalid-credential':
            _errorMessage = 'Invalid credentials. Please check your email and password.';
            break;
          default:
            _errorMessage = 'Authentication failed: ${e.message ?? e.code}';
        }
      });
    }
  } on http.ClientException catch (e) {
    print('✗ HTTP ClientException: $e');
    if (mounted) {
      setState(() {
        _errorMessage = 'Cannot reach server. Please check if your Flask server is running on $BACKEND_URL';
      });
    }
  } on FormatException catch (e) {
    print('✗ JSON Format Exception: $e');
    if (mounted) {
      setState(() {
        _errorMessage = 'Server returned invalid response format.';
      });
    }
  } catch (e, stackTrace) {
    print('✗ Unexpected error: $e');
    print('Stack trace: $stackTrace');
    
    // Ensure we sign out on any unexpected error
    try {
      await FirebaseAuth.instance.signOut();
    } catch (signOutError) {
      print('Error during sign out: $signOutError');
    }
    
    if (mounted) {
      setState(() {
        _errorMessage = 'Unexpected error occurred: $e';
      });
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    final isMobile = screenSize.width <= 480;
    
    // Responsive dimensions
    final cardMaxWidth = isTablet ? 500.0 : (isMobile ? screenSize.width * 0.9 : screenSize.width * 0.85);
    final horizontalPadding = isTablet ? 32.0 : (isMobile ? 16.0 : 24.0);
    final cardPadding = isTablet ? 40.0 : (isMobile ? 24.0 : 32.0);
    final logoSize = isTablet ? 100.0 : (isMobile ? 70.0 : 80.0);
    final titleFontSize = isTablet ? 32.0 : (isMobile ? 24.0 : 28.0);
    final subtitleFontSize = isTablet ? 22.0 : (isMobile ? 16.0 : 20.0);
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: Image.asset('assets/images/vic.jpg').image,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            repeat: ImageRepeat.noRepeat,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.4),
              BlendMode.darken,
            ),
            onError: (exception, stackTrace) {
              print('Error loading background image: $exception');
            },
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: cardMaxWidth,
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Flexible spacing at top
                          if (!isMobile) Flexible(child: SizedBox(height: 20)),
                          
                          // App Logo and Title
                          _buildHeader(logoSize, titleFontSize, subtitleFontSize),
                          
                          SizedBox(height: isTablet ? 50 : (isMobile ? 30 : 40)),
                          
                          // Login Form Card
                          _buildLoginCard(cardPadding, isMobile, isTablet),
                          
                          // Debug buttons (only in debug mode)
                          if (const bool.fromEnvironment('dart.vm.product') == false)
                            _buildDebugButtons(),
                          
                          // Flexible spacing at bottom
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
          width: logoSize + 20,   // circle background size
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
          child: ClipOval( // ensures the logo fits inside circle
            child: Image.asset(
              'assets/images/viclogo.png',
              width: logoSize,
              height: logoSize,
              fit: BoxFit.cover, // make it cover the circle
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
            Shadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: Offset(2, 2),
            ),
          ],
        ),
      ),
      Text(
        'Mobile App',
        style: TextStyle(
          fontSize: subtitleFontSize,
          fontWeight: FontWeight.w300,
          color: Colors.white.withOpacity(0.95),
          letterSpacing: 0.8,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
    ],
  );
}


  Widget _buildLoginCard(double cardPadding, bool isMobile, bool isTablet) {
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
          // Welcome text
          Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 28 : (isMobile ? 20 : 24),
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3436),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Sign in to your account',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 16 : (isMobile ? 12 : 14),
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: isTablet ? 40 : (isMobile ? 24 : 32)),
          
          // Email TextField
          _buildTextField(
            controller: _emailController,
            labelText: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: 16),
          
          // Password TextField
          _buildTextField(
            controller: _passwordController,
            labelText: 'Password',
            prefixIcon: Icons.lock_outline,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Color(0xFF6B8E23),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            onSubmitted: (_) => _isLoading ? null : _login(),
          ),
          
          // Forgot Password Button - ADD THIS SECTION
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ForgotPassPage()),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: Color(0xFF355E3B),
                  fontSize: isTablet ? 15.0 : (isMobile ? 13.0 : 14.0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // END OF NEW SECTION
          
          SizedBox(height: 16),
          
          // Error Message
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            height: _errorMessage.isNotEmpty ? null : 0,
            child: _errorMessage.isNotEmpty ? _buildErrorMessage() : SizedBox.shrink(),
          ),
          
          if (_errorMessage.isNotEmpty) SizedBox(height: 16),
          
          // Login Button
          _buildLoginButton(isTablet, isMobile),
          
          SizedBox(height: 24),
          
          // Registration Link
          _buildRegistrationLink(isTablet, isMobile),
        ],
      ),
    ),
  );
}

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        enabled: !_isLoading,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(prefixIcon, color: Color(0xFF355E3B)),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
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
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'This field is required';
          }
          if (labelText == 'Email' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Please enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(bool isTablet, bool isMobile) {
    final buttonHeight = isTablet ? 60.0 : (isMobile ? 50.0 : 54.0);
    final fontSize = isTablet ? 18.0 : 16.0;
    
    return Container(
      height: buttonHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF355E3B), Color(0xFF6B8E23)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF355E3B).withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isLoading
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
                    'Signing in...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                'Sign In',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildRegistrationLink(bool isTablet, bool isMobile) {
    final fontSize = isTablet ? 16.0 : (isMobile ? 13.0 : 14.0);
    
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Don\'t have an account? ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: fontSize,
          ),
        ),
        TextButton(
          onPressed: _isLoading ? null : () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => RegisterPage()),
            );
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Sign Up',
            style: TextStyle(
              color: Color(0xFF355E3B),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugButtons() {
    return Container(
      margin: EdgeInsets.only(top: 32),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        children: [
          _buildDebugButton(
            'Debug Sign Out',
            () async {
              try {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Signed out successfully'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error signing out: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
          _buildDebugButton(
            'Debug Info',
            () {
              final user = FirebaseAuth.instance.currentUser;
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Debug Info'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current User: ${user?.email ?? 'None'}'),
                      Text('UID: ${user?.uid ?? 'None'}'),
                      Text('Email Verified: ${user?.emailVerified ?? false}'),
                      Text('Backend URL: $BACKEND_URL'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK', style: TextStyle(color: Color(0xFF355E3B))),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDebugButton(String text, VoidCallback onPressed) {
    return TextButton(
      onPressed: _isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 12,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 5,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}