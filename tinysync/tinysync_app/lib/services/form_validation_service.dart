import 'package:flutter/material.dart';

/// Form validation utility service providing common validation methods
/// and consistent form handling patterns
class FormValidationService {
  /// Validates required text fields
  static String? validateRequired(String? value, {String fieldName = 'field'}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter ${fieldName.toLowerCase()}';
    }
    return null;
  }

  /// Validates email format
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter email address';
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validates phone number format
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter phone number';
    }

    // Remove all non-digit characters for validation
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  /// Validates password strength
  static String? validatePassword(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) {
      return 'Please enter password';
    }

    if (value.length < minLength) {
      return 'Password must be at least $minLength characters long';
    }

    return null;
  }

  /// Validates username format
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter username';
    }

    if (value.trim().length < 3) {
      return 'Username must be at least 3 characters long';
    }

    // Check for valid username characters (alphanumeric and underscore)
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(value.trim())) {
      return 'Username can only contain letters, numbers, and underscores';
    }

    return null;
  }

  /// Validates numeric input
  static String? validateNumeric(String? value,
      {String fieldName = 'value', bool allowEmpty = false}) {
    if (allowEmpty && (value == null || value.trim().isEmpty)) {
      return null;
    }

    if (value == null || value.trim().isEmpty) {
      return 'Please enter ${fieldName.toLowerCase()}';
    }

    if (double.tryParse(value.trim()) == null) {
      return 'Please enter a valid number';
    }

    return null;
  }

  /// Validates positive numbers
  static String? validatePositiveNumber(String? value,
      {String fieldName = 'value'}) {
    final numericValidation = validateNumeric(value, fieldName: fieldName);
    if (numericValidation != null) return numericValidation;

    final number = double.parse(value!.trim());
    if (number <= 0) {
      return '${fieldName.substring(0, 1).toUpperCase()}${fieldName.substring(1).toLowerCase()} must be greater than 0';
    }

    return null;
  }

  /// Validates plate number format
  static String? validatePlateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter plate number';
    }

    if (value.trim().length < 6) {
      return 'Plate number must be at least 6 characters long';
    }

    return null;
  }

  /// Common form submission helper that handles loading state and validation
  /// Returns true if form is valid and should proceed
  static bool handleFormSubmission(
      GlobalKey<FormState> formKey, VoidCallback setLoadingState,
      {List<String>? requiredFields,
      List<String?>? fieldValues,
      String errorMessage = 'Please fill all required fields'}) {
    // Validate form
    if (!formKey.currentState!.validate()) {
      return false;
    }

    // Check additional required fields if provided
    if (requiredFields != null && fieldValues != null) {
      if (requiredFields.length != fieldValues.length) {
        throw ArgumentError(
            'requiredFields and fieldValues must have the same length');
      }

      for (int i = 0; i < requiredFields.length; i++) {
        if (fieldValues[i] == null || fieldValues[i]!.trim().isEmpty) {
          // You might want to show an error dialog or snackbar here
          return false;
        }
      }
    }

    // Set loading state
    setLoadingState();
    return true;
  }

  /// Common success/failure handler for async operations
  static Future<void> handleAsyncOperation<T>({
    required Future<T> Function() operation,
    required VoidCallback onSuccess,
    required Function(dynamic error) onError,
    required VoidCallback setLoadingFalse,
  }) async {
    try {
      await operation();
      onSuccess();
    } catch (e) {
      onError(e);
    } finally {
      setLoadingFalse();
    }
  }
}
