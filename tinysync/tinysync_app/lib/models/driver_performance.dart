import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';

part 'driver_performance.g.dart';

@JsonSerializable()
class DriverPerformance {
  final String id;
  final String name;
  final String licenseNumber;
  final String? profileImage;
  final double performanceRating; // 0-5 stars
  final int safetyScore; // 0-100%
  final int behaviorScore; // 0-100%
  final int totalSessions;
  final int totalBehaviors;
  final List<String> recentBehaviors;
  final bool isAvailable;
  final DateTime lastActive;
  final Map<String, int> behaviorCounts;
  final int operatorRating; // 1-5 stars (manual rating)
  final String? operatorNotes;

  DriverPerformance({
    required this.id,
    required this.name,
    required this.licenseNumber,
    this.profileImage,
    required this.performanceRating,
    required this.safetyScore,
    required this.behaviorScore,
    required this.totalSessions,
    required this.totalBehaviors,
    required this.recentBehaviors,
    required this.isAvailable,
    required this.lastActive,
    required this.behaviorCounts,
    required this.operatorRating,
    this.operatorNotes,
  });

  factory DriverPerformance.fromJson(Map<String, dynamic> json) =>
      _$DriverPerformanceFromJson(json);

  Map<String, dynamic> toJson() => _$DriverPerformanceToJson(this);

  // Helper methods
  String get performanceLevel {
    if (performanceRating >= 4.5) return 'Excellent';
    if (performanceRating >= 4.0) return 'Very Good';
    if (performanceRating >= 3.5) return 'Good';
    if (performanceRating >= 3.0) return 'Average';
    return 'Needs Improvement';
  }

  Color get performanceColor {
    if (performanceRating >= 4.0) return Colors.green;
    if (performanceRating >= 3.0) return Colors.orange;
    return Colors.red;
  }

  String get safetyLevel {
    if (safetyScore >= 90) return 'Excellent';
    if (safetyScore >= 80) return 'Good';
    if (safetyScore >= 70) return 'Fair';
    return 'Poor';
  }

  String get behaviorLevel {
    if (behaviorScore >= 90) return 'Excellent';
    if (behaviorScore >= 80) return 'Good';
    if (behaviorScore >= 70) return 'Fair';
    return 'Poor';
  }

  // Calculate performance rating based on monitoring data
  static double calculatePerformanceRating({
    required int safetyScore,
    required int behaviorScore,
    required int operatorRating,
    required int totalSessions,
    required int totalBehaviors,
  }) {
    // Weighted calculation
    double safetyWeight = 0.3;
    double behaviorWeight = 0.3;
    double operatorWeight = 0.2;
    double sessionWeight = 0.1;
    double behaviorWeight2 = 0.1;

    double safetyRating = (safetyScore / 100.0) * 5.0;
    double behaviorRating = (behaviorScore / 100.0) * 5.0;
    double operatorRatingNormalized = operatorRating.toDouble();
    
    // Session quality (more sessions = better, but with diminishing returns)
    double sessionRating = (totalSessions / 50.0).clamp(0.0, 5.0);
    
    // Behavior quality (fewer behaviors = better)
    double behaviorQualityRating = (1.0 - (totalBehaviors / 100.0)).clamp(0.0, 5.0);

    return (safetyRating * safetyWeight) +
           (behaviorRating * behaviorWeight) +
           (operatorRatingNormalized * operatorWeight) +
           (sessionRating * sessionWeight) +
           (behaviorQualityRating * behaviorWeight2);
  }
}
