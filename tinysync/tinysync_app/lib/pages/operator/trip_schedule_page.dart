import 'dart:async';
import 'dart:convert';
// Removed unnecessary import
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/enhanced_trip_card.dart';

class TodaySchedulePage extends StatefulWidget {
  const TodaySchedulePage({super.key});

  @override
  State<TodaySchedulePage> createState() => _TodaySchedulePageState();
}

class _TodaySchedulePageState extends State<TodaySchedulePage> {
  List<Map<String, dynamic>> _todayTrips = [];
  List<Map<String, dynamic>> _scheduledTrips = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Map<String, bool> _expandedCards =
      {}; // Track which trip cards are expanded
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when returning to this page
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T')[0];
      final tomorrowStr =
          today.add(const Duration(days: 1)).toIso8601String().split('T')[0];

      print('🔍 Fetching trips for date: $todayStr');
      print('🔍 Today: $todayStr, Tomorrow: $tomorrowStr');

      // First, let's try to fetch ALL trips to see what's in the database
      print('🔍 Fetching ALL trips first...');
      final allTripsResponse = await Supabase.instance.client
          .from('trips')
          .select('id, start_time, status, driver_id, created_at')
          .order('created_at', ascending: false)
          .limit(10);

      print('📊 ALL trips in database: ${(allTripsResponse as List).length}');
      for (var trip in allTripsResponse) {
        print(
            '   Trip ${trip['id']}: start_time=${trip['start_time']}, status=${trip['status']}, created_at=${trip['created_at']}');
      }

      // 1. Fetch trips - try multiple approaches
      List<dynamic> tripsResponse = [];

      // Approach 1: Try with start_time date range
      try {
        tripsResponse = await Supabase.instance.client
            .from('trips')
            .select(
                '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
            .gte('start_time', todayStr)
            .lt('start_time', tomorrowStr);
        print('📊 Trips found with start_time filter: ${tripsResponse.length}');
      } catch (e) {
        print('❌ Error with start_time filter: $e');
      }

      // Approach 2: If no trips found, try with created_at
      if (tripsResponse.isEmpty) {
        try {
          tripsResponse = await Supabase.instance.client
              .from('trips')
              .select(
                  '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
              .gte('created_at', todayStr)
              .lt('created_at', tomorrowStr);
          print(
              '📊 Trips found with created_at filter: ${tripsResponse.length}');
        } catch (e) {
          print('❌ Error with created_at filter: $e');
        }
      }

      // Approach 3: If still no trips, get recent trips regardless of date
      if (tripsResponse.isEmpty) {
        try {
          tripsResponse = await Supabase.instance.client
              .from('trips')
              .select(
                  '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
              .order('created_at', ascending: false)
              .limit(20);
          print('📊 Recent trips found (any date): ${tripsResponse.length}');
        } catch (e) {
          print('❌ Error fetching recent trips: $e');
        }
      }

      // 2. Fetch scheduled trips for today
      final schedulesResponse = await Supabase.instance.client
          .from('schedules')
          .select(
              '*, trips(*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*))')
          .eq('schedule_date', todayStr)
          .order('schedule_date', ascending: true);

      print('📊 Raw trips fetched: ${tripsResponse.length}');
      print('📊 Raw schedules fetched: ${(schedulesResponse as List).length}');

      // Filter out canceled and deleted trips CLIENT-SIDE
      final filteredTrips = tripsResponse.where((trip) {
        final status = trip['status']?.toString().toLowerCase() ?? '';
        final driverId = trip['driver_id'];
        print('Trip ${trip['id']} has status: $status, driver_id: $driverId');

        // TEMPORARY FIX: Allow 'deleted' trips with assigned drivers to show (they should be 'assigned')
        final hasAssignedDriver = driverId != null;
        final isDeletedButShouldBeAssigned =
            status == 'deleted' && hasAssignedDriver;

        return (status != 'canceled' &&
                status != 'cancelled' &&
                status != 'deleted') ||
            isDeletedButShouldBeAssigned;
      }).toList();

      final filteredSchedules = (schedulesResponse).where((schedule) {
        final trip = schedule['trips'];
        if (trip == null) return true;
        final status = trip['status']?.toString().toLowerCase() ?? '';
        final driverId = trip['driver_id'];
        print('Scheduled trip ${trip['id']} has status: $status');

        // TEMPORARY FIX: Allow 'deleted' trips with assigned drivers to show (they should be 'assigned')
        final hasAssignedDriver = driverId != null;
        final isDeletedButShouldBeAssigned =
            status == 'deleted' && hasAssignedDriver;

        return (status != 'canceled' &&
                status != 'cancelled' &&
                status != 'deleted') ||
            isDeletedButShouldBeAssigned;
      }).toList();

      // Fetch vehicle details for filtered trips
      final tripsWithVehicles =
          await Future.wait(filteredTrips.map((trip) async {
        if (trip['vehicle_id'] != null) {
          try {
            final vehicleResponse = await Supabase.instance.client
                .from('vehicles')
                .select('plate_number, make, model, capacity_kg')
                .eq('id', trip['vehicle_id'])
                .single();
            trip['vehicle_details'] = vehicleResponse;
          } catch (e) {
            debugPrint('Error fetching vehicle details: $e');
            trip['vehicle_details'] = null;
          }
        }
        return trip;
      }));

      // Fetch vehicle details for scheduled trips
      final schedulesWithVehicles =
          await Future.wait(filteredSchedules.map((schedule) async {
        final trip = schedule['trips'];
        if (trip != null && trip['vehicle_id'] != null) {
          try {
            final vehicleResponse = await Supabase.instance.client
                .from('vehicles')
                .select('plate_number, make, model, capacity_kg')
                .eq('id', trip['vehicle_id'])
                .single();
            trip['vehicle_details'] = vehicleResponse;
          } catch (e) {
            debugPrint('Error fetching vehicle details: $e');
            trip['vehicle_details'] = null;
          }
        }
        return schedule;
      }));

      print('✅ Filtered trips count: ${tripsWithVehicles.length}');
      print('✅ Filtered schedules count: ${schedulesWithVehicles.length}');

      if (mounted) {
        setState(() {
          _todayTrips = List<Map<String, dynamic>>.from(tripsWithVehicles);
          _scheduledTrips =
              List<Map<String, dynamic>>.from(schedulesWithVehicles);
        });
      }
    } catch (e) {
      print('❌ Error fetching data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch today\'s trips: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Add shared date/time formatting functions
  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return 'N/A';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatTripId(Map<String, dynamic> trip) {
    // If there's a trip_ref_number, use it (show full reference)
    if (trip['trip_ref_number'] != null &&
        trip['trip_ref_number'].toString().isNotEmpty) {
      return trip['trip_ref_number'].toString();
    }

    // Otherwise, create a formatted ID from the database ID (show full ID)
    final id = trip['id'];
    if (id != null) {
      return 'Trip $id';
    }

    return 'Trip Unknown';
  }

  @override
  Widget build(BuildContext context) {
    // Deduplicate trips by id
    final Map<dynamic, Map<String, dynamic>> uniqueTrips = {};
    for (final trip in _todayTrips) {
      final id = trip['id'] ?? trip['trip_ref_number'];
      if (id != null) uniqueTrips[id] = trip;
    }
    for (final schedule in _scheduledTrips) {
      final trip = schedule['trips'];
      if (trip != null) {
        final id = trip['id'] ?? trip['trip_ref_number'];
        if (id != null) uniqueTrips[id] = trip;
      }
    }
    final List<Map<String, dynamic>> dedupedTrips = uniqueTrips.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed header
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            "Today's Schedule",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                if (_errorMessage != null)
                  Center(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (!_isLoading &&
                    _errorMessage == null &&
                    dedupedTrips.isEmpty)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.event_busy,
                            size: 60,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No Trips Scheduled',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No trips are scheduled for today. Check back later or add a new trip.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isLoading &&
                    _errorMessage == null &&
                    dedupedTrips.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dedupedTrips.length,
                    itemBuilder: (context, index) {
                      final trip = dedupedTrips[index];
                      return EnhancedTripCard(
                        trip: trip,
                        cardIndex: index,
                        isFromSchedule: true,
                        isToday: false,
                        showRealTimeTracking: true,
                        isDriver: false,
                        isOperator: true,
                        userData: null, // TODO: Pass userData when available
                        onTripUpdated: () {
                          // Refresh trips when trip is updated
                          _fetchData();
                        },
                        onAssignDriver:
                            null, // Schedule page doesn't need assignment
                        onAssignVehicle:
                            null, // Schedule page doesn't need assignment
                        onCancel: null, // Schedule page doesn't need cancel
                        onDelete: null, // Schedule page doesn't need delete
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripCard(Map<String, dynamic>? trip, int cardIndex,
      {bool isFromSchedule = false, bool isToday = false}) {
    if (trip == null) return const SizedBox.shrink();

    final mainDriver = trip['driver'] ?? {};
    final subDriver = trip['sub_driver'] ?? {};
    final status = trip['status'] ?? 'Unassigned';
    final priority = trip['priority'] ?? 'normal';

    // Format time
    DateTime? startDate = trip['start_time'] != null
        ? DateTime.tryParse(trip['start_time'])
        : null;

    // Determine if completed today
    bool completedToday = false;
    String? completedTime;
    if (status.toLowerCase() == 'completed' && trip['end_time'] != null) {
      final endDt = DateTime.tryParse(trip['end_time']);
      if (endDt != null) {
        final now = DateTime.now();
        completedToday = endDt.year == now.year &&
            endDt.month == now.month &&
            endDt.day == now.day;
        completedTime = _formatTime(endDt);
      }
    }

    // Determine if still delivering
    bool delivering = status.toLowerCase() == 'in_progress';

    return InkWell(
        onTap: () async {
          setState(() {
            // Use a more unique identifier for expansion tracking
            final uniqueKey =
                '${trip['id']}_${trip['trip_ref_number'] ?? 'unknown'}';
            final isCurrentlyExpanded = _expandedCards[uniqueKey] ?? false;

            // Close all other expanded cards
            _expandedCards.clear();

            // Toggle only the clicked card (expand if it was closed)
            if (!isCurrentlyExpanded) {
              _expandedCards[uniqueKey] = true;
            }
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Card(
          margin: const EdgeInsets.only(bottom: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          color: const Color(0xFF232323),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER SECTION - Trip ID and Badges
                Row(
                  children: [
                    // Trip Icon and ID
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        size: 24,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2, // Give more space to Trip ID
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip ID',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTripId(trip),
                            style: const TextStyle(
                              fontSize: 16, // Slightly smaller font
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    // Status Badges - Horizontally aligned
                    Expanded(
                      flex: 3, // Give proportional space to badges
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Priority Badge
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4), // Even smaller padding
                              decoration: BoxDecoration(
                                color: _getPriorityColor(priority)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _getPriorityColor(priority)
                                      .withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getPriorityIcon(priority),
                                    size: 10, // Even smaller icon
                                    color: _getPriorityColor(priority),
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      priority.toUpperCase(),
                                      style: TextStyle(
                                        color: _getPriorityColor(priority),
                                        fontSize: 9, // Even smaller text
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Status Badge - only show when driver is assigned
                          if (trip['driver_id'] != null &&
                              trip['driver_id'].toString().isNotEmpty)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4), // Even smaller padding
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _getStatusColor(status)
                                        .withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getStatusIcon(status),
                                      size: 10, // Even smaller icon
                                      color: _getStatusColor(status),
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        delivering
                                            ? 'DELIVERING'
                                            : (completedToday
                                                ? 'COMPLETED'
                                                : status.toUpperCase()),
                                        style: TextStyle(
                                          color: _getStatusColor(status),
                                          fontSize: 9, // Even smaller text
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          // Pending Badge
                          if (trip['driver_id'] == null ||
                              trip['driver_id'].toString().isEmpty)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.orangeAccent
                                        .withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 10,
                                      color: Colors.orangeAccent,
                                    ),
                                    SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        'PENDING',
                                        style: TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Add expandable section right after the header
                Row(
                  children: [
                    if (!(_expandedCards[
                            '${trip['id']}_${trip['trip_ref_number'] ?? 'unknown'}'] ??
                        false)) ...[
                      Text(
                        startDate != null
                            ? '${_formatDate(startDate)} • ${_formatTime(startDate)}'
                            : 'Not scheduled',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ],
                ),

                // Expandable content
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      // SCHEDULE SECTION
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'SCHEDULE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildScheduleItem(
                                    'Scheduled Date',
                                    startDate != null
                                        ? _formatDate(startDate)
                                        : 'Not set',
                                    Icons.event,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildScheduleItem(
                                    'Scheduled Time',
                                    startDate != null
                                        ? _formatTime(startDate)
                                        : 'Not set',
                                    Icons.access_time,
                                  ),
                                ),
                              ],
                            ),
                            if (completedToday && completedTime != null) ...[
                              const SizedBox(height: 12),
                              _buildScheduleItem(
                                'Completed At',
                                completedTime,
                                Icons.check_circle,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // DRIVER INFO SECTION
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'DRIVER INFO',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildDriverInfo(
                              'Main Driver',
                              mainDriver.isNotEmpty
                                  ? '${mainDriver['first_name'] ?? ''} ${mainDriver['last_name'] ?? ''}'
                                      .trim()
                                  : 'Unassigned',
                              mainDriver.isNotEmpty,
                            ),
                            const SizedBox(height: 8),
                            _buildDriverInfo(
                              'Sub Driver',
                              subDriver.isNotEmpty
                                  ? '${subDriver['first_name'] ?? ''} ${subDriver['last_name'] ?? ''}'
                                      .trim()
                                  : 'None',
                              subDriver.isNotEmpty,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // TRUCK & ROUTE SECTION
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_shipping,
                                  size: 16,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'VEHICLE & ROUTE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildVehicleInfo(trip['vehicle_details']),
                            const SizedBox(height: 12),
                            _buildRouteInfo(
                              trip['origin'] ?? 'Not specified',
                              trip['destination'] ?? 'Not specified',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // VIEW LOGS BUTTON SECTION
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showViewLogsModal(context, trip),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.1),
                            foregroundColor: Theme.of(context).primaryColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text(
                            'View Logs',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      // Debug info (if needed)
                      if (isFromSchedule || isToday) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isFromSchedule
                                ? 'From Schedules table'
                                : 'Today\'s Schedule',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  crossFadeState: (_expandedCards[
                              '${trip['id']}_${trip['trip_ref_number'] ?? 'unknown'}'] ??
                          false)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),
              ],
            ),
          ),
        ));
  }

  Widget _buildScheduleItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfo(String label, String name, bool isAssigned) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isAssigned ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name.isEmpty ? 'Not assigned' : name,
            style: TextStyle(
              fontSize: 14,
              color: isAssigned ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleInfo(Map<String, dynamic>? vehicleDetails) {
    String vehicleInfo = 'Not assigned';
    bool isAssigned = false;

    if (vehicleDetails != null) {
      final plateNumber = vehicleDetails['plate_number'] ?? '';
      final make = vehicleDetails['make'] ?? '';
      final model = vehicleDetails['model'] ?? '';

      if (plateNumber.isNotEmpty) {
        isAssigned = true;
        if (make.isNotEmpty && model.isNotEmpty) {
          vehicleInfo = '$plateNumber ($make $model)';
        } else {
          vehicleInfo = plateNumber;
        }
      }
    }

    return Row(
      children: [
        Icon(
          Icons.local_shipping,
          size: 16,
          color: isAssigned ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 12),
        const Text(
          'Truck:',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            vehicleInfo,
            style: TextStyle(
              fontSize: 14,
              color: isAssigned ? Colors.white : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteInfo(String origin, String destination) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.my_location,
              size: 14,
              color: Colors.green,
            ),
            const SizedBox(width: 12),
            const Text(
              'From:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                origin.isNotEmpty ? origin : 'Not specified',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.location_on,
              size: 14,
              color: Colors.red,
            ),
            const SizedBox(width: 12),
            const Text(
              'To:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                destination.isNotEmpty ? destination : 'Not specified',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Icons.priority_high;
      case 'urgent':
        return Icons.warning;
      case 'low':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.remove;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.local_shipping;
      case 'assigned':
        return Icons.assignment;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in progress':
        return Colors.blue;
      case 'delayed':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors
            .orangeAccent; // Use orange for pending to match PENDING badge
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // View Logs Modal
  void _showViewLogsModal(BuildContext context, Map<String, dynamic> trip) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ViewLogsModal(trip: trip),
          ),
        );
      },
    );
  }
}

// View Logs Modal Widget
class ViewLogsModal extends StatefulWidget {
  final Map<String, dynamic> trip;

  const ViewLogsModal({super.key, required this.trip});

  @override
  State<ViewLogsModal> createState() => _ViewLogsModalState();
}

class _ViewLogsModalState extends State<ViewLogsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _driverLogs = [];
  List<Map<String, dynamic>> _snapshots = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentDriverId;
  Map<String, dynamic>? _currentUser;
  final bool _isOperator =
      true; // Always true since this modal is only accessible from operator page

  // Rating variables
  double _currentRating = 0.0;
  bool _isSubmittingRating = false;
  String _ratingComment = '';
  final TextEditingController _commentController = TextEditingController();

  // Driver profile and rating analytics
  String? _driverProfileImageUrl;
  String? _driverRecommendation;
  bool _isLoadingDriverData = false;

  // Real-time subscriptions
  RealtimeChannel? _behaviorLogsChannel;
  RealtimeChannel? _snapshotsChannel;
  RealtimeChannel? _ratingsChannel;
  Timer? _refreshTimer;

  // ✅ HELPER METHODS for enhanced activity logs
  String _formatTripId(Map<String, dynamic> trip) {
    if (trip['trip_ref_number'] != null &&
        trip['trip_ref_number'].toString().isNotEmpty) {
      String refNumber = trip['trip_ref_number'].toString();
      if (refNumber.length > 8) {
        return refNumber.substring(0, 8);
      }
      return refNumber;
    }

    final id = trip['id'];
    if (id != null) {
      String idStr = id.toString();
      if (idStr.length >= 3) {
        return 'TR-${idStr.substring(idStr.length - 3)}';
      } else {
        return 'TR-$idStr';
      }
    }

    return 'TR-000';
  }

  String _getDriverName() {
    final mainDriver = widget.trip['driver'] ?? {};
    if (mainDriver.isNotEmpty) {
      return '${mainDriver['first_name'] ?? ''} ${mainDriver['last_name'] ?? ''}'
          .trim();
    }
    return 'Unknown Driver';
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getEventIcon(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'drowsiness':
        return Icons.bedtime;
      case 'looking_away':
        return Icons.visibility_off;
      case 'distraction':
        return Icons.phone_android;
      case 'speeding':
        return Icons.speed;
      case 'harsh_braking':
        return Icons.warning;
      case 'system':
        return Icons.settings;
      default:
        return Icons.info;
    }
  }

  String _getEventTitle(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'drowsiness':
        return 'Drowsiness Detected';
      case 'looking_away':
        return 'Looking Away';
      case 'distraction':
        return 'Driver Distraction';
      case 'speeding':
        return 'Speeding';
      case 'harsh_braking':
        return 'Harsh Braking';
      case 'system':
        return 'System Event';
      default:
        return eventType;
    }
  }

  String _formatBehaviorDescription(Map<String, dynamic> log) {
    final behaviorType = log['behavior_type'];
    final confidence = log['confidence'];
    final duration = log['duration'];

    String description = '';

    switch (behaviorType?.toLowerCase()) {
      case 'drowsiness':
        description = 'Driver showing signs of drowsiness';
        break;
      case 'looking_away':
        description = 'Driver looking away from road';
        break;
      case 'distraction':
        description = 'Driver distraction detected';
        break;
      default:
        description = behaviorType ?? 'Unknown behavior';
    }

    if (confidence != null) {
      description += ' (${(confidence * 100).toStringAsFixed(0)}% confidence)';
    }

    if (duration != null) {
      description += ' for ${duration}s';
    }

    return description;
  }

  String _getBehaviorSeverity(String? behaviorType, double? confidence) {
    if (confidence == null) return 'INFO';

    switch (behaviorType?.toLowerCase()) {
      case 'drowsiness':
        return confidence > 0.8
            ? 'CRITICAL'
            : confidence > 0.6
                ? 'WARNING'
                : 'INFO';
      case 'looking_away':
        return confidence > 0.7 ? 'WARNING' : 'INFO';
      case 'distraction':
        return confidence > 0.75 ? 'WARNING' : 'INFO';
      default:
        return 'INFO';
    }
  }

  String _formatLocation(double? lat, double? lng) {
    if (lat == null || lng == null) return 'Unknown location';
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  String _getTripContext() {
    try {
      final startTime = widget.trip['start_time'];
      if (startTime != null) {
        final startDateTime = DateTime.parse(startTime);
        final now = DateTime.now();
        final duration = now.difference(startDateTime);

        if (duration.inHours > 6) {
          return 'long_trip';
        } else if (duration.inHours > 2) {
          return 'medium_trip';
        } else {
          return 'short_trip';
        }
      }
      return 'unknown_duration';
    } catch (e) {
      print('Error determining trip context: $e');
      return 'unknown_duration';
    }
  }

  String _getDriverContext() {
    try {
      // Determine if it's main driver or sub driver
      final mainDriverId = widget.trip['driver_id'];
      final subDriverId = widget.trip['sub_driver_id'];
      final currentDriverId = _currentDriverId;

      if (currentDriverId == mainDriverId && mainDriverId != null) {
        return 'main_driver';
      } else if (currentDriverId == subDriverId && subDriverId != null) {
        return 'sub_driver';
      } else {
        return 'unknown_driver';
      }
    } catch (e) {
      print('Error determining driver context: $e');
      return 'unknown_driver';
    }
  }

  String _getRatingContextDescription(
      String tripContext, String driverContext) {
    String contextDesc = '';

    // Trip context description
    switch (tripContext) {
      case 'long_trip':
        contextDesc += 'Long trip (6+ hours)';
        break;
      case 'medium_trip':
        contextDesc += 'Medium trip (2-6 hours)';
        break;
      case 'short_trip':
        contextDesc += 'Short trip (<2 hours)';
        break;
      default:
        contextDesc += 'Trip duration unknown';
    }

    // Driver context description
    switch (driverContext) {
      case 'main_driver':
        contextDesc += ' - Main driver';
        break;
      case 'sub_driver':
        contextDesc += ' - Sub driver';
        break;
      default:
        contextDesc += ' - Driver role unknown';
    }

    return contextDesc;
  }

  Color _getContextColor(String tripContext) {
    switch (tripContext) {
      case 'long_trip':
        return Colors.red.shade300;
      case 'medium_trip':
        return Colors.orange.shade300;
      case 'short_trip':
        return Colors.green.shade300;
      default:
        return Colors.grey;
    }
  }

  String _formatBehaviorType(String behaviorType) {
    return _formatBehaviorDescription({'behavior_type': behaviorType});
  }

  @override
  void initState() {
    super.initState();
    // Initialize TabController synchronously first
    _tabController = TabController(
      length: 2, // Always 2 tabs: Activity Logs and Snapshots
      vsync: this,
    );
    // Then initialize the modal data asynchronously
    _initializeModal();
  }

  Future<void> _initializeModal() async {
    await _getCurrentUser();
    _getCurrentDriverAndFetchLogs();
  }

  Future<void> _getCurrentUser() async {
    try {
      print('🔍 Getting current user...');

      // Since we're on the operator page and user is already authenticated,
      // let's get the operator user directly from the database
      final operatorResponse = await Supabase.instance.client
          .from('users')
          .select('*')
          .eq('role', 'operator')
          .eq('username', 'operator') // The logged-in operator
          .single();

      _currentUser = operatorResponse;
      print(
          '🔍 Found operator: ${operatorResponse['first_name']} ${operatorResponse['last_name']}');
      print('✅ Operator authentication successful');
    } catch (e) {
      print('❌ Error fetching current user: $e');

      // Fallback: create a mock operator user for testing
      _currentUser = {
        'id': '21d5611a-1659-4a5b-a7d0-f9fdb87bcffc',
        'first_name': 'Operator',
        'last_name': 'User',
        'username': 'operator',
        'role': 'operator',
      };
      print('🔧 Using fallback operator user for testing');
    }
  }

  // Fetch driver profile image and rating analytics (optimized)
  Future<void> _fetchDriverData(String driverId) async {
    if (_isLoadingDriverData) return; // Prevent multiple concurrent calls

    setState(() {
      _isLoadingDriverData = true;
    });

    try {
      // Fetch driver profile image and basic info in parallel
      final futures = await Future.wait([
        // Driver profile
        Supabase.instance.client
            .from('users')
            .select('profile_image_url, first_name, last_name')
            .eq('id', driverId)
            .maybeSingle(),
        // Rating stats (simplified query)
        Supabase.instance.client
            .from('driver_ratings')
            .select('rating')
            .eq('driver_id', driverId)
            .limit(50) // Limit to recent ratings for performance
      ]);

      final driverResponse = futures[0] as Map<String, dynamic>?;
      final ratingsResponse = futures[1] as List<dynamic>;

      if (driverResponse != null) {
        _driverProfileImageUrl = driverResponse['profile_image_url'];

        // If no profile image URL, generate a fallback one
        if (_driverProfileImageUrl == null || _driverProfileImageUrl!.isEmpty) {
          final firstName = driverResponse['first_name'] ?? 'Driver';
          _driverProfileImageUrl =
              'https://ui-avatars.com/api/?name=$firstName&background=4CAF50&color=fff&size=150';
        }
      }

      // Quick rating calculation (simplified but complete)
      if (ratingsResponse.isNotEmpty) {
        final ratings = ratingsResponse
            .map((r) => (r['rating'] as num).toDouble())
            .toList();
        final average = ratings.reduce((a, b) => a + b) / ratings.length;

        // Simple recommendation based on average
        if (average >= 4.5) {
          _driverRecommendation = '⭐ Excellent driver performance!';
        } else if (average >= 3.5) {
          _driverRecommendation = '👍 Good driver performance';
        } else {
          _driverRecommendation = '📈 Room for improvement';
        }
      } else {
        // No ratings available
        _driverRecommendation = null;
      }
    } catch (e) {
      print('❌ Error fetching driver data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDriverData = false;
        });
      }
    }
  }

  // Calculate driver rating statistics and recommendations
  Future<void> _calculateDriverRatingStats(String driverId) async {
    try {
      final ratingsResponse = await Supabase.instance.client
          .from('driver_ratings')
          .select('rating, comment, created_at')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      if (ratingsResponse.isEmpty) {
        _driverRecommendation = null;
        return;
      }

      final ratings = ratingsResponse;

      // Separate day and night ratings
      final dayRatings = <double>[];
      final nightRatings = <double>[];

      for (final rating in ratings) {
        final createdAt = DateTime.parse(rating['created_at']);
        final hour = createdAt.hour;
        final ratingValue = (rating['rating'] as num).toDouble();

        // Consider 6 AM - 6 PM as day, 6 PM - 6 AM as night
        if (hour >= 6 && hour < 18) {
          dayRatings.add(ratingValue);
        } else {
          nightRatings.add(ratingValue);
        }
      }

      // Calculate averages
      final dayAverage = dayRatings.isNotEmpty
          ? dayRatings.reduce((a, b) => a + b) / dayRatings.length
          : 0.0;
      final nightAverage = nightRatings.isNotEmpty
          ? nightRatings.reduce((a, b) => a + b) / nightRatings.length
          : 0.0;

      // Generate recommendation
      _generateDriverRecommendation(
          dayAverage, nightAverage, dayRatings.length, nightRatings.length);
    } catch (e) {
      print('❌ Error calculating rating stats: $e');
      // If the table doesn't exist, set default values
      _driverRecommendation = null;
    }
  }

  // Generate time-based driver recommendations
  void _generateDriverRecommendation(
      double dayAvg, double nightAvg, int dayCount, int nightCount) {
    if (dayCount == 0 && nightCount == 0) {
      _driverRecommendation = null;
      return;
    }

    final difference = (dayAvg - nightAvg).abs();

    if (difference < 0.5) {
      _driverRecommendation =
          "⭐ This driver performs consistently well throughout the day.";
    } else if (dayAvg > nightAvg && difference >= 0.5) {
      if (dayAvg >= 4.0) {
        _driverRecommendation =
            "🌅 This driver excels during morning shifts. Consider scheduling more day trips.";
      } else {
        _driverRecommendation =
            "🌅 This driver is better suited for morning shifts.";
      }
    } else if (nightAvg > dayAvg && difference >= 0.5) {
      if (nightAvg >= 4.0) {
        _driverRecommendation =
            "🌙 This driver performs excellently during night shifts. Ideal for evening routes.";
      } else {
        _driverRecommendation =
            "🌙 This driver is better suited for evening shifts.";
      }
    }

    // Add additional context for low sample sizes
    if (dayCount + nightCount < 5) {
      _driverRecommendation =
          "${_driverRecommendation ?? ""}\n📊 Note: Limited rating data available.";
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    // Clean up real-time subscriptions
    _behaviorLogsChannel?.unsubscribe();
    _snapshotsChannel?.unsubscribe();
    _ratingsChannel?.unsubscribe();
    // Clean up timer
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentDriverAndFetchLogs() async {
    print(
        '🔍 Starting _getCurrentDriverAndFetchLogs for trip: ${widget.trip['id']}');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get driver ID from the trip data
      final trip = widget.trip;
      String? driverId;

      // Try to get main driver ID first
      if (trip['driver_id'] != null) {
        driverId = trip['driver_id'];
      }
      // If no main driver, try to get from driver relationship
      else if (trip['driver'] != null && trip['driver']['id'] != null) {
        driverId = trip['driver']['id'];
      }

      if (driverId == null) {
        setState(() {
          _errorMessage = 'No driver ID found for this trip';
        });
        return;
      }

      _currentDriverId = driverId;
      print(
          '📝 Using driver ID for logs: $_currentDriverId for trip: ${trip['id']}');

      // Validate database connectivity and table existence
      await _validateDatabaseTables();

      // Fetch snapshots first, then process driver logs with snapshot data
      print('🔄 About to fetch snapshots first...');
      await _fetchSnapshots();

      print('🔄 About to fetch driver logs...');
      await Future.wait([
        _fetchDriverLogs(),
        if (_isOperator) _fetchExistingRating(),
      ]);
      print('✅ Finished fetching all data');

      // Set up real-time subscriptions
      _setupRealtimeSubscriptions();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch logs: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Validate that the required database tables exist and are accessible
  Future<void> _validateDatabaseTables() async {
    try {
      print('🔍 Validating database table connectivity...');

      // Test snapshots table (unified table for behavior logs)
      try {
        await Supabase.instance.client
            .from('snapshots')
            .select('count')
            .eq('event_type', 'behavior')
            .limit(1);
        print('✅ snapshots table (behavior logs) is accessible');
      } catch (e) {
        print('❌ snapshots table (behavior logs) issue: $e');
      }

      // Test snapshots table
      try {
        await Supabase.instance.client
            .from('snapshots')
            .select('count')
            .limit(1);
        print('✅ snapshots table is accessible');
      } catch (e) {
        print('❌ snapshots table issue: $e');
      }

      // Test driver_ratings table (optional)
      if (_isOperator) {
        try {
          await Supabase.instance.client
              .from('driver_ratings')
              .select('count')
              .limit(1);
          print('✅ driver_ratings table is accessible');
        } catch (e) {
          print('❌ driver_ratings table issue: $e');
          print(
              'ℹ️ Rating system may need setup - this is not critical for core functionality');
        }
      }

      print('✅ Database validation completed');
    } catch (e) {
      print('❌ Database validation error: $e');
    }
  }

  // Set up real-time subscriptions for live updates (optimized and trip-specific)
  void _setupRealtimeSubscriptions() {
    if (_currentDriverId == null) return;

    print(
        '🔗 Setting up optimized trip-specific real-time subscriptions for driver: $_currentDriverId, trip: ${widget.trip['id']}');

    // Use a debouncer to prevent excessive refreshes
    void debouncedRefresh(VoidCallback refreshFunction) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 500), refreshFunction);
    }

    // Subscribe to behavior logs updates for this specific trip (enhanced)
    _behaviorLogsChannel = Supabase.instance.client
        .channel('snapshots_behavior:trip_${widget.trip['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'snapshots',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: widget.trip['id'], // Trip-specific filtering
          ),
          callback: (payload) {
            print(
                '📡 Behavior logs update for trip ${widget.trip['id']}: ${payload.eventType}');
            debouncedRefresh(_fetchDriverLogs);
          },
        )
        .subscribe();

    // Subscribe to snapshots updates for this specific trip (enhanced)
    _snapshotsChannel = Supabase.instance.client
        .channel('snapshots:trip_${widget.trip['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'snapshots',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: widget.trip['id'], // Trip-specific filtering
          ),
          callback: (payload) {
            print(
                '📡 Snapshots update for trip ${widget.trip['id']}: ${payload.eventType}');
            debouncedRefresh(_fetchSnapshots);
          },
        )
        .subscribe();

    // Subscribe to ratings updates for this specific trip (only for operators, enhanced)
    if (_isOperator) {
      _ratingsChannel = Supabase.instance.client
          .channel('driver_ratings:trip_${widget.trip['id']}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'driver_ratings',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'trip_id',
              value: widget.trip['id'], // Trip-specific filtering
            ),
            callback: (payload) {
              print(
                  '📡 Ratings update for trip ${widget.trip['id']}: ${payload.eventType}');
              debouncedRefresh(_fetchExistingRating);
            },
          )
          .subscribe();
    }

    print(
        '✅ Optimized trip-specific real-time subscriptions set up successfully');
  }

  // Fetch snapshots from Supabase for the specific driver and trip
  Future<void> _fetchSnapshots() async {
    try {
      print(
          '📸 Fetching snapshots for driver: $_currentDriverId, trip: ${widget.trip['id']}');

      // ✅ DEBUG: First check if there are any snapshots at all
      final allSnapshotsResponse = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .order('timestamp', ascending: false)
          .limit(10);

      print(
          '🔍 DEBUG: Total snapshots in database: ${allSnapshotsResponse.length}');
      for (var snapshot in allSnapshotsResponse) {
        print(
            '   Snapshot: driver_id=${snapshot['driver_id']}, trip_id=${snapshot['trip_id']}, behavior_type=${snapshot['behavior_type']}, filename=${snapshot['filename']}');
      }

      // Enhanced query to get snapshots for specific trip and driver
      final snapshotsResponse = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .eq('driver_id', _currentDriverId!)
          .eq('trip_id', widget.trip['id']) // Ensure trip-specific data
          .order('timestamp', ascending: false);

      print('🔍 Trip-specific snapshots: ${snapshotsResponse.length}');

      // ✅ FALLBACK: If no trip-specific snapshots, try driver-only filter
      if (snapshotsResponse.isEmpty) {
        print(
            '🔄 No trip-specific snapshots found, trying driver-only filter...');
        final driverSnapshotsResponse = await Supabase.instance.client
            .from('snapshots')
            .select('*')
            .eq('driver_id', _currentDriverId!)
            .order('timestamp', ascending: false);

        print('🔍 Driver-only snapshots: ${driverSnapshotsResponse.length}');

        // If still no results, try any snapshots without driver filter (most recent)
        if (driverSnapshotsResponse.isEmpty) {
          print('🔄 No driver-specific snapshots, showing recent snapshots...');
          final recentSnapshotsResponse = await Supabase.instance.client
              .from('snapshots')
              .select('*')
              .order('timestamp', ascending: false)
              .limit(50); // Get more recent snapshots

          print(
              '🔍 Recent snapshots (no driver filter): ${recentSnapshotsResponse.length}');
          setState(() {
            _snapshots =
                List<Map<String, dynamic>>.from(recentSnapshotsResponse);
          });
        } else {
          setState(() {
            _snapshots =
                List<Map<String, dynamic>>.from(driverSnapshotsResponse);
          });
        }
      } else {
        setState(() {
          _snapshots = List<Map<String, dynamic>>.from(snapshotsResponse);
        });

        print('✅ Snapshots set in state: ${_snapshots.length} items');
        if (_snapshots.isNotEmpty) {
          print('🔍 First snapshot example: ${_snapshots.first}');
          // ✅ DEBUG: Check image_data specifically
          final firstSnapshot = _snapshots.first;
          print('🔍 Image data check:');
          print(
              '   - image_data present: ${firstSnapshot['image_data'] != null}');
          print(
              '   - image_data type: ${firstSnapshot['image_data']?.runtimeType}');
          print('   - filename: ${firstSnapshot['filename']}');
          print('   - behavior_type: ${firstSnapshot['behavior_type']}');
          if (firstSnapshot['image_data'] != null) {
            final imageData = firstSnapshot['image_data'];
            if (imageData is List) {
              print('   - image_data length: ${imageData.length}');
            } else if (imageData is String) {
              print('   - image_data string length: ${imageData.length}');
              print(
                  '   - image_data starts with: ${imageData.substring(0, imageData.length > 20 ? 20 : imageData.length)}');
            }
          }
        }
      }

      print(
          '✅ Snapshots fetched: ${_snapshots.length} items for trip ${widget.trip['id']}');
    } catch (e) {
      print('❌ Error fetching snapshots: $e');
      setState(() {
        _snapshots = [];
      });
    }
  }

  // Fetch existing rating for this driver for the specific trip (operator only)
  Future<void> _fetchExistingRating() async {
    if (!_isOperator || _currentDriverId == null) return;

    try {
      // Enhanced query to get rating for specific trip
      final ratingResponses = await Supabase.instance.client
          .from('driver_ratings')
          .select('*')
          .eq('driver_id', _currentDriverId!)
          .eq('rated_by', _currentUser!['id'])
          .eq('trip_id', widget.trip['id']) // Trip-specific rating
          .limit(1);

      if (mounted) {
        setState(() {
          if (ratingResponses.isNotEmpty) {
            final ratingResponse = ratingResponses.first;
            _currentRating = (ratingResponse['rating'] ?? 0.0).toDouble();
            _ratingComment = ratingResponse['comment'] ?? '';
            _commentController.text = _ratingComment;
            print(
                '✅ Loaded existing rating: $_currentRating stars for trip ${widget.trip['id']}');
          } else {
            // Reset to default values when no rating exists
            _currentRating = 0.0;
            _ratingComment = '';
            _commentController.text = '';
            print('📝 No existing rating found for this trip, starting fresh');
          }
        });
      }
    } catch (e) {
      print('❌ Error fetching existing rating: $e');
      // If table doesn't exist or error occurs, reset to defaults
      if (mounted) {
        setState(() {
          _currentRating = 0.0;
          _ratingComment = '';
          _commentController.text = '';
        });
      }
    }
  }

  Future<void> _fetchDriverLogs() async {
    try {
      print(
          '📝 Fetching behavior logs for driver: $_currentDriverId, trip: ${widget.trip['id']}');

      // ✅ DEBUG: First check if there are any behavior logs at all
      final allLogsResponse = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .eq('event_type', 'behavior')
          .order('timestamp', ascending: false)
          .limit(10);

      print(
          '🔍 DEBUG: Total behavior logs in database: ${allLogsResponse.length}');
      for (var log in allLogsResponse) {
        print(
            '   Log: driver_id=${log['driver_id']}, trip_id=${log['trip_id']}, behavior_type=${log['behavior_type']}, timestamp=${log['timestamp']}');
      }

      // Fetch behavior logs (this table exists)
      final behaviorLogsResponse = await Supabase.instance.client
          .from('snapshots')
          .select('*')
          .eq('driver_id', _currentDriverId!)
          .eq('event_type', 'behavior')
          .eq('trip_id', widget.trip['id'])
          .order('timestamp', ascending: false);

      print('🔍 Trip-specific behavior logs: ${behaviorLogsResponse.length}');

      List<Map<String, dynamic>> combinedLogs = [];

      // Add behavior logs
      for (var log in behaviorLogsResponse) {
        combinedLogs.add({
          'id': log['id'],
          'event_type': log['behavior_type'],
          'behavior_type': log['behavior_type'], // Keep both for compatibility
          'description': _formatBehaviorDescription(log),
          'severity':
              _getBehaviorSeverity(log['behavior_type'], log['confidence']),
          'created_at': log['timestamp'],
          'timestamp': log['timestamp'], // Keep both for compatibility
          'location': _formatLocation(log['location_lat'], log['location_lng']),
          'confidence': log['confidence'],
          'details': log['details'],
        });
      }

      // ✅ FALLBACK: If no trip-specific logs, try driver-only filter
      if (combinedLogs.isEmpty) {
        print('🔄 No trip-specific logs found, trying driver-only filter...');
        final driverLogsResponse = await Supabase.instance.client
            .from('snapshots')
            .select('*')
            .eq('driver_id', _currentDriverId!)
            .eq('event_type', 'behavior')
            .order('timestamp', ascending: false)
            .limit(50); // Get more recent logs

        print('🔍 Driver-only behavior logs: ${driverLogsResponse.length}');

        for (var log in driverLogsResponse) {
          combinedLogs.add({
            'id': log['id'],
            'event_type': log['behavior_type'],
            'behavior_type':
                log['behavior_type'], // Keep both for compatibility
            'description': _formatBehaviorDescription(log),
            'severity':
                _getBehaviorSeverity(log['behavior_type'], log['confidence']),
            'created_at': log['timestamp'],
            'timestamp': log['timestamp'], // Keep both for compatibility
            'location':
                _formatLocation(log['location_lat'], log['location_lng']),
            'confidence': log['confidence'],
            'details': log['details'],
          });
        }

        // If still no logs found, show recent logs from any driver
        if (combinedLogs.isEmpty) {
          print('🔄 No driver-specific logs, trying recent logs...');
          final recentLogsResponse = await Supabase.instance.client
              .from('snapshots')
              .select('*')
              .eq('event_type', 'behavior')
              .order('timestamp', ascending: false)
              .limit(20);

          print(
              '🔍 Recent behavior logs (no driver filter): ${recentLogsResponse.length}');

          for (var log in recentLogsResponse) {
            combinedLogs.add({
              'id': log['id'],
              'event_type': log['behavior_type'],
              'behavior_type':
                  log['behavior_type'], // Keep both for compatibility
              'description': _formatBehaviorDescription(log),
              'severity':
                  _getBehaviorSeverity(log['behavior_type'], log['confidence']),
              'created_at': log['timestamp'],
              'timestamp': log['timestamp'], // Keep both for compatibility
              'location':
                  _formatLocation(log['location_lat'], log['location_lng']),
              'confidence': log['confidence'],
              'details': log['details'],
            });
          }
        }
      }

      // If still no behavior logs exist, show recent logs regardless of driver/trip
      if (combinedLogs.isEmpty) {
        print('🔄 No driver-specific logs, showing recent logs...');
        for (var log in allLogsResponse) {
          combinedLogs.add({
            'id': log['id'],
            'event_type': log['behavior_type'],
            'description': _formatBehaviorDescription(log),
            'severity':
                _getBehaviorSeverity(log['behavior_type'], log['confidence']),
            'created_at': log['timestamp'],
            'location':
                _formatLocation(log['location_lat'], log['location_lng']),
            'confidence': log['confidence'],
            'details': log['details'],
          });
        }
      }

      // If STILL no logs, try to convert snapshots to activity logs first
      if (combinedLogs.isEmpty && _snapshots.isNotEmpty) {
        print(
            '🔄 No behavior logs found - converting snapshots to activity logs...');

        for (var snapshot in _snapshots) {
          combinedLogs.add({
            'id': snapshot['id'],
            'event_type': snapshot['behavior_type'],
            'behavior_type': snapshot['behavior_type'],
            'description': _formatBehaviorDescription({
              'behavior_type': snapshot['behavior_type'],
              'confidence': 0.85, // Default confidence for snapshots
            }),
            'severity': _getBehaviorSeverity(snapshot['behavior_type'], 0.85),
            'created_at': snapshot['created_at'],
            'timestamp': snapshot['created_at'],
            'location': 'Location from snapshot',
            'confidence': 0.85,
            'details': {
              'message': 'Real data from snapshot: ${snapshot['filename']}',
              'filename': snapshot['filename'],
              'source': 'snapshot'
            },
          });
        }
        print('✅ Converted ${_snapshots.length} snapshots to activity logs');
      }

      // If STILL no logs after checking snapshots, add sample data for testing
      if (combinedLogs.isEmpty) {
        print(
            '⚠️ No behavior logs or snapshots found - showing sample data for testing');

        // Add sample data to demonstrate the feature
        combinedLogs = [
          {
            'id': 'sample_1',
            'event_type': 'drowsiness_alert',
            'behavior_type': 'drowsiness_alert',
            'description': 'Sample: Signs of driver drowsiness detected',
            'severity': 'warning',
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 2))
                .toIso8601String(),
            'location': 'Sample Location (0.0000, 0.0000)',
            'confidence': 0.85,
            'details': {
              'message':
                  'Sample drowsiness event - this would be real data from IoT system'
            },
          },
          {
            'id': 'sample_2',
            'event_type': 'looking_away_alert',
            'behavior_type': 'looking_away_alert',
            'description': 'Sample: Driver looking away from road',
            'severity': 'warning',
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 8))
                .toIso8601String(),
            'location': 'Sample Location (0.0000, 0.0000)',
            'confidence': 0.78,
            'details': {
              'message':
                  'Sample looking away event - this would be real data from IoT system'
            },
          },
          {
            'id': 'sample_3',
            'event_type': 'phone_use_alert',
            'behavior_type': 'phone_use_alert',
            'description': 'Sample: Driver using phone while driving',
            'severity': 'warning',
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 15))
                .toIso8601String(),
            'location': 'Sample Location (0.0000, 0.0000)',
            'confidence': 0.92,
            'details': {
              'message':
                  'Sample phone usage event - this would be real data from IoT system'
            },
          },
        ];
      }

      // Sort by timestamp (newest first)
      combinedLogs.sort((a, b) {
        final aTime =
            DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
        final bTime =
            DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
        return bTime.compareTo(aTime);
      });

      setState(() {
        _driverLogs = combinedLogs;
      });

      print('✅ Total logs processed: ${_driverLogs.length}');
      print('🔍 Driver logs content: $_driverLogs');
    } catch (e) {
      print('❌ Error fetching driver logs: $e');
      // If there's an error, show informational system logs
      setState(() {
        _driverLogs = [
          {
            'id': 'system_1',
            'event_type': 'drowsiness_alert',
            'behavior_type': 'drowsiness_alert',
            'description': 'Sample: Driver showing signs of drowsiness',
            'severity': 'warning',
            'created_at': DateTime.now().toIso8601String(),
            'location': 'Sample Location',
            'confidence': 0.85,
            'details': {
              'message': 'This is a sample drowsiness detection event'
            },
          },
          {
            'id': 'system_2',
            'event_type': 'looking_away_alert',
            'behavior_type': 'looking_away_alert',
            'description': 'Sample: Driver looking away from road',
            'severity': 'warning',
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
            'location': 'Sample Location',
            'confidence': 0.78,
            'details': {
              'message': 'This is a sample looking away detection event'
            },
          },
          {
            'id': 'system_3',
            'event_type': 'system_info',
            'description': 'Monitoring system is running',
            'severity': 'info',
            'created_at': DateTime.now()
                .subtract(const Duration(minutes: 10))
                .toIso8601String(),
            'location': 'System',
            'confidence': 1.0,
            'details': {
              'message': 'Driver behavior monitoring is active and ready'
            },
          },
        ];
      });
    }
  }

  // Submit or update driver rating (operator only) - Enhanced with context awareness
  Future<void> _submitRating() async {
    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    if (!_isOperator || driverId == null || _currentRating == 0) return;

    setState(() {
      _isSubmittingRating = true;
    });

    try {
      // ✅ ENHANCED: Context-aware rating based on trip timing and driver type
      final tripContext = _getTripContext();
      final driverContext = _getDriverContext();

      final ratingData = {
        'driver_id': driverId,
        'rated_by': _currentUser!['id'],
        'rating': _currentRating,
        'comment': _commentController.text.trim(),
        'trip_id': widget.trip['id'],
        'created_at': DateTime.now().toIso8601String(),
        // Add context metadata for better analytics
        'metadata': {
          'trip_context': tripContext,
          'driver_context': driverContext,
          'trip_start_time': widget.trip['start_time'],
          'rating_context':
              _getRatingContextDescription(tripContext, driverContext),
        }
      };

      // Check if rating already exists for this trip (handle duplicates)
      final existingRatings = await Supabase.instance.client
          .from('driver_ratings')
          .select('id')
          .eq('driver_id', driverId)
          .eq('rated_by', _currentUser!['id'])
          .eq('trip_id', widget.trip['id'])
          .limit(1);

      if (existingRatings.isNotEmpty) {
        // Update the first existing rating
        await Supabase.instance.client.from('driver_ratings').update({
          'rating': _currentRating,
          'comment': _commentController.text.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existingRatings.first['id']);
      } else {
        // Insert new rating
        await Supabase.instance.client
            .from('driver_ratings')
            .insert(ratingData);
      }

      // Immediately update driver statistics for real-time feedback
      // Note: This is done in background to avoid blocking UI
      _calculateDriverRatingStats(driverId).then((_) {
        if (mounted) {
          setState(() {}); // Refresh UI with new stats
        }
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the rating dialog

        // ✅ ENHANCED: Context-aware success message
        final contextDesc =
            _getRatingContextDescription(tripContext, driverContext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Rating submitted! ($_currentRating ⭐)'),
                      Text(
                        'Context: $contextDesc',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Update the state
      setState(() {
        _ratingComment = _commentController.text.trim();
      });
    } catch (e) {
      print('❌ Error submitting rating: $e');
      if (mounted) {
        String errorMessage = 'Failed to submit rating';

        // Handle specific errors
        if (e
            .toString()
            .contains('relation "public.driver_ratings" does not exist')) {
          errorMessage =
              'Rating system not yet configured. Please contact administrator.';
        } else if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Setup',
              textColor: Colors.white,
              onPressed: () {
                // Show setup instructions
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Setup Required'),
                    content: const Text(
                        'The rating system requires database setup. '
                        'Please run the SQL script: create_driver_ratings_table.sql'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmittingRating = false;
      });
    }
  }

  // Show rating dialog (operator only)
  void _showRatingDialog() {
    if (!_isOperator) return;

    // Get driver ID and fetch driver data + existing rating
    final driverId = widget.trip['driver_id'] ?? widget.trip['sub_driver_id'];
    if (driverId != null) {
      _currentDriverId = driverId;
      _fetchDriverData(driverId);
      _fetchExistingRating(); // Load existing rating immediately
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Theme.of(context).primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Rate Driver',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Driver info with profile image
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              // Profile Image
                              _isLoadingDriverData
                                  ? const SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : CircleAvatar(
                                      radius: 30,
                                      backgroundColor:
                                          Theme.of(context).primaryColor,
                                      backgroundImage:
                                          _driverProfileImageUrl != null
                                              ? NetworkImage(
                                                  _driverProfileImageUrl!)
                                              : null,
                                      child: _driverProfileImageUrl == null
                                          ? const Icon(Icons.person,
                                              color: Colors.white, size: 30)
                                          : null,
                                    ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.trip['driver']?['first_name'] !=
                                              null
                                          ? '${widget.trip['driver']['first_name']} ${widget.trip['driver']['last_name'] ?? ''}'
                                          : 'Driver',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Driver ID: ${widget.trip['driver']?['id'] ?? 'N/A'}',
                                      style:
                                          const TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    // ✅ ENHANCED: Display trip context for rating
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color:
                                            _getContextColor(_getTripContext())
                                                .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _getRatingContextDescription(
                                            _getTripContext(),
                                            _getDriverContext()),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _getContextColor(
                                              _getTripContext()),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Rating section
                        const Text(
                          'Rate this Driver',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Star rating container with proper spacing
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Star rating row - simplified
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: List.generate(5, (index) {
                                  final isSelected = index < _currentRating;
                                  return GestureDetector(
                                    onTap: () {
                                      final newRating = (index + 1).toDouble();
                                      if (_currentRating != newRating) {
                                        HapticFeedback.selectionClick();
                                        // Update both the modal state and dialog state
                                        setState(() {
                                          _currentRating = newRating;
                                        });
                                        setDialogState(() {
                                          // This will update the dialog UI immediately
                                        });
                                      }
                                    },
                                    child: Icon(
                                      isSelected
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: isSelected
                                          ? Colors.amber
                                          : Colors.grey,
                                      size: 32,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 12),
                              // Rating text - Always show
                              Text(
                                _getRatingText(_currentRating),
                                style: TextStyle(
                                  color: _currentRating > 0
                                      ? Colors.amber
                                      : Colors.grey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Rating description - Always show
                              Text(
                                _currentRating > 0
                                    ? _getRatingDescription(_currentRating)
                                    : 'Tap a star to rate this driver',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Comment section
                        const Text(
                          'Comment (Optional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _commentController,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add your feedback about the driver...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor),
                            ),
                            filled: true,
                            fillColor: Colors.grey.withValues(alpha: 0.1),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed:
                                _currentRating > 0 && !_isSubmittingRating
                                    ? _submitRating
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSubmittingRating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Submit Rating',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.visibility,
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'View Logs',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close,
                  color: Colors.grey,
                  size: 24,
                ),
              ),
            ],
          ),
        ),

        // Trip Info
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping,
                color: Theme.of(context).primaryColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Trip ${_formatTripId(widget.trip)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Driver: ${_getDriverName()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(
                icon: Icon(Icons.list_alt, size: 20),
                text: 'Activity Logs',
              ),
              Tab(
                icon: Icon(Icons.camera_alt, size: 20),
                text: 'Snapshots',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Tab Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActivityLogsTab(),
                        _buildSnapshotsTab(),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildActivityLogsTab() {
    print(
        '🎯 Building activity logs tab - _driverLogs.length: ${_driverLogs.length}');
    print('🎯 _driverLogs content: $_driverLogs');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: _driverLogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.list_alt,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Activity Logs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No driver activity has been recorded for this trip.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _driverLogs.length,
              itemBuilder: (context, index) {
                return _buildLogItem(_driverLogs[index]);
              },
            ),
    );
  }

  Widget _buildSnapshotsTab() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: _snapshots.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Snapshots',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No snapshots are available for this driver.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                return _buildSnapshotItem(_snapshots[index]);
              },
            ),
    );
  }

  // Async image conversion helper to avoid blocking the UI thread
  Future<Uint8List?> _convertImageDataAsync(dynamic imageData) async {
    if (imageData == null) return null;

    try {
      print('📸 Image data type: ${imageData.runtimeType}');

      // Handle Uint8List directly
      if (imageData is Uint8List) {
        print('📸 Processing Uint8List with ${imageData.length} bytes');
        return imageData.isNotEmpty ? imageData : null;
      }

      // Handle List<int> directly
      if (imageData is List<int>) {
        print('📸 Processing List<int> with ${imageData.length} bytes');
        return imageData.isNotEmpty ? Uint8List.fromList(imageData) : null;
      }

      // Handle List (cast to int)
      if (imageData is List) {
        try {
          print('📸 Processing List with ${imageData.length} items');
          final intList = imageData.cast<int>();
          return intList.isNotEmpty ? Uint8List.fromList(intList) : null;
        } catch (e) {
          print('📸 Failed to cast to List<int>: $e');
          return null;
        }
      }

      // Handle PostgreSQL hex string format (\x...)
      if (imageData is String && imageData.startsWith('\\x')) {
        print('📸 Processing PostgreSQL hex string: ${imageData.length} chars');
        // Quick size check before processing
        if (imageData.length > 1000000) {
          print(
              '📸 Data too large (${imageData.length} chars), returning placeholder');
          return null;
        }
        return await _processHexStringAsync(imageData);
      }

      // Handle base64 encoded string
      if (imageData is String && !imageData.startsWith('\\x')) {
        print(
            '📸 Processing potential base64 string: ${imageData.length} chars');
        try {
          // Try to decode as base64
          final bytes = base64Decode(imageData);
          print('📸 Successfully decoded base64: ${bytes.length} bytes');
          return bytes;
        } catch (e) {
          print('📸 Not a valid base64 string: $e');
          return null;
        }
      }

      print('📸 Unsupported image data type: ${imageData.runtimeType}');
      return null;
    } catch (e) {
      print('📸 Error in async conversion: $e');
      return null;
    }
  }

  // Process hex string in background with proper yielding to avoid blocking UI
  Future<Uint8List?> _processHexStringAsync(String imageData) async {
    try {
      final hexString = imageData.substring(2); // Remove \x prefix

      if (hexString.length > 1000000) {
        // Reduced limit to 1MB
        print('📸 Data too large (${hexString.length} chars), skipping');
        return null;
      }

      print('📸 Processing hex string async...');

      // Use smaller chunks and more frequent yields
      const chunkSize = 2000;
      final List<int> bytes = [];

      for (int start = 0; start < hexString.length; start += chunkSize) {
        final end = (start + chunkSize < hexString.length)
            ? start + chunkSize
            : hexString.length;
        final chunk = hexString.substring(start, end);

        final evenChunk = chunk.length % 2 == 0
            ? chunk
            : chunk.substring(0, chunk.length - 1);

        // Process chunk
        for (int i = 0; i < evenChunk.length; i += 2) {
          final hex = evenChunk.substring(i, i + 2);
          try {
            final intValue = int.parse(hex, radix: 16);
            bytes.add(intValue);
          } catch (e) {
            // Skip invalid hex values
            continue;
          }
        }

        // Yield control back to UI thread more frequently
        if (start % 4000 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      print('📸 Hex conversion completed: ${bytes.length} bytes');

      // First, try to use the bytes directly as image data
      if (bytes.isNotEmpty) {
        // Check if the first few bytes look like a valid image header
        if (bytes.length >= 4) {
          // Check for common image format headers
          if ((bytes[0] == 0xFF &&
                  bytes[1] == 0xD8 &&
                  bytes[2] == 0xFF) || // JPEG
              (bytes[0] == 0x89 &&
                  bytes[1] == 0x50 &&
                  bytes[2] == 0x4E &&
                  bytes[3] == 0x47) || // PNG
              (bytes[0] == 0x47 &&
                  bytes[1] == 0x49 &&
                  bytes[2] == 0x46) || // GIF
              (bytes[0] == 0x42 && bytes[1] == 0x4D)) {
            // BMP
            print('📸 Detected valid image header, using bytes directly');
            return Uint8List.fromList(bytes);
          }
        }

        // If not a direct image, try to decode as JSON array
        try {
          final decodedString = String.fromCharCodes(bytes);
          if (decodedString.startsWith('[') && decodedString.endsWith(']')) {
            print('📸 Parsing JSON array async...');
            final List<dynamic> jsonArray = jsonDecode(decodedString);
            final intList = jsonArray.cast<int>();
            print('📸 Successfully converted JSON to ${intList.length} bytes');
            return Uint8List.fromList(intList);
          }
        } catch (e) {
          print('📸 JSON parsing failed: $e');
        }

        // If all else fails, return the bytes as-is (might be raw image data)
        print('📸 Using bytes as raw image data');
        return Uint8List.fromList(bytes);
      }

      return null;
    } catch (e) {
      print('📸 Error processing hex: $e');
      return null;
    }
  }

  // DEPRECATED: Replaced with async version
  // Helper function to convert image data to Uint8List
  /*
  Uint8List? _convertImageData(dynamic imageData) {
    print('📸 ========== IMAGE CONVERSION DEBUG ==========');
    if (imageData == null) {
      print('📸 Image data is null');
      return null;
    }

    try {
      print('📸 Converting image data of type: ${imageData.runtimeType}');
      print('📸 Data toString length: ${imageData.toString().length}');

      // Sample first few characters for debugging
      final dataStr = imageData.toString();
      final sampleLength = dataStr.length > 50 ? 50 : dataStr.length;
      print(
          '📸 Data sample (first $sampleLength chars): ${dataStr.substring(0, sampleLength)}');

      if (imageData is Uint8List) {
        print('📸 Data is already Uint8List, length: ${imageData.length}');
        return imageData.isNotEmpty ? imageData : null;
      } else if (imageData is List<int>) {
        print('📸 Data is List<int>, length: ${imageData.length}');
        return imageData.isNotEmpty ? Uint8List.fromList(imageData) : null;
      } else if (imageData is List) {
        // Handle cases where it might be List<dynamic>
        print('📸 Data is List<dynamic>, length: ${imageData.length}');
        try {
          final intList = imageData.cast<int>();
          return intList.isNotEmpty ? Uint8List.fromList(intList) : null;
        } catch (e) {
          print('📸 Failed to cast to List<int>: $e');
          return null;
        }
      } else if (imageData is String) {
        print('📸 Data is String, length: ${imageData.length}');

        // Check if it's base64 encoded
        if (imageData.startsWith('data:image')) {
          print('📸 Detected data URL format');
          final base64String = imageData.split(',')[1];
          try {
            final bytes = base64Decode(base64String);
            print('📸 Decoded data URL to ${bytes.length} bytes');
            return bytes;
          } catch (e) {
            print('📸 Failed to decode data URL: $e');
            return null;
          }
        } else if (imageData.startsWith('/9j/') ||
            imageData.startsWith('iVBOR') ||
            imageData.startsWith('R0lGOD')) {
          print('📸 Detected base64 image format');
          try {
            final bytes = base64Decode(imageData);
            print('📸 Decoded base64 to ${bytes.length} bytes');
            return bytes;
          } catch (e) {
            print('📸 Failed to decode base64: $e');
            return null;
          }
        } else if (imageData.startsWith('\\x')) {
          print('📸 Detected PostgreSQL hex format');
          // Remove the \x prefix and convert hex to bytes
          final hexString = imageData.substring(2);

          // Safety check for very large strings
          if (hexString.length > 2000000) {
            // 2MB limit
            print(
                '📸 WARNING: Hex string too large (${hexString.length} chars), skipping');
            return null;
          }

          // First convert hex to string in smaller chunks to avoid memory issues
          print('📸 Converting hex string in chunks...');
          String decodedString = '';
          try {
            const chunkSize = 10000; // Process 10k chars at a time
            for (int start = 0; start < hexString.length; start += chunkSize) {
              final end = (start + chunkSize < hexString.length)
                  ? start + chunkSize
                  : hexString.length;
              final chunk = hexString.substring(start, end);

              // Make sure chunk has even length
              final evenChunk = chunk.length % 2 == 0
                  ? chunk
                  : chunk.substring(0, chunk.length - 1);

              for (int i = 0; i < evenChunk.length; i += 2) {
                final hex = evenChunk.substring(i, i + 2);
                final intValue = int.parse(hex, radix: 16);
                decodedString += String.fromCharCode(intValue);
              }

              // Check periodically if we have enough to determine format
              if (start == 0 && decodedString.length > 10) {
                print(
                    '📸 First chunk decoded sample: ${decodedString.substring(0, 10)}');
              }
            }

            print('📸 Decoded hex to string, length: ${decodedString.length}');
            print(
                '📸 Decoded string sample: ${decodedString.length > 50 ? decodedString.substring(0, 50) : decodedString}');

            // Check if the decoded string is a JSON array
            if (decodedString.startsWith('[') && decodedString.endsWith(']')) {
              print('📸 Detected JSON array within hex format');
              try {
                final List<dynamic> jsonArray = jsonDecode(decodedString);
                final intList = jsonArray.cast<int>();
                print(
                    '📸 Successfully parsed JSON array to ${intList.length} bytes');
                return intList.isNotEmpty ? Uint8List.fromList(intList) : null;
              } catch (e) {
                print('📸 JSON array decode from hex failed: $e');
              }
            }

            // If not JSON, treat as raw binary data
            final bytes = <int>[];
            for (int i = 0; i < hexString.length; i += 2) {
              final hex = hexString.substring(i, i + 2);
              bytes.add(int.parse(hex, radix: 16));
            }
            print('📸 Converted hex string to ${bytes.length} bytes');
            return bytes.isNotEmpty ? Uint8List.fromList(bytes) : null;
          } catch (e) {
            print('📸 Failed to convert hex: $e');
            return null;
          }
        } else {
          print('📸 Unknown string format, trying as raw bytes');
          try {
            return Uint8List.fromList(imageData.codeUnits);
          } catch (e) {
            print('📸 Failed to convert as raw bytes: $e');
            return null;
          }
        }
      }

      print('❌ Unsupported image data type: ${imageData.runtimeType}');
      return null;
    } catch (e) {
      print('❌ Error converting image data: $e');
      return null;
    } finally {
      print('📸 ========== END IMAGE CONVERSION DEBUG ==========');
    }
  }
  */

  Widget _buildSnapshotItem(Map<String, dynamic> snapshot) {
    // Debug: Print all available fields
    print('🔍 Snapshot fields: ${snapshot.keys.toList()}');
    print(
        '📸 Snapshot data: filename=${snapshot['filename']}, behavior_type=${snapshot['behavior_type']}, image_data available=${snapshot['image_data'] != null}');

    // Get image data (binary) from the database - handle different formats
    final imageData = snapshot['image_data'];
    final filename = snapshot['filename'];

    print('📸 Image data present: ${imageData != null}, filename: $filename');
    if (imageData != null) {
      print('📸 Image data type: ${imageData.runtimeType}');
      if (imageData is List) {
        print('📸 Image data length: ${imageData.length}');
        if (imageData.isNotEmpty) {
          print('📸 First few bytes: ${imageData.take(10).toList()}');
        }
      } else if (imageData is String) {
        print('📸 String length: ${imageData.length}');
        print(
            '📸 String starts with: ${imageData.substring(0, imageData.length > 50 ? 50 : imageData.length)}');
      }
    }

    // Convert image data using async helper function to avoid UI blocking

    final timestamp = DateTime.tryParse(
        snapshot['timestamp'] ?? snapshot['created_at'] ?? '');
    final behaviorType =
        snapshot['behavior_type'] ?? snapshot['detection_type'] ?? 'unknown';

    return GestureDetector(
      onTap: () => _showSnapshotDialog(snapshot),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _convertImageDataAsync(imageData).timeout(
                    const Duration(seconds: 10),
                    onTimeout: () {
                      print('📸 Image conversion timed out');
                      return null;
                    },
                  ),
                  builder: (context, asyncSnapshot) {
                    if (asyncSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey.withValues(alpha: 0.1),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (asyncSnapshot.hasData && asyncSnapshot.data != null) {
                      return Image.memory(
                        asyncSnapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.withValues(alpha: 0.2),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Image error',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }

                    // If no data or error, show placeholder
                    return Container(
                      color: Colors.grey.withValues(alpha: 0.2),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.grey,
                            size: 32,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'No image',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getBehaviorTypeColor(behaviorType)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatBehaviorType(behaviorType),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: _getBehaviorTypeColor(behaviorType),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (timestamp != null)
                    Text(
                      _formatSnapshotTime(timestamp),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnapshotDialog(Map<String, dynamic> snapshot) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Snapshot Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Image
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder<Uint8List?>(
                      future: _convertImageDataAsync(snapshot['image_data'])
                          .timeout(
                        const Duration(seconds: 10),
                        onTimeout: () {
                          print('📸 Snapshot image conversion timed out');
                          return null;
                        },
                      ),
                      builder: (context, asyncSnapshot) {
                        if (asyncSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                            height: 200,
                            color: Colors.grey.withValues(alpha: 0.1),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(strokeWidth: 2),
                                  SizedBox(height: 8),
                                  Text('Loading image...',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        }

                        if (asyncSnapshot.hasData &&
                            asyncSnapshot.data != null) {
                          return Image.memory(
                            asyncSnapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                color: Colors.grey.withValues(alpha: 0.2),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image,
                                          color: Colors.grey, size: 48),
                                      SizedBox(height: 8),
                                      Text('Image decode error',
                                          style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        }

                        // If no data or error, show placeholder
                        return Container(
                          height: 200,
                          color: Colors.grey.withValues(alpha: 0.2),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_alt_outlined,
                                    color: Colors.grey, size: 48),
                                SizedBox(height: 8),
                                Text('No image available',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Details
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (snapshot['behavior_type'] != null)
                      _buildDetailRow('Detection Type',
                          _formatBehaviorType(snapshot['behavior_type'])),
                    if (snapshot['confidence'] != null)
                      _buildDetailRow('Confidence',
                          '${(snapshot['confidence'] * 100).toStringAsFixed(1)}%'),
                    if (snapshot['timestamp'] != null)
                      _buildDetailRow(
                          'Captured At',
                          _formatSnapshotTime(
                              DateTime.parse(snapshot['timestamp']))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getRatingText(double rating) {
    if (rating == 0) return 'Select a rating';
    if (rating <= 1) return 'Poor';
    if (rating <= 2) return 'Below Average';
    if (rating <= 3) return 'Average';
    if (rating <= 4) return 'Good';
    return 'Excellent';
  }

  String _getRatingDescription(double rating) {
    if (rating == 0) return '';
    if (rating <= 1) return 'Driver needs significant improvement';
    if (rating <= 2) return 'Driver performance is below expectations';
    if (rating <= 3) return 'Driver meets basic requirements';
    if (rating <= 4) return 'Driver performs well above average';
    return 'Outstanding driver performance!';
  }

  Color _getBehaviorTypeColor(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness':
        return Colors.red;
      case 'distraction':
        return Colors.orange;
      case 'phone_usage':
        return Colors.purple;
      case 'normal':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  String _formatSnapshotTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    // Check if this is a behavior log or old system log
    final behaviorType = log['behavior_type'] ?? log['event_type'];

    if (behaviorType != null &&
        (log['behavior_type'] != null || log['event_type'] != null)) {
      // This is a behavior log from snapshots table (event_type = 'behavior')
      return _buildBehaviorLogItem(log);
    } else {
      // This is an old system log format
      return _buildSystemLogItem(log);
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();

    // Convert UTC timestamp to local time for proper comparison
    final localTimestamp = timestamp.toLocal();
    final difference = now.difference(localTimestamp);

    // Shorter format for better UI
    final dateTime =
        '${localTimestamp.day.toString().padLeft(2, '0')}/${localTimestamp.month.toString().padLeft(2, '0')} ${localTimestamp.hour.toString().padLeft(2, '0')}:${localTimestamp.minute.toString().padLeft(2, '0')}';

    if (difference.inMinutes < 1) {
      return '$dateTime (now)';
    } else if (difference.inHours < 1) {
      return '$dateTime (${difference.inMinutes}m)';
    } else if (difference.inDays < 1) {
      return '$dateTime (${difference.inHours}h)';
    } else {
      return '$dateTime (${difference.inDays}d)';
    }
  }

  String _getBehaviorDescription(String behaviorType, dynamic details) {
    final baseDescription = _getBaseBehaviorDescription(behaviorType);

    // Add details if available
    if (details != null && details is Map) {
      if (details['confidence'] != null) {
        final confidence = (details['confidence'] * 100).round();
        return '$baseDescription ($confidence% confidence)';
      }
    }

    return baseDescription;
  }

  String _getBaseBehaviorDescription(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'looking_away_alert':
        return 'Driver was looking away from the road';
      case 'drowsiness_alert':
        return 'Signs of driver drowsiness detected';
      case 'phone_use_alert':
        return 'Driver using phone while driving';
      case 'distraction_alert':
        return 'Driver distraction detected';
      case 'speeding_alert':
        return 'Vehicle exceeding speed limit';
      case 'harsh_braking':
        return 'Sudden or harsh braking detected';
      case 'harsh_acceleration':
        return 'Aggressive acceleration detected';
      case 'sharp_turn':
        return 'Sharp turning maneuver detected';
      default:
        return 'Driver behavior alert recorded';
    }
  }

  Color _getBehaviorSeverityColor(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'looking_away_alert':
      case 'phone_use_alert':
      case 'distraction_alert':
        return Colors.orange;
      case 'drowsiness_alert':
      case 'speeding_alert':
        return Colors.red;
      case 'harsh_braking':
      case 'harsh_acceleration':
      case 'sharp_turn':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }

  IconData _getBehaviorIcon(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'looking_away_alert':
      case 'distraction_alert':
        return Icons.visibility_off;
      case 'drowsiness_alert':
        return Icons.bedtime;
      case 'phone_use_alert':
        return Icons.phone_android;
      case 'speeding_alert':
        return Icons.speed;
      case 'harsh_braking':
        return Icons.warning;
      case 'harsh_acceleration':
        return Icons.trending_up;
      case 'sharp_turn':
        return Icons.turn_right;
      default:
        return Icons.info;
    }
  }

  String _getBehaviorSeverityLevel(String behaviorType) {
    switch (behaviorType.toLowerCase()) {
      case 'drowsiness_alert':
      case 'speeding_alert':
        return 'HIGH';
      case 'looking_away_alert':
      case 'phone_use_alert':
      case 'distraction_alert':
        return 'MEDIUM';
      case 'harsh_braking':
      case 'harsh_acceleration':
      case 'sharp_turn':
        return 'LOW';
      default:
        return 'INFO';
    }
  }

  Widget _buildBehaviorLogItem(Map<String, dynamic> log) {
    final behaviorType = log['behavior_type'] ?? log['event_type'] ?? '';
    final timestamp = log['timestamp'] ?? log['created_at'] ?? '';
    final details = log['details'];
    final description =
        log['description'] ?? _getBehaviorDescription(behaviorType, details);

    // Parse timestamp
    final DateTime? logTime = DateTime.tryParse(timestamp);
    final String timeDisplay =
        logTime != null ? _formatTimestamp(logTime) : 'Unknown time';

    // Format behavior type for display
    final String displayName = _formatBehaviorType(behaviorType);
    final Color severityColor = _getBehaviorSeverityColor(behaviorType);
    final IconData icon = _getBehaviorIcon(behaviorType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.withValues(alpha: 0.15),
            Colors.grey.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: severityColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: severityColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getBehaviorSeverityLevel(behaviorType),
                  style: TextStyle(
                    color: severityColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Colors.grey[400],
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        timeDisplay,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: Colors.grey[400],
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Driver',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemLogItem(Map<String, dynamic> log) {
    final eventType = log['event_type'] ?? '';
    final severity = log['severity'] ?? 'info';
    final description = log['description'] ?? 'No description';
    final location = log['location'] ?? 'Unknown location';
    final createdAt = DateTime.tryParse(log['created_at'] ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getSeverityColor(severity).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getSeverityColor(severity).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getEventIcon(eventType),
                  color: _getSeverityColor(severity),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getEventTitle(eventType),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getSeverityColor(severity).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  severity.toUpperCase(),
                  style: TextStyle(
                    color: _getSeverityColor(severity),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.access_time,
                color: Colors.grey[400],
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                createdAt != null ? _formatDateTime(createdAt) : 'Unknown time',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.location_on,
                color: Colors.grey[400],
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                location,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
