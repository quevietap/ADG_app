import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  factory AppSettingsService() => _instance;
  AppSettingsService._internal();

  // Theme settings
  ThemeMode _themeMode = ThemeMode.dark;
  String _selectedLanguage = 'English';
  bool _notificationsEnabled = true;

  // Getters
  ThemeMode get themeMode => _themeMode;
  String get selectedLanguage => _selectedLanguage;
  bool get notificationsEnabled => _notificationsEnabled;

  // Supported languages
  final Map<String, String> _supportedLanguages = {
    'English': 'en',
    'Filipino': 'fil',
    'Spanish': 'es',
  };

  Map<String, String> get supportedLanguages => _supportedLanguages;

  // Initialize settings from storage
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load theme setting (removed Auto option)
    final themeString = prefs.getString('app_theme_mode') ?? 'dark';
    _themeMode = themeString == 'light' ? ThemeMode.light : ThemeMode.dark;

    // Load language setting
    _selectedLanguage = prefs.getString('app_language') ?? 'English';

    // Load notifications setting
    _notificationsEnabled = prefs.getBool('app_notifications_enabled') ?? true;

    notifyListeners();
  }

  // Update theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'app_theme_mode', mode == ThemeMode.light ? 'light' : 'dark');
      notifyListeners();
    }
  }

  // Update language
  Future<void> setLanguage(String language) async {
    if (_selectedLanguage != language &&
        _supportedLanguages.containsKey(language)) {
      _selectedLanguage = language;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', language);
      notifyListeners();
    }
  }

  // Update notifications
  Future<void> setNotificationsEnabled(bool enabled) async {
    if (_notificationsEnabled != enabled) {
      _notificationsEnabled = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_notifications_enabled', enabled);

      // Handle device-level notification subscription
      if (enabled) {
        await _enableDeviceNotifications();
      } else {
        await _disableDeviceNotifications();
      }

      notifyListeners();
    }
  }

  // Device-level notification management
  Future<void> _enableDeviceNotifications() async {
    // TODO: Implement actual notification service subscription
    // This would typically involve:
    // - Requesting notification permissions
    // - Subscribing to FCM topics
    // - Enabling local notifications
    debugPrint('✅ Device notifications enabled');
  }

  Future<void> _disableDeviceNotifications() async {
    // TODO: Implement actual notification service unsubscription
    // This would typically involve:
    // - Canceling all local notifications
    // - Unsubscribing from FCM topics
    // - Clearing notification channels
    debugPrint('❌ Device notifications disabled');
  }

  // Get light theme
  ThemeData get lightTheme => ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        cardColor: Colors.white,
        primaryColor: const Color(0xFF007AFF),
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF007AFF),
          secondary: Color(0xFF34C759),
          surface: Colors.white,
          error: Color(0xFFFF3B30),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF1C1C1E),
          onError: Colors.white,
        ),
        // Enhanced AppBar theme for light mode
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1C1C1E),
          elevation: 0.5,
          shadowColor: Colors.black12,
          iconTheme: IconThemeData(color: Color(0xFF1C1C1E)),
          actionsIconTheme: IconThemeData(color: Color(0xFF1C1C1E)),
          titleTextStyle: TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        // Enhanced bottom navigation for light mode
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF007AFF),
          unselectedItemColor: Color(0xFF8E8E93),
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
        // Enhanced card theme for light mode
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.08),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
        // Enhanced text theme for light mode
        textTheme: const TextTheme(
          headlineLarge:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.bold),
          headlineMedium:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600),
          headlineSmall:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600),
          titleLarge:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Color(0xFF1C1C1E)),
          bodyMedium: TextStyle(color: Color(0xFF1C1C1E)),
          bodySmall: TextStyle(color: Color(0xFF8E8E93)),
          labelLarge:
              TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: Color(0xFF8E8E93)),
          labelSmall: TextStyle(color: Color(0xFF8E8E93)),
        ),
        // Enhanced switch theme for light mode
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF);
            }
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade400;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF).withOpacity(0.5);
            }
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade300;
            }
            return Colors.grey.shade300;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF).withOpacity(0.1);
            }
            return Colors.grey.withOpacity(0.1);
          }),
        ),
        // Enhanced list tile theme
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF8E8E93),
          textColor: Color(0xFF1C1C1E),
          tileColor: Colors.transparent,
          selectedTileColor: Color(0xFFF2F2F7),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        // Enhanced icon theme
        iconTheme: const IconThemeData(
          color: Color(0xFF8E8E93),
          size: 24,
        ),
        primaryIconTheme: const IconThemeData(
          color: Color(0xFF007AFF),
          size: 24,
        ),
        // Enhanced divider theme
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade200,
          thickness: 0.5,
          space: 1,
        ),
        // Enhanced dialog theme
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 16,
          ),
        ),
        // Enhanced snackbar theme
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
        ),
      );

  // Get dark theme
  ThemeData get darkTheme => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        cardColor: const Color(0xFF1C1C1E),
        primaryColor: const Color(0xFF007AFF),
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007AFF),
          secondary: Color(0xFF30D158),
          surface: Color(0xFF1C1C1E),
          error: Color(0xFFFF453A),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.white,
        ),
        // Enhanced AppBar theme for dark mode
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 0.5,
          shadowColor: Colors.white10,
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        // Enhanced bottom navigation for dark mode
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF000000),
          selectedItemColor: Color(0xFF007AFF),
          unselectedItemColor: Color(0xFF8E8E93),
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          showSelectedLabels: true,
          showUnselectedLabels: true,
        ),
        // Enhanced card theme for dark mode
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1C1E),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade800, width: 0.5),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
        // Enhanced text theme for dark mode
        textTheme: const TextTheme(
          headlineLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          headlineMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          headlineSmall:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          titleLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          titleMedium:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          titleSmall:
              TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Color(0xFF8E8E93)),
          labelLarge:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: Color(0xFF8E8E93)),
          labelSmall: TextStyle(color: Color(0xFF8E8E93)),
        ),
        // Enhanced switch theme for dark mode
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF);
            }
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade600;
            }
            return Colors.grey.shade400;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF).withOpacity(0.5);
            }
            if (states.contains(WidgetState.disabled)) {
              return Colors.grey.shade700;
            }
            return Colors.grey.shade700;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF007AFF).withOpacity(0.1);
            }
            return Colors.grey.withOpacity(0.1);
          }),
        ),
        // Enhanced list tile theme
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF8E8E93),
          textColor: Colors.white,
          tileColor: Colors.transparent,
          selectedTileColor: Color(0xFF2C2C2E),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        // Enhanced icon theme
        iconTheme: const IconThemeData(
          color: Color(0xFF8E8E93),
          size: 24,
        ),
        primaryIconTheme: const IconThemeData(
          color: Color(0xFF007AFF),
          size: 24,
        ),
        // Enhanced divider theme
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade800,
          thickness: 0.5,
          space: 1,
        ),
        // Enhanced dialog theme
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF1C1C1E),
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        // Enhanced snackbar theme
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2C2C2E),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
        ),
      );
}
