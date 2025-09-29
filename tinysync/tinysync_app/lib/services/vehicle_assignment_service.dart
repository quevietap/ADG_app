import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/vehicle_status_config.dart';

class VehicleAssignmentService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Check if a vehicle is available for assignment
  static Future<Map<String, dynamic>> checkVehicleAvailability(
      String vehicleId) async {
    try {
      // Check if vehicle is under maintenance or out of service
      final vehicleResponse = await _client
          .from('vehicles')
          .select('id, plate_number, status')
          .eq('id', vehicleId)
          .single();

      if (VehicleStatusConfig.isUnderMaintenance(vehicleResponse['status'])) {
        return {
          'is_available': false,
          'current_status': 'maintenance',
          'current_trip_ref': '',
          'message': 'Vehicle ${vehicleResponse['plate_number']} is under maintenance',
          'reason': VehicleStatusConfig.getReasonCode(vehicleResponse['status']),
        };
      }

      if (VehicleStatusConfig.isOutOfService(vehicleResponse['status'])) {
        return {
          'is_available': false,
          'current_status': 'out_of_service',
          'current_trip_ref': '',
          'message': 'Vehicle ${vehicleResponse['plate_number']} is out of service',
          'reason': VehicleStatusConfig.getReasonCode(vehicleResponse['status']),
        };
      }

      // Check if vehicle is already assigned to active or scheduled trips
      final activeTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status, start_time')
          .eq('vehicle_id', vehicleId)
          .inFilter('status', ['assigned', 'in_progress']);

      if (activeTrips.isNotEmpty) {
        final trip = activeTrips[0];
        final tripRef = trip['trip_ref_number'] ??
            'Trip #${trip['id']?.toString().substring(0, 8)}';
        return {
          'is_available': false,
          'current_status': 'assigned',
          'current_trip_ref': tripRef,
          'message': 'Vehicle ${vehicleResponse['plate_number']} is already assigned to $tripRef',
          'reason': 'assigned',
        };
      }

      // Check for scheduled trips (future trips)
      final scheduledTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status, start_time')
          .eq('vehicle_id', vehicleId)
          .eq('status', 'pending')
          .gte('start_time', DateTime.now().toIso8601String());

      if (scheduledTrips.isNotEmpty) {
        final trip = scheduledTrips[0];
        final tripRef = trip['trip_ref_number'] ??
            'Trip #${trip['id']?.toString().substring(0, 8)}';
        return {
          'is_available': false,
          'current_status': 'scheduled',
          'current_trip_ref': tripRef,
          'message': 'Vehicle ${vehicleResponse['plate_number']} is scheduled for $tripRef',
          'reason': 'scheduled',
        };
      }

      // Vehicle appears to be available
      return {
        'is_available': true,
        'current_status': 'available',
        'current_trip_ref': '',
        'message': 'Vehicle ${vehicleResponse['plate_number']} is available for assignment',
        'reason': 'available',
      };
    } catch (e) {
      print('Vehicle availability check failed: $e');
      return {
        'is_available': true, // Allow assignment if we can't check
        'current_status': 'unknown',
        'current_trip_ref': '',
        'message': 'Unable to verify availability - proceeding with assignment',
        'reason': 'unknown',
      };
    }
  }

  /// Check availability for multiple vehicles in batch (more efficient)
  static Future<Map<String, Map<String, dynamic>>>
      checkMultipleVehicleAvailability(List<String> vehicleIds) async {
    Map<String, Map<String, dynamic>> results = {};

    // Initialize all vehicles as available
    for (String vehicleId in vehicleIds) {
      results[vehicleId] = {
        'is_available': true,
        'current_status': 'available',
        'current_trip_ref': '',
        'message': 'Vehicle is available for assignment',
        'reason': 'available',
      };
    }

    try {
      // Get vehicle statuses
      final vehicles = await _client
          .from('vehicles')
          .select('id, plate_number, status')
          .inFilter('id', vehicleIds);

      // Check for maintenance and out of service vehicles
      for (var vehicle in vehicles) {
        if (VehicleStatusConfig.isUnderMaintenance(vehicle['status'])) {
          results[vehicle['id']] = {
            'is_available': false,
            'current_status': 'maintenance',
            'current_trip_ref': '',
            'message': 'Vehicle ${vehicle['plate_number']} is under maintenance',
            'reason': VehicleStatusConfig.getReasonCode(vehicle['status']),
          };
        } else if (VehicleStatusConfig.isOutOfService(vehicle['status'])) {
          results[vehicle['id']] = {
            'is_available': false,
            'current_status': 'out_of_service',
            'current_trip_ref': '',
            'message': 'Vehicle ${vehicle['plate_number']} is out of service',
            'reason': VehicleStatusConfig.getReasonCode(vehicle['status']),
          };
        }
      }

      // Check for active trips
      final activeTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status, vehicle_id')
          .inFilter('vehicle_id', vehicleIds)
          .inFilter('status', ['assigned', 'in_progress']);

      for (var trip in activeTrips) {
        final vehicleId = trip['vehicle_id'];
        if (vehicleIds.contains(vehicleId)) {
          final vehicle = vehicles.firstWhere((v) => v['id'] == vehicleId);
          final tripRef = trip['trip_ref_number'] ??
              'Trip #${trip['id']?.toString().substring(0, 8)}';
          results[vehicleId] = {
            'is_available': false,
            'current_status': 'assigned',
            'current_trip_ref': tripRef,
            'message': 'Vehicle ${vehicle['plate_number']} is already assigned to $tripRef',
            'reason': 'assigned',
          };
        }
      }

      // Check for scheduled trips
      final scheduledTrips = await _client
          .from('trips')
          .select('id, trip_ref_number, status, vehicle_id, start_time')
          .inFilter('vehicle_id', vehicleIds)
          .eq('status', 'pending')
          .gte('start_time', DateTime.now().toIso8601String());

      for (var trip in scheduledTrips) {
        final vehicleId = trip['vehicle_id'];
        if (vehicleIds.contains(vehicleId) && results[vehicleId]!['is_available']) {
          final vehicle = vehicles.firstWhere((v) => v['id'] == vehicleId);
          final tripRef = trip['trip_ref_number'] ??
              'Trip #${trip['id']?.toString().substring(0, 8)}';
          results[vehicleId] = {
            'is_available': false,
            'current_status': 'scheduled',
            'current_trip_ref': tripRef,
            'message': 'Vehicle ${vehicle['plate_number']} is scheduled for $tripRef',
            'reason': 'scheduled',
          };
        }
      }
    } catch (e) {
      print('Multiple vehicle availability check failed: $e');
      // Keep default available status if check fails
    }

    return results;
  }

  /// Get all vehicles with their availability status (including unavailable ones)
  static Future<List<Map<String, dynamic>>> getAvailableVehicles() async {
    try {
      // Get ALL vehicles (including maintenance and out of service)
      final vehicles = await _client
          .from('vehicles')
          .select('*')
          .order('plate_number');

      if (vehicles.isEmpty) {
        return [];
      }

      // Get vehicle IDs for batch availability check
      final vehicleIds = vehicles.map((v) => v['id'] as String).toList();
      final availabilityResults = await checkMultipleVehicleAvailability(vehicleIds);

      // Combine vehicle data with availability status
      return vehicles.map((vehicle) {
        final availability = availabilityResults[vehicle['id']] ?? {
          'is_available': true,
          'current_status': 'available',
          'current_trip_ref': '',
          'message': 'Vehicle is available for assignment',
          'reason': 'available',
        };

        return {
          ...vehicle,
          'availability': availability,
        };
      }).toList();
    } catch (e) {
      print('Error fetching vehicles: $e');
      return [];
    }
  }

  /// Assign vehicle to a trip with availability validation
  static Future<Map<String, dynamic>> assignVehicleToTrip({
    required String tripId,
    String? vehicleId,
    String? assignedBy,
  }) async {
    try {
      // If no vehicle is being assigned, just update the trip
      if (vehicleId == null) {
        await _client
            .from('trips')
            .update({'vehicle_id': null})
            .eq('id', tripId);

        return {
          'success': true,
          'message': 'Trip updated - no vehicle assigned',
          'vehicle_assigned': false,
        };
      }

      // Check vehicle availability first
      final availability = await checkVehicleAvailability(vehicleId);
      if (!availability['is_available']) {
        return {
          'success': false,
          'message': availability['message'],
          'error': 'vehicle_not_available',
          'reason': availability['reason'],
        };
      }

      // If vehicle is available, proceed with assignment
      await _client
          .from('trips')
          .update({'vehicle_id': vehicleId})
          .eq('id', tripId);

      // Also update the schedule if it exists
      try {
        await _client
            .from('schedules')
            .update({'vehicle_id': vehicleId})
            .eq('trip_id', tripId);
      } catch (e) {
        // Schedule update is optional, don't fail the whole operation
        print('Warning: Could not update schedule: $e');
      }

      return {
        'success': true,
        'message': 'Vehicle assigned successfully',
        'vehicle_assigned': true,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to assign vehicle: $e',
        'error': 'assignment_failed',
      };
    }
  }

  /// Validate vehicle assignment before creating a new trip
  static Future<Map<String, dynamic>> validateVehicleForNewTrip(
      String? vehicleId) async {
    if (vehicleId == null) {
      return {
        'is_valid': true,
        'message': 'No vehicle assignment required',
      };
    }

    final availability = await checkVehicleAvailability(vehicleId);
    if (!availability['is_available']) {
      return {
        'is_valid': false,
        'message': availability['message'],
        'reason': availability['reason'],
      };
    }

    return {
      'is_valid': true,
      'message': 'Vehicle is available for assignment',
    };
  }
}
