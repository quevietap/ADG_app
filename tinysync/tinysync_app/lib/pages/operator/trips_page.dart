import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';
import '../../services/dialog_service.dart';
import '../../services/vehicle_assignment_service.dart';
import '../../config/vehicle_status_config.dart';
import '../../widgets/enhanced_trip_card.dart';
import 'dart:math';

class TripsPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const TripsPage({super.key, this.userData});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Real-time subscriptions
  RealtimeChannel? _tripsSubscription;
  RealtimeChannel? _driversSubscription;
  RealtimeChannel? _vehiclesSubscription;

  // Add shared date/time formatting functions at the top of the class
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

  Color _getColorFromName(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'brown':
        return Colors.brown;
      case 'white':
        return Colors.white;
      default:
        return Colors.grey;
    }
  }

  @override
  void initState() {
    super.initState();
    _autoArchiveExpiredTrips(); // Auto-archive expired trips on app launch
    _fetchTrips();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    _tripsSubscription?.unsubscribe();
    _driversSubscription?.unsubscribe();
    _vehiclesSubscription?.unsubscribe();
    super.dispose();
  }

  // Set up real-time subscriptions for trip and driver status updates
  void _setupRealtimeSubscriptions() {
    // Subscribe to trips changes (assignments, status updates)
    _tripsSubscription = Supabase.instance.client
        .channel('trips_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            print('🔄 Trip update detected: ${payload.eventType}');
            print('🔄 Updated trip data: ${payload.newRecord}');
            print(
                '🔄 Trip ${payload.newRecord['id']} status is now: ${payload.newRecord['status']}');
            _fetchTrips(); // Refresh trips list
          },
        )
        .subscribe();

    // Subscribe to driver status changes
    _driversSubscription = Supabase.instance.client
        .channel('drivers_status_realtime')
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
            print('🔄 Driver status update detected');
            // Update could affect assignment dialogs, but we'll refresh on dialog open
          },
        )
        .subscribe();

    // Subscribe to vehicle changes (colors, status, etc.)
    _vehiclesSubscription = Supabase.instance.client
        .channel('vehicles_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (payload) {
            print('🔄 Vehicle update detected: ${payload.eventType}');
            print('🔄 Updated vehicle data: ${payload.newRecord}');
            // Vehicle data changed - this affects assignment dialogs
            // The dialog will get fresh data when opened, so no immediate action needed
          },
        )
        .subscribe();

    print('✅ Real-time subscriptions setup complete');
  }

  // Fetch only pending trips (no driver assigned)
  Future<void> _fetchTrips() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Auto-archive expired trips before fetching
    await _autoArchiveExpiredTrips();

    try {
      final tripsResponse = await Supabase.instance.client
          .from('trips')
          .select(
              '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*)')
          .inFilter('status',
              ['pending', 'assigned', 'in_progress', 'driver_completed']);
      var allTrips = List<Map<String, dynamic>>.from(tripsResponse);

      // Filter trips: exclude assigned trips scheduled for today (they should appear in Today Schedule)
      final today = DateTime.now();
      final todayStr =
          today.toIso8601String().split('T')[0]; // Get YYYY-MM-DD format

      var trips = allTrips.where((trip) {
        final hasMainDriver = trip['driver_id'] != null &&
            trip['driver_id'].toString().isNotEmpty;
        final hasSubDriver = trip['sub_driver_id'] != null &&
            trip['sub_driver_id'].toString().isNotEmpty;
        final hasAnyDriver = hasMainDriver || hasSubDriver;

        // If trip has no drivers assigned, keep it in pending trips
        if (!hasAnyDriver) {
          return true;
        }

        // If trip has any driver assigned, check if it's scheduled for today
        final startTime = trip['start_time'];
        if (startTime != null) {
          final tripDate = DateTime.tryParse(startTime);
          if (tripDate != null) {
            final tripDateStr = tripDate.toIso8601String().split('T')[0];
            // If assigned trip is scheduled for today, exclude it from pending trips (it goes to Today Schedule)
            if (tripDateStr == todayStr) {
              return false;
            }
          }
        }

        // Keep assigned trips that are not scheduled for today
        return true;
      }).toList();

      print(
          '📋 OPERATOR: Fetched ${allTrips.length} total trips from database');
      print(
          '📋 OPERATOR: Showing ${trips.length} trips in Pending Trips (after filtering today\'s assigned trips)');
      for (var trip in trips) {
        print(
            '📋 OPERATOR: Trip ${trip['id']} status: ${trip['status']}, driver_assigned: ${trip['driver_id'] != null}, start_time: ${trip['start_time']}');
      }

      // Sort: assigned trips first, then pending, then by priority, then deadline
      trips.sort((a, b) {
        final aHasDriver =
            a['driver_id'] != null && a['driver_id'].toString().isNotEmpty;
        final bHasDriver =
            b['driver_id'] != null && b['driver_id'].toString().isNotEmpty;

        // Assigned trips (with driver) come first
        if (aHasDriver != bHasDriver) return aHasDriver ? -1 : 1;

        const priorityOrder = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
        final aPriority = priorityOrder[a['priority']] ?? 4;
        final bPriority = priorityOrder[b['priority']] ?? 4;
        final aDue =
            DateTime.tryParse(a['end_time'] ?? a['start_time'] ?? '') ??
                DateTime(2100);
        final bDue =
            DateTime.tryParse(b['end_time'] ?? b['start_time'] ?? '') ??
                DateTime(2100);
        if (aPriority != bPriority) return aPriority.compareTo(bPriority);
        return aDue.compareTo(bDue);
      });
      final tripsWithVehicles = await Future.wait(trips.map((trip) async {
        if (!mounted) return trip;
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
      setState(() {
        _trips = List<Map<String, dynamic>>.from(tripsWithVehicles);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch trips: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Trips',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              FloatingActionButton(
                onPressed: () => _showCreateTripDialog(context),
                mini: true,
                child: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null)
            Center(
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red))),
          if (!_isLoading && _errorMessage == null && _trips.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _trips.length,
              itemBuilder: (context, index) {
                final trip = _trips[index];
                print(
                    '🏗️ CREATING EnhancedTripCard for trip ${trip['id']} - onCancel: ${true}, onDelete: ${true}');
                return EnhancedTripCard(
                  trip: trip,
                  cardIndex: index,
                  isFromSchedule: false,
                  isToday: false,
                  showRealTimeTracking: true,
                  isDriver: false,
                  isOperator: true,
                  userData: widget.userData,
                  onTripUpdated: () {
                    // Refresh trips when trip is updated
                    _fetchTrips();
                  },
                  onAssignDriver: (trip) {
                    // Use the existing assign driver method
                    _showAssignDriverDialog(trip);
                  },
                  onAssignVehicle: (trip) async {
                    // Use the existing assign truck method
                    final result = await _showAssignTruckDialog(trip);
                    if (result == true && mounted) {
                      _fetchTrips();
                    }
                  },
                  onCancel: (trip, reason) {
                    // Directly cancel the trip with the reason from the first modal
                    _cancelTrip(trip, reason);
                  },
                  onDelete: (trip, reason) {
                    print(
                        '🔴 TRIPS_PAGE: Delete callback received - Trip ID: ${trip['id']}, Reason: "$reason"');
                    // Directly call delete method with reason from EnhancedTripCard
                    _markTripAsDeleted(trip, reason);
                  },
                );
              },
            ),
          if (!_isLoading && _errorMessage == null && _trips.isEmpty)
            _buildEmptyState(),
        ],
      ),
    );
  }

  // Helper method to build status badges with icons
  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get priority icons
  IconData _getPriorityIcon(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'urgent':
        return Icons.warning;
      case 'high':
        return Icons.priority_high;
      case 'normal':
        return Icons.circle;
      case 'low':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.circle;
    }
  }

  // Helper method to build section headers
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }

  // Helper method to build detail rows with icons
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required dynamic value,
    bool isBold = false,
    bool isContact = false,
    bool isEmpty = false,
  }) {
    Widget valueWidget;

    if (isContact && value != null) {
      // Make contact clickable with tel: link
      valueWidget = GestureDetector(
        onTap: () async {
          final phoneNumber =
              value.toString().replaceAll(RegExp(r'[\s\-\(\)]'), '');
          final uri = Uri(scheme: 'tel', path: phoneNumber);
          try {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Could not launch phone app for: $phoneNumber')),
                );
              }
            }
          } catch (e) {
            debugPrint('Error launching phone app: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Error: Could not make call to $phoneNumber')),
              );
            }
          }
        },
        child: Text(
          value.toString(),
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).primaryColor,
            decoration: TextDecoration.underline,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
    } else {
      valueWidget = Text(
        value?.toString() ?? 'Not set',
        style: TextStyle(
          fontSize: 15,
          color: isEmpty ? Colors.grey : Colors.white,
          fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: label == 'Notes' ? 3 : 2,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: isEmpty ? Colors.grey : Theme.of(context).primaryColor,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: valueWidget),
      ],
    );
  }

  // Helper method to build action buttons with improved layout
  Widget _buildActionButtons(Map<String, dynamic> trip) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;

        return Column(
          children: [
            // Primary Actions (Assignment)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAssignDriverDialog(trip),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: Text(isSmallScreen ? 'Driver' : 'Assign Driver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await _showAssignTruckDialog(trip);
                      if (result == true && mounted) {
                        _fetchTrips();
                        NotificationService.showOperationResult(
                          context,
                          operation: 'assigned',
                          itemType: 'truck',
                          success: true,
                        );
                      }
                    },
                    icon: const Icon(Icons.local_shipping, size: 18),
                    label: Text(isSmallScreen ? 'Truck' : 'Assign Truck'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Secondary Actions (Destructive) - separated with spacing
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDeleteConfirmation(trip),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // Helper methods for confirmation dialogs

  Future<void> _showDeleteConfirmation(Map<String, dynamic> trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.of(context).size.height * 0.3,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Delete Trip',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete trip',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip['trip_ref_number'] ?? '#${trip['id']}'}?',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(false),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red,
                            Colors.red.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(true),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Delete Trip',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      _markTripAsDeleted(trip);
    }
  }

  Color _getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
      case 'urgent':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    final statusLower = status.toLowerCase();
    switch (statusLower) {
      case 'assigned':
      case 'assigned_to_driver':
        return Colors.orange;
      case 'in_progress':
      case 'in-progress':
      case 'active':
        return Colors.blue;
      case 'completed':
      case 'complete':
        return Colors.green;
      case 'pending':
      case 'unassigned':
        return Colors.grey;
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      case 'archived':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_shipping_outlined,
              size: 60,
              color: Colors.grey.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Pending Trips',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'All trips have been assigned to drivers or there are no trips created yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.7),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDriverDialog(Map<String, dynamic> trip) async {
    if (trip.isEmpty || trip['id'] == null) {
      debugPrint('Invalid trip data');
      return;
    }

    // Variables for the dialog state
    List<Map<String, dynamic>> drivers = [];
    List<String> selectedDriverIds = [];
    bool isLoading = true;
    String? error;

    // Load drivers function
    Future<void> loadDrivers() async {
      try {
        debugPrint('Fetching drivers using backward compatible query...');
        final response = await Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, profile_picture, role')
            .eq('role', 'driver');
        drivers = List<Map<String, dynamic>>.from(response);

        // Check which drivers have conflicting trips (time-based availability)
        final driverIds = drivers.map((d) => d['id'] as String).toList();
        final conflictingDriverIds = await _getDriversWithConflictingTrips(
            driverIds, trip['start_time'], trip['id']);

        // Fetch rating data for all drivers
        final ratingData = await _fetchDriverRatings(driverIds);

        // Merge rating data and availability status with driver data
        for (var driver in drivers) {
          final driverId = driver['id'] as String;

          // Set busy status based on time conflicts
          driver['is_busy'] = conflictingDriverIds.contains(driverId);

          // Set rating data
          final ratings = ratingData[driverId];
          if (ratings != null && ratings.isNotEmpty) {
            final ratingValues =
                ratings.map((r) => (r['rating'] as num).toDouble()).toList();
            final averageRating =
                ratingValues.reduce((a, b) => a + b) / ratingValues.length;

            driver['average_rating'] = averageRating;
            driver['total_ratings'] = ratings.length;
            driver['rating_level'] = _getRatingLevel(averageRating);
            driver['rating_color'] = _getRatingColor(averageRating);
          } else {
            driver['average_rating'] = 0.0;
            driver['total_ratings'] = 0;
            driver['rating_level'] = 'No Ratings';
            driver['rating_color'] = Colors.grey;
          }
        }

        // Sort drivers: available first, then by rating
        drivers.sort((a, b) {
          // Available drivers first
          if (a['is_busy'] != b['is_busy']) {
            return (a['is_busy'] ?? false) ? 1 : -1;
          }
          // Then by rating
          final aRating = a['average_rating'] ?? 0.0;
          final bRating = b['average_rating'] ?? 0.0;
          return bRating.compareTo(aRating);
        });

        debugPrint('Fetched drivers with ratings: ${drivers.length}');
        isLoading = false;
      } catch (e) {
        error = 'Unable to load drivers. Please check your connection.';
        debugPrint('Error fetching drivers: $e');
        isLoading = false;
      }
    }

    // Get current assigned drivers for this trip
    final String? currentMainDriverId = trip['driver_id'];
    final String? currentSubDriverId = trip['sub_driver_id'];
    selectedDriverIds = [currentMainDriverId, currentSubDriverId]
        .where((id) => id != null)
        .cast<String>()
        .toList();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Load drivers on first build
            if (isLoading && drivers.isEmpty) {
              loadDrivers().then((_) => setState(() {}));
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E1E1E),
                      Color(0xFF0A0A0A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Enhanced Header with Beautiful Gradient (matching Create New Trip)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.2),
                            Theme.of(context).primaryColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Enhanced Icon with Animation
                          Hero(
                            tag: 'assign_driver_icon',
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.assignment_ind_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Enhanced Title Section
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Assign Driver',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Select drivers for your trip',
                                  style: TextStyle(
                                    fontSize: 11,
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
                    // Content
                    Container(
                      height: 320,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                              ? Center(child: Text(error!))
                              : drivers.isEmpty
                                  ? const Center(
                                      child: Text('No drivers available'))
                                  :
                                  // Enhanced driver list with profile pictures and roles
                                  ListView.builder(
                                      itemCount: drivers.length,
                                      itemBuilder: (context, index) {
                                        final driver = drivers[index];
                                        final isSelected = selectedDriverIds
                                            .contains(driver['id']);
                                        final driverIndex = selectedDriverIds
                                            .indexOf(driver['id']);
                                        final isMainDriver = driverIndex == 0;

                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 4),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.blue.withOpacity(0.1)
                                                : Colors.grey.withOpacity(0.05),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.blue
                                                  : Colors.grey
                                                      .withOpacity(0.3),
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Tooltip(
                                            message: driver['is_busy'] == true
                                                ? 'This driver has a scheduled trip that conflicts with the selected time. Please choose a different time or driver.'
                                                : 'Driver is available for assignment',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4),
                                              leading: Stack(
                                                children: [
                                                  CircleAvatar(
                                                    backgroundColor:
                                                        Colors.grey.shade300,
                                                    backgroundImage: driver[
                                                                    'profile_picture'] !=
                                                                null &&
                                                            driver['profile_picture']
                                                                .toString()
                                                                .isNotEmpty
                                                        ? NetworkImage(driver[
                                                            'profile_picture'])
                                                        : null,
                                                    radius: 18,
                                                    child: driver['profile_picture'] ==
                                                                null ||
                                                            driver['profile_picture']
                                                                .toString()
                                                                .isEmpty
                                                        ? Text(
                                                            _getDriverInitials(
                                                                driver['first_name'] ??
                                                                    '',
                                                                driver['last_name'] ??
                                                                    ''),
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .black87,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                  // Role indicator badge
                                                  if (isSelected)
                                                    Positioned(
                                                      bottom: -1,
                                                      right: -1,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isMainDriver
                                                              ? Colors.blue
                                                              : Colors.green,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                              color:
                                                                  Colors.white,
                                                              width: 1),
                                                        ),
                                                        child: Text(
                                                          isMainDriver
                                                              ? '1'
                                                              : '2',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 8,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              title: Text(
                                                '${driver['first_name']} ${driver['last_name']}',
                                                style: TextStyle(
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Rating: ${(driver['average_rating'] ?? 0.0).toStringAsFixed(1)}/5 (${driver['total_ratings'] ?? 0} reviews)',
                                                    style: const TextStyle(
                                                        fontSize: 11),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  // Star rating display
                                                  _buildStarRating(driver[
                                                          'average_rating'] ??
                                                      0.0),
                                                  const SizedBox(height: 4),
                                                  // Driver status badges
                                                  Row(
                                                    children: [
                                                      if (driver['is_busy'] ==
                                                          true)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.red
                                                                .withOpacity(
                                                                    0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10),
                                                            border: Border.all(
                                                              color: Colors.red
                                                                  .withOpacity(
                                                                      0.3),
                                                              width: 0.5,
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'SCHEDULE CONFLICT',
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      if (isSelected &&
                                                          driver['is_busy'] ==
                                                              true)
                                                        const SizedBox(
                                                            width: 6),
                                                      if (isSelected)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isMainDriver
                                                                ? Colors.blue
                                                                : Colors.green,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                          child: Text(
                                                            isMainDriver
                                                                ? 'MAIN DRIVER'
                                                                : 'SUB DRIVER',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 8,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              trailing: Transform.scale(
                                                scale: 0.9,
                                                child: Checkbox(
                                                  value: isSelected,
                                                  onChanged: (checked) {
                                                    setState(() {
                                                      if (checked == true) {
                                                        if (selectedDriverIds
                                                                    .length <
                                                                2 &&
                                                            !selectedDriverIds
                                                                .contains(driver[
                                                                    'id'])) {
                                                          selectedDriverIds.add(
                                                              driver['id']);
                                                        }
                                                      } else {
                                                        selectedDriverIds
                                                            .remove(
                                                                driver['id']);
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ), // Close Tooltip
                                        );
                                      },
                                    ),
                    ),
                    // Action Buttons
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: selectedDriverIds.isNotEmpty
                                  ? () async {
                                      try {
                                        debugPrint(
                                            'Assigning drivers: $selectedDriverIds to trip ${trip['id']}');

                                        // Final validation: Check for time conflicts before assignment
                                        final conflictingDrivers =
                                            await _getDriversWithConflictingTrips(
                                                selectedDriverIds,
                                                trip['start_time'],
                                                trip['id']);

                                        if (conflictingDrivers.isNotEmpty) {
                                          // Show error message for conflicts
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Cannot assign drivers: Time conflict detected for ${conflictingDrivers.length} driver(s). Please check their schedules.'),
                                                backgroundColor: Colors.red,
                                                duration:
                                                    const Duration(seconds: 4),
                                              ),
                                            );
                                          }
                                          return; // Stop assignment
                                        }

                                        // Prepare update data
                                        final updateData = <String, dynamic>{};

                                        if (selectedDriverIds.isNotEmpty) {
                                          updateData['driver_id'] =
                                              selectedDriverIds[0];
                                          if (selectedDriverIds.length > 1) {
                                            updateData['sub_driver_id'] =
                                                selectedDriverIds[1];
                                          }
                                          updateData['status'] = 'assigned';
                                        }

                                        // Update the trip in database
                                        final response = await Supabase
                                            .instance.client
                                            .from('trips')
                                            .update(updateData)
                                            .eq('id', trip['id'])
                                            .select();

                                        if (response.isNotEmpty) {
                                          debugPrint(
                                              'Successfully assigned drivers to trip');

                                          // Close dialog first
                                          if (mounted) {
                                            Navigator.of(context).pop();
                                          }

                                          // Refresh the trips list
                                          if (mounted) {
                                            _fetchTrips();

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Drivers assigned successfully'),
                                                backgroundColor: Colors.green,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        debugPrint(
                                            'Error assigning drivers: $e');
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Error assigning drivers: $e'),
                                              backgroundColor: Colors.red,
                                              duration:
                                                  const Duration(seconds: 4),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  : null,
                              child: const Text('Assign'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showAssignTruckDialog(Map<String, dynamic> trip) async {
    String? selectedVehicleId;

    try {
      // Use the new vehicle assignment service to get available vehicles
      final availableVehicles =
          await VehicleAssignmentService.getAvailableVehicles();

      // Debug: Log vehicle data to check colors
      print('🔍 Available vehicles for assignment:');
      for (var vehicle in availableVehicles) {
        print(
            '  Vehicle ${vehicle['plate_number']}: color = "${vehicle['color']}" (isEmpty: ${vehicle['color']?.toString().isEmpty ?? true})');
        print(
            '    Color will show: ${vehicle['color'] != null && vehicle['color'].toString().isNotEmpty}');
      }

      if (!mounted) return false;

      return showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  constraints: BoxConstraints(
                    maxWidth: 600,
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1E1E1E),
                        Color(0xFF0A0A0A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Enhanced Header with Beautiful Gradient (matching Create New Trip)
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).primaryColor.withOpacity(0.2),
                              Theme.of(context).primaryColor.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Enhanced Icon with Animation
                            Hero(
                              tag: 'assign_truck_icon',
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).primaryColor,
                                      Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.local_shipping_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            // Enhanced Title Section
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Assign Truck to',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    trip['trip_ref_number'] ??
                                        'Trip #${trip['id']}',
                                    style: const TextStyle(
                                      fontSize: 11,
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
                      // Content
                      Container(
                        height: 320,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              // None option with enhanced styling
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: selectedVehicleId == null
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.grey.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selectedVehicleId == null
                                        ? Colors.blue
                                        : Colors.grey.withOpacity(0.3),
                                    width: selectedVehicleId == null ? 2 : 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      selectedVehicleId = null;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        // Empty space for consistency with truck color indicators
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  Colors.grey.withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 12,
                                            color: Colors.grey.withOpacity(0.6),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Text content in center
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'None - No truck assigned',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Leave trip unassigned',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Radio button on rightmost side
                                        Radio<String?>(
                                          value: null,
                                          groupValue: selectedVehicleId,
                                          onChanged: (value) {
                                            setState(() {
                                              selectedVehicleId = value;
                                            });
                                          },
                                          activeColor: Colors.blue,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Vehicle options with enhanced styling and availability indicators
                              ...availableVehicles.map((vehicle) {
                                final isSelected =
                                    selectedVehicleId == vehicle['id'];
                                final availability = vehicle['availability']
                                    as Map<String, dynamic>;
                                final isAvailable =
                                    availability['is_available'] as bool;
                                final reason = availability['reason'] as String;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.withOpacity(0.1)
                                        : isAvailable
                                            ? Colors.grey.withOpacity(0.05)
                                            : Colors.red.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.blue
                                          : isAvailable
                                              ? Colors.grey.withOpacity(0.3)
                                              : Colors.red.withOpacity(0.3),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: isAvailable
                                        ? () {
                                            setState(() {
                                              selectedVehicleId = vehicle['id'];
                                            });
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          // Color indicator on leftmost side with more space
                                          if (vehicle['color'] != null &&
                                              vehicle['color']
                                                  .toString()
                                                  .isNotEmpty) ...[
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: _getColorFromName(
                                                    vehicle['color']),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withOpacity(0.4),
                                                  width: 2,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: _getColorFromName(
                                                            vehicle['color'])
                                                        .withOpacity(0.3),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else ...[
                                            // Placeholder for vehicles without color
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.grey
                                                    .withOpacity(0.3),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withOpacity(0.2),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.palette_outlined,
                                                size: 12,
                                                color: Colors.grey
                                                    .withOpacity(0.6),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 16),
                                          // Truck information in the center
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Truck name with inline status badge
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        vehicle['plate_number'] ??
                                                            'No Plate',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: isAvailable
                                                              ? Colors.white
                                                              : Colors.grey,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    // Status badge aligned with truck name (when unavailable)
                                                    if (!isAvailable) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 6,
                                                                vertical: 2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: reason ==
                                                                  'maintenance'
                                                              ? Colors.orange
                                                                  .withOpacity(
                                                                      0.2)
                                                              : Colors.red
                                                                  .withOpacity(
                                                                      0.2),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          border: Border.all(
                                                            color: reason ==
                                                                    'maintenance'
                                                                ? Colors.orange
                                                                    .withOpacity(
                                                                        0.5)
                                                                : Colors.red
                                                                    .withOpacity(
                                                                        0.5),
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          reason ==
                                                                  'maintenance'
                                                              ? VehicleStatusConfig
                                                                      .getShortDisplayName(
                                                                          VehicleStatusConfig
                                                                              .maintenance)
                                                                  .toUpperCase()
                                                              : reason ==
                                                                      'out_of_service'
                                                                  ? VehicleStatusConfig
                                                                          .getShortDisplayName(
                                                                              VehicleStatusConfig.outOfService)
                                                                      .toUpperCase()
                                                                  : 'UNAVAILABLE',
                                                          style: TextStyle(
                                                            fontSize: 8,
                                                            color: reason ==
                                                                    'maintenance'
                                                                ? Colors.orange
                                                                : reason ==
                                                                        'out_of_service'
                                                                    ? Colors.red
                                                                    : Colors
                                                                        .red,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                // Truck contents placed under the name
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // Model
                                                    if (vehicle['model'] !=
                                                        null) ...[
                                                      Text(
                                                        vehicle['model'],
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: isAvailable
                                                              ? Colors.grey
                                                                  .withOpacity(
                                                                      0.8)
                                                              : Colors.grey
                                                                  .withOpacity(
                                                                      0.5),
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                    // Capacity and color
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.scale_outlined,
                                                          size: 12,
                                                          color: Colors.grey
                                                              .withOpacity(0.7),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          '${vehicle['capacity_kg'] ?? 'N/A'} kg',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.grey
                                                                .withOpacity(
                                                                    0.8),
                                                          ),
                                                        ),
                                                        if (vehicle['color'] !=
                                                                null &&
                                                            vehicle['color']
                                                                .toString()
                                                                .isNotEmpty) ...[
                                                          const SizedBox(
                                                              width: 12),
                                                          Icon(
                                                            Icons.palette,
                                                            size: 12,
                                                            color: Colors.grey
                                                                .withOpacity(
                                                                    0.7),
                                                          ),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            vehicle['color'],
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors.grey
                                                                  .withOpacity(
                                                                      0.8),
                                                              fontStyle:
                                                                  FontStyle
                                                                      .italic,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    // Availability message below truck contents (when unavailable)
                                                    if (!isAvailable) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        availability['message']
                                                            as String,
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: reason ==
                                                                  'maintenance'
                                                              ? Colors.orange
                                                              : reason ==
                                                                      'out_of_service'
                                                                  ? Colors.red
                                                                  : Colors.red,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Radio button on rightmost side
                                          Radio<String?>(
                                            value: vehicle['id'],
                                            groupValue: selectedVehicleId,
                                            onChanged: isAvailable
                                                ? (value) {
                                                    setState(() {
                                                      selectedVehicleId = value;
                                                    });
                                                  }
                                                : null,
                                            activeColor: Colors.blue,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      // Action Buttons
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop(false);
                                },
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  // Use the vehicle assignment service for validation
                                  final result = await VehicleAssignmentService
                                      .assignVehicleToTrip(
                                    tripId: trip['id'],
                                    vehicleId: selectedVehicleId,
                                  );

                                  if (mounted) {
                                    if (result['success']) {
                                      Navigator.of(context).pop(true);
                                      NotificationService.showSuccess(
                                        context,
                                        result['message'],
                                      );
                                    } else {
                                      NotificationService.showError(
                                        context,
                                        result['message'],
                                      );
                                    }
                                  }
                                },
                                child: const Text('Assign'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Error fetching vehicles: $e');
      if (mounted) {
        NotificationService.showError(
          context,
          'Error loading vehicles: $e',
        );
      }
      return false;
    }
  }

  Future<void> _showCreateTripDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final originController = TextEditingController();
    final destinationController = TextEditingController();
    final contactController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedPriority;
    TimeOfDay? selectedTime;
    DateTime? selectedDate;
    String? selectedVehicleId;
    List<Map<String, dynamic>> vehicles = [];

    // Fetch available vehicles using the new service
    try {
      vehicles = await VehicleAssignmentService.getAvailableVehicles();

      // Debug: Log vehicle data for create trip dialog
      print('🔍 Available vehicles for create trip:');
      for (var vehicle in vehicles) {
        print(
            '  Vehicle ${vehicle['plate_number']}: color = "${vehicle['color']}" (isEmpty: ${vehicle['color']?.toString().isEmpty ?? true})');
      }
    } catch (e) {
      debugPrint('Error fetching vehicles: $e');
      vehicles = [];
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E1E1E),
                      Color(0xFF0A0A0A),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Enhanced Header with Beautiful Gradient
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.2),
                            Theme.of(context).primaryColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Enhanced Icon with Animation
                          Hero(
                            tag: 'create_trip_icon',
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add_location_alt,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Enhanced Title Section
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create New Trip',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Plan your delivery journey',
                                  style: TextStyle(
                                    fontSize: 11,
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
                    // Enhanced Content with Better Organization
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Trip Route Section
                              _buildSectionTitle('Trip Route',
                                  'Define pickup and delivery locations'),
                              const SizedBox(height: 20),

                              // Origin Field
                              _buildEnhancedFormField(
                                label: 'Origin',
                                controller: originController,
                                icon: Icons.my_location,
                                hintText: 'Enter pickup location',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter origin';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              // Arrow Indicator
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.arrow_downward,
                                    color: Theme.of(context).primaryColor,
                                    size: 20,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Destination Field
                              _buildEnhancedFormField(
                                label: 'Destination',
                                controller: destinationController,
                                icon: Icons.location_on,
                                hintText: 'Enter delivery location',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter destination';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 32),

                              // Trip Details Section
                              _buildSectionTitle('Trip Details',
                                  'Configure priority and scheduling'),
                              const SizedBox(height: 20),

                              // Priority Field
                              _buildEnhancedDropdownField(
                                label: 'Priority Level',
                                value: selectedPriority,
                                icon: Icons.priority_high,
                                items: const [
                                  {
                                    'value': 'urgent',
                                    'label': 'Urgent',
                                    'color': Colors.red
                                  },
                                  {
                                    'value': 'high',
                                    'label': 'High',
                                    'color': Colors.orange
                                  },
                                  {
                                    'value': 'normal',
                                    'label': 'Normal',
                                    'color': Colors.blue
                                  },
                                  {
                                    'value': 'low',
                                    'label': 'Low',
                                    'color': Colors.green
                                  },
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedPriority = value;
                                  });
                                },
                                isRequired: true,
                              ),

                              const SizedBox(height: 16),

                              // Contact Field
                              _buildEnhancedFormField(
                                label: 'Contact Number',
                                controller: contactController,
                                icon: Icons.phone,
                                hintText: '+63 912 345 6789',
                                keyboardType: TextInputType.phone,
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter contact number';
                                  }

                                  // Clean the phone number (remove spaces, dashes, parentheses)
                                  final cleanedValue = value.replaceAll(
                                      RegExp(r'[\s\-\(\)]'), '');

                                  // Philippines mobile number validation
                                  // Format 1: +639XXXXXXXXX (13 chars total, 11 digits after +63)
                                  // Format 2: 09XXXXXXXXX (11 digits total)
                                  // Format 3: 9XXXXXXXXX (10 digits total)

                                  if (cleanedValue.startsWith('+63')) {
                                    // Format: +639XXXXXXXXX
                                    if (cleanedValue.length != 13) {
                                      return 'Mobile number must be 11 digits (including area code)';
                                    }
                                    final phoneDigits =
                                        cleanedValue.substring(3); // Remove +63
                                    if (!RegExp(r'^9\d{9}$')
                                        .hasMatch(phoneDigits)) {
                                      return 'Mobile number must start with 9 and be 10 digits';
                                    }
                                  } else if (cleanedValue.startsWith('0')) {
                                    // Format: 09XXXXXXXXX
                                    if (cleanedValue.length != 11) {
                                      return 'Mobile number must be 11 digits total';
                                    }
                                    if (!RegExp(r'^09\d{9}$')
                                        .hasMatch(cleanedValue)) {
                                      return 'Mobile number must start with 09 and be 11 digits';
                                    }
                                  } else if (cleanedValue.startsWith('9')) {
                                    // Format: 9XXXXXXXXX
                                    if (cleanedValue.length != 10) {
                                      return 'Mobile number must be 10 digits (without leading 0)';
                                    }
                                    if (!RegExp(r'^9\d{9}$')
                                        .hasMatch(cleanedValue)) {
                                      return 'Mobile number must start with 9 and be 10 digits';
                                    }
                                  } else {
                                    return 'Please enter a valid Philippines mobile number\n(09XXXXXXXXX or +639XXXXXXXXX)';
                                  }

                                  return null;
                                },
                                onChanged: (value) {
                                  // Auto-format phone number to Philippines format
                                  final cleanedValue = value.replaceAll(
                                      RegExp(r'[\s\-\(\)]'), '');

                                  // Prevent infinite loops by checking if formatting is needed
                                  if (cleanedValue.isNotEmpty &&
                                      !cleanedValue.startsWith('+63')) {
                                    String formattedNumber = '';

                                    if (cleanedValue.startsWith('0') &&
                                        cleanedValue.length >= 2) {
                                      // Convert 09XXXXXXXXX to +639XXXXXXXXX
                                      if (cleanedValue.startsWith('09')) {
                                        formattedNumber =
                                            '+63${cleanedValue.substring(1)}';
                                      }
                                    } else if (cleanedValue.startsWith('9')) {
                                      // Convert 9XXXXXXXXX to +639XXXXXXXXX
                                      formattedNumber = '+63$cleanedValue';
                                    }

                                    // Only update if we have a valid formatted number
                                    if (formattedNumber.isNotEmpty &&
                                        formattedNumber !=
                                            contactController.text) {
                                      // Limit to maximum valid length (+63 + 10 digits = 13 chars)
                                      if (formattedNumber.length <= 13) {
                                        contactController.text =
                                            formattedNumber;
                                        contactController.selection =
                                            TextSelection.fromPosition(
                                          TextPosition(
                                              offset: contactController
                                                  .text.length),
                                        );
                                      }
                                    }
                                  }

                                  // Limit input length to prevent overly long numbers
                                  if (contactController.text.length > 13) {
                                    contactController.text =
                                        contactController.text.substring(0, 13);
                                    contactController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset:
                                              contactController.text.length),
                                    );
                                  }
                                },
                              ),

                              const SizedBox(height: 24),

                              // Date Field
                              _buildEnhancedDateTimeField(
                                label: 'Date',
                                icon: Icons.calendar_today,
                                value: selectedDate?.toString().split(' ')[0] ??
                                    'Select date',
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 30)),
                                  );
                                  if (date != null) {
                                    setState(() {
                                      selectedDate = date;
                                    });
                                  }
                                },
                                isSelected: selectedDate != null,
                              ),

                              const SizedBox(height: 16),

                              // Time Field
                              _buildEnhancedDateTimeField(
                                label: 'Time',
                                icon: Icons.access_time,
                                value: selectedTime?.format(context) ??
                                    'Select time',
                                onTap: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now(),
                                  );
                                  if (time != null) {
                                    setState(() {
                                      selectedTime = time;
                                    });
                                  }
                                },
                                isSelected: selectedTime != null,
                              ),

                              const SizedBox(height: 32),

                              // Additional Information Section
                              _buildSectionTitle('Additional Information',
                                  'Optional details and truck assignment'),
                              const SizedBox(height: 20),

                              _buildEnhancedFormField(
                                label: 'Notes (Optional)',
                                controller: notesController,
                                icon: Icons.note_alt,
                                hintText:
                                    'Add any special instructions or notes...',
                                maxLines: 3,
                              ),

                              const SizedBox(height: 24),

                              _buildEnhancedDropdownField(
                                label: 'Assign Truck (Optional)',
                                value: selectedVehicleId,
                                icon: Icons.local_shipping,
                                items: [
                                  {
                                    'value': null,
                                    'label': 'No truck assigned',
                                    'color': Colors.grey
                                  },
                                  ...vehicles.map((vehicle) {
                                    final availability = vehicle['availability']
                                        as Map<String, dynamic>;
                                    final isAvailable =
                                        availability['is_available'] as bool;
                                    final reason =
                                        availability['reason'] as String;

                                    // Build label with vehicle color if available
                                    String labelText = isAvailable
                                        ? '${vehicle['plate_number'] ?? 'No Plate'} • ${vehicle['model'] ?? 'N/A'} (${vehicle['capacity_kg'] ?? 'N/A'} kg)'
                                        : '${vehicle['plate_number'] ?? 'No Plate'} • ${vehicle['model'] ?? 'N/A'} (${reason == 'maintenance' ? VehicleStatusConfig.getDisplayName(VehicleStatusConfig.maintenance) : reason == 'out_of_service' ? VehicleStatusConfig.getDisplayName(VehicleStatusConfig.outOfService) : 'Unavailable'})';

                                    // Add color info to label if available
                                    if (vehicle['color'] != null &&
                                        vehicle['color']
                                            .toString()
                                            .isNotEmpty) {
                                      labelText += ' • ${vehicle['color']}';
                                    }

                                    return {
                                      'value': vehicle['id'],
                                      'label': labelText,
                                      'color': vehicle['color'] != null &&
                                              vehicle['color']
                                                  .toString()
                                                  .isNotEmpty
                                          ? _getColorFromName(vehicle['color'])
                                          : (isAvailable
                                              ? Colors.grey.withOpacity(0.6)
                                              : reason == 'maintenance'
                                                  ? Colors.orange
                                                  : reason == 'out_of_service'
                                                      ? Colors.red
                                                      : Colors.red),
                                      'disabled': !isAvailable,
                                    };
                                  }),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedVehicleId = value;
                                  });
                                },
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Enhanced Action Buttons
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF2A2A2A),
                            Color(0xFF1E1E1E),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).pop(),
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.close,
                                            color: Colors.grey, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Cancel',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    if ((formKey.currentState?.validate() ??
                                            false) &&
                                        selectedDate != null &&
                                        selectedTime != null) {
                                      // Generate professional trip reference number
                                      final now = DateTime.now();
                                      final tripRefNumber =
                                          'TRIP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${Random().nextInt(999).toString().padLeft(3, '0')}';

                                      // Validate vehicle assignment before creating trip
                                      if (selectedVehicleId != null) {
                                        // First check if the selected vehicle is available in the current list
                                        final selectedVehicle =
                                            vehicles.firstWhere(
                                          (v) => v['id'] == selectedVehicleId,
                                          orElse: () => {},
                                        );

                                        if (selectedVehicle.isNotEmpty) {
                                          final availability =
                                              selectedVehicle['availability']
                                                  as Map<String, dynamic>;
                                          if (!availability['is_available']) {
                                            NotificationService.showError(
                                              context,
                                              'Cannot create trip: ${availability['message']}',
                                            );
                                            return;
                                          }
                                        }

                                        // Double-check with the service for real-time validation
                                        final validation =
                                            await VehicleAssignmentService
                                                .validateVehicleForNewTrip(
                                                    selectedVehicleId);
                                        if (!validation['is_valid']) {
                                          NotificationService.showError(
                                            context,
                                            'Cannot create trip: ${validation['message']}',
                                          );
                                          return;
                                        }
                                      }

                                      // Set status to pending since no driver is assigned yet
                                      final tripData = {
                                        'trip_ref_number': tripRefNumber,
                                        'origin': originController.text,
                                        'destination':
                                            destinationController.text,
                                        'priority': selectedPriority,
                                        'contact_person':
                                            contactController.text,
                                        'contact_phone': contactController.text,
                                        'notes': notesController.text.isEmpty
                                            ? null
                                            : notesController.text,
                                        'start_time': DateTime(
                                          selectedDate!.year,
                                          selectedDate!.month,
                                          selectedDate!.day,
                                          selectedTime!.hour,
                                          selectedTime!.minute,
                                        ).toIso8601String(),
                                        'status': 'pending',
                                        'vehicle_id': selectedVehicleId,
                                      };

                                      try {
                                        final response = await Supabase
                                            .instance.client
                                            .from('trips')
                                            .insert(tripData)
                                            .select();

                                        if (response.isNotEmpty && mounted) {
                                          final newTrip = response[0];
                                          final timeFormatted =
                                              selectedTime?.format(context) ??
                                                  '';
                                          // Always insert into Schedules
                                          await Supabase.instance.client
                                              .from('schedules')
                                              .insert({
                                            'trip_id': newTrip['id'],
                                            'vehicle_id': selectedVehicleId,
                                            'schedule_date': selectedDate
                                                ?.toIso8601String()
                                                .split('T')[0],
                                            'schedule_time': timeFormatted,
                                            'status': 'scheduled',
                                          });
                                          _fetchTrips();
                                          if (mounted) {
                                            Navigator.of(context).pop();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: const Row(
                                                  children: [
                                                    Icon(Icons.check_circle,
                                                        color: Colors.green),
                                                    SizedBox(width: 12),
                                                    Text(
                                                        'Trip created successfully!'),
                                                  ],
                                                ),
                                                backgroundColor: Colors.green
                                                    .withOpacity(0.8),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            );
                                          }
                                        } else if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'Failed to create trip')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text('Error: $e')),
                                          );
                                        }
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: const Row(
                                            children: [
                                              Icon(Icons.warning,
                                                  color: Colors.orange),
                                              SizedBox(width: 12),
                                              Text(
                                                  'Please fill all required fields'),
                                            ],
                                          ),
                                          backgroundColor:
                                              Colors.orange.withOpacity(0.8),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_task,
                                            color: Colors.white, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Create Trip',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
            );
          },
        );
      },
    );
  }

  Future<void> _cancelTrip(Map<String, dynamic> trip, String reason) async {
    print(
        '🔶 _cancelTrip: Called with Trip ID: ${trip['id']}, Reason: "$reason"');
    if (trip.isEmpty || trip['id'] == null) {
      print('❌ _cancelTrip: Invalid trip data');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Invalid trip data')),
      );
      return;
    }

    try {
      // Define deletion date locally
      final deletionDate = DateTime.now().add(const Duration(days: 10));
      final now = DateTime.now();

      // Set the status to cancelled and track when it was cancelled
      // Store reason in notes until cancellation_reason field is added
      await Supabase.instance.client.from('trips').update({
        'status': 'cancelled',
        'scheduled_deletion': deletionDate.toIso8601String(),
        'canceled_at': now.toIso8601String(),
        // Store the reason in notes for now
        'notes':
            '${trip['notes'] ?? ''}\n\nCANCELLED: $reason (${now.toString()})'
                .trim(),
      }).eq('id', trip['id']);

      _fetchTrips(); // Refresh the list
      if (mounted) {
        NotificationService.showOperationResult(
          context,
          operation: 'cancelled',
          itemType: 'trip',
          success: true,
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showOperationResult(
          context,
          operation: 'cancelled',
          itemType: 'trip',
          success: false,
          errorDetails: e.toString(),
        );
      }
    }
  }

  // Auto-archive expired unassigned trips
  Future<void> _autoArchiveExpiredTrips() async {
    try {
      final now = DateTime.now();

      // Get all pending trips
      final response = await Supabase.instance.client
          .from('trips')
          .select('*')
          .eq('status', 'pending');

      final trips = List<Map<String, dynamic>>.from(response);
      int archivedCount = 0;

      for (final trip in trips) {
        // Check if trip is unassigned (no driver and no vehicle)
        final isUnassigned = (trip['driver_id'] == null ||
                trip['driver_id'].toString().isEmpty) &&
            (trip['vehicle_id'] == null ||
                trip['vehicle_id'].toString().isEmpty);

        if (!isUnassigned) continue;

        // Check if trip date has passed
        DateTime? tripDate;
        if (trip['start_time'] != null) {
          tripDate = DateTime.tryParse(trip['start_time']);
        } else if (trip['end_time'] != null) {
          tripDate = DateTime.tryParse(trip['end_time']);
        }

        // If trip date is in the past, auto-archive it
        if (tripDate != null && tripDate.isBefore(now)) {
          final deletionDate = now.add(const Duration(days: 10));

          await Supabase.instance.client.from('trips').update({
            'status': 'deleted',
            'scheduled_deletion': deletionDate.toIso8601String(),
            'deleted_at': now.toIso8601String(),
            // Store auto-archive info in notes since other fields don't exist
            'notes':
                '${trip['notes'] ?? ''}\n\nAUTO-ARCHIVED: Unassigned trip expired (${tripDate.toString()}) - System archived on ${now.toString()}'
                    .trim(),
          }).eq('id', trip['id']);

          archivedCount++;
        }
      }

      // Log the result for debugging
      if (archivedCount > 0) {
        debugPrint('Auto-archived $archivedCount expired unassigned trips');
      }
    } catch (e) {
      debugPrint('Error auto-archiving expired trips: $e');
    }
  }

  // Public method to validate driver availability for a specific time
  static Future<bool> validateDriverAvailability({
    required String driverId,
    required String startTime,
    String? excludeTripId,
    Duration? estimatedDuration,
  }) async {
    try {
      final conflicts = await _checkDriverConflictsStatic(
          [driverId], startTime, excludeTripId, estimatedDuration);
      return !conflicts.contains(driverId);
    } catch (e) {
      print('Error validating driver availability: $e');
      return false; // Default to not available on error
    }
  }

  // Public method to get all conflicting drivers for a time slot
  static Future<List<String>> getConflictingDrivers({
    required List<String> driverIds,
    required String startTime,
    String? excludeTripId,
    Duration? estimatedDuration,
  }) async {
    try {
      final conflicts = await _checkDriverConflictsStatic(
          driverIds, startTime, excludeTripId, estimatedDuration);
      return conflicts.toList();
    } catch (e) {
      print('Error getting conflicting drivers: $e');
      return [];
    }
  }

  // Static method for checking conflicts (can be called from other classes)
  static Future<Set<String>> _checkDriverConflictsStatic(
    List<String> driverIds,
    String? newTripStartTime,
    String? excludeTripId,
    Duration? estimatedDuration,
  ) async {
    if (newTripStartTime == null || driverIds.isEmpty) {
      return <String>{};
    }

    try {
      final newTripStart = DateTime.parse(newTripStartTime);
      final duration = estimatedDuration ?? const Duration(hours: 4);
      final newTripEnd = newTripStart.add(duration);

      final bufferTime = const Duration(minutes: 30);
      final conflictStart = newTripStart.subtract(bufferTime);
      final conflictEnd = newTripEnd.add(bufferTime);

      final conflictQuery = Supabase.instance.client
          .from('trips')
          .select('id, driver_id, sub_driver_id, start_time, status')
          .inFilter(
              'status', ['pending', 'assigned', 'in_progress', 'started']);

      if (excludeTripId != null) {
        conflictQuery.neq('id', excludeTripId);
      }

      final existingTrips = await conflictQuery;
      final conflictingDriverIds = <String>{};

      for (var existingTrip in existingTrips) {
        final existingStartTime = existingTrip['start_time'] as String?;
        if (existingStartTime == null) continue;

        try {
          final existingStart = DateTime.parse(existingStartTime);
          final existingEnd = existingStart.add(duration);

          final hasTimeConflict = !(conflictEnd.isBefore(existingStart) ||
              conflictStart.isAfter(existingEnd));

          if (hasTimeConflict) {
            final conflictingMainDriver = existingTrip['driver_id'] as String?;
            final conflictingSubDriver =
                existingTrip['sub_driver_id'] as String?;

            if (conflictingMainDriver != null &&
                driverIds.contains(conflictingMainDriver)) {
              conflictingDriverIds.add(conflictingMainDriver);
            }

            if (conflictingSubDriver != null &&
                driverIds.contains(conflictingSubDriver)) {
              conflictingDriverIds.add(conflictingSubDriver);
            }
          }
        } catch (e) {
          continue;
        }
      }

      return conflictingDriverIds;
    } catch (e) {
      return <String>{};
    }
  }

  // Check for driver scheduling conflicts based on trip start times and duration
  Future<Set<String>> _getDriversWithConflictingTrips(
    List<String> driverIds,
    String? newTripStartTime,
    String? excludeTripId,
  ) async {
    if (newTripStartTime == null || driverIds.isEmpty) {
      return <String>{};
    }

    // Use the static method with detailed logging
    final conflicts = await _checkDriverConflictsStatic(
        driverIds, newTripStartTime, excludeTripId, const Duration(hours: 4));

    if (conflicts.isNotEmpty) {
      print('🔍 Driver conflict check results:');
      print('  Requested drivers: $driverIds');
      print('  Trip start time: $newTripStartTime');
      print('  Conflicting drivers: $conflicts');
    }

    return conflicts;
  }

  // Public method to manually trigger auto-archive (called by auto-archive system)
  static Future<int> manuallyArchiveExpiredTrips() async {
    try {
      final now = DateTime.now();

      // Get all pending trips
      final response = await Supabase.instance.client
          .from('trips')
          .select('*')
          .eq('status', 'pending');

      final trips = List<Map<String, dynamic>>.from(response);
      int archivedCount = 0;

      for (final trip in trips) {
        // Check if trip is unassigned (no driver and no vehicle)
        final isUnassigned = (trip['driver_id'] == null ||
                trip['driver_id'].toString().isEmpty) &&
            (trip['vehicle_id'] == null ||
                trip['vehicle_id'].toString().isEmpty);

        if (!isUnassigned) continue;

        // Check if trip date has passed
        DateTime? tripDate;
        if (trip['start_time'] != null) {
          tripDate = DateTime.tryParse(trip['start_time']);
        } else if (trip['end_time'] != null) {
          tripDate = DateTime.tryParse(trip['end_time']);
        }

        // If trip date is in the past, auto-archive it
        if (tripDate != null && tripDate.isBefore(now)) {
          final deletionDate = now.add(const Duration(days: 10));

          await Supabase.instance.client.from('trips').update({
            'status': 'deleted',
            'scheduled_deletion': deletionDate.toIso8601String(),
            'deleted_at': now.toIso8601String(),
            // Store auto-archive info in notes since other fields don't exist
            'notes':
                '${trip['notes'] ?? ''}\n\nAUTO-ARCHIVED: Unassigned trip expired (${tripDate.toString()}) - System archived on ${now.toString()}'
                    .trim(),
          }).eq('id', trip['id']);

          archivedCount++;
        }
      }

      return archivedCount;
    } catch (e) {
      debugPrint('Error in manual archive: $e');
      return 0;
    }
  }

  // Helper method for section titles
  Widget _buildSectionTitle(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for enhanced form fields
  Widget _buildEnhancedFormField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    bool isRequired = false,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[400],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
          child: TextFormField(
            controller: controller,
            validator: validator,
            onChanged: onChanged,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor.withOpacity(0.6),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.red[400]!,
                  width: 2,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: maxLines > 1 ? 12 : 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Icon(
                  icon,
                  color: Theme.of(context).primaryColor.withOpacity(0.7),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper method for enhanced dropdown fields
  Widget _buildEnhancedDropdownField({
    required String label,
    required dynamic value,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required void Function(dynamic) onChanged,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[400],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
              ),
              child: DropdownButtonFormField<dynamic>(
                value: value,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                icon: Icon(
                  Icons.expand_more,
                  color: Theme.of(context).primaryColor.withOpacity(0.7),
                  size: 16,
                ),
                isExpanded: true,
                items: items.map((item) {
                  final isDisabled = item['disabled'] == true;
                  return DropdownMenuItem<dynamic>(
                    value: item['value'],
                    enabled: !isDisabled,
                    child: SizedBox(
                      width: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item['color'] != null) ...[
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.5)
                                    : item['color'],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              item['label'],
                              style: TextStyle(
                                fontSize: 12,
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.6)
                                    : Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                validator: isRequired
                    ? (value) {
                        if (value == null) {
                          return 'Please select $label';
                        }
                        return null;
                      }
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper method for enhanced date/time fields
  Widget _buildEnhancedDateTimeField({
    required String label,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              ' *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.red[400],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor.withOpacity(0.6)
                  : Colors.grey.withOpacity(0.2),
              width: isSelected ? 2 : 1,
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
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Theme.of(context).primaryColor.withOpacity(0.7),
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.edit_calendar,
                      color: Theme.of(context).primaryColor.withOpacity(0.5),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _markTripAsDeleted(Map<String, dynamic> trip,
      [String? reason]) async {
    print(
        '🔴 _markTripAsDeleted: Called with Trip ID: ${trip['id']}, Reason: "$reason"');
    if (trip.isEmpty || trip['id'] == null) {
      print('❌ _markTripAsDeleted: Invalid trip data');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Invalid trip data')),
      );
      return;
    }

    final confirm = await DialogService.showDeleteConfirmationDialog(
      context,
      itemName: 'trip',
      customMessage:
          'Are you sure you want to delete this trip? It will be kept in the deleted section for 10 days.',
    );

    if (confirm == true) {
      try {
        // Mark as deleted and add deletion date for auto-cleanup
        final deletionDate = DateTime.now().add(const Duration(days: 10));
        final now = DateTime.now();

        // Prepare update data
        Map<String, dynamic> updateData = {
          'status': 'deleted',
          'scheduled_deletion': deletionDate.toIso8601String(),
          'deleted_at': now.toIso8601String(),
        };

        // Add reason to notes if provided
        if (reason != null && reason.trim().isNotEmpty) {
          updateData['notes'] =
              '${trip['notes'] ?? ''}\n\nDELETED: ${reason.trim()} (${now.toString()})'
                  .trim();
        }

        await Supabase.instance.client
            .from('trips')
            .update(updateData)
            .eq('id', trip['id']);

        _fetchTrips(); // Refresh the list
        if (mounted) {
          NotificationService.showOperationResult(
            context,
            operation: 'deleted',
            itemType: 'trip',
            success: true,
          );
        }
      } catch (e) {
        if (mounted) {
          NotificationService.showOperationResult(
            context,
            operation: 'deleted',
            itemType: 'trip',
            success: false,
            errorDetails: e.toString(),
          );
        }
      }
    }
  }

  // Fetch rating data for multiple drivers
  Future<Map<String, List<Map<String, dynamic>>>> _fetchDriverRatings(
      List<String> driverIds) async {
    try {
      final response = await Supabase.instance.client
          .from('driver_ratings')
          .select('driver_id, rating')
          .inFilter('driver_id', driverIds);

      // Group ratings by driver_id
      final Map<String, List<Map<String, dynamic>>> groupedRatings = {};
      for (var rating in response) {
        final driverId = rating['driver_id'] as String;
        if (!groupedRatings.containsKey(driverId)) {
          groupedRatings[driverId] = [];
        }
        groupedRatings[driverId]!.add(rating);
      }

      return groupedRatings;
    } catch (e) {
      print('Error fetching driver ratings: $e');
      return {};
    }
  }

  String _getRatingLevel(double rating) {
    if (rating >= 4.5) return 'Excellent';
    if (rating >= 4.0) return 'Very Good';
    if (rating >= 3.5) return 'Good';
    if (rating >= 3.0) return 'Average';
    if (rating > 0) return 'Needs Improvement';
    return 'No Ratings';
  }

  Color _getRatingColor(double rating) {
    if (rating >= 4.0) return Colors.green;
    if (rating >= 3.0) return Colors.orange;
    if (rating > 0) return Colors.red;
    return Colors.grey;
  }

  String _getDriverInitials(String firstName, String lastName) {
    String initials = '';
    if (firstName.isNotEmpty) {
      initials += firstName[0].toUpperCase();
    }
    if (lastName.isNotEmpty) {
      initials += lastName[0].toUpperCase();
    }
    return initials.isNotEmpty ? initials : '??';
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 14,
        );
      }),
    );
  }
}
