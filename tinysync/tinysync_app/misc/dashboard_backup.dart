import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OperatorDashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const OperatorDashboardPage({super.key, this.userData});

  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isRealtimeUpdating = false;
  List<Map<String, dynamic>> _drivers = [];
  int _activeDriversCount = 0;
  int _inactiveDriversCount = 0;
  int _pendingTripsCount = 0;
  int _completedTripsToday = 0;
  int _inProgressTripsCount = 0;
  int _availableVehicles = 0;
  List<Map<String, dynamic>> _recentTrips = [];
  DateTime? _lastRefresh;

  // Real-time subscription
  RealtimeChannel? _tripsSubscription;
  RealtimeChannel? _driversSubscription;
  RealtimeChannel? _vehiclesSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.userData != null) {
      _currentUser = widget.userData;
      _loadDashboardData();
    } else {
      _loadCurrentUser();
    }
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    _tripsSubscription?.unsubscribe();
    _driversSubscription?.unsubscribe();
    _vehiclesSubscription?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    // Subscribe to trips table changes
    _tripsSubscription = Supabase.instance.client
        .channel('trips_dashboard_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            // ignore: avoid_print
            print('🔄 Trip change detected: ${payload.eventType}');
            // Refresh dashboard data when trips change
            _refreshDashboardData();
          },
        )
        .subscribe();

    // Subscribe to driver sessions changes (for active/inactive driver count)
    _driversSubscription = Supabase.instance.client
        .channel('driver_sessions_dashboard_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_sessions',
          callback: (payload) {
            // ignore: avoid_print
            print('🔄 Driver session change detected: ${payload.eventType}');
            // Refresh dashboard data when driver sessions change
            _refreshDashboardData();
          },
        )
        .subscribe();

    // Subscribe to vehicles table changes (for available vehicles count)
    _vehiclesSubscription = Supabase.instance.client
        .channel('vehicles_dashboard_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (payload) {
            // ignore: avoid_print
            print('🔄 Vehicle change detected: ${payload.eventType}');
            // Refresh dashboard data when vehicles change
            _refreshDashboardData();
          },
        )
        .subscribe();
  }

  /// Silent refresh method for real-time updates (no loading spinner)
  Future<void> _refreshDashboardData() async {
    if (_isRefreshing || _isLoading) return; // Prevent overlapping refreshes

    setState(() {
      _isRealtimeUpdating = true;
    });

    try {
      // Get today's date for filtering
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Execute all queries in parallel for better performance
      final results = await Future.wait([
        // Load drivers with profile image support
        Supabase.instance.client
            .from('users')
            .select(
                'id, first_name, last_name, status, employee_id, username, profile_image_url, updated_at')
            .eq('role', 'driver')
            .order('first_name'),

        // Load recent trips (limit to 10 for efficiency)
        Supabase.instance.client
            .from('trips')
            .select(
                'id, status, fare, created_at, trip_ref_number, driver_id, pickup_location, destination')
            .order('created_at', ascending: false)
            .limit(10),

        // Load vehicles
        Supabase.instance.client
            .from('vehicles')
            .select('id, status')
            .order('id'),

        // Load active driver sessions
        Supabase.instance.client
            .from('driver_sessions')
            .select('driver_id, status, created_at')
            .eq('status', 'active'),

        // Get trip counts by status (efficient aggregation)
        Supabase.instance.client
            .from('trips')
            .select('status')
            .neq('status', 'deleted'), // Exclude soft-deleted trips

        // Get today's completed trips count
        Supabase.instance.client
            .from('trips')
            .select('status, created_at')
            .eq('status', 'completed')
            .gte('created_at', todayStart.toIso8601String())
            .lt('created_at', todayEnd.toIso8601String()),
      ]);

      final driversResponse = results[0];
      final recentTripsResponse = results[1];
      final vehiclesResponse = results[2];
      final sessionsResponse = results[3];
      final allTripsResponse = results[4];
      final todayCompletedResponse = results[5];

      // Process data efficiently
      final drivers = List<Map<String, dynamic>>.from(driversResponse);
      final recentTrips = List<Map<String, dynamic>>.from(recentTripsResponse);
      final vehicles = List<Map<String, dynamic>>.from(vehiclesResponse);
      final activeSessions = List<Map<String, dynamic>>.from(sessionsResponse);
      final allTrips = List<Map<String, dynamic>>.from(allTripsResponse);
      final todayCompleted =
          List<Map<String, dynamic>>.from(todayCompletedResponse);

      // Get active driver IDs from sessions for more accurate count
      final activeDriverIds = activeSessions.map((s) => s['driver_id']).toSet();

      // Calculate driver counts based on actual login status and driver status
      int activeDriversCount = 0;
      int inactiveDriversCount = 0;

      for (final driver in drivers) {
        final driverId = driver['id'];
        final driverStatus = driver['status'];

        // A driver is considered active if they have an active session AND their status is active
        if (activeDriverIds.contains(driverId) && driverStatus == 'active') {
          activeDriversCount++;
        } else {
          inactiveDriversCount++;
        }
      }

      // Calculate trip counts efficiently
      final tripStatusCounts = <String, int>{};
      for (final trip in allTrips) {
        final status = trip['status'] as String? ?? 'unknown';
        tripStatusCounts[status] = (tripStatusCounts[status] ?? 0) + 1;
      }

      setState(() {
        _drivers = drivers;
        _recentTrips = recentTrips;

        // Driver counts (based on active sessions + status)
        _activeDriversCount = activeDriversCount;
        _inactiveDriversCount = inactiveDriversCount;

        // Trip counts (from aggregated data)
        _pendingTripsCount = tripStatusCounts['pending'] ?? 0;
        _inProgressTripsCount = tripStatusCounts['in_progress'] ?? 0;
        _completedTripsToday = todayCompleted.length;

        // Vehicle counts
        _availableVehicles =
            vehicles.where((v) => v['status'] == 'available').length;

        _lastRefresh = DateTime.now();
      });

      // Add current trip information to drivers using the active sessions we already fetched
      await _loadCurrentTripsForDrivers(activeSessions);
    } catch (e) {
      // ignore: avoid_print
      print('Error refreshing dashboard data: $e');
    } finally {
      setState(() {
        _isRealtimeUpdating = false;
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Get current user from Supabase
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        // Fetch user profile from users table with all necessary fields
        final profile = await Supabase.instance.client
            .from('users')
            .select(
                'id, first_name, middle_name, last_name, email, role, employee_id, username, profile_image_url, updated_at')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null) {
          // Debug: Log the fetched profile data
          // ignore: avoid_print
          print('🔍 Fetched operator profile: $profile');

          setState(() {
            _currentUser = profile;
          });
          _loadDashboardData();
        } else {
          // ignore: avoid_print
          print('❌ No profile found for user ID: ${user.id}');
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error loading user: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get today's date for filtering
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Execute all queries in parallel for better performance
      final results = await Future.wait([
        // Load drivers with profile image support
        Supabase.instance.client
            .from('users')
            .select(
                'id, first_name, last_name, status, employee_id, username, profile_image_url, updated_at')
            .eq('role', 'driver')
            .order('first_name'),

        // Load recent trips (limit to 10 for efficiency)
        Supabase.instance.client
            .from('trips')
            .select(
                'id, status, fare, created_at, trip_ref_number, driver_id, pickup_location, destination')
            .order('created_at', ascending: false)
            .limit(10),

        // Load vehicles
        Supabase.instance.client
            .from('vehicles')
            .select('id, status')
            .order('id'),

        // Load active driver sessions
        Supabase.instance.client
            .from('driver_sessions')
            .select('driver_id, status, created_at')
            .eq('status', 'active'),

        // Get trip counts by status (efficient aggregation)
        Supabase.instance.client
            .from('trips')
            .select('status')
            .neq('status', 'deleted'), // Exclude soft-deleted trips

        // Get today's completed trips count
        Supabase.instance.client
            .from('trips')
            .select('status, created_at')
            .eq('status', 'completed')
            .gte('created_at', todayStart.toIso8601String())
            .lt('created_at', todayEnd.toIso8601String()),
      ]);

      final driversResponse = results[0];
      final recentTripsResponse = results[1];
      final vehiclesResponse = results[2];
      final sessionsResponse = results[3];
      final allTripsResponse = results[4];
      final todayCompletedResponse = results[5];

      // Process data efficiently
      final drivers = List<Map<String, dynamic>>.from(driversResponse);
      final recentTrips = List<Map<String, dynamic>>.from(recentTripsResponse);
      final vehicles = List<Map<String, dynamic>>.from(vehiclesResponse);
      final activeSessions = List<Map<String, dynamic>>.from(sessionsResponse);
      final allTrips = List<Map<String, dynamic>>.from(allTripsResponse);
      final todayCompleted =
          List<Map<String, dynamic>>.from(todayCompletedResponse);

      // Get active driver IDs from sessions for more accurate count
      final activeDriverIds = activeSessions.map((s) => s['driver_id']).toSet();

      // Calculate driver counts based on actual login status and driver status
      int activeDriversCount = 0;
      int inactiveDriversCount = 0;

      for (final driver in drivers) {
        final driverId = driver['id'];
        final driverStatus = driver['status'];

        // A driver is considered active if they have an active session AND their status is active
        if (activeDriverIds.contains(driverId) && driverStatus == 'active') {
          activeDriversCount++;
        } else {
          inactiveDriversCount++;
        }
      }

      // Calculate trip counts efficiently
      final tripStatusCounts = <String, int>{};
      for (final trip in allTrips) {
        final status = trip['status'] as String? ?? 'unknown';
        tripStatusCounts[status] = (tripStatusCounts[status] ?? 0) + 1;
      }

      setState(() {
        _drivers = drivers;
        _recentTrips = recentTrips;

        // Driver counts (based on active sessions + status)
        _activeDriversCount = activeDriversCount;
        _inactiveDriversCount = inactiveDriversCount;

        // Trip counts (from aggregated data)
        _pendingTripsCount = tripStatusCounts['pending'] ?? 0;
        _inProgressTripsCount = tripStatusCounts['in_progress'] ?? 0;
        _completedTripsToday = todayCompleted.length;

        // Vehicle counts
        _availableVehicles =
            vehicles.where((v) => v['status'] == 'available').length;

        // Debug: Log calculated counts before setState
        // ignore: avoid_print
        print('🔍 Dashboard Final Counts:');
        // ignore: avoid_print
        print('  - Drivers: ${drivers.length}');
        // ignore: avoid_print
        print('  - Pending trips: ${tripStatusCounts['pending'] ?? 0}');
        // ignore: avoid_print
        print('  - In progress trips: ${tripStatusCounts['in_progress'] ?? 0}');
        // ignore: avoid_print
        print('  - Active drivers: $activeDriversCount');
        // ignore: avoid_print
        print('  - Inactive drivers: $inactiveDriversCount');
        // ignore: avoid_print
        print('  - Vehicles found: ${vehicles.length}');

        _isLoading = false;
        _lastRefresh = DateTime.now();
      });

      // Add current trip information to drivers using the active sessions we already fetched
      await _loadCurrentTripsForDrivers(activeSessions);
    } catch (e) {
      // ignore: avoid_print
      print('Error loading dashboard data: $e');
      setState(() {
        _isLoading = false;
        _lastRefresh =
            DateTime.now(); // Update even on error to show refresh attempt
      });
    }
  }

  Future<void> _loadCurrentTripsForDrivers(
      [List<Map<String, dynamic>>? sessions]) async {
    try {
      List<Map<String, dynamic>> activeSessions = sessions ?? [];

      // If sessions not provided, fetch them
      if (sessions == null) {
        final response = await Supabase.instance.client
            .from('driver_sessions')
            .select('driver_id, id, created_at')
            .eq('status', 'active');
        activeSessions = List<Map<String, dynamic>>.from(response);
      }

      // Get all active driver IDs at once to query trips efficiently
      final activeDriverIds =
          activeSessions.map((s) => s['driver_id']).toList();

      if (activeDriverIds.isEmpty) {
        setState(() {});
        return;
      }

      // Get current trips for all active drivers in one query
      final tripsResponse = await Supabase.instance.client
          .from('trips')
          .select(
              'trip_ref_number, status, driver_id, pickup_location, destination')
          .inFilter('driver_id', activeDriverIds)
          .eq('status', 'in_progress');

      final currentTrips = List<Map<String, dynamic>>.from(tripsResponse);

      // Map trips to drivers efficiently
      final tripsByDriver = <String, Map<String, dynamic>>{};
      for (final trip in currentTrips) {
        tripsByDriver[trip['driver_id']] = trip;
      }

      // Update drivers with current trip information
      for (int i = 0; i < _drivers.length; i++) {
        final driverId = _drivers[i]['id'];
        final currentTrip = tripsByDriver[driverId];

        if (currentTrip != null) {
          _drivers[i]['currentTrip'] = currentTrip['trip_ref_number'];
          _drivers[i]['currentTripDetails'] = {
            'pickup': currentTrip['pickup_location'],
            'destination': currentTrip['destination'],
            'status': currentTrip['status'],
          };
        } else {
          // Clear current trip if no longer active
          _drivers[i].remove('currentTrip');
          _drivers[i].remove('currentTripDetails');
        }
      }

      setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Error loading current trips: $e');
    }
  }

  String _buildUserDisplayName() {
    if (_currentUser == null) return 'Unknown Operator';

    final firstName = _currentUser!['first_name'] ?? '';
    final middleName = _currentUser!['middle_name'] ?? '';
    final lastName = _currentUser!['last_name'] ?? '';

    // Build full name with proper spacing
    String fullName = '';
    if (firstName.isNotEmpty) {
      fullName += firstName;
    }
    if (middleName.isNotEmpty) {
      if (fullName.isNotEmpty) fullName += ' ';
      fullName += middleName;
    }
    if (lastName.isNotEmpty) {
      if (fullName.isNotEmpty) fullName += ' ';
      fullName += lastName;
    }

    // Fallback to username or email if no name parts available
    if (fullName.isEmpty) {
      if (_currentUser!['username'] != null &&
          _currentUser!['username'].toString().isNotEmpty) {
        return _currentUser!['username'].toString();
      }
      if (_currentUser!['email'] != null &&
          _currentUser!['email'].toString().isNotEmpty) {
        return _currentUser!['email'].toString();
      }
      return 'Unknown Operator';
    }

    return fullName.trim();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(), // Enables pull-to-refresh even when content doesn't fill screen
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
                            color: Theme.of(context).scaffoldBackgroundColor,
                            shape: BoxShape.circle,
                          ),
                          child: _currentUser?['profile_image_url'] != null
                              ? ClipOval(
                                  child: Image.network(
                                    _currentUser!['profile_image_url'],
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.admin_panel_settings,
                                        size: 30,
                                        color: Colors.white54,
                                      );
                                    },
                                  ),
                                )
                              : const Icon(
                                  Icons.admin_panel_settings,
                                  size: 30,
                                  color: Colors.white54,
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _buildUserDisplayName(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Operator ID: ${_currentUser?['id']}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              if (_currentUser?['role'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Role: ${_currentUser!['role']}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
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

            // Quick Stats - Row 1
            Padding(
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
            const SizedBox(height: 12),

            // Quick Stats - Row 2
            Padding(
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
            const SizedBox(height: 12),

            // Quick Stats - Row 3
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Completed Today',
                      _completedTripsToday.toString(),
                      Icons.check_circle,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Total Drivers',
                      (_activeDriversCount + _inactiveDriversCount).toString(),
                      Icons.people,
                      Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quick Stats - Row 4
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildStatCard(
                'Available Vehicles',
                _availableVehicles.toString(),
                Icons.car_rental,
                Colors.teal,
              ),
            ),

            // Recent Trips Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Trips',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      // Navigate to full trips page
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),

            if (_recentTrips.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No recent trips',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTrips.length > 5
                    ? 5
                    : _recentTrips.length, // Limit to 5 recent trips
                itemBuilder: (context, index) {
                  final trip = _recentTrips[index];
                  return _buildTripCard(trip);
                },
              ),
            ],

            // Active Drivers Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Drivers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (_lastRefresh != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _getLastRefreshText(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (_isRealtimeUpdating) ...[
                        const Icon(
                          Icons.wifi,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_isRefreshing) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: _isRefreshing ? Colors.grey : Colors.white,
                        ),
                        onPressed: _isRefreshing ? null : _refreshDashboard,
                        tooltip: 'Refresh Dashboard',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_activeDriversCount == 0) ...[
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_off,
                        size: 48,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Active Drivers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All drivers are currently inactive. Assign a trip or activate a driver to see them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount:
                    _drivers.where((d) => d['status'] == 'active').length,
                itemBuilder: (context, index) {
                  final activeDrivers =
                      _drivers.where((d) => d['status'] == 'active').toList();
                  final driver = activeDrivers[index];
                  return _buildDriverCard(driver);
                },
              ),
            ],
          ],
        ),
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
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final driverName =
        '${driver['first_name'] ?? ''} ${driver['last_name'] ?? ''}'.trim();
    final driverId = driver['employee_id'] ?? driver['id'] ?? 'N/A';
    final status = driver['status'] ?? 'unknown';
    final profileImageUrl = driver['profile_image_url'];
    final currentTrip = driver['currentTrip'];
    final currentTripDetails = driver['currentTripDetails'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  backgroundImage:
                      profileImageUrl != null && profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : null,
                  child: profileImageUrl == null || profileImageUrl.isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName.isEmpty ? 'Unknown Driver' : driverName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'ID: $driverId',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'active'
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: status == 'active' ? Colors.green : Colors.grey,
                    ),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: status == 'active' ? Colors.green : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (currentTrip != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Current Trip: $currentTrip',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (currentTripDetails != null) ...[
                      const SizedBox(height: 8),
                      if (currentTripDetails['pickup'] != null ||
                          currentTripDetails['destination'] != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${currentTripDetails['pickup'] ?? 'Unknown'} → ${currentTripDetails['destination'] ?? 'Unknown'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final tripRef = trip['trip_ref_number'] ?? 'N/A';
    final status = trip['status'] ?? 'unknown';
    final fare = trip['fare']?.toDouble() ?? 0.0;
    final createdAt =
        trip['created_at'] != null ? DateTime.parse(trip['created_at']) : null;
    final pickup = trip['pickup_location'] ?? 'Not specified';
    final destination = trip['destination'] ?? 'Not specified';

    Color statusColor;
    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        break;
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_taxi,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trip #$tripRef',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          _formatDateTime(createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (fare > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '₱${fare.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            // Add pickup and destination information if available
            if (pickup != 'Not specified' ||
                destination != 'Not specified') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$pickup → $destination',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Manual refresh method for pull-to-refresh or button refresh
  Future<void> _refreshDashboard() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes

    setState(() {
      _isRefreshing = true;
      _lastRefresh = DateTime.now();
    });

    try {
      await _loadDashboardData();
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  /// Get time since last refresh for display
  String _getLastRefreshText() {
    if (_lastRefresh == null) return '';

    final now = DateTime.now();
    final difference = now.difference(_lastRefresh!);

    if (difference.inMinutes < 1) {
      return 'Updated just now';
    } else if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes}m ago';
    } else {
      return 'Updated ${difference.inHours}h ago';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tripDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    String dateStr;
    if (tripDate == today) {
      dateStr = 'Today';
    } else if (tripDate == yesterday) {
      dateStr = 'Yesterday';
    } else {
      dateStr = '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }

    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final ampm = dateTime.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:${dateTime.minute.toString().padLeft(2, '0')} $ampm';

    return '$dateStr at $timeStr';
  }
}
