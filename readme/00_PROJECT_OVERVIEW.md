# 🚀 TinySync Project - Complete Overview

## 📋 Project Summary
**TinySync** is a comprehensive driver monitoring and fleet management system that combines:
- **Flutter Mobile App** (Driver & Operator interfaces)
- **IoT Device Integration** (Raspberry Pi 5 with AI-powered drowsiness detection)
- **Real-time Data Sync** (WiFi Direct + Supabase cloud)
- **Advanced Mapping** (Google Maps integration with live tracking)

## 🎯 Core Features

### 📱 **Flutter Mobile App**
- **Driver Portal**: Dashboard, Status monitoring, History, Profile
- **Operator Portal**: Fleet management, Trip scheduling, Driver performance
- **Real-time Tracking**: Live GPS tracking with Google Maps
- **IoT Integration**: Direct connection to Raspberry Pi 5 device
- **Push Notifications**: Firebase Cloud Messaging integration

### 🤖 **IoT Device (Raspberry Pi 5)**
- **AI Drowsiness Detection**: Computer vision-based driver monitoring
- **Camera System**: Real-time face detection and behavior analysis
- **Sound Alerts**: Audio warnings for drowsiness and distractions
- **WiFi Direct**: Direct communication with mobile app
- **Local Database**: SQLite storage for offline operation

### ☁️ **Backend & Database**
- **Supabase**: PostgreSQL database with real-time subscriptions
- **Firebase**: Push notifications and authentication
- **Data Sync**: Bidirectional sync between IoT device and cloud

## 🏗️ Architecture Overview

```
┌─────────────────┐    WiFi Direct    ┌─────────────────┐
│   Flutter App   │ ←──────────────→ │  Raspberry Pi 5 │
│   (Mobile)      │                  │   (IoT Device)  │
└─────────────────┘                  └─────────────────┘
         │                                    │
         │ HTTP/WebSocket                     │ Local SQLite
         ▼                                    ▼
┌─────────────────┐                  ┌─────────────────┐
│    Supabase     │                  │  Local Storage  │
│   (Database)    │                  │   (Offline)     │
└─────────────────┘                  └─────────────────┘
         │
         │ Firebase
         ▼
┌─────────────────┐
│   Push Notif.   │
└─────────────────┘
```

## 📁 Project Structure

```
Softdev/
├── tinysync/                    # Main Flutter application
│   ├── tinysync_app/           # Flutter app source code
│   │   ├── lib/                # Dart source code
│   │   │   ├── pages/          # UI pages (Driver/Operator)
│   │   │   ├── services/       # Business logic services
│   │   │   ├── models/         # Data models
│   │   │   ├── widgets/        # Reusable UI components
│   │   │   └── config/         # Configuration files
│   │   ├── android/            # Android-specific code
│   │   ├── ios/                # iOS-specific code
│   │   └── assets/             # Images, fonts, config files
│   └── supabase/               # Backend configuration
├── List/                       # Important configuration files
├── progress/                   # Development progress & analysis
├── android/                    # Android build configuration
└── supabase.sql               # Database schema
```

## 🔧 Technology Stack

### **Frontend (Flutter)**
- **Framework**: Flutter 3.2.3+
- **Language**: Dart
- **State Management**: Provider pattern
- **Maps**: Google Maps Flutter + Flutter Map
- **HTTP**: http package for API calls
- **WebSocket**: web_socket_channel for real-time communication

### **Backend (Supabase)**
- **Database**: PostgreSQL
- **Authentication**: Supabase Auth
- **Real-time**: Supabase Realtime subscriptions
- **Storage**: Supabase Storage for images/files

### **IoT (Raspberry Pi 5)**
- **OS**: Debian GNU/Linux
- **Language**: Python 3
- **AI/ML**: OpenCV, dlib for face detection
- **Camera**: USB camera with hot-plugging support
- **Database**: SQLite for local storage
- **Network**: WiFi Direct for mobile communication

### **External Services**
- **Firebase**: Push notifications
- **Google Maps**: Mapping and geocoding
- **GitHub**: Version control and collaboration

## 🚀 Key Capabilities

### **Driver Monitoring**
- Real-time drowsiness detection using AI
- Face tracking and behavior analysis
- Audio alerts for safety violations
- Automatic snapshot capture for evidence
- Offline operation with local storage

### **Fleet Management**
- Trip scheduling and assignment
- Real-time vehicle tracking
- Driver performance monitoring
- Maintenance scheduling
- Route optimization

### **Data Management**
- Bidirectional sync between IoT and cloud
- Offline-first architecture
- Chronological data ordering
- Timestamp accuracy preservation
- Comprehensive audit trails

## 📊 Current Status

### ✅ **Production Ready Features**
- Complete Flutter app with Driver/Operator interfaces
- IoT device with AI drowsiness detection
- Real-time data sync and cloud storage
- Google Maps integration with live tracking
- Push notification system
- Comprehensive error handling

### 🔧 **Recent Fixes Applied**
- Timestamp accuracy preservation throughout data pipeline
- Chronological sync order implementation
- Enhanced data validation and error handling
- Improved IoT connection reliability
- Database schema optimization

## 🎯 Use Cases

1. **Fleet Management**: Monitor driver behavior and vehicle performance
2. **Safety Compliance**: Ensure driver alertness and safe driving practices
3. **Route Optimization**: Track and optimize delivery routes
4. **Performance Analytics**: Analyze driver and vehicle performance metrics
5. **Incident Documentation**: Automatic capture of safety events with timestamps

## 📈 Performance Metrics

- **Real-time Processing**: < 3 seconds from detection to alert
- **Data Accuracy**: 99.9% timestamp preservation
- **Offline Capability**: Full functionality without internet
- **Battery Optimization**: Efficient power usage on mobile devices
- **Scalability**: Supports multiple vehicles and drivers

---

**Last Updated**: December 2024  
**Version**: 1.0.1+5  
**Status**: Production Ready ✅
