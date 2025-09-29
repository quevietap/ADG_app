import 'package:flutter/material.dart';

class MapStyleService {
  static final MapStyleService _instance = MapStyleService._internal();
  factory MapStyleService() => _instance;
  MapStyleService._internal();

  // Professional map styles similar to Lalamove and Strava
  static const Map<String, MapStyle> _mapStyles = {
    'streets': MapStyle(
      name: 'Streets',
      description: 'Detailed street view like Lalamove',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      icon: Icons.map,
      color: Colors.blue,
    ),
    'satellite': MapStyle(
      name: 'Satellite',
      description: 'High-resolution satellite imagery',
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      subdomains: null,
      icon: Icons.satellite,
      color: Colors.green,
    ),
    'dark': MapStyle(
      name: 'Dark',
      description: 'Dark theme for night driving',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      icon: Icons.dark_mode,
      color: Colors.grey,
    ),
    'light': MapStyle(
      name: 'Light',
      description: 'Clean light theme like Strava',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      icon: Icons.light_mode,
      color: Colors.orange,
    ),
    'terrain': MapStyle(
      name: 'Terrain',
      description: 'Topographic view with elevation',
      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
      subdomains: null,
      icon: Icons.terrain,
      color: Colors.brown,
    ),
    'traffic': MapStyle(
      name: 'Traffic',
      description: 'Traffic-focused view',
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}{r}.png',
      subdomains: ['a', 'b', 'c', 'd'],
      icon: Icons.traffic,
      color: Colors.red,
    ),
  };

  static const String _defaultStyle = 'streets';

  /// Get all available map styles
  static List<MapStyle> getAllStyles() {
    return _mapStyles.values.toList();
  }

  /// Get a specific map style by name
  static MapStyle? getStyle(String name) {
    return _mapStyles[name];
  }

  /// Get the default map style
  static MapStyle getDefaultStyle() {
    return _mapStyles[_defaultStyle]!;
  }

  /// Get map style names
  static List<String> getStyleNames() {
    return _mapStyles.keys.toList();
  }

  /// Check if a style exists
  static bool hasStyle(String name) {
    return _mapStyles.containsKey(name);
  }
}

class MapStyle {
  final String name;
  final String description;
  final String urlTemplate;
  final List<String>? subdomains;
  final IconData icon;
  final Color color;

  const MapStyle({
    required this.name,
    required this.description,
    required this.urlTemplate,
    this.subdomains,
    required this.icon,
    required this.color,
  });

  @override
  String toString() => name;
}

// Enhanced map configuration for professional appearance
class ProfessionalMapConfig {
  static const double defaultZoom = 15.0;
  static const double maxZoom = 18.0;
  static const double minZoom = 10.0;
  static const String userAgentPackageName = 'com.tinysync.app';
  
  // Professional color scheme for trip paths
  static const Color primaryPathColor = Color(0xFF2196F3); // Blue like Lalamove
  static const Color secondaryPathColor = Color(0xFF4CAF50); // Green like Strava
  static const Color accentPathColor = Color(0xFFFF9800); // Orange for highlights
  
  // Professional marker colors
  static const Color startMarkerColor = Color(0xFF4CAF50); // Green
  static const Color endMarkerColor = Color(0xFFF44336); // Red
  static const Color currentLocationColor = Color(0xFF2196F3); // Blue
  static const Color waypointColor = Color(0xFFFF9800); // Orange
  
  // Professional stroke widths
  static const double primaryPathWidth = 4.0;
  static const double secondaryPathWidth = 3.0;
  static const double accentPathWidth = 2.0;
  
  // Professional marker sizes
  static const double largeMarkerSize = 40.0;
  static const double mediumMarkerSize = 30.0;
  static const double smallMarkerSize = 20.0;
  
  // Professional shadow effects
  static const List<BoxShadow> markerShadow = [
    BoxShadow(
      color: Colors.black26,
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  
  // Professional border radius
  static const double mapBorderRadius = 12.0;
  
  // Professional border
  static const Color mapBorderColor = Color(0xFFE0E0E0);
  static const double mapBorderWidth = 1.0;
}
