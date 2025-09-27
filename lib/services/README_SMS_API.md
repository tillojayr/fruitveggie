# SMS Service

## Overview
The SMS Service provides functionality to send SMS messages through an external API service. 
This document outlines how to configure and use the service in the FruitVeggie app.

## Configuration
The SMS service requires an API URL and token to function properly. These can be set in one of two ways:

1. **Through the app settings** (recommended)
2. **Through code** using the `setApiToken()` and `setApiUrl()` methods

The service stores these credentials in SharedPreferences for persistence.

## Usage

### Basic Usage
```dart
// Get instance of the SMS service
final smsService = await SmsService.create();

// Send a simple message
bool success = await smsService.sendSms(
  message: 'Your produce is ready for harvest!',
  recipient: '+15551234567'
);

if (success) {
  print('Message sent successfully');
} else {
  print('Failed to send message');
}
```

### Batch Messaging
```dart
// Send the same message to multiple recipients
final recipients = ['+15551234567', '+15557654321'];
Map<String, bool> results = await smsService.sendBatchSms(
  message: 'Your produce is ready for harvest!',
  recipients: recipients
);

// Check individual results
results.forEach((recipient, success) {
  print('Message to $recipient: ${success ? "sent" : "failed"}');
});
```

## API Requirements
The SMS service is designed to work with RESTful APIs that accept:
- POST requests to the specified endpoint
- JSON body with `to` and `message` fields
- Authorization via Bearer token

## Example Integration with Harvest Notifications
```dart
void scheduleHarvestNotification(String produceType, DateTime harvestDate, String phoneNumber) {
  // Schedule a local notification
  notificationService.scheduleNotification(
    title: 'Harvest Time!',
    body: 'Your $produceType is ready to be harvested.',
    scheduledDate: harvestDate,
  );
  
  // Also send an SMS notification if enabled and a phone number is available
  if (phoneNumber.isNotEmpty) {
    SmsService.create().then((smsService) {
      if (smsService.isConfigured()) {
        smsService.sendSms(
          message: 'Your $produceType is ready to be harvested!',
          recipient: phoneNumber
        );
      }
    });
  }
}
```

## Error Handling
The service handles and logs errors appropriately:
- Missing API token
- Network errors
- API response errors

Always check the return value of `sendSms()` to handle potential failures in your UI.
