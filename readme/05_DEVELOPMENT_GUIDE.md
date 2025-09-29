# 🛠️ Development Guide - TinySync Project

## 🚀 Getting Started

### **Prerequisites**
- **Flutter SDK**: >=3.2.3 <4.0.0
- **Dart SDK**: Included with Flutter
- **Git**: For version control
- **Android Studio** / **VS Code**: IDE with Flutter extensions
- **Raspberry Pi 5**: For IoT device development
- **Python 3**: For IoT device scripts

### **Development Environment Setup**

#### **1. Clone Repository**
```bash
git clone https://github.com/quevietap/Softdev.git
cd Softdev/tinysync/tinysync_app
```

#### **2. Install Dependencies**
```bash
flutter pub get
```

#### **3. Configure Environment**
```bash
# Copy environment configuration
cp lib/config/firebase_config_example.dart lib/config/firebase_config.dart
cp lib/config/vehicle_status_config_example.dart lib/config/vehicle_status_config.dart

# Edit configuration files with your API keys
```

#### **4. Run Development Server**
```bash
flutter run
```

## 📱 Flutter Development

### **Project Structure**
```
lib/
├── main.dart                 # App entry point
├── config/                   # Configuration files
├── models/                   # Data models
├── pages/                    # UI pages
│   ├── driver/              # Driver interface
│   ├── operator/            # Operator interface
│   └── login_page/          # Authentication
├── services/                 # Business logic
├── widgets/                  # Reusable components
└── test/                     # Unit tests
```

### **Key Development Files**

#### **Main App Entry** (`main.dart`)
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize Supabase
  await Supabase.initialize(url: '...', anonKey: '...');
  
  // Initialize services
  await AppSettingsService().loadSettings();
  await PushNotificationService().initialize();
  
  runApp(const MyApp());
}
```

#### **IoT Connection Service** (`services/iot_connection_service.dart`)
```dart
class IoTConnectionService {
  static const String _iotSSID = 'TinySync_IoT';
  static const String _iotPassword = '12345678';
  static const String _iotIP = '192.168.4.1';
  static const int _iotPort = 8081;
  
  Future<bool> connectToIoT() async {
    if (!await _isConnectedToIoTWiFI()) {
      return false;
    }
    _isConnected = true;
    return true;
  }
}
```

#### **Status Page** (`pages/driver/status_page.dart`)
```dart
class StatusPage extends StatefulWidget {
  // IoT connection management
  // Real-time data processing
  // Manual monitoring controls
  // Data synchronization
}
```

### **Development Commands**

#### **Flutter Commands**
```bash
# Run app in debug mode
flutter run

# Run app in release mode
flutter run --release

# Build APK for Android
flutter build apk --release

# Build for iOS
flutter build ios --release

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
flutter format .

# Clean build
flutter clean
```

#### **Dependency Management**
```bash
# Add new dependency
flutter pub add package_name

# Update dependencies
flutter pub upgrade

# Get dependencies
flutter pub get

# Remove dependency
flutter pub remove package_name
```

### **Code Style & Standards**

#### **Dart Style Guide**
```dart
// Use camelCase for variables and methods
String userName = 'john_doe';
void connectToIoT() {}

// Use PascalCase for classes
class IoTConnectionService {}

// Use UPPER_CASE for constants
static const String IOT_SSID = 'TinySync_IoT';

// Use descriptive names
Future<bool> checkIoTConnectionStatus() {}

// Use proper documentation
/// Connects to the IoT device via WiFi Direct
/// Returns true if connection is successful
Future<bool> connectToIoT() async {}
```

#### **File Organization**
```dart
// Import order
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Class structure
class ExampleService {
  // Static constants
  static const String _apiUrl = 'https://api.example.com';
  
  // Instance variables
  bool _isConnected = false;
  
  // Constructor
  ExampleService();
  
  // Public methods
  Future<bool> connect() async {}
  
  // Private methods
  Future<void> _initialize() async {}
}
```

## 🤖 IoT Device Development

### **Development Environment**

#### **SSH Access**
```bash
# Connect to Pi5
ssh pi5

# Or direct connection
ssh -i "C:\Users\mizor\.ssh\tinysync_key" tinysync@192.168.254.120
```

#### **Development Directory**
```bash
cd /home/tinysync/omega/ai/detection
```

### **Key Development Files**

#### **Main AI Service** (`detection_ai.py`)
```python
class DetectionAI:
    def __init__(self):
        self.camera = None
        self.face_detector = None
        self.landmark_predictor = None
        self.db_connection = None
        
    def start_detection(self):
        """Start AI monitoring and detection"""
        
    def stop_detection(self):
        """Stop AI monitoring and detection"""
        
    def detect_drowsiness(self, frame):
        """Detect driver drowsiness using eye aspect ratio"""
```

#### **Service Management**
```bash
# Check service status
sudo systemctl status tinysync-detection-ai.service

# Start/stop service
sudo systemctl start tinysync-detection-ai.service
sudo systemctl stop tinysync-detection-ai.service

# View logs
sudo journalctl -u tinysync-detection-ai.service -f

# Restart service
sudo systemctl restart tinysync-detection-ai.service
```

### **Python Development**

#### **Dependencies**
```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Common packages
pip3 install opencv-python dlib flask sqlite3 requests
```

#### **Code Style**
```python
# Use snake_case for variables and functions
user_name = 'john_doe'
def connect_to_iot():
    pass

# Use PascalCase for classes
class DetectionAI:
    pass

# Use UPPER_CASE for constants
IOT_IP = '192.168.4.1'
IOT_PORT = 8081

# Use proper documentation
def detect_drowsiness(self, frame):
    """
    Detect driver drowsiness using eye aspect ratio analysis.
    
    Args:
        frame: OpenCV frame from camera
        
    Returns:
        tuple: (is_drowsy, confidence_score)
    """
```

## 🗄️ Database Development

### **Supabase Development**

#### **Local Development**
```bash
# Install Supabase CLI
npm install -g supabase

# Initialize project
supabase init

# Start local development
supabase start

# Generate types
supabase gen types typescript --local > lib/types/supabase.ts
```

#### **Database Migrations**
```sql
-- Create migration file
-- supabase/migrations/20241201000000_create_snapshots_table.sql

CREATE TABLE public.snapshots (
  id bigint NOT NULL DEFAULT nextval('snapshots_id_seq'::regclass),
  filename character varying NOT NULL,
  behavior_type character varying,
  driver_id uuid,
  trip_id uuid,
  timestamp timestamp with time zone DEFAULT now(),
  device_id character varying NOT NULL,
  -- ... other columns
  CONSTRAINT snapshots_pkey PRIMARY KEY (id)
);
```

#### **Real-time Subscriptions**
```dart
// Subscribe to real-time updates
Stream<Map<String, dynamic>> subscribeToSnapshots() {
  return Supabase.instance.client
    .from('snapshots')
    .stream(primaryKey: ['id'])
    .listen((data) {
      // Handle real-time updates
    });
}
```

### **Local SQLite Development**

#### **Database Operations**
```python
import sqlite3

class DatabaseManager:
    def __init__(self, db_path):
        self.db_path = db_path
        self.init_database()
        
    def init_database(self):
        """Initialize database with proper schema"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS behavior_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                behavior_type TEXT NOT NULL,
                confidence_score REAL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                device_id TEXT NOT NULL
            )
        ''')
        
        conn.commit()
        conn.close()
```

## 🔧 Testing

### **Flutter Testing**

#### **Unit Tests**
```dart
// test/services/iot_connection_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tinysync_app/services/iot_connection_service.dart';

void main() {
  group('IoTConnectionService', () {
    late IoTConnectionService service;
    
    setUp(() {
      service = IoTConnectionService();
    });
    
    test('should connect to IoT device', () async {
      // Test implementation
      final result = await service.connectToIoT();
      expect(result, isTrue);
    });
  });
}
```

#### **Widget Tests**
```dart
// test/widgets/status_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinysync_app/pages/driver/status_page.dart';

void main() {
  testWidgets('StatusPage should display IoT connection status', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StatusPage()));
    
    expect(find.text('IoT Connection Status'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsWidgets);
  });
}
```

### **IoT Device Testing**

#### **Python Testing**
```python
# test_detection_ai.py
import unittest
from detection_ai import DetectionAI

class TestDetectionAI(unittest.TestCase):
    def setUp(self):
        self.detection_ai = DetectionAI()
        
    def test_drowsiness_detection(self):
        # Test drowsiness detection
        frame = self.create_test_frame()
        is_drowsy, confidence = self.detection_ai.detect_drowsiness(frame)
        self.assertIsInstance(is_drowsy, bool)
        self.assertIsInstance(confidence, float)
        
    def create_test_frame(self):
        # Create test frame for testing
        pass

if __name__ == '__main__':
    unittest.main()
```

#### **API Testing**
```bash
# Test API endpoints
curl -X GET http://192.168.4.1:8081/api/health
curl -X POST http://192.168.4.1:8081/api/start
curl -X POST http://192.168.4.1:8081/api/stop
```

## 🚀 Deployment

### **Flutter App Deployment**

#### **Android Deployment**
```bash
# Build release APK
flutter build apk --release

# Build app bundle for Play Store
flutter build appbundle --release

# Sign APK
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore my-release-key.keystore app-release-unsigned.apk alias_name
```

#### **iOS Deployment**
```bash
# Build for iOS
flutter build ios --release

# Archive for App Store
flutter build ipa --release
```

### **IoT Device Deployment**

#### **Service Deployment**
```bash
# Copy service files
sudo cp config/*.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable tinysync-detection-ai.service
sudo systemctl enable tinysync-universal-camera.service
sudo systemctl enable tinysync-wifi-direct.service

# Start services
sudo systemctl start tinysync-detection-ai.service
sudo systemctl start tinysync-universal-camera.service
sudo systemctl start tinysync-wifi-direct.service
```

#### **Code Deployment**
```bash
# Copy code to Pi5
scp -r ai/ pi5:/home/tinysync/omega/

# Restart services
ssh pi5 "sudo systemctl restart tinysync-detection-ai.service"
```

## 🔍 Debugging

### **Flutter Debugging**

#### **Debug Tools**
```dart
// Use debugPrint for debugging
debugPrint('IoT connection status: $_isConnected');

// Use assert for development
assert(_isConnected, 'IoT device must be connected');

// Use breakpoints in IDE
// Set breakpoints in VS Code or Android Studio
```

#### **Logging**
```dart
import 'dart:developer' as developer;

void logIoTConnection(String message) {
  developer.log(
    message,
    name: 'IoTConnection',
    level: 800, // INFO level
  );
}
```

### **IoT Device Debugging**

#### **Service Logs**
```bash
# View service logs
sudo journalctl -u tinysync-detection-ai.service -f

# View system logs
sudo journalctl -f

# Check service status
sudo systemctl status tinysync-detection-ai.service
```

#### **Python Debugging**
```python
import logging

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('detection_ai.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# Use logger for debugging
logger.debug('Starting drowsiness detection')
logger.info('IoT device connected successfully')
logger.error('Failed to connect to camera')
```

## 📊 Performance Optimization

### **Flutter Performance**

#### **Memory Management**
```dart
// Dispose controllers properly
@override
void dispose() {
  _controller.dispose();
  _streamSubscription.cancel();
  super.dispose();
}

// Use const constructors
const Text('Static text');

// Use ListView.builder for large lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ListTile(
    title: Text(items[index].title),
  ),
)
```

#### **Network Optimization**
```dart
// Use connection pooling
final httpClient = HttpClient();
httpClient.connectionTimeout = const Duration(seconds: 30);

// Cache responses
final cache = <String, dynamic>{};
if (cache.containsKey(key)) {
  return cache[key];
}
```

### **IoT Device Performance**

#### **Camera Optimization**
```python
# Optimize camera settings
self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
self.camera.set(cv2.CAP_PROP_FPS, 30)

# Use threading for processing
import threading

def process_frame_async(self, frame):
    thread = threading.Thread(target=self._process_frame, args=(frame,))
    thread.start()
```

#### **Database Optimization**
```python
# Use prepared statements
cursor.execute('INSERT INTO behavior_logs (behavior_type, confidence) VALUES (?, ?)', 
               (behavior_type, confidence))

# Use batch operations
cursor.executemany('INSERT INTO snapshots (filename, behavior_type) VALUES (?, ?)', 
                   snapshot_data)
```

## 🔐 Security Best Practices

### **Flutter Security**

#### **API Security**
```dart
// Use HTTPS for all API calls
final uri = Uri.https('api.example.com', '/endpoint');

// Validate input data
if (data['timestamp'] == null || data['timestamp'].isEmpty) {
  throw ArgumentError('Timestamp is required');
}

// Use secure storage for sensitive data
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();
await storage.write(key: 'api_key', value: apiKey);
```

### **IoT Device Security**

#### **Network Security**
```python
# Use HTTPS for API endpoints
from flask import Flask
from flask_sslify import SSLify

app = Flask(__name__)
sslify = SSLify(app)

# Validate input data
def validate_request_data(data):
    required_fields = ['behavior_type', 'confidence', 'timestamp']
    for field in required_fields:
        if field not in data:
            raise ValueError(f'Missing required field: {field}')
```

#### **File System Security**
```bash
# Set proper file permissions
chmod 600 /home/tinysync/.ssh/authorized_keys
chmod 700 /home/tinysync/omega/ai/detection
chmod 644 /home/tinysync/omega/ai/detection/detection_ai.py
```

---

**Development Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
