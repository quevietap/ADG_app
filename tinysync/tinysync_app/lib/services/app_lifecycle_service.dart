import 'package:flutter/material.dart';
import 'location_service.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  bool _isInitialized = false;

  /// Initialize the app lifecycle service
  void initialize() {
    if (!_isInitialized) {
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;
      print('📱 App lifecycle service initialized');
    }
  }

  /// Dispose the app lifecycle service
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
      _isInitialized = false;
      print('📱 App lifecycle service disposed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App resumed');
        // Re-initialize location service if needed
        _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
        print('📱 App inactive');
        break;
      case AppLifecycleState.paused:
        print('📱 App paused');
        break;
      case AppLifecycleState.detached:
        print('📱 App detached');
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        print('📱 App hidden');
        break;
    }
  }

  /// Handle app resumed state
  void _handleAppResumed() {
    try {
      // Location service will be re-initialized on demand
      print('🔄 App resumed - services will reinitialize as needed');
    } catch (e) {
      print('⚠️ Error handling app resumed: $e');
    }
  }

  /// Handle app detached state
  void _handleAppDetached() {
    try {
      // Safely dispose location service
      LocationService().dispose();
      print('🧹 Location service disposed on app detach');
    } catch (e) {
      print('⚠️ Error disposing services on app detach: $e');
    }
  }
}
