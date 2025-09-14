import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'dart:async';

class NotificationStatusCard extends StatefulWidget {
  const NotificationStatusCard({super.key});

  @override
  State<NotificationStatusCard> createState() => _NotificationStatusCardState();
}

class _NotificationStatusCardState extends State<NotificationStatusCard> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _checkNotificationStatus();

    // Set up periodic refresh of status
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkNotificationStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNotificationStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await NotificationService().verifyNotificationStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = {
            'errors': ['Failed to check notification status: $e'],
            'isInitialized': false,
          };
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // Refresh status after requesting
      _checkNotificationStatus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request permissions: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        elevation: 2,
        margin: const EdgeInsets.all(16),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final hasErrors =
        _status?['errors'] != null && (_status?['errors'] as List).isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      color: hasErrors ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasErrors ? Icons.error : Icons.check_circle,
                  color: hasErrors ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  'Notification Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _checkNotificationStatus,
                  tooltip: 'Refresh status',
                ),
              ],
            ),
            const Divider(),
            _buildStatusInfo(),
            if (hasErrors) ...[
              const SizedBox(height: 8),
              _buildErrorsList(),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _requestPermissions,
              child: const Text('Request Notification Permissions'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusRow('Initialized', _status?['isInitialized'] ?? false),
        _buildStatusRow(
            'Permission', _status?['permissionStatus'] ?? 'Unknown'),
        _buildStatusRow('FCM Token', _status?['hasToken'] ?? false),
        _buildStatusRow(
            'Token in Firestore', _status?['tokenInFirestore'] ?? false),
        _buildStatusRow(
            'Test Notification', _status?['testNotificationSent'] ?? false),
      ],
    );
  }

  Widget _buildStatusRow(String label, dynamic value) {
    final isOk = value == true || value == 'AuthorizationStatus.authorized';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.error,
            color: isOk ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.toString(),
              style: TextStyle(
                color: isOk ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorsList() {
    final errors = _status?['errors'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Issues (${errors.length}):',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 4),
        ...errors.map((error) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(error.toString())),
                ],
              ),
            )),
      ],
    );
  }
}
