import 'package:flutter/material.dart';
import '../../widgets/overdue_trip_manager_widget.dart';

/// Page for managing overdue trips
class OverdueTripsPage extends StatelessWidget {
  const OverdueTripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Page header
            Container(
              margin: const EdgeInsets.all(16),
              child: Card(
                elevation: 4,
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Overdue Trip Management',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Monitor and manage trips that are overdue to start or complete',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Info cards
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.yellow.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.yellow, width: 1),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.play_circle_outline,
                                      color: Colors.yellow, size: 24),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Not Started',
                                    style: TextStyle(
                                      color: Colors.yellow,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Trips 10+ min overdue to start',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.orange, width: 1),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.flag_outlined,
                                      color: Colors.orange, size: 24),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Not Completed',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Trips 15+ min overdue to complete',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Overdue trip manager widget
            const OverdueTripManagerWidget(),

            // Additional actions card
            Container(
              margin: const EdgeInsets.all(16),
              child: Card(
                elevation: 4,
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Action items
                      _buildActionItem(
                        icon: Icons.notification_important,
                        title: 'Send Urgent Reminder',
                        description:
                            'Send high-priority push notification to driver',
                        color: Colors.orange,
                      ),

                      const SizedBox(height: 8),

                      _buildActionItem(
                        icon: Icons.swap_horiz,
                        title: 'Reassign Trip',
                        description:
                            'Transfer trip to a different available driver',
                        color: Colors.blue,
                      ),

                      const SizedBox(height: 8),

                      _buildActionItem(
                        icon: Icons.phone,
                        title: 'Call Driver',
                        description:
                            'Direct phone contact with the assigned driver',
                        color: Colors.green,
                      ),

                      const SizedBox(height: 8),

                      _buildActionItem(
                        icon: Icons.cancel,
                        title: 'Cancel Trip',
                        description:
                            'Cancel overdue trip and notify relevant parties',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom padding
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
