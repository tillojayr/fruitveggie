import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// SMS Service for sending text messages via an API
class SmsService {
  /// API endpoint for sending SMS messages
  final String _apiUrl;
  
  /// API token for authentication
  final String _apiToken;

  /// Constructor requiring API URL and token
  SmsService({required String apiUrl, required String apiToken})
      : _apiUrl = apiUrl,
        _apiToken = apiToken;

  /// Factory constructor that loads the API token from shared preferences
  static Future<SmsService> create() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('sms_api_url') ?? 'https://api.example.com/sms';
      final apiToken = prefs.getString('sms_api_token') ?? '';

      // For security, in debug mode, log a warning if no token is set
      if (apiToken.isEmpty && kDebugMode) {
        debugPrint(
            'WARNING: No SMS API token found. Please set one in the app settings.');
      }

      return SmsService(apiUrl: apiUrl, apiToken: apiToken);
    } catch (e) {
      debugPrint('Error creating SmsService: $e');
      // Return a service with default values if there's an error
      return SmsService(
          apiUrl: 'https://api.example.com/sms', apiToken: '');
    }
  }

  /// Set the API token and save it to SharedPreferences
  Future<void> setApiToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sms_api_token', token);
    } catch (e) {
      debugPrint('Error saving SMS API token: $e');
    }
  }

  /// Set the API URL and save it to SharedPreferences
  Future<void> setApiUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sms_api_url', url);
    } catch (e) {
      debugPrint('Error saving SMS API URL: $e');
    }
  }

  /// Send an SMS message to the provided recipient
  /// 
  /// [message] The text message to send
  /// [recipient] The phone number to send the message to (in E.164 format, e.g. +15551234567)
  /// Returns a Future that completes with a bool indicating success or failure
  Future<bool> sendSms({required String message, required String recipient}) async {
    if (_apiToken.isEmpty) {
      debugPrint('Error: SMS API token is not set');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiToken',
        },
        body: jsonEncode({
          'to': recipient,
          'message': message,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('SMS sent successfully to $recipient');
        return true;
      } else {
        debugPrint('Failed to send SMS: ${response.statusCode}, ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending SMS: $e');
      return false;
    }
  }
  
  /// Send a batch of SMS messages to multiple recipients
  /// 
  /// [message] The text message to send to all recipients
  /// [recipients] List of phone numbers to send the message to
  /// Returns a Future that completes with a map of recipient to success/failure status
  Future<Map<String, bool>> sendBatchSms({
    required String message,
    required List<String> recipients,
  }) async {
    if (_apiToken.isEmpty) {
      debugPrint('Error: SMS API token is not set');
      return {for (var recipient in recipients) recipient: false};
    }

    Map<String, bool> results = {};

    // Process each recipient
    for (final recipient in recipients) {
      try {
        final response = await http.post(
          Uri.parse(_apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiToken',
          },
          body: jsonEncode({
            'to': recipient,
            'message': message,
          }),
        );

        results[recipient] = response.statusCode >= 200 && response.statusCode < 300;
      } catch (e) {
        debugPrint('Error sending SMS to $recipient: $e');
        results[recipient] = false;
      }
    }

    return results;
  }

  /// Check if the SMS service is properly configured
  /// Returns true if the API token is set
  bool isConfigured() {
    return _apiToken.isNotEmpty;
  }
}
