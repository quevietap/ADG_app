# ⚡ Quick Reference - TinySync Project

## 🚀 Essential Commands

### **Flutter Development**
```bash
# Run app
flutter run

# Build APK
flutter build apk --release

# Clean build
flutter clean && flutter pub get

# Check dependencies
flutter pub deps

# Run tests
flutter test
```

### **IoT Device (Pi5)**
```bash
# Connect to Pi5
ssh pi5

# Check services
ssh pi5 "sudo systemctl status tinysync-*"

# Restart services
ssh pi5 "sudo systemctl restart tinysync-detection-ai.service"

# View logs
ssh pi5 "sudo journalctl -u tinysync-detection-ai.service -f"

# Check system status
ssh pi5 "htop && df -h && free -h"
```

### **Database Operations**
```bash
# Test Supabase connection
curl -X GET "https://hhsaglfvhdlgsbqmcwbw.supabase.co/rest/v1/" \
  -H "apikey: your-anon-key"

# Check local SQLite
ssh pi5 "sqlite3 /home/tinysync/omega/ai/detection/drowsiness_data.db '.tables'"
```

## 📱 App Quick Access

### **Key Pages**
- **Driver Dashboard**: `/driver` - Trip overview and quick actions
- **Status Page**: `/driver` → Status tab - IoT connection and monitoring
- **History Page**: `/driver` → History tab - Trip history and logs
- **Profile Page**: `/driver` → Profile tab - Personal information
- **Operator Dashboard**: `/operator` - Fleet management
- **Settings**: `/settings` - App configuration

### **Critical Features**
- **IoT Connection**: Status Page → "Manual Connect to IoT" button
- **Start Monitoring**: Status Page → "Start Monitoring" button
- **Stop Monitoring**: Status Page → "Stop Monitoring" button
- **View Logs**: Status Page → "View Logs" button
- **Sync Data**: Status Page → "Sync Data" button

## 🤖 IoT Device Quick Access

### **Network Information**
- **WiFi Direct**: `TinySync_IoT` (Password: `12345678`)
- **IP Address**: `192.168.4.1` (WiFi Direct) / `192.168.254.120` (Ethernet)
- **SSH Access**: `ssh pi5` or `ssh -i "C:\Users\mizor\.ssh\tinysync_key" tinysync@192.168.254.120`

### **API Endpoints**
- **Health Check**: `http://192.168.4.1:8081/api/health`
- **Start Monitoring**: `POST http://192.168.4.1:8081/api/start`
- **Stop Monitoring**: `POST http://192.168.4.1:8081/api/stop`
- **Get Snapshots**: `GET http://192.168.4.1:8081/api/snapshots`

### **Service Management**
```bash
# Start all services
ssh pi5 "sudo systemctl start tinysync-*"

# Stop all services
ssh pi5 "sudo systemctl stop tinysync-*"

# Restart all services
ssh pi5 "sudo systemctl restart tinysync-*"

# Check service status
ssh pi5 "sudo systemctl status tinysync-*"
```

## 🗄️ Database Quick Access

### **Supabase Tables**
- **Users**: `public.users` - User accounts (drivers/operators)
- **Trips**: `public.trips` - Trip information and status
- **Vehicles**: `public.vehicles` - Vehicle information
- **Snapshots**: `public.snapshots` - AI detection snapshots and behavior logs
- **Driver Locations**: `public.driver_locations` - Real-time GPS tracking
- **Notifications**: `public.notifications` - In-app notifications

### **Local SQLite Tables**
- **Behavior Logs**: `behavior_logs` - AI detection events
- **Snapshots**: `snapshots` - Captured images and metadata

### **Key Queries**
```sql
-- Get recent snapshots
SELECT * FROM snapshots ORDER BY timestamp DESC LIMIT 10;

-- Get active trips
SELECT * FROM trips WHERE status = 'in_progress';

-- Get driver locations
SELECT * FROM driver_locations WHERE is_active = true;
```

## 🔧 Configuration Files

### **Flutter App**
- **Main Config**: `tinysync/tinysync_app/lib/main.dart`
- **Dependencies**: `tinysync/tinysync_app/pubspec.yaml`
- **Firebase Config**: `tinysync/tinysync_app/lib/config/firebase_config.dart`
- **Supabase Config**: `tinysync/tinysync_app/lib/services/supabase_config.dart`

### **IoT Device**
- **Main AI Service**: `/home/tinysync/omega/ai/detection/detection_ai.py`
- **Service Files**: `/etc/systemd/system/tinysync-*.service`
- **Database**: `/home/tinysync/omega/ai/detection/drowsiness_data.db`
- **Sounds**: `/home/tinysync/omega/sounds/`

### **Database**
- **Schema**: `supabase.sql`
- **Local Schema**: SQLite tables in detection_ai.py

## 🚨 Emergency Procedures

### **App Won't Start**
1. Check Flutter installation: `flutter doctor`
2. Clean and rebuild: `flutter clean && flutter pub get`
3. Check dependencies: `flutter pub deps`
4. Review configuration files

### **IoT Device Not Responding**
1. Test network: `ping 192.168.254.120`
2. Check SSH: `ssh pi5`
3. Check services: `ssh pi5 "sudo systemctl status tinysync-*"`
4. Restart services: `ssh pi5 "sudo systemctl restart tinysync-*"`

### **Data Not Syncing**
1. Check network connection
2. Verify Supabase credentials
3. Check sync status in app
4. Review timestamp accuracy

### **Camera Not Working**
1. Check camera connection: `ssh pi5 "ls /dev/video*"`
2. Test camera: `ssh pi5 "ffmpeg -f v4l2 -i /dev/video0 -t 10 test.mp4"`
3. Restart camera service: `ssh pi5 "sudo systemctl restart tinysync-universal-camera.service"`

## 📊 System Status Check

### **Flutter App Status**
```dart
// Check app status
final appStatus = await AppStatusService().getStatus();
print('App Status: ${appStatus.isHealthy}');
print('IoT Connected: ${appStatus.isIoTConnected}');
print('Sync Status: ${appStatus.syncStatus}');
```

### **IoT Device Status**
```bash
# Quick status check
ssh pi5 "echo '=== SYSTEM STATUS ===' && \
         echo 'Uptime:' && uptime && \
         echo 'Memory:' && free -h && \
         echo 'Disk:' && df -h && \
         echo 'Temperature:' && vcgencmd measure_temp && \
         echo 'Services:' && sudo systemctl status tinysync-* --no-pager"
```

### **Database Status**
```sql
-- Check Supabase connection
SELECT COUNT(*) FROM users;

-- Check local database
SELECT COUNT(*) FROM behavior_logs;
SELECT COUNT(*) FROM snapshots;
```

## 🔍 Debugging Quick Commands

### **Flutter Debugging**
```bash
# Run with debug info
flutter run --verbose

# Check for issues
flutter analyze

# View device logs
flutter logs
```

### **IoT Device Debugging**
```bash
# View service logs
ssh pi5 "sudo journalctl -u tinysync-detection-ai.service -f"

# Check system logs
ssh pi5 "sudo journalctl -f"

# Test API endpoints
curl -X GET http://192.168.4.1:8081/api/health
```

### **Network Debugging**
```bash
# Test connectivity
ping 192.168.4.1
ping 192.168.254.120

# Check ports
nmap -p 8081 192.168.4.1

# Test WiFi Direct
iwconfig
```

## 📱 User Interface Quick Reference

### **Driver Interface**
- **Dashboard**: Trip overview, quick actions, live tracking
- **Status**: IoT connection, monitoring controls, real-time logs
- **History**: Trip history, behavior logs, performance analytics
- **Profile**: Personal information, settings, performance stats

### **Operator Interface**
- **Dashboard**: Fleet overview, active trips, system status
- **Trips**: Trip management, creation, assignment, monitoring
- **Users**: Driver management, performance, assignment
- **Vehicles**: Vehicle management, maintenance, assignment

### **Common Actions**
- **Connect to IoT**: Status Page → "Manual Connect to IoT"
- **Start Monitoring**: Status Page → "Start Monitoring"
- **Stop Monitoring**: Status Page → "Stop Monitoring"
- **View Logs**: Status Page → "View Logs"
- **Sync Data**: Status Page → "Sync Data"

## 🔐 Security Quick Reference

### **Authentication**
- **Login**: Use valid credentials
- **Session**: Auto-refresh enabled
- **Logout**: Available in profile/settings

### **Network Security**
- **WiFi Direct**: Password protected (`12345678`)
- **SSH**: Key-based authentication
- **API**: HTTPS endpoints
- **Database**: Encrypted connections

### **Data Security**
- **Local Storage**: Encrypted sensitive data
- **Transmission**: HTTPS/WSS encryption
- **Backup**: Regular automated backups
- **Access Control**: Role-based permissions

## 📈 Performance Quick Tips

### **Flutter App**
- Use `ListView.builder` for large lists
- Implement proper disposal
- Use `const` constructors
- Optimize image loading

### **IoT Device**
- Monitor temperature regularly
- Check memory usage
- Optimize camera settings
- Review service performance

### **Database**
- Use proper indexes
- Implement data validation
- Regular cleanup of old data
- Monitor query performance

## 🆘 Support Resources

### **Documentation**
- **Project Overview**: `readme/00_PROJECT_OVERVIEW.md`
- **Architecture**: `readme/01_ARCHITECTURE.md`
- **Flutter Guide**: `readme/02_FLUTTER_APP_GUIDE.md`
- **IoT Guide**: `readme/03_IOT_DEVICE_GUIDE.md`
- **Database Schema**: `readme/04_DATABASE_SCHEMA.md`
- **Development Guide**: `readme/05_DEVELOPMENT_GUIDE.md`
- **Troubleshooting**: `readme/06_TROUBLESHOOTING_GUIDE.md`

### **Configuration Files**
- **SSH Access**: `List/passwordless_key.txt`
- **Progress Reports**: `progress/FINAL_SUMMARY.txt`
- **Database Schema**: `supabase.sql`
- **App Config**: `tinysync/tinysync_app/pubspec.yaml`

### **Logs & Debugging**
- **Progress Logs**: `progress/` folder
- **Development Logs**: `List/` folder
- **Service Logs**: `ssh pi5 "sudo journalctl -u tinysync-*"`

---

**Quick Reference Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
