import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';

class OperatorDashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const OperatorDashboardPage({super.key, this.userData});

  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  List<Map<String, dynamic>> _drivers = [];
  int _activeDriversCount = 0;
  int _inactiveDriversCount = 0;
  int _pendingTripsCount = 0;
  int _inProgressTripsCount = 0;
  String? _operatorId;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isRefreshing = false;

  // Real-time subscription variables
  RealtimeChannel? _driversSubscription;
  RealtimeChannel? _tripsSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.userData != null) {
      _currentUser = widget.userData;
      if (_currentUser?['role'] == 'operator') {
        _generateOperatorId(_currentUser!);
      }
      // Ensure we have the profile image - refresh user data if needed
      _ensureProfileImageLoaded();
      _loadDashboardData();
    } else {
      _loadCurrentUser();
    }

    // Set up auto-refresh every 30 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadDashboardData();
    });

    // Set up real-time subscriptions for driver status changes
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _driversSubscription?.unsubscribe();
    _tripsSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _ensureProfileImageLoaded() async {
    // Check if profile image URL is missing from current user data
    if (_currentUser != null &&
        _currentUser!['profile_image_url'] == null &&
        _currentUser!['profile_picture'] == null) {
      try {
        // Fetch the complete user profile including both image columns for backward compatibility
        final updatedProfile = await Supabase.instance.client
            .from('users')
            .select('*, profile_image_url, profile_picture')
            .eq('id', _currentUser!['id'])
            .maybeSingle();

        if (updatedProfile != null) {
          setState(() {
            _currentUser = updatedProfile;
          });
        }
      } catch (e) {
        print('Error loading profile image: $e');
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Get current user from Supabase
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        // Fetch user profile from users table including both image columns for backward compatibility
        final profile = await Supabase.instance.client
            .from('users')
            .select('*, profile_image_url, profile_picture')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null && profile['role'] == 'operator') {
          // Generate or retrieve Operator ID
          await _generateOperatorId(profile);
        }

        setState(() {
          _currentUser = profile;
        });
        _loadDashboardData();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateOperatorId(Map<String, dynamic> profile) async {
    try {
      // Check if operator already has an operator_id
      if (profile['operator_id'] != null && profile['operator_id'].isNotEmpty) {
        _operatorId = profile['operator_id'];
        return;
      }

      // Count total operators to generate new ID
      final operatorCountResponse = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('role', 'operator');

      final operatorCount = operatorCountResponse.length;
      final newOperatorNumber = operatorCount + 1;
      final formattedOperatorId =
          'OPR-${newOperatorNumber.toString().padLeft(3, '0')}';

      // Update the user's profile with the new operator_id
      await Supabase.instance.client
          .from('users')
          .update({'operator_id': formattedOperatorId}).eq('id', profile['id']);

      _operatorId = formattedOperatorId;

      // Update the current user data
      profile['operator_id'] = formattedOperatorId;
    } catch (e) {
      print('Error generating operator ID: $e');
      // Set a fallback ID if generation fails
      _operatorId = 'OPR-000';
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      // Load drivers with real-time status
      final driversResponse = await Supabase.instance.client
          .from('users')
          .select(
              'id, first_name, last_name, status, employee_id, driver_id, username')
          .eq('role', 'driver')
          .order('first_name');

      // Load all trips data
      final allTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('id, status, created_at, trip_ref_number, driver_id')
          .order('created_at', ascending: false);

      final allTrips = List<Map<String, dynamic>>.from(allTripsResponse);

      setState(() {
        _drivers = List<Map<String, dynamic>>.from(driversResponse);

        // Debug: Print driver information to verify driver_id is fetched
        print('📋 Loaded ${_drivers.length} drivers:');
        for (final driver in _drivers.take(3)) {
          print(
              '   ${driver['first_name']} ${driver['last_name']} - Driver ID: ${driver['driver_id']} - Status: ${driver['status']}');
        }

        // Driver counts - use status field for driver status with smooth transitions
        final newActiveCount = _drivers.where((d) {
          return d['status'] == 'active';
        }).length;

        final newInactiveCount = _drivers.where((d) {
          return d['status'] == 'inactive';
        }).length;

        // Animate count changes smoothly
        _activeDriversCount = newActiveCount;
        _inactiveDriversCount = newInactiveCount;

        // Trip counts
        _pendingTripsCount =
            allTrips.where((t) => t['status'] == 'pending').length;
        _inProgressTripsCount =
            allTrips.where((t) => t['status'] == 'in_progress').length;

        _lastUpdated = DateTime.now();
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  void _setupRealtimeSubscriptions() {
    // Subscribe to driver status changes (users table)
    _driversSubscription = Supabase.instance.client
        .channel('operator_drivers_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'role',
            value: 'driver',
          ),
          callback: (payload) {
            final driverName =
                '${payload.newRecord['first_name'] ?? ''} ${payload.newRecord['last_name'] ?? ''}';
            final newStatus = payload.newRecord['status'] ?? 'unknown';
            print('🔄 Driver status change detected in operator dashboard');
            print('   Driver: $driverName -> Status: $newStatus');

            // Add a small delay for smoother visual transitions
            Future.delayed(const Duration(milliseconds: 150), () {
              if (mounted) {
                // Refresh dashboard data when driver status changes
                _loadDashboardData();
              }
            });
          },
        )
        .subscribe();

    // Subscribe to trip changes
    _tripsSubscription = Supabase.instance.client
        .channel('operator_trips_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            print(
                '🔄 Trip change detected in operator dashboard: ${payload.eventType}');
            // Refresh dashboard data when trips change
            _loadDashboardData();
          },
        )
        .subscribe();
  }

  String _buildOperatorName() {
    if (_currentUser == null) return 'Unknown Operator';

    // Try to build name from first_name and last_name
    final firstName = _currentUser!['first_name'];
    final lastName = _currentUser!['last_name'];

    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName;
    } else if (lastName != null) {
      return lastName;
    }

    // Fall back to name field or username
    return _currentUser!['name'] ??
        _currentUser!['username'] ??
        'Unknown Operator';
  }

  String _formatLastUpdated(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else {
      final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final ampm = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${dateTime.minute.toString().padLeft(2, '0')} $ampm';
    }
  }

  Widget _buildProfileImage() {
    // Use the same dual-column approach as users page for backward compatibility
    final profileImageUrl =
        _currentUser?['profile_picture'] ?? _currentUser?['profile_image_url'];

    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      // Handle different types of image URLs
      String imageUrl = profileImageUrl;

      // Check if it's a base64 data URL (don't convert these)
      if (profileImageUrl.startsWith('data:image/')) {
        // It's already a base64 data URL, use it directly
        imageUrl = profileImageUrl;
      } else if (!profileImageUrl.startsWith('http')) {
        // If it's a Supabase Storage path (doesn't start with http), convert it
        try {
          imageUrl = Supabase.instance.client.storage
              .from('profile-images')
              .getPublicUrl(profileImageUrl);
        } catch (e) {
          print('Error building Supabase storage URL: $e');
          // Fall back to original URL
          imageUrl = profileImageUrl;
        }
      }

      return ClipOval(
        child: Container(
          width: 56, // Slightly smaller to account for border
          height: 56,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: profileImageUrl.startsWith('data:image/')
              ? Image.memory(
                  // Handle base64 data URLs
                  base64Decode(profileImageUrl.split(',')[1]),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading base64 profile image: $error');
                    return Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const Icon(
                        Icons.admin_panel_settings,
                        size: 28,
                        color: Colors.white54,
                      ),
                    );
                  },
                )
              : Image.network(
                  // Handle network URLs
                  imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading profile image: $error');
                    // Fallback to default icon if image fails to load
                    return Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const Icon(
                        Icons.admin_panel_settings,
                        size: 28,
                        color: Colors.white54,
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            strokeWidth: 2,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white54),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
    } else {
      // Default icon when no profile image is available
      return ClipOval(
        child: Container(
          width: 56,
          height: 56,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: const Icon(
            Icons.admin_panel_settings,
            size: 28,
            color: Colors.white54,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Operator Status Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isLoading
                ? const Row(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Loading user information...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildProfileImage(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _buildOperatorName(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (_currentUser?['role'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Role: ${_currentUser!['role'].toString().toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Operator ID: ${_operatorId ?? _currentUser?['operator_id'] ?? 'Generating...'}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            if (_currentUser?['email'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Email: ${_currentUser!['email']}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // Refresh Button and Stats Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Real-time Dashboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (_lastUpdated != null)
                      Text(
                        'Last updated: ${_formatLastUpdated(_lastUpdated!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (_isRefreshing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    if (_isRefreshing) const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _isRefreshing ? null : _loadDashboardData,
                      tooltip: 'Refresh Data',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Quick Stats - Row 1 with smooth animations
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Active Drivers',
                      _activeDriversCount.toString(),
                      Icons.person,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Inactive Drivers',
                      _inactiveDriversCount.toString(),
                      Icons.person_off,
                      Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick Stats - Row 2 with smooth animations
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Pending Trips',
                      _pendingTripsCount.toString(),
                      Icons.pending_actions,
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'In Progress',
                      _inProgressTripsCount.toString(),
                      Icons.directions_car,
                      Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Animated icon with smooth color transitions
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 8),
            // Animated text value with smooth scaling and color transitions
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: Text(
                value,
                key: ValueKey(value), // Key ensures proper animation triggers
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Animated title with smooth fade transitions
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
