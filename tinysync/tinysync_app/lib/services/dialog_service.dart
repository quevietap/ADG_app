import 'package:flutter/material.dart';

/// Dialog utility service providing consistent confirmation dialogs
/// and reducing code duplication across the application
class DialogService {
  /// Show a confirmation dialog for destructive actions
  /// Returns true if user confirms, false or null if cancelled
  static Future<bool?> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Yes',
    String cancelText = 'Cancel',
    Color? confirmColor,
    IconData? icon,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: confirmColor),
              const SizedBox(width: 8),
            ],
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmColor != null
                ? TextButton.styleFrom(foregroundColor: confirmColor)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// Show a deletion confirmation dialog
  static Future<bool?> showDeleteConfirmationDialog(
    BuildContext context, {
    required String itemName,
    String? customMessage,
  }) async {
    return showConfirmationDialog(
      context,
      title: 'Delete $itemName',
      message:
          customMessage ?? 'Are you sure you want to delete this $itemName?',
      confirmText: 'Delete',
      confirmColor: Colors.red,
      icon: Icons.delete_outline,
    );
  }

  /// Show a cancellation confirmation dialog
  static Future<bool?> showCancelConfirmationDialog(
    BuildContext context, {
    required String itemName,
    String? customMessage,
  }) async {
    return showConfirmationDialog(
      context,
      title: 'Cancel $itemName',
      message:
          customMessage ?? 'Are you sure you want to cancel this $itemName?',
      confirmText: 'Yes',
      confirmColor: Colors.orange,
      icon: Icons.cancel_outlined,
    );
  }

  /// Show a restore confirmation dialog
  static Future<bool?> showRestoreConfirmationDialog(
    BuildContext context, {
    required String itemName,
    String? customMessage,
  }) async {
    return showConfirmationDialog(
      context,
      title: 'Restore $itemName',
      message: customMessage ??
          'Are you sure you want to restore this $itemName? It will be moved back to active items.',
      confirmText: 'Restore',
      confirmColor: Colors.green,
      icon: Icons.restore,
    );
  }

  /// Show an information dialog (non-blocking)
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    IconData? icon,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.blue),
              const SizedBox(width: 8),
            ],
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show an error dialog
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) async {
    return showInfoDialog(
      context,
      title: title,
      message: message,
      buttonText: buttonText,
      icon: Icons.error_outline,
    );
  }
}
