import 'package:latlong2/latlong.dart' as latlong2;
import 'package:url_launcher/url_launcher.dart';

/// Waze Integration Service
/// Provides free navigation and traffic information through Waze
class WazeIntegrationService {
  static final WazeIntegrationService _instance = WazeIntegrationService._internal();
  factory WazeIntegrationService() => _instance;
  WazeIntegrationService._internal();

  // Waze API endpoints
  static const String _wazeApiBaseUrl = 'https://www.waze.com';
  static const String _wazeRoutingApi = 'https://www.waze.com/row-routing-manager';
  
  /// Open Waze navigation to destination
  Future<bool> openWazeNavigation({
    required latlong2.LatLng destination,
    String? destinationName,
    latlong2.LatLng? origin,
  }) async {
    try {
      print('🗺️ Opening Waze navigation to: ${destination.latitude}, ${destination.longitude}');
      
      // Build Waze URL
      final wazeUrl = _buildWazeUrl(
        destination: destination,
        destinationName: destinationName,
        origin: origin,
      );
      
      // Launch Waze app or website
      final uri = Uri.parse(wazeUrl);
      final canLaunch = await canLaunchUrl(uri);
      
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('✅ Waze navigation opened successfully');
        return true;
      } else {
        print('❌ Cannot launch Waze URL: $wazeUrl');
        return false;
      }
      
    } catch (e) {
      print('❌ Error opening Waze navigation: $e');
      return false;
    }
  }

  /// Get Waze traffic information for a route
  Future<Map<String, dynamic>?> getWazeTrafficInfo({
    required latlong2.LatLng origin,
    required latlong2.LatLng destination,
  }) async {
    try {
      print('🚦 Getting Waze traffic info...');
      
      // Note: Waze doesn't provide a public API for traffic data
      // This is a placeholder for future implementation
      // You would need to use Waze's partner program or alternative services
      
      return {
        'origin': origin,
        'destination': destination,
        'traffic_level': 'unknown',
        'note': 'Waze traffic data requires partner program access',
        'alternative': 'Use Waze app for real-time traffic',
      };
      
    } catch (e) {
      print('❌ Error getting Waze traffic info: $e');
      return null;
    }
  }

  /// Get Waze route information
  Future<Map<String, dynamic>?> getWazeRoute({
    required latlong2.LatLng origin,
    required latlong2.LatLng destination,
    String travelMode = 'driving',
  }) async {
    try {
      print('🛣️ Getting Waze route...');
      
      // Note: Waze doesn't provide a public routing API
      // This is a placeholder for future implementation
      
      return {
        'origin': origin,
        'destination': destination,
        'travel_mode': travelMode,
        'note': 'Waze routing requires partner program access',
        'alternative': 'Use Waze app for routing',
      };
      
    } catch (e) {
      print('❌ Error getting Waze route: $e');
      return null;
    }
  }

  /// Check if Waze app is installed
  Future<bool> isWazeInstalled() async {
    try {
      // Try to launch Waze with a test URL
      const testUrl = 'waze://';
      final uri = Uri.parse(testUrl);
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }

  /// Get Waze app store URL for installation
  String getWazeAppStoreUrl() {
    // Return appropriate app store URL based on platform
    // This would be implemented with platform-specific code
    return 'https://www.waze.com/get';
  }

  /// Build Waze navigation URL
  String _buildWazeUrl({
    required latlong2.LatLng destination,
    String? destinationName,
    latlong2.LatLng? origin,
  }) {
    final buffer = StringBuffer();
    
    // Base Waze URL
    buffer.write('waze://?');
    
    // Add destination coordinates
    buffer.write('ll=${destination.latitude},${destination.longitude}');
    
    // Add destination name if provided
    if (destinationName != null && destinationName.isNotEmpty) {
      buffer.write('&n=${Uri.encodeComponent(destinationName)}');
    }
    
    // Add origin if provided
    if (origin != null) {
      buffer.write('&from=${origin.latitude},${origin.longitude}');
    }
    
    // Add navigation mode
    buffer.write('&navigate=yes');
    
    return buffer.toString();
  }

  /// Build Waze web URL (fallback when app is not installed)
  String _buildWazeWebUrl({
    required latlong2.LatLng destination,
    String? destinationName,
    latlong2.LatLng? origin,
  }) {
    final buffer = StringBuffer();
    
    // Base Waze web URL
    buffer.write('https://waze.com/ul?');
    
    // Add destination coordinates
    buffer.write('ll=${destination.latitude},${destination.longitude}');
    
    // Add destination name if provided
    if (destinationName != null && destinationName.isNotEmpty) {
      buffer.write('&n=${Uri.encodeComponent(destinationName)}');
    }
    
    // Add origin if provided
    if (origin != null) {
      buffer.write('&from=${origin.latitude},${origin.longitude}');
    }
    
    // Add navigation mode
    buffer.write('&navigate=yes');
    
    return buffer.toString();
  }

  /// Get alternative navigation options
  List<Map<String, dynamic>> getAlternativeNavigationOptions(
    latlong2.LatLng destination,
    String? destinationName,
  ) {
    return [
      {
        'name': 'Waze',
        'description': 'Community-based navigation with real-time traffic',
        'url': _buildWazeUrl(destination: destination, destinationName: destinationName),
        'web_url': _buildWazeWebUrl(destination: destination, destinationName: destinationName),
        'icon': 'waze',
        'features': ['Real-time traffic', 'Community updates', 'Route optimization'],
      },
      {
        'name': 'Google Maps',
        'description': 'Comprehensive mapping with detailed navigation',
        'url': 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving',
        'icon': 'google_maps',
        'features': ['Street view', 'Detailed navigation', 'Public transport'],
      },
      {
        'name': 'Apple Maps',
        'description': 'Native iOS mapping solution',
        'url': 'http://maps.apple.com/?daddr=${destination.latitude},${destination.longitude}&dirflg=d',
        'icon': 'apple_maps',
        'features': ['iOS integration', 'Privacy-focused', 'Siri integration'],
      },
    ];
  }

  /// Get Waze community features
  Map<String, dynamic> getWazeCommunityFeatures() {
    return {
      'real_time_traffic': true,
      'road_conditions': true,
      'police_alerts': true,
      'accident_reports': true,
      'construction_updates': true,
      'speed_camera_alerts': true,
      'community_edits': true,
      'route_optimization': true,
    };
  }

  /// Get Waze advantages over other navigation apps
  List<String> getWazeAdvantages() {
    return [
      'Real-time traffic updates from community',
      'Police and speed camera alerts',
      'Road condition reports',
      'Construction and accident notifications',
      'Community-driven route optimization',
      'Free to use with no ads',
      'Works offline with cached maps',
      'Social features for drivers',
    ];
  }
}
