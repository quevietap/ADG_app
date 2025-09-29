import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service to handle authentication persistence for driver safety
/// Prevents drivers from having to login while driving
class AuthPersistenceService {
  static const String _authKey = 'user_auth_data';
  static const String _loginTimestampKey = 'login_timestamp';
  static const int _sessionTimeoutHours = 24; // 24 hours session timeout

  /// Save authentication data to persist login state
  static Future<void> saveAuthData(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save user data
      await prefs.setString(_authKey, json.encode(userData));
      
      // Save login timestamp
      await prefs.setInt(_loginTimestampKey, DateTime.now().millisecondsSinceEpoch);
      
      print('✅ Authentication data saved for user: ${userData['username']}');
    } catch (e) {
      print('❌ Error saving authentication data: $e');
    }
  }

  /// Check if user is already logged in and session is valid
  static Future<Map<String, dynamic>?> getValidAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if auth data exists
      final authDataString = prefs.getString(_authKey);
      final loginTimestamp = prefs.getInt(_loginTimestampKey);
      
      if (authDataString == null || loginTimestamp == null) {
        print('🔐 No saved authentication data found - showing login screen');
        return null;
      }
      
      // Check if session is still valid (not expired)
      final loginTime = DateTime.fromMillisecondsSinceEpoch(loginTimestamp);
      final now = DateTime.now();
      final sessionDuration = now.difference(loginTime);
      
      if (sessionDuration.inHours >= _sessionTimeoutHours) {
        print('⏰ Authentication session expired (${sessionDuration.inHours} hours old)');
        await clearAuthData(); // Clear expired session
        return null;
      }
      
      // Parse and return user data
      final userData = json.decode(authDataString) as Map<String, dynamic>;
      print('✅ Valid authentication found for user: ${userData['username']} (${sessionDuration.inHours}h old)');
      
      return userData;
    } catch (e) {
      print('❌ Error retrieving authentication data: $e');
      return null;
    }
  }

  /// Clear authentication data (logout)
  static Future<void> clearAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authKey);
      await prefs.remove(_loginTimestampKey);
      print('✅ Authentication data cleared');
    } catch (e) {
      print('❌ Error clearing authentication data: $e');
    }
  }

  /// Check if user is currently logged in
  static Future<bool> isLoggedIn() async {
    final authData = await getValidAuthData();
    return authData != null;
  }

  /// Get current user role
  static Future<String?> getCurrentUserRole() async {
    final authData = await getValidAuthData();
    return authData?['role'];
  }

  /// Get current user data
  static Future<Map<String, dynamic>?> getCurrentUserData() async {
    return await getValidAuthData();
  }

  /// Extend session (update login timestamp)
  static Future<void> extendSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_loginTimestampKey, DateTime.now().millisecondsSinceEpoch);
      print('✅ Session extended');
    } catch (e) {
      print('❌ Error extending session: $e');
    }
  }

  /// Force clear all authentication data (for fresh installs)
  static Future<void> forceClearAllAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Clear ALL SharedPreferences data
      print('✅ All authentication data force cleared - fresh install mode');
    } catch (e) {
      print('❌ Error force clearing authentication data: $e');
    }
  }
}
