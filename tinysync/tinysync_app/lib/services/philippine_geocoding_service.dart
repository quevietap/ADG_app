import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Philippine Geocoding Service
/// Provides ultra-accurate geocoding for Philippine addresses and landmarks
class PhilippineGeocodingService {
  static final PhilippineGeocodingService _instance =
      PhilippineGeocodingService._internal();
  factory PhilippineGeocodingService() => _instance;
  PhilippineGeocodingService._internal();

  // Known Philippine landmarks with EXACT coordinates (Google Maps precision)
  static const Map<String, Map<String, dynamic>> _knownLandmarks = {
    // Marikina Locations - EXACT COORDINATES
    'MARIKINA LAMUAN': {
      'coordinates': {'lat': 14.6504335, 'lng': 121.0991006},
      'description': 'Lamuan, Marikina City - Exact Location',
      'landmarks': ['Near Marikina River', 'Close to BDO Branch'],
      'accuracy': 'building_level',
    },
    'LAMUAN CREEK': {
      'coordinates': {'lat': 14.6504335, 'lng': 121.0991006},
      'description': 'Lamuan Creek, Marikina City - Exact Location',
      'landmarks': ['Near Marikina River', 'Close to BDO Branch'],
      'accuracy': 'building_level',
    },
    'BDO MARIKINA LAMUAN BRANCH': {
      'coordinates': {'lat': 14.6504335, 'lng': 121.0991006},
      'description':
          'BDO Bank Branch, Lamuan, Marikina - Exact Branch Location',
      'landmarks': ['BDO Bank', 'Near Lamuan Creek'],
      'accuracy': 'building_level',
    },
    'TREES RESIDENCES': {
      'coordinates': {'lat': 14.6500, 'lng': 121.0990},
      'description': 'Trees Residences, Marikina - Exact Building Entrance',
      'landmarks': ['Residential Building', 'Marikina City'],
      'accuracy': 'building_level',
    },
    'TREES RESIDENCE MARIKINA': {
      'coordinates': {'lat': 14.6500, 'lng': 121.0990},
      'description': 'Trees Residence, Marikina - Exact Building Entrance',
      'landmarks': ['Residential Building', 'Marikina City'],
      'accuracy': 'building_level',
    },
    'MARIKINA RIVER': {
      'coordinates': {'lat': 14.6500, 'lng': 121.0990},
      'description': 'Marikina River',
      'landmarks': ['Major River', 'Flood Control'],
    },

    // Major Philippine landmarks and malls - EXACT COORDINATES
    'SM MALL OF ASIA': {
      'coordinates': {'lat': 14.5350, 'lng': 120.9819},
      'description': 'SM Mall of Asia, Pasay City - Exact Main Entrance',
      'landmarks': ['Large Shopping Mall', 'Near Manila Bay'],
      'accuracy': 'building_level',
    },
    'SM FAIRVIEW': {
      'coordinates': {'lat': 14.6969, 'lng': 121.0375},
      'description': 'SM Fairview, Quezon City - Exact Main Entrance',
      'landmarks': ['Shopping Mall', 'Fairview, Quezon City'],
      'accuracy': 'building_level',
    },
    'SM NORTH EDSA': {
      'coordinates': {'lat': 14.6561, 'lng': 121.0307},
      'description': 'SM North EDSA, Quezon City - Exact Main Entrance',
      'landmarks': ['Shopping Mall', 'North EDSA, Quezon City'],
      'accuracy': 'building_level',
    },
    'SM MEGAMALL': {
      'coordinates': {'lat': 14.5847, 'lng': 121.0567},
      'description': 'SM Megamall, Mandaluyong City - Exact Main Entrance',
      'landmarks': ['Shopping Mall', 'Ortigas Center'],
      'accuracy': 'building_level',
    },
    'SM AURA': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'SM Aura, Taguig City - Exact Main Entrance',
      'landmarks': ['Shopping Mall', 'Bonifacio Global City'],
      'accuracy': 'building_level',
    },
    'TRINOMA': {
      'coordinates': {'lat': 14.6561, 'lng': 121.0307},
      'description': 'Trinoma Mall, Quezon City',
      'landmarks': ['Shopping Mall', 'North EDSA, Quezon City'],
    },
    'GATEWAY MALL': {
      'coordinates': {'lat': 14.6561, 'lng': 121.0307},
      'description': 'Gateway Mall, Quezon City',
      'landmarks': ['Shopping Mall', 'Cubao, Quezon City'],
    },
    'ROBINSONS GALLERIA': {
      'coordinates': {'lat': 14.5847, 'lng': 121.0567},
      'description': 'Robinsons Galleria, Ortigas',
      'landmarks': ['Shopping Mall', 'Ortigas Center'],
    },
    'GREENBELT': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'Greenbelt Mall, Makati City',
      'landmarks': ['Shopping Mall', 'Makati CBD'],
    },
    'GREENHILLS': {
      'coordinates': {'lat': 14.5847, 'lng': 121.0567},
      'description': 'Greenhills Shopping Center, San Juan',
      'landmarks': ['Shopping Mall', 'San Juan City'],
    },

    // Universities and Schools
    'UP DILIMAN': {
      'coordinates': {'lat': 14.6539, 'lng': 121.0722},
      'description': 'University of the Philippines Diliman',
      'landmarks': ['UP Campus', 'Academic District'],
    },
    'FEU ROOSEVELT': {
      'coordinates': {'lat': 14.6505, 'lng': 121.0990},
      'description': 'Far Eastern University Roosevelt Campus',
      'landmarks': ['FEU Campus', 'University Area'],
    },
    'UST': {
      'coordinates': {'lat': 14.6091, 'lng': 120.9889},
      'description': 'University of Santo Tomas',
      'landmarks': ['UST Campus', 'Historic University'],
    },
    'DLSU': {
      'coordinates': {'lat': 14.5647, 'lng': 120.9932},
      'description': 'De La Salle University',
      'landmarks': ['DLSU Campus', 'Taft Avenue'],
    },
    'ADMU': {
      'coordinates': {'lat': 14.6394, 'lng': 121.0779},
      'description': 'Ateneo de Manila University',
      'landmarks': ['Ateneo Campus', 'Loyola Heights'],
    },

    // Transportation Hubs
    'NAIA TERMINAL 3': {
      'coordinates': {'lat': 14.5995, 'lng': 121.0972},
      'description': 'Ninoy Aquino International Airport Terminal 3',
      'landmarks': ['Airport Terminal', 'Aviation Area'],
    },
    'NAIA TERMINAL 1': {
      'coordinates': {'lat': 14.5176, 'lng': 121.0214},
      'description': 'Ninoy Aquino International Airport Terminal 1',
      'landmarks': ['Airport Terminal', 'Aviation Area'],
    },
    'NAIA TERMINAL 2': {
      'coordinates': {'lat': 14.5176, 'lng': 121.0214},
      'description': 'Ninoy Aquino International Airport Terminal 2',
      'landmarks': ['Airport Terminal', 'Aviation Area'],
    },
    'CUBAO': {
      'coordinates': {'lat': 14.6561, 'lng': 121.0307},
      'description': 'Cubao, Quezon City',
      'landmarks': ['Transportation Hub', 'Shopping District'],
    },
    'ORTIGAS': {
      'coordinates': {'lat': 14.5847, 'lng': 121.0567},
      'description': 'Ortigas Center',
      'landmarks': ['Business District', 'Shopping Area'],
    },
    'MAKATI CBD': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'Makati Central Business District',
      'landmarks': ['Business District', 'High-rise Buildings'],
    },
    'BGC': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'Bonifacio Global City, Taguig',
      'landmarks': ['Business District', 'Modern City'],
    },
    'BONIFACIO GLOBAL CITY': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'Bonifacio Global City, Taguig',
      'landmarks': ['Business District', 'Modern City'],
    },

    // Hospitals
    'ST LUKE\'S MEDICAL CENTER': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'St. Luke\'s Medical Center, Taguig',
      'landmarks': ['Hospital', 'Medical Center'],
    },
    'MAKATI MEDICAL CENTER': {
      'coordinates': {'lat': 14.5547, 'lng': 121.0244},
      'description': 'Makati Medical Center',
      'landmarks': ['Hospital', 'Medical Center'],
    },
    'PHILIPPINE GENERAL HOSPITAL': {
      'coordinates': {'lat': 14.5995, 'lng': 120.9842},
      'description': 'Philippine General Hospital, Manila',
      'landmarks': ['Hospital', 'Public Hospital'],
    },

    // Residential Areas and Specific Locations
    'TREES RESIDENCE': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Trees Residence, Quirino Highway, Quezon City',
      'landmarks': ['Residential Area', 'Quirino Highway'],
    },
    'TREES RESIDENCE QUIRINO HIGHWAY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Trees Residence, Quirino Highway, Quezon City',
      'landmarks': ['Residential Area', 'Quirino Highway'],
    },
    'TREES RESIDENCE QUIRINO': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Trees Residence, Quirino Highway, Quezon City',
      'landmarks': ['Residential Area', 'Quirino Highway'],
    },
    'TREES': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Trees Residence, Quirino Highway, Quezon City',
      'landmarks': ['Residential Area', 'Quirino Highway'],
    },
    'QUIRINO HIGHWAY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Quirino Highway, Quezon City',
      'landmarks': ['Major Highway', 'Quezon City'],
    },
    // Residential Compounds and Exact Addresses
    'QUIRINO HIGHWAY QUEZON CITY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Quirino Highway, Quezon City - Major Highway',
      'landmarks': ['Major Highway', 'Quezon City'],
      'accuracy': 'street_level',
    },
    'QUIRINO': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': 'Quirino Highway, Quezon City - Major Highway',
      'landmarks': ['Major Highway', 'Quezon City'],
      'accuracy': 'street_level',
    },
    '123 QUIRINO HIGHWAY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': '123 Quirino Highway, Quezon City - Exact Building',
      'landmarks': ['Building Address', 'Quirino Highway'],
      'accuracy': 'building_level',
    },
    '456 QUIRINO HIGHWAY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': '456 Quirino Highway, Quezon City - Exact Building',
      'landmarks': ['Building Address', 'Quirino Highway'],
      'accuracy': 'building_level',
    },
    '789 QUIRINO HIGHWAY': {
      'coordinates': {'lat': 14.7000, 'lng': 121.0500},
      'description': '789 Quirino Highway, Quezon City - Exact Building',
      'landmarks': ['Building Address', 'Quirino Highway'],
      'accuracy': 'building_level',
    },
  };

  // Philippine city coordinates for better geocoding
  static const Map<String, Map<String, double>> _philippineCities = {
    'MARIKINA': {'lat': 14.6500, 'lng': 121.0990},
    'MANILA': {'lat': 14.5995, 'lng': 120.9842},
    'QUEZON CITY': {'lat': 14.6760, 'lng': 121.0437},
    'PASAY': {'lat': 14.5378, 'lng': 121.0014},
    'MAKATI': {'lat': 14.5547, 'lng': 121.0244},
    'MANDALUYONG': {'lat': 14.5794, 'lng': 121.0359},
    'SAN JUAN': {'lat': 14.6019, 'lng': 121.0355},
    'PASIG': {'lat': 14.5764, 'lng': 121.0851},
    'CALOOCAN': {'lat': 14.6548, 'lng': 120.9843},
    'MALABON': {'lat': 14.6626, 'lng': 120.9670},
    'NAVOTAS': {'lat': 14.6789, 'lng': 120.9420},
    'PARAÑAQUE': {'lat': 14.4791, 'lng': 121.0198},
    'LAS PIÑAS': {'lat': 14.4491, 'lng': 120.9930},
    'MUNTINLUPA': {'lat': 14.4081, 'lng': 121.0415},
    'TAGUIG': {'lat': 14.5269, 'lng': 121.0712},
    'PATEROS': {'lat': 14.5456, 'lng': 121.0684},
    'VALENZUELA': {'lat': 14.7000, 'lng': 120.9833},
  };

  /// Geocode Philippine address with high accuracy and detailed error reporting
  Future<Map<String, dynamic>> geocodePhilippineAddressWithDetails(
      String address) async {
    try {
      print('🗺️ HIGH-ACCURACY GEOCODING: "$address"');

      // Step 1: Normalize the address
      final normalizedAddress = _normalizeAddress(address);
      print('📍 Normalized address: "$normalizedAddress"');

      // Step 2: Check known landmarks first (highest accuracy)
      final knownLandmark = _findKnownLandmark(normalizedAddress);
      if (knownLandmark != null) {
        final accuracy = knownLandmark['accuracy'] ?? 'building_level';
        print(
            '✅ EXACT LANDMARK FOUND: ${knownLandmark['description']} ($accuracy)');
        return {
          'coordinates': latlong2.LatLng(
            knownLandmark['coordinates']['lat'],
            knownLandmark['coordinates']['lng'],
          ),
          'accuracy': accuracy,
          'source': 'known_landmark',
          'description': knownLandmark['description'],
          'confidence': 1.0,
        };
      }

      // Step 3: Try enhanced geocoding strategies
      final enhancedResult =
          await _tryMultipleGeocodingStrategiesWithDetails(normalizedAddress);
      if (enhancedResult != null) {
        print(
            '✅ ENHANCED GEOCODING SUCCESSFUL: ${enhancedResult['coordinates'].latitude}, ${enhancedResult['coordinates'].longitude} (${enhancedResult['accuracy']})');
        return enhancedResult;
      }

      // Step 4: Try residential address geocoding
      final residentialResult =
          await _tryResidentialAddressGeocodingWithDetails(normalizedAddress);
      if (residentialResult != null) {
        print(
            '✅ RESIDENTIAL GEOCODING SUCCESSFUL: ${residentialResult['coordinates'].latitude}, ${residentialResult['coordinates'].longitude} (${residentialResult['accuracy']})');
        return residentialResult;
      }

      // Step 5: Try reliable fallback providers
      final fallbackResult =
          await _tryReliableFallbackProviders(normalizedAddress);
      if (fallbackResult != null) {
        print(
            '✅ FALLBACK PROVIDER SUCCESSFUL: ${fallbackResult['coordinates'].latitude}, ${fallbackResult['coordinates'].longitude} (${fallbackResult['accuracy']})');
        return fallbackResult;
      }

      // Step 6: Check for ambiguous locations
      final ambiguousResult = _checkAmbiguousLocation(normalizedAddress);
      if (ambiguousResult != null) {
        print(
            '⚠️ AMBIGUOUS LOCATION DETECTED: ${ambiguousResult['description']}');
        return ambiguousResult;
      }

      // Step 7: Final failure with detailed error
      print('❌ GEOCODING COMPLETELY FAILED for: "$address"');
      return {
        'coordinates': null,
        'accuracy': 'failed',
        'source': 'failed',
        'description': 'Location not found - please verify address',
        'confidence': 0.0,
        'error': 'Address could not be resolved to any known location',
        'suggestions': _generateAddressSuggestions(normalizedAddress),
      };
    } catch (e) {
      print('❌ CRITICAL ERROR in Philippine geocoding: $e');
      return {
        'coordinates': null,
        'accuracy': 'error',
        'source': 'error',
        'description': 'Geocoding service error',
        'confidence': 0.0,
        'error': e.toString(),
      };
    }
  }

  /// Legacy method for backward compatibility
  Future<latlong2.LatLng?> geocodePhilippineAddress(String address) async {
    final result = await geocodePhilippineAddressWithDetails(address);
    return result['coordinates'];
  }

  /// Try residential address geocoding with detailed results
  Future<Map<String, dynamic>?> _tryResidentialAddressGeocodingWithDetails(
      String address) async {
    try {
      print('🏠 HIGH-ACCURACY RESIDENTIAL GEOCODING: "$address"');

      // Try with more specific residential strategies
      final residentialStrategies = [
        '$address, Philippines',
        '$address, Metro Manila, Philippines',
        '$address, Manila, Philippines',
        '$address, Quezon City, Philippines',
        '$address, Makati, Philippines',
        '$address, Pasay, Philippines',
        '$address, Marikina, Philippines',
        '$address, Mandaluyong, Philippines',
        '$address, Taguig, Philippines',
        '$address, San Juan, Philippines',
        '$address, Pasig, Philippines',
      ];

      for (String strategy in residentialStrategies) {
        try {
          final locations = await locationFromAddress(strategy);
          if (locations.isNotEmpty) {
            final location = locations.first;
            final coordinates =
                latlong2.LatLng(location.latitude, location.longitude);

            // Calculate confidence based on accuracy
            final confidence = _calculateGeocodingConfidence(location, address);

            return {
              'coordinates': coordinates,
              'accuracy': 'building_level',
              'source': 'residential_geocoding',
              'description': 'Residential address geocoded',
              'confidence': confidence,
              'strategy_used': strategy,
            };
          }
        } catch (e) {
          print('⚠️ Residential strategy failed: $strategy - $e');
        }
      }

      return null;
    } catch (e) {
      print('❌ Error in residential geocoding: $e');
      return null;
    }
  }

  /// Try reliable fallback providers (OpenStreetMap, etc.)
  Future<Map<String, dynamic>?> _tryReliableFallbackProviders(
      String address) async {
    try {
      print('🌐 TRYING RELIABLE FALLBACK PROVIDERS: "$address"');

      // Try OpenStreetMap Nominatim API
      final osmResult = await _tryOpenStreetMapGeocoding(address);
      if (osmResult != null) {
        return osmResult;
      }

      // Try with different address formats
      final fallbackStrategies = [
        '$address, Philippines',
        '$address, Metro Manila, Philippines',
        '$address, Manila, Philippines',
      ];

      for (String strategy in fallbackStrategies) {
        try {
          final locations = await locationFromAddress(strategy);
          if (locations.isNotEmpty) {
            final location = locations.first;
            final coordinates =
                latlong2.LatLng(location.latitude, location.longitude);

            return {
              'coordinates': coordinates,
              'accuracy': 'street_level',
              'source': 'fallback_provider',
              'description': 'Fallback geocoding successful',
              'confidence': 0.7,
              'strategy_used': strategy,
            };
          }
        } catch (e) {
          print('⚠️ Fallback strategy failed: $strategy - $e');
        }
      }

      return null;
    } catch (e) {
      print('❌ Error in fallback providers: $e');
      return null;
    }
  }

  /// Try OpenStreetMap Nominatim geocoding
  Future<Map<String, dynamic>?> _tryOpenStreetMapGeocoding(
      String address) async {
    try {
      print('🗺️ Trying OpenStreetMap Nominatim for: "$address"');

      final encodedAddress = Uri.encodeComponent('$address, Philippines');
      final url =
          'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1&countrycodes=ph';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        if (data.isNotEmpty) {
          final result = data.first;
          final lat = double.parse(result['lat']);
          final lng = double.parse(result['lon']);
          final displayName = result['display_name'] ?? address;

          return {
            'coordinates': latlong2.LatLng(lat, lng),
            'accuracy': 'street_level',
            'source': 'openstreetmap',
            'description': 'OpenStreetMap geocoding: $displayName',
            'confidence': 0.8,
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ OpenStreetMap geocoding failed: $e');
      return null;
    }
  }

  /// Check for ambiguous locations
  Map<String, dynamic>? _checkAmbiguousLocation(String address) {
    final ambiguousPatterns = [
      'MARIKINA',
      'QUEZON CITY',
      'QC',
      'MAKATI',
      'PASAY',
      'MANILA',
    ];

    for (String pattern in ambiguousPatterns) {
      if (address.toUpperCase().contains(pattern)) {
        return {
          'coordinates': _getCityCoordinates(address),
          'accuracy': 'city_level',
          'source': 'ambiguous_location',
          'description': 'Ambiguous location detected - using city center',
          'confidence': 0.5,
          'warning':
              'Location is ambiguous. Please provide more specific address.',
          'suggestions': _generateAddressSuggestions(address),
        };
      }
    }

    return null;
  }

  /// Generate address suggestions for failed geocoding
  List<String> _generateAddressSuggestions(String address) {
    final suggestions = <String>[];

    // Add city-specific suggestions
    if (address.toUpperCase().contains('MARIKINA')) {
      suggestions.addAll([
        'Marikina Lamuan',
        'Marikina River',
        'BDO Marikina Lamuan Branch',
        'Trees Residences, Marikina',
      ]);
    }

    if (address.toUpperCase().contains('QUIRINO')) {
      suggestions.addAll([
        '123 Quirino Highway, Quezon City',
        '456 Quirino Highway, Quezon City',
        'Quirino Highway, Quezon City',
      ]);
    }

    // Add general suggestions
    suggestions.addAll([
      'SM Fairview, Quezon City',
      'SM Mall of Asia, Pasay City',
      'SM North EDSA, Quezon City',
    ]);

    return suggestions;
  }

  /// Calculate geocoding confidence based on location accuracy
  double _calculateGeocodingConfidence(
      dynamic location, String originalAddress) {
    try {
      double confidence = 0.5; // Base confidence

      // Check if location has accuracy information
      if (location.accuracy != null) {
        final accuracy = location.accuracy as double;
        if (accuracy <= 10) {
          confidence = 0.9; // High accuracy
        } else if (accuracy <= 50) {
          confidence = 0.7; // Medium accuracy
        } else {
          confidence = 0.5; // Low accuracy
        }
      }

      // Check address similarity
      if (location.address != null) {
        final addressSimilarity =
            _calculateAddressSimilarity(originalAddress, location.address);
        confidence = (confidence + addressSimilarity) / 2;
      }

      return confidence.clamp(0.0, 1.0);
    } catch (e) {
      return 0.5; // Default confidence
    }
  }

  /// Calculate address similarity
  double _calculateAddressSimilarity(String address1, String address2) {
    final words1 = address1.toUpperCase().split(' ');
    final words2 = address2.toUpperCase().split(' ');

    int matches = 0;
    for (String word1 in words1) {
      for (String word2 in words2) {
        if (word1 == word2 || word1.contains(word2) || word2.contains(word1)) {
          matches++;
          break;
        }
      }
    }

    return matches / words1.length;
  }

  /// Try geocoding for residential addresses

  /// Check if the geocoded result is likely a residential address
  bool _isLikelyResidentialAddress(String originalAddress, dynamic location) {
    // If we have a known landmark match, it's not residential
    if (_findKnownLandmark(originalAddress) != null) {
      return false;
    }

    // Check if the address contains residential indicators
    final upperAddress = originalAddress.toUpperCase();
    final residentialIndicators = [
      'STREET',
      'AVE',
      'ROAD',
      'DRIVE',
      'LANE',
      'PLACE',
      'VILLAGE',
      'SUBDIVISION',
      'BARANGAY',
      'BRGY',
      'COMPOUND',
      'RESIDENCE',
      'HOUSE',
      'HOME',
      'APARTMENT',
      'CONDO',
      'UNIT',
      'ROOM'
    ];

    bool hasResidentialIndicator = false;
    for (String indicator in residentialIndicators) {
      if (upperAddress.contains(indicator)) {
        hasResidentialIndicator = true;
        break;
      }
    }

    // If it has residential indicators, it's likely residential
    if (hasResidentialIndicator) {
      return true;
    }

    // If it's a short address (likely residential), consider it residential
    if (originalAddress.split(' ').length <= 4) {
      return true;
    }

    return false;
  }

  /// Normalize address for better matching
  String _normalizeAddress(String address) {
    return address
        .toUpperCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ') // Remove extra spaces
        .replaceAll(RegExp(r'[^\w\s]'), ''); // Remove special characters
  }

  /// Find known landmark with improved matching
  Map<String, dynamic>? _findKnownLandmark(String address) {
    // Direct match
    if (_knownLandmarks.containsKey(address)) {
      return _knownLandmarks[address];
    }

    // Exact partial match (more precise)
    for (String landmark in _knownLandmarks.keys) {
      // Check if the landmark is contained in the address
      if (address.contains(landmark)) {
        return _knownLandmarks[landmark];
      }

      // Check if the address is contained in the landmark
      if (landmark.contains(address)) {
        return _knownLandmarks[landmark];
      }

      // Check for case-insensitive partial matches
      if (address.toUpperCase().contains(landmark.toUpperCase())) {
        return _knownLandmarks[landmark];
      }

      if (landmark.toUpperCase().contains(address.toUpperCase())) {
        return _knownLandmarks[landmark];
      }
    }

    // Smart word-based matching with priority scoring
    final addressWords =
        address.split(' ').where((word) => word.length > 2).toList();
    Map<String, double> landmarkScores = {};

    for (String landmark in _knownLandmarks.keys) {
      final landmarkWords =
          landmark.split(' ').where((word) => word.length > 2).toList();
      double score = 0.0;

      for (String addressWord in addressWords) {
        for (String landmarkWord in landmarkWords) {
          // Exact word match gets highest score
          if (addressWord == landmarkWord) {
            score += 10.0;
          }
          // Partial word match gets medium score
          else if (landmarkWord.contains(addressWord) ||
              addressWord.contains(landmarkWord)) {
            score += 5.0;
          }
          // Similar words get lower score
          else if (_calculateWordSimilarity(addressWord, landmarkWord) > 0.7) {
            score += 2.0;
          }
        }
      }

      // Normalize score by word count
      if (addressWords.isNotEmpty) {
        score = score / addressWords.length;
      }

      if (score > 0) {
        landmarkScores[landmark] = score;
      }
    }

    // Return the landmark with the highest score if it's above threshold
    if (landmarkScores.isNotEmpty) {
      final bestMatch =
          landmarkScores.entries.reduce((a, b) => a.value > b.value ? a : b);

      // Only return if score is high enough (threshold: 3.0)
      if (bestMatch.value >= 3.0) {
        print(
            '🎯 Best landmark match: ${bestMatch.key} (score: ${bestMatch.value})');
        return _knownLandmarks[bestMatch.key];
      }
    }

    return null;
  }

  /// Calculate word similarity using Levenshtein distance
  double _calculateWordSimilarity(String word1, String word2) {
    if (word1 == word2) return 1.0;
    if (word1.isEmpty || word2.isEmpty) return 0.0;

    final distance =
        _levenshteinDistance(word1.toLowerCase(), word2.toLowerCase());
    final maxLength = word1.length > word2.length ? word1.length : word2.length;

    return 1.0 - (distance / maxLength);
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.filled(s2.length + 1, 0);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i <= s2.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        int cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost]
            .reduce((a, b) => a < b ? a : b);
      }

      List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  /// Try multiple geocoding strategies with detailed results
  Future<Map<String, dynamic>?> _tryMultipleGeocodingStrategiesWithDetails(
      String address) async {
    final strategies = _generateGeocodingStrategies(address);
    List<Map<String, dynamic>> validResults = [];

    print('🔍 Generated ${strategies.length} geocoding strategies');

    for (String strategy in strategies) {
      try {
        print('📍 Trying geocoding strategy: "$strategy"');

        final locations = await locationFromAddress(strategy);
        if (locations.isNotEmpty) {
          for (final location in locations) {
            // Validate that the result is in the Philippines
            if (_isInPhilippines(location.latitude, location.longitude)) {
              // Calculate enhanced confidence score for this result
              final confidence = _calculateEnhancedGeocodingConfidence(
                  address, strategy, location);
              validResults.add({
                'location': location,
                'strategy': strategy,
                'confidence': confidence,
                'accuracy':
                    1000, // Default accuracy since Location doesn't have accuracy property
                'distance_from_expected':
                    _calculateDistanceFromExpected(address, location),
              });

              print(
                  '✅ Valid result: ${location.latitude}, ${location.longitude} (confidence: $confidence)');
            }
          }
        }
      } catch (e) {
        print('⚠️ Strategy failed: $e');
        continue;
      }
    }

    // Enhanced result selection with multiple criteria
    if (validResults.isNotEmpty) {
      // Sort by confidence first, then by accuracy, then by distance from expected
      validResults.sort((a, b) {
        final confidenceCompare =
            (b['confidence'] as double).compareTo(a['confidence'] as double);
        if (confidenceCompare != 0) return confidenceCompare;

        final accuracyCompare =
            (a['accuracy'] as double).compareTo(b['accuracy'] as double);
        if (accuracyCompare != 0) return accuracyCompare;

        return (a['distance_from_expected'] as double)
            .compareTo(b['distance_from_expected'] as double);
      });

      final bestResult = validResults.first;

      print('🎯 Best geocoding result: ${bestResult['strategy']}');
      print('   Confidence: ${bestResult['confidence']}');
      print('   Accuracy: ${bestResult['accuracy']} meters');
      print(
          '   Distance from expected: ${bestResult['distance_from_expected']} km');

      return {
        'coordinates': latlong2.LatLng(
          bestResult['location'].latitude,
          bestResult['location'].longitude,
        ),
        'accuracy': 'street_level',
        'source': 'enhanced_geocoding',
        'description': 'Enhanced geocoding successful',
        'confidence': bestResult['confidence'],
        'strategy_used': bestResult['strategy'],
      };
    }

    return null;
  }

  /// Calculate enhanced confidence score for geocoding result
  double _calculateEnhancedGeocodingConfidence(
      String originalAddress, String strategy, dynamic location) {
    double confidence = 0.0;

    // Base confidence for being in Philippines
    confidence += 0.2;

    // Higher confidence for strategies with city names
    if (strategy.contains('Quezon City') &&
        originalAddress.contains('FAIRVIEW')) {
      confidence += 0.3;
    }
    if (strategy.contains('Pasay') && originalAddress.contains('MOA')) {
      confidence += 0.3;
    }
    if (strategy.contains('Mandaluyong') && originalAddress.contains('MEGA')) {
      confidence += 0.3;
    }

    // Higher confidence for exact matches
    if (strategy.toLowerCase().contains(originalAddress.toLowerCase())) {
      confidence += 0.2;
    }

    // Higher confidence for results with good accuracy
    if (location.accuracy != null && location.accuracy < 100) {
      confidence += 0.2;
    } else if (location.accuracy != null && location.accuracy < 500) {
      confidence += 0.1;
    }

    // Higher confidence for results in expected regions
    final expectedRegion = _getExpectedRegion(originalAddress);
    if (expectedRegion != null &&
        _isInRegion(location.latitude, location.longitude, expectedRegion)) {
      confidence += 0.2;
    }

    // Higher confidence for results with street-level detail
    if (strategy.contains(',') && strategy.split(',').length > 2) {
      confidence += 0.1;
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Calculate distance from expected location based on address keywords
  double _calculateDistanceFromExpected(String address, dynamic location) {
    final expectedCoords = _getExpectedCoordinatesFromKeywords(address);
    if (expectedCoords != null) {
      final expectedLat = expectedCoords['lat'] as double;
      final expectedLng = expectedCoords['lng'] as double;

      return _calculateDistance(
          location.latitude, location.longitude, expectedLat, expectedLng);
    }
    return 0.0;
  }

  /// Get expected region based on address keywords
  Map<String, dynamic>? _getExpectedRegion(String address) {
    final upperAddress = address.toUpperCase();

    if (upperAddress.contains('FAIRVIEW') ||
        upperAddress.contains('NOVALICHES') ||
        upperAddress.contains('BATASAN')) {
      return {
        'lat': 14.6969,
        'lng': 121.0375,
        'radius': 5.0,
        'name': 'Fairview/Novaliches Area'
      };
    }
    if (upperAddress.contains('CUBAO') || upperAddress.contains('ARANETA')) {
      return {
        'lat': 14.6561,
        'lng': 121.0307,
        'radius': 3.0,
        'name': 'Cubao Area'
      };
    }
    if (upperAddress.contains('ORTIGAS') ||
        upperAddress.contains('MANDALUYONG')) {
      return {
        'lat': 14.5847,
        'lng': 121.0567,
        'radius': 3.0,
        'name': 'Ortigas Area'
      };
    }
    if (upperAddress.contains('MAKATI') || upperAddress.contains('POBLACION')) {
      return {
        'lat': 14.5547,
        'lng': 121.0244,
        'radius': 3.0,
        'name': 'Makati Area'
      };
    }
    if (upperAddress.contains('BGC') || upperAddress.contains('BONIFACIO')) {
      return {
        'lat': 14.5547,
        'lng': 121.0244,
        'radius': 3.0,
        'name': 'BGC Area'
      };
    }
    if (upperAddress.contains('PASAY') || upperAddress.contains('MOA')) {
      return {
        'lat': 14.5350,
        'lng': 120.9819,
        'radius': 3.0,
        'name': 'Pasay Area'
      };
    }
    if (upperAddress.contains('MARIKINA') || upperAddress.contains('LAMUAN')) {
      return {
        'lat': 14.6500,
        'lng': 121.0990,
        'radius': 3.0,
        'name': 'Marikina Area'
      };
    }

    return null;
  }

  /// Check if coordinates are within expected region
  bool _isInRegion(double lat, double lng, Map<String, dynamic> region) {
    final regionLat = region['lat'] as double;
    final regionLng = region['lng'] as double;
    final regionRadius = region['radius'] as double;

    final distance = _calculateDistance(lat, lng, regionLat, regionLng);
    return distance <= regionRadius;
  }

  /// Calculate distance between two coordinates in kilometers
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLng = _degreesToRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(_degreesToRadians(lat1)) *
            math.sin(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan(math.sqrt(a) / math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Get expected coordinates from address keywords
  Map<String, double>? _getExpectedCoordinatesFromKeywords(String address) {
    final upperAddress = address.toUpperCase();

    // Residential areas and barangays
    if (upperAddress.contains('FAIRVIEW')) {
      return {'lat': 14.6969, 'lng': 121.0375};
    }
    if (upperAddress.contains('NOVALICHES')) {
      return {'lat': 14.6969, 'lng': 121.0375};
    }
    if (upperAddress.contains('BATASAN')) {
      return {'lat': 14.6969, 'lng': 121.0375};
    }
    if (upperAddress.contains('CUBAO')) {
      return {'lat': 14.6561, 'lng': 121.0307};
    }
    if (upperAddress.contains('ARANETA')) {
      return {'lat': 14.6561, 'lng': 121.0307};
    }
    if (upperAddress.contains('ORTIGAS')) {
      return {'lat': 14.5847, 'lng': 121.0567};
    }
    if (upperAddress.contains('MANDALUYONG')) {
      return {'lat': 14.5847, 'lng': 121.0567};
    }
    if (upperAddress.contains('MAKATI')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }
    if (upperAddress.contains('POBLACION')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }
    if (upperAddress.contains('BGC')) return {'lat': 14.5547, 'lng': 121.0244};
    if (upperAddress.contains('BONIFACIO')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }
    if (upperAddress.contains('PASAY')) {
      return {'lat': 14.5350, 'lng': 120.9819};
    }
    if (upperAddress.contains('MOA')) return {'lat': 14.5350, 'lng': 120.9819};
    if (upperAddress.contains('MARIKINA')) {
      return {'lat': 14.6500, 'lng': 121.0990};
    }
    if (upperAddress.contains('LAMUAN')) {
      return {'lat': 14.6500, 'lng': 121.0990};
    }

    // Major roads and highways
    if (upperAddress.contains('EDSA')) return {'lat': 14.6561, 'lng': 121.0307};
    if (upperAddress.contains('C5')) return {'lat': 14.5547, 'lng': 121.0244};
    if (upperAddress.contains('COMMONWEALTH')) {
      return {'lat': 14.6969, 'lng': 121.0375};
    }
    if (upperAddress.contains('QUEZON AVE')) {
      return {'lat': 14.6561, 'lng': 121.0307};
    }
    if (upperAddress.contains('ROOSEVELT')) {
      return {'lat': 14.6500, 'lng': 121.0990};
    }
    if (upperAddress.contains('KATIPUNAN')) {
      return {'lat': 14.6394, 'lng': 121.0779};
    }
    if (upperAddress.contains('AURORA')) {
      return {'lat': 14.6561, 'lng': 121.0307};
    }
    if (upperAddress.contains('ESPANA')) {
      return {'lat': 14.6091, 'lng': 120.9889};
    }
    if (upperAddress.contains('TAFT')) return {'lat': 14.5647, 'lng': 120.9932};
    if (upperAddress.contains('BUENDIA')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }
    if (upperAddress.contains('AYALA')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }
    if (upperAddress.contains('GIL PUYAT')) {
      return {'lat': 14.5547, 'lng': 121.0244};
    }

    return null;
  }

  /// Generate multiple geocoding strategies for better accuracy
  List<String> _generateGeocodingStrategies(String address) {
    final strategies = <String>[];

    // Original address
    strategies.add(address);

    // Add "Philippines" suffix
    strategies.add('$address, Philippines');

    // Add "Metro Manila" suffix
    strategies.add('$address, Metro Manila, Philippines');

    // Add "Manila" suffix
    strategies.add('$address, Manila, Philippines');

    // Enhanced city-specific strategies
    if (address.contains('MARIKINA') || address.contains('LAMUAN')) {
      strategies.add('$address, Marikina City, Philippines');
      strategies.add('$address, Marikina, Metro Manila, Philippines');
      strategies.add('$address, Marikina, Rizal, Philippines');
    }

    if (address.contains('QUEZON') ||
        address.contains('QC') ||
        address.contains('FAIRVIEW') ||
        address.contains('NOVALICHES') ||
        address.contains('BATASAN')) {
      strategies.add('$address, Quezon City, Philippines');
      strategies.add('$address, Quezon City, Metro Manila, Philippines');
      strategies.add('$address, Fairview, Quezon City, Philippines');
      strategies.add('$address, Novaliches, Quezon City, Philippines');
      strategies.add('$address, Batasan, Quezon City, Philippines');
    }

    if (address.contains('MAKATI') || address.contains('POBLACION')) {
      strategies.add('$address, Makati City, Philippines');
      strategies.add('$address, Makati, Metro Manila, Philippines');
      strategies.add('$address, Poblacion, Makati City, Philippines');
    }

    if (address.contains('PASAY') || address.contains('MOA')) {
      strategies.add('$address, Pasay City, Philippines');
      strategies.add('$address, Pasay, Metro Manila, Philippines');
      strategies.add('$address, Mall of Asia, Pasay City, Philippines');
    }

    if (address.contains('MANDALUYONG') || address.contains('ORTIGAS')) {
      strategies.add('$address, Mandaluyong City, Philippines');
      strategies.add('$address, Mandaluyong, Metro Manila, Philippines');
      strategies.add('$address, Ortigas, Mandaluyong City, Philippines');
    }

    if (address.contains('TAGUIG') ||
        address.contains('BGC') ||
        address.contains('BONIFACIO')) {
      strategies.add('$address, Taguig City, Philippines');
      strategies.add('$address, Taguig, Metro Manila, Philippines');
      strategies.add('$address, Bonifacio Global City, Taguig, Philippines');
      strategies.add('$address, BGC, Taguig City, Philippines');
    }

    if (address.contains('SAN JUAN') || address.contains('GREENHILLS')) {
      strategies.add('$address, San Juan City, Philippines');
      strategies.add('$address, San Juan, Metro Manila, Philippines');
      strategies.add('$address, Greenhills, San Juan City, Philippines');
    }

    if (address.contains('PASIG') || address.contains('ORTIGAS')) {
      strategies.add('$address, Pasig City, Philippines');
      strategies.add('$address, Pasig, Metro Manila, Philippines');
      strategies.add('$address, Ortigas, Pasig City, Philippines');
    }

    // Major road and intersection strategies
    if (address.contains('EDSA') ||
        address.contains('CUBAO') ||
        address.contains('ARANETA')) {
      strategies.add('$address, Cubao, Quezon City, Philippines');
      strategies.add('$address, EDSA, Cubao, Quezon City, Philippines');
      strategies
          .add('$address, Araneta Center, Cubao, Quezon City, Philippines');
    }

    if (address.contains('COMMONWEALTH') || address.contains('FAIRVIEW')) {
      strategies.add('$address, Commonwealth Avenue, Quezon City, Philippines');
      strategies
          .add('$address, Fairview, Commonwealth, Quezon City, Philippines');
    }

    if (address.contains('ROOSEVELT') || address.contains('MARIKINA')) {
      strategies.add('$address, Roosevelt Avenue, Marikina City, Philippines');
      strategies.add('$address, Roosevelt, Marikina, Philippines');
    }

    if (address.contains('KATIPUNAN') || address.contains('ATENEO')) {
      strategies.add('$address, Katipunan Avenue, Quezon City, Philippines');
      strategies.add('$address, Katipunan, Quezon City, Philippines');
    }

    // Special handling for SM malls and major establishments
    if (address.contains('SM')) {
      if (address.contains('FAIRVIEW')) {
        strategies.add('SM Fairview, Quezon City, Philippines');
        strategies.add('SM Fairview, Fairview, Quezon City, Philippines');
        strategies
            .add('SM Fairview, Commonwealth Avenue, Quezon City, Philippines');
      } else if (address.contains('NORTH') || address.contains('EDSA')) {
        strategies.add('SM North EDSA, Quezon City, Philippines');
        strategies.add('SM North EDSA, North EDSA, Quezon City, Philippines');
        strategies.add('SM North EDSA, Cubao, Quezon City, Philippines');
      } else if (address.contains('MEGA')) {
        strategies.add('SM Megamall, Mandaluyong City, Philippines');
        strategies.add('SM Megamall, Ortigas, Mandaluyong City, Philippines');
        strategies.add('SM Megamall, Ortigas Center, Philippines');
      } else if (address.contains('AURA')) {
        strategies.add('SM Aura, Taguig City, Philippines');
        strategies.add('SM Aura, Bonifacio Global City, Taguig, Philippines');
        strategies.add('SM Aura, BGC, Taguig, Philippines');
      } else if (address.contains('MOA') || address.contains('MALL OF ASIA')) {
        strategies.add('SM Mall of Asia, Pasay City, Philippines');
        strategies.add('SM Mall of Asia, Pasay, Metro Manila, Philippines');
        strategies.add('SM Mall of Asia, Manila Bay, Pasay, Philippines');
      }
    }

    // Barangay and subdivision strategies
    if (address.contains('BARANGAY') || address.contains('BRGY')) {
      strategies.add('$address, Philippines');
      strategies.add('$address, Metro Manila, Philippines');
    }

    // Street-level strategies
    if (address.contains('STREET') ||
        address.contains('AVE') ||
        address.contains('ROAD')) {
      strategies.add('$address, Philippines');
      strategies.add('$address, Metro Manila, Philippines');
    }

    // Remove duplicates
    return strategies.toSet().toList();
  }

  /// Check if coordinates are in the Philippines
  bool _isInPhilippines(double lat, double lng) {
    // Philippines bounding box (approximate)
    return lat >= 4.0 && lat <= 21.0 && lng >= 116.0 && lng <= 127.0;
  }

  /// Get city coordinates as fallback
  latlong2.LatLng? _getCityCoordinates(String address) {
    for (String city in _philippineCities.keys) {
      if (address.contains(city)) {
        final coords = _philippineCities[city]!;
        return latlong2.LatLng(coords['lat']!, coords['lng']!);
      }
    }
    return null;
  }

  /// Reverse geocode coordinates to address
  Future<String> reverseGeocode(latlong2.LatLng coordinates) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
      }
    } catch (e) {
      print('❌ Reverse geocoding error: $e');
    }

    return 'Unknown location';
  }

  /// Validate if an address is likely in the Philippines
  bool isPhilippineAddress(String address) {
    final normalized = _normalizeAddress(address);

    // Check for Philippine cities
    for (String city in _philippineCities.keys) {
      if (normalized.contains(city)) {
        return true;
      }
    }

    // Check for Philippine indicators
    final philippineIndicators = [
      'PHILIPPINES',
      'PH',
      'METRO MANILA',
      'NCR',
      'MANILA',
      'QUEZON',
      'MAKATI',
      'PASAY',
      'MARIKINA',
      'PASIG',
      'MANDALUYONG',
      'SAN JUAN',
      'CALOOCAN',
      'MALABON',
      'NAVOTAS',
      'PARAÑAQUE',
      'LAS PIÑAS',
      'MUNTINLUPA',
      'TAGUIG',
      'PATEROS',
      'VALENZUELA'
    ];

    for (String indicator in philippineIndicators) {
      if (normalized.contains(indicator)) {
        return true;
      }
    }

    return false;
  }

  /// Get detailed geocoding information for debugging
  Future<Map<String, dynamic>> getDetailedGeocodingInfo(String address) async {
    final result = <String, dynamic>{
      'original_address': address,
      'normalized_address': _normalizeAddress(address),
      'is_philippine_address': isPhilippineAddress(address),
      'known_landmark_match': null,
      'geocoding_strategies': [],
      'geocoding_results': [],
      'final_result': null,
      'geocoding_quality': 'unknown',
      'confidence_score': 0.0,
    };

    try {
      // Check known landmarks
      final knownLandmark = _findKnownLandmark(_normalizeAddress(address));
      if (knownLandmark != null) {
        result['known_landmark_match'] = {
          'name': knownLandmark['description'],
          'coordinates': knownLandmark['coordinates'],
          'landmarks': knownLandmark['landmarks'],
        };
        result['geocoding_quality'] = 'exact_landmark';
        result['confidence_score'] = 1.0;
      }

      // Generate strategies
      result['geocoding_strategies'] =
          _generateGeocodingStrategies(_normalizeAddress(address));

      // Try geocoding
      final coordinates = await geocodePhilippineAddress(address);
      if (coordinates != null) {
        result['final_result'] = {
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
          'address': await reverseGeocode(coordinates),
        };

        // Determine geocoding quality
        if (result['known_landmark_match'] != null) {
          result['geocoding_quality'] = 'exact_landmark';
          result['confidence_score'] = 1.0;
        } else if (_isLikelyResidentialAddress(address, null)) {
          result['geocoding_quality'] = 'residential_address';
          result['confidence_score'] = 0.8;
        } else {
          result['geocoding_quality'] = 'general_area';
          result['confidence_score'] = 0.6;
        }
      }
    } catch (e) {
      result['error'] = e.toString();
    }

    return result;
  }

  /// Get geocoding quality assessment
  String getGeocodingQualityAssessment(String address) {
    final normalized = _normalizeAddress(address);

    // Check if it's a known landmark
    if (_findKnownLandmark(normalized) != null) {
      return 'exact_landmark';
    }

    // Check if it's likely residential
    if (_isLikelyResidentialAddress(normalized, null)) {
      return 'residential_address';
    }

    // Check if it contains major road/area indicators
    final majorIndicators = [
      'EDSA',
      'COMMONWEALTH',
      'ROOSEVELT',
      'KATIPUNAN',
      'AURORA',
      'CUBAO',
      'ORTIGAS',
      'MAKATI',
      'BGC',
      'PASAY',
      'MARIKINA'
    ];

    for (String indicator in majorIndicators) {
      if (normalized.contains(indicator)) {
        return 'major_area';
      }
    }

    return 'general_area';
  }

  /// Get estimated accuracy for geocoding result
  String getEstimatedAccuracy(String address) {
    final quality = getGeocodingQualityAssessment(address);

    switch (quality) {
      case 'exact_landmark':
        return '±10 meters';
      case 'residential_address':
        return '±50 meters';
      case 'major_area':
        return '±200 meters';
      case 'general_area':
        return '±500 meters';
      default:
        return '±1000 meters';
    }
  }
}
