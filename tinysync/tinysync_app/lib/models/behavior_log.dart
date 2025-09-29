import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';

part 'behavior_log.g.dart';

@JsonSerializable()
class BehaviorLog {
  final int? id;
  final String? driverId;
  final String behaviorType;
  final double confidence;
  final DateTime timestamp;
  final Map<String, dynamic>? details;
  final String? videoClipUrl;
  final double? locationLat;
  final double? locationLng;
  final String? sessionId;
  final String? deviceId;
  final bool audioAlertTriggered;
  final bool buzzerSoundPlayed;
  final bool voiceWarningPlayed;
  final DateTime createdAt;
  final DateTime updatedAt;

  BehaviorLog({
    this.id,
    this.driverId,
    required this.behaviorType,
    required this.confidence,
    required this.timestamp,
    this.details,
    this.videoClipUrl,
    this.locationLat,
    this.locationLng,
    this.sessionId,
    this.deviceId,
    this.audioAlertTriggered = false,
    this.buzzerSoundPlayed = false,
    this.voiceWarningPlayed = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BehaviorLog.fromJson(Map<String, dynamic> json) => 
      _$BehaviorLogFromJson(json);

  Map<String, dynamic> toJson() => _$BehaviorLogToJson(this);

  // Behavior type constants
  static const String drowsiness = 'drowsiness';
  static const String lookingAway = 'looking_away';
  static const String phoneUsage = 'phone_usage';
  static const String distracted = 'distracted';
  static const String noFace = 'no_face';
  static const String eyesClosed = 'eyes_closed';
  static const String headDown = 'head_down';
  static const String yawning = 'yawning';

  // Helper methods
  String get displayName {
    switch (behaviorType) {
      case drowsiness:
        return 'Drowsiness';
      case lookingAway:
        return 'Looking Away';
      case phoneUsage:
        return 'Phone Usage';
      case distracted:
        return 'Distracted';
      case noFace:
        return 'No Face Detected';
      case eyesClosed:
        return 'Eyes Closed';
      case headDown:
        return 'Head Down';
      case yawning:
        return 'Yawning';
      default:
        return behaviorType;
    }
  }

  String get severity {
    switch (behaviorType) {
      case drowsiness:
      case phoneUsage:
        return 'HIGH';
      case lookingAway:
      case distracted:
        return 'MEDIUM';
      case noFace:
      case eyesClosed:
      case headDown:
      case yawning:
        return 'LOW';
      default:
        return 'INFO';
    }
  }

  Color get severityColor {
    switch (severity) {
      case 'HIGH':
        return Colors.red;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
        return Colors.yellow;
      default:
        return Colors.blue;
    }
  }
}
