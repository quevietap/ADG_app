import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../services/notification_service.dart';

// Shared phone number formatter to avoid duplication
final _sharedPhoneFormatter = MaskTextInputFormatter(
  mask: '+63###-###-####',
  filter: {"#": RegExp(r'[0-9]')},
  initialText: '+63',
);

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _errorMessage;
  TextEditingController displayIdController = TextEditingController();
  bool isLoadingDisplayId = true;
  String? displayIdError;
  String selectedRole = 'driver';
  TextEditingController employeeIdController = TextEditingController();
  TextEditingController roleIdController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isUsernameEditable = false;
  bool isPasswordEditable = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    fetchNextDisplayId();
    fetchNextIds();
    _generateUsernameAndPassword();
  }

  // Optimized fetch users with better caching and error handling
  Future<void> _fetchUsers() async {
    // Prevent multiple simultaneous fetch calls
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Use a more targeted query to reduce data transfer
      // Query both potential image columns to handle legacy data
      final response = await Supabase.instance.client
          .from('users')
          .select(
            'id, first_name, middle_name, last_name, username, role, status, contact_number, driver_license_number, driver_license_expiration_date, driver_license_class, employee_id, driver_id, operator_id, profile_picture, profile_image_url, created_at, updated_at',
          )
          .eq('role', selectedRole)
          .eq('status', 'active')
          .order(
            'created_at',
            ascending: false,
          ); // Order by newest first for better UX

      print('🔍 Fetched users response: ${response.length} users');

      // Process data in batches to avoid UI blocking
      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response).map((user) {
            // Handle both profile_picture and profile_image_url columns
            // Priority: profile_image_url (existing data) -> profile_picture (new data)
            String? finalImageUrl;

            if (user['profile_image_url'] != null &&
                user['profile_image_url'].toString().isNotEmpty &&
                user['profile_image_url'].toString().toLowerCase() != 'null') {
              finalImageUrl = user['profile_image_url'].toString();
            } else if (user['profile_picture'] != null &&
                user['profile_picture'].toString().isNotEmpty &&
                user['profile_picture'].toString().toLowerCase() != 'null') {
              finalImageUrl = user['profile_picture'].toString();
            }

            // Set the standardized field
            user['profile_image_url'] = finalImageUrl;

            return user;
          }).toList();
        });
      }
    } catch (e) {
      print('❌ Error fetching users: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch users: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> fetchNextDisplayId() async {
    setState(() {
      isLoadingDisplayId = true;
      displayIdError = null;
    });
    try {
      final response = await http.get(
        Uri.parse(
          'https://hhsaglfvhdlgsbqmcwbw.functions.supabase.co/next-driver-id',
        ),
      );
      if (response.statusCode == 200) {
        final nextId = jsonDecode(response.body)['nextId'];
        setState(() {
          displayIdController.text = nextId;
          isLoadingDisplayId = false;
        });
      } else {
        setState(() {
          displayIdError = "Failed to load Display ID";
          isLoadingDisplayId = false;
        });
      }
    } catch (e) {
      setState(() {
        displayIdError = "Failed to load Display ID";
        isLoadingDisplayId = false;
      });
    }
  }

  Future<void> fetchNextIds() async {
    // Fetch next employee ID and role ID from backend based on selectedRole
    final response = await http.get(
      Uri.parse(
        'https://hhsaglfvhdlgsbqmcwbw.functions.supabase.co/next-ids?role=$selectedRole',
      ),
      headers: {
        'Authorization':
            'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
        'apikey':
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
      },
    );
    print('next-ids response: ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        employeeIdController.text = data['employee_id'] ?? '';
        print('Fetched employee_id: ${data['employee_id']}');
        passwordController.text = generateStrongPassword(10);
      });
    } else {
      print('Failed to fetch next IDs: ${response.body}');
      setState(() {
        passwordController.text = generateStrongPassword(10);
      });
    }
  }

  String generateAdgUsername(String role, String idNumber) {
    final prefix = role == 'driver' ? 'adgdrv-' : 'adgopr-';
    return '$prefix${idNumber.padLeft(3, '0')}';
  }

  String generateStrongPassword([int length = 10]) {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';
    const specials = '!@#\$%^&*()_+-=';
    final rand = Random.secure();

    String pick(String chars) => chars[rand.nextInt(chars.length)];
    List<String> chars = [
      pick(upper),
      pick(lower),
      pick(digits),
      pick(specials),
    ];
    String all = upper + lower + digits + specials;
    chars.addAll(List.generate(length - 4, (_) => pick(all)));
    chars.shuffle();
    return chars.join();
  }

  void _generateUsernameAndPassword() {
    String id = selectedRole == 'driver'
        ? employeeIdController.text
        : roleIdController.text;
    usernameController.text = id.isNotEmpty
        ? generateAdgUsername(
            selectedRole,
            id.replaceAll(RegExp(r'\D'), ''),
          )
        : '';
    passwordController.text = generateStrongPassword(10);
    isUsernameEditable = false;
    isPasswordEditable = false;
  }

  // Optimized dialog showing with pre-loading
  void _showAddDriverDialog() {
    // Pre-warm the dialog to reduce perceived delay
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal during loading
      builder: (context) => AddDriverDialog(
        onDriverAdded: () {
          // Use a slight delay to allow dialog animation to complete
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _fetchUsers();
          });
        },
      ),
    );
  }

  // Optimized edit dialog with better state management
  void _showEditProfileDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (context) => EditProfileDialog(
        user: user,
        onProfileUpdated: () {
          // Use a slight delay to allow dialog animation to complete
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _fetchUsers();
          });
        },
      ),
    );
  }

  // Optimized role change with debouncing
  void _onRoleChanged(String role) {
    if (selectedRole == role) return; // Prevent unnecessary updates

    setState(() {
      selectedRole = role;
    });

    // Debounce the fetch to prevent rapid successive calls
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && selectedRole == role) {
        _fetchUsers();
        fetchNextIds();
      }
    });
  }

  // Optimized delete confirmation with better UX
  void _showDeleteConfirmation(Map<String, dynamic> user) {
    // Safety check: Don't allow deleting self
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null && currentUser.id == user['id']) {
      NotificationService.showError(
        context,
        'You cannot delete your own account while logged in.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismissal
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.red.withOpacity(0.15),
                Colors.red.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.red.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete User Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you absolutely sure you want to delete this user account?',
              style: TextStyle(
                color: Colors.grey.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            // Enhanced user info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2A2A), Color(0xFF232323)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: user['role'] == 'driver'
                              ? Colors.blue.withOpacity(0.2)
                              : Colors.purple.withOpacity(0.2),
                          border: Border.all(
                            color: user['role'] == 'driver'
                                ? Colors.blue.withOpacity(0.4)
                                : Colors.purple.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          user['role'] == 'driver'
                              ? Icons.local_shipping_rounded
                              : Icons.engineering_rounded,
                          color: user['role'] == 'driver'
                              ? Colors.blue
                              : Colors.purple,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatFullName(user),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${user['role']?.toString().toUpperCase()} • ${user['username'] ?? 'N/A'}',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (user['employee_id'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Employee ID: ${user['employee_id']}',
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Enhanced warning section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.withOpacity(0.1),
                    Colors.red.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.dangerous_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Permanent Action',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This action cannot be undone. The user will be permanently removed from both the database and authentication system.',
                    style: TextStyle(
                      color: Colors.red.withOpacity(0.9),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Enhanced cancel button
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Enhanced delete button
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.red, Color(0xFFD32F2F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _deleteUser(user);
                },
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Text(
                    'Delete User',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    // Show enhanced loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.withOpacity(0.2),
                      Colors.red.withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    strokeWidth: 3,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Deleting User Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait while we process this request...',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'This may take a moment',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final userId = user['id'];
      print('��️ Starting deletion process for user ID: $userId');
      print('🔍 User ID type: ${userId.runtimeType}');
      print('🔍 User ID length: ${userId.toString().length}');
      print('🔍 Raw user data: $user');

      if (userId == null) {
        throw Exception('User ID is required for deletion');
      }

      // Use the helper function to delete the user
      final success = await deleteUser(userId.toString());

      // Close loading dialog
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (success) {
        print('✅ User deletion completed successfully');
        print('🔄 Showing success notification...');

        // Show success notification
        if (mounted) {
          NotificationService.showOperationResult(
            context,
            operation: 'deleted',
            itemType: user['role'] == 'driver' ? 'driver' : 'operator',
            success: true,
          );
        }

        print('🔄 Refreshing user list...');
        // Refresh the user list after a short delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          // Force clear any cache and refresh
          setState(() {
            _users.clear(); // Clear the current list first
          });
          await _fetchUsers();
        }
        print('✅ User deletion flow completed successfully');
      } else {
        throw Exception('Failed to delete user - unexpected response');
      }
    } catch (e) {
      print('❌ Error during user deletion: $e');

      // Close loading dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Determine error message
      String errorMessage = e.toString();
      if (errorMessage.contains('permission denied')) {
        errorMessage =
            'Permission denied. You may not have rights to delete this user.';
      } else if (errorMessage.contains('network') ||
          errorMessage.contains('SocketException')) {
        errorMessage =
            'Network error. Please check your connection and try again.';
      } else if (errorMessage.contains('NOT_FOUND')) {
        errorMessage =
            'User deletion service temporarily unavailable. Using fallback method.';
      } else if (errorMessage.contains('Exception: ')) {
        errorMessage = errorMessage.replaceAll('Exception: ', '');
      }

      // If it's just a service issue but deletion might have worked, give more context
      if (errorMessage.contains('Edge Function failed') ||
          errorMessage.contains('NOT_FOUND')) {
        errorMessage =
            'Deletion completed with fallback method. Please refresh to verify.';
      }

      NotificationService.showOperationResult(
        context,
        operation: 'deleted',
        itemType: user['role'] == 'driver' ? 'driver' : 'operator',
        success: false,
        errorDetails: errorMessage,
      );
    }
  }

  // Helper function to format full name
  String _formatFullName(Map<String, dynamic> user) {
    final firstName = user['first_name'] ?? '';
    final middleName = user['middle_name'] ?? '';
    final lastName = user['last_name'] ?? '';

    String fullName = firstName;
    if (middleName.isNotEmpty) {
      fullName += ' $middleName';
    }
    if (lastName.isNotEmpty) {
      fullName += ' $lastName';
    }

    return fullName.trim().isEmpty ? 'No name' : fullName.trim();
  }

  // Helper function to format license class
  String _formatLicenseClass(String? licenseClass) {
    if (licenseClass == null || licenseClass.isEmpty) {
      return 'N/A';
    }

    // Handle various possible values in the database
    switch (licenseClass.toUpperCase()) {
      case 'PRO':
      case 'PROFESSIONAL':
        return 'Professional';
      case 'NON-PRO':
      case 'NON-PROFESSIONAL':
      case 'NONPROFESSIONAL':
        return 'Non-Professional';
      default:
        // Return the raw value if it doesn't match expected values
        return licenseClass;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Fixed header section that doesn't scroll
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Theme.of(context).primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section with icon, title, and description
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon container
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.people_alt,
                        color: Theme.of(context).primaryColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Title and description section
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'User Management',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Manage your team members and their access permissions',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[300],
                              fontWeight: FontWeight.w400,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Role selection and action buttons section
                Column(
                  children: [
                    // Role selection buttons
                    Row(
                      children: [
                        // Drivers button
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedRole == 'driver'
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedRole == 'driver'
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _onRoleChanged('driver'),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.local_shipping_rounded,
                                        color: selectedRole == 'driver'
                                            ? Colors.white
                                            : Colors.grey[400],
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Drivers',
                                        style: TextStyle(
                                          color: selectedRole == 'driver'
                                              ? Colors.white
                                              : Colors.grey[400],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Operators button
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedRole == 'operator'
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedRole == 'operator'
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _onRoleChanged('operator'),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.engineering_rounded,
                                        color: selectedRole == 'operator'
                                            ? Colors.white
                                            : Colors.grey[400],
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Operators',
                                        style: TextStyle(
                                          color: selectedRole == 'operator'
                                              ? Colors.white
                                              : Colors.grey[400],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Add Driver button (full width)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _showAddDriverDialog,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person_add_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Add ${selectedRole == 'driver' ? 'Driver' : 'Operator'}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Fixed header section for user count (not scrollable)
        if (!_isLoading && _errorMessage == null && _users.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_users.length} ${selectedRole == 'driver' ? 'Drivers' : 'Operators'} Found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.withOpacity(0.9),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_alt,
                        size: 14,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Scrollable content section with dedicated frame (only user cards)
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 20),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  // Content section with better error handling
                  if (_isLoading) _buildModernLoadingState(),
                  if (_errorMessage != null) _buildErrorState(),
                  if (!_isLoading && _errorMessage == null && _users.isNotEmpty)
                    _buildUsersListOnly(),
                  if (!_isLoading && _errorMessage == null && _users.isEmpty)
                    _buildEmptyState(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Modern loading state with skeleton animation
  Widget _buildModernLoadingState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header skeleton
          Container(
            height: 20,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.withOpacity(0.1),
                  Colors.grey.withOpacity(0.2),
                  Colors.grey.withOpacity(0.1),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          // Card skeletons
          ...List.generate(3, (index) => _buildSkeletonCard()),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          // Profile picture skeleton
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Enhanced error state
  Widget _buildErrorState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, size: 48, color: Colors.red),
          ),
          const SizedBox(height: 16),
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.withOpacity(0.8)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchUsers,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Users list only (without header) - for scrollable content
  Widget _buildUsersListOnly() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == _users.length - 1 ? 20 : 0),
          child: _buildModernUserCard(user, index),
        );
      },
    );
  }

  // Optimized modern user card with reduced debug output
  Widget _buildModernUserCard(Map<String, dynamic> user, int index) {
    return AnimatedContainer(
      duration: Duration(
        milliseconds: 150 + (index * 50),
      ), // Reduced animation time
      curve: Curves.easeOutCubic, // Smoother animation curve
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2A2A), Color(0xFF232323)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDriverDetails(user),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Stack(
                children: [
                  // Main content row
                  Row(
                    children: [
                      // Smaller profile image with status indicator
                      Stack(
                        children: [
                          Hero(
                            tag: 'profile_${user['id']}',
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.1),
                                    Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: _buildProfileImageContent(user),
                              ),
                            ),
                          ),
                          // Online status indicator
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: user['status'] == 'active'
                                    ? Colors.green
                                    : Colors.orange,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF2A2A2A),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // User information with clean layout
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name only (role badge moved to top-right)
                            Text(
                              _formatFullName(user),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // ID information - clean text without icon
                            Text(
                              'ID: ${user['operator_id'] != null && user['operator_id'].toString().isNotEmpty ? user['operator_id'] : (user['driver_id'] != null && user['driver_id'].toString().isNotEmpty ? user['driver_id'] : 'N/A')}',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Contact number - clean text without icon
                            Text(
                              '${user['contact_number'] != null && user['contact_number'].toString().isNotEmpty ? user['contact_number'] : 'N/A'}',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Role badge positioned at top-right
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: user['role'] == 'driver'
                              ? [
                                  Colors.blue.withOpacity(0.2),
                                  Colors.blue.withOpacity(0.1),
                                ]
                              : [
                                  Colors.purple.withOpacity(0.2),
                                  Colors.purple.withOpacity(0.1),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: user['role'] == 'driver'
                              ? Colors.blue.withOpacity(0.4)
                              : Colors.purple.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        user['role'] == 'operator' ? 'Opr' : 'Drv',
                        style: TextStyle(
                          color: user['role'] == 'driver'
                              ? Colors.blue
                              : Colors.purple,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  // Action buttons positioned at bottom-right
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildActionButton(
                          icon: Icons.edit_rounded,
                          color: Colors.blue,
                          onTap: () => _showEditProfileDialog(user),
                          tooltip: 'Edit Profile',
                        ),
                        const SizedBox(width: 6),
                        _buildActionButton(
                          icon: Icons.delete_rounded,
                          color: Colors.red,
                          onTap: () => _showDeleteConfirmation(user),
                          tooltip: 'Delete User',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced action button widget
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 14, color: color),
            ),
          ),
        ),
      ),
    );
  }

  // Optimized profile image content builder
  Widget _buildProfileImageContent(Map<String, dynamic> user) {
    final imageUrl = user['profile_image_url'];

    // Check if imageUrl is valid using helper method
    if (_isValidImageUrl(imageUrl)) {
      final provider = _getImageProvider(imageUrl.toString());

      if (provider != null) {
        return ClipOval(
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            width: 56,
            height: 56,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultProfileIcon();
            },
          ),
        );
      }
    }

    return _buildDefaultProfileIcon();
  }

  // Default profile icon with enhanced design
  Widget _buildDefaultProfileIcon() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.withOpacity(0.2), Colors.grey.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: 28,
        color: Colors.grey.withOpacity(0.6),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey.withOpacity(0.05),
            Colors.grey.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Enhanced empty state illustration
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Theme.of(context).primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Icon(
              selectedRole == 'driver'
                  ? Icons.local_shipping_rounded
                  : Icons.engineering_rounded,
              size: 56,
              color: Theme.of(context).primaryColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'No ${selectedRole == 'driver' ? 'Drivers' : 'Operators'} Found',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              'Your team is waiting to be built! Add your first $selectedRole to start managing your fleet operations efficiently.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.withOpacity(0.8),
                height: 1.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Enhanced CTA button
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showAddDriverDialog,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selectedRole == 'driver'
                            ? Icons.local_shipping_rounded
                            : Icons.engineering_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Add First ${selectedRole == 'driver' ? 'Driver' : 'Operator'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Additional helpful tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tip: You can switch between Drivers and Operators using the tabs above',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDriverDetails(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1A1A), Color(0xFF0F0F0F)],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Enhanced drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(24),
                  children: [
                    // Enhanced header section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.15),
                            Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              // Enhanced profile image
                              Hero(
                                tag: 'profile_${user['id']}',
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Theme.of(
                                          context,
                                        ).primaryColor.withOpacity(0.2),
                                        Theme.of(
                                          context,
                                        ).primaryColor.withOpacity(0.1),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.4),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(
                                          context,
                                        ).primaryColor.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _buildProfileImageContent(user),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatFullName(user),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.badge,
                                          size: 14,
                                          color: Colors.grey.withOpacity(
                                            0.7,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ID: ${user['role'] == 'driver' ? (user['driver_id'] ?? 'N/A') : (user['operator_id'] ?? 'N/A')}',
                                          style: TextStyle(
                                            color: Colors.grey.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Small badges in bottom-right corner
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: user['role'] == 'driver'
                                        ? Colors.blue.withOpacity(0.2)
                                        : Colors.purple.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: user['role'] == 'driver'
                                          ? Colors.blue.withOpacity(0.4)
                                          : Colors.purple.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        user['role'] == 'driver'
                                            ? Icons.local_shipping_rounded
                                            : Icons.engineering_rounded,
                                        size: 10,
                                        color: user['role'] == 'driver'
                                            ? Colors.blue
                                            : Colors.purple,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        user['role']
                                                ?.toString()
                                                .toUpperCase() ??
                                            'USER',
                                        style: TextStyle(
                                          color: user['role'] == 'driver'
                                              ? Colors.blue
                                              : Colors.purple,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: user['status'] == 'active'
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: user['status'] == 'active'
                                          ? Colors.green.withOpacity(0.4)
                                          : Colors.orange.withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        user['status'] == 'active'
                                            ? Icons.check_circle
                                            : Icons.warning,
                                        size: 10,
                                        color: user['status'] == 'active'
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        user['status']
                                                ?.toString()
                                                .toUpperCase() ??
                                            'N/A',
                                        style: TextStyle(
                                          color: user['status'] == 'active'
                                              ? Colors.green
                                              : Colors.orange,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildEnhancedInfoSection(
                      'Personal Information',
                      Icons.person,
                      [
                        _buildEnhancedInfoRow(
                          'Full Name',
                          _formatFullName(user),
                          Icons.badge,
                        ),
                        _buildEnhancedInfoRow(
                          'First Name',
                          user['first_name'] ?? '',
                          Icons.person_outline,
                        ),
                        _buildEnhancedInfoRow(
                          'Middle Name',
                          user['middle_name'] ?? 'N/A',
                          Icons.person_outline,
                        ),
                        _buildEnhancedInfoRow(
                          'Last Name',
                          user['last_name'] ?? '',
                          Icons.person_outline,
                        ),
                        _buildEnhancedInfoRow(
                          'Username',
                          user['username'] ?? '',
                          Icons.alternate_email,
                        ),
                        _buildEnhancedInfoRow(
                          'Contact Number',
                          user['contact_number'] ?? 'N/A',
                          Icons.phone,
                        ),
                        _buildEnhancedInfoRow(
                          'Employee ID',
                          user['employee_id'] ?? 'N/A',
                          Icons.work,
                        ),
                      ],
                    ),
                    if (user['role'] == 'driver') ...[
                      const SizedBox(height: 24),
                      _buildEnhancedInfoSection(
                        'License Information',
                        Icons.card_membership,
                        [
                          _buildEnhancedInfoRow(
                            'License Number',
                            user['driver_license_number'] ?? 'N/A',
                            Icons.confirmation_number,
                          ),
                          _buildEnhancedInfoRow(
                            'License Class',
                            _formatLicenseClass(
                              user['driver_license_class'],
                            ),
                            Icons.class_,
                          ),
                          _buildEnhancedInfoRow(
                            'License Expiration',
                            user['driver_license_expiration_date'] ?? 'N/A',
                            Icons.event,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildEnhancedInfoSection(
                      'System Information',
                      Icons.info,
                      [
                        _buildEnhancedInfoRow(
                          'Created',
                          user['created_at'] != null
                              ? DateTime.parse(
                                  user['created_at'],
                                ).toLocal().toString().split('.')[0]
                              : 'N/A',
                          Icons.schedule,
                        ),
                        _buildEnhancedInfoRow(
                          'Last Updated',
                          user['updated_at'] != null
                              ? DateTime.parse(
                                  user['updated_at'],
                                ).toLocal().toString().split('.')[0]
                              : 'N/A',
                          Icons.update,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Enhanced action buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailActionButton(
                            'Edit Profile',
                            Icons.edit_rounded,
                            Colors.blue,
                            () {
                              Navigator.pop(context);
                              _showEditProfileDialog(user);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDetailActionButton(
                            'View History',
                            Icons.history_rounded,
                            Colors.green,
                            () {
                              Navigator.pop(context);
                              // TODO: Navigate to history view
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Enhanced info section with modern design
  Widget _buildEnhancedInfoSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2A), Color(0xFF232323)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  // Enhanced info row with icons and better layout
  Widget _buildEnhancedInfoRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  // Enhanced action button for detail view
  Widget _buildDetailActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to check if an image URL is valid
  bool _isValidImageUrl(dynamic imageUrl) {
    return imageUrl != null &&
        imageUrl.toString().isNotEmpty &&
        imageUrl.toString().toLowerCase() != 'null';
  }

  // Optimized image provider with better caching
  ImageProvider? _getImageProvider(String imageUrl) {
    // Check if the URL is valid (not null, not empty, and not the string "null")
    if (imageUrl.isEmpty || imageUrl.toLowerCase() == 'null') {
      return null;
    }

    if (imageUrl.startsWith('data:image/')) {
      // Base64 image
      try {
        final bytes = base64Decode(imageUrl.split(',')[1]);
        return MemoryImage(bytes);
      } catch (e) {
        print('❌ Base64 decode failed: $e');
        return null;
      }
    } else {
      // Network image with optimized caching
      return NetworkImage(imageUrl);
    }
  }
}

class AddDriverDialog extends StatefulWidget {
  final VoidCallback onDriverAdded;
  const AddDriverDialog({required this.onDriverAdded, super.key});

  @override
  State<AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends State<AddDriverDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _licenseExpirationController = TextEditingController();
  final TextEditingController employeeIdController = TextEditingController();
  final TextEditingController driverIdController = TextEditingController();
  final TextEditingController operatorIdController = TextEditingController();
  bool _isLoading = false;
  String? errorMessage;
  String? _driverId; // Store driver ID from next-ids response
  String? _operatorId; // Store operator ID from next-ids response
  String selectedRole = 'driver';
  final RegExp phMobileRegex = RegExp(r'^(09\d{9}|\+639\d{9})$');
  bool _obscurePassword = true;
  String? _licenseClass; // Pro or Non-Pro

  // Password validation state
  bool _isPasswordValid = false;
  Map<String, bool> _passwordCriteria = {
    'length': false,
    'uppercase': false,
    'lowercase': false,
    'number': false,
    'special': false,
  };
  double _passwordStrength = 0.0;

  @override
  void initState() {
    super.initState();
    fetchNextIds();
    // Initialize password validation state
    _validatePassword('');
    // Don't auto-generate password anymore - user will enter manually
  }

  String generateAdgUsername(String role, String idNumber) {
    final prefix = role == 'driver' ? 'adgdrv-' : 'adgopr-';
    return '$prefix${idNumber.padLeft(3, '0')}';
  }

  // Generate username based on name and employee count
  Future<String> generateUsernameFromName(
    String firstName,
    String lastName,
    String role,
  ) async {
    try {
      // Get total count of users to determine the next number
      final response =
          await Supabase.instance.client.from('users').select('id').count();

      final totalEmployees = response.count + 1; // Add 1 for the new employee

      // Create username from first letter of first name + last name + employee number
      final firstLetter =
          firstName.isNotEmpty ? firstName[0].toLowerCase() : '';
      final cleanLastName = lastName.toLowerCase().replaceAll(
            RegExp(r'[^a-z]'),
            '',
          );
      final rolePrefix = role == 'driver' ? 'drv' : 'opr';

      return '$firstLetter$cleanLastName$rolePrefix${totalEmployees.toString().padLeft(3, '0')}';
    } catch (e) {
      // Fallback to timestamp-based username if database query fails
      final now = DateTime.now().millisecondsSinceEpoch;
      final rolePrefix = role == 'driver' ? 'drv' : 'opr';
      return 'user$rolePrefix$now';
    }
  }

  // Enhanced password validation with real-time feedback
  void _validatePassword(String password) {
    setState(() {
      _passwordCriteria = {
        'length': password.length >= 8,
        'uppercase': RegExp(r'[A-Z]').hasMatch(password),
        'lowercase': RegExp(r'[a-z]').hasMatch(password),
        'number': RegExp(r'[0-9]').hasMatch(password),
        'special': RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password),
      };

      // Check if all criteria are met
      _isPasswordValid = _passwordCriteria.values.every((criteria) => criteria);

      // Calculate password strength (0.0 to 1.0)
      int validCriteria =
          _passwordCriteria.values.where((criteria) => criteria).length;
      _passwordStrength = validCriteria / _passwordCriteria.length;

      // Additional strength factors
      if (password.length >= 12) _passwordStrength += 0.1;
      if (password.length >= 16) _passwordStrength += 0.1;
      if (password.length > 64) {
        _passwordStrength = 0.0; // Invalid if too long
        _isPasswordValid = false;
      }

      // Cap at 1.0
      _passwordStrength = _passwordStrength.clamp(0.0, 1.0);
    });
  }

  // Password validation method for form validator
  String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    if (password.length > 64) {
      return 'Password must not exceed 64 characters';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number';
    }

    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain at least one special character';
    }

    return null; // Password is valid
  }

  String generateStrongPassword([int length = 10]) {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';
    const specials = '!@#\$%^&*()_+-=';
    final rand = Random.secure();

    String pick(String chars) => chars[rand.nextInt(chars.length)];
    List<String> chars = [
      pick(upper),
      pick(lower),
      pick(digits),
      pick(specials),
    ];
    String all = upper + lower + digits + specials;
    chars.addAll(List.generate(length - 4, (_) => pick(all)));
    chars.shuffle();
    return chars.join();
  }

  Future<void> _addDriver() async {
    if (!_formKey.currentState!.validate()) return;

    // Additional check for password validity
    if (!_isPasswordValid) {
      setState(() {
        errorMessage = 'Password does not meet all requirements.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      errorMessage = null;
    });
    try {
      final firstName = _firstNameController.text.trim();
      final middleName = _middleNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      final contactNumber = _contactNumberController.text.trim();
      final licenseNumber = _licenseNumberController.text.trim();
      final licenseExpiration = _licenseExpirationController.text.trim();
      final licenseClass = _licenseClass; // get the selected value

      if (firstName.isEmpty ||
          lastName.isEmpty ||
          username.isEmpty ||
          password.isEmpty) {
        NotificationService.showError(
          context,
          'Required fields cannot be empty!',
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Only require license fields for drivers
      if (selectedRole == 'driver' &&
          (licenseNumber.isEmpty || licenseExpiration.isEmpty)) {
        setState(() {
          errorMessage = 'License Number and Expiry are required for drivers.';
          _isLoading = false;
        });
        return;
      }

      // Only require license class for drivers
      if (selectedRole == 'driver' &&
          (licenseClass == null || licenseClass.isEmpty)) {
        setState(() {
          errorMessage =
              'Please select Professional or Non-Professional license class for drivers.';
          _isLoading = false;
        });
        return;
      }
      if (selectedRole == 'driver' &&
          (licenseClass == null || licenseClass.isEmpty)) {
        setState(() {
          errorMessage =
              'Please select Professional or Non-Professional license class for drivers.';
        });
        return;
      }

      // Call your Edge Function instead of the admin API
      final response = await addDriver(
        firstName,
        middleName,
        lastName,
        username,
        password,
        contactNumber,
        licenseNumber.isEmpty ? null : licenseNumber,
        licenseExpiration.isEmpty ? null : licenseExpiration,
        selectedRole, // Pass selectedRole to the backend
        licenseClass, // Pass license class
        employeeIdController.text, // Pass employee ID
        _driverId, // Pass driver ID from next-ids response
        _operatorId, // Pass operator ID from next-ids response
      );

      if (response == true) {
        Navigator.of(context).pop();
        NotificationService.showOperationResult(
          context,
          operation: 'added',
          itemType:
              selectedRole, // Dynamic based on selected role (driver/operator)
          success: true,
        );
        // Wait a moment for the database to update, then refresh the user list
        await Future.delayed(const Duration(seconds: 1));
        widget.onDriverAdded();
      } else {
        NotificationService.showOperationResult(
          context,
          operation: 'added',
          itemType:
              selectedRole, // Dynamic based on selected role (driver/operator)
          success: false,
        );
      }
    } catch (e) {
      NotificationService.showOperationResult(
        context,
        operation: 'added',
        itemType:
            selectedRole, // Dynamic based on selected role (driver/operator)
        success: false,
        errorDetails: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Auto-generate username when name changes
  void _updateUsernameFromName() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      final newUsername = await generateUsernameFromName(
        firstName,
        lastName,
        selectedRole,
      );
      setState(() {
        _usernameController.text = newUsername;
      });
    }
  }

  // Optimized fetchNextIds with error handling
  Future<void> fetchNextIds() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://hhsaglfvhdlgsbqmcwbw.functions.supabase.co/next-ids?role=$selectedRole',
        ),
        headers: {
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
        },
      ).timeout(const Duration(seconds: 10)); // Add timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            // Format the employee ID properly as EMP-XXX
            final rawEmployeeId = data['employee_id']?.toString() ?? '';
            final formattedEmployeeId = rawEmployeeId.isNotEmpty
                ? 'EMP-${rawEmployeeId.padLeft(3, '0')}'
                : '';
            employeeIdController.text = formattedEmployeeId;

            // Store the IDs for later use when creating driver/operator
            final rawDriverId = data['driver_id']?.toString() ?? '';
            final rawOperatorId = data['operator_id']?.toString() ?? '';

            _driverId = rawDriverId.isNotEmpty
                ? 'DRV-${rawDriverId.padLeft(3, '0')}'
                : null;
            _operatorId = rawOperatorId.isNotEmpty
                ? 'OPR-${rawOperatorId.padLeft(3, '0')}'
                : null;
          });
        }
      } else {
        print('❌ Failed to fetch next IDs: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching next IDs: $e');
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _contactNumberController.dispose();
    _licenseNumberController.dispose();
    _licenseExpirationController.dispose();
    super.dispose();
  }

  // Custom role selection chip
  Widget _buildRoleChip(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ), // Reduced vertical padding for shorter height
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey,
              size: 18, // Increased icon size
            ),
            const SizedBox(width: 6), // Slightly increased spacing
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 12, // Reduced font size for better proportion
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Custom text field builder
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    bool isReadOnly = false,
    bool obscureText = false,
    String? helperText,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    void Function()? onTap,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    Widget? suffixIcon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label + (isRequired ? ' *' : ''),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            readOnly: isReadOnly,
            obscureText: obscureText,
            onChanged: onChanged,
            onTap: onTap,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            decoration: InputDecoration(
              hintText: 'Enter ${label.toLowerCase()}',
              hintStyle: TextStyle(
                color: Colors.grey.withOpacity(0.5),
                fontSize: 12,
              ),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF007AFF),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              suffixIcon: suffixIcon,
              counterText: "", // Always hide counter text
              helperText: null, // Remove helper text to prevent overlap
              errorStyle: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                height: 0.5, // Reduce error text height
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1E1E),
              Color(0xFF0A0A0A),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Enhanced Header with Beautiful Gradient (matching Create New Trip modal)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor.withOpacity(0.2),
                      Theme.of(context).primaryColor.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    // Enhanced Icon with Glow Effect
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Enhanced Title Section
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New User',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Create new driver or operator account',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable Content
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Role selection with enhanced design
                          Container(
                            padding: const EdgeInsets.all(
                                1), // Further reduced padding
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildRoleChip(
                                    'Driver',
                                    Icons.local_shipping_rounded,
                                    selectedRole == 'driver',
                                    () {
                                      setState(() {
                                        selectedRole = 'driver';
                                      });
                                      fetchNextIds();
                                      _updateUsernameFromName();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 1), // Further reduced gap
                                Expanded(
                                  child: _buildRoleChip(
                                    'Operator',
                                    Icons.admin_panel_settings_rounded,
                                    selectedRole == 'operator',
                                    () {
                                      setState(() {
                                        selectedRole = 'operator';
                                      });
                                      fetchNextIds();
                                      _updateUsernameFromName();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Personal Information Section
                          _buildSectionHeader('Personal Information'),
                          const SizedBox(height: 16),

                          // Name fields in a row
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _firstNameController,
                                  label: 'First Name',
                                  icon: Icons.person_outline,
                                  isRequired: true,
                                  onChanged: (_) => _updateUsernameFromName(),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'First name is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _lastNameController,
                                  label: 'Last Name',
                                  icon: Icons.person_outline,
                                  isRequired: true,
                                  onChanged: (_) => _updateUsernameFromName(),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Last name is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),

                          _buildTextField(
                            controller: _middleNameController,
                            label: 'Middle Name (Optional)',
                            icon: Icons.person_outline,
                          ),

                          // Account Information Section
                          _buildSectionHeader('Account Information'),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _usernameController,
                            label: 'Username (Auto-generated)',
                            icon: Icons.account_circle_outlined,
                            isRequired: true,
                            isReadOnly: true,
                            helperText:
                                'Generated from your name and employee count',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Username is required';
                              }
                              return null;
                            },
                          ),

                          _buildTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            isRequired: true,
                            obscureText: _obscurePassword,
                            helperText:
                                'Min 8 chars, max 64 chars, 1 uppercase, 1 lowercase, 1 number, 1 special char',
                            validator: validatePassword,
                            onChanged: (value) => _validatePassword(value),
                            maxLength: 64,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              tooltip: _obscurePassword
                                  ? 'Show Password'
                                  : 'Hide Password',
                            ),
                          ),

                          // Password strength meter and criteria
                          _buildPasswordStrengthMeter(),
                          const SizedBox(height: 8),
                          _buildPasswordCriteria(),

                          // Contact Information Section
                          _buildSectionHeader('Contact Information'),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _contactNumberController,
                            label: 'Contact Number',
                            icon: Icons.phone_outlined,
                            isRequired: true,
                            inputFormatters: [_sharedPhoneFormatter],
                            maxLength: 16,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Contact number is required';
                              }
                              String normalized = value.replaceAll(
                                RegExp(r'[^0-9+]'),
                                '',
                              );
                              if (!RegExp(
                                r'^(09\d{9}|\+639\d{9})$',
                              ).hasMatch(normalized)) {
                                return 'Enter a valid PH mobile number';
                              }
                              return null;
                            },
                          ),

                          // License Information Section (only show for drivers)
                          if (selectedRole == 'driver') ...[
                            _buildSectionHeader('License Information'),
                            const SizedBox(height: 16),

                            // License fields with proper spacing
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _licenseNumberController,
                                        label: 'License Number',
                                        icon: Icons.credit_card_outlined,
                                        isRequired: true,
                                        inputFormatters: [
                                          PhLicenseNumberFormatter()
                                        ],
                                        maxLength: 13,
                                        validator: (value) {
                                          if (selectedRole == 'driver' &&
                                              (value == null ||
                                                  value.isEmpty)) {
                                            return 'License number is required for drivers';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildTextField(
                                        controller:
                                            _licenseExpirationController,
                                        label: 'License Expiry',
                                        icon: Icons.calendar_today_outlined,
                                        isRequired: true,
                                        isReadOnly: true,
                                        validator: (value) {
                                          if (selectedRole == 'driver' &&
                                              (value == null ||
                                                  value.isEmpty)) {
                                            return 'License expiry is required for drivers';
                                          }
                                          return null;
                                        },
                                        onTap: () async {
                                          DateTime? picked =
                                              await showDatePicker(
                                            context: context,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime(1900),
                                            lastDate: DateTime(2100),
                                            builder: (context, child) {
                                              return Theme(
                                                data: ThemeData.dark().copyWith(
                                                  colorScheme:
                                                      const ColorScheme.dark(
                                                    primary: Color(0xFF007AFF),
                                                    surface: Color(0xFF2A2A2A),
                                                  ),
                                                ),
                                                child: child!,
                                              );
                                            },
                                          );
                                          if (picked != null) {
                                            _licenseExpirationController.text =
                                                '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                    height:
                                        20), // Extra spacing after license fields
                              ],
                            ),

                            // License Class Selection
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_outlined,
                                      color: Colors.grey,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'License Class *',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _buildLicenseClassChip(
                                          'Non-Professional',
                                          _licenseClass == 'Non-Pro',
                                          () => setState(
                                              () => _licenseClass = 'Non-Pro'),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: _buildLicenseClassChip(
                                          'Professional',
                                          _licenseClass == 'Pro',
                                          () => setState(
                                              () => _licenseClass = 'Pro'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ],
                        ], // Close the Form Column children array
                      ), // Close Form Column
                    ), // Close Form
                  ), // Close SingleChildScrollView
                ), // Close Expanded
              ),

              // Fixed Action Buttons at Bottom
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Error message (if any)
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(20), // More rounded
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                minimumSize: const Size(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius:
                                  BorderRadius.circular(20), // More rounded
                            ),
                            child: TextButton(
                              onPressed: (_isLoading || !_isPasswordValid)
                                  ? null
                                  : _addDriver,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                minimumSize: const Size(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Add User',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Add small bottom padding
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ], // Close main Column children array
          ), // Close main Column
        ), // Close ClipRRect
      ), // Close Container (Dialog child)
    ); // Close Dialog and return statement
  } // Close build method

  // Section header builder
  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  // License class chip builder
  Widget _buildLicenseClassChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // Password strength meter widget
  Widget _buildPasswordStrengthMeter() {
    if (_passwordController.text.isEmpty) return const SizedBox.shrink();

    Color strengthColor;
    String strengthText;

    if (_passwordStrength < 0.3) {
      strengthColor = Colors.red;
      strengthText = 'Weak';
    } else if (_passwordStrength < 0.7) {
      strengthColor = Colors.orange;
      strengthText = 'Medium';
    } else {
      strengthColor = Colors.green;
      strengthText = 'Strong';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Password Strength:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              strengthText,
              style: TextStyle(
                color: strengthColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: _passwordStrength,
          backgroundColor: Colors.grey.withOpacity(0.3),
          valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
          minHeight: 4,
        ),
      ],
    );
  }

  // Password criteria checklist widget
  Widget _buildPasswordCriteria() {
    if (_passwordController.text.isEmpty) return const SizedBox.shrink();

    final criteria = [
      {'key': 'length', 'text': 'At least 8 characters'},
      {'key': 'uppercase', 'text': 'One uppercase letter'},
      {'key': 'lowercase', 'text': 'One lowercase letter'},
      {'key': 'number', 'text': 'One number'},
      {'key': 'special', 'text': 'One special character'},
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password Requirements:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...criteria.map((criterion) {
            final isValid = _passwordCriteria[criterion['key']] ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    isValid ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: isValid ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    criterion['text']!,
                    style: TextStyle(
                      color: isValid ? Colors.green : Colors.grey,
                      fontSize: 11,
                      fontWeight: isValid ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class EditProfileDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onProfileUpdated;

  const EditProfileDialog({
    required this.user,
    required this.onProfileUpdated,
    super.key,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _middleNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _usernameController;
  late TextEditingController _contactNumberController;
  late TextEditingController _licenseNumberController;
  late TextEditingController _licenseExpirationController;
  bool _isLoading = false;
  String? errorMessage;
  String? _licenseClass;
  String? _status;

  // Profile image related variables
  File? _selectedImage;
  String? _currentImageUrl;
  final bool _isUploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _firstNameController = TextEditingController(
      text: widget.user['first_name'] ?? '',
    );
    _middleNameController = TextEditingController(
      text: widget.user['middle_name'] ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.user['last_name'] ?? '',
    );
    _usernameController = TextEditingController(
      text: widget.user['username'] ?? '',
    );
    _contactNumberController = TextEditingController(
      text: widget.user['contact_number'] ?? '',
    );
    _licenseNumberController = TextEditingController(
      text: widget.user['driver_license_number'] ?? '',
    );
    _licenseExpirationController = TextEditingController(
      text: _formatDateForDisplay(
        widget.user['driver_license_expiration_date'],
      ),
    );
    _licenseClass = widget.user['driver_license_class'];
    _status = widget.user['status'];

    // Handle profile image URL with proper null checking
    final profileImageUrl = widget.user['profile_image_url'];

    // Check for null, empty, or "null" string values
    final isNull = profileImageUrl == null;
    final isEmpty = profileImageUrl?.toString().isEmpty ?? true;
    final isNullString = profileImageUrl?.toString().toLowerCase() == 'null';

    if (isNull || isEmpty || isNullString) {
      _currentImageUrl = null;
    } else {
      _currentImageUrl = profileImageUrl.toString();
    }
  }

  // Helper method to format database date (ISO) to display format (MM/DD/YYYY)
  String _formatDateForDisplay(dynamic dateValue) {
    if (dateValue == null || dateValue.toString().isEmpty) {
      return '';
    }

    try {
      String dateStr = dateValue.toString();
      // If already in MM/DD/YYYY format, return as is
      if (dateStr.contains('/')) {
        return dateStr;
      }

      // Parse ISO date (YYYY-MM-DD) and convert to MM/DD/YYYY
      final parsedDate = DateTime.parse(dateStr);
      return '${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.year}';
    } catch (e) {
      print('⚠️ Error formatting date: $dateValue -> $e');
      return dateValue.toString(); // Return original if parsing fails
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      errorMessage = null;
    });

    try {
      // Verify we have proper authentication context
      print('🔍 Starting profile update for user: ${widget.user['id']}');
      print('🔍 Update being performed by operator session');

      final firstName = _firstNameController.text.trim();
      final middleName = _middleNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final username = _usernameController.text.trim();
      final contactNumber = _contactNumberController.text.trim();
      final licenseNumber = _licenseNumberController.text.trim();
      final licenseExpiration = _licenseExpirationController.text.trim();

      if (firstName.isEmpty || lastName.isEmpty || username.isEmpty) {
        setState(() {
          errorMessage = 'First name, last name, and username are required.';
          _isLoading = false;
        });
        return;
      }

      // Validate driver license requirements if user is a driver
      if (widget.user['role'] == 'driver' &&
          (licenseNumber.isEmpty ||
              licenseExpiration.isEmpty ||
              _licenseClass == null)) {
        setState(() {
          errorMessage = 'License information is required for drivers.';
          _isLoading = false;
        });
        return;
      }

      // Upload image if selected
      String? profileImageUrl;
      if (_selectedImage != null) {
        print('🖼️ Processing selected image...');
        // Skip storage upload due to RLS policies, use base64 directly
        profileImageUrl = await _uploadImageAsBase64();

        if (profileImageUrl == null) {
          setState(() {
            errorMessage = 'Failed to process profile image.';
            _isLoading = false;
          });
          return;
        }
        print('✅ Image processed successfully as base64');
      } else if (_currentImageUrl == null &&
          _isValidImageUrl(widget.user['profile_image_url'])) {
        // Image was removed
        profileImageUrl = null;
        print('🗑️ Profile image removed');
      } else {
        // Keep existing image
        profileImageUrl = _currentImageUrl;
        print('📷 Keeping existing profile image');
      }

      final updateData = {
        'first_name': firstName,
        'middle_name': middleName.isEmpty ? null : middleName,
        'last_name': lastName,
        'username': username,
        'contact_number': contactNumber.isEmpty ? null : contactNumber,
        'status': _status,
        'profile_image_url': profileImageUrl,
      };

      // Add driver-specific fields if user is a driver
      if (widget.user['role'] == 'driver') {
        updateData.addAll({
          'driver_license_number': licenseNumber.isEmpty ? null : licenseNumber,
          'driver_license_expiration_date':
              licenseExpiration.isEmpty ? null : licenseExpiration,
          'driver_license_class': _licenseClass,
        });
      }

      print('🔄 Updating profile with data: $updateData');
      print(
        '🔍 Target user ID: ${widget.user['id']} (type: ${widget.user['id'].runtimeType})',
      );

      // Use RPC function to update profile with elevated privileges
      print('🔄 Performing profile update using RPC function...');

      final result = await Supabase.instance.client.rpc(
        'update_user_profile',
        params: {
          'p_user_id': widget.user['id'],
          'p_first_name': firstName,
          'p_middle_name': middleName.isEmpty ? null : middleName,
          'p_last_name': lastName,
          'p_username': username,
          'p_contact_number': contactNumber.isEmpty ? null : contactNumber,
          'p_status': _status,
          'p_profile_image_url': profileImageUrl,
          // Add driver-specific fields only if user is a driver
          if (widget.user['role'] == 'driver') ...{
            'p_driver_license_number':
                licenseNumber.isEmpty ? null : licenseNumber,
            'p_driver_license_expiration_date':
                licenseExpiration.isEmpty ? null : licenseExpiration,
            'p_driver_license_class': _licenseClass,
          },
        },
      );

      print('🔄 RPC Update result: $result');

      if (result == null || (result is List && result.isEmpty)) {
        throw Exception(
          'Failed to update user profile: No data returned from update function.',
        );
      }

      print('✅ Profile update successful using RPC function!');

      // Extract the first record from the result for verification
      final updatedUser = result is List ? result.first : result;
      print('🔍 Updated user data: $updatedUser');

      // Close dialog immediately
      Navigator.of(context).pop();

      // Show success notification
      NotificationService.showOperationResult(
        context,
        operation: 'updated',
        itemType: 'profile',
        success: true,
      );

      // Add a small delay to ensure database consistency, then refresh
      Future.delayed(const Duration(milliseconds: 500), () {
        widget.onProfileUpdated();
      });
    } catch (e) {
      print('❌ Error updating profile: $e');
      setState(() {
        if (e.toString().contains('Username already exists')) {
          errorMessage =
              'Username already exists. Please choose a different username.';
        } else if (e.toString().contains('User not found with ID')) {
          errorMessage = 'User not found. The profile may have been deleted.';
        } else if (e.toString().contains('Invalid status')) {
          errorMessage = 'Invalid status value provided.';
        } else if (e.toString().contains('Invalid license class')) {
          errorMessage =
              'Invalid license class. Must be Professional or Non-Professional.';
        } else if (e.toString().contains('permission denied') ||
            e.toString().contains('insufficient_privilege')) {
          errorMessage =
              'Permission denied. Please contact your administrator.';
        } else if (e.toString().contains('row-level security policy')) {
          errorMessage =
              'Access denied. Database security policies prevent this update.';
        } else {
          errorMessage =
              'Failed to update profile. Please try again or contact support.';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Method to pick image from gallery or camera
  Future<void> _pickImage() async {
    try {
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Colors.blue,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _selectImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera,
                  color: Colors.green,
                ),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  await _selectImage(ImageSource.camera);
                },
              ),
              if (_isValidImageUrl(_currentImageUrl) || _selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeImage();
                  },
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      NotificationService.showError(context, 'Failed to open image picker: $e');
    }
  }

  // Method to select image from source
  Future<void> _selectImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      NotificationService.showError(context, 'Failed to pick image: $e');
    }
  }

  // Method to remove the selected/current image
  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _currentImageUrl = null;
    });
  }

  // Alternative method: Upload image as base64 to database (if storage bucket fails)
  Future<String?> _uploadImageAsBase64() async {
    if (_selectedImage == null) return _currentImageUrl;

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64String';

      return dataUrl;
    } catch (e) {
      NotificationService.showError(context, 'Failed to process image: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _contactNumberController.dispose();
    _licenseNumberController.dispose();
    _licenseExpirationController.dispose();
    super.dispose();
  }

  // Build the actual profile image widget
  Widget _buildProfileImage() {
    if (_selectedImage != null) {
      // Show selected image
      return Image.file(
        _selectedImage!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else if (_isValidImageUrl(_currentImageUrl)) {
      // Check if it's a base64 image or network image
      if (_currentImageUrl!.startsWith('data:image')) {
        // Base64 image
        final base64String = _currentImageUrl!.split(',')[1];
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } else {
        // Network image
        final cacheBustedUrl = _addCacheBusterForDialog(_currentImageUrl!);
        return Image.network(
          cacheBustedUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 280, // Cache at 2x resolution for crisp display
          cacheHeight: 280,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF007AFF).withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF007AFF),
                  ),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar();
          },
        );
      }
    } else {
      return _buildDefaultAvatar();
    }
  }

  // Build default avatar widget
  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF007AFF).withOpacity(0.1),
            Colors.transparent,
          ],
        ),
      ),
      child: Icon(
        Icons.person_outline,
        size: 60,
        color: Colors.grey.withOpacity(0.6),
      ),
    );
  }

  // Helper method to add cache-busting parameter to image URLs
  String _addCacheBusterForDialog(String url) {
    if (url.isEmpty) return url;

    // Add timestamp as query parameter to bust cache
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}t=${DateTime.now().millisecondsSinceEpoch}';
  }

  // Helper method to check if an image URL is valid
  bool _isValidImageUrl(dynamic imageUrl) {
    final isNotNull = imageUrl != null;
    final isNotEmpty = imageUrl.toString().isNotEmpty;
    final isNotNullString = imageUrl.toString().toLowerCase() != 'null';

    return isNotNull && isNotEmpty && isNotNullString;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1E1E),
              Color(0xFF0A0A0A),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Enhanced Header with Beautiful Gradient
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.2),
                    Theme.of(context).primaryColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Enhanced Icon with Animation
                  Hero(
                    tag: 'edit_profile_icon',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.user['role'] == 'driver'
                            ? Icons.local_shipping_rounded
                            : Icons.admin_panel_settings_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Enhanced Title Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Update ${widget.user['role'] ?? 'user'} information',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Enhanced Content with Better Organization
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Enhanced Profile Image Section
                      _buildEnhancedProfileSection(),
                      const SizedBox(height: 32),

                      // Personal Information Section
                      _buildSectionTitle(
                        'Personal Information',
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildNameFields(),
                      const SizedBox(height: 24),

                      // Contact & Account Section
                      _buildSectionTitle(
                        'Contact & Account',
                        Icons.contact_phone_outlined,
                      ),
                      const SizedBox(height: 16),
                      _buildContactFields(),
                      const SizedBox(height: 24),

                      // Driver License Section (conditional)
                      if (widget.user['role'] == 'driver') ...[
                        _buildSectionTitle(
                          'License Information',
                          Icons.credit_card_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildLicenseFields(),
                        const SizedBox(height: 24),
                      ],

                      // Error Display
                      if (errorMessage != null) ...[
                        _buildErrorMessage(),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Enhanced Action Buttons at Bottom
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.05),
                    Theme.of(context).primaryColor.withOpacity(0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: _buildActionButtons(),
            ),
          ],
        ),
      ),
    );
  }

  // Enhanced Profile Image Section
  Widget _buildEnhancedProfileSection() {
    return Column(
      children: [
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow effect background
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF007AFF).withOpacity(0.2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
              // Main profile image container
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.1),
                      Colors.white.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(child: _buildProfileImage()),
              ),
              // Enhanced edit button
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _isUploadingImage ? null : _pickImage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isUploadingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Profile Photo',
            style: TextStyle(
              color: Colors.grey.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (_isUploadingImage)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Uploading...',
                style: TextStyle(
                  color: const Color(0xFF007AFF).withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Section Title Builder
  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF007AFF).withOpacity(0.2),
                const Color(0xFF0056CC).withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF007AFF), size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  // Enhanced Name Fields
  Widget _buildNameFields() {
    return Column(
      children: [
        // First row: First Name and Last Name
        Row(
          children: [
            Expanded(
              child: _buildModernTextField(
                controller: _firstNameController,
                label: 'First Name',
                icon: Icons.person_outline,
                isRequired: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernTextField(
                controller: _lastNameController,
                label: 'Last Name',
                icon: Icons.person_outline,
                isRequired: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Second row: Middle Name (full width)
        _buildModernTextField(
          controller: _middleNameController,
          label: 'Middle Name',
          icon: Icons.person_outline,
        ),
      ],
    );
  }

  // Enhanced Contact Fields
  Widget _buildContactFields() {
    return Column(
      children: [
        _buildModernTextField(
          controller: _usernameController,
          label: 'Username',
          icon: Icons.alternate_email_rounded,
          isRequired: true,
        ),
        const SizedBox(height: 20),
        _buildModernTextField(
          controller: _contactNumberController,
          label: 'Contact Number',
          icon: Icons.phone_outlined,
          inputFormatters: [_sharedPhoneFormatter],
          maxLength: 16,
        ),
        const SizedBox(height: 20),
        _buildStatusDropdown(),
      ],
    );
  }

  // Enhanced License Fields
  Widget _buildLicenseFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildModernTextField(
                controller: _licenseNumberController,
                label: 'License Number',
                icon: Icons.credit_card_outlined,
                isRequired: true,
                inputFormatters: [PhLicenseNumberFormatter()],
                maxLength: 13,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModernTextField(
                controller: _licenseExpirationController,
                label: 'License Expiry',
                icon: Icons.calendar_today_outlined,
                isRequired: true,
                isReadOnly: true,
                onTap: _selectLicenseExpiryDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildLicenseClassSelector(),
      ],
    );
  }

  // Modern Text Field Builder
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    bool isReadOnly = false,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF007AFF), size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label + (isRequired ? ' *' : ''),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: TextFormField(
            controller: controller,
            readOnly: isReadOnly,
            onTap: onTap,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Enter ${label.toLowerCase()}',
              hintStyle: TextStyle(
                color: Colors.grey.withOpacity(0.5),
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF007AFF),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              counterText: maxLength != null ? '' : null,
              suffixIcon: isReadOnly && onTap != null
                  ? Icon(
                      Icons.arrow_drop_down,
                      color: Colors.grey.withOpacity(0.7),
                    )
                  : null,
            ),
            validator: isRequired
                ? (value) {
                    if (value == null || value.isEmpty) {
                      return '$label is required';
                    }
                    return null;
                  }
                : null,
          ),
        ),
      ],
    );
  }

  // Enhanced Status Dropdown
  Widget _buildStatusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.toggle_on_outlined,
              color: Color(0xFF007AFF),
              size: 14,
            ),
            const SizedBox(width: 8),
            Text(
              'Status',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: DropdownButtonFormField<String>(
            value: _status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            dropdownColor: const Color(0xFF2A2A2A),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
            ),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.withOpacity(0.7),
            ),
            items: [
              DropdownMenuItem(
                value: 'active',
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Active'),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 'inactive',
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Inactive'),
                  ],
                ),
              ),
            ],
            onChanged: (value) {
              print('🔄 Status dropdown changed to: $value');
              setState(() {
                _status = value;
              });
              print('✅ Status updated in state, no profile update called');
            },
          ),
        ),
      ],
    );
  }

  // Enhanced License Class Selector
  Widget _buildLicenseClassSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF007AFF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'License Class *',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildLicenseChip(
                  'Non-Professional',
                  _licenseClass == 'Non-Pro',
                  () => setState(() => _licenseClass = 'Non-Pro'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildLicenseChip(
                  'Professional',
                  _licenseClass == 'Pro',
                  () => setState(() => _licenseClass = 'Pro'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // License Class Chip
  Widget _buildLicenseChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced Action Buttons
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF007AFF), Color(0xFF0056CC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007AFF).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      print('🔥 Update Profile button pressed');
                      _updateProfile();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : const Text(
                      'Update Profile',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // Enhanced Error Message
  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.withOpacity(0.15), Colors.red.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Date Picker Helper
  Future<void> _selectLicenseExpiryDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF007AFF),
              surface: Color(0xFF1A1A1A),
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _licenseExpirationController.text =
          '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
    }
  }
}

// Extension to capitalize string
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

Future<bool> addDriver(
  String firstName,
  String middleName,
  String lastName,
  String username,
  String password,
  String? contactNumber,
  String? licenseNumber,
  String? licenseExpiration,
  String role,
  String? licenseClass,
  String? employeeId,
  String? driverId, // Add driver ID parameter
  String? operatorId,
) async {
  // Add operator ID parameter
  final response = await http.post(
    Uri.parse(
      'https://hhsaglfvhdlgsbqmcwbw.functions.supabase.co/create-driver',
    ),
    headers: {
      'Content-Type': 'application/json',
      'Authorization':
          'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
    },
    body: jsonEncode({
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'username': username,
      'password': password,
      'contact_number': contactNumber,
      'driver_license_number': licenseNumber,
      'driver_license_expiration_date': licenseExpiration,
      'role': role,
      'driver_license_class': licenseClass, // send license class
      'employee_id': employeeId, // send employee ID
      'driver_id': driverId, // send driver ID
      'operator_id': operatorId, // send operator ID
    }),
  );

  print('🚀 Sending to backend:');
  print('  driver_id: $driverId');
  print('  operator_id: $operatorId');
  print('  employee_id: $employeeId');
  print('  role: $role');

  if (response.statusCode == 200) {
    // Parse and log the returned IDs for debugging
    final data = jsonDecode(response.body);
    print('✅ Driver created successfully!');
    print('Response data: $data');
    print('Employee ID: ${data['employee_id']}');
    print('Driver ID: ${data['driver_id']}');
    print('Operator ID: ${data['operator_id']}');
    return true;
  } else {
    print('❌ Error creating driver: ${response.body}');
    return false;
  }
}

// Helper function to delete a user via direct Supabase calls (fallback method)
Future<bool> deleteUser(String userId) async {
  try {
    print('🗑️ Starting user deletion process for user ID: $userId');

    // First, try to use the Edge Function
    try {
      print('🗑️ Attempting Edge Function deletion...');
      final response = await http.post(
        Uri.parse(
          'https://hhsaglfvhdlgsbqmcwbw.functions.supabase.co/delete-user',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
          'apikey':
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhoc2FnbGZ2aGRsZ3NicW1jd2J3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE5NjgyMTAsImV4cCI6MjA2NzU0NDIxMH0.tcbnhoxdDWEyDDUVFlXFr5UwNY1M9H7tDsNuW2pP2t4',
        },
        body: jsonEncode({'userId': userId}),
      );

      print('🗑️ Edge Function response status: ${response.statusCode}');
      print('🗑️ Edge Function response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ User deleted successfully via Edge Function!');
        return true;
      } else {
        print('❌ Edge Function failed, trying fallback method...');
        throw Exception('Edge Function failed: ${response.body}');
      }
    } catch (edgeFunctionError) {
      print('❌ Edge Function error: $edgeFunctionError');
      print('🔄 Falling back to direct Supabase deletion...');

      // Fallback: Delete directly using Supabase client
      // Note: This will only delete from the users table, not from auth
      // but it's better than having no deletion capability
      try {
        print('🗑️ Attempting direct database deletion...');
        print('🔍 Deleting user with ID: "$userId"');

        // First, let's check what might be preventing deletion
        // Check for foreign key references
        try {
          // Check if user is referenced in trips table
          final tripReferences = await Supabase.instance.client
              .from('trips')
              .select('id')
              .eq('driver_id', userId)
              .limit(1);

          print('🔍 Trip references found: ${tripReferences.length}');
          if (tripReferences.isNotEmpty) {
            print('⚠️ User has trip references that may prevent deletion');
          }
        } catch (e) {
          print('⚠️ Could not check trip references: $e');
        }

        // Delete from users table - check for response
        final deleteResponse = await Supabase.instance.client
            .from('users')
            .delete()
            .eq('id', userId);

        print(
          '🔍 Direct deletion response type: ${deleteResponse.runtimeType}',
        );
        print('🔍 Direct deletion response: $deleteResponse');

        // The delete operation in Supabase Flutter doesn't throw exceptions
        // We need to verify deletion by checking if the user still exists
        final verifyResponse = await Supabase.instance.client
            .from('users')
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        print('🔍 Verification query result: $verifyResponse');

        if (verifyResponse != null) {
          // User still exists - this could be due to foreign key constraints
          // Let's try to handle this more gracefully
          print('❌ User still exists in database after deletion attempt');
          print('🔍 This could be due to:');
          print(
            '  1. Foreign key constraints (user referenced in other tables)',
          );
          print('  2. Row Level Security (RLS) policies');
          print('  3. Insufficient permissions');

          // Instead of hard failing, let's try a soft delete approach
          // Set the user status to 'inactive' instead of actually deleting
          // (the database only allows 'active' and 'inactive' status values)
          print('🔄 Attempting soft delete (marking as inactive)...');

          try {
            final softDeleteResponse =
                await Supabase.instance.client.from('users').update({
              'status': 'inactive',
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', userId);

            print('🔍 Soft delete response: $softDeleteResponse');

            // Verify soft delete worked
            final softVerifyResponse = await Supabase.instance.client
                .from('users')
                .select('id, status')
                .eq('id', userId)
                .maybeSingle();

            if (softVerifyResponse?['status'] == 'inactive') {
              print('✅ User successfully marked as inactive (soft delete)');
              print(
                '⚠️ Note: User record still exists but is marked as inactive',
              );
              return true;
            } else {
              throw Exception(
                'Soft delete failed - could not update user status',
              );
            }
          } catch (softDeleteError) {
            print('❌ Soft delete also failed: $softDeleteError');
            throw Exception(
              'User deletion failed: Cannot delete due to database constraints or permissions. Try removing any associated trips first, or contact administrator.',
            );
          }
        }

        print('✅ User deleted from users table successfully!');
        print('⚠️ Note: User may still exist in authentication system');
        return true;
      } catch (directDeleteError) {
        print('❌ Direct deletion also failed: $directDeleteError');
        throw Exception(
          'Both Edge Function and direct deletion failed: $directDeleteError',
        );
      }
    }
  } catch (e) {
    print('❌ Critical error during user deletion: $e');
    rethrow; // Re-throw to maintain error info
  }
}

Future<void> assignDriverToTrip(String tripId, String driverId) async {
  final response = await Supabase.instance.client
      .from('trips')
      .update({'driver_id': driverId}).eq('id', tripId);

  if (response.error == null) {
    // Success
  } else {
    // Handle error
  }
}

// Add custom formatters
class PhMobileNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.startsWith('0')) {
      text = '+63${text.substring(1)}';
    } else if (!text.startsWith('+63')) {
      text = '+63$text';
    }
    if (text.length > 3) {
      text = '${text.substring(0, 3)} ${text.substring(3)}';
    }
    if (text.length > 7) {
      text = '${text.substring(0, 7)}-${text.substring(7)}';
    }
    if (text.length > 11) {
      text =
          '${text.substring(0, 11)}-${text.substring(11, text.length > 15 ? 15 : text.length)}';
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class PhLicenseNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text =
        newValue.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (text.length > 3) text = '${text.substring(0, 3)}-${text.substring(3)}';
    if (text.length > 5) {
      text =
          '${text.substring(0, 6)}-${text.substring(6, text.length > 13 ? 13 : text.length)}';
    }
    return TextEditingValue(
      text: text.length > 13 ? text.substring(0, 13) : text,
      selection: TextSelection.collapsed(
        offset: text.length > 13 ? 13 : text.length,
      ),
    );
  }
}

class DateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 2) text = '${text.substring(0, 2)}/${text.substring(2)}';
    if (text.length > 5) {
      text =
          '${text.substring(0, 5)}/${text.substring(5, text.length > 10 ? 10 : text.length)}';
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
