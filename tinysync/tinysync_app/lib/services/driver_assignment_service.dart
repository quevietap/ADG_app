import 'package:supabase_flutter/supabase_flutter.dart';

class DriverAssignmentService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Check if a driver is available for assignment
  static Future<Map<String, dynamic>> checkDriverAvailability(
      String driverId) async {
    // Skip function call and go directly to fallback for better performance
    try {
      final activeTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status')
          .or('driver_id.eq.$driverId,sub_driver_id.eq.$driverId')
          .inFilter('status', ['assigned', 'in_progress']);

      if (activeTrips.isNotEmpty) {
        final trip = activeTrips[0];
        final tripRef = trip['trip_ref_number'] ??
            'Trip #${trip['id']?.toString().substring(0, 8)}';
        return {
          'is_available': false,
          'current_status': 'assigned',
          'current_trip_ref': tripRef,
          'message': 'Driver is currently assigned to $tripRef',
        };
      }

      // Driver appears to be available
      return {
        'is_available': true,
        'current_status': 'available',
        'current_trip_ref': '',
        'message': 'Driver is available for assignment',
      };
    } catch (e) {
      print('Driver availability check failed: $e');
      return {
        'is_available': true, // Allow assignment if we can't check
        'current_status': 'unknown',
        'current_trip_ref': '',
        'message': 'Unable to verify availability - proceeding with assignment',
      };
    }
  }

  /// Check availability for multiple drivers in batch (more efficient)
  static Future<Map<String, Map<String, dynamic>>>
      checkMultipleDriverAvailability(List<String> driverIds) async {
    Map<String, Map<String, dynamic>> results = {};

    // Initialize all drivers as available
    for (String driverId in driverIds) {
      results[driverId] = {
        'is_available': true,
        'current_status': 'available',
        'current_trip_ref': '',
        'message': 'Driver is available for assignment',
      };
    }

    try {
      // Single query to check all drivers at once
      final activeTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status, driver_id, sub_driver_id')
          .inFilter('status', ['assigned', 'in_progress']);

      // Filter trips that involve any of our drivers
      final relevantTrips = activeTrips.where((trip) {
        final driverId = trip['driver_id'];
        final subDriverId = trip['sub_driver_id'];
        return (driverId != null && driverIds.contains(driverId)) ||
            (subDriverId != null && driverIds.contains(subDriverId));
      }).toList();

      // Update results for drivers that are assigned
      for (var trip in relevantTrips) {
        final tripRef = trip['trip_ref_number'] ??
            'Trip #${trip['id']?.toString().substring(0, 8)}';

        // Check if driver is main driver
        if (trip['driver_id'] != null &&
            driverIds.contains(trip['driver_id'])) {
          results[trip['driver_id']] = {
            'is_available': false,
            'current_status': 'assigned',
            'current_trip_ref': tripRef,
            'message': 'Driver is currently assigned to $tripRef',
          };
        }

        // Check if driver is sub driver
        if (trip['sub_driver_id'] != null &&
            driverIds.contains(trip['sub_driver_id'])) {
          results[trip['sub_driver_id']] = {
            'is_available': false,
            'current_status': 'assigned',
            'current_trip_ref': tripRef,
            'message': 'Driver is currently assigned to $tripRef as sub-driver',
          };
        }
      }
    } catch (e) {
      print('Batch driver availability check failed: $e');
      // Keep all drivers as available if check fails
    }

    return results;
  }

  /// Get all available drivers with their status
  static Future<List<Map<String, dynamic>>> getAvailableDrivers() async {
    try {
      // Try to use the new driver_availability view
      final response = await _client
          .from('driver_availability')
          .select('*')
          .order('is_available', ascending: false)
          .order('first_name');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Driver availability view not available, using fallback: $e');

      // Fallback: Get drivers from users table and manually check availability
      try {
        final drivers = await _client
            .from('users')
            .select('id, first_name, last_name, driver_status, current_trip_id')
            .eq('role', 'driver')
            .order('first_name');

        return List<Map<String, dynamic>>.from(drivers).map((driver) {
          return {
            ...driver,
            'is_available':
                (driver['driver_status'] ?? 'available') == 'available',
            'current_trip_ref': null, // Would need another query to get this
            'current_trip_status': null,
          };
        }).toList();
      } catch (fallbackError) {
        print('Fallback driver fetch failed: $fallbackError');

        // Last resort: basic driver list
        final basicDrivers = await _client
            .from('users')
            .select('id, first_name, last_name')
            .eq('role', 'driver')
            .order('first_name');

        return List<Map<String, dynamic>>.from(basicDrivers).map((driver) {
          return {
            ...driver,
            'driver_status': 'available',
            'current_trip_id': null,
            'is_available': true,
            'current_trip_ref': null,
            'current_trip_status': null,
          };
        }).toList();
      }
    }
  }

  /// Assign drivers to a trip with availability validation
  static Future<Map<String, dynamic>> assignDriversToTrip({
    required String tripId,
    String? mainDriverId,
    String? subDriverId,
    String? assignedBy,
  }) async {
    try {
      // Check availability of all drivers first
      final List<String> driverIds = [mainDriverId, subDriverId]
          .where((id) => id != null)
          .cast<String>()
          .toList();

      for (String driverId in driverIds) {
        final availability = await checkDriverAvailability(driverId);
        if (!availability['is_available']) {
          return {
            'success': false,
            'message': availability['message'],
            'error': 'driver_not_available',
          };
        }
      }

      // If all drivers are available, proceed with assignment
      final updateData = <String, dynamic>{
        'status': 'assigned',
        // Remove assigned_at since column doesn't exist in current schema
        // 'assigned_at': DateTime.now().toIso8601String(),
      };

      if (mainDriverId != null) updateData['driver_id'] = mainDriverId;
      if (subDriverId != null) updateData['sub_driver_id'] = subDriverId;
      // Remove assigned_by since column doesn't exist in current schema
      // if (assignedBy != null) updateData['assigned_by'] = assignedBy;

      await _client.from('trips').update(updateData).eq('id', tripId);

      return {
        'success': true,
        'message': 'Drivers assigned successfully',
        'assigned_drivers': driverIds.length,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error assigning drivers: $e',
        'error': 'assignment_failed',
      };
    }
  }

  /// Complete a trip and make drivers available
  static Future<Map<String, dynamic>> completeTrip(String tripId) async {
    try {
      await _client.from('trips').update({
        'status': 'completed',
        // Remove completed_at since column might not exist in current schema
        // 'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', tripId);

      return {
        'success': true,
        'message': 'Trip completed successfully. Drivers are now available.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error completing trip: $e',
      };
    }
  }

  /// Cancel a trip and make drivers available
  static Future<Map<String, dynamic>> cancelTrip(
      String tripId, String reason) async {
    try {
      await _client.from('trips').update({
        'status': 'cancelled',
        // Remove canceled_at and notes since columns might not exist in current schema
        // 'canceled_at': DateTime.now().toIso8601String(),
        // 'notes': reason,
      }).eq('id', tripId);

      return {
        'success': true,
        'message': 'Trip cancelled successfully. Drivers are now available.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error cancelling trip: $e',
      };
    }
  }

  /// Get driver assignment history
  static Future<List<Map<String, dynamic>>> getDriverAssignmentHistory(
      String driverId) async {
    try {
      final response = await _client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            status,
            assigned_at,
            completed_at,
            canceled_at,
            origin,
            destination
          ''')
          .or('driver_id.eq.$driverId,sub_driver_id.eq.$driverId')
          .order('assigned_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching driver assignment history: $e');
      return [];
    }
  }

  /// Get current active assignments count by status
  static Future<Map<String, int>> getAssignmentStats() async {
    try {
      final response = await _client
          .from('trips')
          .select('status')
          .inFilter('status', ['assigned', 'in_progress']);

      final trips = List<Map<String, dynamic>>.from(response);
      final stats = <String, int>{
        'assigned': 0,
        'in_progress': 0,
        'total_active': 0,
      };

      for (final trip in trips) {
        final status = trip['status'];
        stats[status] = (stats[status] ?? 0) + 1;
        stats['total_active'] = (stats['total_active'] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      print('Error fetching assignment stats: $e');
      return {
        'assigned': 0,
        'in_progress': 0,
        'total_active': 0,
      };
    }
  }

  /// Subscribe to real-time driver status changes
  static RealtimeChannel subscribeToDriverStatusChanges({
    required Function(Map<String, dynamic>) onStatusChange,
  }) {
    return _client.channel('driver_status_changes').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'role',
            value: 'driver',
          ),
          callback: (payload) {
            onStatusChange(payload.newRecord);
          },
        );
  }

  /// Subscribe to real-time trip assignment changes
  static RealtimeChannel subscribeToTripAssignments({
    required Function(Map<String, dynamic>) onTripChange,
  }) {
    return _client.channel('trip_assignments').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            onTripChange(payload.newRecord);
          },
        );
  }
}
