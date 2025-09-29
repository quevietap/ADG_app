import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Service to handle trip lifecycle management including session logging,
/// trip status transitions, and history management
class TripLifecycleService {
  static final TripLifecycleService _instance =
      TripLifecycleService._internal();
  factory TripLifecycleService() => _instance;
  TripLifecycleService._internal();

  /// Start a trip and create session log entry
  Future<Map<String, dynamic>> startTrip({
    required String tripId,
    required String driverId,
    required String origin,
    required String destination,
    double? startLatitude,
    double? startLongitude,
  }) async {
    try {
      print('🚀 Starting trip lifecycle for trip: $tripId');

      // 1. Update trip status to in_progress
      await Supabase.instance.client.from('trips').update({
        'status': 'in_progress',
        'started_at': DateTime.now().toIso8601String(),
        if (startLatitude != null) 'start_latitude': startLatitude,
        if (startLongitude != null) 'start_longitude': startLongitude,
        'current_latitude': startLatitude ?? 0.0,
        'current_longitude': startLongitude ?? 0.0,
        'last_location_update': DateTime.now().toIso8601String(),
      }).eq('id', tripId);

      // 2. Create session log entry
      await _createSessionLogEntry(
        tripId: tripId,
        driverId: driverId,
        eventType: 'trip_started',
        description: 'Driver started trip from $origin to $destination',
        origin: origin,
        destination: destination,
        latitude: startLatitude,
        longitude: startLongitude,
      );

      print('✅ Trip started successfully with session log');
      return {
        'success': true,
        'message': 'Trip started successfully',
        'trip_id': tripId,
      };
    } catch (e) {
      print('❌ Error starting trip: $e');
      return {
        'success': false,
        'message': 'Error starting trip: $e',
        'error': e.toString(),
      };
    }
  }

  /// Complete a trip and create completion log entry
  Future<Map<String, dynamic>> completeTrip({
    required String tripId,
    required String driverId,
    required String origin,
    required String destination,
    double? endLatitude,
    double? endLongitude,
  }) async {
    try {
      print('✅ Completing trip lifecycle for trip: $tripId');

      // 1. Update trip status to driver_completed (awaiting operator confirmation)
      final completionTime = DateTime.now().toIso8601String();

      // Prepare update data with safe type conversion
      final updateData = <String, dynamic>{
        'status':
            'driver_completed', // Driver completed, awaiting operator confirmation
        'end_time': completionTime,
        'completed_at': completionTime,
        'last_location_update': completionTime,
        // Note: operator_confirmed_at is NOT set, indicating awaiting confirmation
      };
      print(
          '🔧 UPDATING TRIP STATUS TO: driver_completed (awaiting operator confirmation) for trip: $tripId');
      print('🔧 UPDATE DATA: $updateData');

      // Safely add location data with proper type conversion
      if (endLatitude != null) {
        updateData['end_latitude'] =
            double.tryParse(endLatitude.toString()) ?? 0.0;
        updateData['current_latitude'] =
            double.tryParse(endLatitude.toString()) ?? 0.0;
      } else {
        updateData['current_latitude'] = 0.0;
      }

      if (endLongitude != null) {
        updateData['end_longitude'] =
            double.tryParse(endLongitude.toString()) ?? 0.0;
        updateData['current_longitude'] =
            double.tryParse(endLongitude.toString()) ?? 0.0;
      } else {
        updateData['current_longitude'] = 0.0;
      }

      print('🔍 DEBUG: About to update trip $tripId with data: $updateData');
      await Supabase.instance.client
          .from('trips')
          .update(updateData)
          .eq('id', tripId);
      print('🔍 DEBUG: Trip $tripId updated successfully in database');

      print(
          '✅ DATABASE UPDATE COMPLETED - Status should now be driver_completed');

      // Verify the update worked by checking the trip status
      final verifyResponse = await Supabase.instance.client
          .from('trips')
          .select('status, operator_confirmed_at')
          .eq('id', tripId)
          .single();
      print(
          '🔍 VERIFICATION: Trip $tripId status is now: ${verifyResponse['status']}');
      print(
          '🔍 VERIFICATION: operator_confirmed_at is: ${verifyResponse['operator_confirmed_at']}');

      // 2. Create completion session log entry
      await _createSessionLogEntry(
        tripId: tripId,
        driverId: driverId,
        eventType: 'trip_completed',
        description: 'Driver completed trip from $origin to $destination',
        origin: origin,
        destination: destination,
        latitude: endLatitude,
        longitude: endLongitude,
      );

      // 3. Send completion notification to operator
      try {
        final driverName = await _getDriverName(driverId);
        final tripRefNumber = await _getTripRefNumber(tripId);

        // Send notification directly using NotificationService
        await NotificationService().sendTripCompletionNotification(
          tripId: tripId,
          driverName: driverName,
          tripRefNumber: tripRefNumber,
        );
        print('🔔 Completion notification sent to operator');
      } catch (notificationError) {
        print('⚠️ Error sending completion notification: $notificationError');
        // Continue without notification
      }

      print('✅ Trip completed by driver, awaiting operator confirmation');
      return {
        'success': true,
        'message': 'Trip marked as completed. Awaiting operator confirmation.',
        'trip_id': tripId,
      };
    } catch (e) {
      print('❌ Error completing trip: $e');
      return {
        'success': false,
        'message': 'Error completing trip: $e',
        'error': e.toString(),
      };
    }
  }

  /// Mark trip as confirmed by operator and move to Completed tab
  Future<Map<String, dynamic>> confirmTripCompletion({
    required String tripId,
    required String operatorId,
    required String origin,
    required String destination,
  }) async {
    try {
      print('🔍 Operator confirming trip completion: $tripId');

      // 1. Update trip with operator confirmation
      await Supabase.instance.client.from('trips').update({
        'operator_confirmed_at': DateTime.now().toIso8601String(),
        'confirmed_by': operatorId,
        'status': 'completed', // Ensure status is completed
      }).eq('id', tripId);

      // 2. Create operator confirmation session log entry
      await _createSessionLogEntry(
        tripId: tripId,
        driverId: operatorId,
        eventType: 'trip_confirmed',
        description:
            'Operator confirmed trip completion from $origin to $destination',
        origin: origin,
        destination: destination,
      );

      print('✅ Trip confirmed by operator and moved to Completed tab');
      return {
        'success': true,
        'message': 'Trip confirmed and moved to Completed tab',
        'trip_id': tripId,
      };
    } catch (e) {
      print('❌ Error confirming trip: $e');
      return {
        'success': false,
        'message': 'Error confirming trip: $e',
        'error': e.toString(),
      };
    }
  }

  /// Cancel a trip and move to Cancelled tab
  Future<Map<String, dynamic>> cancelTrip({
    required String tripId,
    required String cancelledBy,
    required String reason,
    required String origin,
    required String destination,
  }) async {
    try {
      print('❌ Cancelling trip: $tripId');

      // 1. Update trip status to cancelled
      await Supabase.instance.client.from('trips').update({
        'status': 'cancelled',
        'canceled_at': DateTime.now().toIso8601String(),
        'cancelled_by': cancelledBy,
        'cancel_reason': reason,
      }).eq('id', tripId);

      // 2. Create cancellation session log entry
      await _createSessionLogEntry(
        tripId: tripId,
        driverId: cancelledBy,
        eventType: 'trip_cancelled',
        description: 'Trip cancelled: $reason',
        origin: origin,
        destination: destination,
      );

      print('✅ Trip cancelled and moved to Cancelled tab');
      return {
        'success': true,
        'message': 'Trip cancelled successfully',
        'trip_id': tripId,
      };
    } catch (e) {
      print('❌ Error cancelling trip: $e');
      return {
        'success': false,
        'message': 'Error cancelling trip: $e',
        'error': e.toString(),
      };
    }
  }

  /// Delete a trip and move to Deleted tab
  Future<Map<String, dynamic>> deleteTrip({
    required String tripId,
    required String deletedBy,
    required String reason,
    required String origin,
    required String destination,
  }) async {
    try {
      print('🗑️ Deleting trip: $tripId');

      // 1. Update trip status to deleted
      await Supabase.instance.client.from('trips').update({
        'status': 'deleted',
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': deletedBy,
        'delete_reason': reason,
      }).eq('id', tripId);

      // 2. Create deletion session log entry
      await _createSessionLogEntry(
        tripId: tripId,
        driverId: deletedBy,
        eventType: 'trip_deleted',
        description: 'Trip deleted: $reason',
        origin: origin,
        destination: destination,
      );

      print('✅ Trip deleted and moved to Deleted tab');
      return {
        'success': true,
        'message': 'Trip deleted successfully',
        'trip_id': tripId,
      };
    } catch (e) {
      print('❌ Error deleting trip: $e');
      return {
        'success': false,
        'message': 'Error deleting trip: $e',
        'error': e.toString(),
      };
    }
  }

  /// Create session log entry
  Future<void> _createSessionLogEntry({
    required String tripId,
    required String driverId,
    required String eventType,
    required String description,
    required String origin,
    required String destination,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Check if session_logs table exists, if not create it
      await _ensureSessionLogsTable();

      await Supabase.instance.client.from('session_logs').insert({
        'trip_id': tripId,
        'driver_id': driverId,
        'event_type': eventType,
        'description': description,
        'origin': origin,
        'destination': destination,
        'latitude': latitude,
        'longitude': longitude,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('📝 Session log entry created: $eventType');
    } catch (e) {
      print('❌ Error creating session log entry: $e');
      // Don't throw error - session logging is not critical
    }
  }

  /// Ensure session_logs table exists
  Future<void> _ensureSessionLogsTable() async {
    try {
      // Try to query the table to see if it exists
      await Supabase.instance.client.from('session_logs').select('id').limit(1);
    } catch (e) {
      // Table doesn't exist, create it
      print('📋 Creating session_logs table...');

      // Note: In a real app, you would use a migration system
      // For now, we'll just log that the table should be created
      print(
          '⚠️ session_logs table does not exist. Please create it with the following SQL:');
      print('''
        CREATE TABLE IF NOT EXISTS session_logs (
          id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
          trip_id UUID REFERENCES trips(id),
          driver_id UUID REFERENCES users(id),
          event_type VARCHAR NOT NULL,
          description TEXT,
          origin VARCHAR,
          destination VARCHAR,
          latitude DECIMAL(10, 8),
          longitude DECIMAL(11, 8),
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      ''');
    }
  }

  /// Get session logs for a trip
  Future<List<Map<String, dynamic>>> getSessionLogs(String tripId) async {
    try {
      final response = await Supabase.instance.client
          .from('session_logs')
          .select('*')
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching session logs: $e');
      return [];
    }
  }

  /// Check if trip should be moved to history (outdated)
  bool isTripOutdated(Map<String, dynamic> trip) {
    final startTime = trip['start_time'];
    if (startTime == null) return false;

    final tripDate = DateTime.tryParse(startTime);
    if (tripDate == null) return false;

    final today = DateTime.now();
    return tripDate.year != today.year ||
        tripDate.month != today.month ||
        tripDate.day != today.day;
  }

  /// Move outdated trips to history automatically
  Future<void> moveOutdatedTripsToHistory() async {
    try {
      final today = DateTime.now();
      final todayStr = today.toIso8601String().split('T')[0];

      print('📅 Checking for outdated trips before: $todayStr');

      // Find trips from previous days that are still in active status
      final outdatedTrips = await Supabase.instance.client
          .from('trips')
          .select('*')
          .lt('start_time', todayStr)
          .inFilter('status', [
        'assigned',
        'in_progress',
        'driver_completed',
        'completed'
      ]).order('start_time', ascending: false);

      print(
          '📅 Found ${outdatedTrips.length} outdated trips to move to history');

      for (final trip in outdatedTrips) {
        try {
          // TEMPORARILY DISABLED: Create history entry
          // await _createHistoryEntry(trip);
          print(
              '⚠️ History entry creation temporarily disabled for trip ${trip['id']}');

          // Update trip status to archived (but keep it accessible)
          await Supabase.instance.client.from('trips').update({
            'status': 'archived',
            'archived_at': DateTime.now().toIso8601String(),
          }).eq('id', trip['id']);

          print(
              '✅ Moved trip ${trip['id']} to history (without history entry)');
        } catch (e) {
          print('❌ Error moving trip ${trip['id']} to history: $e');
        }
      }

      print('✅ Completed moving ${outdatedTrips.length} trips to history');
    } catch (e) {
      print('❌ Error moving outdated trips to history: $e');
    }
  }

  /// Create history entry for a trip
  Future<void> _createHistoryEntry(Map<String, dynamic> trip) async {
    // TEMPORARILY DISABLED: All history creation is disabled
    print(
        '⚠️ History entry creation is completely disabled for trip: ${trip['id']}');
    print('⚠️ This is a temporary fix to allow trip completion to work');
    return;

    // ORIGINAL CODE COMMENTED OUT BELOW:
    /*
    try {
      print('🔍 DEBUG: Starting _createHistoryEntry for trip: ${trip['id']}');
      print('🔍 DEBUG: Trip data keys: ${trip.keys.toList()}');
      print('🔍 DEBUG: trip_ref_number value: ${trip['trip_ref_number']}');
      print('🔍 DEBUG: trip_ref_number type: ${trip['trip_ref_number']?.runtimeType}');

      // First, try to fetch the complete trip data from the database
      print('🔍 DEBUG: Fetching complete trip data from database...');
      final completeTripData = await Supabase.instance.client
          .from('trips')
          .select('*')
          .eq('id', trip['id'])
          .single();
      
      print('🔍 DEBUG: Complete trip data from DB: ${completeTripData.keys.toList()}');
      print('🔍 DEBUG: DB trip_ref_number: ${completeTripData['trip_ref_number']}');

      // Generate a guaranteed trip_ref_number with extensive debugging
      final tripRefNumber = _generateTripRefNumber(completeTripData);
      print('🔍 DEBUG: Generated trip_ref_number: $tripRefNumber');

      // Prepare all required fields with safe defaults
      final historyData = <String, dynamic>{
        'trip_id': completeTripData['id'],
        'trip_ref_number': tripRefNumber,
        'origin': completeTripData['origin']?.toString() ?? 'Unknown Origin',
        'destination': completeTripData['destination']?.toString() ?? 'Unknown Destination',
        'status': completeTripData['status']?.toString() ?? 'unknown',
        'driver_id': completeTripData['driver_id'],
        'sub_driver_id': completeTripData['sub_driver_id'],
        'vehicle_id': completeTripData['vehicle_id'],
        'start_time': completeTripData['start_time'],
        'end_time': completeTripData['end_time'],
        'started_at': completeTripData['started_at'],
        'completed_at': completeTripData['completed_at'],
        'operator_confirmed_at': completeTripData['operator_confirmed_at'],
        'confirmed_by': completeTripData['confirmed_by'],
        'archived_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };

      // Add optional fields only if they exist
      if (completeTripData.containsKey('original_trip_data')) {
        historyData['original_trip_data'] = completeTripData['original_trip_data'];
      }
      if (completeTripData.containsKey('metadata')) {
        historyData['metadata'] = completeTripData['metadata'];
      }

      print('🔍 DEBUG: Final history data: $historyData');

      // Try direct insert first (bypass the RPC function)
      await Supabase.instance.client
          .from('trip_history')
          .insert(historyData);

      print('✅ History entry created successfully via direct insert');
    } catch (e) {
      print('❌ Error creating history entry via direct insert: $e');
      
      // If direct insert fails, try with minimal data
      try {
        print('🔄 Trying minimal data insert...');
        
        final minimalData = <String, dynamic>{
          'trip_id': trip['id'],
          'trip_ref_number': _generateTripRefNumber(trip),
          'origin': trip['origin']?.toString() ?? 'Unknown Origin',
          'destination': trip['destination']?.toString() ?? 'Unknown Destination',
          'status': trip['status']?.toString() ?? 'unknown',
          'driver_id': trip['driver_id'],
          'sub_driver_id': trip['sub_driver_id'],
          'vehicle_id': trip['vehicle_id'],
          'archived_at': DateTime.now().toIso8601String(),
        };

        print('🔍 DEBUG: Minimal data: $minimalData');

        await Supabase.instance.client
            .from('trip_history')
            .insert(minimalData);

        print('✅ History entry created with minimal data');
      } catch (minimalError) {
        print('❌ Critical Error: Failed to create history entry even with minimal data: $minimalError');
        print('⚠️ Skipping history entry creation - continuing with trip completion');
        // Don't rethrow - let the trip completion continue
      }
    }
    */
  }

  /// Generate a guaranteed trip reference number with extensive validation
  String _generateTripRefNumber(Map<String, dynamic> trip) {
    print(
        '🔍 DEBUG: _generateTripRefNumber called with trip ID: ${trip['id']}');

    // Initialize with a guaranteed non-null value
    String refNumber = 'TRIP-UNKNOWN-${DateTime.now().millisecondsSinceEpoch}';

    // Try primary key first
    if (trip.containsKey('trip_ref_number')) {
      final value = trip['trip_ref_number'];
      print(
          '🔍 DEBUG: Found trip_ref_number: $value (type: ${value?.runtimeType})');

      if (value != null &&
          value.toString().isNotEmpty &&
          value.toString() != 'null') {
        refNumber = value.toString();
        print('🔍 DEBUG: Using trip_ref_number: $refNumber');
        return refNumber;
      }
    }

    // Try alternative keys
    if (trip.containsKey('reference_number')) {
      final value = trip['reference_number'];
      if (value != null &&
          value.toString().isNotEmpty &&
          value.toString() != 'null') {
        refNumber = value.toString();
        print('🔍 DEBUG: Using reference_number: $refNumber');
        return refNumber;
      }
    }

    if (trip.containsKey('ref_number')) {
      final value = trip['ref_number'];
      if (value != null &&
          value.toString().isNotEmpty &&
          value.toString() != 'null') {
        refNumber = value.toString();
        print('🔍 DEBUG: Using ref_number: $refNumber');
        return refNumber;
      }
    }

    // Fallback to trip ID
    if (trip.containsKey('id') && trip['id'] != null) {
      refNumber = 'TRIP-${trip['id'].toString()}';
      print('🔍 DEBUG: Using trip ID fallback: $refNumber');
      return refNumber;
    }

    // Final fallback
    print('🔍 DEBUG: Using timestamp fallback: $refNumber');
    return refNumber;
  }

  /// Get a safe string value with fallback
  String _getSafeString(dynamic value, String fallback) {
    if (value == null) return fallback;

    final stringValue = value.toString();
    if (stringValue.isEmpty || stringValue == 'null') {
      return fallback;
    }

    return stringValue;
  }

  /// Ensure trip_history table exists
  Future<void> _ensureTripHistoryTable() async {
    try {
      await Supabase.instance.client.from('trip_history').select('id').limit(1);
    } catch (e) {
      print('📋 Creating trip_history table...');
      print(
          '⚠️ trip_history table does not exist. Please create it with the following SQL:');
      print('''
        CREATE TABLE IF NOT EXISTS trip_history (
          id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
          trip_id UUID REFERENCES trips(id),
          trip_ref_number VARCHAR NOT NULL,
          origin VARCHAR NOT NULL,
          destination VARCHAR NOT NULL,
          start_time TIMESTAMP WITH TIME ZONE,
          end_time TIMESTAMP WITH TIME ZONE,
          status VARCHAR NOT NULL,
          driver_id UUID REFERENCES users(id),
          sub_driver_id UUID REFERENCES users(id),
          vehicle_id UUID REFERENCES vehicles(id),
          started_at TIMESTAMP WITH TIME ZONE,
          completed_at TIMESTAMP WITH TIME ZONE,
          operator_confirmed_at TIMESTAMP WITH TIME ZONE,
          archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      ''');
    }
  }

  /// Get trip history
  Future<List<Map<String, dynamic>>> getTripHistory({
    String? driverId,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      String queryString = 'SELECT * FROM trip_history';
      List<String> conditions = [];
      List<dynamic> params = [];

      if (driverId != null) {
        conditions.add('driver_id = ?');
        params.add(driverId);
      }

      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }

      if (fromDate != null) {
        conditions.add('archived_at >= ?');
        params.add(fromDate.toIso8601String());
      }

      if (toDate != null) {
        conditions.add('archived_at <= ?');
        params.add(toDate.toIso8601String());
      }

      if (conditions.isNotEmpty) {
        queryString += ' WHERE ${conditions.join(' AND ')}';
      }

      queryString += ' ORDER BY archived_at DESC';

      final response = await Supabase.instance.client
          .rpc('exec_sql', params: {'query': queryString, 'params': params});

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error fetching trip history: $e');
      return [];
    }
  }

  /// Subscribe to trip status changes
  RealtimeChannel subscribeToTripStatusChanges(
      Function(Map<String, dynamic>) onStatusChange) {
    return Supabase.instance.client
        .channel('trip_lifecycle_status_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            onStatusChange(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Get trips that should be shown in History → Session Tab
  Future<List<Map<String, dynamic>>> getSessionTabTrips() async {
    try {
      // Get archived trips (outdated trips that were moved to history)
      final archivedTrips = await Supabase.instance.client
          .from('trips')
          .select(
              '*, driver:users!trips_driver_id_fkey(*), sub_driver:users!trips_sub_driver_id_fkey(*), vehicles(*)')
          .eq('status', 'archived')
          .order('start_time', ascending: false);

      // Get session logs for these trips
      final sessionLogs = await Supabase.instance.client
          .from('session_logs')
          .select('*')
          .inFilter('trip_id', archivedTrips.map((trip) => trip['id']).toList())
          .order('created_at', ascending: false);

      // Combine trips with their session logs and add vehicle details
      final List<Map<String, dynamic>> sessionTabTrips = [];

      for (final trip in archivedTrips) {
        final tripLogs =
            sessionLogs.where((log) => log['trip_id'] == trip['id']).toList();

        // Add vehicle details if available
        Map<String, dynamic> tripWithDetails = {
          ...trip,
          'session_logs': tripLogs,
          'is_outdated': true,
          'is_archived': true, // Mark as archived for UI handling
        };

        // Add vehicle details if not already included
        if (trip['vehicle_id'] != null && trip['vehicles'] == null) {
          try {
            final vehicleResponse = await Supabase.instance.client
                .from('vehicles')
                .select('plate_number, make, model, capacity_kg')
                .eq('id', trip['vehicle_id'])
                .single();
            tripWithDetails['vehicle_details'] = vehicleResponse;
          } catch (e) {
            print(
                '⚠️ Error fetching vehicle details for trip ${trip['id']}: $e');
            tripWithDetails['vehicle_details'] = null;
          }
        }

        sessionTabTrips.add(tripWithDetails);
      }

      print(
          '✅ Session tab trips fetched: ${sessionTabTrips.length} archived trips');
      return sessionTabTrips;
    } catch (e) {
      print('❌ Error getting session tab trips: $e');
      return [];
    }
  }

  /// Check if a trip should be automatically transferred
  bool shouldAutoTransfer(Map<String, dynamic> trip) {
    // Only transfer trips that are outdated and not already archived/deleted
    // Also ensure the trip has a start_time to determine if it's outdated
    return isTripOutdated(trip) &&
        trip['status'] != 'archived' &&
        trip['status'] != 'deleted' &&
        trip['start_time'] != null;
  }

  /// Auto-transfer outdated trips (call this periodically)
  Future<void> autoTransferOutdatedTrips() async {
    try {
      print('🔄 Starting automatic transfer of outdated trips...');

      // Get all active trips that could potentially be transferred
      // Only transfer trips that are not already completed, cancelled, or deleted
      final activeTrips = await Supabase.instance.client
          .from('trips')
          .select('*')
          .inFilter('status', ['assigned', 'in_progress']).order('start_time',
              ascending: false);

      print(
          '📊 Found ${activeTrips.length} active trips to check for auto-transfer');

      int transferredCount = 0;
      int skippedCount = 0;

      for (final trip in activeTrips) {
        final tripId = trip['id'];
        final tripStatus = trip['status'];
        final startTime = trip['start_time'];

        print(
            '🔍 Checking trip $tripId (status: $tripStatus, start_time: $startTime)');

        if (shouldAutoTransfer(trip)) {
          try {
            print(
                '📅 Trip $tripId is outdated, transferring to Session tab...');

            // Create session log entry for the transfer
            await _createSessionLogEntry(
              tripId: tripId,
              driverId: trip['driver_id'] ?? 'system',
              eventType: 'trip_archived',
              description:
                  'Trip automatically transferred to Session tab due to date change',
              origin: trip['origin'] ?? 'Unknown',
              destination: trip['destination'] ?? 'Unknown',
            );

            // Update trip status to archived (Session tab)
            try {
              await Supabase.instance.client.from('trips').update({
                'status': 'archived',
                'archived_at': DateTime.now().toIso8601String(),
              }).eq('id', tripId);
            } catch (constraintError) {
              print('❌ Database constraint error: $constraintError');
              print(
                  '⚠️ The trips table constraint needs to be updated to allow "archived" status');
              print('⚠️ Please run the fix_trips_status_constraint.sql script');

              // Fallback: Try to update with a different status that's allowed
              try {
                await Supabase.instance.client.from('trips').update({
                  'status': 'completed', // Use completed as fallback
                  'archived_at': DateTime.now().toIso8601String(),
                  'notes':
                      '${trip['notes'] ?? ''}\n\nAUTO-TRANSFERRED: Trip moved to Session tab (${DateTime.now()})'
                          .trim(),
                }).eq('id', tripId);
                print('✅ Used fallback status "completed" for trip $tripId');
              } catch (fallbackError) {
                print('❌ Fallback update also failed: $fallbackError');
                rethrow;
              }
            }

            transferredCount++;
            print(
                '✅ Auto-transferred trip $tripId to Session tab with session log');
          } catch (e) {
            print('❌ Error auto-transferring trip $tripId: $e');
          }
        } else {
          skippedCount++;
          print('⏭️ Skipping trip $tripId (not outdated or already archived)');
        }
      }

      print('📊 Auto-transfer summary:');
      print('   - Total trips checked: ${activeTrips.length}');
      print('   - Trips transferred: $transferredCount');
      print('   - Trips skipped: $skippedCount');

      if (transferredCount > 0) {
        print('✅ Auto-transferred $transferredCount trips to Session tab');
      } else {
        print('ℹ️ No trips needed auto-transfer');
      }
    } catch (e) {
      print('❌ Error in auto-transfer process: $e');
    }
  }

  /// Get driver name by ID
  Future<String> _getDriverName(String driverId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('first_name, last_name')
          .eq('id', driverId)
          .single();

      final firstName = response['first_name'] ?? '';
      final lastName = response['last_name'] ?? '';
      return '$firstName $lastName'.trim();
    } catch (e) {
      print('❌ Error getting driver name: $e');
      return 'Unknown Driver';
    }
  }

  /// Get trip reference number by ID
  Future<String> _getTripRefNumber(String tripId) async {
    try {
      final response = await Supabase.instance.client
          .from('trips')
          .select('trip_ref_number')
          .eq('id', tripId)
          .single();

      return response['trip_ref_number'] ?? 'TRIP-$tripId';
    } catch (e) {
      print('❌ Error getting trip ref number: $e');
      return 'TRIP-$tripId';
    }
  }
}
