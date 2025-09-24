import 'package:flutter/material.dart';
import '../services/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmsServiceSettings extends StatefulWidget {
  const SmsServiceSettings({super.key});

  @override
  State<SmsServiceSettings> createState() => _SmsServiceSettingsState();
}

class _SmsServiceSettingsState extends State<SmsServiceSettings> {
  final _formKey = GlobalKey<FormState>();
  final _apiUrlController = TextEditingController();
  final _apiTokenController = TextEditingController();
  bool _smsEnabled = false;
  bool _isLoading = true;
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('sms_api_url') ?? 'https://api.example.com/sms';
      final apiToken = prefs.getString('sms_api_token') ?? '';
      final smsEnabled = prefs.getBool('sms_notifications_enabled') ?? false;

      setState(() {
        _apiUrlController.text = apiUrl;
        _apiTokenController.text = apiToken;
        _smsEnabled = smsEnabled;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading SMS settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final smsService = await SmsService.create();
      await smsService.setApiUrl(_apiUrlController.text.trim());
      await smsService.setApiToken(_apiTokenController.text.trim());

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sms_notifications_enabled', _smsEnabled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving SMS settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
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
  void dispose() {
    _apiUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SMS Notifications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _smsEnabled,
                  activeColor: const Color(0xFF4CAF50),
                  onChanged: (value) {
                    setState(() {
                      _smsEnabled = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiUrlController,
              decoration: InputDecoration(
                labelText: 'SMS API URL',
                hintText: 'https://api.example.com/sms',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (_smsEnabled && (value == null || value.isEmpty)) {
                  return 'Please enter an API URL';
                }
                return null;
              },
              enabled: _smsEnabled,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiTokenController,
              decoration: InputDecoration(
                labelText: 'API Token',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                suffixIcon: IconButton(
                  icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _isObscured = !_isObscured;
                    });
                  },
                ),
              ),
              obscureText: _isObscured,
              validator: (value) {
                if (_smsEnabled && (value == null || value.isEmpty)) {
                  return 'Please enter an API token';
                }
                return null;
              },
              enabled: _smsEnabled,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _smsEnabled ? _saveSettings : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text('Save SMS Settings'),
              ),
            ),
            if (_smsEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                'Note: SMS charges may apply depending on your service provider.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
