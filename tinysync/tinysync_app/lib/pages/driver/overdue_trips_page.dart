import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverOverdueTripsPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const DriverOverdueTripsPage({super.key, this.userData});

  @override
  State<DriverOverdueTripsPage> createState() => _DriverOverdueTripsPageState();
}

class _DriverOverdueTripsPageState extends State<DriverOverdueTripsPage> {
  List<Map<String, dynamic>> _overdueTrips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOverdueTrips();
  }

  Future<void> _loadOverdueTrips() async {
    try {
      if (widget.userData == null) return;

      final now = DateTime.now();
      final currentDriverId = widget.userData!['id'];

      // Load overdue trips for current driver
      final response = await Supabase.instance.client
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
            created_at,
            driver_id,
            sub_driver_id
          ''')
          .or('driver_id.eq.$currentDriverId,sub_driver_id.eq.$currentDriverId')
          .inFilter('status', ['assigned', 'in_progress'])
          .lt('start_time', now.toIso8601String())
          .order('start_time', ascending: true);

      setState(() {
        _overdueTrips = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading overdue trips: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getOverdueSeverity(Map<String, dynamic> trip) {
    if (trip['start_time'] == null) return 'Unknown';

    final startTime = DateTime.parse(trip['start_time'].toString());
    final now = DateTime.now();
    final overdueHours = now.difference(startTime).inHours;

    if (overdueHours > 24) return 'Critical';
    if (overdueHours > 8) return 'High';
    if (overdueHours > 2) return 'Medium';
    return 'Low';
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'Critical':
        return Colors.red;
      case 'High':
        return Colors.orange;
      case 'Medium':
        return Colors.yellow;
      case 'Low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getOverdueTime(Map<String, dynamic> trip) {
    if (trip['start_time'] == null) return 'Unknown';

    final startTime = DateTime.parse(trip['start_time'].toString());
    final now = DateTime.now();
    final difference = now.difference(startTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h overdue';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m overdue';
    } else {
      return '${difference.inMinutes}m overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Color(0xFF000000), // Pure black background
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF000000), // Pure black background
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors
                            .blue, // Solid blue background instead of transparent
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white, // White icon on blue background
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overdue Trips',
                            style: TextStyle(
                              fontSize: 20, // Reduced from 24 to 20
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Trips that need immediate attention',
                            style: TextStyle(
                              fontSize: 12, // Reduced from 14 to 12
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isLoading = true;
                        });
                        _loadOverdueTrips();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.refresh,
                                color: Colors.white,
                                size: 24,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_overdueTrips.length}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const Text(
                              'Overdue',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${_overdueTrips.where((trip) => _getOverdueSeverity(trip) == 'Critical').length}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const Text(
                              'Critical',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.red),
                  )
                : _overdueTrips.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 80,
                              color: Colors.green,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No Overdue Trips',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'All your trips are on schedule!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _overdueTrips.length,
                        itemBuilder: (context, index) {
                          final trip = _overdueTrips[index];
                          return _buildOverdueTripCard(trip);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverdueTripCard(Map<String, dynamic> trip) {
    final severity = _getOverdueSeverity(trip);
    final severityColor = _getSeverityColor(severity);
    final overdueTime = _getOverdueTime(trip);
    final isMainDriver = trip['driver_id'] == widget.userData!['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2A), Color(0xFF1E1E1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: severityColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
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
                        trip['trip_ref_number'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        overdueTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: severityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Route info
            Row(
              children: [
                const Icon(
                  Icons.route,
                  color: Colors.blue,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${trip['origin'] ?? 'N/A'} → ${trip['destination'] ?? 'N/A'}',
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

            // Role and status
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isMainDriver
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.blue.withOpacity(
                            0.2), // Changed from Colors.purple to Colors.blue
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isMainDriver ? 'Main Driver' : 'Sub Driver',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isMainDriver
                          ? Colors.blue
                          : Colors
                              .blue, // Changed from Colors.purple to Colors.blue
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trip['status']?.toString().toUpperCase() ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
