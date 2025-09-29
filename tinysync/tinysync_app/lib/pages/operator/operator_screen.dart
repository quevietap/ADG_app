import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_persistence_service.dart';
import 'dashboard_page.dart';
import 'trips_page.dart';
import 'today_schedule_page.dart';
import 'history_page.dart';
import 'users_page.dart';
import 'vehicles_page.dart';
import '../../widgets/notification_icon_widget.dart';

class OperatorScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const OperatorScreen({super.key, this.userData});

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animationController;
  late AnimationController _indicatorController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _indicatorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animationController.forward();
    _indicatorController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index != _currentIndex) {
      // Add haptic feedback
      HapticFeedback.selectionClick();

      // Reset and restart animations
      _animationController.reset();
      _indicatorController.reset();

      setState(() {
        _currentIndex = index;
      });

      // Start animations
      _animationController.forward();
      _indicatorController.forward();
    }
  }

  void _showProfileDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Profile header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Profile avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: widget.userData?['profile_image_url'] != null
                          ? Image.network(
                              widget.userData!['profile_image_url'],
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Theme.of(context).primaryColor,
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress
                                                .cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                );
                              },
                            )
                          : Icon(
                              Icons.person,
                              size: 40,
                              color: Theme.of(context).primaryColor,
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User name
                  Text(
                    '${widget.userData?['first_name'] ?? 'Operator'} ${widget.userData?['last_name'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Role
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).primaryColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Role: ${widget.userData?['role']?.toString().toUpperCase() ?? 'OPERATOR'}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Operator ID
                  Text(
                    'Operator ID: ${widget.userData?['employee_id'] ?? widget.userData?['id'] ?? 'N/A'}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            // Profile options
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined,
                        color: Colors.white),
                    title: const Text('Settings',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.info_outline, color: Colors.white),
                    title: const Text('About',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showAboutDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Logout',
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showLogoutConfirmation();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Logout Confirmation',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                await _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    try {
      // Clear Supabase auth
      await Supabase.instance.client.auth.signOut();
      
      // Clear local authentication data (SharedPreferences)
      await AuthPersistenceService.clearAuthData();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF007AFF).withValues(alpha: 0.2),
                        const Color(0xFF007AFF).withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'About TINYSYNC',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Version 1.0.0',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TINYSYNC is a real-time alert and micro-sleep monitoring system made for drivers of ADG Company.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This app helps detect signs of short sleep (micro-sleep) using smart sensors and sends quick alerts to keep drivers safe.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The goal is to prevent accidents and support safe driving.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF007AFF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF007AFF)
                                  .withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.school_outlined,
                                color: Color(0xFF007AFF),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'This project was developed by Mark Beriso, Jc Magdaraog, Kate Millares, and Carl Johnrey as part of a school project to improve road safety using IoT technology.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[300],
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedBottomNavBar() {
    final List<IconData> icons = [
      Icons.dashboard,
      Icons.local_shipping,
      Icons.today,
      Icons.history,
      Icons.people,
      Icons.directions_car,
    ];

    final List<IconData> outlinedIcons = [
      Icons.dashboard_outlined,
      Icons.local_shipping_outlined,
      Icons.today_outlined,
      Icons.history_outlined,
      Icons.people_outline,
      Icons.directions_car_outlined,
    ];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(icons.length, (index) {
            final isSelected = _currentIndex == index;
            return Expanded(
              child: _buildNavItem(
                icon: icons[index],
                outlinedIcon: outlinedIcons[index],
                isSelected: isSelected,
                onTap: () => _onTabTapped(index),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData outlinedIcon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                    ? const Color(0xFF007AFF).withValues(alpha: 0.15)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: isSelected
                        ? 1.0 + (_animationController.value * 0.2)
                        : 1.0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        isSelected ? icon : outlinedIcon,
                        key: ValueKey(isSelected),
                        size: 24,
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.grey.withValues(alpha: 0.7),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 4),

            // Animated indicator
            AnimatedBuilder(
              animation: _indicatorController,
              builder: (context, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: isSelected ? 20 : 0,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      OperatorDashboardPage(userData: widget.userData),
      TripsPage(userData: widget.userData),
      const TodaySchedulePage(),
      HistoryPage(userData: widget.userData),
      const UsersPage(),
      const VehiclesPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Dashboard'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          const NotificationIconWidget(),
          GestureDetector(
            onTap: _showProfileDrawer,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17.5),
                child: widget.userData?['profile_image_url'] != null
                    ? Image.network(
                        widget.userData!['profile_image_url'],
                        width: 35,
                        height: 35,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person_outline,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          );
                        },
                      )
                    : Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Theme.of(context).primaryColor,
                      ),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.3, 0),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        child: Container(
          key: ValueKey(_currentIndex),
          child: pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: _buildAnimatedBottomNavBar(),
    );
  }
}
