import 'geocoding_provider.dart';

/// Utility class for testing geocoding accuracy
class GeocodingTestUtils {
  static final GeocodingService _geocodingService = GeocodingService();

  /// Test a list of addresses and return results
  static Future<List<GeocodingTestResult>> testAddresses(List<String> addresses) async {
    final results = <GeocodingTestResult>[];
    
    for (final address in addresses) {
      print('🧪 Testing address: "$address"');
      
      final startTime = DateTime.now();
      final result = await _geocodingService.geocode(address);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      results.add(GeocodingTestResult(
        address: address,
        result: result,
        duration: duration,
        timestamp: startTime,
      ));
      
      // Add delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    return results;
  }

  /// Test a single address with detailed output
  static Future<GeocodingTestResult> testSingleAddress(String address) async {
    print('🧪 Testing single address: "$address"');
    
    final startTime = DateTime.now();
    final result = await _geocodingService.geocode(address);
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    
    final testResult = GeocodingTestResult(
      address: address,
      result: result,
      duration: duration,
      timestamp: startTime,
    );
    
    _printTestResult(testResult);
    return testResult;
  }

  /// Print detailed test results
  static void _printTestResult(GeocodingTestResult testResult) {
    print('\n🧪 GEOCODING TEST RESULT:');
    print('   📍 Address: ${testResult.address}');
    print('   ⏱️ Duration: ${testResult.duration.inMilliseconds}ms');
    print('   ✅ Success: ${testResult.result.isSuccess}');
    
    if (testResult.result.isSuccess) {
      print('   📍 Coordinates: ${testResult.result.coordinates!.latitude}, ${testResult.result.coordinates!.longitude}');
      print('   🎯 Accuracy: ${testResult.result.accuracy}');
      print('   📡 Source: ${testResult.result.source}');
      print('   📊 Confidence: ${(testResult.result.confidence * 100).toStringAsFixed(1)}%');
      print('   📝 Description: ${testResult.result.description}');
    } else {
      print('   ❌ Error: ${testResult.result.error}');
      if (testResult.result.suggestions != null && testResult.result.suggestions!.isNotEmpty) {
        print('   💡 Suggestions: ${testResult.result.suggestions!.join(', ')}');
      }
    }
    print('');
  }

  /// Generate test report
  static void generateTestReport(List<GeocodingTestResult> results) {
    print('\n📊 GEOCODING TEST REPORT');
    print('=' * 50);
    
    final totalTests = results.length;
    final successfulTests = results.where((r) => r.result.isSuccess).length;
    final failedTests = totalTests - successfulTests;
    final averageDuration = results.fold<int>(0, (sum, r) => sum + r.duration.inMilliseconds) / totalTests;
    
    print('📈 Summary:');
    print('   Total Tests: $totalTests');
    print('   Successful: $successfulTests (${(successfulTests / totalTests * 100).toStringAsFixed(1)}%)');
    print('   Failed: $failedTests (${(failedTests / totalTests * 100).toStringAsFixed(1)}%)');
    print('   Average Duration: ${averageDuration.toStringAsFixed(0)}ms');
    
    print('\n✅ Successful Tests:');
    for (final result in results.where((r) => r.result.isSuccess)) {
      print('   • ${result.address} → ${result.result.accuracy} (${(result.result.confidence * 100).toStringAsFixed(1)}%)');
    }
    
    if (failedTests > 0) {
      print('\n❌ Failed Tests:');
      for (final result in results.where((r) => r.result.isFailure)) {
        print('   • ${result.address} → ${result.result.error}');
      }
    }
    
    print('\n🎯 Accuracy Breakdown:');
    final accuracyCounts = <String, int>{};
    for (final result in results.where((r) => r.result.isSuccess)) {
      accuracyCounts[result.result.accuracy] = (accuracyCounts[result.result.accuracy] ?? 0) + 1;
    }
    for (final entry in accuracyCounts.entries) {
      print('   • ${entry.key}: ${entry.value} tests');
    }
    
    print('=' * 50);
  }

  /// Test common Philippine addresses
  static Future<List<GeocodingTestResult>> testCommonPhilippineAddresses() async {
    final commonAddresses = [
      'SM Fairview, Quezon City',
      'SM Mall of Asia, Pasay City',
      'SM North EDSA, Quezon City',
      'Trees Residences, Marikina',
      'BDO Marikina Lamuan Branch',
      '123 Quirino Highway, Quezon City',
      'Marikina Lamuan',
      'Quezon City',
      'Makati City',
      'Unknown Address Test',
    ];
    
    return await testAddresses(commonAddresses);
  }
}

/// Result of a geocoding test
class GeocodingTestResult {
  final String address;
  final GeocodingResult result;
  final Duration duration;
  final DateTime timestamp;

  GeocodingTestResult({
    required this.address,
    required this.result,
    required this.duration,
    required this.timestamp,
  });
}
