import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinysync_app/services/secure_auth_service.dart';

/// ⏰ SESSION MANAGEMENT SERVICE
/// Handles secure session management with timeout and security measures
class SessionService {
  static const String _sessionKey = 'user_session';
  static const String _loginTimeKey = 'login_time';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const String _lastFailedAttemptKey = 'last_failed_attempt';
  static const String _isLockedKey = 'account_locked';

  /// 🔐 Create a new secure session
  static Future<void> createSession(String userId, String userRole) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    
    // Store session data
    await prefs.setString(_sessionKey, userId);
    await prefs.setString(_loginTimeKey, now.toIso8601String());
    await prefs.setString('user_role', userRole);
    
    // Clear any previous failed attempts
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lastFailedAttemptKey);
    await prefs.remove(_isLockedKey);
    
    print('✅ Secure session created for user: $userId');
  }

  /// ✅ Check if current session is valid
  static Future<bool> isSessionValid() async {
    final prefs = await SharedPreferences.getInstance();
    
    final sessionData = prefs.getString(_sessionKey);
    final loginTimeStr = prefs.getString(_loginTimeKey);
    
    if (sessionData == null || loginTimeStr == null) {
      return false;
    }
    
    try {
      final loginTime = DateTime.parse(loginTimeStr);
      
      // Check if session is expired
      if (SecureAuthService.isSessionExpired(loginTime)) {
        await clearSession();
        print('⏰ Session expired, clearing session');
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ Error parsing session time: $e');
      await clearSession();
      return false;
    }
  }

  /// 👤 Get current user ID from session
  static Future<String?> getCurrentUserId() async {
    if (!await isSessionValid()) {
      return null;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// 🎭 Get current user role from session
  static Future<String?> getCurrentUserRole() async {
    if (!await isSessionValid()) {
      return null;
    }
    
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  /// 🚪 Clear current session (logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_sessionKey);
    await prefs.remove(_loginTimeKey);
    await prefs.remove('user_role');
    
    print('🚪 Session cleared');
  }

  /// 🚫 Record failed login attempt
  static Future<void> recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    
    final currentAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final newAttempts = currentAttempts + 1;
    
    await prefs.setInt(_failedAttemptsKey, newAttempts);
    await prefs.setString(_lastFailedAttemptKey, DateTime.now().toIso8601String());
    
    print('🚫 Failed login attempt recorded: $newAttempts');
    
    // Check if account should be locked
    if (newAttempts >= 5) {
      await prefs.setBool(_isLockedKey, true);
      print('🔒 Account locked due to too many failed attempts');
    }
  }

  /// 🔓 Check if account is locked
  static Future<bool> isAccountLocked() async {
    final prefs = await SharedPreferences.getInstance();
    
    final isLocked = prefs.getBool(_isLockedKey) ?? false;
    final lastFailedAttemptStr = prefs.getString(_lastFailedAttemptKey);
    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    
    if (!isLocked || lastFailedAttemptStr == null) {
      return false;
    }
    
    try {
      final lastFailedAttempt = DateTime.parse(lastFailedAttemptStr);
      return SecureAuthService.isAccountLocked(lastFailedAttempt, failedAttempts);
    } catch (e) {
      print('❌ Error parsing lockout time: $e');
      return false;
    }
  }

  /// ⏰ Get remaining session time in minutes
  static Future<int> getRemainingSessionTime() async {
    final prefs = await SharedPreferences.getInstance();
    final loginTimeStr = prefs.getString(_loginTimeKey);
    
    if (loginTimeStr == null) {
      return 0;
    }
    
    try {
      final loginTime = DateTime.parse(loginTimeStr);
      final now = DateTime.now();
      final sessionDuration = now.difference(loginTime);
      final remainingMinutes = (8 * 60) - sessionDuration.inMinutes; // 8 hours max
      
      return remainingMinutes > 0 ? remainingMinutes : 0;
    } catch (e) {
      print('❌ Error calculating session time: $e');
      return 0;
    }
  }

  /// 🔄 Refresh session (extend login time)
  static Future<void> refreshSession() async {
    if (!await isSessionValid()) {
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_sessionKey);
    final userRole = prefs.getString('user_role');
    
    if (userId != null && userRole != null) {
      await createSession(userId, userRole);
      print('🔄 Session refreshed');
    }
  }

  /// 📊 Get session statistics
  static Future<Map<String, dynamic>> getSessionStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'isValid': await isSessionValid(),
      'userId': await getCurrentUserId(),
      'userRole': await getCurrentUserRole(),
      'remainingTime': await getRemainingSessionTime(),
      'isLocked': await isAccountLocked(),
      'failedAttempts': prefs.getInt(_failedAttemptsKey) ?? 0,
    };
  }

  /// 🧹 Clear all session data (for testing/reset)
  static Future<void> clearAllSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_sessionKey);
    await prefs.remove(_loginTimeKey);
    await prefs.remove('user_role');
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lastFailedAttemptKey);
    await prefs.remove(_isLockedKey);
    
    print('🧹 All session data cleared');
  }
}
