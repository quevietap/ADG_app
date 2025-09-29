/// Firebase Configuration
/// This file contains Firebase-related configuration constants
class FirebaseConfig {
  // Replace this with your actual Firebase Server Key
  // You can get this from Firebase Console > Project Settings > Cloud Messaging > Server Key
  static const String serverKey = 'YOUR_FIREBASE_SERVER_KEY_HERE';

  // Firebase project configuration
  static const String fcmSendUrl = 'https://fcm.googleapis.com/fcm/send';

  // Deep linking configuration
  static const String appPackageName =
      'com.tinysync.app'; // Updated to match Firebase registration
  static const String appScheme =
      'tinysync'; // Custom URL scheme for deep linking

  /// Instructions to get Firebase Server Key:
  /// 1. Go to Firebase Console (https://console.firebase.google.com/)
  /// 2. Select your project (tinysync-production)
  /// 3. Go to Project Settings (gear icon)
  /// 4. Click on Cloud Messaging tab
  /// 5. Enable Legacy API if needed (click 3-dot menu next to "Cloud Messaging API (Legacy)")
  /// 6. Copy the Server Key that appears
  /// 7. Replace 'YOUR_FIREBASE_SERVER_KEY_HERE' with the actual key

  /// Instructions for deep linking:
  /// 1. Update appPackageName to match your Android package name
  /// 2. Configure URL schemes in android/app/src/main/AndroidManifest.xml
  /// 3. Configure URL schemes in ios/Runner/Info.plist
}
