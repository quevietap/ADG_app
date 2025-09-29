import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tinysync_app/services/secure_auth_service.dart';

class LoginPage extends StatefulWidget {
  final Function(Map<String, dynamic>)? onLoginSuccess;
  
  const LoginPage({super.key, this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _usernameError;
  String? _passwordError;
  bool _hasUsernameError = false;
  bool _hasPasswordError = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Clear previous errors
    setState(() {
      _errorMessage = null;
      _usernameError = null;
      _passwordError = null;
      _hasUsernameError = false;
      _hasPasswordError = false;
    });

    // Validate inputs
    bool hasErrors = false;

    if (_idController.text.trim().isEmpty) {
      setState(() {
        _usernameError = 'Please enter your username';
        _hasUsernameError = true;
      });
      hasErrors = true;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _passwordError = 'Please enter your password';
        _hasPasswordError = true;
      });
      hasErrors = true;
    }

    if (hasErrors) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔐 Attempting login for username: ${_idController.text.trim()}');

      // Skip basic network test for web to avoid CORS issues
      // The Supabase connection test below will verify connectivity

      // Connect to your Supabase database to check credentials
      print('🔍 Connecting to Supabase database...');

      try {
        // 🛡️ SANITIZE INPUT TO PREVENT SQL INJECTION
        final sanitizedUsername = SecureAuthService.sanitizeInput(_idController.text.trim());
        
        // Validate username format
        if (!SecureAuthService.isValidUsername(sanitizedUsername)) {
          setState(() {
            _usernameError = 'Invalid username format. Use only letters, numbers, underscore, and hyphen.';
            _hasUsernameError = true;
          });
          return;
        }
        
        // Query your users table in Supabase with the sanitized credentials
        final userResponse = await Supabase.instance.client
            .from('users')
            .select()
            .eq('username', sanitizedUsername)
            .maybeSingle();

        print('📡 Supabase response: $userResponse');

        if (userResponse == null) {
          setState(() {
            _usernameError = 'User not found. Please check your username.';
            _hasUsernameError = true;
          });
          return;
        }

        // Check if user is active (only if status column exists)
        if (userResponse['status'] != null && userResponse['status'] != 'active') {
          setState(() {
            _errorMessage =
                'Account is inactive. Please contact administrator.';
          });
          return;
        }

        // 🔐 PASSWORD VERIFICATION - PLAIN TEXT PASSWORDS
        final inputPassword = _passwordController.text;
        final storedPassword = userResponse['password'] as String?;
        
        print('🔍 Password verification debug:');
        print('  Input password: $inputPassword');
        print('  Stored password: ${storedPassword != null ? "Present" : "NULL"}');
        
        bool passwordValid = false;
        
        // Check plain text password
        if (storedPassword != null && storedPassword == inputPassword) {
          passwordValid = true;
          print('✅ Plain text password match');
        } else {
          print('❌ Password does not match');
        }
        
        if (!passwordValid) {
          print('❌ Password verification failed');
          print('💡 Try: admin123 (operators) or driver123 (drivers)');
        }
        
        if (passwordValid) {
          print('✅ Supabase authentication successful');

          // ✅ FIXED: Use callback instead of direct navigation for AuthWrapper
          if (widget.onLoginSuccess != null) {
            widget.onLoginSuccess!(userResponse);
          } else {
            // Fallback to old navigation method if no callback provided
            if (userResponse['role'] == 'operator') {
              Navigator.pushReplacementNamed(context, '/operator',
                  arguments: userResponse);
            } else if (userResponse['role'] == 'driver') {
              Navigator.pushReplacementNamed(context, '/driver',
                  arguments: userResponse);
            } else {
              setState(() {
                _errorMessage =
                    'Unknown user role. Please contact administrator.';
              });
            }
          }
        } else {
          setState(() {
            _passwordError = 'Incorrect password. Please try again.';
            _hasPasswordError = true;
          });
        }
      } catch (connectionError) {
        print('❌ Supabase connection failed: $connectionError');
        print('❌ Error type: ${connectionError.runtimeType}');
        print('❌ Error details: ${connectionError.toString()}');

        // More specific error handling
        String errorMessage = 'Cannot connect to database. ';
        if (connectionError.toString().contains('SocketException')) {
          errorMessage += 'Network connection failed. Please check your WiFi.';
        } else if (connectionError.toString().contains('HandshakeException')) {
          errorMessage +=
              'SSL/TLS connection failed. Please check your network.';
        } else if (connectionError.toString().contains('HttpException')) {
          errorMessage += 'HTTP request failed. Please check your connection.';
        } else if (connectionError.toString().contains('TimeoutException')) {
          errorMessage += 'Connection timeout. Please try again.';
        } else {
          errorMessage += 'Please check your internet connection.';
        }

        setState(() {
          _errorMessage = errorMessage;
        });
        return;
      }
    } catch (e) {
      print('❌ Login error: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Error details: ${e.toString()}');
      setState(() {
        _errorMessage =
            'Login failed. Please check your credentials and try again.';
      });
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2A2A2A),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_shipping,
                          size: 50,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // App Title
                      Text(
                        'TinySync',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Driver Monitoring System',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey[400],
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Error Message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.inter(
                                    color: Colors.red,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Username Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            child: TextFormField(
                              controller: _idController,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Username',
                                prefixIcon: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasUsernameError
                                        ? Colors.red
                                        : Colors.grey.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasUsernameError
                                        ? Colors.red
                                        : Colors.grey.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasUsernameError
                                        ? Colors.red
                                        : const Color(0xFF007AFF),
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                labelStyle: GoogleFonts.inter(
                                  color: _hasUsernameError
                                      ? Colors.red
                                      : Colors.grey[400],
                                  fontSize: 14,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              onChanged: (value) {
                                if (_hasUsernameError && value.isNotEmpty) {
                                  setState(() {
                                    _hasUsernameError = false;
                                    _usernameError = null;
                                  });
                                }
                              },
                            ),
                          ),
                          if (_usernameError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 12),
                              child: Text(
                                _usernameError!,
                                style: GoogleFonts.inter(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Password Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(
                                  Icons.lock,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasPasswordError
                                        ? Colors.red
                                        : Colors.grey.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasPasswordError
                                        ? Colors.red
                                        : Colors.grey.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _hasPasswordError
                                        ? Colors.red
                                        : const Color(0xFF007AFF),
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                labelStyle: GoogleFonts.inter(
                                  color: _hasPasswordError
                                      ? Colors.red
                                      : Colors.grey[400],
                                  fontSize: 14,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              onChanged: (value) {
                                if (_hasPasswordError && value.isNotEmpty) {
                                  setState(() {
                                    _hasPasswordError = false;
                                    _passwordError = null;
                                  });
                                }
                              },
                            ),
                          ),
                          if (_passwordError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 12),
                              child: Text(
                                _passwordError!,
                                style: GoogleFonts.inter(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Login Button
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor:
                                const Color(0xFF007AFF).withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey[600],
                          ).copyWith(
                            overlayColor:
                                WidgetStateProperty.resolveWith<Color?>(
                              (Set<WidgetState> states) {
                                if (states.contains(WidgetState.pressed)) {
                                  return Colors.white.withOpacity(0.1);
                                }
                                return null;
                              },
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Text(
                                  'Sign In',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
