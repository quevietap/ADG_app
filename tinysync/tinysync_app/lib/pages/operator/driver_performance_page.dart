import 'package:flutter/material.dart';
import '../../models/driver_performance.dart';
import '../../services/supabase_service.dart';

class DriverPerformancePage extends StatefulWidget {
  const DriverPerformancePage({super.key});

  @override
  State<DriverPerformancePage> createState() => _DriverPerformancePageState();
}

class _DriverPerformancePageState extends State<DriverPerformancePage> {
  final SupabaseService _supabaseService = SupabaseService();
  List<DriverPerformance> _drivers = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // all, excellent, good, needs_improvement

  @override
  void initState() {
    super.initState();
    _loadDriverPerformance();
  }

  Future<void> _loadDriverPerformance() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final drivers = await _supabaseService.getDriverPerformance();
      setState(() {
        _drivers = drivers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<DriverPerformance> get _filteredDrivers {
    switch (_selectedFilter) {
      case 'excellent':
        return _drivers.where((d) => d.performanceRating >= 4.0).toList();
      case 'good':
        return _drivers.where((d) => d.performanceRating >= 3.0 && d.performanceRating < 4.0).toList();
      case 'needs_improvement':
        return _drivers.where((d) => d.performanceRating < 3.0).toList();
      default:
        return _drivers;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Performance'),
        actions: [
          IconButton(
            onPressed: _loadDriverPerformance,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildFilterChip('All', 'all'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip('Excellent', 'excellent'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip('Good', 'good'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip('Needs Improvement', 'needs_improvement'),
                ),
              ],
            ),
          ),

          // Performance Summary
          _buildPerformanceSummary(),

          // Driver List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDrivers.isEmpty
                    ? const Center(
                        child: Text(
                          'No drivers found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredDrivers.length,
                        itemBuilder: (context, index) {
                          final driver = _filteredDrivers[index];
                          return _buildDriverCard(driver);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      backgroundColor: Colors.grey.withValues(alpha: 0.1),
      selectedColor: Colors.blue.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildPerformanceSummary() {
    final totalDrivers = _drivers.length;
    final excellentDrivers = _drivers.where((d) => d.performanceRating >= 4.0).length;
    final goodDrivers = _drivers.where((d) => d.performanceRating >= 3.0 && d.performanceRating < 4.0).length;
    final needsImprovementDrivers = _drivers.where((d) => d.performanceRating < 3.0).length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Performance Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Total Drivers',
                    totalDrivers.toString(),
                    Icons.people,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Excellent',
                    excellentDrivers.toString(),
                    Icons.star,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Good',
                    goodDrivers.toString(),
                    Icons.star_half,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Needs Improvement',
                    needsImprovementDrivers.toString(),
                    Icons.warning,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDriverCard(DriverPerformance driver) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver Header
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: driver.profileImage != null
                      ? NetworkImage(driver.profileImage!)
                      : null,
                  child: driver.profileImage == null
                      ? Text(driver.name[0])
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        driver.licenseNumber,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Performance Rating
                Column(
                  children: [
                    _buildStarRating(driver.performanceRating),
                    Text(
                      driver.performanceLevel,
                      style: TextStyle(
                        color: driver.performanceColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Performance Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Safety Score',
                    '${driver.safetyScore}%',
                    Icons.shield,
                    _getSafetyColor(driver.safetyScore),
                    driver.safetyLevel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Behavior Score',
                    '${driver.behaviorScore}%',
                    Icons.psychology,
                    _getBehaviorColor(driver.behaviorScore),
                    driver.behaviorLevel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Sessions',
                    '${driver.totalSessions}',
                    Icons.timer,
                    Colors.blue,
                    'Total',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Recent Behaviors
            if (driver.recentBehaviors.isNotEmpty) ...[
              const Text(
                'Recent Behaviors:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: driver.recentBehaviors
                    .take(3)
                    .map((behavior) => Chip(
                          label: Text(
                            behavior,
                            style: const TextStyle(fontSize: 10),
                          ),
                          backgroundColor: Colors.orange.withValues(alpha: 0.2),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],

            // Action Buttons
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRatingDialog(driver),
                    icon: const Icon(Icons.rate_review, size: 16),
                    label: const Text('Rate Driver'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDriverDetails(driver),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 16,
        );
      }),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, String level) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
          Text(
            level,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSafetyColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Color _getBehaviorColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  void _showRatingDialog(DriverPerformance driver) {
    int rating = driver.operatorRating;
    String notes = driver.operatorNotes ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate ${driver.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Star Rating
            StatefulBuilder(
              builder: (context, setState) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    onPressed: () {
                      setState(() {
                        rating = index + 1;
                      });
                    },
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            // Notes
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (value) => notes = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _supabaseService.rateDriver(driver.id, rating, notes);
              Navigator.of(context).pop();
              _loadDriverPerformance(); // Refresh data
            },
            child: const Text('Save Rating'),
          ),
        ],
      ),
    );
  }

  void _showDriverDetails(DriverPerformance driver) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${driver.name} Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('License: ${driver.licenseNumber}'),
              const SizedBox(height: 8),
              Text('Performance Rating: ${driver.performanceRating.toStringAsFixed(1)}/5'),
              Text('Safety Score: ${driver.safetyScore}%'),
              Text('Behavior Score: ${driver.behaviorScore}%'),
              Text('Total Sessions: ${driver.totalSessions}'),
              Text('Total Behaviors: ${driver.totalBehaviors}'),
              const SizedBox(height: 8),
              if (driver.operatorNotes != null) ...[
                const Text('Operator Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(driver.operatorNotes!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
