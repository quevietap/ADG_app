import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:geocoding/geocoding.dart';
import 'philippine_geocoding_service.dart';

/// Enhanced Mapping Service
/// Integrates with Google Maps API for superior location accuracy and features
class EnhancedMappingService {
  static final EnhancedMappingService _instance = EnhancedMappingService._internal();
  factory EnhancedMappingService() => _instance;
  EnhancedMappingService._internal();

  // Configuration
  static const String _googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY'; // Replace with your API key
  static const String _googleMapsBaseUrl = 'https://maps.googleapis.com/maps/api';
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  
  // Service selection
  static const bool _useGoogleMaps = true; // Set to false to use free alternatives
  static const bool _useWazeIntegration = true;

  /// Get ultra-accurate coordinates using multiple services
  Future<Map<String, dynamic>> getEnhancedCoordinates(String address) async {
    try {
      print('🗺️ Getting enhanced coordinates for: "$address"');
      
      // Step 1: Try Philippine geocoding first (fastest for known locations)
      final philippineService = PhilippineGeocodingService();
      final philippineCoords = await philippineService.geocodePhilippineAddress(address);
      
      if (philippineCoords != null) {
        print('✅ Philippine geocoding successful: ${philippineCoords.latitude}, ${philippineCoords.longitude}');
        return {
          'coordinates': philippineCoords,
          'accuracy': 'excellent',
          'source': 'philippine_landmarks',
          'confidence': 0.95,
        };
      }

      // Step 2: Try Google Maps API (most accurate)
      if (_useGoogleMaps && _googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
        final googleCoords = await _getGoogleMapsCoordinates(address);
        if (googleCoords != null) {
          print('✅ Google Maps geocoding successful: ${googleCoords.latitude}, ${googleCoords.longitude}');
          return {
            'coordinates': googleCoords,
            'accuracy': 'excellent',
            'source': 'google_maps',
            'confidence': 0.90,
          };
        }
      }

      // Step 3: Try OpenStreetMap Nominatim (free alternative)
      final osmCoords = await _getNominatimCoordinates(address);
      if (osmCoords != null) {
        print('✅ OpenStreetMap geocoding successful: ${osmCoords.latitude}, ${osmCoords.longitude}');
        return {
          'coordinates': osmCoords,
          'accuracy': 'good',
          'source': 'openstreetmap',
          'confidence': 0.80,
        };
      }

      // Step 4: Fallback to original geocoding
      final fallbackCoords = await _getFallbackCoordinates(address);
      if (fallbackCoords != null) {
        print('⚠️ Using fallback geocoding: ${fallbackCoords.latitude}, ${fallbackCoords.longitude}');
        return {
          'coordinates': fallbackCoords,
          'accuracy': 'acceptable',
          'source': 'fallback',
          'confidence': 0.60,
        };
      }

      print('❌ All geocoding methods failed for: "$address"');
      return {
        'coordinates': null,
        'accuracy': 'unknown',
        'source': 'none',
        'confidence': 0.0,
      };

    } catch (e) {
      print('❌ Error in enhanced geocoding: $e');
      return {
        'coordinates': null,
        'accuracy': 'error',
        'source': 'error',
        'confidence': 0.0,
      };
    }
  }

  /// Get coordinates using Google Maps API
  Future<latlong2.LatLng?> _getGoogleMapsCoordinates(String address) async {
    try {
      final url = Uri.parse('$_googleMapsBaseUrl/geocode/json')
          .replace(queryParameters: {
        'address': address,
        'key': _googleMapsApiKey,
        'region': 'ph', // Philippines
        'language': 'en',
      });

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final location = result['geometry']['location'];
          
          return latlong2.LatLng(
            location['lat'].toDouble(),
            location['lng'].toDouble(),
          );
        }
      }
    } catch (e) {
      print('⚠️ Google Maps API error: $e');
    }
    return null;
  }

  /// Get coordinates using OpenStreetMap Nominatim
  Future<latlong2.LatLng?> _getNominatimCoordinates(String address) async {
    try {
      final url = Uri.parse('$_nominatimBaseUrl/search')
          .replace(queryParameters: {
        'q': '$address, Philippines',
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      });

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data.isNotEmpty) {
          final result = data[0];
          return latlong2.LatLng(
            double.parse(result['lat']),
            double.parse(result['lon']),
          );
        }
      }
    } catch (e) {
      print('⚠️ OpenStreetMap Nominatim error: $e');
    }
    return null;
  }

  /// Fallback to original geocoding
  Future<latlong2.LatLng?> _getFallbackCoordinates(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return latlong2.LatLng(
          locations.first.latitude,
          locations.first.longitude,
        );
      }
    } catch (e) {
      print('⚠️ Fallback geocoding error: $e');
    }
    return null;
  }

  /// Get enhanced route with traffic and alternatives
  Future<Map<String, dynamic>> getEnhancedRoute({
    required latlong2.LatLng origin,
    required latlong2.LatLng destination,
    bool avoidTraffic = true,
    String travelMode = 'driving',
  }) async {
    try {
      print('🛣️ Getting enhanced route...');
      
      // Try Google Maps Directions API first
      if (_useGoogleMaps && _googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
        final googleRoute = await _getGoogleMapsRoute(
          origin: origin,
          destination: destination,
          avoidTraffic: avoidTraffic,
          travelMode: travelMode,
        );
        
        if (googleRoute != null) {
          return {
            'route': googleRoute,
            'source': 'google_maps',
            'traffic_data': true,
            'alternatives': true,
          };
        }
      }

      // Fallback to OSRM
      final osrmRoute = await _getOSRMRoute(origin, destination);
      if (osrmRoute != null) {
        return {
          'route': osrmRoute,
          'source': 'osrm',
          'traffic_data': false,
          'alternatives': false,
        };
      }

      return {
        'route': null,
        'source': 'none',
        'traffic_data': false,
        'alternatives': false,
      };

    } catch (e) {
      print('❌ Error getting enhanced route: $e');
      return {
        'route': null,
        'source': 'error',
        'traffic_data': false,
        'alternatives': false,
      };
    }
  }

  /// Get route using Google Maps Directions API
  Future<List<latlong2.LatLng>?> _getGoogleMapsRoute({
    required latlong2.LatLng origin,
    required latlong2.LatLng destination,
    required bool avoidTraffic,
    required String travelMode,
  }) async {
    try {
      final url = Uri.parse('$_googleMapsBaseUrl/directions/json')
          .replace(queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': travelMode,
        'avoid': avoidTraffic ? 'traffic' : '',
        'key': _googleMapsApiKey,
        'alternatives': 'true',
      });

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polyline = route['overview_polyline']['points'];
          
          return _decodePolyline(polyline);
        }
      }
    } catch (e) {
      print('⚠️ Google Maps Directions API error: $e');
    }
    return null;
  }

  /// Get route using OSRM (free alternative)
  Future<List<latlong2.LatLng>?> _getOSRMRoute(
    latlong2.LatLng origin,
    latlong2.LatLng destination,
  ) async {
    try {
      final url = 'http://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
        
        return coordinates.map((coord) {
          return latlong2.LatLng(coord[1] as double, coord[0] as double);
        }).toList();
      }
    } catch (e) {
      print('⚠️ OSRM routing error: $e');
    }
    return null;
  }

  /// Decode Google Maps polyline
  List<latlong2.LatLng> _decodePolyline(String encoded) {
    List<latlong2.LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final p = latlong2.LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
      poly.add(p);
    }
    return poly;
  }

  /// Get real-time traffic information
  Future<Map<String, dynamic>?> getTrafficInfo(latlong2.LatLng location) async {
    try {
      if (_useGoogleMaps && _googleMapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
        final url = Uri.parse('$_googleMapsBaseUrl/geocode/json')
            .replace(queryParameters: {
          'latlng': '${location.latitude},${location.longitude}',
          'key': _googleMapsApiKey,
        });

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // Note: Google Maps doesn't provide free traffic API
          // This would require additional paid services
          return {
            'location': location,
            'traffic_level': 'unknown',
            'note': 'Traffic data requires additional Google services',
          };
        }
      }
    } catch (e) {
      print('⚠️ Traffic info error: $e');
    }
    return null;
  }

  /// Get Waze integration URL
  String getWazeNavigationUrl(latlong2.LatLng destination) {
    return 'https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes';
  }

  /// Get Google Maps navigation URL
  String getGoogleMapsNavigationUrl(latlong2.LatLng destination) {
    return 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving';
  }

  /// Validate if coordinates are in Philippines
  bool isInPhilippines(latlong2.LatLng coordinates) {
    // Philippines bounding box (approximate)
    return coordinates.latitude >= 4.0 && 
           coordinates.latitude <= 21.0 && 
           coordinates.longitude >= 116.0 && 
           coordinates.longitude <= 127.0;
  }
}
