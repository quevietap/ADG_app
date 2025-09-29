import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';

/// Dialog for managing overdue trip actions
class OverdueTripActionDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final VoidCallback? onActionTaken;

  const OverdueTripActionDialog({
    super.key,
    required this.trip,
    this.onActionTaken,
  });

  @override
  State<OverdueTripActionDialog> createState() =>
      _OverdueTripActionDialogState();
}

class _OverdueTripActionDialogState extends State<OverdueTripActionDialog> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableDrivers = [];
  String? _selectedDriverId;
  String? _selectedReassignReason;
  final TextEditingController _notesController = TextEditingController();

  final List<String> _reassignReasons = [
    'Driver not responding',
    'Driver reported unavailable',
    'Vehicle breakdown',
    'Traffic/route issues',
    'Emergency situation',
    'Other operational reason',
  ];

  @override
  void initState() {
    super.initState();
    _loadAvailableDrivers();
  }

  /// Load available drivers for reassignment
  Future<void> _loadAvailableDrivers() async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('id, first_name, last_name, phone')
          .eq('role', 'driver')
          .eq('is_active', true)
          .neq('id', widget.trip['users']['id']); // Exclude current driver

      setState(() {
        _availableDrivers = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('❌ Error loading available drivers: $e');
    }
  }

  /// Send reminder notification to current driver
  Future<void> _sendReminderToDriver() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final driver = widget.trip['users'];
      final driverName = '${driver['first_name']} ${driver['last_name']}';
      final tripRef = widget.trip['trip_ref_number'];
      final overdueType = widget.trip['overdue_type'];

      String title, message;
      if (overdueType == 'not_started') {
        title = '🚨 Urgent: Trip Start Required';
        message =
            'Your trip $tripRef is overdue to start. Please start the trip immediately or contact dispatch.';
      } else {
        title = '🚨 Urgent: Trip Completion Required';
        message =
            'Your trip $tripRef is overdue for completion. Please complete the trip or contact dispatch.';
      }

      // Send notification
      await NotificationService().sendDriverReminder(
        driverId: driver['id'],
        tripId: widget.trip['id'],
        title: title,
        message: message,
        urgency: 'high',
      );

      // Log the reminder action
      await Supabase.instance.client.from('trip_actions').insert({
        'trip_id': widget.trip['id'],
        'action_type': 'reminder_sent',
        'action_details': {
          'driver_name': driverName,
          'overdue_type': overdueType,
          'minutes_overdue': widget.trip['minutes_overdue'],
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onActionTaken?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Urgent reminder sent to $driverName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error sending reminder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Reassign trip to different driver
  Future<void> _reassignTrip() async {
    if (_selectedDriverId == null || _selectedReassignReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a driver and reason'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final oldDriver = widget.trip['users'];
      final newDriver = _availableDrivers.firstWhere(
        (d) => d['id'] == _selectedDriverId,
      );

      final oldDriverName =
          '${oldDriver['first_name']} ${oldDriver['last_name']}';
      final newDriverName =
          '${newDriver['first_name']} ${newDriver['last_name']}';

      // Update trip assignment
      await Supabase.instance.client.from('trips').update({
        'driver_id': _selectedDriverId,
        'status': 'assigned', // Reset to assigned status
        'reassignment_reason': _selectedReassignReason,
        'reassignment_notes': _notesController.text,
        'reassigned_at': DateTime.now().toIso8601String(),
        'original_driver_id': oldDriver['id'],
      }).eq('id', widget.trip['id']);

      // Send notification to new driver
      final startTime = DateTime.parse(widget.trip['start_time']);
      await NotificationService().sendTripAssignmentNotification(
        driverId: _selectedDriverId!,
        tripId: widget.trip['id'],
        tripRefNumber: widget.trip['trip_ref_number'],
        origin: widget.trip['origin'],
        destination: widget.trip['destination'],
        startTime: startTime,
      );

      // Send notification to old driver
      await NotificationService().sendTripReassignmentNotification(
        driverId: oldDriver['id'],
        tripId: widget.trip['id'],
        tripRefNumber: widget.trip['trip_ref_number'],
        reason: _selectedReassignReason!,
        newDriverName: newDriverName,
      );

      // Log the reassignment action
      await Supabase.instance.client.from('trip_actions').insert({
        'trip_id': widget.trip['id'],
        'action_type': 'trip_reassigned',
        'action_details': {
          'old_driver_name': oldDriverName,
          'new_driver_name': newDriverName,
          'reason': _selectedReassignReason,
          'notes': _notesController.text,
          'overdue_minutes': widget.trip['minutes_overdue'],
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onActionTaken?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Trip reassigned from $oldDriverName to $newDriverName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error reassigning trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reassigning trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Cancel overdue trip
  Future<void> _cancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Trip'),
        content: const Text(
          'Are you sure you want to cancel this overdue trip? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Trip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.from('trips').update({
        'status': 'cancelled',
        'cancellation_reason': 'Overdue - cancelled by operator',
        'cancelled_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.trip['id']);

      // Notify driver
      final driver = widget.trip['users'];
      await NotificationService().sendTripCancellationNotification(
        driverId: driver['id'],
        tripId: widget.trip['id'],
        tripRefNumber: widget.trip['trip_ref_number'],
        reason: 'Trip was overdue and cancelled by operations',
      );

      // Log the cancellation
      await Supabase.instance.client.from('trip_actions').insert({
        'trip_id': widget.trip['id'],
        'action_type': 'trip_cancelled',
        'action_details': {
          'reason': 'Overdue - cancelled by operator',
          'minutes_overdue': widget.trip['minutes_overdue'],
          'driver_name': '${driver['first_name']} ${driver['last_name']}',
        },
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        widget.onActionTaken?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip has been cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ Error cancelling trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.trip['users'];
    final driverName = '${driver['first_name']} ${driver['last_name']}';
    final tripRef = widget.trip['trip_ref_number'];
    final overdueType = widget.trip['overdue_type'];
    final minutesOverdue = widget.trip['minutes_overdue'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  overdueType == 'not_started'
                      ? Icons.play_circle_outline
                      : Icons.flag_outlined,
                  color: Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Overdue Trip',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$tripRef • $driverName • $minutesOverdue min overdue',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action buttons
                  const Text(
                    'Available Actions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),

                  // Send reminder button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sendReminderToDriver,
                      icon: const Icon(Icons.notification_important),
                      label: const Text('Send Urgent Reminder to Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Reassign trip section
                  ExpansionTile(
                    title: const Text('Reassign to Different Driver'),
                    leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                    children: [
                      // Driver selection
                      if (_availableDrivers.isNotEmpty) ...[
                        const Text('Select new driver:'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedDriverId,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Choose driver...',
                          ),
                          items: _availableDrivers.map((driver) {
                            return DropdownMenuItem<String>(
                              value: driver['id'],
                              child: Text(
                                  '${driver['first_name']} ${driver['last_name']}'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedDriverId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Reason selection
                        const Text('Reassignment reason:'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedReassignReason,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Select reason...',
                          ),
                          items: _reassignReasons.map((reason) {
                            return DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedReassignReason = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Notes
                        TextField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Additional notes (optional)',
                            hintText: 'Add any relevant details...',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),

                        // Reassign button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _reassignTrip,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Reassign Trip'),
                          ),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No other drivers available for reassignment',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Cancel trip button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _cancelTrip,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel Trip'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // Close button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
