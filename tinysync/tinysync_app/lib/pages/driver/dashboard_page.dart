import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../services/profile_image_service.dart';
import '../../services/notification_service.dart';
import '../../services/notification_tracking_service.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const DashboardPage({super.key, this.userData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isActive = false;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  List<Map<String, dynamic>> _currentTrips = [];
  List<Map<String, dynamic>> _scheduledTrips = [];

  // Add expansion state for assignment cards
  final Map<String, bool> _cardExpansionStates = {};

  // Real-time subscription variables
  RealtimeChannel? _userStatusSubscription;
  RealtimeChannel? _tripsSubscription;
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isUpdatingStatus = false; // Prevent update loops
  
  // Notification tracking service
  final NotificationTrackingService _notificationTracker = NotificationTrackingService();

  @override
  void initState() {
    super.initState();
    if (widget.userData != null) {
      _currentUser = widget.userData;
      _isActive = _currentUser?['status'] == 'active';
      _isLoading = false;
      _loadTrips();
    } else {
      _loadCurrentUser();
    }

    // Set up real-time subscriptions for live updates
    _setupRealtimeSubscriptions();

    // Set up periodic refresh every 30 seconds as backup
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isRefreshing) {
        _refreshData();
      }
    });

    // Perform maintenance cleanup on initialization
    _notificationTracker.performMaintenanceCleanup();
  }

  @override
  void dispose() {
    _userStatusSubscription?.unsubscribe();
    _tripsSubscription?.unsubscribe();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    if (_currentUser == null) return;

    // Subscribe to user status changes
    _userStatusSubscription = Supabase.instance.client
        .channel('user_status_channel_${_currentUser!['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _currentUser!['id'],
          ),
          callback: (payload) {
            print('🔄 User status change detected');
            _handleUserStatusUpdate(payload.newRecord);
          },
        )
        .subscribe();

    // Subscribe to trips assigned to this driver
    _tripsSubscription = Supabase.instance.client
        .channel('driver_trips_channel_${_currentUser!['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: _currentUser!['id'],
          ),
          callback: (payload) {
            print('🔄 Trip change detected for driver: ${payload.eventType}');
            _handleTripChange(payload);
            _loadTrips();
          },
        )
        .subscribe();
  }

  void _handleUserStatusUpdate(Map<String, dynamic> updatedUser) async {
    // Ignore real-time updates during manual status changes to prevent loops
    if (_isUpdatingStatus) {
      print('🚫 Ignoring real-time update during manual status change');
      return;
    }

    print('🔔 Real-time update received: ${updatedUser['status']}');
    print('🏠 Current local status: ${_isActive ? 'active' : 'inactive'}');

    if (mounted) {
      // Only update if the status actually changed to avoid loops
      final newStatus = updatedUser['status'] == 'active';
      if (newStatus != _isActive) {
        setState(() {
          _currentUser = {...?_currentUser, ...updatedUser};
          _isActive = newStatus;
        });
        print(
            '✅ Driver status updated in real-time: ${_isActive ? 'active' : 'inactive'}');

        // Check if we've already shown this status change notification
        final notificationId = _notificationTracker.generateUserStatusNotificationId(
          userId: _currentUser!['id'],
          status: updatedUser['status'],
        );
        
        final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(notificationId);
        
        if (!hasBeenShown && mounted) {
          // Show notification to user about status change
          NotificationService.showInfo(
            context,
            'Status updated to ${_isActive ? 'Active' : 'Inactive'}',
            icon: _isActive ? Icons.check_circle : Icons.pause_circle_filled,
          );
          
          // Mark notification as shown
          await _notificationTracker.markNotificationAsShown(notificationId);
        } else {
          print('🔄 Status change notification already shown, skipping');
        }
      } else {
        print('🔄 Status unchanged, skipping update');
      }
    }
  }

  void _handleTripChange(dynamic payload) async {
    if (!mounted) return;

    final eventType = payload.eventType;
    final newRecord = payload.newRecord;

    switch (eventType) {
      case PostgresChangeEvent.insert:
        // New trip assigned
        if (newRecord != null) {
          final tripRef = newRecord['trip_ref_number'] ?? 'New trip';
          final tripId = newRecord['id']?.toString() ?? 'unknown';
          
          // Check if we've already shown this assignment notification
          final notificationId = _notificationTracker.generateTripAssignmentNotificationId(
            tripId: tripId,
            driverId: _currentUser!['id'],
          );
          
          final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(notificationId);
          
          if (!hasBeenShown && mounted) {
            NotificationService.showInfo(
              context,
              'New assignment: $tripRef',
              icon: Icons.assignment_add,
            );
            
            // Mark notification as shown
            await _notificationTracker.markNotificationAsShown(notificationId);
          } else {
            print('🔄 Trip assignment notification already shown, skipping');
          }
        }
        break;
      case PostgresChangeEvent.update:
        // Trip status changed
        if (newRecord != null) {
          final tripRef = newRecord['trip_ref_number'] ?? 'Trip';
          final tripId = newRecord['id']?.toString() ?? 'unknown';
          final status = newRecord['status'];
          
          // Check if we've already shown this status change notification
          final notificationId = _notificationTracker.generateTripStatusNotificationId(
            tripId: tripId,
            status: status,
            driverId: _currentUser!['id'],
          );
          
          final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(notificationId);
          
          if (!hasBeenShown && mounted) {
            if (status == 'in_progress') {
              NotificationService.showSuccess(
                context,
                '$tripRef started',
                icon: Icons.play_arrow,
              );
            } else if (status == 'driver_completed') {
              NotificationService.showSuccess(
                context,
                '$tripRef completed - awaiting operator confirmation',
                icon: Icons.pending_actions,
              );
            } else if (status == 'completed') {
              NotificationService.showSuccess(
                context,
                '$tripRef fully completed',
                icon: Icons.check_circle,
              );
            } else if (status == 'cancelled') {
              NotificationService.showWarning(
                context,
                '$tripRef cancelled',
                icon: Icons.cancel,
              );
            }
            
            // Mark notification as shown
            await _notificationTracker.markNotificationAsShown(notificationId);
          } else {
            print('🔄 Trip status notification already shown, skipping');
          }
        }
        break;
      case PostgresChangeEvent.delete:
        // Trip removed/unassigned
        final tripId = payload.oldRecord?['id']?.toString() ?? 'unknown';
        
        // Check if we've already shown this removal notification
        final notificationId = _notificationTracker.generateNotificationId(
          type: 'trip_removed',
          tripId: tripId,
          driverId: _currentUser!['id'],
        );
        
        final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(notificationId);
        
        if (!hasBeenShown && mounted) {
          NotificationService.showWarning(
            context,
            'Trip assignment removed',
            icon: Icons.remove_circle_outline,
          );
          
          // Mark notification as shown
          await _notificationTracker.markNotificationAsShown(notificationId);
        } else {
          print('🔄 Trip removal notification already shown, skipping');
        }
        break;
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing || _currentUser == null) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Refresh user data to get latest status and profile image
      await _loadCurrentUserData();
      // Refresh trips data
      await _loadTrips();

      // Show refresh completion notification (only if not already shown recently)
      if (mounted) {
        final refreshNotificationId = _notificationTracker.generateNotificationId(
          type: 'dashboard_refresh',
          tripId: 'refresh_${DateTime.now().millisecondsSinceEpoch ~/ 30000}', // 30-second buckets
          driverId: _currentUser!['id'],
        );
        
        final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(refreshNotificationId);
        
        if (!hasBeenShown) {
          NotificationService.showSuccess(
            context,
            'Dashboard updated',
            icon: Icons.refresh,
            duration: const Duration(seconds: 2),
          );
          
          // Mark notification as shown
          await _notificationTracker.markNotificationAsShown(refreshNotificationId);
        }
      }
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadCurrentUserData() async {
    if (_currentUser == null) return;

    print('🔄 Loading current user data for refresh...');
    try {
      final userData = await Supabase.instance.client
          .from('users')
          .select('*, profile_image_url')
          .eq('id', _currentUser!['id'])
          .maybeSingle();

      print('📊 Fresh user data from database: ${userData?['status']}');
      print('🏠 Current local status: ${_isActive ? 'active' : 'inactive'}');

      if (userData != null && mounted) {
        final dbStatus = userData['status'] == 'active';
        setState(() {
          _currentUser = userData;
          _isActive = dbStatus;
        });
        print(
            '✅ User data refreshed - Status now: ${_isActive ? 'active' : 'inactive'}');
      }
    } catch (e) {
      print('❌ Error loading current user data: $e');
    }
  }

  Future<void> _loadTrips() async {
    try {
      if (_currentUser == null) return;

      // Load current trips (in_progress)
      final currentTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            priority,
            contact_person,
            contact_phone,
            notes,
            progress
          ''')
          .eq('driver_id', _currentUser!['id'])
          .eq('status', 'in_progress')
          .order('start_time');

      // Load scheduled trips
      final scheduledTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            priority,
            contact_person,
            contact_phone,
            notes,
            progress
          ''')
          .eq('driver_id', _currentUser!['id'])
          .eq('status', 'assigned')
          .order('start_time');

      if (mounted) {
        setState(() {
          _currentTrips = List<Map<String, dynamic>>.from(currentTripsResponse);
          _scheduledTrips =
              List<Map<String, dynamic>>.from(scheduledTripsResponse);
        });
      }
    } catch (e) {
      print('Error loading trips: $e');
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Get current user from Supabase
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        // Fetch user data from users table including profile image
        final userData = await Supabase.instance.client
            .from('users')
            .select('*, profile_image_url')
            .eq('id', user.id)
            .maybeSingle();

        if (userData != null && mounted) {
          setState(() {
            _currentUser = userData;
            _isActive = userData['status'] == 'active';
            _isLoading = false;
          });

          // Set up real-time subscriptions now that we have user data
          _setupRealtimeSubscriptions();
          _loadTrips();
        } else {
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
      print('Error loading user: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color:
            Color(0xFF000000), // Pure black background like operator dashboard
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          await _refreshData();
        },
        color: Theme.of(context).primaryColor,
        backgroundColor: const Color(0xFF2A2A2A),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Real-time indicator
              if (_isRefreshing)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor.withOpacity(0.15),
                        Theme.of(context).primaryColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Syncing real-time data...',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Driver Status Card with operator-style design
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A2A2A),
                      Color(0xFF232323),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: _isLoading
                    ? Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white54),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Loading driver information...',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: Profile picture and driver name/role/status
                              Row(
                                crossAxisAlignment: CrossAxisAlignment
                                    .start, // Align profile picture with name at top
                                children: [
                                  // Enhanced profile image with border and shadow - aligned with name at top
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _isActive
                                            ? const Color(0xFF4CAF50)
                                            : Colors.grey.withOpacity(0.5),
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isActive
                                                  ? const Color(0xFF4CAF50)
                                                  : Colors.grey)
                                              .withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: _buildDriverProfileImage(),
                                  ),
                                  const SizedBox(width: 20),
                                  // Driver Info with enhanced styling (name, role, status only)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Status badge moved above the name - smaller size
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8, // Reduced from 10
                                            vertical: 4, // Reduced from 6
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: _isActive
                                                  ? [
                                                      const Color(0xFF4CAF50),
                                                      const Color(0xFF45A049),
                                                    ]
                                                  : [
                                                      Colors.grey.shade700,
                                                      Colors.grey.shade600,
                                                    ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                                12), // Reduced from 16
                                            boxShadow: [
                                              BoxShadow(
                                                color: (_isActive
                                                        ? const Color(
                                                            0xFF4CAF50)
                                                        : Colors.grey)
                                                    .withOpacity(0.3),
                                                blurRadius: 3, // Reduced from 4
                                                offset: const Offset(
                                                    0, 1), // Reduced from 2
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _isActive
                                                    ? Icons.radio_button_checked
                                                    : Icons
                                                        .radio_button_unchecked,
                                                color: Colors.white,
                                                size: 10, // Reduced from 12
                                              ),
                                              const SizedBox(
                                                  width: 3), // Reduced from 4
                                              Text(
                                                _isActive
                                                    ? 'Active'
                                                    : 'Inactive',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize:
                                                      9, // Reduced from 11
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing:
                                                      0.2, // Reduced from 0.3
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                            height:
                                                12), // Increased space between status and name (from 8)
                                        // Driver name with enhanced typography
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 0), // Move text to the left
                                          child: Text(
                                            '${_currentUser?['first_name'] ?? ''} ${_currentUser?['last_name'] ?? ''}'
                                                    .trim()
                                                    .isEmpty
                                                ? 'Unknown Driver'
                                                : '${_currentUser?['first_name'] ?? ''} ${_currentUser?['last_name'] ?? ''}'
                                                    .trim(),
                                            style: const TextStyle(
                                              fontSize: 18, // Reduced from 22
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                              letterSpacing: 0.3,
                                            ),
                                            maxLines:
                                                2, // Allow name to wrap to 2 lines if needed
                                            overflow: TextOverflow
                                                .ellipsis, // Prevent overflow
                                          ),
                                        ),
                                        const SizedBox(
                                            height:
                                                3), // Reduced spacing to bring role closer to name (from 8)
                                        // Role with primary color
                                        if (_currentUser?['role'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left:
                                                    0), // Aligned with driver name
                                            child: Text(
                                              'Role: ${_currentUser!['role'].toString().toUpperCase()}',
                                              style: TextStyle(
                                                fontSize: 12, // Reduced from 14
                                                color: Theme.of(context)
                                                    .primaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                  height:
                                      16), // Space between top row and details
                              // Bottom section: Driver details below the profile picture
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 0), // Align with left edge
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Driver details with consistent styling
                                    Text(
                                      'Driver ID: ${_currentUser?['driver_id'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        fontSize: 12, // Reduced from 14
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_currentUser?['contact_number'] !=
                                        null) ...[
                                      const SizedBox(
                                          height: 3), // Reduced from 4
                                      Text(
                                        'Contact: ${_currentUser!['contact_number']}',
                                        style: const TextStyle(
                                          fontSize: 12, // Reduced from 14
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (_currentUser?[
                                            'driver_license_number'] !=
                                        null) ...[
                                      const SizedBox(
                                          height: 3), // Reduced from 4
                                      Text(
                                        'License: ${_currentUser!['driver_license_number']}',
                                        style: const TextStyle(
                                          fontSize: 12, // Reduced from 14
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Toggle switch positioned absolutely at bottom right, aligned with license info
                          Positioned(
                            top:
                                -12, // Align exactly with the bottom of the license text
                            right:
                                -11, // Move even further to the right, closer to container border
                            child: Transform.scale(
                              scale:
                                  0.7, // Make switch smaller (reduced from 0.8)
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Switch(
                                  value: _isActive,
                                  onChanged: (value) async {
                                    await _updateDriverStatus(value);
                                  },
                                  activeColor: const Color(0xFF4CAF50),
                                  activeTrackColor:
                                      const Color(0xFF4CAF50).withOpacity(0.3),
                                  inactiveThumbColor: Colors.grey.shade400,
                                  inactiveTrackColor: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // Real-time Dashboard Header (matching operator style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My Assignments',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Real-time trip updates',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (_isRefreshing)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Live',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Current Trips Section
              if (_currentTrips.isNotEmpty) ...[
                _buildTripSection(
                  'Active Assignments',
                  'Currently in progress',
                  _currentTrips,
                  Icons
                      .local_shipping_outlined, // Changed from Icons.directions_car to truck icon
                  const Color(0xFF2196F3), // Changed from green to blue
                ),
                const SizedBox(height: 20),
              ],

              // Scheduled Trips Section
              if (_scheduledTrips.isNotEmpty) ...[
                _buildTripSection(
                  'Scheduled Trips',
                  'Upcoming assignments',
                  _scheduledTrips,
                  Icons.schedule,
                  const Color(0xFF2196F3),
                ),
                const SizedBox(height: 20),
              ],

              // No trips message with operator-style design
              if (_currentTrips.isEmpty && _scheduledTrips.isEmpty) ...[
                _buildNoTripsState(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Build trip section with operator-style design
  Widget _buildTripSection(
    String title,
    String subtitle,
    List<Map<String, dynamic>> trips,
    IconData icon,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A2A2A),
            Color(0xFF1E1E1E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accentColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${trips.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Trips list
          ...trips.asMap().entries.map((entry) {
            final index = entry.key;
            final trip = entry.value;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: index == trips.length - 1 ? 0 : 16),
              child: _buildModernAssignmentCard(trip, accentColor),
            );
          }),
        ],
      ),
    );
  }

  // Modern expandable assignment card with operator-style design
  Widget _buildModernAssignmentCard(
      Map<String, dynamic> trip, Color accentColor) {
    final tripId =
        trip['id']?.toString() ?? trip['trip_ref_number'] ?? 'unknown';
    final isExpanded = _cardExpansionStates[tripId] ?? false;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A3A3A),
            Color(0xFF2E2E2E),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _cardExpansionStates[tripId] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with Trip ID and status badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.local_shipping_outlined,
                              color: Colors.blue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trip ID',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                trip['trip_ref_number'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Status badge in top right
                      if (trip['priority'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(trip['priority'])
                                .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getPriorityColor(trip['priority'])
                                  .withOpacity(0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            trip['priority'].toString().toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: _getPriorityColor(trip['priority']),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),

                  if (!isExpanded) ...[
                    const SizedBox(height: 16),

                    // Origin and Destination stacked vertically
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Origin
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.blue,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trip['origin'] ?? 'Unknown Origin',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Destination
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trip['destination'] ?? 'Unknown Destination',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],

                  // Expanded content - directly in card like trip card
                  if (isExpanded) ...[
                    const SizedBox(height: 20),

                    // Driver Information - directly in card
                    const Text(
                      'Driver Information:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Name: ${_currentUser != null ? '${_currentUser!['first_name'] ?? ''} ${_currentUser!['last_name'] ?? ''}'.trim() : 'Unknown Driver'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Driver ID: ${_currentUser?['driver_id'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'License: ${_currentUser?['driver_license_number'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),

                    const SizedBox(height: 16),

                    // Trip Details - directly in card
                    const Text(
                      'Trip Details:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Trip ID: ${trip['trip_ref_number'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Status: ${trip['status'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    if (trip['priority'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Priority: ${trip['priority'].toString()}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Start Time: ${_formatDateTime(trip['start_time'])}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'End Time: ${trip['end_time'] != null ? _formatDateTime(trip['end_time']) : 'N/A'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),

                    const SizedBox(height: 16),

                    // Locations - directly in card
                    const Text(
                      'Locations:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Origin: ${trip['origin'] ?? 'Unknown Origin'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Destination: ${trip['destination'] ?? 'Unknown Destination'}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),

                    if (trip['contact_person'] != null ||
                        trip['contact_phone'] != null) ...[
                      const SizedBox(height: 16),

                      // Contact Information - directly in card
                      const Text(
                        'Contact Information:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (trip['contact_person'] != null) ...[
                        Text(
                          'Contact Person: ${_currentUser != null ? '${_currentUser!['first_name'] ?? ''} ${_currentUser!['last_name'] ?? ''}'.trim() : 'Unknown Driver'}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (trip['contact_phone'] != null) ...[
                        Text(
                          'Phone: ${trip['contact_phone']}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced no trips state with operator-style design
  Widget _buildNoTripsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.withOpacity(0.1),
            Colors.grey.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 48,
              color: Colors.grey.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Active Assignments',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You don\'t have any current or scheduled trips.\nNew assignments will appear here automatically.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.withOpacity(0.7),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sync,
                  size: 16,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Real-time updates active',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get priority color
  Color _getPriorityColor(String? priority) {
    if (priority == null) return Colors.grey;
    switch (priority.toLowerCase()) {
      case 'high':
      case 'urgent':
        return Colors.red;
      case 'medium':
      case 'normal':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Build driver profile image widget
  Widget _buildDriverProfileImage() {
    final profileImageUrl = _currentUser?['profile_image_url'];

    return ProfileImageService.buildCircularProfileImage(
      imageUrl: profileImageUrl,
      size: 60,
      borderColor: _isActive ? const Color(0xFF4CAF50) : Colors.grey,
      borderWidth: 2,
      fallbackIcon: const Icon(
        Icons.person_outline,
        size: 30,
        color: Colors.white54,
      ),
    );
  }

  // Helper method to format date time
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'Not specified';
    try {
      DateTime parsedDate;
      if (dateTime is String) {
        parsedDate = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        parsedDate = dateTime;
      } else {
        return 'Invalid date';
      }
      return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year} at ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }


  Future<void> _updateDriverStatus(bool isActive) async {
    if (_isUpdatingStatus) return; // Prevent concurrent updates

    try {
      if (_currentUser == null) return;

      print('🔧 Starting status update: ${isActive ? 'active' : 'inactive'}');
      print('🆔 User ID: ${_currentUser!['id']}');
      print(
          '👤 Current user data: ${_currentUser!['first_name']} ${_currentUser!['last_name']}');

      _isUpdatingStatus = true; // Set flag to prevent loops

      // First, let's check if the user exists in the database
      final userExists = await Supabase.instance.client
          .from('users')
          .select('id, first_name, last_name, status')
          .eq('id', _currentUser!['id'])
          .maybeSingle();

      print('🔍 User exists check: $userExists');

      if (userExists == null) {
        print('❌ User not found in database!');
        return;
      }

      // Update user status using the database function (bypasses RLS)
      final result = await Supabase.instance.client.rpc(
        'update_driver_status',
        params: {
          'driver_id': _currentUser!['id'],
          'new_status': isActive ? 'active' : 'inactive',
        },
      );

      print('� RPC result: $result');

      // The function returns the updated record, so we can use it directly
      if (result != null && result.isNotEmpty) {
        final updatedRecord = result[0];
        setState(() {
          _isActive = isActive;
          _currentUser!['status'] = updatedRecord['status'];
          _currentUser!['updated_at'] = updatedRecord['updated_at'];
        });
        print(
            '✅ Driver status updated successfully to: ${updatedRecord['status']}');

        // Show success notification to user (only if not already shown)
        if (mounted) {
          final statusNotificationId = _notificationTracker.generateUserStatusNotificationId(
            userId: _currentUser!['id'],
            status: isActive ? 'active' : 'inactive',
          );
          
          final hasBeenShown = await _notificationTracker.hasNotificationBeenShown(statusNotificationId);
          
          if (!hasBeenShown) {
            NotificationService.showSuccess(
              context,
              'Status changed to ${isActive ? 'Active' : 'Inactive'}',
              icon: isActive ? Icons.check_circle : Icons.pause_circle_filled,
            );
            
            // Mark notification as shown
            await _notificationTracker.markNotificationAsShown(statusNotificationId);
          }
        }
      } else {
        print('❌ Database function did not return expected data');
        return;
      }
    } catch (e) {
      print('❌ Error updating driver status: $e');
      // Revert the local state if the database update failed
      if (mounted) {
        setState(() {
          _isActive = !isActive;
          _currentUser!['status'] = !isActive ? 'active' : 'inactive';
        });

        // Show error notification to user
        NotificationService.showError(
          context,
          'Failed to update status. Please try again.',
          icon: Icons.error_outline,
        );
      }
    } finally {
      // Reset the flag after a brief delay to allow real-time updates to process
      Future.delayed(const Duration(milliseconds: 500), () {
        _isUpdatingStatus = false;
      });
    }
  }
}
