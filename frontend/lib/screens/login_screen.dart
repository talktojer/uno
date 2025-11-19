import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();
  
  bool _isLoading = false;
  bool _obscurePin = true;
  String _errorMessage = '';
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadLastUsername();
    _setupPinAutoSubmit();
  }

  Future<void> _loadLastUsername() async {
    final lastUsername = await AuthService.getLastUsername();
    if (lastUsername != null && mounted) {
      _usernameController.text = lastUsername;
    }
  }

  void _setupPinAutoSubmit() {
    _pinController.addListener(() {
      if (_pinController.text.length == 4 && !_isLoading) {
        // Auto-submit when PIN is complete
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _pinController.text.length == 4) {
            _login();
          }
        });
      }
    });
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    _usernameFocusNode.dispose();
    _pinFocusNode.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_validateInputs()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await AuthService.login(
      _usernameController.text.trim(),
      _pinController.text,
    );

    if (result.isSuccess) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } else {
      setState(() {
        String error = result.error ?? 'Login failed';
        // Provide more user-friendly error messages
        if (error.contains('Invalid') || error.contains('incorrect')) {
          _errorMessage = 'Invalid username or PIN. Please try again.';
        } else if (error.contains('not found') || error.contains('does not exist')) {
          _errorMessage = 'Username not found. Please check your username or sign up.';
        } else if (error.contains('Network')) {
          _errorMessage = 'Connection error. Please check your internet and try again.';
        } else {
          _errorMessage = error;
        }
        // Focus on PIN field for retry
        _pinFocusNode.requestFocus();
        _pinController.clear();
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  bool _validateInputs() {
    final username = _usernameController.text.trim();
    final pin = _pinController.text;

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your username';
      });
      _usernameFocusNode.requestFocus();
      return false;
    }

    if (!AuthService.isValidUsername(username)) {
      setState(() {
        _errorMessage = 'Username must be 3-20 characters long';
      });
      _usernameFocusNode.requestFocus();
      return false;
    }

    if (pin.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your 4-digit PIN';
      });
      _pinFocusNode.requestFocus();
      return false;
    }

    if (!AuthService.isValidPin(pin)) {
      setState(() {
        _errorMessage = 'PIN must be exactly 4 digits';
      });
      _pinFocusNode.requestFocus();
      return false;
    }

    return true;
  }

  void _navigateToSignup() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const SignupScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFFf093fb),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    
                    // Logo and Title
                    _buildHeader(),
                    
                    const SizedBox(height: 60),
                    
                    // Login Form
                    _buildLoginForm(),
                    
                    const SizedBox(height: 40),
                    
                    // Sign Up Link
                    _buildSignupLink(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFf8f9fa)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.casino,
            size: 60,
            color: Color(0xFF667eea),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'UNO Game',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome back!',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          // Username Field
          _buildUsernameField(),
          
          const SizedBox(height: 24),
          
          // PIN Field
          _buildPinField(),
          
          const SizedBox(height: 32),
          
          // Error Message
          if (_errorMessage.isNotEmpty) _buildErrorMessage(),
          
          const SizedBox(height: 24),
          
          // Login Button
          _buildLoginButton(),
        ],
      ),
    );
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Username',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2d3748),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFe2e8f0)),
            color: const Color(0xFFf7fafc),
          ),
          child: TextField(
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            decoration: const InputDecoration(
              hintText: 'Enter your username',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              hintStyle: TextStyle(color: Color(0xFFa0aec0)),
            ),
            style: const TextStyle(fontSize: 16),
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _errorMessage = '';
              });
            },
            onSubmitted: (value) {
              // Move to PIN field when username is submitted
              _pinFocusNode.requestFocus();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPinField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PIN',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2d3748),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFe2e8f0)),
            color: const Color(0xFFf7fafc),
          ),
          child: TextField(
            controller: _pinController,
            focusNode: _pinFocusNode,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(
              hintText: 'Enter 4-digit PIN',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              hintStyle: const TextStyle(color: Color(0xFFa0aec0)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePin ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFFa0aec0),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePin = !_obscurePin;
                  });
                },
              ),
            ),
            style: const TextStyle(fontSize: 16, letterSpacing: 2),
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _errorMessage = '';
              });
            },
            onSubmitted: (value) {
              if (value.length == 4) {
                _login();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFfed7d7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFfc8181)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFe53e3e), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                color: Color(0xFFe53e3e),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF667eea),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Login',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildSignupLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
          ),
        ),
        GestureDetector(
          onTap: _navigateToSignup,
          child: const Text(
            'Sign Up',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
