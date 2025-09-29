import 'package:latlong2/latlong.dart' as latlong2;
import 'geocoding_provider.dart';
import 'philippine_geocoding_service.dart';

/// Philippine Geocoding Provider Adapter
/// This adapts the existing PhilippineGeocodingService to the new provider interface
class PhilippineGeocodingProvider extends GeocodingProvider {
  final PhilippineGeocodingService _philippineService = PhilippineGeocodingService();

  @override
  String get providerName => 'Philippine Geocoding';

  @override
  bool get isAvailable => true; // Always available

  @override
  Future<GeocodingResult> geocode(String address) async {
    try {
      print('🇵🇭 Philippine geocoding: "$address"');
      
      final result = await _philippineService.geocodePhilippineAddressWithDetails(address);
      
      return GeocodingResult(
        coordinates: result['coordinates'] as latlong2.LatLng?,
        accuracy: result['accuracy'] as String,
        source: result['source'] as String,
        description: result['description'] as String,
        confidence: result['confidence'] as double,
        warning: result['warning'] as String?,
        suggestions: result['suggestions'] as List<String>?,
        error: result['error'] as String?,
      );
    } catch (e) {
      return GeocodingResult(
        accuracy: 'failed',
        source: 'philippine_geocoding',
        description: 'Philippine geocoding error',
        confidence: 0.0,
        error: e.toString(),
      );
    }
  }

  @override
  Future<ReverseGeocodingResult> reverseGeocode(double latitude, double longitude) async {
    try {
      print('🇵🇭 Philippine reverse geocoding: $latitude, $longitude');
      
      // For now, we'll use a simple reverse geocoding approach
      // In the future, this could be enhanced with Philippine-specific reverse geocoding
      return ReverseGeocodingResult(
        address: 'Location at $latitude, $longitude',
        formattedAddress: 'Location at $latitude, $longitude',
        confidence: 0.5, // Lower confidence for basic reverse geocoding
      );
    } catch (e) {
      return ReverseGeocodingResult(
        confidence: 0.0,
        error: e.toString(),
      );
    }
  }
}
