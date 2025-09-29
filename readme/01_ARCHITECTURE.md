# 🏗️ TinySync Architecture Documentation

## 📐 System Architecture Overview

### **High-Level Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                        TinySync Ecosystem                       │
├─────────────────────────────────────────────────────────────────┤
│  Mobile Layer (Flutter)    │  IoT Layer (Pi5)    │  Cloud Layer │
│  ┌─────────────────────┐   │  ┌─────────────────┐ │  ┌─────────┐ │
│  │   Driver App        │   │  │  Detection AI   │ │  │Supabase │ │
│  │   Operator App      │◄──┼──┤  Camera System  │ │  │Database │ │
│  │   Real-time UI      │   │  │  Sound Alerts   │ │  │         │ │
│  └─────────────────────┘   │  └─────────────────┘ │  └─────────┘ │
│           │                │           │          │      │      │
│           │ WiFi Direct    │           │ Local    │      │ HTTP │
│           │ HTTP/WebSocket │           │ SQLite   │      │      │
│           ▼                │           ▼          │      ▼      │
│  ┌─────────────────────┐   │  ┌─────────────────┐ │  ┌─────────┐ │
│  │   Data Processing   │   │  │  Local Storage  │ │  │Firebase │ │
│  │   Sync Management   │   │  │  Offline Queue  │ │  │Push Not.│ │
│  └─────────────────────┘   │  └─────────────────┘ │  └─────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 📱 Flutter App Architecture

### **App Structure**
```
lib/
├── main.dart                 # App entry point & initialization
├── config/                   # Configuration files
│   ├── firebase_config.dart
│   └── vehicle_status_config.dart
├── models/                   # Data models
│   ├── behavior_log.dart     # IoT behavior data
│   ├── driver.dart          # Driver information
│   ├── operator.dart        # Operator information
│   └── system_log.dart      # System events
├── pages/                    # UI Pages
│   ├── driver/              # Driver interface
│   │   ├── dashboard_page.dart
│   │   ├── status_page.dart    # IoT connection & monitoring
│   │   ├── history_page.dart
│   │   └── profile_page.dart
│   ├── operator/            # Operator interface
│   │   ├── operator_screen.dart
│   │   ├── dashboard_page.dart
│   │   ├── trips_page.dart
│   │   ├── users_page.dart
│   │   └── vehicles_page.dart
│   └── login_page/          # Authentication
├── services/                 # Business logic
│   ├── iot_connection_service.dart  # IoT device communication
│   ├── supabase_service.dart        # Database operations
│   ├── location_service.dart        # GPS tracking
│   ├── google_maps_service.dart     # Mapping functionality
│   └── push_notification_service.dart
└── widgets/                  # Reusable components
    ├── live_tracking_map.dart
    ├── iot_connection_status.dart
    └── view_logs_modal.dart
```

### **Key Services Architecture**

#### **IoT Connection Service**
```dart
class IoTConnectionService {
  // WiFi Direct connection management
  Future<bool> connectToIoT()
  Future<bool> _isConnectedToIoTWiFI()
  
  // API communication
  Future<Map<String, dynamic>> sendCommand(String endpoint, Map<String, dynamic> data)
  Future<List<Map<String, dynamic>>> fetchVideoClips()
  
  // Health monitoring
  Future<bool> checkIoTHealth()
}
```

#### **Supabase Service**
```dart
class SupabaseService {
  // Data operations
  Future<void> insertBehaviorLog(BehaviorLog log)
  Future<void> insertSnapshot(Map<String, dynamic> snapshot)
  Future<List<Trip>> getTrips()
  
  // Real-time subscriptions
  Stream<Map<String, dynamic>> subscribeToTrips()
  Stream<Map<String, dynamic>> subscribeToNotifications()
}
```

## 🤖 IoT Device Architecture (Raspberry Pi 5)

### **Service Architecture**
```
/home/tinysync/omega/
├── ai/
│   └── detection/
│       ├── detection_ai.py          # Main AI service
│       ├── drowsiness_data.db       # Local SQLite database
│       └── videos/                  # Captured snapshots
├── config/
│   ├── tinysync-detection-ai.service
│   ├── tinysync-universal-camera.service
│   ├── tinysync-wifi-direct.service
│   └── tinysync-phone-api.service
└── sounds/                          # Audio alert files
    ├── start_monitoring.mp3
    ├── stop_monitoring.mp3
    └── drowsiness_warning.mp3
```

### **Detection AI Service**
```python
class DetectionAI:
    def __init__(self):
        self.camera = None
        self.face_detector = None
        self.landmark_predictor = None
        self.db_connection = None
        
    # Core detection methods
    def start_detection(self)
    def stop_detection(self)
    def detect_drowsiness(self, frame)
    def detect_looking_away(self, frame)
    
    # Data management
    def log_behavior(self, behavior_type, confidence, details)
    def log_snapshot(self, image_data, behavior_type, metadata)
    def send_to_flutter(self, data)
    
    # API endpoints
    def start_monitoring_api()
    def stop_monitoring_api()
    def health_check_api()
```

### **System Services**
- **tinysync-detection-ai.service**: Main AI detection and Flask API
- **tinysync-universal-camera.service**: Camera management and hot-plugging
- **tinysync-wifi-direct.service**: WiFi Direct access point (TinySync_IoT)
- **tinysync-phone-api.service**: Phone communication API
- **tinysync-fan-combined.service**: Temperature management

## ☁️ Database Architecture

### **Supabase Schema**
```sql
-- Core Tables
users                    # User accounts (drivers/operators)
trips                    # Trip information and status
vehicles                 # Vehicle information
driver_sessions          # Driver session tracking

-- Monitoring & Behavior
snapshots               # AI detection snapshots and behavior logs
driver_locations        # Real-time GPS tracking
trip_locations          # Trip-specific location data
session_logs            # Session event logging

-- Notifications & Communication
notifications           # In-app notifications
push_notifications      # Firebase push notifications
notification_logs       # Notification delivery tracking

-- Management & Scheduling
schedules               # Trip scheduling
maintenance_history     # Vehicle maintenance records
driver_ratings          # Driver performance ratings
```

### **Data Flow Architecture**
```
IoT Device → Flutter App → Supabase Database
     │            │              │
     │            │              │
     ▼            ▼              ▼
Local SQLite → Processing → PostgreSQL
     │            │              │
     │            │              │
     ▼            ▼              ▼
Offline Queue → Validation → Real-time Sync
```

## 🔄 Data Flow Architecture

### **Real-time Data Pipeline**
```
1. IoT Detection → 2. Local Storage → 3. WiFi Direct → 4. Flutter Processing
       │                    │                │                │
       ▼                    ▼                ▼                ▼
   AI Analysis         SQLite DB        HTTP POST        Data Validation
       │                    │                │                │
       ▼                    ▼                ▼                ▼
5. Timestamp Preserve → 6. Chronological → 7. Supabase → 8. Real-time UI
       │                    │                │                │
       ▼                    ▼                ▼                ▼
   Original Time        Sort Order        Cloud Storage    Live Updates
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

## 🔐 Security Architecture

### **Authentication Flow**
```
1. User Login → 2. Supabase Auth → 3. JWT Token → 4. API Access
       │              │                │              │
       ▼              ▼                ▼              ▼
   Credentials    User Validation   Secure Token   Authorized Requests
```

### **Data Security**
- **Encryption**: All data encrypted in transit (HTTPS/WSS)
- **Authentication**: JWT tokens for API access
- **Authorization**: Role-based access control (Driver/Operator)
- **Data Privacy**: Local storage with secure sync

## 📊 Performance Architecture

### **Optimization Strategies**
- **Caching**: Local data caching for offline operation
- **Batch Processing**: Efficient data synchronization
- **Real-time Updates**: WebSocket connections for live data
- **Image Compression**: Optimized snapshot storage
- **GPS Optimization**: Efficient location tracking

### **Scalability Considerations**
- **Horizontal Scaling**: Multiple IoT devices per fleet
- **Database Partitioning**: Trip-based data partitioning
- **CDN Integration**: Image and asset delivery
- **Load Balancing**: Multiple Supabase instances

---

**Architecture Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
