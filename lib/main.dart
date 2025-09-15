import 'package:flutter/material.dart';
import 'screens/landing_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'utils/app_theme.dart';
import 'screens/login_page.dart';
import 'screens/dashboard_page.dart';
import 'services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

// Better background message handler implementation
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Need to ensure Firebase is initialized here too
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Handling a background message: ${message.messageId}');

  // Initialize FlutterLocalNotificationsPlugin for background messages
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notifications with basic settings for background use
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Create notification channel for Android (skip on web)
  if (!kIsWeb && Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'harvest_channel',
      'Harvest Reminders',
      description: 'Notifications for produce harvest reminders',
      importance: Importance.high,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Show the notification
  if (message.notification != null) {
    final androidDetails = AndroidNotificationDetails(
      'harvest_channel',
      'Harvest Reminders',
      channelDescription: 'Notifications for produce harvest reminders',
      importance: Importance.high,
      priority: Priority.high,
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

    // Ensure unique notification ID
    final String uniqueId =
        '${message.messageId ?? DateTime.now().millisecondsSinceEpoch}';
    final int notificationId = uniqueId.hashCode;

    // Show notification
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      message.notification!.title,
      message.notification!.body,
      details,
      payload: message.data['scanId'],
    );
  }
}

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone data
  tz.initializeTimeZones();

  // Set up background message handler before initializing Firebase (skip on web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Print Firebase package versions for debugging
  debugPrint('Starting app initialization...');

  try {
    // Initialize Firebase with explicit error handling
    debugPrint('Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialization successful');

    // Configure Firestore settings
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    debugPrint('Firestore settings configured');

    // Check if Firebase Auth is working properly
    final auth = FirebaseAuth.instance;
    debugPrint('Firebase Auth instance created: ${auth.hashCode}');

    // Listen for auth state changes to verify auth is working
    auth.authStateChanges().listen((User? user) {
      debugPrint('Auth state changed. User: ${user?.uid ?? 'No user'}');
    }, onError: (error) {
      debugPrint('Auth state change error: $error');
    });

    // Initialize notification service
    try {
      debugPrint('Initializing notification service...');
      await NotificationService().initialize();
      debugPrint('Notification service initialized successfully');

      // Check for reminders due today when app starts
      await NotificationService().checkTodayReminders();

      // Request notification permissions (skip on web for now)
      if (!kIsWeb) {
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: true,
          provisional: false,
          sound: true,
        );

        debugPrint('User granted permission: ${settings.authorizationStatus}');

        // Configure high priority notifications in Android (skip on web)
        try {
          if (Platform.isAndroid) {
            debugPrint('Configuring high priority notifications for Android');
          }
        } catch (e) {
          debugPrint('Failed to configure notifications: $e');
        }

        // Get FCM token for debugging
        final token = await messaging.getToken();
        debugPrint('FCM Token: $token');
      } else {
        debugPrint('Skipping Firebase messaging setup on web platform');
      }
    } catch (e) {
      debugPrint('Notification service initialization failed: $e');
      // Continue app initialization even if notification service fails
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    // Continue even if Firebase fails - app can work without it
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Start periodic checks when app is in foreground
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed - starting periodic reminder checks');
      NotificationService().startPeriodicReminderCheck();
    }
    // Stop periodic checks when app is in background to save resources
    else if (state == AppLifecycleState.paused) {
      debugPrint('App paused - stopping periodic reminder checks');
      NotificationService().stopPeriodicReminderCheck();
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FruitVeggie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Using a darker, more saturated color scheme for better readability
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryGradient.colors[0], // Dark Green
          primary: const Color(0xFF2E7D32), // Dark Green
          secondary: const Color(0xFFE65100), // Deep Orange
          tertiary: const Color(0xFFFFB300), // Amber
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Color(0xFF2E7D32), // Dark Green
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE65100), // Deep Orange
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: Color(0xFF2E7D32), width: 2), // Dark Green
          ),
        ),
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _CustomPageTransitionsBuilder(),
            TargetPlatform.iOS: _CustomPageTransitionsBuilder(),
            TargetPlatform.windows: _CustomPageTransitionsBuilder(),
            TargetPlatform.macOS: _CustomPageTransitionsBuilder(),
            TargetPlatform.linux: _CustomPageTransitionsBuilder(),
          },
        ),
      ),
      // Add navigation observer to handle back button presses
      navigatorObservers: [
        NavigatorObserver(),
      ],
      // Add navigation key for global access
      navigatorKey: GlobalKey<NavigatorState>(),
      // Update routes to handle navigation properly
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasData && snapshot.data != null) {
                  // User is logged in
                  return const DashboardPage();
                }

                // User is not logged in
                return const LandingPage();
              },
            ),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
      },
      // Add onGenerateRoute for handling unknown routes
      onGenerateRoute: (settings) {
        // Default to landing page for unknown routes
        return MaterialPageRoute(
          builder: (context) => const LandingPage(),
        );
      },
    );
  }
}

/// Custom page transitions builder that uses slide animations
class _CustomPageTransitionsBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Define default animation (slide from right)
    var slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
    );

    // Add a fade animation on top of the slide
    var fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
    );

    // Apply both animations
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }
}
