import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_service.dart';
import 'notification_service.dart';

/// Example integration class showing how the SMS service can be used alongside notifications
class SmsIntegrationExample {
  final NotificationService _notificationService = NotificationService();

  /// Example method demonstrating how to send both a notification and SMS
  /// for a harvest reminder
  Future<void> sendHarvestReminder({
    required String produceType, 
    required String phoneNumber,
    required String message,
    String? imageUrl,
  }) async {
    // Check if SMS notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final smsEnabled = prefs.getBool('sms_notifications_enabled') ?? false;
    
    // Always schedule a local notification
    final notificationId = DateTime.now().millisecondsSinceEpoch % 0x3FFFFFFF;
    _notificationService.showNotification(
      id: notificationId,
      title: 'Harvest Time!', 
      body: 'Your $produceType is ready to harvest',
      imageUrl: imageUrl,
    );
    
    // Optionally send an SMS if enabled and phone number is provided
    if (smsEnabled && phoneNumber.isNotEmpty) {
      final smsService = await SmsService.create();
      if (smsService.isConfigured()) {
        final success = await smsService.sendSms(
          message: message,
          recipient: phoneNumber,
        );
        
        debugPrint('SMS notification ${success ? 'sent' : 'failed'} to $phoneNumber');
      } else {
        debugPrint('SMS service not properly configured');
      }
    }
  }
  
  /// Example method demonstrating batch SMS notifications
  Future<void> sendBatchHarvestReminders({
    required List<Map<String, String>> recipients,
    required String message,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final smsEnabled = prefs.getBool('sms_notifications_enabled') ?? false;
    
    if (smsEnabled && recipients.isNotEmpty) {
      final smsService = await SmsService.create();
      if (smsService.isConfigured()) {
        // Extract just the phone numbers
        final phoneNumbers = recipients.map((r) => r['phoneNumber'] ?? '').toList();
        
        // Filter out any empty phone numbers
        final validPhoneNumbers = phoneNumbers.where((p) => p.isNotEmpty).toList();
        
        if (validPhoneNumbers.isNotEmpty) {
          final results = await smsService.sendBatchSms(
            message: message,
            recipients: validPhoneNumbers,
          );
          
          // Log results
          results.forEach((recipient, success) {
            debugPrint('Batch SMS to $recipient: ${success ? 'sent' : 'failed'}');
          });
        }
      }
    }
  }
  
  /// Example method to check if the SMS service is properly configured
  Future<bool> isSmsServiceConfigured() async {
    final smsService = await SmsService.create();
    return smsService.isConfigured();
  }
  
  /// Example method to toggle SMS notifications on/off
  Future<bool> toggleSmsNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final currentValue = prefs.getBool('sms_notifications_enabled') ?? false;
    final newValue = !currentValue;
    await prefs.setBool('sms_notifications_enabled', newValue);
    return newValue;
  }
  
  /// Example method to update SMS service configuration
  Future<void> updateSmsServiceConfig({
    required String apiUrl,
    required String apiToken,
  }) async {
    final smsService = await SmsService.create();
    await smsService.setApiUrl(apiUrl);
    await smsService.setApiToken(apiToken);
  }
}
