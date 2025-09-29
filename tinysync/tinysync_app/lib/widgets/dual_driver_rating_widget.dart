import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_persistence_service.dart';

/// Enhanced widget for rating both Main Driver and Sub Driver on completed trips
/// Records operator information and links ratings to correct driver IDs
class DualDriverRatingWidget extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onRatingSubmitted;

  const DualDriverRatingWidget({
    super.key,
    required this.trip,
    this.onRatingSubmitted,
  });

  @override
  State<DualDriverRatingWidget> createState() => _DualDriverRatingWidgetState();
}

class _DualDriverRatingWidgetState extends State<DualDriverRatingWidget> {
  // Main Driver Rating
  int _mainDriverRating = 0;
  final TextEditingController _mainDriverCommentController =
      TextEditingController();

  // Sub Driver Rating
  int _subDriverRating = 0;
  final TextEditingController _subDriverCommentController =
      TextEditingController();

  bool _isSubmitting = false;
  bool _isLoadingData = true;

  // Trip data
  Map<String, dynamic>? _mainDriverData;
  Map<String, dynamic>? _subDriverData;
  Map<String, dynamic>? _operatorData;
  Map<String, dynamic>? _existingMainDriverRating;
  Map<String, dynamic>? _existingSubDriverRating;

  @override
  void initState() {
    super.initState();
    _loadTripData();
  }

  @override
  void dispose() {
    _mainDriverCommentController.dispose();
    _subDriverCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadTripData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final tripId = widget.trip['id'];
      final mainDriverId = widget.trip['driver_id'];
      final subDriverId = widget.trip['sub_driver_id'];
      final currentOperator = Supabase.instance.client.auth.currentUser;

      // Load current operator data
      if (currentOperator != null) {
        _operatorData = await Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, role')
            .eq('id', currentOperator.id)
            .maybeSingle();
      }

      // Load main driver data
      if (mainDriverId != null) {
        _mainDriverData = await Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, profile_image_url, driver_id')
            .eq('id', mainDriverId)
            .maybeSingle();
      }

      // Load sub driver data
      if (subDriverId != null) {
        _subDriverData = await Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, profile_image_url, driver_id')
            .eq('id', subDriverId)
            .maybeSingle();
      }

      // Load existing ratings
      if (mainDriverId != null && currentOperator != null) {
        _existingMainDriverRating = await Supabase.instance.client
            .from('driver_ratings')
            .select('*')
            .eq('trip_id', tripId)
            .eq('driver_id', mainDriverId)
            .eq('rated_by', currentOperator.id)
            .maybeSingle();
      }

      if (subDriverId != null && currentOperator != null) {
        _existingSubDriverRating = await Supabase.instance.client
            .from('driver_ratings')
            .select('*')
            .eq('trip_id', tripId)
            .eq('driver_id', subDriverId)
            .eq('rated_by', currentOperator.id)
            .maybeSingle();
      }

      // Set existing ratings if found
      if (_existingMainDriverRating != null) {
        _mainDriverRating =
            (_existingMainDriverRating!['rating'] as num).toInt();
        _mainDriverCommentController.text =
            _existingMainDriverRating!['comment'] ?? '';
      }

      if (_existingSubDriverRating != null) {
        _subDriverRating = (_existingSubDriverRating!['rating'] as num).toInt();
        _subDriverCommentController.text =
            _existingSubDriverRating!['comment'] ?? '';
      }

      setState(() {
        _isLoadingData = false;
      });
    } catch (e) {
      print('❌ Error loading trip data: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  Future<void> _submitRatings() async {
    if ((_mainDriverData != null && _mainDriverRating == 0) ||
        (_subDriverData != null && _subDriverRating == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide ratings for all drivers'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get operator ID using the app's authentication system
      String? operatorId;

      // Try AuthPersistenceService first (app's custom auth)
      try {
        final authData = await AuthPersistenceService.getCurrentUserData();
        if (authData != null && authData['role'] == 'operator') {
          operatorId = authData['id'];
        }
      } catch (e) {
        print('⚠️ AuthPersistenceService failed: $e');
      }

      // Fallback to Supabase auth if needed
      if (operatorId == null) {
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser != null) {
          operatorId = currentUser.id;
        }
      }

      // Final validation
      if (operatorId == null || operatorId.isEmpty) {
        throw Exception(
            'No authenticated operator found. Please ensure you are logged in properly.');
      }

      final tripId = widget.trip['id'];
      final timestamp = DateTime.now().toIso8601String();

      // Submit main driver rating
      if (_mainDriverData != null && _mainDriverRating > 0) {
        final mainDriverRatingData = {
          'trip_id': tripId,
          'driver_id': _mainDriverData!['id'],
          'rated_by': operatorId,
          'rating': _mainDriverRating,
          'comment': _mainDriverCommentController.text.trim(),
          'created_at': timestamp,
          'updated_at': timestamp,
          'metadata': {
            'operator_name':
                '${_operatorData?['first_name'] ?? ''} ${_operatorData?['last_name'] ?? ''}',
            'operator_id': operatorId,
            'driver_type': 'main_driver',
            'trip_ref': widget.trip['trip_ref_number'],
          }
        };

        if (_existingMainDriverRating != null) {
          // Update existing rating
          await Supabase.instance.client
              .from('driver_ratings')
              .update(mainDriverRatingData)
              .eq('id', _existingMainDriverRating!['id']);
        } else {
          // Insert new rating
          await Supabase.instance.client
              .from('driver_ratings')
              .insert(mainDriverRatingData);
        }
      }

      // Submit sub driver rating
      if (_subDriverData != null && _subDriverRating > 0) {
        final subDriverRatingData = {
          'trip_id': tripId,
          'driver_id': _subDriverData!['id'],
          'rated_by': operatorId,
          'rating': _subDriverRating,
          'comment': _subDriverCommentController.text.trim(),
          'created_at': timestamp,
          'updated_at': timestamp,
          'metadata': {
            'operator_name':
                '${_operatorData?['first_name'] ?? ''} ${_operatorData?['last_name'] ?? ''}',
            'operator_id': operatorId,
            'driver_type': 'sub_driver',
            'trip_ref': widget.trip['trip_ref_number'],
          }
        };

        if (_existingSubDriverRating != null) {
          // Update existing rating
          await Supabase.instance.client
              .from('driver_ratings')
              .update(subDriverRatingData)
              .eq('id', _existingSubDriverRating!['id']);
        } else {
          // Insert new rating
          await Supabase.instance.client
              .from('driver_ratings')
              .insert(subDriverRatingData);
        }
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver ratings submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Callback
      widget.onRatingSubmitted?.call();
    } catch (e) {
      print('❌ Error submitting ratings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting ratings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Widget _buildDriverRatingSection({
    required String title,
    required Map<String, dynamic>? driverData,
    required int currentRating,
    required TextEditingController commentController,
    required Function(int) onRatingChanged,
    required Color accentColor,
  }) {
    if (driverData == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver info header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 2),
                  color: accentColor.withOpacity(0.1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: driverData['profile_image_url'] != null
                      ? Image.network(
                          driverData['profile_image_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(Icons.person, color: accentColor, size: 20),
                        )
                      : Icon(Icons.person, color: accentColor, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    Text(
                      '${driverData['first_name']} ${driverData['last_name']}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (driverData['driver_id'] != null)
                      Text(
                        'ID: ${driverData['driver_id']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rating stars
          const Text(
            'Rate Performance (1-5 stars)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(5, (index) {
              return GestureDetector(
                onTap: () => onRatingChanged(index + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(right: index < 4 ? 3 : 0),
                  child: Icon(
                    currentRating > index ? Icons.star : Icons.star_border,
                    color:
                        currentRating > index ? Colors.amber : Colors.grey[600],
                    size: 24,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Comment field
          const Text(
            'Comment (Optional)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: commentController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add your feedback about this driver\'s performance...',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.transparent),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[800]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: accentColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const SizedBox(
          height: 300,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF007AFF)),
                SizedBox(height: 16),
                Text(
                  'Loading driver information...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.maxFinite,
      constraints: BoxConstraints(
        maxWidth: 600,
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - matching Assign Driver design
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rate Driver',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Evaluate trip completion quality',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),

          // Route info - Fixed at top
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Origin: ${widget.trip['origin'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Destination: ${widget.trip['destination'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable driver rating sections - Middle
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Main Driver Rating Section
                  _buildDriverRatingSection(
                    title: 'Main Driver',
                    driverData: _mainDriverData,
                    currentRating: _mainDriverRating,
                    commentController: _mainDriverCommentController,
                    onRatingChanged: (rating) {
                      setState(() {
                        _mainDriverRating = rating;
                      });
                    },
                    accentColor: const Color(0xFF007AFF),
                  ),

                  // Sub Driver Rating Section
                  _buildDriverRatingSection(
                    title: 'Sub Driver',
                    driverData: _subDriverData,
                    currentRating: _subDriverRating,
                    commentController: _subDriverCommentController,
                    onRatingChanged: (rating) {
                      setState(() {
                        _subDriverRating = rating;
                      });
                    },
                    accentColor: const Color(0xFF5856D6),
                  ),
                ],
              ),
            ),
          ),

          // Submit button - Fixed at bottom
          Container(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRatings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Submit Ratings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
