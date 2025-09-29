import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';

part 'system_log.g.dart';

@JsonSerializable()
class SystemLog {
  final int? id;
  final String deviceId;
  final String logLevel;
  final String message;
  final String? component;
  final Map<String, dynamic>? details;
  final DateTime timestamp;
  final DateTime createdAt;
  final DateTime updatedAt;

  SystemLog({
    this.id,
    required this.deviceId,
    required this.logLevel,
    required this.message,
    this.component,
    this.details,
    required this.timestamp,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SystemLog.fromJson(Map<String, dynamic> json) => 
      _$SystemLogFromJson(json);

  Map<String, dynamic> toJson() => _$SystemLogToJson(this);

  // Log level constants
  static const String debug = 'DEBUG';
  static const String info = 'INFO';
  static const String warning = 'WARNING';
  static const String error = 'ERROR';
  static const String critical = 'CRITICAL';

  // Helper methods
  Color get levelColor {
    switch (logLevel.toUpperCase()) {
      case 'ERROR':
      case 'CRITICAL':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      case 'DEBUG':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  IconData get levelIcon {
    switch (logLevel.toUpperCase()) {
      case 'ERROR':
      case 'CRITICAL':
        return Icons.error;
      case 'WARNING':
        return Icons.warning;
      case 'INFO':
        return Icons.info;
      case 'DEBUG':
        return Icons.bug_report;
      default:
        return Icons.message;
    }
  }

  String get displayLevel {
    switch (logLevel.toUpperCase()) {
      case 'ERROR':
        return 'Error';
      case 'CRITICAL':
        return 'Critical';
      case 'WARNING':
        return 'Warning';
      case 'INFO':
        return 'Info';
      case 'DEBUG':
        return 'Debug';
      default:
        return logLevel;
    }
  }
}
