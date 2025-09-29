# 🔧 Troubleshooting Guide - TinySync Project

## 🚨 Common Issues & Solutions

### **Flutter App Issues**

#### **App Won't Start**
```bash
# Check Flutter installation
flutter doctor

# Clean and rebuild
flutter clean
flutter pub get
flutter run

# Check for dependency conflicts
flutter pub deps
```

**Common Causes:**
- Missing dependencies
- Corrupted build cache
- Version conflicts
- Configuration errors

#### **IoT Connection Failed**
```dart
// Check connection status
final isConnected = await IoTConnectionService().connectToIoT();
if (!isConnected) {
  // Debug connection issues
  print('❌ IoT connection failed');
  print('Check WiFi Direct connection');
  print('Verify Pi5 is running');
}
```

**Troubleshooting Steps:**
1. Verify WiFi Direct connection to `TinySync_IoT`
2. Check Pi5 device status
3. Test API endpoints manually
4. Review connection logs

#### **Data Sync Issues**
```dart
// Check sync status
final syncStatus = await SupabaseService().checkSyncStatus();
if (syncStatus.hasErrors) {
  // Debug sync issues
  print('❌ Sync failed: ${syncStatus.error}');
  print('Check network connection');
  print('Verify Supabase configuration');
}
```

**Common Solutions:**
- Check internet connection
- Verify Supabase credentials
- Review data validation
- Check timestamp accuracy

#### **Maps Not Loading**
```dart
// Check Google Maps configuration
final mapsService = GoogleMapsService();
if (!mapsService.isConfigured) {
  print('❌ Google Maps not configured');
  print('Check API key in config');
  print('Verify API key permissions');
}
```

**Troubleshooting:**
1. Verify Google Maps API key
2. Check API key permissions
3. Ensure billing is enabled
4. Test API key in browser

### **IoT Device Issues**

#### **Pi5 Not Accessible**
```bash
# Test network connectivity
ping 192.168.254.120

# Check SSH connection
ssh pi5

# Verify service status
ssh pi5 "sudo systemctl status tinysync-*"
```

**Common Solutions:**
- Check network connection
- Verify SSH key permissions
- Restart Pi5 device
- Check service status

#### **Camera Not Working**
```bash
# Check camera devices
ssh pi5 "ls /dev/video*"

# Test camera manually
ssh pi5 "ffmpeg -f v4l2 -i /dev/video0 -t 10 test.mp4"

# Check camera service
ssh pi5 "sudo systemctl status tinysync-universal-camera.service"
```

**Troubleshooting Steps:**
1. Verify camera is connected
2. Check camera permissions
3. Restart camera service
4. Test with different camera

#### **AI Detection Not Working**
```bash
# Check detection AI service
ssh pi5 "sudo systemctl status tinysync-detection-ai.service"

# View service logs
ssh pi5 "sudo journalctl -u tinysync-detection-ai.service -f"

# Check database
ssh pi5 "sqlite3 /home/tinysync/omega/ai/detection/drowsiness_data.db '.tables'"
```

**Common Issues:**
- Camera not detected
- AI model files missing
- Database connection failed
- Service crashed

#### **WiFi Direct Not Working**
```bash
# Check WiFi Direct status
ssh pi5 "sudo systemctl status tinysync-wifi-direct.service"

# Check network interfaces
ssh pi5 "ip addr show"

# Test WiFi Direct
ssh pi5 "iw dev wlan0 info"
```

**Solutions:**
- Restart WiFi Direct service
- Check network configuration
- Verify access point settings
- Test with different device

#### **Sound Not Playing**
```bash
# Check audio devices
ssh pi5 "aplay -l"

# Test sound manually
ssh pi5 "mpg123 /home/tinysync/omega/sounds/start_monitoring.mp3"

# Check volume
ssh pi5 "amixer get Master"
```

**Troubleshooting:**
1. Verify audio device
2. Check volume levels
3. Test sound files
4. Restart audio service

### **Database Issues**

#### **Supabase Connection Failed**
```dart
// Check Supabase connection
try {
  await Supabase.initialize(url: url, anonKey: anonKey);
  print('✅ Supabase connected');
} catch (e) {
  print('❌ Supabase connection failed: $e');
}
```

**Common Causes:**
- Invalid URL or API key
- Network connectivity issues
- Supabase service down
- Authentication problems

#### **Data Not Syncing**
```dart
// Check sync status
final syncStatus = await SupabaseService().getSyncStatus();
if (syncStatus.pendingCount > 0) {
  print('❌ ${syncStatus.pendingCount} items pending sync');
  // Force sync
  await SupabaseService().forceSync();
}
```

**Solutions:**
- Check network connection
- Verify data validation
- Review sync queue
- Check timestamp accuracy

#### **Local Database Issues**
```bash
# Check SQLite database
ssh pi5 "sqlite3 /home/tinysync/omega/ai/detection/drowsiness_data.db '.schema'"

# Check database integrity
ssh pi5 "sqlite3 /home/tinysync/omega/ai/detection/drowsiness_data.db 'PRAGMA integrity_check;'"

# Backup database
ssh pi5 "cp /home/tinysync/omega/ai/detection/drowsiness_data.db /home/tinysync/backup/"
```

### **Network Issues**

#### **WiFi Direct Connection Problems**
```bash
# Check WiFi Direct status
ssh pi5 "sudo systemctl status tinysync-wifi-direct.service"

# Check access point
ssh pi5 "iw dev wlan0 info"

# Test connection
ping 192.168.4.1
```

**Troubleshooting:**
1. Restart WiFi Direct service
2. Check access point configuration
3. Verify network settings
4. Test with different device

#### **API Endpoints Not Responding**
```bash
# Test health endpoint
curl -X GET http://192.168.4.1:8081/api/health

# Test start endpoint
curl -X POST http://192.168.4.1:8081/api/start

# Check service status
ssh pi5 "sudo systemctl status tinysync-detection-ai.service"
```

**Solutions:**
- Restart detection AI service
- Check port availability
- Verify firewall settings
- Test with different client

### **Performance Issues**

#### **App Running Slow**
```dart
// Check memory usage
final memoryInfo = await MemoryInfo.get();
print('Memory usage: ${memoryInfo.totalMemory}');

// Optimize list rendering
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ListTile(
    title: Text(items[index].title),
  ),
)
```

**Optimization Tips:**
- Use ListView.builder for large lists
- Implement proper disposal
- Optimize image loading
- Use const constructors

#### **IoT Device Performance**
```bash
# Check system resources
ssh pi5 "htop"
ssh pi5 "df -h"
ssh pi5 "free -h"

# Check temperature
ssh pi5 "vcgencmd measure_temp"

# Check CPU usage
ssh pi5 "top -bn1 | grep 'Cpu(s)'"
```

**Optimization:**
- Monitor temperature
- Check memory usage
- Optimize camera settings
- Review service performance

### **Data Issues**

#### **Timestamp Accuracy Problems**
```dart
// Validate timestamps
bool isValidTimestamp(String timestamp) {
  try {
    final dateTime = DateTime.parse(timestamp);
    final now = DateTime.now();
    final difference = now.difference(dateTime).inDays;
    return difference >= 0 && difference <= 1; // Within 1 day
  } catch (e) {
    return false;
  }
}
```

**Solutions:**
- Validate timestamp format
- Check time synchronization
- Review data processing
- Verify IoT device time

#### **Data Loss Issues**
```dart
// Check data integrity
final dataIntegrity = await SupabaseService().checkDataIntegrity();
if (dataIntegrity.hasErrors) {
  print('❌ Data integrity issues found');
  // Repair data
  await SupabaseService().repairData();
}
```

**Prevention:**
- Implement data validation
- Use transaction handling
- Regular backups
- Monitor sync status

### **Authentication Issues**

#### **Login Problems**
```dart
// Check authentication
try {
  final user = await Supabase.instance.client.auth.signInWithPassword(
    email: email,
    password: password,
  );
  print('✅ Login successful');
} catch (e) {
  print('❌ Login failed: $e');
}
```

**Troubleshooting:**
- Verify credentials
- Check network connection
- Review authentication flow
- Test with different account

#### **Session Expired**
```dart
// Check session status
final session = Supabase.instance.client.auth.currentSession;
if (session == null) {
  print('❌ No active session');
  // Redirect to login
  Navigator.pushReplacementNamed(context, '/login');
}
```

**Solutions:**
- Implement session refresh
- Handle token expiration
- Auto-logout on expiry
- Store credentials securely

### **Configuration Issues**

#### **Missing Configuration**
```dart
// Check configuration
if (FirebaseConfig.apiKey.isEmpty) {
  print('❌ Firebase API key not configured');
  // Use default or show error
}
```

**Solutions:**
- Verify configuration files
- Check environment variables
- Review setup documentation
- Test with sample data

#### **API Key Issues**
```dart
// Validate API keys
bool isValidApiKey(String apiKey) {
  return apiKey.isNotEmpty && apiKey.length > 10;
}
```

**Troubleshooting:**
- Verify API key format
- Check key permissions
- Test key validity
- Review billing status

## 🔍 Debugging Tools

### **Flutter Debugging**

#### **Debug Console**
```dart
// Use debugPrint for debugging
debugPrint('Debug message: $variable');

// Use assert for development
assert(condition, 'Error message');

// Use breakpoints in IDE
// Set breakpoints in VS Code or Android Studio
```

#### **Logging**
```dart
import 'dart:developer' as developer;

void logMessage(String message, {String? tag}) {
  developer.log(
    message,
    name: tag ?? 'TinySync',
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
sudo systemctl status tinysync-*
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
logger.debug('Debug message')
logger.info('Info message')
logger.error('Error message')
```

### **Network Debugging**

#### **Network Tools**
```bash
# Test connectivity
ping 192.168.4.1
ping 192.168.254.120

# Check ports
nmap -p 8081 192.168.4.1
nmap -p 8080 192.168.4.1

# Test HTTP endpoints
curl -v http://192.168.4.1:8081/api/health
```

#### **WiFi Debugging**
```bash
# Check WiFi status
iwconfig
iw dev wlan0 info

# Check access point
iw dev wlan0 link

# Test WiFi Direct
iw dev wlan0 scan
```

## 📊 Monitoring & Maintenance

### **System Monitoring**

#### **Flutter App Monitoring**
```dart
// Monitor app performance
class PerformanceMonitor {
  static void trackEvent(String event, Map<String, dynamic> properties) {
    // Track custom events
    print('Event: $event, Properties: $properties');
  }
  
  static void trackError(String error, StackTrace stackTrace) {
    // Track errors
    print('Error: $error, Stack: $stackTrace');
  }
}
```

#### **IoT Device Monitoring**
```bash
# Monitor system resources
htop
df -h
free -h

# Monitor services
sudo systemctl status tinysync-*

# Monitor temperature
watch -n 1 vcgencmd measure_temp
```

### **Regular Maintenance**

#### **Database Maintenance**
```sql
-- Clean up old data
DELETE FROM snapshots WHERE created_at < NOW() - INTERVAL '30 days';

-- Optimize database
VACUUM ANALYZE;

-- Check database integrity
PRAGMA integrity_check;
```

#### **Log Rotation**
```bash
# Rotate logs
sudo logrotate /etc/logrotate.conf

# Clean old logs
sudo journalctl --vacuum-time=7d
```

### **Backup Procedures**

#### **Data Backup**
```bash
# Backup IoT database
ssh pi5 "cp /home/tinysync/omega/ai/detection/drowsiness_data.db /home/tinysync/backup/"

# Backup configuration
ssh pi5 "tar -czf /home/tinysync/backup/config.tar.gz /home/tinysync/omega/config/"

# Backup code
ssh pi5 "tar -czf /home/tinysync/backup/code.tar.gz /home/tinysync/omega/ai/"
```

#### **System Backup**
```bash
# Create system image
sudo dd if=/dev/mmcblk0 of=/home/tinysync/backup/system.img bs=4M

# Backup service files
sudo cp /etc/systemd/system/tinysync-*.service /home/tinysync/backup/
```

## 🆘 Emergency Procedures

### **System Recovery**

#### **Complete System Reset**
```bash
# Stop all services
sudo systemctl stop tinysync-*

# Reset configuration
sudo rm -rf /home/tinysync/omega/config/*
sudo cp /home/tinysync/backup/config/* /home/tinysync/omega/config/

# Restart services
sudo systemctl start tinysync-*
```

#### **Data Recovery**
```bash
# Restore database
ssh pi5 "cp /home/tinysync/backup/drowsiness_data.db /home/tinysync/omega/ai/detection/"

# Restore configuration
ssh pi5 "tar -xzf /home/tinysync/backup/config.tar.gz -C /home/tinysync/omega/"
```

### **Emergency Contacts**

#### **Support Resources**
- **GitHub Issues**: https://github.com/quevietap/Softdev/issues
- **Documentation**: `/readme/` folder
- **Logs**: `/progress/` folder
- **Configuration**: `/List/` folder

#### **Critical Files**
- **SSH Access**: `List/passwordless_key.txt`
- **Progress Reports**: `progress/FINAL_SUMMARY.txt`
- **Database Schema**: `supabase.sql`
- **App Configuration**: `tinysync/tinysync_app/pubspec.yaml`

---

**Troubleshooting Status**: Production Ready ✅  
**Last Updated**: December 2024  
**Version**: 1.0.1+5
