import 'package:bcrypt/bcrypt.dart';
import 'dart:convert';
import 'dart:math';

/// 🔐 SECURE AUTHENTICATION SERVICE
/// Handles password hashing, validation, and security measures
class SecureAuthService {
  static const int _sessionTimeoutHours = 8; // 8 hours max session
  static const int _maxLoginAttempts = 5; // Max failed attempts
  static const int _lockoutDurationMinutes = 30; // 30 min lockout

  /// 🔒 Hash a password using bcrypt
  static String hashPassword(String password) {
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }
    
    // Generate salt and hash password
    final salt = BCrypt.gensalt();
    return BCrypt.hashpw(password, salt);
  }

  /// ✅ Verify a password against its hash
  static bool verifyPassword(String password, String hash) {
    if (password.isEmpty || hash.isEmpty) {
      return false;
    }
    
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      // Log error for debugging (in production, use proper logging)
      // print('❌ Password verification error: $e');
      return false;
    }
  }

  /// 🛡️ Validate password strength
  static PasswordValidationResult validatePasswordStrength(String password) {
    if (password.isEmpty) {
      return PasswordValidationResult(
        isValid: false,
        errors: ['Password is required'],
      );
    }

    final errors = <String>[];

    // Length check
    if (password.length < 8) {
      errors.add('Password must be at least 8 characters long');
    }

    // Complexity checks
    if (!password.contains(RegExp(r'[A-Z]'))) {
      errors.add('Password must contain at least one uppercase letter');
    }

    if (!password.contains(RegExp(r'[a-z]'))) {
      errors.add('Password must contain at least one lowercase letter');
    }

    if (!password.contains(RegExp(r'[0-9]'))) {
      errors.add('Password must contain at least one number');
    }

    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      errors.add('Password must contain at least one special character');
    }

    // Common password check
    final commonPasswords = [
      'password', '123456', 'admin', 'admin123', 'driver123', 'operator123',
      'password123', 'qwerty', 'abc123', 'letmein', 'welcome', 'monkey'
    ];
    
    if (commonPasswords.contains(password.toLowerCase())) {
      errors.add('Password is too common, please choose a stronger password');
    }

    return PasswordValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// 🔐 Generate a secure random token
  static String generateSecureToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// ⏰ Check if session is expired
  static bool isSessionExpired(DateTime loginTime) {
    final now = DateTime.now();
    final sessionDuration = now.difference(loginTime);
    return sessionDuration.inHours >= _sessionTimeoutHours;
  }

  /// 🚫 Check if account is locked due to failed attempts
  static bool isAccountLocked(DateTime? lastFailedAttempt, int failedAttempts) {
    if (lastFailedAttempt == null || failedAttempts < _maxLoginAttempts) {
      return false;
    }

    final now = DateTime.now();
    final lockoutDuration = now.difference(lastFailedAttempt);
    return lockoutDuration.inMinutes < _lockoutDurationMinutes;
  }

  /// 🔍 Sanitize input to prevent SQL injection
  static String sanitizeInput(String input) {
    if (input.isEmpty) return '';
    
    // Remove potentially dangerous characters
    String sanitized = input;
    
    // Remove SQL injection characters
    sanitized = sanitized.replaceAll(';', '');
    sanitized = sanitized.replaceAll("'", '');
    sanitized = sanitized.replaceAll('"', '');
    sanitized = sanitized.replaceAll('\\', '');
    
    // Remove script tags
    sanitized = sanitized.replaceAll(RegExp(r'<script.*?</script>', caseSensitive: false), '');
    
    return sanitized.trim();
  }

  /// 🛡️ Validate username format
  static bool isValidUsername(String username) {
    if (username.isEmpty || username.length < 3) return false;
    
    // Allow alphanumeric, underscore, and hyphen only
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(username);
  }

  /// 🔐 Create a secure password reset token
  static String generatePasswordResetToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 📊 Get password strength score (0-100)
  static int getPasswordStrengthScore(String password) {
    int score = 0;
    
    if (password.length >= 8) score += 20;
    if (password.length >= 12) score += 10;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 20;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 20;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score += 15;
    
    return score;
  }
}

/// 📋 Password validation result
class PasswordValidationResult {
  final bool isValid;
  final List<String> errors;

  PasswordValidationResult({
    required this.isValid,
    required this.errors,
  });

  String get errorMessage => errors.join(', ');
}
