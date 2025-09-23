import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:typed_data';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // Replace Set with Map to include timestamps for expiration
  static final Map<String, DateTime> _recentlyScheduledReminders = {};

  // Track recently shown notification IDs to prevent rapid duplicates
  static final Map<int, DateTime> _recentlyShownNotifications = {};

  // Flag to track if we've checked for today's reminders yet
  bool _hasTodayRemindersBeenChecked = false;

  // Timer for periodic reminder checks
  Timer? _periodicReminderCheckTimer;

  // Track when we last checked for reminders
  DateTime? _lastReminderCheck;

  // Start periodic check for reminders (called when app is in foreground)
  void startPeriodicReminderCheck() {
    // Cancel any existing timer
    _periodicReminderCheckTimer?.cancel();

    // Check immediately
    checkTodayReminders();

    // Set up timer to check every 30 minutes
    _periodicReminderCheckTimer =
        Timer.periodic(const Duration(minutes: 30), (timer) {
      debugPrint('Performing periodic reminder check');
      checkTodayReminders();
    });

    debugPrint('Started periodic reminder checks');
  }

  // Stop periodic reminder checks (called when app is in background)
  void stopPeriodicReminderCheck() {
    _periodicReminderCheckTimer?.cancel();
    _periodicReminderCheckTimer = null;
    debugPrint('Stopped periodic reminder checks');
  }

  // Add a method to generate a unique key for a reminder
  String _getReminderKey(String produceType, String scanId) {
    return '$produceType:$scanId';
  }

  // Improved cleanup method that removes entries older than 5 minutes
  void _cleanupRecentReminders() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    // Find keys older than 5 minutes
    _recentlyScheduledReminders.forEach((key, timestamp) {
      if (now.difference(timestamp).inMinutes >= 5) {
        expiredKeys.add(key);
      }
    });

    // Remove expired keys
    for (final key in expiredKeys) {
      _recentlyScheduledReminders.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      debugPrint(
          'NotificationService: Removed ${expiredKeys.length} expired reminders from tracking cache');
    }
  }

  // Initialize notification services
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permission for iOS devices
      if (Platform.isIOS) {
        await _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Initialize local notifications
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final bool? initialized = await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized != null && initialized) {
        debugPrint('Local notifications initialized successfully');
      } else {
        debugPrint('Local notifications initialization may have failed');
      }

      // Set up notification channels for Android
      await _setupNotificationChannels();

      // Configure Firebase Messaging handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp
          .listen(_handleBackgroundMessageOpened);

      // Listen for token refreshes
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM token refreshed, updating in Firestore');
        _updateFCMToken(newToken: newToken);
      });

      // Get FCM token for the device
      await _updateFCMToken();

      // Test notifications are working
      await _testNotification();

      _isInitialized = true;
      debugPrint('NotificationService: Initialized successfully');

      // Check for any reminder notifications due today
      checkTodayReminders();

      // Start periodic reminder checking
      startPeriodicReminderCheck();
    } catch (e) {
      debugPrint('NotificationService: Initialization failed: $e');
      // Don't set _isInitialized to true so we can retry later
    }
  }

  // Set up notification channels for Android
  Future<void> _setupNotificationChannels() async {
    try {
      // Create a notification channel for Android
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        'harvest_channel',
        'Harvest Reminders',
        description: 'Notifications for produce harvest reminders',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      );

      // Create a special high-priority channel for exact harvest date notifications
      final AndroidNotificationChannel harvestDayChannel =
          AndroidNotificationChannel(
        'harvest_day_channel',
        'Harvest Day Alerts',
        description: 'High priority alerts for produce ready to harvest today',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
        showBadge: true,
      );

      // Register the channels with the system
      final androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(channel);
        await androidImplementation
            .createNotificationChannel(harvestDayChannel);
        debugPrint(
            'NotificationService: Notification channels created successfully');
      } else {
        debugPrint('NotificationService: Android implementation not available');
      }
    } catch (e) {
      debugPrint(
          'NotificationService: Failed to create notification channel: $e');
    }
  }

  // Test notification delivery
  Future<void> _testNotification() async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'harvest_channel',
        'Harvest Reminders',
        channelDescription: 'Notifications for produce harvest reminders',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFF2E7D32),
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show a test notification to verify it's working
      await _localNotifications.show(
        0, // Use ID 0 for test notification
        'Notification Test',
        'Notifications are working correctly!',
        details,
      );

      debugPrint('NotificationService: Test notification sent successfully');
      return;
    } catch (e) {
      debugPrint('NotificationService: Failed to send test notification: $e');
    }
  }

  // Update FCM token in Firestore
  Future<void> _updateFCMToken({String? newToken}) async {
    try {
      final token = newToken ?? await _firebaseMessaging.getToken();
      final user = FirebaseAuth.instance.currentUser;

      if (token != null && user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'devicePlatform': Platform.operatingSystem,
          'deviceModel': Platform.isAndroid
              ? 'Android'
              : Platform.isIOS
                  ? 'iOS'
                  : Platform.operatingSystem,
        });
        debugPrint(
            'NotificationService: FCM token updated to: ${token.substring(0, 10)}...');
      }
    } catch (e) {
      debugPrint('NotificationService: Failed to update FCM token: $e');
      // Retry after delay if it's a network-related error
      if (e.toString().contains('network') ||
          e.toString().contains('timeout')) {
        debugPrint(
            'NotificationService: Will retry FCM token update in 60 seconds');
        Future.delayed(const Duration(seconds: 60), () => _updateFCMToken());
      }
    }
  }

  // Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
        'NotificationService: Received foreground message: ${message.notification?.title}');
    _showLocalNotification(message);
  }

  // Handle background message being opened
  void _handleBackgroundMessageOpened(RemoteMessage message) {
    debugPrint(
        'NotificationService: Background message opened: ${message.notification?.title}');
    // Handle navigation or other actions based on the notification
  }

  // Show a local notification with error handling
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      if (notification == null) return;

      // Generate a more stable notification ID
      final int notificationId = message.data['scanId'] != null
          ? _getConsistentHashCode(
              message.notification?.title ?? 'Notification',
              message.data['scanId'])
          : message.hashCode;

      // Check if we've shown this notification recently
      final now = DateTime.now();
      if (_recentlyShownNotifications.containsKey(notificationId)) {
        final lastShown = _recentlyShownNotifications[notificationId]!;
        if (now.difference(lastShown).inMinutes < 5) {
          debugPrint(
              'NotificationService: Skipping duplicate FCM notification #$notificationId (shown recently)');
          return;
        }
      }

      // Check if this is a harvest day notification
      final bool isHarvestDayNotification =
          notification.title?.contains('Harvest Today') == true ||
              notification.title?.contains('Ready to Harvest') == true ||
              notification.title?.contains('Harvest Day') == true;

      // Create the notification details with high importance and priority
      final androidDetails = AndroidNotificationDetails(
        isHarvestDayNotification ? 'harvest_day_channel' : 'harvest_channel',
        isHarvestDayNotification ? 'Harvest Day Alerts' : 'Harvest Reminders',
        channelDescription: isHarvestDayNotification
            ? 'High priority alerts for produce ready to harvest today'
            : 'Notifications for produce harvest reminders',
        importance: isHarvestDayNotification ? Importance.max : Importance.high,
        priority: Priority.high,
        color: const Color(0xFF2E7D32),
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        vibrationPattern: Int64List.fromList(
            [0, 500, 200, 500, 200, 500]), // Strong vibration pattern
        fullScreenIntent:
            true, // Make sure the notification pops up even when device is locked
        visibility: NotificationVisibility.public, // Show on lock screen
        channelShowBadge: true,
        category: AndroidNotificationCategory
            .alarm, // Set as an alarm for higher priority
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
            'notification_sound'), // Custom sound from res/raw folder
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'notification_sound.aiff', // Custom sound file in app bundle
        interruptionLevel: InterruptionLevel
            .timeSensitive, // Higher priority for time-sensitive notifications
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        notificationId,
        notification.title,
        notification.body,
        details,
        payload: message.data['scanId'],
      );

      // Record that we showed this notification
      _recentlyShownNotifications[notificationId] = now;

      // Log success
      debugPrint(
          'NotificationService: Successfully showed notification: ${notification.title}');
    } catch (e) {
      // Catch and log any errors to prevent app crashes
      debugPrint('NotificationService: Error showing notification: $e');
    }
  }

  // Callback for when a notification is tapped
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - could navigate to specific page
    debugPrint(
        'NotificationService: Notification tapped with payload: ${response.payload}');
  }

  // Schedule harvest reminders
  Future<void> scheduleHarvestReminder({
    required String produceType,
    required String imagePath,
    required String scanId,
    required int daysUntilHarvest,
    String? confidence,
    String? imageBase64, // Added parameter for base64 image
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint(
            'NotificationService: Cannot schedule reminder - No user logged in');
        return;
      }

      // Check in-memory cache to prevent rapid duplicate notifications
      final reminderKey = _getReminderKey(produceType, scanId);
      if (_recentlyScheduledReminders.containsKey(reminderKey)) {
        debugPrint(
            'NotificationService: Duplicate reminder detected and prevented: $produceType (scanId: $scanId)');
        return;
      }

      // Add to recently scheduled set to prevent duplicates
      _recentlyScheduledReminders[reminderKey] = DateTime.now();

      // Clean up the set periodically
      _cleanupRecentReminders();

      // Ensure service is initialized
      if (!_isInitialized) {
        debugPrint(
            'NotificationService: Initializing before scheduling reminder');
        await initialize();
      }

      // Validate and normalize days until harvest
      int normalizedDaysUntilHarvest = daysUntilHarvest;

      // Handle negative days (invalid state)
      if (normalizedDaysUntilHarvest < 0) {
        debugPrint(
            'NotificationService: Negative days until harvest detected ($daysUntilHarvest), setting to 0');
        normalizedDaysUntilHarvest = 0;
      }
      // Cap extremely high values to avoid unreasonable reminders
      else if (normalizedDaysUntilHarvest > 60) {
        debugPrint(
            'NotificationService: Unusually high days until harvest detected ($daysUntilHarvest), capping at 60 days');
        normalizedDaysUntilHarvest = 60;
      }

      // For zero days (ready now), we'll still set a reminder for today
      // This allows users to be reminded of produce that's ready right now

      // Calculate the harvest date - set to noon to avoid time zone issues
      final DateTime now = DateTime.now();
      final DateTime harvestDate = DateTime(
          now.year,
          now.month,
          now.day + normalizedDaysUntilHarvest,
          12, // Set to noon (12 PM)
          0,
          0);
      final String formattedDate =
          DateFormat('MMM dd, yyyy').format(harvestDate);

      debugPrint(
          'NotificationService: Scheduling reminder for $produceType on $formattedDate (in $normalizedDaysUntilHarvest days)');

      // First check if there's any active reminder for this produce type already
      final existingRemindersByProduceType = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .where('produceType', isEqualTo: produceType)
          .where('isDismissed', isEqualTo: false)
          .get();

      // If we already have an active reminder for this produce type (with different scanId), update that instead
      if (existingRemindersByProduceType.docs.isNotEmpty) {
        debugPrint(
            'NotificationService: Found existing active reminder for $produceType. Updating instead of creating new one.');

        // Use the first existing reminder
        final existingReminderDoc = existingRemindersByProduceType.docs.first;
        final existingReminderId = existingReminderDoc.id;
        final existingReminderData = existingReminderDoc.data();
        final existingScanId = existingReminderData['scanId'] as String? ?? '';

        // Check if this is the SAME scanId (exact duplicate)
        if (existingScanId == scanId) {
          debugPrint(
              'NotificationService: This is an exact duplicate with scanId $scanId. Updating.');
        } else {
          debugPrint(
              'NotificationService: Different scanId but same produce type. Updating existing reminder.');
        }

        // Update the existing reminder with new data
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .doc(existingReminderId)
            .update({
          'harvestDate': Timestamp.fromDate(harvestDate),
          'daysUntilHarvest': normalizedDaysUntilHarvest,
          'confidence': confidence ?? 'Medium',
          'updatedAt': FieldValue.serverTimestamp(),
          'scanId': scanId, // Update with the most recent scan
          'imagePath': imagePath, // Update with the most recent image
          'imageBase64': imageBase64, // Add base64 image data
          'isNotified': false,
          'isDismissed': false,
        });

        // Calculate consistent IDs for notifications - both old and new
        final oldNotificationId =
            _getConsistentHashCode(produceType, existingScanId);
        final newNotificationId = _getConsistentHashCode(produceType, scanId);

        // Cancel both old and new notifications to be safe
        await _localNotifications.cancel(oldNotificationId);
        await _localNotifications.cancel(oldNotificationId + 1);
        await _localNotifications.cancel(newNotificationId);
        await _localNotifications.cancel(newNotificationId + 1);

        // Schedule new notifications with updated info
        _scheduleHarvestNotifications(
          notificationId: newNotificationId,
          produceType: produceType,
          daysUntilHarvest: normalizedDaysUntilHarvest,
          harvestDate: harvestDate,
          scanId: scanId,
        );

        debugPrint(
            'NotificationService: Updated existing reminder and rescheduled notifications');
        return;
      }

      // If we reach here, we don't have an active reminder for this produce type
      // Continue with the original duplicate checking by scanId and similar reminders

      // Check for exact duplicate by scanId (first priority)
      final existingRemindersByExactScanId = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .where('scanId', isEqualTo: scanId)
          .limit(1)
          .get();

      // Check for similar reminders by produce type and date range (to avoid near-duplicates)
      // Only perform this check if no exact match found
      if (existingRemindersByExactScanId.docs.isEmpty) {
        // Calculate date range to check for similar reminders (±2 days)
        final earliestDate =
            Timestamp.fromDate(harvestDate.subtract(const Duration(days: 2)));
        final latestDate =
            Timestamp.fromDate(harvestDate.add(const Duration(days: 2)));

        // Use a simpler query that doesn't require a complex index
        // First query by produceType only
        final similarRemindersQuery = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .where('produceType', isEqualTo: produceType)
            .get();

        // Then filter the results in memory
        final similarReminders = similarRemindersQuery.docs.where((doc) {
          final data = doc.data();
          final reminderDate = data['harvestDate'] as Timestamp?;
          final isDismissed = data['isDismissed'] as bool? ?? false;

          // Check if the reminder matches our criteria
          return reminderDate != null &&
              !isDismissed &&
              reminderDate.compareTo(earliestDate) >= 0 &&
              reminderDate.compareTo(latestDate) <= 0;
        }).toList();

        // If similar reminder exists, use that instead
        if (similarReminders.isNotEmpty) {
          debugPrint(
              'NotificationService: Found similar reminder for $produceType with close harvest date. Updating instead of creating new');

          // Update the existing similar reminder with new data
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('reminders')
              .doc(similarReminders.first.id)
              .update({
            'harvestDate': Timestamp.fromDate(harvestDate),
            'daysUntilHarvest': normalizedDaysUntilHarvest,
            'confidence': confidence ?? 'Medium',
            'updatedAt': FieldValue.serverTimestamp(),
            'scanId': scanId, // Update with the most recent scan
            'imagePath': imagePath, // Update with the most recent image
            'imageBase64': imageBase64, // Add base64 image data
            'isNotified': false,
            'isDismissed': false,
          });

          // Calculate consistent IDs for notifications
          final notificationId = _getConsistentHashCode(produceType, scanId);

          // Cancel existing notifications
          await _localNotifications.cancel(notificationId);
          await _localNotifications.cancel(notificationId + 1);

          // Schedule new notifications with updated info
          _scheduleHarvestNotifications(
            notificationId: notificationId,
            produceType: produceType,
            daysUntilHarvest: normalizedDaysUntilHarvest,
            harvestDate: harvestDate,
            scanId: scanId,
          );

          debugPrint('NotificationService: Updated similar existing reminder');
          return;
        }
      }

      // If we found an exact match by scanId
      if (existingRemindersByExactScanId.docs.isNotEmpty) {
        debugPrint(
            'NotificationService: Updating existing reminder for scanId $scanId');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .doc(existingRemindersByExactScanId.docs.first.id)
            .update({
          'harvestDate': Timestamp.fromDate(harvestDate),
          'daysUntilHarvest': normalizedDaysUntilHarvest,
          'confidence': confidence ?? 'Medium',
          'updatedAt': FieldValue.serverTimestamp(),
          'imageBase64': imageBase64, // Add base64 image data
          'isNotified': false,
          'isDismissed': false,
        });

        // Calculate consistent ID for notifications
        final notificationId = _getConsistentHashCode(produceType, scanId);

        // Cancel existing notifications
        await _localNotifications.cancel(notificationId);
        await _localNotifications.cancel(notificationId + 1);

        // Schedule new notifications
        _scheduleHarvestNotifications(
          notificationId: notificationId,
          produceType: produceType,
          daysUntilHarvest: normalizedDaysUntilHarvest,
          harvestDate: harvestDate,
          scanId: scanId,
        );
      } else {
        // Create a new reminder in Firestore
        final reminderRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .add({
          'produceType': produceType,
          'imagePath': imagePath,
          'imageBase64': imageBase64, // Add base64 image data
          'scanId': scanId,
          'daysUntilHarvest': normalizedDaysUntilHarvest,
          'confidence': confidence ?? 'Medium',
          'harvestDate': Timestamp.fromDate(harvestDate),
          'createdAt': FieldValue.serverTimestamp(),
          'isNotified': false,
          'isDismissed': false,
        });

        debugPrint(
            'NotificationService: Created new reminder with ID: ${reminderRef.id}');

        // Calculate consistent ID for notifications
        final notificationId = _getConsistentHashCode(produceType, scanId);

        // Schedule notifications
        _scheduleHarvestNotifications(
          notificationId: notificationId,
          produceType: produceType,
          daysUntilHarvest: normalizedDaysUntilHarvest,
          harvestDate: harvestDate,
          scanId: scanId,
        );
      }

      // If the produce is ready for harvest today (daysUntilHarvest = 0),
      // send an immediate notification to ensure the user knows it's ready
      if (normalizedDaysUntilHarvest == 0) {
        debugPrint(
            'NotificationService: Produce is ready TODAY - sending immediate notification');
        await _sendReadyNowNotification(
            produceType: produceType, scanId: scanId);
      }

      // Log success message
      debugPrint(
          'NotificationService: Harvest reminder(s) scheduled successfully for $produceType');
      return;
    } catch (e) {
      debugPrint(
          'NotificationService: Failed to schedule harvest reminder: $e');
      throw Exception('Failed to schedule harvest reminder: $e');
    }
  }

  // Special method to send an immediate notification for produce that is ready now
  Future<void> _sendReadyNowNotification({
    required String produceType,
    required String scanId,
  }) async {
    try {
      // Calculate consistent ID for notification
      final notificationId = _getConsistentHashCode(produceType, scanId);

      // Check if this notification was recently shown
      final now = DateTime.now();

      // For "ready now" notifications, ensure the notification is received
      final readyNowTime = now.add(const Duration(minutes: 1));

      debugPrint(
          'NotificationService: Sending READY NOW notification for $produceType');

      await _scheduleLocalNotification(
        id: notificationId +
            3, // Use a unique ID different from other notifications
        title: '$produceType Ready to Harvest',
        body:
            'Your $produceType is ready to harvest now! Pick it today for optimal flavor and nutrition.',
        scheduledDate: readyNowTime,
        payload: scanId,
        forceShow:
            true, // Force the notification to show regardless of time filters
      );

      // Also schedule a reminder later in the day if it's morning/afternoon
      if (now.hour < 16) {
        // If it's before 4 PM
        final eveningReminder = DateTime(
            now.year,
            now.month,
            now.day,
            18, // Evening reminder (6 PM)
            0,
            0);

        if (eveningReminder.isAfter(now.add(const Duration(hours: 1)))) {
          await _scheduleLocalNotification(
            id: notificationId + 4,
            title: 'Harvest Reminder: $produceType',
            body:
                'Don\'t forget: Your $produceType should be harvested today for best quality.',
            scheduledDate: eveningReminder,
            payload: scanId,
          );
        }
      }

      debugPrint(
          'NotificationService: Ready-now notifications scheduled for $produceType');
    } catch (e) {
      debugPrint(
          'NotificationService: Failed to send ready-now notification: $e');
    }
  }

  // Generate a consistent hash code for a reminder, guaranteed to fit within 32-bit integer limits
  int _getConsistentHashCode(String produceType, String scanId) {
    // Flutter local notifications plugin requires IDs to be within 32-bit integer range

    // Normalize inputs to handle case differences and whitespace
    final normalizedProduceType = produceType.trim().toLowerCase();
    final normalizedScanId = scanId.trim();

    // Create a string that combines the two values to hash
    final String combinedString = "$normalizedProduceType:$normalizedScanId";

    // Get the hash code and ensure it's positive
    int hashCode = combinedString.hashCode;

    // Create a more stable hash that's less likely to cause collisions
    // Using a prime number (10007) as a multiplier and modulo with another prime (99991)
    // to distribute the hash values more evenly
    int stableHash = (hashCode.abs() * 10007) % 99991;

    // Add a prefix to differentiate notification types (1 for harvests)
    return 10000 + stableHash % 89999;
  }

  // Helper to schedule both day-before and harvest-day notifications
  Future<void> _scheduleHarvestNotifications({
    required int notificationId,
    required String produceType,
    required int daysUntilHarvest,
    required DateTime harvestDate,
    required String scanId,
  }) async {
    try {
      // Get the current date for better scheduling decisions
      final now = DateTime.now();

      // Normalize both dates to remove time of day for consistent comparison
      final normalizedNow = DateTime(now.year, now.month, now.day);
      final normalizedHarvest =
          DateTime(harvestDate.year, harvestDate.month, harvestDate.day);

      // Calculate actual days until harvest (may differ from daysUntilHarvest parameter if dates were passed directly)
      final actualDaysUntil =
          normalizedHarvest.difference(normalizedNow).inDays;

      debugPrint(
          'NotificationService: Actual days until harvest: $actualDaysUntil (parameter: $daysUntilHarvest)');

      // Check if we've already scheduled notifications for this produce type and scanId recently
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final recentNotifications = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scheduled_notifications')
            .where('payload', isEqualTo: scanId)
            .where('scheduledDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(
                    DateTime.now().subtract(const Duration(minutes: 5))))
            .get();

        if (recentNotifications.docs.isNotEmpty) {
          debugPrint(
              'NotificationService: Found recently scheduled notifications for this scanId ($scanId). Skipping duplicate notifications.');
          return;
        }
      }

      // Schedule day-before notification only if there's more than 1 day left
      // and the harvest is not today or in the past
      if (actualDaysUntil > 1) {
        // Calculate the day before harvest date
        // Use normalized date arithmetic to avoid time zone issues
        final dayBeforeHarvest = DateTime(
            harvestDate.year,
            harvestDate.month,
            harvestDate.day - 1,
            9, // Morning notification (9 AM)
            0,
            0);

        // Check that the day before notification is not in the past
        if (dayBeforeHarvest.isAfter(now)) {
          debugPrint(
              'NotificationService: Scheduling day-before notification for ${DateFormat('MMM dd, yyyy HH:mm').format(dayBeforeHarvest)}');

          await _scheduleLocalNotification(
            id: notificationId,
            title: '$produceType Ready Tomorrow',
            body:
                'Your $produceType will be ready to harvest tomorrow! Prepare to pick at optimal ripeness.',
            scheduledDate: dayBeforeHarvest,
            payload: scanId,
            forceShow: true, // Force show day-before notifications
          );
        } else {
          debugPrint(
              'NotificationService: Day-before notification would be in the past, skipping');
        }
      } else {
        debugPrint(
            'NotificationService: Skipping day-before notification, less than 2 days until harvest');
      }

      // Schedule harvest day notification if it's today or in the future
      if (actualDaysUntil >= 0) {
        // Set notification for harvest day morning
        final harvestDayMorning = DateTime(
            harvestDate.year,
            harvestDate.month,
            harvestDate.day,
            9, // Morning notification (9 AM)
            0,
            0);

        // Only schedule if it's in the future
        if (harvestDayMorning.isAfter(now)) {
          debugPrint(
              'NotificationService: Scheduling harvest-day morning notification for ${DateFormat('MMM dd, yyyy HH:mm').format(harvestDayMorning)}');

          await _scheduleLocalNotification(
            id: notificationId + 1,
            title: 'Harvest Day: $produceType',
            body:
                'Your $produceType is at peak ripeness today! Harvest now for best flavor and nutrition.',
            scheduledDate: harvestDayMorning,
            payload: scanId,
            forceShow: true, // Always force show harvest day notifications
          );

          // Also schedule a second notification a bit later to ensure it's seen
          final harvestDayLateAM = DateTime(
              harvestDate.year,
              harvestDate.month,
              harvestDate.day,
              11, // Late morning notification (11 AM)
              30,
              0);

          if (harvestDayLateAM.isAfter(now)) {
            await _scheduleLocalNotification(
              id: notificationId + 7,
              title: 'Reminder: Harvest $produceType Today',
              body:
                  'Your $produceType is ready to harvest today! For best quality, harvest it soon.',
              scheduledDate: harvestDayLateAM,
              payload: scanId,
              forceShow: true,
            );
          }
        } else {
          // If the morning time is past but it's still the harvest day, schedule for immediate notification
          if (normalizedHarvest.isAtSameMomentAs(normalizedNow)) {
            // For same-day harvest notifications, send one immediately (1 minute from now)
            final oneMinuteFromNow = now.add(const Duration(minutes: 1));

            debugPrint(
                'NotificationService: Scheduling immediate harvest notification for ${DateFormat('MMM dd, yyyy HH:mm').format(oneMinuteFromNow)}');

            await _scheduleLocalNotification(
              id: notificationId + 1,
              title: 'Harvest Today: $produceType',
              body:
                  'Your $produceType is ready to harvest today! Harvest now for best quality and flavor.',
              scheduledDate: oneMinuteFromNow,
              payload: scanId,
              forceShow:
                  true, // Force notification even if time-based filter would skip it
            );

            // For same-day reminders, also schedule another one for later in the day
            if (now.hour < 14) {
              // If it's before 2 PM
              final afternoonReminder = DateTime(
                  harvestDate.year,
                  harvestDate.month,
                  harvestDate.day,
                  16, // Afternoon reminder (4 PM)
                  0,
                  0);

              if (afternoonReminder.isAfter(now)) {
                debugPrint(
                    'NotificationService: Scheduling afternoon harvest reminder for ${DateFormat('MMM dd, yyyy HH:mm').format(afternoonReminder)}');

                await _scheduleLocalNotification(
                  id: notificationId + 2,
                  title: 'Harvest Reminder: $produceType',
                  body:
                      'Reminder: Your $produceType is at optimal ripeness today. Don\'t forget to harvest!',
                  scheduledDate: afternoonReminder,
                  payload: scanId,
                  forceShow: true, // Always force show reminder notifications
                );
              }
            }
          } else {
            debugPrint(
                'NotificationService: Harvest day has passed, not scheduling harvest-day notification');
          }
        }
      }

      // Log success
      debugPrint(
          'NotificationService: Successfully scheduled notifications for $produceType with harvest date ${DateFormat('MMM dd, yyyy').format(harvestDate)}');
    } catch (e) {
      debugPrint('NotificationService: Error scheduling notifications: $e');
    }
  }

  // Helper method to schedule a local notification
  Future<void> _scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    bool forceShow = false,
  }) async {
    try {
      // Check if this notification ID was recently shown (within 30 seconds)
      final now = DateTime.now();
      if (_recentlyShownNotifications.containsKey(id)) {
        final lastShown = _recentlyShownNotifications[id]!;
        if (now.difference(lastShown).inSeconds < 30) {
          debugPrint(
              'NotificationService: Skipping duplicate notification #$id - shown too recently');
          return;
        }
      }

      // Verify service is initialized
      if (!_isInitialized) {
        debugPrint(
            'NotificationService: Cannot schedule notification, service not initialized');
        await initialize();
      }

      // Check if this is a harvest day notification
      final bool isHarvestDayNotification = title.contains('Harvest Today') ||
          title.contains('Ready to Harvest') ||
          title.contains('Harvest Day');

      // Create the notification details with high importance and priority
      final androidDetails = AndroidNotificationDetails(
        isHarvestDayNotification ? 'harvest_day_channel' : 'harvest_channel',
        isHarvestDayNotification ? 'Harvest Day Alerts' : 'Harvest Reminders',
        channelDescription: isHarvestDayNotification
            ? 'High priority alerts for produce ready to harvest today'
            : 'Notifications for produce harvest reminders',
        importance: isHarvestDayNotification ? Importance.max : Importance.high,
        priority: Priority.high,
        color: const Color(0xFF2E7D32),
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        vibrationPattern: Int64List.fromList(
            [0, 500, 200, 500, 200, 500]), // Strong vibration pattern
        fullScreenIntent:
            true, // Make sure the notification pops up even when device is locked
        visibility: NotificationVisibility.public, // Show on lock screen
        channelShowBadge: true,
        category: AndroidNotificationCategory
            .alarm, // Set as an alarm for higher priority
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(
            'notification_sound'), // Custom sound from res/raw folder
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'notification_sound.aiff', // Custom sound file in app bundle
        interruptionLevel: InterruptionLevel
            .timeSensitive, // Higher priority for time-sensitive notifications
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // First check if we've already scheduled or shown this notification ID recently
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Generate a unique ID for this notification instance
        final String notificationUniqueId =
            '${payload ?? ''}_${id}_${DateTime.now().millisecondsSinceEpoch}';

        // Store the scheduled notification in Firestore for tracking
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scheduled_notifications')
            .add({
          'uniqueId': notificationUniqueId,
          'id': id,
          'title': title,
          'body': body,
          'scheduledDate': Timestamp.fromDate(scheduledDate),
          'payload': payload,
          'createdAt': FieldValue.serverTimestamp(),
          'isHarvestNotification': title.contains('Harvest') ||
              title.contains('Ready'), // Flag harvest notifications
        });
      }

      // For the demo/MVP, we'll use immediate notifications
      // Check if this is a harvest date notification
      final bool isHarvestNotification =
          title.contains('Harvest') || title.contains('Ready');

      // Calculate time difference for logging
      final timeDifference = scheduledDate.difference(now).inSeconds;

      final bool shouldShow =
          forceShow || isHarvestNotification || timeDifference > 10;

      // Always show harvest notifications, otherwise follow normal rules
      if (shouldShow) {
        await _localNotifications.show(
          id,
          title,
          body,
          details,
          payload: payload,
        );

        // Record that we showed this notification
        _recentlyShownNotifications[id] = now;

        // Clean up old entries
        final expiredIds = <int>[];
        _recentlyShownNotifications.forEach((notifId, timestamp) {
          if (now.difference(timestamp).inMinutes >= 5) {
            expiredIds.add(notifId);
          }
        });
        for (final expiredId in expiredIds) {
          _recentlyShownNotifications.remove(expiredId);
        }

        debugPrint(
            'NotificationService: Successfully showed notification #$id: $title');
      } else {
        debugPrint(
            'NotificationService: Skipping immediate duplicate notification #$id as it is too close to previous one');
      }

      debugPrint(
          'NotificationService: Notification #$id set for ${DateFormat('MMM dd, yyyy').format(scheduledDate)}');
      return;
    } catch (e) {
      debugPrint('NotificationService: Failed to schedule notification: $e');
      // Don't rethrow, just log the error to avoid crashing the app
    }
  }

  // Get pending reminders for a user
  Future<List<Map<String, dynamic>>> getPendingReminders() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final now = DateTime.now();

      // Use a simpler query that doesn't require a complex index
      // First query by just the date filter
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .where('harvestDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .orderBy('harvestDate', descending: false)
          .get();

      // Then filter in memory for isDismissed
      return querySnapshot.docs
          .where((doc) => !(doc.data()['isDismissed'] as bool? ?? false))
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .toList();
    } catch (e) {
      debugPrint('NotificationService: Failed to get pending reminders: $e');
      return [];
    }
  }

  // Cancel a specific reminder
  Future<void> cancelReminder(String reminderId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get the reminder details first to extract produceType and scanId
      final reminderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .doc(reminderId)
          .get();

      if (reminderDoc.exists) {
        final reminderData = reminderDoc.data();
        final produceType = reminderData?['produceType'] as String? ?? '';
        final scanId = reminderData?['scanId'] as String? ?? '';

        // Calculate the consistent hash code using the same method
        final notificationId = _getConsistentHashCode(produceType, scanId);

        // Mark reminder as dismissed in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('reminders')
            .doc(reminderId)
            .update({
          'isDismissed': true,
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        // Cancel notifications using the consistent IDs
        await _localNotifications.cancel(notificationId);
        await _localNotifications.cancel(notificationId + 1);

        debugPrint(
            'NotificationService: Reminder canceled: $reminderId (produce: $produceType)');
      } else {
        debugPrint(
            'NotificationService: Reminder $reminderId not found, cannot cancel');
      }
    } catch (e) {
      debugPrint('NotificationService: Failed to cancel reminder: $e');
    }
  }

  // Method to check for reminders due today that haven't been notified yet
  Future<void> checkTodayReminders() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      debugPrint(
          'NotificationService: Checking for produce ready to harvest today...');

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // For more reliability, reset the check flag if it's a new day
      final lastCheckedDay = _lastReminderCheck?.day;
      if (lastCheckedDay != null && lastCheckedDay != now.day) {
        _hasTodayRemindersBeenChecked = false;
        debugPrint(
            'NotificationService: New day detected, resetting reminder check flag');
      }

      // Update last check time
      _lastReminderCheck = now;

      // Check if we've already run the check today and it's not a force check
      if (_hasTodayRemindersBeenChecked) {
        debugPrint(
            'NotificationService: Today\'s reminders have already been checked this session');
        // Even if we've checked, let's do a quick query to see if any new reminders were added
      }

      // Query for reminders that are due today or within the last 3 days but haven't been notified
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reminders')
          .where('harvestDate',
              isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
          .where('harvestDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                  todayStart.subtract(const Duration(days: 3))))
          .where('isDismissed', isEqualTo: false)
          .get(); // Remove isNotified filter to recheck all reminders

      if (querySnapshot.docs.isEmpty) {
        debugPrint(
            'NotificationService: No reminders due today or missed recently');
      } else {
        debugPrint(
            'NotificationService: Found ${querySnapshot.docs.length} reminders due today or missed');

        // Process each reminder
        for (final doc in querySnapshot.docs) {
          final reminderData = doc.data();
          final reminderDate =
              (reminderData['harvestDate'] as Timestamp).toDate();
          final produceType =
              reminderData['produceType'] as String? ?? 'Your produce';
          final scanId = reminderData['scanId'] as String? ?? '';
          final isNotified = reminderData['isNotified'] as bool? ?? false;

          // Check if date is today or past
          final isToday = reminderDate.year == now.year &&
              reminderDate.month == now.month &&
              reminderDate.day == now.day;

          final isPast = reminderDate.isBefore(todayStart);

          // Only send notifications if not already notified
          if (!isNotified) {
            if (isToday) {
              debugPrint(
                  'NotificationService: Sending notification for $produceType due TODAY');
              await _sendReadyNowNotification(
                  produceType: produceType, scanId: scanId);

              // Mark as notified
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('reminders')
                  .doc(doc.id)
                  .update({
                'isNotified': true,
                'notifiedAt': FieldValue.serverTimestamp(),
              });
            } else if (isPast) {
              debugPrint(
                  'NotificationService: Sending notification for $produceType that was MISSED (due: ${DateFormat('MMM dd').format(reminderDate)})');

              // Send notification for missed harvest
              final notificationId =
                  _getConsistentHashCode(produceType, scanId);
              await _scheduleLocalNotification(
                id: notificationId + 5,
                title: 'Missed Harvest: $produceType',
                body:
                    'Your $produceType was ready for harvest on ${DateFormat('MMM dd').format(reminderDate)}. Check it soon!',
                scheduledDate: now.add(const Duration(minutes: 2)),
                payload: scanId,
                forceShow: true, // Force show missed harvest notifications
              );

              // Mark as notified
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('reminders')
                  .doc(doc.id)
                  .update({
                'isNotified': true,
                'notifiedAt': FieldValue.serverTimestamp(),
              });
            }
          } else if (isToday) {
            // For today's reminders that have been notified, check when they were notified
            final notifiedAt = reminderData['notifiedAt'] as Timestamp?;

            // If notified more than 4 hours ago, send another reminder in the afternoon
            if (notifiedAt != null &&
                now.difference(notifiedAt.toDate()).inHours >= 4 &&
                now.hour >= 14 &&
                now.hour < 18) {
              debugPrint(
                  'NotificationService: Sending afternoon follow-up for $produceType due TODAY');

              final notificationId =
                  _getConsistentHashCode(produceType, scanId);
              await _scheduleLocalNotification(
                id: notificationId + 6,
                title: 'Reminder: Harvest $produceType Today',
                body:
                    'Don\'t forget to harvest your $produceType today for best quality!',
                scheduledDate: now.add(const Duration(minutes: 2)),
                payload: scanId,
                forceShow: true,
              );
            }
          }
        }
      }

      // Mark as checked for this session
      _hasTodayRemindersBeenChecked = true;
    } catch (e) {
      debugPrint('NotificationService: Error checking today\'s reminders: $e');
    }
  }

  // Method to verify notifications are working properly
  Future<Map<String, dynamic>> verifyNotificationStatus() async {
    final result = <String, dynamic>{
      'isInitialized': _isInitialized,
      'errors': <String>[],
      'deviceInfo': {
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
      }
    };

    try {
      // Check notification permissions
      final NotificationSettings settings =
          await _firebaseMessaging.getNotificationSettings();
      result['permissionStatus'] = settings.authorizationStatus.toString();

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        result['errors'].add('Notification permissions not granted');
      }

      // Check FCM token
      final token = await _firebaseMessaging.getToken();
      result['hasToken'] = token != null && token.isNotEmpty;

      if (token == null || token.isEmpty) {
        result['errors'].add('Failed to get FCM token');
      }

      // Check if user has token saved in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data();
            final storedToken = userData?['fcmToken'];
            result['tokenInFirestore'] =
                storedToken != null && storedToken.isNotEmpty;

            if (storedToken == null || storedToken.isEmpty) {
              result['errors'].add('FCM token not saved in Firestore');

              // Update token if missing
              await _updateFCMToken();
            } else if (storedToken != token) {
              result['errors'].add('FCM token mismatch');

              // Update with current token
              await _updateFCMToken();
            }
          } else {
            result['errors'].add('User document not found in Firestore');
          }
        } catch (e) {
          result['errors'].add('Firestore error: $e');
        }
      } else {
        result['errors'].add('User not logged in');
      }

      // Send test notification
      // await _testNotification();
      result['testNotificationSent'] = true;

      return result;
    } catch (e) {
      debugPrint('NotificationService: Verification failed: $e');
      result['errors'].add('Verification error: $e');
      return result;
    }
  }
}
