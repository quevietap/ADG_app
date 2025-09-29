import 'package:json_annotation/json_annotation.dart';

part 'video_clip.g.dart';

@JsonSerializable()
class VideoClip {
  final int? id;
  final String? driverId;
  final String fileName;
  final String filePath;
  final String fileUrl;
  final int fileSize;
  final int duration;
  final String? behaviorType;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final String? sessionId;
  final String? deviceId;
  final bool isProcessed;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  VideoClip({
    this.id,
    this.driverId,
    required this.fileName,
    required this.filePath,
    required this.fileUrl,
    required this.fileSize,
    required this.duration,
    this.behaviorType,
    required this.timestamp,
    this.metadata,
    this.sessionId,
    this.deviceId,
    this.isProcessed = false,
    this.thumbnailUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VideoClip.fromJson(Map<String, dynamic> json) => 
      _$VideoClipFromJson(json);

  Map<String, dynamic> toJson() => _$VideoClipToJson(this);

  // Helper methods
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedFileSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String get displayName {
    if (behaviorType != null) {
      switch (behaviorType) {
        case 'drowsiness':
          return 'Drowsiness Detection';
        case 'looking_away':
          return 'Looking Away';
        case 'phone_usage':
          return 'Phone Usage';
        case 'distracted':
          return 'Distracted Driving';
        case 'no_face':
          return 'No Face Detected';
        default:
          return 'Behavior Detection';
      }
    }
    return 'Video Clip';
  }
}
