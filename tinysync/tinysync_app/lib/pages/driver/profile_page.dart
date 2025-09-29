import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_persistence_service.dart';
// ✅ ALL FCM CRAP REMOVED!

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const ProfilePage({super.key, this.userData});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.userData != null) {
      _currentUser = widget.userData;
      _isLoading = false;
    } else {
      _loadCurrentUser();
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        print('Loading user data for ID: ${user.id}');

        final userData = await Supabase.instance.client.from('users').select('''
              id,
              first_name,
              last_name,
              middle_name,
              username,
              role,
              status,
              contact_number,
              driver_license_number,
              driver_license_expiration_date,
              created_at,
              updated_at,
              profile_image_url,
              driver_license_class,
              employee_id,
              operator_id,
              driver_id
            ''').eq('id', user.id).maybeSingle();

        print(
            'Fetched user data: ${userData != null ? 'Success' : 'No data found'}');
        if (userData != null) {
          print('=== DETAILED USER DATA DEBUG ===');
          print('Raw userData: $userData');
          print('All keys in userData: ${userData.keys.toList()}');
          print('Driver details:');
          print(
              '  Name: ${userData['first_name']} ${userData['middle_name'] ?? ''} ${userData['last_name']}');
          print('  Driver ID: ${userData['driver_id']}');
          print('  Employee ID: ${userData['employee_id']}');
          print('  Status: ${userData['status']}');
          print('  Role: ${userData['role']}');
          print('  Contact: ${userData['contact_number']}');
          print('  License: ${userData['driver_license_number']}');
          print('=== PROFILE PICTURE DEBUG ===');
          print('  Profile Image URL Raw: ${userData['profile_image_url']}');
          print(
              '  Profile Image URL Type: ${userData['profile_image_url'].runtimeType}');
          print(
              '  Profile Image URL is null: ${userData['profile_image_url'] == null}');
          print(
              '  Profile Image URL toString: "${userData['profile_image_url']?.toString()}"');
          print(
              '  Has profile_image_url key: ${userData.containsKey('profile_image_url')}');
          print('=== END DEBUG ===');
        }

        setState(() {
          _currentUser = userData;
          _isLoading = false;
        });
      } else {
        print('No authenticated user found');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildProfileImage() {
    print('=== BUILD PROFILE IMAGE DEBUG ===');
    print('Current user data: $_currentUser');
    print('Keys available: ${_currentUser?.keys.toList()}');

    // Use the correct column name from the database
    final profilePicture = _currentUser!['profile_image_url'];

    print('Profile image URL: "$profilePicture"');
    print('Profile image URL type: ${profilePicture.runtimeType}');
    print('Profile image URL is null: ${profilePicture == null}');
    print('Profile image URL is empty string: ${profilePicture == ""}');
    print('Profile image URL toString: "${profilePicture?.toString()}"');
    print(
        'Is profile image URL empty: ${profilePicture == null || profilePicture.toString().trim().isEmpty}');
    print('=== END BUILD PROFILE IMAGE DEBUG ===');

    // Check if profile picture URL exists and is not empty
    if (profilePicture != null && profilePicture.toString().trim().isNotEmpty) {
      final imageUrl = profilePicture.toString().trim();
      print('Loading image from URL: $imageUrl');

      return Image.network(
        imageUrl,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            print('Image loaded successfully');
            return child;
          }
          print(
              'Loading image... ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes ?? 'unknown'}');
          return Container(
            width: 120,
            height: 120,
            color: Theme.of(context).cardColor,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: Theme.of(context).primaryColor,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('Error loading profile image: $error');
          print('Falling back to default icon');
          return _buildDefaultProfileIcon();
        },
      );
    } else {
      print('No profile picture URL available, showing default icon');
      return _buildDefaultProfileIcon();
    }
  }

  Widget _buildDefaultProfileIcon() {
    // Create a more personalized default icon with user initials
    final firstName = _currentUser!['first_name']?.toString() ?? '';
    final lastName = _currentUser!['last_name']?.toString() ?? '';

    String initials = '';
    if (firstName.isNotEmpty) {
      initials += firstName[0].toUpperCase();
    }
    if (lastName.isNotEmpty) {
      initials += lastName[0].toUpperCase();
    }

    if (initials.isEmpty) {
      initials = 'D'; // Default to 'D' for Driver
    }

    print('Building default profile icon with initials: "$initials"');
    print('First name: "$firstName", Last name: "$lastName"');

    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(
        color: Color(0xFF4CAF50),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Shared date formatting function
  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final DateTime dt = DateTime.parse(date.toString());
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}-${dt.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  void _showFullScreenImage() {
    final profilePicture = _currentUser!['profile_image_url'];

    // Only show full screen if there's an actual profile image URL
    if (profilePicture != null && profilePicture.toString().trim().isNotEmpty) {
      final imageUrl = profilePicture.toString().trim();
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      width: 200,
                      color: Theme.of(context).cardColor,
                      child: const Center(
                        child: Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } else {
      // Show a message that no profile image is available
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No profile image available'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Logout Confirmation',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to log out?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog
                await _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    try {
      // Clear Supabase auth
      await Supabase.instance.client.auth.signOut();
      
      // Clear local authentication data (SharedPreferences)
      await AuthPersistenceService.clearAuthData();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoSection(
      BuildContext context, String title, List<Map<String, String>> details) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        detail['label'] ?? '',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        detail['value'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: const Color(0xFF000000),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_currentUser == null) {
      return Container(
        color: const Color(0xFF000000),
        child: const Center(
          child: Text(
            'Failed to load profile',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final fullName =
        '${_currentUser!['first_name'] ?? ''} ${_currentUser!['middle_name'] ?? ''} ${_currentUser!['last_name'] ?? ''}'
            .trim();
    final driverId = _currentUser!['driver_id'] ?? 'N/A';
    final isActive = _currentUser!['status'] == 'active';

    return Container(
      color: const Color(0xFF000000), // Pure black background
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Profile Photo
            GestureDetector(
              onTap: _showFullScreenImage,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: _buildProfileImage(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Name - made smaller
            Text(
              fullName.isEmpty ? 'Unknown Driver' : fullName,
              style: const TextStyle(
                fontSize: 20, // Reduced from 24
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6), // Reduced from 8
            // Driver ID
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withOpacity(
                    0.3), // Increased from 0.1 to 0.3 for better visibility
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Driver ID: $driverId',
                style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8), // Reduced from 24 to bring badge closer
            // Status Indicator - made to match Driver ID styling
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4), // Matching Driver ID padding exactly
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF4CAF50) : Colors.grey,
                borderRadius: BorderRadius.circular(
                    8), // Matching Driver ID border radius exactly
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? Icons.check_circle_outlined
                        : Icons.cancel_outlined,
                    color: Colors.white,
                    size: 14, // Reduced to match text size better
                  ),
                  const SizedBox(width: 6), // Reduced spacing
                  Text(
                    isActive ? 'Active Driver' : 'Inactive Driver',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14, // Matching Driver ID text style
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoSection(
              context,
              'Personal Information',
              [
                {
                  'label': 'Full Name',
                  'value': fullName.isEmpty ? 'N/A' : fullName
                },
                {
                  'label': 'Username',
                  'value': _currentUser!['username'] ?? 'N/A'
                },
                {
                  'label': 'Contact',
                  'value': _currentUser!['contact_number'] ?? 'N/A'
                },
              ],
            ),
            _buildInfoSection(
              context,
              'License Information',
              [
                {
                  'label': 'License No.',
                  'value': _currentUser!['driver_license_number'] ?? 'N/A'
                },
                {
                  'label': 'Class',
                  'value': _currentUser!['driver_license_class'] ?? 'N/A'
                },
                {
                  'label': 'Expiration',
                  'value': _formatDate(
                      _currentUser!['driver_license_expiration_date'])
                },
              ],
            ),
            _buildInfoSection(
              context,
              'Employment Details',
              [
                {
                  'label': 'Employee ID',
                  'value': _currentUser!['employee_id'] ?? 'N/A'
                },
                {
                  'label': 'Driver ID',
                  'value': _currentUser!['driver_id'] ?? 'N/A'
                },
                {'label': 'Role', 'value': _currentUser!['role'] ?? 'N/A'},
                {
                  'label': 'Account Created',
                  'value': _formatDate(_currentUser!['created_at'])
                },
                {
                  'label': 'Last Updated',
                  'value': _formatDate(_currentUser!['updated_at'])
                },
              ],
            ),

            // Add System Information section if operator_id exists
            if (_currentUser!['operator_id'] != null)
              _buildInfoSection(
                context,
                'System Information',
                [
                  {
                    'label': 'Operator ID',
                    'value': _currentUser!['operator_id'] ?? 'N/A'
                  },
                  {
                    'label': 'Status',
                    'value': (_currentUser!['status'] ?? 'N/A').toUpperCase()
                  },
                ],
              ),

            // ✅ FCM CRAP REMOVED! Notifications work through database!

            // Logout Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showLogoutConfirmation,
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
