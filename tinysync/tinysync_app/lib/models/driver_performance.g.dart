// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'driver_performance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DriverPerformance _$DriverPerformanceFromJson(Map<String, dynamic> json) =>
    DriverPerformance(
      id: json['id'] as String,
      name: json['name'] as String,
      licenseNumber: json['licenseNumber'] as String,
      profileImage: json['profileImage'] as String?,
      performanceRating: (json['performanceRating'] as num).toDouble(),
      safetyScore: (json['safetyScore'] as num).toInt(),
      behaviorScore: (json['behaviorScore'] as num).toInt(),
      totalSessions: (json['totalSessions'] as num).toInt(),
      totalBehaviors: (json['totalBehaviors'] as num).toInt(),
      recentBehaviors: (json['recentBehaviors'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      isAvailable: json['isAvailable'] as bool,
      lastActive: DateTime.parse(json['lastActive'] as String),
      behaviorCounts: Map<String, int>.from(json['behaviorCounts'] as Map),
      operatorRating: (json['operatorRating'] as num).toInt(),
      operatorNotes: json['operatorNotes'] as String?,
    );

Map<String, dynamic> _$DriverPerformanceToJson(DriverPerformance instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'licenseNumber': instance.licenseNumber,
      'profileImage': instance.profileImage,
      'performanceRating': instance.performanceRating,
      'safetyScore': instance.safetyScore,
      'behaviorScore': instance.behaviorScore,
      'totalSessions': instance.totalSessions,
      'totalBehaviors': instance.totalBehaviors,
      'recentBehaviors': instance.recentBehaviors,
      'isAvailable': instance.isAvailable,
      'lastActive': instance.lastActive.toIso8601String(),
      'behaviorCounts': instance.behaviorCounts,
      'operatorRating': instance.operatorRating,
      'operatorNotes': instance.operatorNotes,
    };
