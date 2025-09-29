import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

/// Utility service for handling profile images across the application
class ProfileImageService {
  /// Check if a given URL/string is a valid image URL
  static bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http') ||
        url.startsWith('data:image') ||
        url.contains('/'); // Supabase storage path
  }

  /// Build a profile image widget with proper fallback handling
  static Widget buildProfileImage({
    required String? imageUrl,
    required double size,
    Widget? fallbackIcon,
    Color? borderColor,
    double borderWidth = 0,
  }) {
    Widget imageWidget;

    if (isValidImageUrl(imageUrl)) {
      if (imageUrl!.startsWith('data:image')) {
        // Handle base64 images
        try {
          final base64String = imageUrl.split(',')[1];
          final bytes = base64Decode(base64String);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultAvatar(size, fallbackIcon);
            },
          );
        } catch (e) {
          imageWidget = _buildDefaultAvatar(size, fallbackIcon);
        }
      } else {
        // Handle network images
        String finalImageUrl = imageUrl;

        // Convert Supabase Storage paths to public URLs
        if (!imageUrl.startsWith('http')) {
          try {
            finalImageUrl = Supabase.instance.client.storage
                .from('user-profiles')
                .getPublicUrl(imageUrl);
          } catch (e) {
            print('Error building Supabase storage URL: $e');
            finalImageUrl = imageUrl;
          }
        }

        imageWidget = Image.network(
          finalImageUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: size,
              height: size,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: size > 40 ? 3 : 2,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar(size, fallbackIcon);
          },
        );
      }
    } else {
      imageWidget = _buildDefaultAvatar(size, fallbackIcon);
    }

    if (borderWidth > 0) {
      return Container(
        width: size + (borderWidth * 2),
        height: size + (borderWidth * 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor ?? Colors.grey,
            width: borderWidth,
          ),
        ),
        child: ClipOval(child: imageWidget),
      );
    }

    return ClipOval(child: imageWidget);
  }

  /// Build a circular profile image widget (most common use case)
  static Widget buildCircularProfileImage({
    required String? imageUrl,
    required double size,
    Widget? fallbackIcon,
    Color? borderColor,
    double borderWidth = 0,
  }) {
    return Container(
      width: size + (borderWidth * 2),
      height: size + (borderWidth * 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(
                color: borderColor ?? Colors.grey,
                width: borderWidth,
              )
            : null,
      ),
      child: ClipOval(
        child: buildProfileImage(
          imageUrl: imageUrl,
          size: size,
          fallbackIcon: fallbackIcon,
          borderColor: Colors.transparent,
          borderWidth: 0,
        ),
      ),
    );
  }

  /// Build default avatar widget
  static Widget _buildDefaultAvatar(double size, Widget? fallbackIcon) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        shape: BoxShape.circle,
      ),
      child: fallbackIcon ??
          Icon(
            Icons.person_outline,
            size: size * 0.5,
            color: Colors.white54,
          ),
    );
  }

  /// Get a cache-busted URL for profile images to ensure fresh loading
  static String addCacheBuster(String url) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (url.contains('?')) {
      return '$url&cb=$timestamp';
    } else {
      return '$url?cb=$timestamp';
    }
  }

  /// Convert a Supabase storage path to public URL
  static String getSupabaseImageUrl(String storagePath,
      {String bucket = 'user-profiles'}) {
    try {
      return Supabase.instance.client.storage
          .from(bucket)
          .getPublicUrl(storagePath);
    } catch (e) {
      print('Error converting Supabase storage path: $e');
      return storagePath;
    }
  }

  /// Check if user has a profile image
  static bool hasProfileImage(Map<String, dynamic>? user) {
    return user != null && isValidImageUrl(user['profile_image_url']);
  }

  /// Extract filename from storage URL for deletion
  static String? extractFilenameFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      if (url.contains('/')) {
        return url.split('/').last.split('?').first;
      }
      return url;
    } catch (e) {
      return null;
    }
  }
}
