// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_clip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VideoClip _$VideoClipFromJson(Map<String, dynamic> json) => VideoClip(
      id: (json['id'] as num?)?.toInt(),
      driverId: json['driverId'] as String?,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      fileUrl: json['fileUrl'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      duration: (json['duration'] as num).toInt(),
      behaviorType: json['behaviorType'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      sessionId: json['sessionId'] as String?,
      deviceId: json['deviceId'] as String?,
      isProcessed: json['isProcessed'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$VideoClipToJson(VideoClip instance) => <String, dynamic>{
      'id': instance.id,
      'driverId': instance.driverId,
      'fileName': instance.fileName,
      'filePath': instance.filePath,
      'fileUrl': instance.fileUrl,
      'fileSize': instance.fileSize,
      'duration': instance.duration,
      'behaviorType': instance.behaviorType,
      'timestamp': instance.timestamp.toIso8601String(),
      'metadata': instance.metadata,
      'sessionId': instance.sessionId,
      'deviceId': instance.deviceId,
      'isProcessed': instance.isProcessed,
      'thumbnailUrl': instance.thumbnailUrl,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
