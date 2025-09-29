import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryPage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const HistoryPage({super.key, this.userData});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<String, dynamic>? _currentUser;
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;

  // Add expansion state for trip cards
  final Map<String, bool> _cardExpansionStates = {};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _animationController.forward();

    if (widget.userData != null) {
      _currentUser = widget.userData;
      _loadTripHistory();
    } else {
      _loadCurrentUser();
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        setState(() {
          _currentUser = userData;
        });
        _loadTripHistory();
      }
    } catch (e) {
      print('Error loading user: $e');
    }
  }

  Future<void> _loadTripHistory() async {
    try {
      if (_currentUser == null) return;

      // Load trips where current user was either main driver or sub driver
      final tripsResponse = await Supabase.instance.client
          .from('trips')
          .select('''
            id,
            trip_ref_number,
            origin,
            destination,
            start_time,
            end_time,
            status,
            priority,
            contact_person,
            contact_phone,
            notes,
            progress,
            created_at,
            driver_id,
            sub_driver_id,
            users:driver_id(id, first_name, last_name, profile_image_url),
            sub_driver:sub_driver_id(id, first_name, last_name, profile_image_url)
          ''')
          .or('driver_id.eq.${_currentUser!['id']},sub_driver_id.eq.${_currentUser!['id']}')
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      // Load additional history data from history table
      final historyResponse = await Supabase.instance.client
          .from('history')
          .select('''
            id,
            trip_id,
            completed_at,
            fuel_used,
            weight,
            packages,
            delivery_receipt,
            customer_rating,
            notes,
            client_name,
            requested_at
          ''')
          .eq('driver_id', _currentUser!['id'])
          .order('completed_at', ascending: false);

      // Combine trips with history and rating data
      final List<Map<String, dynamic>> combinedTrips = [];

      for (var trip in tripsResponse) {
        // Find matching history record
        final historyRecord = historyResponse.firstWhere(
          (history) => history['trip_id'] == trip['id'],
          orElse: () => <String, dynamic>{},
        );

        // Load ratings for this trip and current driver
        final ratings = await Supabase.instance.client
            .from('driver_ratings')
            .select('''
              id, rating, comment, created_at, updated_at,
              metadata,
              rated_by_user:rated_by(id, first_name, last_name, role)
            ''')
            .eq('trip_id', trip['id'])
            .eq('driver_id', _currentUser!['id'])
            .order('created_at', ascending: false);

        // Calculate duration
        String duration = 'N/A';
        if (trip['start_time'] != null && trip['end_time'] != null) {
          try {
            final startTime = DateTime.parse(trip['start_time'].toString());
            final endTime = DateTime.parse(trip['end_time'].toString());
            final difference = endTime.difference(startTime);
            final hours = difference.inHours;
            final minutes = difference.inMinutes % 60;
            duration = '$hours hours $minutes minutes';
          } catch (e) {
            duration = 'N/A';
          }
        }

        // Determine driver role for this trip
        String driverRole = 'Unknown';
        if (trip['driver_id'] == _currentUser!['id']) {
          driverRole = 'Main Driver';
        } else if (trip['sub_driver_id'] == _currentUser!['id']) {
          driverRole = 'Sub Driver';
        }

        combinedTrips.add({
          ...trip,
          'history_data': historyRecord,
          'ratings': List<Map<String, dynamic>>.from(ratings),
          'driver_role': driverRole,
          'duration': duration,
          'date': trip['created_at'] != null
              ? _formatDate(DateTime.parse(trip['created_at'].toString()))
              : 'N/A',
        });
      }

      setState(() {
        _trips = combinedTrips;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading trip history: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filteredTrips {
    if (_selectedDate == null) return _trips;
    return _trips
        .where((trip) => trip['date'] == _formatDate(_selectedDate))
        .toList();
  }

  // Shared date/time formatting functions
  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}';
  }

  String _formatFullDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final DateTime dt = DateTime.parse(dateTime.toString());
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'pm' : 'am';
      return '${dt.month}/${dt.day}/${dt.year} $hour:${dt.minute.toString().padLeft(2, '0')} $ampm';
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Color(0xFF000000), // Pure black background like dashboard
      ),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            // Top controls - Filter and Refresh
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Filter by Date - Left side
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                color: Colors.blue,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _selectedDate == null
                                    ? 'Filter by Date'
                                    : _formatDate(_selectedDate),
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedDate = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.clear,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Refresh Button - Right side
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isLoading = true;
                      });
                      _loadTripHistory();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ), // Trip List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.blue,
                      ),
                    )
                  : filteredTrips.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_outlined,
                                size: 64,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedDate != null
                                    ? 'No trips found for\n${_formatDate(_selectedDate)}'
                                    : 'No completed trips found',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredTrips.length,
                          itemBuilder: (context, index) {
                            final trip = filteredTrips[index];
                            return _buildModernTripCard(trip);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern expandable trip card with operator-style design
  Widget _buildModernTripCard(Map<String, dynamic> trip) {
    final tripId =
        trip['id']?.toString() ?? trip['trip_ref_number'] ?? 'unknown';
    final isExpanded = _cardExpansionStates[tripId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A3A3A),
            Color(0xFF2E2E2E),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _cardExpansionStates[tripId] = !isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with Trip ID and status badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.history_outlined,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trip ID',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                trip['trip_ref_number'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Status badge and date in top right
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF4CAF50).withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'completed',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4CAF50),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trip['date'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (!isExpanded) ...[
                    const SizedBox(height: 16),

                    // Route and duration stacked vertically
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Route
                        Row(
                          children: [
                            const Icon(
                              Icons.route_outlined,
                              color: Colors.blue,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${trip['origin'] ?? 'N/A'} → ${trip['destination'] ?? 'N/A'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Duration
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              color: Colors.orange,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                trip['duration'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],

                  // Expanded content
                  if (isExpanded) ...[
                    const SizedBox(height: 20),

                    // Trip Information Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2A2A2A),
                            Color(0xFF232323),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Trip Information:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Date: ${trip['date'] ?? 'N/A'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Duration: ${trip['duration'] ?? 'N/A'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Status: ',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF4CAF50).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50)
                                        .withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  trip['status'] ?? 'N/A',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4CAF50),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (trip['priority'] != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'Priority: ',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(trip['priority'])
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _getPriorityColor(trip['priority'])
                                          .withOpacity(0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    trip['priority'].toString().toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          _getPriorityColor(trip['priority']),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Driver Role Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2A2A2A),
                            Color(0xFF232323),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: trip['driver_role'] == 'Main Driver'
                                  ? Colors.blue.withOpacity(0.15)
                                  : Colors.blue.withOpacity(
                                      0.15), // Changed from Colors.purple to Colors.blue
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              trip['driver_role'] == 'Main Driver'
                                  ? Icons.person
                                  : Icons.person_outline,
                              color: trip['driver_role'] == 'Main Driver'
                                  ? Colors.blue
                                  : Colors
                                      .blue, // Changed from Colors.purple to Colors.blue
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your Role',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                trip['driver_role'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: trip['driver_role'] == 'Main Driver'
                                      ? Colors.blue
                                      : Colors
                                          .blue, // Changed from Colors.purple to Colors.blue
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Ratings & Comments Container
                    if (trip['ratings'] != null &&
                        (trip['ratings'] as List).isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2A2A2A),
                              Color(0xFF232323),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Operator Ratings & Comments:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...(trip['ratings'] as List<Map<String, dynamic>>)
                                .map((rating) {
                              final operatorName = rating['rated_by_user'] !=
                                      null
                                  ? '${rating['rated_by_user']['first_name']} ${rating['rated_by_user']['last_name']}'
                                  : (rating['metadata']?['operator_name'] ??
                                      'Unknown Operator');
                              final operatorId = rating['rated_by_user']
                                      ?['id'] ??
                                  rating['metadata']?['operator_id'] ??
                                  'Unknown';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Rating stars and operator info
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: List.generate(5, (index) {
                                            return Icon(
                                              index <
                                                      (rating['rating'] as num)
                                                          .toInt()
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.amber,
                                              size: 16,
                                            );
                                          }),
                                        ),
                                        Text(
                                          '${(rating['rating'] as num).toInt()}/5',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.amber,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Comment
                                    if (rating['comment'] != null &&
                                        rating['comment']
                                            .toString()
                                            .isNotEmpty) ...[
                                      Text(
                                        rating['comment'],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    // Operator info
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person_outline,
                                          color: Colors.grey,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Rated by: $operatorName',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          'ID: ${operatorId.toString().substring(0, 8)}...',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Date
                                    if (rating['created_at'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Rated on: ${_formatFullDateTime(rating['created_at'])}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Route Details Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2A2A2A),
                            Color(0xFF232323),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Route Details:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Origin: ${trip['origin'] ?? 'N/A'}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
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
                              const SizedBox(width: 8),
                              Text(
                                'Destination: ${trip['destination'] ?? 'N/A'}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start Time: ${trip['start_time'] != null ? _formatFullDateTime(trip['start_time']) : 'N/A'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'End Time: ${trip['end_time'] != null ? _formatFullDateTime(trip['end_time']) : 'N/A'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to get priority color
  Color _getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
