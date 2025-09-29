import 'package:flutter/material.dart';
import '../services/auth_persistence_service.dart';
// ✅ Removed push notification service - using database notifications!
import '../pages/login_page/login_page.dart';
import '../pages/operator/operator_screen.dart';

/// Smart wrapper that handles authentication state and routing
/// Prevents drivers from having to login while driving
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  /// Check authentication state on app startup
  Future<void> _checkAuthState() async {
    try {
      print('🔐 Checking authentication state...');

      // Check if user is already logged in
      final authData = await AuthPersistenceService.getValidAuthData();

      if (authData != null) {
        print(
            '✅ User already logged in: ${authData['username']} (${authData['role']})');

        // ✅ FCM removed - using database notifications!

        setState(() {
          _userData = authData;
          _isLoading = false;
        });
      } else {
        print('🔐 No valid authentication found, showing login page');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error checking authentication state: $e');
      setState(() {
        _errorMessage = 'Authentication check failed: $e';
        _isLoading = false;
      });
    }
  }

  /// Handle successful login
  void _onLoginSuccess(Map<String, dynamic> userData) async {
    // Save authentication data
    await AuthPersistenceService.saveAuthData(userData);

    // Save FCM token for push notifications
    // ✅ FCM removed - using database notifications!
    print('✅ User logged in: ${userData['id']} (${userData['role']})');

    setState(() {
      _userData = userData;
    });
  }

  /// Handle logout
  void _onLogout() async {
    // Clear authentication data
    await AuthPersistenceService.clearAuthData();

    setState(() {
      _userData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while checking authentication
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Checking authentication...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Show error screen if authentication check failed
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Authentication Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                  });
                  _checkAuthState();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // User is logged in - route to appropriate screen
    if (_userData != null) {
      final userRole = _userData!['role'];

      switch (userRole) {
        case 'driver':
          // Navigate to the DriverScreen using named route
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context, rootNavigator: true).pushReplacementNamed(
              '/driver',
              arguments: _userData,
            );
          });
          // Return a temporary loading screen while navigating
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Driver Portal...'),
                ],
              ),
            ),
          );
        case 'operator':
          return OperatorScreen(
            userData: _userData,
          );
        default:
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_outlined,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unknown User Role',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'User role "$userRole" is not recognized.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _onLogout,
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
          );
      }
    }

    // User is not logged in - show login page
    return LoginPage(
      onLoginSuccess: _onLoginSuccess,
    );
  }
}
