import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Professional Rate Driver Performance Card
/// Displays trip details, driver information, and rating system
class RateDriverPerformanceCard extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onRatingSubmitted;

  const RateDriverPerformanceCard({
    super.key,
    required this.trip,
    this.onRatingSubmitted,
  });

  @override
  State<RateDriverPerformanceCard> createState() =>
      _RateDriverPerformanceCardState();
}

class _RateDriverPerformanceCardState extends State<RateDriverPerformanceCard> {
  int _mainDriverRating = 0;
  int _subDriverRating = 0;
  final TextEditingController _mainDriverCommentController =
      TextEditingController();
  final TextEditingController _subDriverCommentController =
      TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingData = true;

  // Driver data
  Map<String, dynamic>? _mainDriverData;
  Map<String, dynamic>? _subDriverData;
  Map<String, dynamic>? _existingMainDriverRating;
  Map<String, dynamic>? _existingSubDriverRating;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  @override
  void dispose() {
    _mainDriverCommentController.dispose();
    _subDriverCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadDriverData() async {
    setState(() {
      _isLoadingData = true;
    });

    try {
      final tripId = widget.trip['id'];
      final mainDriverId = widget.trip['driver_id'];
      final subDriverId = widget.trip['sub_driver_id'];

      // Create a list of futures to execute
      final List<Future<dynamic>> futures = [];

      // Main driver data
      if (mainDriverId != null) {
        futures.add(Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, profile_image_url, driver_id')
            .eq('id', mainDriverId)
            .maybeSingle()
            .catchError((e) {
          print('❌ Error loading main driver data: $e');
          return null;
        }));
      } else {
        futures.add(Future.value(null));
      }

      // Sub-driver data
      if (subDriverId != null) {
        futures.add(Supabase.instance.client
            .from('users')
            .select('id, first_name, last_name, profile_image_url, driver_id')
            .eq('id', subDriverId)
            .maybeSingle()
            .catchError((e) {
          print('❌ Error loading sub-driver data: $e');
          return null;
        }));
      } else {
        futures.add(Future.value(null));
      }

      // Check for existing main driver rating
      futures.add(Supabase.instance.client
          .from('driver_ratings')
          .select('*')
          .eq('trip_id', tripId)
          .eq('driver_id', mainDriverId)
          .maybeSingle()
          .catchError((e) {
        print('❌ Error loading main driver rating: $e');
        return null;
      }));

      // Check for existing sub driver rating
      if (subDriverId != null) {
        futures.add(Supabase.instance.client
            .from('driver_ratings')
            .select('*')
            .eq('trip_id', tripId)
            .eq('driver_id', subDriverId)
            .maybeSingle()
            .catchError((e) {
          print('❌ Error loading sub driver rating: $e');
          return null;
        }));
      } else {
        futures.add(Future.value(null));
      }

      // Execute all futures
      final results = await Future.wait(futures);

      // Process results with null safety
      if (results.isNotEmpty) {
        _mainDriverData = results[0] as Map<String, dynamic>?;
      }
      if (results.length >= 2) {
        _subDriverData = results[1] as Map<String, dynamic>?;
      }
      if (results.length >= 3) {
        _existingMainDriverRating = results[2] as Map<String, dynamic>?;
      }
      if (results.length >= 4) {
        _existingSubDriverRating = results[3] as Map<String, dynamic>?;
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
    } catch (e) {
      print('❌ Error loading driver data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  Future<void> _submitRatings() async {
    if (_mainDriverRating == 0 && _subDriverRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one rating before submitting'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      final tripId = widget.trip['id'];
      final mainDriverId = widget.trip['driver_id'];
      final subDriverId = widget.trip['sub_driver_id'];

      // Submit main driver rating if provided
      if (_mainDriverRating > 0 && mainDriverId != null) {
        final mainDriverRatingData = {
          'driver_id': mainDriverId,
          'rated_by': currentUser.id,
          'trip_id': tripId,
          'rating': _mainDriverRating,
          'comment': _mainDriverCommentController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        };

        if (_existingMainDriverRating != null) {
          await Supabase.instance.client
              .from('driver_ratings')
              .update(mainDriverRatingData)
              .eq('id', _existingMainDriverRating!['id']);
        } else {
          await Supabase.instance.client
              .from('driver_ratings')
              .insert(mainDriverRatingData);
        }
      }

      // Submit sub driver rating if provided
      if (_subDriverRating > 0 && subDriverId != null) {
        final subDriverRatingData = {
          'driver_id': subDriverId,
          'rated_by': currentUser.id,
          'trip_id': tripId,
          'rating': _subDriverRating,
          'comment': _subDriverCommentController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        };

        if (_existingSubDriverRating != null) {
          await Supabase.instance.client
              .from('driver_ratings')
              .update(subDriverRatingData)
              .eq('id', _existingSubDriverRating!['id']);
        } else {
          await Supabase.instance.client
              .from('driver_ratings')
              .insert(subDriverRatingData);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ratings submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Call callback if provided
      widget.onRatingSubmitted?.call();
    } catch (e) {
      print('❌ Error submitting ratings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting ratings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatDateTime(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateTime);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF2D2D2D),
              Color(0xFF1A1A1A),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
              ),
              SizedBox(height: 12),
              Text(
                'Loading driver data...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        _buildHeaderSection(),

        // Trip Info Section
        _buildTripInfoSection(),

        // Add extra spacing between trip info and driver info
        const SizedBox(height: 20),

        // Combined Driver Info and Rating Sections
        _buildCombinedDriverSections(),

        // Submit Button
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.trip['trip_ref_number'] ?? 'Trip ${widget.trip['id']}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.green.withOpacity(0.4),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 12),
                SizedBox(width: 3),
                Text(
                  'Completed',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF3B82F6),
                      Color(0xFF1E40AF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.route, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              const Text(
                'Trip Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Trip Details Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Origin
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.location_on,
                          color: Colors.green, size: 14),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Origin:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.trip['origin'] ?? 'Unknown Origin',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Destination
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 14),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Destination:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.trip['destination'] ?? 'Unknown Destination',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Date
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.calendar_today,
                          color: Color(0xFF3B82F6), size: 14),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Date:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatDateTime(widget.trip['start_time']?.toString()),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedDriverSections() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver Information Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF10B981),
                      Color(0xFF059669),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Driver Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main Driver Section (Info + Rating)
          if (_mainDriverData != null) ...[
            // Main Driver Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF3B82F6),
                          Color(0xFF1E40AF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_mainDriverData!['first_name']} ${_mainDriverData!['last_name']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'MAIN DRIVER',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_mainDriverData!['driver_id'] != null)
                          Text(
                            'ID: ${_mainDriverData!['driver_id']}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Main Driver Rating
            _buildDriverRatingSection(
              driverName:
                  '${_mainDriverData!['first_name']} ${_mainDriverData!['last_name']}',
              driverType: 'MAIN',
              rating: _mainDriverRating,
              commentController: _mainDriverCommentController,
              onRatingChanged: (rating) {
                setState(() {
                  _mainDriverRating = rating;
                });
              },
            ),
            const SizedBox(height: 16),
          ],

          // Sub Driver Section (Info + Rating)
          if (_subDriverData != null) ...[
            // Sub Driver Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF59E0B),
                          Color(0xFFD97706),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_subDriverData!['first_name']} ${_subDriverData!['last_name']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'SUB DRIVER',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_subDriverData!['driver_id'] != null)
                          Text(
                            'ID: ${_subDriverData!['driver_id']}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Sub Driver Rating
            _buildDriverRatingSection(
              driverName:
                  '${_subDriverData!['first_name']} ${_subDriverData!['last_name']}',
              driverType: 'SUB',
              rating: _subDriverRating,
              commentController: _subDriverCommentController,
              onRatingChanged: (rating) {
                setState(() {
                  _subDriverRating = rating;
                });
              },
            ),
            const SizedBox(height: 16),
          ],

          // No Driver Info Available
          if (_mainDriverData == null && _subDriverData == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No driver information available',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF92400E),
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

  Widget _buildDriverRatingSection({
    required String driverName,
    required String driverType,
    required int rating,
    required TextEditingController commentController,
    required Function(int) onRatingChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  driverName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: driverType == 'MAIN'
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$driverType DRIVER',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Star Rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return GestureDetector(
                onTap: () => onRatingChanged(index + 1),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.star,
                    size: 28,
                    color: index < rating
                        ? const Color(0xFFFBBF24)
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Rating Labels
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Poor',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Excellent',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Comment TextField
          TextField(
            controller: commentController,
            maxLines: 3,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Leave feedback about this driver...',
              hintStyle: TextStyle(
                color: Colors.grey.withOpacity(0.6),
                fontSize: 14,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.blue.withOpacity(0.5),
                  width: 1,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        children: [
          // Cancel Button
          Expanded(
            child: TextButton(
              onPressed:
                  _isSubmitting ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isSubmitting
                    ? Colors.grey.withOpacity(0.3)
                    : const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _isSubmitting ? Colors.grey.shade600 : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Submit Button
          Expanded(
            child: TextButton(
              onPressed: _isSubmitting ? null : _submitRatings,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isSubmitting
                    ? Colors.grey.withOpacity(0.3)
                    : const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Submitting...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Assign',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
