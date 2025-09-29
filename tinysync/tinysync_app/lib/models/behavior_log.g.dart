// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'behavior_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BehaviorLog _$BehaviorLogFromJson(Map<String, dynamic> json) => BehaviorLog(
      id: (json['id'] as num?)?.toInt(),
      driverId: json['driverId'] as String?,
      behaviorType: json['behaviorType'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      details: json['details'] as Map<String, dynamic>?,
      videoClipUrl: json['videoClipUrl'] as String?,
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
      sessionId: json['sessionId'] as String?,
      deviceId: json['deviceId'] as String?,
      audioAlertTriggered: json['audioAlertTriggered'] as bool? ?? false,
      buzzerSoundPlayed: json['buzzerSoundPlayed'] as bool? ?? false,
      voiceWarningPlayed: json['voiceWarningPlayed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$BehaviorLogToJson(BehaviorLog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'driverId': instance.driverId,
      'behaviorType': instance.behaviorType,
      'confidence': instance.confidence,
      'timestamp': instance.timestamp.toIso8601String(),
      'details': instance.details,
      'videoClipUrl': instance.videoClipUrl,
      'locationLat': instance.locationLat,
      'locationLng': instance.locationLng,
      'sessionId': instance.sessionId,
      'deviceId': instance.deviceId,
      'audioAlertTriggered': instance.audioAlertTriggered,
      'buzzerSoundPlayed': instance.buzzerSoundPlayed,
      'voiceWarningPlayed': instance.voiceWarningPlayed,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
