import 'package:flutter/material.dart';
import '../services/sms_service.dart';
import '../widgets/sms_service_settings.dart';

class SmsServiceDemo extends StatefulWidget {
  const SmsServiceDemo({super.key});

  @override
  State<SmsServiceDemo> createState() => _SmsServiceDemoState();
}

class _SmsServiceDemoState extends State<SmsServiceDemo> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  bool _isConfigured = false;
  bool _isSending = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    final smsService = await SmsService.create();
    setState(() {
      _isConfigured = smsService.isConfigured();
      _statusMessage = _isConfigured
          ? 'SMS service is configured and ready'
          : 'SMS service is not configured';
    });
  }

  Future<void> _sendTestSms() async {
    if (_messageController.text.isEmpty || _recipientController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter both message and recipient';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = 'Sending SMS...';
    });

    try {
      final smsService = await SmsService.create();
      
      if (!smsService.isConfigured()) {
        setState(() {
          _statusMessage = 'SMS service is not configured';
          _isSending = false;
        });
        return;
      }
      
      final success = await smsService.sendSms(
        message: _messageController.text.trim(),
        recipient: _recipientController.text.trim(),
      );
      
      setState(() {
        _statusMessage = success
            ? 'SMS sent successfully'
            : 'Failed to send SMS';
        _isSending = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isSending = false;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Service Demo'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SMS Service Configuration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Settings widget
            const SmsServiceSettings(),
            
            const SizedBox(height: 32),
            const Text(
              'Test SMS Messaging',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Status indicator
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _isConfigured ? Colors.green.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: _isConfigured ? Colors.green.shade800 : Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Message and recipient input fields
            TextField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              maxLines: 3,
              enabled: _isConfigured && !_isSending,
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _recipientController,
              decoration: InputDecoration(
                labelText: 'Recipient Phone Number',
                hintText: '+15551234567',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              keyboardType: TextInputType.phone,
              enabled: _isConfigured && !_isSending,
            ),
            
            const SizedBox(height: 24),
            
            // Send button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isConfigured && !_isSending) ? _sendTestSms : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Send Test Message'),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Refresh configuration button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _checkConfiguration,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Configuration Status'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text(
              'Note: This is a demo page for testing the SMS service. In a real app, you would integrate the SMS service with your notification system.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
