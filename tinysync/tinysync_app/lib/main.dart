import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ✅ Removed Firebase - not needed for notifications!
import 'pages/driver/status_page.dart';
import 'pages/driver/dashboard_page.dart';
import 'pages/driver/profile_page.dart';
import 'pages/driver/history_page.dart';
import 'pages/driver/overdue_trips_page.dart';
import 'pages/login_page/login_page.dart';
import 'pages/settings_page.dart';
import 'pages/operator/operator_screen.dart';
import 'services/app_settings_service.dart';
// ✅ Removed push notification service - using existing database notifications!
import 'services/notification_service.dart';
// ✅ Removed navigation service - no FCM dependencies!
import 'services/overdue_trip_service.dart';
import 'services/app_lifecycle_service.dart';
import 'services/location_service.dart';
import 'widgets/auth_wrapper.dart';
import 'widgets/driver_notification_alert.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ NO MORE FIREBASE HEADACHES!

  // Initialize Supabase (required for database)
  try {
    await Supabase.initialize(
      url: 'https://hhsaglfvhdlgsbqmcwbw.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
    );
    print('✅ Supabase initialized - all we need for notifications!');
  } catch (e) {
    print('⚠️ Supabase initialization failed: $e');
    print('📱 App will continue with limited features');
  }

  // Initialize app settings
  try {
    await AppSettingsService().loadSettings();
    print('✅ App settings loaded successfully');
  } catch (e) {
    print('⚠️ App settings loading failed: $e');
    print('📱 App will continue with default settings');
  }

  // ✅ NO MORE PUSH NOTIFICATION SERVICE - your existing system works!

  // Initialize notification service (optional)
  try {
    await NotificationService().initialize();

    // Start overdue tracking system
    NotificationService().startOverdueTracking();

    // Start processing scheduled notifications every minute
    Timer.periodic(const Duration(minutes: 1), (timer) {
      NotificationService().processScheduledNotifications();
    });

    print('✅ Notification service initialized with tracking');
  } catch (e) {
    print('⚠️ Notification service failed: $e');
    print('📱 App will continue without notifications');
  }

  // Initialize overdue trip service (optional)
  try {
    await OverdueTripService().initialize();
    print('✅ Overdue trip service initialized');
  } catch (e) {
    print('⚠️ Overdue trip service failed: $e');
    print('📱 App will continue without overdue monitoring');
  }

  // ✅ Navigation service removed - no more FCM dependencies!

  // Initialize app lifecycle service for better plugin management
  AppLifecycleService().initialize();

  // Clear potentially corrupted location cache to fix type casting issues
  try {
    await LocationService().clearLocationCache();
    print('✅ Location cache cleared to prevent type casting errors');
  } catch (e) {
    print('⚠️ Error clearing location cache: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettingsService(),
      builder: (context, child) {
        final settingsService = AppSettingsService();

        return MaterialApp(
          title: 'ADG Tiny Sync',
          // ✅ Removed NavigationService dependency
          themeMode: settingsService.themeMode,
          theme: settingsService.lightTheme,
          darkTheme: settingsService.darkTheme,
          home:
              const AuthWrapper(), // ✅ FIXED: Use AuthWrapper instead of always going to login
          routes: {
            '/login': (context) => const LoginPage(),
            '/driver': (context) => DriverScreen(
                userData: ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?),
            '/operator': (context) => OperatorScreen(
                userData: ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?),
            '/settings': (context) => const SettingsPage(),
          },
        );
      },
    );
  }
}

class DriverScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const DriverScreen({super.key, this.userData});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF000000), // Pure black background
            boxShadow: [
              BoxShadow(
                color: Color(0x26000000),
                offset: Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false, // Keep title on the left
            automaticallyImplyLeading: false,
            title: Padding(
              padding: const EdgeInsets.only(
                  left: 8,
                  top: 8), // Reduced left padding and increased top padding
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ADG Tiny Sync',
                          style: TextStyle(
                            fontSize: 18, // Increased from 16
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Driver Portal',
                          style: TextStyle(
                            fontSize: 13, // Increased from 11
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // ✅ Driver notification alert - replaced the blue notification button
              if (widget.userData?['id'] != null)
                Container(
                  padding: const EdgeInsets.all(
                      6), // Match settings button padding style
                  child: DriverNotificationAlert(
                    driverId: widget.userData!['id'],
                  ),
                ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(10), // Increased from 6
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white70,
                    size: 22, // Increased from 18
                  ),
                ),
                onPressed: () {
                  Navigator.pushNamed(context, '/settings');
                },
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                constraints: const BoxConstraints(
                    minWidth: 48, minHeight: 48), // Increased from 40
              ),
              const SizedBox(
                  width: 12), // Add gap from right edge to match left side
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardPage(userData: widget.userData),
          StatusPage(userData: widget.userData),
          DriverOverdueTripsPage(userData: widget.userData),
          HistoryPage(userData: widget.userData),
          ProfilePage(userData: widget.userData),
        ],
      ),
      bottomNavigationBar: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF000000), // Pure black background like operator
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSimpleNavItem(
                0, Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
            _buildSimpleNavItem(
                1, Icons.monitor_heart_outlined, Icons.monitor_heart, 'Status'),
            _buildSimpleNavItem(2, Icons.warning_amber_outlined,
                Icons.warning_amber_rounded, 'Overdue'),
            _buildSimpleNavItem(
                3, Icons.history_outlined, Icons.history, 'History'),
            _buildSimpleNavItem(
                4, Icons.person_outline, Icons.person, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleNavItem(
      int index, IconData inactiveIcon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectedIndex != index) {
            setState(() {
              _selectedIndex = index;
            });
          }
        },
        child: SizedBox(
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Background circle for selected item
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF007AFF).withOpacity(0.15)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  size: 24,
                  color: isSelected
                      ? const Color(0xFF007AFF)
                      : Colors.grey.withOpacity(0.7),
                ),
              ),

              const SizedBox(height: 4),

              // Animated indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: isSelected ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
