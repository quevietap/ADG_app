# 📱 Flutter App - Complete Guide

## 🚀 App Overview

**TinySync Flutter App** is a comprehensive mobile application for driver monitoring and fleet management, featuring dual interfaces for drivers and operators.

### **App Information**
- **Name**: ADG Tiny Sync
- **Version**: 1.0.1+5
- **Flutter SDK**: >=3.2.3 <4.0.0
- **Target Platforms**: Android, iOS, Web, Windows, macOS, Linux

## 📋 Key Features

### **Driver Interface**
- **Dashboard**: Trip overview, status monitoring, quick actions
- **Status Page**: IoT device connection, real-time monitoring, manual controls
- **History**: Trip history, behavior logs, performance analytics
- **Profile**: Personal information, settings, preferences

### **Operator Interface**
- **Dashboard**: Fleet overview, active trips, system status
- **Trip Management**: Create, assign, monitor trips
- **Driver Management**: Driver performance, assignment, scheduling
- **Vehicle Management**: Vehicle status, maintenance, assignment
- **Analytics**: Performance metrics, compliance reports

## 🏗️ App Structure

### **Main Entry Point**
```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (optional)
  await Firebase.initializeApp();
  
  // Initialize Supabase (optional)
  await Supabase.initialize(url: '...', anonKey: '...');
  
  // Initialize services
  await AppSettingsService().loadSettings();
  await PushNotificationService().initialize();
  await NotificationService().initialize();
  
  runApp(const MyApp());
}
```

### **Navigation Structure**
```dart
MaterialApp(
  title: 'ADG Tiny Sync',
  home: const AuthWrapper(),
  routes: {
    '/login': (context) => const LoginPage(),
    '/driver': (context) => DriverScreen(userData: userData),
    '/operator': (context) => OperatorScreen(userData: userData),
    '/settings': (context) => const SettingsPage(),
  },
)
```

## 📱 Driver Interface

### **DriverScreen Structure**
```dart
class DriverScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  
  // Bottom Navigation Tabs:
  // 0: DashboardPage - Trip overview and quick actions
  // 1: StatusPage - IoT connection and monitoring
  // 2: HistoryPage - Trip history and logs
  // 3: ProfilePage - Personal information
}
```

### **Key Driver Pages**

#### **Dashboard Page** (`dashboard_page.dart`)
- **Trip Overview**: Current trip status, progress, details
- **Quick Actions**: Start/stop monitoring, emergency contacts
- **Live Tracking**: Real-time GPS location on map
- **Notifications**: Important alerts and updates

#### **Status Page** (`status_page.dart`) - **CRITICAL**
- **IoT Connection**: Manual connect to Raspberry Pi 5
- **Monitoring Controls**: Start/stop AI detection
- **Real-time Logs**: Live behavior detection events
- **Snapshot Gallery**: Captured images from AI detection
- **Sync Status**: Data synchronization with cloud

**Key Features:**
```dart
// IoT Connection Management
Future<void> _manualConnectToIoT()
Future<void> _startMonitoring()
Future<void> _stopMonitoring()

// Real-time Data Processing
void _addAILog(Map<String, dynamic> message)
void _addSnapshotsLog(Map<String, dynamic> message)
void _addSnapshot(Map<String, dynamic> message)

// Data Synchronization
Future<void> _syncDataChronologically()
Future<void> _validateTimestampAccuracyEnhanced()
```

#### **History Page** (`history_page.dart`)
- **Trip History**: Complete trip records with timestamps
- **Behavior Logs**: AI detection events and snapshots
- **Performance Analytics**: Driver performance metrics
- **Export Options**: Data export for compliance

#### **Profile Page** (`profile_page.dart`)
- **Personal Information**: Driver details and contact info
- **Settings**: App preferences and configurations
- **Performance Stats**: Personal performance metrics
- **Account Management**: Password change, logout

## 👨‍💼 Operator Interface

### **OperatorScreen Structure**
```dart
class OperatorScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  
  // Bottom Navigation Tabs:
  // 0: DashboardPage - Fleet overview
  // 1: TripsPage - Trip management
  // 2: UsersPage - Driver management
  // 3: VehiclesPage - Vehicle management
}
```

### **Key Operator Pages**

#### **Operator Dashboard** (`dashboard_page.dart`)
- **Fleet Overview**: Active trips, driver status, vehicle status
- **Quick Actions**: Create trips, assign drivers, emergency alerts
- **Real-time Monitoring**: Live fleet tracking on map
- **System Status**: IoT device connectivity, sync status

#### **Trips Page** (`trips_page.dart`)
- **Trip Creation**: Create new trips with origin/destination
- **Trip Assignment**: Assign drivers and vehicles to trips
- **Trip Monitoring**: Real-time trip progress tracking
- **Trip History**: Complete trip records and analytics

#### **Users Page** (`users_page.dart`)
- **Driver Management**: Add, edit, remove drivers
- **Performance Monitoring**: Driver performance analytics
- **Assignment History**: Driver trip assignments
- **Compliance Tracking**: Driver behavior compliance

#### **Vehicles Page** (`vehicles_page.dart`)
- **Vehicle Management**: Add, edit, remove vehicles
- **Maintenance Tracking**: Vehicle maintenance schedules
- **Assignment History**: Vehicle trip assignments
- **Status Monitoring**: Vehicle availability and status

## 🔧 Core Services

### **IoT Connection Service** (`iot_connection_service.dart`)
```dart
class IoTConnectionService {
  static const String _iotSSID = 'TinySync_IoT';
  static const String _iotPassword = '12345678';
  static const String _iotIP = '192.168.4.1';
  static const int _iotPort = 8081;
  
  // Connection management
  Future<bool> connectToIoT()
  Future<bool> _isConnectedToIoTWiFI()
  
  // API communication
  Future<Map<String, dynamic>> sendCommand(String endpoint, Map<String, dynamic> data)
  Future<List<Map<String, dynamic>>> fetchVideoClips()
  Future<bool> checkIoTHealth()
}
```

### **Supabase Service** (`supabase_service.dart`)
```dart
class SupabaseService {
  // Data operations
  Future<void> insertBehaviorLog(BehaviorLog log)
  Future<void> insertSnapshot(Map<String, dynamic> snapshot)
  Future<List<Trip>> getTrips()
  Future<List<Driver>> getDrivers()
  Future<List<Vehicle>> getVehicles()
  
  // Real-time subscriptions
  Stream<Map<String, dynamic>> subscribeToTrips()
  Stream<Map<String, dynamic>> subscribeToNotifications()
  Stream<Map<String, dynamic>> subscribeToDriverLocations()
}
```

### **Location Service** (`location_service.dart`)
```dart
class LocationService {
  // GPS tracking
  Future<Position> getCurrentPosition()
  Stream<Position> getPositionStream()
  
  // Geocoding
  Future<List<Placemark>> placemarkFromCoordinates(double lat, double lng)
  Future<List<Location>> locationFromAddress(String address)
  
  // Distance calculation
  double calculateDistance(double lat1, double lng1, double lat2, double lng2)
}
```

### **Google Maps Service** (`google_maps_service.dart`)
```dart
class GoogleMapsService {
  // Map functionality
  Widget buildMapWidget()
  void updateCameraPosition(LatLng position)
  void addMarker(Marker marker)
  void drawRoute(List<LatLng> waypoints)
  
  // Geocoding
  Future<LatLng> geocodeAddress(String address)
  Future<String> reverseGeocode(LatLng position)
}
```

## 🎨 UI Components

### **Custom Widgets**

#### **Live Tracking Map** (`live_tracking_map.dart`)
```dart
class LiveTrackingMap extends StatefulWidget {
  final List<LatLng> route;
  final LatLng currentPosition;
  final bool showTraffic;
  
  // Real-time GPS tracking with Google Maps
  // Route visualization and navigation
  // Traffic information overlay
}
```

#### **IoT Connection Status** (`iot_connection_status.dart`)
```dart
class IoTConnectionStatus extends StatelessWidget {
  // Connection status indicator
  // Manual connect button
  // Connection quality metrics
  // Troubleshooting options
}
```

#### **View Logs Modal** (`view_logs_modal.dart`)
```dart
class ViewLogsModal extends StatefulWidget {
  // Real-time log display
  // Log filtering and search
  // Export functionality
  // Log level indicators
}
```

## 🔄 Data Flow

### **Real-time Data Processing**
```
IoT Device → WiFi Direct → Flutter App → Local Processing → Supabase
     │            │              │              │              │
     ▼            ▼              ▼              ▼              ▼
AI Detection → HTTP POST → Data Validation → Timestamp → Cloud Storage
     │            │              │              │              │
     ▼            ▼              ▼              ▼              ▼
Snapshots → JSON Data → Chronological → Preservation → Real-time UI
```

### **Offline-First Architecture**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   IoT Device    │    │  Flutter App    │    │   Supabase      │
│                 │    │                 │    │                 │
│ Local SQLite    │◄──►│ Local Storage   │◄──►│ PostgreSQL      │
│ Offline Queue   │    │ Sync Queue      │    │ Real-time DB    │
│                 │    │                 │    │                 │
│ Auto-sync when  │    │ Batch upload    │    │ Live queries    │
│ connected       │    │ when online     │    │ & subscriptions │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Build & Deployment

### **Build Configuration**
```yaml
# pubspec.yaml
name: tinysync_app
version: 1.0.1+5
environment:
  sdk: '>=3.2.3 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.3.4
  google_maps_flutter: ^2.5.3
  geolocator: ^10.1.0
  firebase_core: ^2.27.0
  firebase_messaging: ^14.9.4
  # ... other dependencies
```

### **Build Commands**
```bash
# Development build
flutter run

# Release build for Android
flutter build apk --release

# Release build for iOS
flutter build ios --release

# Web build
flutter build web --release
```

### **Platform-Specific Configuration**

#### **Android** (`android/app/build.gradle.kts`)
```kotlin
android {
    compileSdk 34
    defaultConfig {
        applicationId "com.example.tinysync_app"
        minSdk 21
        targetSdk 34
        versionCode 5
        versionName "1.0.1"
    }
}
```

#### **iOS** (`ios/Runner/Info.plist`)
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.1</string>
<key>CFBundleVersion</key>
<string>5</string>
```

## 🔧 Configuration

### **Firebase Configuration**
```dart
// config/firebase_config.dart
class FirebaseConfig {
  static const String projectId = 'your-project-id';
  static const String apiKey = 'your-api-key';
  static const String appId = 'your-app-id';
}
```

### **Supabase Configuration**
```dart
// services/supabase_config.dart
class SupabaseConfig {
  static const String url = 'https://hhsaglfvhdlgsbqmcwbw.supabase.co';
  static const String anonKey = 'your-anon-key';
}
```

### **Google Maps Configuration**
```dart
// services/google_maps_service.dart
class GoogleMapsConfig {
  static const String apiKey = 'your-google-maps-api-key';
}
```

## 📊 Performance Optimization

### **Memory Management**
- Efficient image caching and compression
- Lazy loading of large datasets
- Proper disposal of controllers and streams
- Optimized list rendering with ListView.builder

### **Network Optimization**
- Request batching and caching
- Offline-first data synchronization
- Efficient WebSocket connections
- Image compression for snapshots

### **Battery Optimization**
- Efficient GPS tracking intervals
- Background processing optimization
- Smart notification scheduling
- Power-aware UI updates

---

**App Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
