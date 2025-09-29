import '../models/driver.dart';
import '../models/operator.dart';
import 'secure_auth_service.dart';

enum UserType {
  driver,
  operator,
  none,
}

class AuthResult {
  final bool success;
  final String? errorMessage;
  final UserType userType;
  final dynamic userData;

  AuthResult({
    required this.success,
    this.errorMessage,
    required this.userType,
    this.userData,
  });
}

class AuthService {
  // Add current user type
  UserType _currentUserType = UserType.none;
  UserType get currentUserType => _currentUserType;

  // In a real app, these would come from a secure database
  static final List<Driver> _drivers = [
    Driver(
      id: "RS789",  // Ricardo Santos
      name: "Ricardo Santos",
      password: SecureAuthService.hashPassword("driver123"),
    ),
    Driver(
      id: "DRV002",
      name: "Jane Driver",
      password: SecureAuthService.hashPassword("driver123"),
    ),
  ];

  static final List<Operator> _operators = [
    Operator(
      id: "OP001",
      name: "Admin Operator",
      password: SecureAuthService.hashPassword("admin123"),
      role: "admin",
    ),
    Operator(
      id: "OP002",
      name: "Support Operator",
      password: SecureAuthService.hashPassword("support123"),
      role: "support",
    ),
  ];

  Future<AuthResult> login(String id, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    print('Login attempt - ID: $id'); // Debug log

    // Check for driver with secure password verification
    Driver? foundDriver;
    for (var d in _drivers) {
      if (d.id == id && SecureAuthService.verifyPassword(password, d.password)) {
        foundDriver = d;
        break;
      }
    }

    if (foundDriver != null) {
      print('Driver found: ${foundDriver.name}'); // Debug log
      _currentUserType = UserType.driver;
      return AuthResult(
        success: true,
        userType: UserType.driver,
        userData: foundDriver,
      );
    }

    // Check for operator with secure password verification
    Operator? foundOperator;
    for (var o in _operators) {
      if (o.id == id && SecureAuthService.verifyPassword(password, o.password)) {
        foundOperator = o;
        break;
      }
    }

    if (foundOperator != null) {
      print('Operator found: ${foundOperator.name}'); // Debug log
      _currentUserType = UserType.operator;
      return AuthResult(
        success: true,
        userType: UserType.operator,
        userData: foundOperator,
      );
    }

    print('No matching user found'); // Debug log
    // No match found
    _currentUserType = UserType.none;
    return AuthResult(
      success: false,
      errorMessage: "Invalid ID or password",
      userType: UserType.none,
    );
  }
} 