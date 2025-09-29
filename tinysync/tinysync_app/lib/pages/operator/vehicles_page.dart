import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../services/notification_service.dart';
import '../../services/dialog_service.dart';
import '../../services/vehicle_assignment_service.dart';
import '../../config/vehicle_status_config.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Map<String, bool> _expandedCards =
      {}; // Track which vehicle cards are expanded

  // Real-time updates
  Timer? _refreshTimer;
  RealtimeChannel? _vehicleSubscription;
  RealtimeChannel? _tripSubscription;

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
    _setupRealTimeUpdates();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _vehicleSubscription?.unsubscribe();
    _tripSubscription?.unsubscribe();
    super.dispose();
  }

  void _setupRealTimeUpdates() {
    // Set up periodic refresh for vehicle locations
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchVehicles();
      }
    });

    // Subscribe to vehicle changes
    _vehicleSubscription = Supabase.instance.client
        .channel('vehicles_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (payload) {
            _fetchVehicles();
          },
        )
        .subscribe();

    // Subscribe to trip changes that affect vehicle assignments
    _tripSubscription = Supabase.instance.client
        .channel('trips_vehicles_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            _fetchVehicles();
          },
        )
        .subscribe();
  }

  Future<void> _fetchVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Get all vehicles with availability information
      final response = await Supabase.instance.client
          .from('vehicles')
          .select()
          .order('created_at', ascending: false);

      final vehicles = List<Map<String, dynamic>>.from(response);

      // Get availability information for all vehicles
      final vehicleIds = vehicles.map((v) => v['id'] as String).toList();
      final availabilityResults =
          await VehicleAssignmentService.checkMultipleVehicleAvailability(
              vehicleIds);

      // Combine vehicle data with availability status
      final vehiclesWithAvailability = vehicles.map((vehicle) {
        final availability = availabilityResults[vehicle['id']] ??
            {
              'is_available': true,
              'current_status': 'available',
              'current_trip_ref': '',
              'message': 'Vehicle is available for assignment',
              'reason': 'available',
            };

        return {
          ...vehicle,
          'availability': availability,
        };
      }).toList();

      setState(() {
        _vehicles = vehiclesWithAvailability;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch vehicles: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern header section with compact design
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.15),
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
                  // Header row with icon and title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).primaryColor,
                              Theme.of(context).primaryColor.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vehicle Management',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Manage your fleet with ease',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showAddVehicleDialog(context),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Add Vehicle',
                                style: TextStyle(
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
            ),
            const SizedBox(height: 20),
            if (_isLoading) _buildModernLoadingState(),
            if (_errorMessage != null) _buildEnhancedErrorState(),
            if (!_isLoading && _errorMessage == null && _vehicles.isNotEmpty)
              _buildModernVehicleGrid(),
            if (!_isLoading && _errorMessage == null && _vehicles.isEmpty)
              _buildEnhancedEmptyState(),
          ],
        ),
      ),
    );
  }

  // Modern vehicle grid with enhanced cards
  Widget _buildModernVehicleGrid() {
    return Column(
      children: [
        // Simple stats header like users page
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Text(
                '${_vehicles.length} Vehicle${_vehicles.length != 1 ? 's' : ''} in Fleet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Active',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Enhanced vehicle cards - vertical scrolling
        SizedBox(
          height: 400, // Fixed height for vertical scrolling
          child: ListView.builder(
            scrollDirection: Axis.vertical,
            itemCount: _vehicles.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: _buildEnhancedVehicleCard(_vehicles[index], index),
              );
            },
          ),
        ),
      ],
    );
  }

  // Enhanced vehicle card with modern design
  Widget _buildEnhancedVehicleCard(Map<String, dynamic> vehicle, int index) {
    // Create unique key for expansion tracking
    final uniqueKey =
        '${vehicle['id']}_${vehicle['plate_number'] ?? 'unknown'}';
    final isExpanded = _expandedCards[uniqueKey] ?? false;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOutBack,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A2A2A),
              Color(0xFF232323),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                // Close all other expanded cards
                _expandedCards.clear();
                // Toggle only the clicked card (expand if it was closed)
                if (!isExpanded) {
                  _expandedCards[uniqueKey] = true;
                }
              });
            },
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER SECTION - Vehicle info and status (always visible)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vehicle icon with gradient background
                      Hero(
                        tag: 'vehicle_${vehicle['id']}',
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor.withOpacity(0.2),
                                Theme.of(context).primaryColor.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.local_shipping_rounded,
                            size: 14,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Vehicle details with proper overflow handling
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle['plate_number'] ?? 'No Plate',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'
                                  .trim(),
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Enhanced status badge with availability info
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getStatusColor(vehicle['status'])
                                      .withOpacity(0.2),
                                  _getStatusColor(vehicle['status'])
                                      .withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _getStatusColor(vehicle['status'])
                                    .withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(vehicle['status']),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  vehicle['status'] ?? 'Unknown',
                                  style: TextStyle(
                                    color: _getStatusColor(vehicle['status']),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Show basic info only when collapsed
                  if (!isExpanded) ...[
                    Text(
                      '${vehicle['type'] ?? 'N/A'} • ${vehicle['capacity_kg'] != null ? '${vehicle['capacity_kg']} kg' : 'No capacity info'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],

                  // Expandable content using AnimatedCrossFade
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        // Vehicle specifications grid
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'VEHICLE SPECIFICATIONS',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildEnhancedInfoRow(
                                'Vehicle Type',
                                vehicle['type'] ?? 'N/A',
                                Icons.category_rounded,
                              ),
                              if (vehicle['capacity_kg'] != null) ...[
                                const SizedBox(height: 16),
                                _buildEnhancedInfoRow(
                                  'Load Capacity',
                                  '${vehicle['capacity_kg']} kg',
                                  Icons.scale_rounded,
                                ),
                              ],
                              if (vehicle['last_maintenance_date'] != null) ...[
                                const SizedBox(height: 16),
                                _buildEnhancedInfoRow(
                                  'Last Maintenance',
                                  _formatDate(vehicle['last_maintenance_date']),
                                  Icons.build_rounded,
                                ),
                              ],
                              if (vehicle['availability'] != null) ...[
                                const SizedBox(height: 16),
                                _buildAvailabilityInfoRow(
                                    vehicle['availability']
                                        as Map<String, dynamic>),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Action buttons with enhanced styling and overflow protection
                        Row(
                          children: [
                            Expanded(
                              child: _buildModernActionButton(
                                'History',
                                Icons.history_rounded,
                                Colors.blue,
                                () => _showMaintenanceHistoryDialog(
                                    context, vehicle),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildModernActionButton(
                                'Edit',
                                Icons.edit_rounded,
                                Colors.orange,
                                () => _showEditVehicleDialog(context, vehicle),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildModernActionButton(
                                'Delete',
                                Icons.delete_rounded,
                                Colors.red,
                                () => _showDeleteConfirmation(context, vehicle),
                                isDestructive: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced info row with icons
  Widget _buildEnhancedInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Availability info row with status indicators
  Widget _buildAvailabilityInfoRow(Map<String, dynamic> availability) {
    final isAvailable = availability['is_available'] as bool;
    final reason = availability['reason'] as String;
    final currentTripRef = availability['current_trip_ref'] as String;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isAvailable) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Available for Assignment';
    } else if (reason == 'maintenance') {
      statusColor = Colors.orange;
      statusIcon = Icons.build_rounded;
      statusText =
          VehicleStatusConfig.getDisplayName(VehicleStatusConfig.maintenance);
    } else if (reason == 'out_of_service') {
      statusColor = Colors.red;
      statusIcon = Icons.block_rounded;
      statusText =
          VehicleStatusConfig.getDisplayName(VehicleStatusConfig.outOfService);
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.block_rounded;
      statusText = 'Currently Assigned';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            statusIcon,
            size: 16,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assignment Status',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (currentTripRef.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Trip: $currentTripRef',
                  style: TextStyle(
                    color: Colors.grey.withOpacity(0.8),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Modern action button with better responsive design
  Widget _buildModernActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(isDestructive ? 0.2 : 0.1),
            color.withOpacity(isDestructive ? 0.1 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Modern loading state
  Widget _buildModernLoadingState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.2),
                  Theme.of(context).primaryColor.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Loading Fleet Data...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we fetch your vehicles',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // Enhanced error state
  Widget _buildEnhancedErrorState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.withOpacity(0.1),
            Colors.red.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red, Colors.red.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _fetchVehicles,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Try Again',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
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
    );
  }

  // Enhanced empty state
  Widget _buildEnhancedEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A2A2A),
            Color(0xFF232323),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.2),
                  Theme.of(context).primaryColor.withOpacity(0.1),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.local_shipping_outlined,
              size: 60,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'No Vehicles in Fleet',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your fleet is empty. Add your first vehicle to get started with fleet management.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.withOpacity(0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          Container(
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
                  color: Theme.of(context).primaryColor.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showAddVehicleDialog(context),
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Add First Vehicle',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value?.toString() ?? 'Not set',
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;

    switch (VehicleStatusConfig.getColorCode(status)) {
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Shared date formatting function
  String _formatDate(dynamic date) {
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}-${dt.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _showAddVehicleDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final plateNumberController = TextEditingController();
    final makeController = TextEditingController();
    final modelController = TextEditingController();
    final capacityController = TextEditingController();

    // Define available truck types
    final availableTruckTypes = [
      '4-Wheeler Truck',
      '6-Wheeler Truck',
      '10-Wheeler Truck',
      '12-Wheeler Truck'
    ];

    String? selectedType = '4-Wheeler Truck';
    String? selectedColor; // Let user choose color

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.transparent,
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
                      Color(0xFF1A1A1A),
                      Color(0xFF0F0F0F),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Enhanced header with gradient
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.15),
                            Theme.of(context).primaryColor.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                        border: Border(
                          bottom: BorderSide(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Enhanced icon with animation
                          Hero(
                            tag: 'add_vehicle_icon',
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Enhanced title section
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add New Vehicle',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Register a new vehicle to your fleet',
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
                    // Enhanced content with better spacing
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Vehicle Information Section
                              _buildSectionTitle('Vehicle Information',
                                  'Basic details about the vehicle'),
                              const SizedBox(height: 20),

                              // Enhanced form fields with icons and better styling
                              _buildEnhancedFormField(
                                label: 'Plate Number',
                                controller: plateNumberController,
                                icon: Icons.confirmation_number_rounded,
                                hintText: 'e.g., ABC-123 or ABC1234',
                                isRequired: true,
                                textCapitalization:
                                    TextCapitalization.characters,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter plate number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildEnhancedFormField(
                                label: 'Brand',
                                controller: makeController,
                                icon: Icons.branding_watermark_rounded,
                                hintText: 'e.g., Isuzu, Fuso, Hino',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter brand';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildEnhancedFormField(
                                label: 'Model',
                                controller: modelController,
                                icon: Icons.precision_manufacturing_rounded,
                                hintText: 'Enter vehicle model',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter model';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 32),

                              // Vehicle Specifications Section
                              _buildSectionTitle('Vehicle Specifications',
                                  'Technical details and capacity'),
                              const SizedBox(height: 20),

                              // Enhanced truck type dropdown
                              _buildEnhancedDropdownField(
                                label: 'Truck Type',
                                value: selectedType,
                                icon: Icons.category_rounded,
                                items: availableTruckTypes,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedType = value;
                                  });
                                },
                                isRequired: true,
                              ),
                              const SizedBox(height: 16),
                              _buildEnhancedFormField(
                                label: 'Capacity (kg)',
                                controller: capacityController,
                                icon: Icons.scale_rounded,
                                hintText: 'e.g., 2950 kg',
                                keyboardType: TextInputType.number,
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter capacity';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              // Color selection dropdown
                              _buildEnhancedColorDropdownField(
                                label: 'Vehicle Color',
                                value: selectedColor,
                                icon: Icons.palette_rounded,
                                colors: _getFallbackColors(),
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedColor = value;
                                  });
                                },
                                isRequired: true,
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Enhanced action buttons
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24)),
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Enhanced cancel button
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).pop(),
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'Cancel',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Enhanced add button
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    if (formKey.currentState!.validate()) {
                                      try {
                                        final vehicleData = {
                                          'plate_number': plateNumberController
                                              .text
                                              .toUpperCase(),
                                          'make': makeController.text,
                                          'model': modelController.text,
                                          'type': selectedType,
                                          'capacity_kg': double.parse(
                                              capacityController.text),
                                          'status': 'Available',
                                          'color': selectedColor,
                                        };

                                        await Supabase.instance.client
                                            .from('vehicles')
                                            .insert(vehicleData);

                                        Navigator.of(context).pop();
                                        _fetchVehicles();
                                        NotificationService.showOperationResult(
                                          context,
                                          operation: 'added',
                                          itemType: 'vehicle',
                                          success: true,
                                        );
                                      } catch (e) {
                                        NotificationService.showOperationResult(
                                          context,
                                          operation: 'added',
                                          itemType: 'vehicle',
                                          success: false,
                                          errorDetails: e.toString(),
                                        );
                                      }
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'Add Vehicle',
                                      textAlign: TextAlign.center,
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Enhanced form field widget
  Widget _buildEnhancedFormField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hintText,
    bool isRequired = false,
    TextInputType? keyboardType,
    TextCapitalization? textCapitalization,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$label${isRequired ? ' *' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2A2A2A),
                Color(0xFF232323),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization ?? TextCapitalization.none,
            validator: validator,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey.withOpacity(0.6),
                fontSize: 12,
              ),
              filled: false,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Enhanced dropdown field widget
  Widget _buildEnhancedDropdownField({
    required String label,
    required String? value,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$label${isRequired ? ' *' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2A2A2A),
                Color(0xFF232323),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            onChanged: onChanged,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
            ),
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).primaryColor,
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            validator: (value) {
              if (isRequired && value == null) {
                return 'Please select $label';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedColorDropdownField({
    required String label,
    required String? value,
    required IconData icon,
    required List<Map<String, dynamic>> colors,
    required void Function(String?) onChanged,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$label${isRequired ? ' *' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2A2A2A),
                Color(0xFF232323),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            onChanged: onChanged,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
            ),
            dropdownColor: const Color(0xFF2A2A2A),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).primaryColor,
            ),
            items: colors.map((colorData) {
              final colorName = colorData['name'] as String;
              return DropdownMenuItem<String>(
                value: colorName,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _getColorFromName(colorName),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                _getColorFromName(colorName).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(colorName),
                  ],
                ),
              );
            }).toList(),
            validator: (value) {
              if (isRequired && value == null) {
                return 'Please select $label';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showEditVehicleDialog(
      BuildContext context, Map<String, dynamic> vehicle) async {
    final formKey = GlobalKey<FormState>();
    final plateNumberController =
        TextEditingController(text: vehicle['plate_number']);
    final makeController = TextEditingController(text: vehicle['make']);
    final modelController = TextEditingController(text: vehicle['model']);
    final capacityController =
        TextEditingController(text: vehicle['capacity_kg']?.toString());

    // Define available truck types
    final availableTruckTypes = [
      '4-Wheeler Truck',
      '6-Wheeler Truck',
      '10-Wheeler Truck',
      '12-Wheeler Truck'
    ];

    // Define available status options
    final availableStatuses = VehicleStatusConfig.allStatuses;

    // Validate and set selectedType to ensure it matches available options
    String? selectedType =
        vehicle['type'] != null && availableTruckTypes.contains(vehicle['type'])
            ? vehicle['type']
            : '4-Wheeler Truck';

    // Validate and set selectedStatus to ensure it matches available options
    String? selectedStatus = vehicle['status'] != null &&
            availableStatuses.contains(vehicle['status'])
        ? vehicle['status']
        : 'Available';

    // Validate and set selectedColor to ensure it matches available options
    final availableColors = _getFallbackColors();
    final availableColorNames =
        availableColors.map((c) => c['name'] as String).toList();
    String? selectedColor = vehicle['color'] != null &&
            availableColorNames.contains(vehicle['color'])
        ? vehicle['color']
        : null; // Let user choose if no existing color

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
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
                              color: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Enhanced Title Section
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit Vehicle',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Update: ${vehicle['plate_number'] ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 12,
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
                    // Content
                    Container(
                      height: 400,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Enhanced form fields with icons and better styling
                              _buildEnhancedFormField(
                                label: 'Plate Number',
                                controller: plateNumberController,
                                icon: Icons.confirmation_number_rounded,
                                hintText: 'e.g., ABC-123 or ABC1234',
                                isRequired: true,
                                textCapitalization:
                                    TextCapitalization.characters,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter plate number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              _buildEnhancedFormField(
                                label: 'Brand',
                                controller: makeController,
                                icon: Icons.branding_watermark_rounded,
                                hintText: 'e.g., Isuzu, Fuso, Hino',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter brand';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              _buildEnhancedFormField(
                                label: 'Model',
                                controller: modelController,
                                icon: Icons.precision_manufacturing_rounded,
                                hintText: 'Enter vehicle model',
                                isRequired: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter model';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              // Enhanced truck type dropdown
                              _buildEnhancedDropdownField(
                                label: 'Truck Type',
                                value: selectedType,
                                icon: Icons.category_rounded,
                                items: availableTruckTypes,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedType = value;
                                  });
                                },
                                isRequired: true,
                              ),
                              const SizedBox(height: 24),
                              _buildEnhancedFormField(
                                label: 'Capacity (kg)',
                                controller: capacityController,
                                icon: Icons.scale_rounded,
                                hintText: 'e.g., 2950 kg',
                                keyboardType: TextInputType.number,
                                isRequired: false,
                              ),
                              const SizedBox(height: 24),
                              // Enhanced status dropdown
                              _buildEnhancedDropdownField(
                                label: 'Status',
                                value: selectedStatus,
                                icon: Icons.info_rounded,
                                items: availableStatuses,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedStatus = value;
                                  });
                                },
                                isRequired: true,
                              ),
                              const SizedBox(height: 24),
                              // Color selection dropdown
                              _buildEnhancedColorDropdownField(
                                label: 'Vehicle Color',
                                value: selectedColor,
                                icon: Icons.palette_rounded,
                                colors: _getFallbackColors(),
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedColor = value;
                                  });
                                },
                                isRequired: true,
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Action Buttons
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (formKey.currentState!.validate()) {
                                  try {
                                    final vehicleData = {
                                      'plate_number': plateNumberController.text
                                          .toUpperCase(),
                                      'make': makeController.text,
                                      'model': modelController.text,
                                      'type': selectedType,
                                      'capacity_kg':
                                          capacityController.text.isNotEmpty
                                              ? double.tryParse(
                                                  capacityController.text)
                                              : null,
                                      'status': selectedStatus,
                                      'color': selectedColor,
                                    };

                                    await Supabase.instance.client
                                        .from('vehicles')
                                        .update(vehicleData)
                                        .eq('id', vehicle['id']);

                                    Navigator.of(context).pop();
                                    _fetchVehicles();
                                    NotificationService.showOperationResult(
                                      context,
                                      operation: 'updated',
                                      itemType: 'vehicle',
                                      success: true,
                                    );
                                  } catch (e) {
                                    NotificationService.showOperationResult(
                                      context,
                                      operation: 'updated',
                                      itemType: 'vehicle',
                                      success: false,
                                      errorDetails: e.toString(),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Update Vehicle'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteConfirmation(
      BuildContext context, Map<String, dynamic> vehicle) async {
    final confirm = await DialogService.showDeleteConfirmationDialog(
      context,
      itemName: 'vehicle',
      customMessage:
          'Are you sure you want to delete ${vehicle['plate_number']}?',
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('vehicles')
            .delete()
            .eq('id', vehicle['id']);

        _fetchVehicles();
        NotificationService.showOperationResult(
          context,
          operation: 'deleted',
          itemType: 'vehicle',
          success: true,
        );
      } catch (e) {
        NotificationService.showOperationResult(
          context,
          operation: 'deleted',
          itemType: 'vehicle',
          success: false,
          errorDetails: e.toString(),
        );
      }
    }
  }

  Future<void> _showMaintenanceHistoryDialog(
      BuildContext context, Map<String, dynamic> vehicle) async {
    // Fetch maintenance history records from the database
    List<Map<String, dynamic>> maintenanceRecords = [];

    try {
      final response = await Supabase.instance.client
          .from('maintenance_history')
          .select('*')
          .eq('vehicle_id', vehicle['id'])
          .order('maintenance_date', ascending: false);

      maintenanceRecords = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching maintenance history: $e');
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enhanced Header with Beautiful Gradient (matching Assign Truck modal)
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
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.history,
                          color: Colors.orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Enhanced Title Section
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Maintenance History',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vehicle['plate_number'] ?? 'Unknown Vehicle',
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
                // Content
                Container(
                  height: 320,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      // Vehicle Info (Non-scrollable)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vehicle Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow('Make:', vehicle['make'] ?? 'N/A'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Model:', vehicle['model'] ?? 'N/A'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Type:', vehicle['type'] ?? 'N/A'),
                            const SizedBox(height: 8),
                            if (vehicle['capacity_kg'] != null) ...[
                              _buildInfoRow(
                                  'Capacity:', '${vehicle['capacity_kg']} kg'),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Maintenance History Header (Non-scrollable)
                      Row(
                        children: [
                          const Expanded(
                            flex: 3,
                            child: Text(
                              'Maintenance Records',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${maintenanceRecords.length} records',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Maintenance records list - ONLY THIS PART IS SCROLLABLE
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.2),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                if (maintenanceRecords.isNotEmpty) ...[
                                  ...maintenanceRecords.map((record) =>
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.orange
                                                  .withOpacity(0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.build,
                                                    color: Colors.orange,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    record['maintenance_type'] ??
                                                        'General Maintenance',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.orange,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  flex: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green
                                                          .withOpacity(0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Text(
                                                      record['status'] ??
                                                          'Available',
                                                      style: const TextStyle(
                                                        color: Colors.green,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Date: ${_formatDate(record['maintenance_date'])}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            if (record['description'] !=
                                                null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Description: ${record['description']}',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                            ],
                                            if (record['performed_by'] !=
                                                null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Performed by: ${record['performed_by']}',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                            if (record['cost'] != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Cost: \$${record['cost']}',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ],
                                        ),
                                      )),
                                ] else ...[
                                  // Show "No records found" message at the top of the scrollable area
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.only(
                                        top: 8,
                                        left: 16,
                                        right: 16,
                                        bottom: 16),
                                    child: const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(Icons.info_outline,
                                            color: Colors.grey, size: 18),
                                        SizedBox(height: 8),
                                        Text(
                                          'No maintenance records found',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
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
                    ],
                  ),
                ),
                // Action Buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method for section titles
  Widget _buildSectionTitle(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Color helper methods
  List<Map<String, dynamic>> _getFallbackColors() {
    return [
      {'id': 1, 'name': 'Red', 'hex_code': '#FF0000'},
      {'id': 2, 'name': 'Blue', 'hex_code': '#0000FF'},
      {'id': 3, 'name': 'Green', 'hex_code': '#00FF00'},
      {'id': 4, 'name': 'Yellow', 'hex_code': '#FFFF00'},
      {'id': 5, 'name': 'Orange', 'hex_code': '#FFA500'},
      {'id': 6, 'name': 'Purple', 'hex_code': '#800080'},
      {'id': 7, 'name': 'Pink', 'hex_code': '#FFC0CB'},
      {'id': 8, 'name': 'Brown', 'hex_code': '#A52A2A'},
      {'id': 9, 'name': 'White', 'hex_code': '#FFFFFF'},
    ];
  }

  Color _getColorFromName(String? colorName) {
    if (colorName == null || colorName.isEmpty) return Colors.grey;

    final colors = _getFallbackColors();
    final colorData = colors.firstWhere(
      (color) =>
          color['name'].toString().toLowerCase() == colorName.toLowerCase(),
      orElse: () => {'hex_code': '#808080'}, // Default to grey
    );

    final hexCode = colorData['hex_code'] as String;
    return Color(int.parse(hexCode.substring(1), radix: 16) + 0xFF000000);
  }
}
