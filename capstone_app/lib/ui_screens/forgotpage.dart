import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ForgotPassPage extends StatefulWidget {
  @override
  _ForgotPassPageState createState() => _ForgotPassPageState();
}

class _ForgotPassPageState extends State<ForgotPassPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _errorMessage = '';
  String _successMessage = '';
  bool _isLoading = false;
  bool _isOtpSent = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  // Countdown timer for resend OTP
  int _resendCountdown = 0;
  Timer? _resendTimer;

  // Update your backend URL here - make sure it matches your Flask server
  static const String BACKEND_URL = 'https://capstone-production-9474.up.railway.app';

  @override
  void initState() {
    super.initState();
    
    // Test image loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(AssetImage('assets/images/vic.jpg'), context).catchError((error) {
        print('Background image precache error: $error');
      });
      precacheImage(AssetImage('assets/images/viclogo.png'), context).catchError((error) {
        print('Logo image precache error: $error');
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    setState(() {
      _resendCountdown = 60; // 60 seconds countdown
    });

    _resendTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorMessage = '';
      _successMessage = '';
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();

      print('=== SEND OTP REQUEST ===');
      print('Email: $email');
      print('Backend URL: $BACKEND_URL/api/send_otp');

      final response = await http.post(
        Uri.parse('$BACKEND_URL/api/send_otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
        }),
      ).timeout(Duration(seconds: 15));

      print('Send OTP response status: ${response.statusCode}');
      print('Send OTP response body: ${response.body}');

      if (response.body.isEmpty) {
        setState(() {
          _errorMessage = 'Empty response from server. Check if your Flask server is running.';
        });
        return;
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _isOtpSent = true;
          _successMessage = 'OTP sent successfully to your email. Please check your inbox.';
          _errorMessage = '';
        });
        _startResendCountdown();
        print('✓ OTP sent successfully');
      } else {
        setState(() {
          _errorMessage = responseData['error'] ?? 'Failed to send OTP. Please try again.';
        });
        print('✗ Send OTP failed: ${responseData['error']}');
      }

    } on http.ClientException catch (e) {
      print('✗ HTTP ClientException: $e');
      setState(() {
        _errorMessage = 'Cannot reach server. Please check if your Flask server is running on $BACKEND_URL';
      });
    } on FormatException catch (e) {
      print('✗ JSON Format Exception: $e');
      setState(() {
        _errorMessage = 'Server returned invalid response format.';
      });
    } catch (e, stackTrace) {
      print('✗ Unexpected error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Unexpected error occurred: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPasswordController.text.trim() != _confirmPasswordController.text.trim()) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
      _successMessage = '';
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final otp = _otpController.text.trim();
      final newPassword = _newPasswordController.text.trim();

      print('=== RESET PASSWORD REQUEST ===');
      print('Email: $email');
      print('OTP: $otp');
      print('New password length: ${newPassword.length}');

      final response = await http.post(
        Uri.parse('$BACKEND_URL/api/reset_password'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'new_password': newPassword,
        }),
      ).timeout(Duration(seconds: 15));

      print('Reset password response status: ${response.statusCode}');
      print('Reset password response body: ${response.body}');

      if (response.body.isEmpty) {
        setState(() {
          _errorMessage = 'Empty response from server. Check if your Flask server is running.';
        });
        return;
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Password reset successfully! Please login with your new password.')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: Duration(seconds: 4),
            ),
          );

          // Navigate back to login page
          Navigator.of(context).pop();
        }
        print('✓ Password reset successful');
      } else {
        setState(() {
          _errorMessage = responseData['error'] ?? 'Failed to reset password. Please try again.';
        });
        print('✗ Password reset failed: ${responseData['error']}');
      }

    } on http.ClientException catch (e) {
      print('✗ HTTP ClientException: $e');
      setState(() {
        _errorMessage = 'Cannot reach server. Please check if your Flask server is running on $BACKEND_URL';
      });
    } on FormatException catch (e) {
      print('✗ JSON Format Exception: $e');
      setState(() {
        _errorMessage = 'Server returned invalid response format.';
      });
    } catch (e, stackTrace) {
      print('✗ Unexpected error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Unexpected error occurred: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
    final logoSize = isTablet ? 80.0 : (isMobile ? 60.0 : 70.0);
    final titleFontSize = isTablet ? 28.0 : (isMobile ? 22.0 : 24.0);
    final subtitleFontSize = isTablet ? 16.0 : (isMobile ? 14.0 : 15.0);

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
                          if (!isMobile) Flexible(child: SizedBox(height: 20)),
                          
                          // Header with logo
                          _buildHeader(logoSize, titleFontSize, subtitleFontSize),
                          
                          SizedBox(height: isTablet ? 40 : (isMobile ? 24 : 32)),
                          
                          // Form Card
                          _buildFormCard(cardPadding, isMobile, isTablet),
                          
                          if (!isMobile) Flexible(child: SizedBox(height: 20)),
                          
                          // Back to Login Link
                          _buildBackToLoginLink(isTablet, isMobile),
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
        // Logo with circular background
        Hero(
          tag: 'reset_logo',
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
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      color: Color(0xFF355E3B).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_reset_outlined,
                      size: logoSize * 0.5,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Reset Password',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.0,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: Offset(2, 2),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Text(
          _isOtpSent 
              ? 'Enter OTP and create new password'
              : 'Enter your email to receive reset code',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w300,
            color: Colors.white.withOpacity(0.95),
            letterSpacing: 0.5,
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

  Widget _buildFormCard(double cardPadding, bool isMobile, bool isTablet) {
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
              _isOtpSent ? 'Almost There!' : 'Forgot Your Password?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 24 : (isMobile ? 18 : 20),
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3436),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isOtpSent 
                  ? 'Complete the steps below to reset your password'
                  : 'Don\'t worry, we\'ll help you get back in',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 16 : (isMobile ? 12 : 14),
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: isTablet ? 32 : (isMobile ? 20 : 24)),
            
            // Email TextField (always visible)
            _buildTextField(
              controller: _emailController,
              labelText: 'Email Address',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: _isOtpSent ? TextInputAction.next : TextInputAction.done,
              enabled: !_isOtpSent && !_isLoading, // Disable after OTP is sent
              onSubmitted: (_) => _isOtpSent ? null : (_isLoading ? null : _sendOtp()),
            ),
            
            // Show OTP and password fields only after OTP is sent
            if (_isOtpSent) ...[
              SizedBox(height: 16),
              
              // OTP TextField
              _buildTextField(
                controller: _otpController,
                labelText: 'Enter 6-digit OTP',
                prefixIcon: Icons.security_outlined,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 6,
              ),
              SizedBox(height: 16),
              
              // New Password TextField
              _buildTextField(
                controller: _newPasswordController,
                labelText: 'New Password',
                prefixIcon: Icons.lock_outline,
                obscureText: _obscureNewPassword,
                textInputAction: TextInputAction.next,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Color(0xFF6B8E23),
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
              ),
              SizedBox(height: 16),
              
              // Confirm Password TextField
              _buildTextField(
                controller: _confirmPasswordController,
                labelText: 'Confirm New Password',
                prefixIcon: Icons.lock_outline,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Color(0xFF6B8E23),
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
                onSubmitted: (_) => _isLoading ? null : _resetPassword(),
              ),
            ],
            
            SizedBox(height: 24),
            
            // Success Message
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              height: _successMessage.isNotEmpty ? null : 0,
              child: _successMessage.isNotEmpty ? _buildSuccessMessage() : SizedBox.shrink(),
            ),
            
            if (_successMessage.isNotEmpty) SizedBox(height: 16),
            
            // Error Message
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              height: _errorMessage.isNotEmpty ? null : 0,
              child: _errorMessage.isNotEmpty ? _buildErrorMessage() : SizedBox.shrink(),
            ),
            
            if (_errorMessage.isNotEmpty) SizedBox(height: 16),
            
            // Action Button
            _buildActionButton(isTablet, isMobile),
            
            // Resend OTP Button (only show when OTP is sent and countdown is 0)
            if (_isOtpSent) ...[
              SizedBox(height: 16),
              _buildResendOtpButton(isTablet, isMobile),
            ],
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
    bool enabled = true,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: enabled ? Colors.grey[50] : Colors.grey[100],
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
        enabled: enabled && !_isLoading,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        maxLength: maxLength,
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        style: TextStyle(
          fontSize: 16,
          color: enabled ? Colors.black87 : Colors.grey[600],
        ),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: enabled ? Colors.grey[600] : Colors.grey[500]),
          prefixIcon: Icon(prefixIcon, color: enabled ? Color(0xFF355E3B) : Colors.grey[500]),
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
          fillColor: enabled ? Colors.grey[50] : Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          counterText: '', // Hide character counter
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'This field is required';
          }
          if (labelText == 'Email Address' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Please enter a valid email';
          }
          if (labelText.contains('OTP') && value.length != 6) {
            return 'OTP must be 6 digits';
          }
          if (labelText.contains('Password') && value.length < 6) {
            return 'Password must be at least 6 characters';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSuccessMessage() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _successMessage,
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
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
            offset: Offset(2, 0),
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

  Widget _buildActionButton(bool isTablet, bool isMobile) {
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
        onPressed: _isLoading ? null : (_isOtpSent ? _resetPassword : _sendOtp),
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
                    _isOtpSent ? 'Resetting...' : 'Sending...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                _isOtpSent ? 'Reset Password' : 'Send Reset Code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildResendOtpButton(bool isTablet, bool isMobile) {
    final fontSize = isTablet ? 16.0 : (isMobile ? 14.0 : 15.0);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Didn\'t receive the code? ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: fontSize,
          ),
        ),
        if (_resendCountdown > 0)
          Text(
            'Resend in ${_resendCountdown}s',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: fontSize,
            ),
          )
        else
          TextButton(
            onPressed: _isLoading ? null : () {
              // Clear OTP field and resend
              _otpController.clear();
              _sendOtp();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Resend Code',
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

  Widget _buildBackToLoginLink(bool isTablet, bool isMobile) {
    final fontSize = isTablet ? 16.0 : (isMobile ? 14.0 : 15.0);
    
    return Container(
      margin: EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Remember your password? ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: fontSize,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 5,
                  offset: Offset(1, 1),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : () {
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Sign In',
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 5,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}