import 'package:latlong2/latlong.dart' as latlong2;

/// Abstract base class for geocoding providers
/// This allows easy switching between different geocoding services
abstract class GeocodingProvider {
  /// Geocode an address to coordinates
  Future<GeocodingResult> geocode(String address);

  /// Reverse geocode coordinates to address
  Future<ReverseGeocodingResult> reverseGeocode(
      double latitude, double longitude);

  /// Get provider name
  String get providerName;

  /// Check if provider is available
  bool get isAvailable;
}

/// Result of geocoding operation
class GeocodingResult {
  final latlong2.LatLng? coordinates;
  final String
      accuracy; // 'building_level', 'street_level', 'city_level', 'failed'
  final String
      source; // 'known_landmark', 'enhanced_geocoding', 'google_maps', etc.
  final String description;
  final double confidence; // 0.0 to 1.0
  final String? warning;
  final List<String>? suggestions;
  final String? error;

  GeocodingResult({
    this.coordinates,
    required this.accuracy,
    required this.source,
    required this.description,
    required this.confidence,
    this.warning,
    this.suggestions,
    this.error,
  });

  bool get isSuccess => coordinates != null && error == null;
  bool get isFailure => coordinates == null || error != null;
}

/// Result of reverse geocoding operation
class ReverseGeocodingResult {
  final String? address;
  final String? formattedAddress;
  final Map<String, dynamic>? components;
  final double confidence;
  final String? error;

  ReverseGeocodingResult({
    this.address,
    this.formattedAddress,
    this.components,
    required this.confidence,
    this.error,
  });

  bool get isSuccess => address != null && error == null;
  bool get isFailure => address == null || error != null;
}

/// Geocoding service that can use multiple providers
class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  final List<GeocodingProvider> _providers = [];
  GeocodingProvider? _primaryProvider;

  /// Add a geocoding provider
  void addProvider(GeocodingProvider provider) {
    _providers.add(provider);
    _primaryProvider ??= provider;
  }

  /// Set primary provider
  void setPrimaryProvider(GeocodingProvider provider) {
    _primaryProvider = provider;
  }

  /// Get primary provider
  GeocodingProvider? get primaryProvider => _primaryProvider;

  /// Geocode using primary provider with fallbacks
  Future<GeocodingResult> geocode(String address) async {
    if (_primaryProvider == null) {
      return GeocodingResult(
        accuracy: 'failed',
        source: 'no_provider',
        description: 'No geocoding provider available',
        confidence: 0.0,
        error: 'No geocoding provider configured',
      );
    }

    // Try primary provider first
    try {
      final result = await _primaryProvider!.geocode(address);
      if (result.isSuccess) {
        return result;
      }
    } catch (e) {
      print('❌ Primary provider failed: $e');
    }

    // Try fallback providers
    for (final provider in _providers) {
      if (provider == _primaryProvider) continue;

      try {
        final result = await provider.geocode(address);
        if (result.isSuccess) {
          return result;
        }
      } catch (e) {
        print('❌ Fallback provider ${provider.providerName} failed: $e');
      }
    }

    // All providers failed
    return GeocodingResult(
      accuracy: 'failed',
      source: 'all_providers_failed',
      description: 'All geocoding providers failed',
      confidence: 0.0,
      error: 'Unable to geocode address with any available provider',
    );
  }

  /// Reverse geocode using primary provider
  Future<ReverseGeocodingResult> reverseGeocode(
      double latitude, double longitude) async {
    if (_primaryProvider == null) {
      return ReverseGeocodingResult(
        confidence: 0.0,
        error: 'No geocoding provider available',
      );
    }

    try {
      return await _primaryProvider!.reverseGeocode(latitude, longitude);
    } catch (e) {
      return ReverseGeocodingResult(
        confidence: 0.0,
        error: 'Reverse geocoding failed: $e',
      );
    }
  }

  /// Get all available providers
  List<GeocodingProvider> get availableProviders =>
      _providers.where((p) => p.isAvailable).toList();

  /// Get provider by name
  GeocodingProvider? getProviderByName(String name) {
    try {
      return _providers.firstWhere((p) => p.providerName == name);
    } catch (e) {
      return null;
    }
  }
}
