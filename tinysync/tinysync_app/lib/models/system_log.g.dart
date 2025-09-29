// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SystemLog _$SystemLogFromJson(Map<String, dynamic> json) => SystemLog(
      id: (json['id'] as num?)?.toInt(),
      deviceId: json['deviceId'] as String,
      logLevel: json['logLevel'] as String,
      message: json['message'] as String,
      component: json['component'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$SystemLogToJson(SystemLog instance) => <String, dynamic>{
      'id': instance.id,
      'deviceId': instance.deviceId,
      'logLevel': instance.logLevel,
      'message': instance.message,
      'component': instance.component,
      'details': instance.details,
      'timestamp': instance.timestamp.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
