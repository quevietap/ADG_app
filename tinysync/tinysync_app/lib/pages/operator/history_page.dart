import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/trip_lifecycle_service.dart';
import '../../widgets/enhanced_trip_card.dart';
import '../../widgets/dual_driver_rating_widget.dart';

class HistoryPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const HistoryPage({super.key, this.userData});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _completedTrips = [];
  List<Map<String, dynamic>> _canceledTrips = [];
  List<Map<String, dynamic>> _deletedTrips = [];
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;
  final Map<String, bool> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchData();
    _cleanupExpiredTrips(); // Auto-cleanup on page load
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Run cleanup before fetching data (but only occasionally to avoid spam)
      if (DateTime.now().minute % 30 == 0) { // Run cleanup every 30 minutes to reduce load
        _cleanupExpiredTrips();
      }
      
      await _fetchSessions();

      // Fetch all trip data in parallel for better performance
      final futures = await Future.wait([
        // Completed trips
        Supabase.instance.client
            .from('trips')
            .select(
                '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*), vehicles(*)')
            .eq('status', 'completed')
            .not('operator_confirmed_at', 'is', null)
            .order('end_time', ascending: false)
            .limit(50), // Limit to recent 50 trips for better performance
        
        // Canceled trips
        Supabase.instance.client
            .from('trips')
            .select(
                '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*), vehicles(*), scheduled_deletion, canceled_at')
            .eq('status', 'cancelled')
            .order('canceled_at', ascending: false)
            .limit(50), // Limit to recent 50 trips for better performance
        
        // Deleted trips
        Supabase.instance.client
            .from('trips')
            .select(
                '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*), vehicles(*), scheduled_deletion, deleted_at')
            .eq('status', 'deleted')
            .order('deleted_at', ascending: false)
            .limit(50), // Limit to recent 50 trips for better performance
      ]);

      _completedTrips = List<Map<String, dynamic>>.from(futures[0]);
      _canceledTrips = List<Map<String, dynamic>>.from(futures[1]);
      _deletedTrips = List<Map<String, dynamic>>.from(futures[2]);
      
      print('✅ Trips fetched - Completed: ${_completedTrips.length}, Canceled: ${_canceledTrips.length}, Deleted: ${_deletedTrips.length}');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch data: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSessions() async {
    try {
      print('🔍 Fetching session tab trips...');
      final sessionTabTrips = await TripLifecycleService().getSessionTabTrips();
      setState(() {
        _sessions = sessionTabTrips;
      });
      print('✅ Session tab trips fetched: ${_sessions.length} trips');
    } catch (e) {
      print('❌ Error fetching session tab trips: $e');
      setState(() {
        _errorMessage = 'Failed to fetch session tab trips: $e';
      });
    }
  }

  /// Clean up expired cancelled and deleted trips (older than 2 days)
  Future<void> _cleanupExpiredTrips() async {
    try {
      print('🧹 Starting automatic cleanup of expired trips...');
      
      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 2));
      final cutoffDateStr = cutoffDate.toIso8601String();
      
      // Get expired cancelled trips
      final expiredCancelled = await Supabase.instance.client
          .from('trips')
          .select('id, trip_ref_number, canceled_at')
          .eq('status', 'cancelled')
          .lt('canceled_at', cutoffDateStr);
      
      // Get expired deleted trips  
      final expiredDeleted = await Supabase.instance.client
          .from('trips')
          .select('id, trip_ref_number, deleted_at')
          .eq('status', 'deleted')
          .lt('deleted_at', cutoffDateStr);
      
      final totalExpired = expiredCancelled.length + expiredDeleted.length;
      
      if (totalExpired > 0) {
        print('🗑️ Found $totalExpired expired trips to clean up');
        
        // Delete expired cancelled trips (handle foreign key constraints)
        if (expiredCancelled.isNotEmpty) {
          final cancelledIds = expiredCancelled.map((trip) => trip['id']).toList();
          int deletedCount = 0;
          
          for (final tripId in cancelledIds) {
            try {
              // First, remove any schedule references
              await Supabase.instance.client
                  .from('schedules')
                  .delete()
                  .eq('trip_id', tripId);
              
              // Then delete the trip
              await Supabase.instance.client
                  .from('trips')
                  .delete()
                  .eq('id', tripId);
              
              deletedCount++;
            } catch (e) {
              print('⚠️ Could not delete cancelled trip $tripId: $e');
            }
          }
          print('✅ Deleted $deletedCount expired cancelled trips');
        }
        
        // Delete expired deleted trips (handle foreign key constraints)
        if (expiredDeleted.isNotEmpty) {
          final deletedIds = expiredDeleted.map((trip) => trip['id']).toList();
          int deletedCount = 0;
          
          for (final tripId in deletedIds) {
            try {
              // First, remove any schedule references
              await Supabase.instance.client
                  .from('schedules')
                  .delete()
                  .eq('trip_id', tripId);
              
              // Then delete the trip
              await Supabase.instance.client
                  .from('trips')
                  .delete()
                  .eq('id', tripId);
              
              deletedCount++;
            } catch (e) {
              print('⚠️ Could not delete deleted trip $tripId: $e');
            }
          }
          print('✅ Deleted $deletedCount expired deleted trips');
        }
        
        print('🎉 Cleanup completed! Removed $totalExpired expired trips');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cleaned up $totalExpired expired trips (older than 2 days)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        // Refresh data after cleanup
        _fetchData();
      } else {
        print('✅ No expired trips found for cleanup');
      }
    } catch (e) {
      print('❌ Error during automatic cleanup: $e');
      // Don't show error to user for automatic cleanup
    }
  }

  /// Manual cleanup function for operators
  Future<void> _manualCleanupExpiredTrips() async {
    try {
      print('🧹 Starting manual cleanup of expired trips...');
      
      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 2));
      final cutoffDateStr = cutoffDate.toIso8601String();
      
      // Get expired cancelled trips
      final expiredCancelled = await Supabase.instance.client
          .from('trips')
          .select('id, trip_ref_number, canceled_at')
          .eq('status', 'cancelled')
          .lt('canceled_at', cutoffDateStr);
      
      // Get expired deleted trips  
      final expiredDeleted = await Supabase.instance.client
          .from('trips')
          .select('id, trip_ref_number, deleted_at')
          .eq('status', 'deleted')
          .lt('deleted_at', cutoffDateStr);
      
      final totalExpired = expiredCancelled.length + expiredDeleted.length;
      
      if (totalExpired > 0) {
        // Show confirmation dialog
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            title: const Text(
              'Clean Up Expired Trips',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              'This will permanently delete $totalExpired expired trips (older than 2 days):\n\n'
              '• ${expiredCancelled.length} cancelled trips\n'
              '• ${expiredDeleted.length} deleted trips\n\n'
              'This action cannot be undone. Continue?',
              style: const TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        
        if (confirm == true) {
          int totalDeleted = 0;
          
          // Delete expired cancelled trips (handle foreign key constraints)
          if (expiredCancelled.isNotEmpty) {
            final cancelledIds = expiredCancelled.map((trip) => trip['id']).toList();
            int deletedCount = 0;
            
            for (final tripId in cancelledIds) {
              try {
                // First, remove any schedule references
                await Supabase.instance.client
                    .from('schedules')
                    .delete()
                    .eq('trip_id', tripId);
                
                // Then delete the trip
                await Supabase.instance.client
                    .from('trips')
                    .delete()
                    .eq('id', tripId);
                
                deletedCount++;
              } catch (e) {
                print('⚠️ Could not delete cancelled trip $tripId: $e');
              }
            }
            print('✅ Deleted $deletedCount expired cancelled trips');
            totalDeleted += deletedCount;
          }
          
          // Delete expired deleted trips (handle foreign key constraints)
          if (expiredDeleted.isNotEmpty) {
            final deletedIds = expiredDeleted.map((trip) => trip['id']).toList();
            int deletedCount = 0;
            
            for (final tripId in deletedIds) {
              try {
                // First, remove any schedule references
                await Supabase.instance.client
                    .from('schedules')
                    .delete()
                    .eq('trip_id', tripId);
                
                // Then delete the trip
                await Supabase.instance.client
                    .from('trips')
                    .delete()
                    .eq('id', tripId);
                
                deletedCount++;
              } catch (e) {
                print('⚠️ Could not delete deleted trip $tripId: $e');
              }
            }
            print('✅ Deleted $deletedCount expired deleted trips');
            totalDeleted += deletedCount;
          }
          
          print('🎉 Manual cleanup completed! Removed $totalDeleted expired trips');
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully cleaned up $totalDeleted expired trips'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          
          // Refresh data after cleanup
          _fetchData();
        }
      } else {
        // Show info message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No expired trips found for cleanup'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error during manual cleanup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cleaning up trips: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                    onPressed: _manualCleanupExpiredTrips,
                    tooltip: 'Clean Up Expired Trips',
                    color: Colors.orange.withValues(alpha: 0.9),
                    splashRadius: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _fetchData,
                    tooltip: 'Refresh Data',
                    color: Colors.white.withValues(alpha: 0.9),
                    splashRadius: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            tabs: [
              _buildModernTab('Sessions', Icons.work_history_outlined),
              _buildModernTab('Completed', Icons.check_circle_outline),
              _buildModernTab('Canceled', Icons.cancel_outlined),
              _buildModernTab('Deleted', Icons.delete_outline),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey[400],
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(4),
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          const Expanded(child: Center(child: CircularProgressIndicator())),
        if (_errorMessage != null)
          Expanded(
            child: Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        if (!_isLoading && _errorMessage == null)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDriverSessionsTab(),
                _buildTripsTab(_completedTrips, 'Completed'),
                _buildTripsTab(_canceledTrips, 'Canceled'),
                _buildTripsTab(_deletedTrips, 'Deleted'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildModernTab(String label, IconData icon) {
    return Tab(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverSessionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driver Sessions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (_sessions.isEmpty)
            _buildEmptyState('No Driver Sessions Found',
                'Driver sessions will appear here once drivers start their work sessions.'),
          if (_sessions.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                // Use EnhancedTripCard for archived trips to maintain full functionality
                return EnhancedTripCard(
                  trip: session,
                  cardIndex: index,
                  isFromSchedule: false,
                  isToday: false,
                  showRealTimeTracking: true,
                  isDriver: false,
                  isOperator: true,
                  userData: widget.userData,
                  onTripUpdated: () {
                    // Refresh data when trip is updated
                    _fetchData();
                  },
                  onAssignDriver: null, // Archived trips don't need assignment
                  onAssignVehicle: null, // Archived trips don't need assignment
                  onCancel: null, // Archived trips don't need cancel
                  onDelete: null, // Archived trips don't need delete
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTripsTab(List<Map<String, dynamic>> trips, String category) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trips.isEmpty)
            _buildEmptyState(
              'No $category Trips',
              '$category trips will appear here after trips are ${category.toLowerCase()}.',
            ),
          if (trips.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];
                return _buildTripCard(trip, category);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip, String category) {
    final driver = trip['driver'] ?? {};
    final subDriver = trip['sub_driver'] ?? {};
    final vehicle = trip['vehicles'] ?? {};
    final driverName =
        '${driver['first_name'] ?? ''} ${driver['last_name'] ?? ''}'.trim();
    final subDriverName =
        '${subDriver['first_name'] ?? ''} ${subDriver['last_name'] ?? ''}'
            .trim();

    final uniqueKey =
        '${category}_trip_${trip['id']}_${trip['trip_ref_number'] ?? 'unknown'}';
    final isExpanded = _expandedCards[uniqueKey] ?? false;

    String formattedDate = '';
    if (category == 'Completed' && trip['end_time'] != null) {
      formattedDate = _formatDateTime(DateTime.parse(trip['end_time']));
    } else if (category == 'Canceled' && trip['canceled_at'] != null) {
      formattedDate = _formatDateTime(DateTime.parse(trip['canceled_at']));
    } else if (category == 'Deleted' && trip['deleted_at'] != null) {
      formattedDate = _formatDateTime(DateTime.parse(trip['deleted_at']));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            setState(() {
              _expandedCards.clear();
              if (!isExpanded) {
                _expandedCards[uniqueKey] = true;
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                leading: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getCategoryColor(category).withValues(alpha: 0.2),
                        _getCategoryColor(category).withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getCategoryColor(category).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.local_shipping_rounded,
                    size: 24,
                    color: _getCategoryColor(category),
                  ),
                ),
                title: Text(
                  trip['trip_ref_number'] ?? 'Trip #${trip['id']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$category on $formattedDate',
                    style: TextStyle(
                      color: _getCategoryColor(category).withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Priority Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getPriorityColor(trip['priority'] ?? 'normal')
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getPriorityColor(trip['priority'] ?? 'normal')
                              .withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        (trip['priority'] ?? 'normal').toUpperCase(),
                        style: TextStyle(
                          color:
                              _getPriorityColor(trip['priority'] ?? 'normal'),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getCategoryColor(category).withValues(alpha: 0.15),
                            _getCategoryColor(category).withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getCategoryColor(category)
                              .withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          color: _getCategoryColor(category),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isExpanded) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'From: ${trip['origin'] ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward,
                              size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'To: ${trip['destination'] ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white.withValues(alpha: 0.05),
                              Colors.white.withValues(alpha: 0.1),
                            ],
                          ),
                        ),
                      ),
                      _buildTripInfoRow('Origin:', trip['origin'] ?? 'N/A'),
                      _buildTripInfoRow(
                          'Destination:', trip['destination'] ?? 'N/A'),
                      _buildTripInfoRow('Driver:',
                          driverName.isNotEmpty ? driverName : 'None'),
                      if (subDriverName.isNotEmpty)
                        _buildTripInfoRow('Sub Driver:', subDriverName),
                      _buildTripInfoRow(
                          'Vehicle:', vehicle['plate_number'] ?? 'None'),
                      if (category == 'Completed') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.schedule,
                                      color: Colors.green, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Trip Timeline',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildTripInfoRow(
                                  'Start Time:',
                                  _formatTripTime(trip['start_time'] ??
                                      trip['started_at'])),
                            ],
                          ),
                        ),
                      ],
                      if (category == 'Canceled') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.cancel_outlined,
                                      color: Colors.orange, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cancellation Details',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildTripInfoRow('Canceled On:',
                                  _formatTripTime(trip['canceled_at'])),
                              _buildTripInfoRow('Reason:',
                                  _extractCancellationReason(trip['notes'])),
                            ],
                          ),
                        ),
                      ],
                      if (category == 'Deleted') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.delete_outline,
                                      color: Colors.red, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Deletion Details',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildTripInfoRow('Deleted On:',
                                  _formatTripTime(trip['deleted_at'])),
                              _buildTripInfoRow('Reason:',
                                  _extractDeletionReason(trip['notes'])),
                            ],
                          ),
                        ),
                      ],
                      if (category == 'Completed' &&
                          (trip['driver_id'] != null ||
                              trip['sub_driver_id'] != null)) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ElevatedButton(
                            onPressed: () => _showRateDriverDialog(trip),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF3B82F6),
                                    Color(0xFF1E40AF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF3B82F6)
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  'Rate Driver',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Completed':
        return Colors.green;
      case 'Canceled':
        return Colors.orange;
      case 'Deleted':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'normal':
      case 'low':
      default:
        return Colors.blue;
    }
  }

  Widget _buildEmptyState(String title, String description) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.withValues(alpha: 0.1),
                  Colors.grey.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 45,
              color: Colors.grey.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              description,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.grey[400],
                height: 1.4,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatTripTime(dynamic timeValue) {
    if (timeValue == null) return 'N/A';

    try {
      final dateTime = DateTime.parse(timeValue.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid time';
    }
  }

  String _getTripDuration(Map<String, dynamic> trip) {
    final startTime = trip['started_at'] ?? trip['start_time'];
    final endTime = trip['completed_at'] ?? trip['end_time'];

    if (startTime != null && endTime != null) {
      try {
        final start = DateTime.parse(startTime.toString());
        final end = DateTime.parse(endTime.toString());
        final duration = end.difference(start);

        if (duration.isNegative) {
          return 'Data error';
        }

        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;

        if (hours > 0) {
          return '${hours}h ${minutes}m';
        } else {
          return '${minutes}m';
        }
      } catch (e) {
        return 'Invalid duration';
      }
    }

    if (trip['created_at'] != null && trip['updated_at'] != null) {
      try {
        final start = DateTime.parse(trip['created_at'].toString());
        final end = DateTime.parse(trip['updated_at'].toString());
        final duration = end.difference(start);

        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;

        if (hours > 0) {
          return '${hours}h ${minutes}m';
        } else {
          return '${minutes}m';
        }
      } catch (e) {
        return 'Invalid duration';
      }
    }

    return 'N/A';
  }

  void _showRateDriverDialog(Map<String, dynamic> trip) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: _buildRateDriverContent(trip),
        ),
      ),
    );
  }

  Widget _buildRateDriverContent(Map<String, dynamic> trip) {
    return DualDriverRatingWidget(
      trip: trip,
      onRatingSubmitted: () {
        // Close the dialog when rating is submitted
        Navigator.of(context).pop();

        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Driver ratings submitted successfully!'),
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Optionally refresh the data
        _fetchData();
      },
    );
  }

  /// Extract cancellation reason from notes field
  String _extractCancellationReason(String? notes) {
    if (notes == null || notes.isEmpty) {
      return 'No reason provided';
    }

    // Look for the cancellation reason pattern: "CANCELLED: [reason] ([timestamp])"
    final cancelPattern =
        RegExp(r'CANCELLED:\s*(.+?)\s*\([^)]+\)', caseSensitive: false);
    final match = cancelPattern.firstMatch(notes);

    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    // Fallback: look for any line containing "CANCELLED"
    final lines = notes.split('\n');
    for (final line in lines) {
      if (line.toUpperCase().contains('CANCELLED')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          // Remove timestamp if present
          String reason = parts.sublist(1).join(':').trim();
          final timestampPattern = RegExp(r'\s*\([^)]+\)$');
          reason = reason.replaceAll(timestampPattern, '').trim();
          if (reason.isNotEmpty) {
            return reason;
          }
        }
      }
    }

    // Final fallback: if the entire notes field doesn't contain "CANCELLED" prefix,
    // assume the whole notes field is the reason (for old format compatibility)
    if (!notes.toUpperCase().contains('CANCELLED')) {
      return notes.trim();
    }

    return 'No reason provided';
  }

  /// Extract deletion reason from notes field
  String _extractDeletionReason(String? notes) {
    if (notes == null || notes.isEmpty) {
      return 'No reason provided';
    }

    // Look for deletion reason pattern: "DELETED: [reason] ([timestamp])"
    final deletePattern =
        RegExp(r'DELETED:\s*(.+?)\s*\([^)]+\)', caseSensitive: false);
    final match = deletePattern.firstMatch(notes);

    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    // Fallback: look for any line containing "DELETED"
    final lines = notes.split('\n');
    for (final line in lines) {
      if (line.toUpperCase().contains('DELETED')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          // Remove timestamp if present
          String reason = parts.sublist(1).join(':').trim();
          final timestampPattern = RegExp(r'\s*\([^)]+\)$');
          reason = reason.replaceAll(timestampPattern, '').trim();
          if (reason.isNotEmpty) {
            return reason;
          }
        }
      }
    }

    // Final fallback: if the entire notes field doesn't contain "DELETED" prefix,
    // assume the whole notes field is the reason (for old format compatibility)
    if (!notes.toUpperCase().contains('DELETED')) {
      return notes.trim();
    }

    return 'No reason provided';
  }
}
