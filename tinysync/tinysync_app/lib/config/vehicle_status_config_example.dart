/// Example: How to add new vehicle status values
/// 
/// This file shows how to extend the VehicleStatusConfig when new statuses are needed.
/// 
/// IMPORTANT: When adding new status values, you must also:
/// 1. Update the database constraint in Supabase
/// 2. Update this configuration file
/// 3. Test the new status in the UI

/*
// Example: Adding a new "Reserved" status

class VehicleStatusConfig {
  // Existing statuses
  static const String available = 'Available';
  static const String maintenance = 'Maintenance';
  static const String outOfService = 'Out_of_service';
  
  // NEW STATUS - Add this
  static const String reserved = 'Reserved';

  /// Get all valid vehicle status values
  static List<String> get allStatuses => [
        available,
        maintenance,
        outOfService,
        reserved, // ADD THIS
      ];

  /// Get available statuses (excluding maintenance, out of service, and reserved)
  static List<String> get availableStatuses => [
        available,
      ];

  /// Get unavailable statuses (maintenance, out of service, and reserved)
  static List<String> get unavailableStatuses => [
        maintenance,
        outOfService,
        reserved, // ADD THIS
      ];

  /// Check if a status indicates the vehicle is available for assignment
  static bool isAvailableForAssignment(String status) {
    return status == available;
  }

  /// Check if a status indicates the vehicle is under maintenance
  static bool isUnderMaintenance(String status) {
    return status == maintenance;
  }

  /// Check if a status indicates the vehicle is out of service
  static bool isOutOfService(String status) {
    return status == outOfService;
  }

  // NEW METHOD - Add this
  /// Check if a status indicates the vehicle is reserved
  static bool isReserved(String status) {
    return status == reserved;
  }

  /// Check if a status indicates the vehicle is unavailable
  static bool isUnavailable(String status) {
    return unavailableStatuses.contains(status);
  }

  /// Get display name for a status
  static String getDisplayName(String status) {
    switch (status) {
      case available:
        return 'Available';
      case maintenance:
        return 'Under Maintenance';
      case outOfService:
        return 'Out of Service';
      case reserved: // ADD THIS CASE
        return 'Reserved';
      default:
        return 'Unknown';
    }
  }

  /// Get short display name for a status (for badges)
  static String getShortDisplayName(String status) {
    switch (status) {
      case available:
        return 'Available';
      case maintenance:
        return 'Maintenance';
      case outOfService:
        return 'Out of Service';
      case reserved: // ADD THIS CASE
        return 'Reserved';
      default:
        return 'Unknown';
    }
  }

  /// Get color code for a status (for UI)
  static String getColorCode(String status) {
    switch (status) {
      case available:
        return 'green';
      case maintenance:
        return 'orange';
      case outOfService:
        return 'red';
      case reserved: // ADD THIS CASE
        return 'blue';
      default:
        return 'grey';
    }
  }

  /// Get reason code for availability checking
  static String getReasonCode(String status) {
    switch (status) {
      case available:
        return 'available';
      case maintenance:
        return 'maintenance';
      case outOfService:
        return 'out_of_service';
      case reserved: // ADD THIS CASE
        return 'reserved';
      default:
        return 'unknown';
    }
  }
}

// DATABASE UPDATE REQUIRED:
// You would also need to update the database constraint:
// ALTER TABLE vehicles DROP CONSTRAINT vehicles_status_check;
// ALTER TABLE vehicles ADD CONSTRAINT vehicles_status_check 
// CHECK (status::text = ANY (ARRAY['Available'::character varying::text, 'Maintenance'::character varying::text, 'Out_of_service'::character varying::text, 'Reserved'::character varying::text]));

// UI UPDATES REQUIRED:
// You would also need to update the UI components to handle the new status:
// 1. Update color mappings in _getStatusColor methods
// 2. Update availability checking logic
// 3. Update display text in vehicle cards and dialogs
// 4. Test the new status in all vehicle selection interfaces
*/
