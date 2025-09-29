/// Vehicle Status Configuration
/// Centralized configuration for vehicle status values and their properties
class VehicleStatusConfig {
  // Valid vehicle status values as defined in the database constraint
  static const String available = 'Available';
  static const String maintenance = 'Maintenance';
  static const String outOfService = 'Out_of_service';

  /// Get all valid vehicle status values
  static List<String> get allStatuses => [
        available,
        maintenance,
        outOfService,
      ];

  /// Get available statuses (excluding maintenance and out of service)
  static List<String> get availableStatuses => [
        available,
      ];

  /// Get unavailable statuses (maintenance and out of service)
  static List<String> get unavailableStatuses => [
        maintenance,
        outOfService,
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
      default:
        return 'unknown';
    }
  }
}
