import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong2;
import 'geocoding_provider.dart';

/// Google Maps Geocoding Provider
/// This provider uses Google Maps Geocoding API for high-accuracy results
class GoogleMapsGeocodingProvider extends GeocodingProvider {
  final String apiKey;
  final String baseUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

  GoogleMapsGeocodingProvider({required this.apiKey});

  @override
  String get providerName => 'Google Maps';

  @override
  bool get isAvailable => apiKey.isNotEmpty;

  @override
  Future<GeocodingResult> geocode(String address) async {
    if (!isAvailable) {
      return GeocodingResult(
        accuracy: 'failed',
        source: 'google_maps',
        description: 'Google Maps API key not configured',
        confidence: 0.0,
        error: 'API key not available',
      );
    }

    try {
      print('🗺️ Google Maps geocoding: "$address"');
      
      final encodedAddress = Uri.encodeComponent(address);
      final url = '$baseUrl?address=$encodedAddress&key=$apiKey&region=ph';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final location = result['geometry']['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          
          // Determine accuracy based on location type
          final locationType = result['geometry']['location_type'] as String;
          final accuracy = _getAccuracyFromLocationType(locationType);
          final confidence = _calculateConfidence(result);
          
          return GeocodingResult(
            coordinates: latlong2.LatLng(lat, lng),
            accuracy: accuracy,
            source: 'google_maps',
            description: result['formatted_address'] as String,
            confidence: confidence,
          );
        } else {
          return GeocodingResult(
            accuracy: 'failed',
            source: 'google_maps',
            description: 'Google Maps geocoding failed',
            confidence: 0.0,
            error: data['status'] as String,
          );
        }
      } else {
        return GeocodingResult(
          accuracy: 'failed',
          source: 'google_maps',
          description: 'Google Maps API request failed',
          confidence: 0.0,
          error: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return GeocodingResult(
        accuracy: 'failed',
        source: 'google_maps',
        description: 'Google Maps geocoding error',
        confidence: 0.0,
        error: e.toString(),
      );
    }
  }

  @override
  Future<ReverseGeocodingResult> reverseGeocode(double latitude, double longitude) async {
    if (!isAvailable) {
      return ReverseGeocodingResult(
        confidence: 0.0,
        error: 'API key not available',
      );
    }

    try {
      print('🗺️ Google Maps reverse geocoding: $latitude, $longitude');
      
      final url = '$baseUrl?latlng=$latitude,$longitude&key=$apiKey';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          
          return ReverseGeocodingResult(
            address: result['formatted_address'] as String,
            formattedAddress: result['formatted_address'] as String,
            components: result['address_components'] as Map<String, dynamic>,
            confidence: 0.9, // Google Maps is generally very accurate
          );
        } else {
          return ReverseGeocodingResult(
            confidence: 0.0,
            error: data['status'] as String,
          );
        }
      } else {
        return ReverseGeocodingResult(
          confidence: 0.0,
          error: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return ReverseGeocodingResult(
        confidence: 0.0,
        error: e.toString(),
      );
    }
  }

  /// Convert Google Maps location type to our accuracy level
  String _getAccuracyFromLocationType(String locationType) {
    switch (locationType) {
      case 'ROOFTOP':
        return 'building_level';
      case 'RANGE_INTERPOLATED':
        return 'street_level';
      case 'GEOMETRIC_CENTER':
        return 'street_level';
      case 'APPROXIMATE':
        return 'city_level';
      default:
        return 'street_level';
    }
  }

  /// Calculate confidence based on Google Maps result
  double _calculateConfidence(Map<String, dynamic> result) {
    double confidence = 0.8; // Base confidence for Google Maps
    
    // Higher confidence for exact matches
    final locationType = result['geometry']['location_type'] as String;
    if (locationType == 'ROOFTOP') {
      confidence = 0.95;
    } else if (locationType == 'RANGE_INTERPOLATED') {
      confidence = 0.85;
    }
    
    // Check for partial matches
    final partialMatch = result['partial_match'] as bool? ?? false;
    if (partialMatch) {
      confidence *= 0.8; // Reduce confidence for partial matches
    }
    
    return confidence.clamp(0.0, 1.0);
  }
}
