import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Add for compute
import 'dart:io';
import 'dart:async'; // Add import for TimeoutException
import 'dart:convert'; // Add import for Base64 encoding/decoding
import 'camera_page.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'all_scans_page.dart';
import 'all_harvests_page.dart';
import 'chart_page.dart'; // Add import for chart page
import '../utils/custom_route.dart'; // Add import for custom slide animation
import 'login_page.dart';
// Add import for AppTheme

// Skeleton loading indicator widgets
class SkeletonWidget extends StatelessWidget {
  final double height;
  final double width;
  final double borderRadius;

  const SkeletonWidget({
    super.key,
    required this.height,
    required this.width,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const SizedBox(),
    );
  }
}

// Modern skeleton for feature cards
class SkeletonFeatureCard extends StatelessWidget {
  const SkeletonFeatureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.grey.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon placeholder with container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const SkeletonWidget(
              height: 32,
              width: 32,
              borderRadius: 16,
            ),
          ),
          const SizedBox(height: 16),
          // Title placeholder
          const SkeletonWidget(
            height: 16,
            width: 110,
            borderRadius: 8,
          ),
          const SizedBox(height: 8),
          // Description placeholder
          const SkeletonWidget(
            height: 13,
            width: 130,
            borderRadius: 6,
          ),
          const SizedBox(height: 4),
          const SkeletonWidget(
            height: 13,
            width: 90,
            borderRadius: 6,
          ),
        ],
      ),
    );
  }
}

// Animated skeleton for shimmer effect
class ShimmerSkeleton extends StatefulWidget {
  final Widget child;

  const ShimmerSkeleton({
    super.key,
    required this.child,
  });

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade100,
                Colors.grey.shade300,
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(_animation.value, 0),
              end: Alignment(_animation.value + 2, 0),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();
  late final UserService _userService = UserService();
  final ImagePicker _picker = ImagePicker();
  final NotificationService _notificationService =
      NotificationService(); // Add this line
  bool _isLoading = true;
  List<Map<String, dynamic>> _recentScans = [];
  bool _hasScans = false;

  // Weather page variables
  final WeatherService _weatherService = WeatherService();
  final LocationService _locationService = LocationService();
  WeatherData? _weatherData;
  Position? _currentPosition;
  bool _isLoadingWeather = true;
  String? _weatherError;
  final List<Map<String, dynamic>> _weatherForecast = [];
  Timer? _weatherRefreshTimer;

  // Add after the _recentScans declaration in class _DashboardPageState
  String? _lastProcessedImagePath;
  String? _lastProcessedImageBase64;

  // Add a field to store the detected type
  String _lastProcessedProduceType = 'Produce';

  // Add a list to store active reminders
  List<Map<String, dynamic>> _activeReminders = [];

  // Add a map to cache reminder images to prevent duplicate downloads
  final Map<String, Widget> _reminderImageCache = {};

  // Add flag to track reminders refresh status
  bool _isRefreshingReminders = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start checking for reminders periodically
    _notificationService.startPeriodicReminderCheck();

    _loadActiveReminders(); // Add this line

    // Simulate loading data
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        // Load actual data from Firestore
        _loadRecentScans();
        _fetchLastProcessedImage();

        setState(() {
          _isLoading = false;
        });
      }
    });

    _getCurrentLocation();

    // Set up a timer to refresh weather data periodically
    _weatherRefreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _fetchWeatherData(),
    );
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    _notificationService.stopPeriodicReminderCheck();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      _notificationService.startPeriodicReminderCheck();
      _loadActiveReminders();
    } else if (state == AppLifecycleState.paused) {
      // App went to background
      _notificationService.stopPeriodicReminderCheck();
    }
  }

  void _onPopInvoked(bool didPop) {
    if (didPop) return;
    // If not on the dashboard tab, go back to dashboard instead of exiting
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.exit_to_app,
                    color: Color(0xFF2E7D32),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Exit App',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to exit?',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          SystemNavigator.pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: const Text('Exit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadRecentScans() async {
    try {
      final currentUser = _authService.currentUser;
      final userId = currentUser?.uid;

      if (userId != null) {
        try {
          // Get the scans from Firestore
          final QuerySnapshot result = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('scans')
              .orderBy('timestamp', descending: true)
              .limit(5)
              .get();

          if (!mounted) return;

          if (result.docs.isNotEmpty) {
            setState(() {
              _recentScans = result.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final scanId = doc.id;
                // Store the scan ID in the data map for future reference
                data['scanId'] = scanId;

                // Ensure both image fields are populated
                if (data['imageUrl'] != null &&
                    !data.containsKey('imageBase64')) {
                  // Try to convert imageUrl to Base64 (will be done asynchronously)
                  _populateBase64ForScan(data);
                }

                // Cross-populate image fields if only one is available
                if (data['imageUrl'] == null && data['imagePath'] != null) {
                  data['imageUrl'] = data['imagePath'];
                } else if (data['imagePath'] == null &&
                    data['imageUrl'] != null) {
                  data['imagePath'] = data['imageUrl'];
                }

                return data;
              }).toList();
              _hasScans = _recentScans.isNotEmpty;
            });

            // Update last processed image
            if (_recentScans.isNotEmpty) {
              _setLastProcessedFromScan(_recentScans.first);
            }
          } else {
            // No scans found
            print('No scans found in Firestore.');
            setState(() {
              _recentScans = [];
              _hasScans = false;
              _lastProcessedImagePath = null;
              _lastProcessedImageBase64 = null;
              _lastProcessedProduceType = 'Produce';
            });
          }
        } catch (firestoreError) {
          // Handle Firestore errors (likely permission issues)
          print('Firestore error: $firestoreError.');
          setState(() {
            _recentScans = [];
            _hasScans = false;
          });
        }
      } else {
        // No user logged in
        print('No user logged in. Cannot load scans.');
        setState(() {
          _recentScans = [];
          _hasScans = false;
        });
      }
    } catch (e) {
      print('Error loading recent scans: $e');
      setState(() {
        _recentScans = [];
        _hasScans = false;
      });
    }
  }

  // Helper method to set last processed data from a scan
  void _setLastProcessedFromScan(Map<String, dynamic> scan) {
    setState(() {
      _lastProcessedImagePath = scan['imagePath'] ?? scan['imageUrl'];
      _lastProcessedImageBase64 = scan['imageBase64'];
      _lastProcessedProduceType = scan['name'] ?? 'Produce';
    });
  }

  // Helper to populate Base64 data for a scan asynchronously
  Future<void> _populateBase64ForScan(Map<String, dynamic> scan) async {
    if (scan['imageUrl'] != null && !scan.containsKey('imageBase64')) {
      final base64Data = await _convertImageToBase64(scan['imageUrl']);
      if (base64Data != null && mounted) {
        setState(() {
          scan['imageBase64'] = base64Data;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _currentPosition = position;
        });
        _fetchWeatherData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherError = 'Could not access location';
          _isLoadingWeather = false;
        });
      }
    }
  }

  Future<void> _fetchWeatherData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingWeather = true;
      _weatherError = null;
    });

    try {
      WeatherData data;

      if (_currentPosition != null) {
        data = await _weatherService.getWeatherByLocation(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } else {
        // Try to get location first before falling back
        await _getCurrentLocation();
        if (_currentPosition != null) {
          data = await _weatherService.getWeatherByLocation(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
        } else {
          // Only fallback to default city if location is completely unavailable
          throw Exception('Location unavailable and no coordinates provided');
        }
      }

      if (mounted) {
        setState(() {
          _weatherData = data;
          _isLoadingWeather = false;

          // Get real forecast data
          _fetchForecastData();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherError = 'Failed to load weather data';
          _isLoadingWeather = false;
        });
      }
    }
  }

  Future<void> _fetchForecastData() async {
    if (_weatherData == null || !mounted) return;

    try {
      List<ForecastData> forecastData;

      if (_currentPosition != null) {
        forecastData = await _weatherService.getForecastByLocation(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } else {
        // This should rarely happen due to improved location handling
        return; // Skip forecast if no location available
      }

      if (mounted) {
        setState(() {
          _weatherForecast.clear();

          // Convert forecast data to the format expected by the UI
          for (final forecast in forecastData) {
            IconData iconData;
            Color iconColor;

            // Map weather icons to Flutter icons and colors
            switch (forecast.iconCode.substring(0, 2)) {
              case '01': // clear sky
                iconData = Icons.wb_sunny;
                iconColor = Colors.orange;
                break;
              case '02': // few clouds
              case '03': // scattered clouds
              case '04': // broken clouds
                iconData = Icons.wb_cloudy;
                iconColor = Colors.grey.shade600;
                break;
              case '09': // shower rain
              case '10': // rain
                iconData = Icons.water_drop;
                iconColor = Colors.blue;
                break;
              case '11': // thunderstorm
                iconData = Icons.thunderstorm;
                iconColor = Colors.purple;
                break;
              case '13': // snow
                iconData = Icons.ac_unit;
                iconColor = Colors.lightBlue;
                break;
              case '50': // mist
                iconData = Icons.foggy;
                iconColor = Colors.grey;
                break;
              default:
                iconData = Icons.wb_cloudy;
                iconColor = Colors.grey.shade600;
            }

            _weatherForecast.add({
              'day': forecast.day,
              'condition': forecast.description,
              'icon': iconData,
              'color': iconColor,
              'temp': '${forecast.temperature.toStringAsFixed(1)}°C',
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching forecast: $e');
      // Keep existing forecast or show empty state
      if (mounted && _weatherForecast.isEmpty) {
        setState(() {
          // Add a simple fallback message
          _weatherForecast.add({
            'day': 'Today',
            'condition': 'Forecast unavailable',
            'icon': Icons.error_outline,
            'color': Colors.grey,
            'temp': '--°C',
          });
        });
      }
    }
  }

  // Widget to display a single scan item with improved UI and error handling
  Widget _buildScanItem(Map<String, dynamic> scan) {
    final String fruitName = scan['name'] ?? 'Unknown Item';

    // Check for image in different formats: base64, url, or file path
    String? imagePath = scan['imageUrl'];
    String? base64Image = scan['imageBase64'];

    if ((imagePath == null || imagePath.isEmpty) &&
        scan.containsKey('imagePath')) {
      imagePath = scan['imagePath'];
    }

    final bool hasAnalysis = scan['hasAnalysis'] ?? false;

    // Handle different date formats
    DateTime timestamp;
    try {
      if (scan['timestamp'] is Timestamp) {
        timestamp = scan['timestamp'].toDate();
      } else if (scan['timestamp'] is DateTime) {
        timestamp = scan['timestamp'];
      } else {
        timestamp = DateTime.now();
      }
    } catch (e) {
      timestamp = DateTime.now();
    }

    // Format time ago
    String timeAgo = _formatTimeAgo(timestamp);

    return GestureDetector(
      onTap: () {
        // Show details of the scan when tapped
        _showScanDetailsDialog(scan);
      },
      child: Container(
        width: 180,
        margin: const EdgeInsets.only(right: 12, left: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              spreadRadius: 0,
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section with improved styling
            Container(
              height: 120,
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey.shade100,
                            Colors.grey.shade200,
                          ],
                        ),
                      ),
                      child: _buildImageWidget(imagePath, base64Image,
                          width: double.infinity, height: double.infinity),
                    ),
                    // Gradient overlay for better text readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.3),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Analysis badge
                    if (hasAnalysis)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.psychology,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'AI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Content section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fruitName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Helper method to build image widget from various sources
  Widget _buildImageWidget(String? path, String? base64String,
      {double width = 80, double height = 80}) {
    // Debug log for image loading
    // print(
    //     '_buildImageWidget called with path: $path, base64 length: ${base64String?.length ?? 0}');

    // First try base64 with improved performance
    if (base64String != null && base64String.isNotEmpty) {
      try {
        // print('Attempting to load image from base64');
        return FutureBuilder<Uint8List>(
          future: _decodeBase64Async(base64String),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data!,
                width: width,
                height: height,
                fit: BoxFit.cover,
                cacheWidth:
                    _safeCacheSize(width * 2), // Cache at 2x for quality
                cacheHeight: _safeCacheSize(height * 2),
                errorBuilder: (context, error, stackTrace) {
                  print('Error loading image from base64: $error');
                  return _buildScanImageFallback(width, height);
                },
              );
            } else if (snapshot.hasError) {
              print('Error decoding Base64 image: ${snapshot.error}');
              return _buildScanImageFallback(width, height);
            } else {
              return Container(
                width: width,
                height: height,
                color: Colors.grey[200],
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
          },
        );
      } catch (e) {
        print('Error setting up base64 decoder: $e');
        return _buildScanImageFallback(width, height);
      }
    }

    // Then try network or file image
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http')) {
        // Network image
        // print('Attempting to load network image from: $path');
        return CachedNetworkImage(
          imageUrl: path,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.green,
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            print('Error loading network image from $url: $error');
            return _buildScanImageFallback(width, height);
          },
        );
      } else {
        // Local file image
        // print('Attempting to load file image from: $path');
        try {
          // Normalize file path for mobile
          String normalizedPath = path;

          // Handle any URL-encoded characters in the file path
          if (path.contains('%')) {
            try {
              normalizedPath = Uri.decodeFull(path);
              print('Decoded path: $normalizedPath');
            } catch (e) {
              print('Error decoding path: $e');
              // Keep the original path if decoding fails
            }
          }

          // Handle specific mobile platform path issues
          if (Platform.isAndroid) {
            // For Android, handle content:// URIs and other special cases
            if (path.startsWith('content://') || path.startsWith('file:///')) {
              print('Android-specific path detected: $path');
              // For content:// and file:/// URIs on Android, try to use a direct file path approach
              try {
                return Image.file(
                  File(normalizedPath),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading Android content URI: $error');
                    return _buildScanImageFallback(width, height);
                  },
                );
              } catch (e) {
                print('Error with Android-specific path: $e');
                return _buildScanImageFallback(width, height);
              }
            }
          } else if (Platform.isIOS) {
            // For iOS, handle specific path issues
            print('iOS path handling for: $normalizedPath');
            // iOS paths should work without special handling in most cases
          }

          // Try to load the file
          final file = File(normalizedPath);

          print('Checking if file exists at: $normalizedPath');
          if (file.existsSync()) {
            print('File exists, loading from: $normalizedPath');
            return Image.file(
              file,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading file image: $error');
                return _buildScanImageFallback(width, height);
              },
            );
          } else {
            print('File does not exist at path: $normalizedPath');

            // Try as a network URL if it appears to be a remote path
            if (normalizedPath.contains('://') ||
                normalizedPath.contains('storage/')) {
              // print(
              //     'Attempting to load as network image from: $normalizedPath');
              return CachedNetworkImage(
                imageUrl: normalizedPath,
                width: width,
                height: height,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  print('Error loading as network image: $error');
                  return _buildScanImageFallback(width, height);
                },
              );
            }

            return _buildScanImageFallback(width, height);
          }
        } catch (e) {
          print('Exception while loading file image: $e');
          return _buildScanImageFallback(width, height);
        }
      }
    }

    // Fallback
    print('No valid image source provided, using fallback');
    return _buildScanImageFallback(width, height);
  }

  // Helper method to convert an image file to Base64
  Future<String?> _convertImageToBase64(String imagePath) async {
    try {
      if (imagePath.startsWith('http')) {
        // For network images, download first
        print('Converting network image to base64: $imagePath');
        final response = await http.get(Uri.parse(imagePath));
        if (response.statusCode == 200) {
          return base64Encode(response.bodyBytes);
        }
        print('Failed to download image: ${response.statusCode}');
        return null;
      } else {
        // For local file images, handle URL-encoded paths
        String normalizedPath = imagePath;

        // Decode URL-encoded characters if present
        if (imagePath.contains('%')) {
          try {
            normalizedPath = Uri.decodeFull(imagePath);
            print('Decoded path for base64 conversion: $normalizedPath');
          } catch (e) {
            print('Error decoding path for base64 conversion: $e');
            // Use original path if decoding fails
          }
        }

        // Handle Android and iOS specific paths
        if (Platform.isAndroid) {
          // Special handling for Android content:// URIs
          if (imagePath.startsWith('content://')) {
            try {
              print('Handling Android content URI for base64: $imagePath');
              // For Android content:// URIs, we need to use FileUtils or content resolver
              // For now, try direct file access which might work in some cases
              final bytes = await File(normalizedPath).readAsBytes();
              return base64Encode(bytes);
            } catch (contentError) {
              print('Error with Android content URI conversion: $contentError');
              // If direct approach fails, we'll fall back to network approach below
            }
          }
        } else if (Platform.isIOS) {
          // Handle iOS-specific paths if needed
          print('iOS path handling for base64 conversion: $normalizedPath');
        }

        print('Converting file image to base64: $normalizedPath');
        final File imageFile = File(normalizedPath);

        // Check if file exists
        if (await imageFile.exists()) {
          final bytes = await imageFile.readAsBytes();
          return base64Encode(bytes);
        } else {
          print('File does not exist for base64 conversion: $normalizedPath');

          // Try to load as network URL if path looks like a remote path
          if (normalizedPath.contains('://') ||
              normalizedPath.contains('storage/')) {
            print('Trying as network URL instead: $normalizedPath');
            try {
              final response = await http.get(Uri.parse(normalizedPath));
              if (response.statusCode == 200) {
                return base64Encode(response.bodyBytes);
              }
              print('Failed to download image: ${response.statusCode}');
            } catch (netError) {
              print('Network error trying to convert to base64: $netError');
            }
          }
        }
        return null;
      }
    } catch (e) {
      print('Error converting image to Base64: $e');
      return null;
    }
  }

  // Helper for image fallback when loading fails
  Widget _buildScanImageFallback(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported,
            color: Colors.grey,
            size: 30,
          ),
          SizedBox(height: 4),
          Text(
            "No image",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    try {
      final DateTime date = timestamp is DateTime
          ? timestamp
          : timestamp.toDate(); // For Firestore Timestamp
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatRipeness(dynamic ripeness) {
    if (ripeness == null) return 'N/A';

    if (ripeness is double) {
      return '${ripeness.toStringAsFixed(1)}%';
    } else if (ripeness is int) {
      return '$ripeness%';
    } else if (ripeness is String) {
      return '$ripeness%';
    }

    return 'N/A';
  }

  // Show detailed information about a scan
  void _showScanDetailsDialog(Map<String, dynamic> scan) {
    final String fruitName = scan['name'] ?? 'Unknown Item';

    // Check for image in different formats: base64, url, or file path
    String? imagePath = scan['imageUrl'];
    String? base64Image = scan['imageBase64'];

    if ((imagePath == null || imagePath.isEmpty) &&
        scan.containsKey('imagePath')) {
      imagePath = scan['imagePath'];
    }

    final String confidence = scan['confidence'] != null
        ? '${(scan['confidence'] * 100).toStringAsFixed(1)}%'
        : 'N/A';
    final String category = scan['category'] ?? 'Uncategorized';
    final String scanDate = _formatTimestamp(scan['timestamp']);
    final String status = scan['harvestStatus'] ?? 'Unknown';
    final String harvestDate = _formatTimestamp(scan['harvestDate']);
    final String ripeness = _formatRipeness(scan['ripeness'] ?? 'Unknown');
    final String analysis = scan['detailedAnalysis'] ?? 'No analysis available';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImageWidget(imagePath, base64Image,
                          width: 80, height: 80),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fruitName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Category: $category',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scan Date: $scanDate',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: $status',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Harvest date: $harvestDate',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ripeness: $ripeness',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Confidence: $confidence',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Analysis: $analysis',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Recent scans section with refresh capability
  Widget _buildRecentScansSection() {
    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                ShimmerSkeleton(
                  child:
                      SkeletonWidget(height: 20, width: 120, borderRadius: 4),
                ),
                Spacer(),
                ShimmerSkeleton(
                  child: SkeletonWidget(height: 20, width: 60, borderRadius: 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240, // Increased height for new card design
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              itemBuilder: (context, index) {
                return const ShimmerSkeleton(
                  child: SkeletonFeatureCard(),
                );
              },
            ),
          ),
        ],
      );
    } else if (_hasScans) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Recent Scans',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.refresh,
                                size: 20, color: Colors.grey.shade700),
                            onPressed: () {
                              // Skip if already loading (during analysis)
                              if (_isLoading) return;

                              setState(() {
                                _isLoading = true;
                              });
                              _loadRecentScans().then((_) {
                                if (mounted) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                }
                              });
                            },
                            tooltip: 'Refresh',
                            splashRadius: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextButton.icon(
                            onPressed: () {
                              // Show all scans
                              Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: AllScansPage(
                                    scans: _recentScans,
                                    onRefresh: () async {
                                      await _loadRecentScans();
                                    },
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.arrow_forward,
                                color: Colors.white, size: 16),
                            label: const Text(
                              'View All',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your latest fruit and vegetable scans',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240, // Increased height for new card design
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recentScans.length,
              itemBuilder: (context, index) {
                return _buildScanItem(_recentScans[index]);
              },
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Recent Scans',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.refresh,
                            size: 20, color: Colors.grey.shade700),
                        onPressed: () {
                          // Skip if already loading (during analysis)
                          if (_isLoading) return;

                          setState(() {
                            _isLoading = true;
                          });
                          _loadRecentScans().then((_) {
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          });
                        },
                        tooltip: 'Refresh',
                        splashRadius: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your latest fruit and vegetable scans',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.grey.shade50,
                  Colors.grey.shade100,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.camera_enhance_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Scans Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start scanning fruits and vegetables\nto see your history here',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 1; // Navigate to camera
                      });
                    },
                    icon: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 20),
                    label: const Text(
                      'Start Scanning',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  // Profile dialog method similar to CameraPage's _showProfileDialog
  void _showProfileDialog(BuildContext context) {
    final currentUser = _authService.currentUser;
    final screenSize = MediaQuery.of(context).size;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: screenSize.width > 600 ? 400 : screenSize.width * 0.9,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: currentUser == null
                ? _buildLoginPrompt()
                : StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUser.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(
                              color: Color(0xFFE65100),
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error: ${snapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(Icons.close),
                                  label: const Text('Close'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final userData =
                          snapshot.data?.data() as Map<String, dynamic>?;

                      if (userData == null) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text('No user data found'),
                          ),
                        );
                      }

                      final name = userData['name'] as String? ?? 'No name set';
                      final email =
                          userData['email'] as String? ?? 'No email set';
                      final profilePicture =
                          userData['profilePicture'] as String?;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header with gradient background and profile info
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(28),
                                topRight: Radius.circular(28),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Close button positioned at top-right
                                Align(
                                  alignment: Alignment.topRight,
                                  child: InkWell(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Profile picture with gradient ring and edit option
                                Stack(
                                  children: [
                                    // Gradient ring around avatar
                                    GestureDetector(
                                      onTap: () => _pickProfilePicture(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF4CAF50),
                                              Color(0xFF2E7D32)
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.12),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 50,
                                            backgroundColor: Colors.white,
                                            child: ClipOval(
                                              child: SizedBox(
                                                width: 96,
                                                height: 96,
                                                child: profilePicture != null
                                                    ? (_userService
                                                            .getProfilePictureWidget(
                                                                profilePicture) ??
                                                        Icon(
                                                          Icons.person,
                                                          size: 50,
                                                          color:
                                                              Colors.grey[300],
                                                        ))
                                                    : Icon(
                                                        Icons.person,
                                                        size: 50,
                                                        color: Colors.grey[300],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Edit camera button
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () =>
                                            _pickProfilePicture(context),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE65100),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.2),
                                                spreadRadius: 1,
                                                blurRadius: 3,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // User name
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                // User email
                                Text(
                                  email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // User details section with cards
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Account Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF333333),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Info cards - Name
                                _buildInfoCard(
                                  icon: Icons.person,
                                  label: 'Name',
                                  value: name,
                                  iconColor: const Color(0xFF2E7D32),
                                ),

                                const SizedBox(height: 12),

                                // Info cards - Email (copy to clipboard)
                                _buildInfoCard(
                                  icon: Icons.email,
                                  label: 'Email',
                                  value: email,
                                  iconColor: const Color(0xFF1565C0),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    color: const Color(0xFF1565C0),
                                    tooltip: 'Copy email',
                                    onPressed: () {
                                      Clipboard.setData(
                                          ClipboardData(text: email));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('Email copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: email));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Email copied to clipboard'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 12),

                                // Info cards - Password
                                _buildInfoCard(
                                  icon: Icons.lock,
                                  label: 'Password',
                                  value: '••••••••••',
                                  iconColor: const Color(0xFFE65100),
                                ),

                                const SizedBox(height: 24),

                                // Close button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    icon: const Icon(Icons.close),
                                    label: const Text('Close'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  // Helper widget for login prompt
  Widget _buildLoginPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_circle,
            size: 70,
            color: Color(0xFFE65100),
          ),
          const SizedBox(height: 24),
          const Text(
            'Not Logged In',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Please log in to view and manage your profile information.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed('/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Go to Login',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for info cards in the profile dialog
  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final cardContent = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: cardContent,
      ),
    );
  }

  // Upload profile picture - similar to CameraPage's _pickProfilePicture
  Future<void> _pickProfilePicture(BuildContext context) async {
    try {
      // Close the profile dialog temporarily to show loading clearly
      Navigator.of(context).pop();

      // Show a loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.white,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('Processing image...'),
                ],
              ),
            ),
          );
        },
      );

      // Show image picker with both camera and gallery options
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      // Close the loading dialog as we are showing the image picker
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (source == null) {
        // Reopen the profile dialog if user cancels
        if (mounted) {
          _showProfileDialog(context);
        }
        return;
      }

      // Show loading dialog again as we're picking the image
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Selecting image...'),
                  ],
                ),
              ),
            );
          },
        );
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 75, // Reduce quality to improve performance
      );

      // Close the loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (pickedFile == null) {
        // Reopen the profile dialog if user cancels
        if (mounted) {
          _showProfileDialog(context);
        }
        return;
      }

      // Show loading dialog for upload process
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.white,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Uploading profile picture...'),
                  ],
                ),
              ),
            );
          },
        );
      }

      final file = File(pickedFile.path);
      final currentUser = _authService.currentUser;

      if (currentUser != null) {
        try {
          await _userService.saveProfilePicture(currentUser.uid, file);

          // Close the loading dialog
          if (mounted) {
            Navigator.of(context).pop();
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile picture updated successfully'),
                backgroundColor: Colors.green,
              ),
            );

            // Reopen the profile dialog to show updated data
            _showProfileDialog(context);
          }
        } catch (uploadError) {
          // Close the loading dialog
          if (mounted) {
            Navigator.of(context).pop();
          }

          if (mounted) {
            String errorMessage = uploadError.toString();
            if (errorMessage.contains('large')) {
              errorMessage =
                  'Image is too large. Please choose a smaller image.';
            } else if (errorMessage.contains('network')) {
              errorMessage =
                  'Network error. Please check your connection and try again.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );

            // Reopen the profile dialog even if there was an error
            _showProfileDialog(context);
          }
        }
      } else {
        // Close the loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in to update your profile'),
              backgroundColor: Colors.red,
            ),
          );

          // Reopen the profile dialog
          _showProfileDialog(context);
        }
      }
    } catch (e) {
      // Make sure any open dialogs are closed
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );

        // Reopen the profile dialog after showing error
        _showProfileDialog(context);
      }
    }
  }

  // List of feature titles and descriptions from the old landing page
  final List<Map<String, dynamic>> _features = [
    {
      'title': 'Identify Fruits & Vegetables',
      'description': 'Take a photo and get instant identification',
      'icon': Icons.camera_alt_rounded,
    },
    {
      'title': 'Weather Forecast',
      'description': 'Get local weather and plant care suggestions',
      'icon': Icons.cloud_outlined,
    },
    {
      'title': 'Harvest at the Right Time',
      'description': 'Get notifications for optimal harvesting',
      'icon': Icons.access_time_filled_rounded,
    },
  ];

  // Widget methods for Track and Harvest pages
  Widget _buildWeatherPage() {
    if (_isLoading) {
      return Center(
        child: ShimmerSkeleton(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonWidget(height: 80, width: 80, borderRadius: 40),
              SizedBox(height: 20),
              SkeletonWidget(height: 24, width: 200, borderRadius: 4),
              SizedBox(height: 10),
              SkeletonWidget(height: 16, width: 240, borderRadius: 4),
              SizedBox(height: 30),
              SkeletonWidget(height: 48, width: 150, borderRadius: 24),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1565C0),
                  const Color(0xFF0D47A1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Weather Forecast',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.3),
                        child: IconButton(
                          icon: const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            _showFeatureInfoDialog(context, 'Weather Forecast',
                                'Get local weather forecasts and plant care recommendations based on weather conditions. Plan your gardening activities for optimal results.');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Current weather
                  _isLoadingWeather
                      ? Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(
                                  color: Colors.white),
                              const SizedBox(height: 10),
                              Text(
                                'Fetching weather data...',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _weatherError != null
                          ? Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.cloud_off,
                                      color: Colors.white, size: 50),
                                  const SizedBox(height: 10),
                                  Text(
                                    _weatherError!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton(
                                    onPressed: _fetchWeatherData,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF1565C0),
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _weatherData?.location ?? 'Unknown',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${_weatherData?.temperature.toStringAsFixed(1) ?? "?"}°C',
                                      style: const TextStyle(
                                        fontSize: 42,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      _weatherData?.description ?? 'Unknown',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                _weatherData?.iconCode != null
                                    ? Image.network(
                                        _weatherData!.iconUrl,
                                        width: 80,
                                        height: 80,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.wb_sunny,
                                            size: 80,
                                            color: Colors.yellow,
                                          );
                                        },
                                      )
                                    : const Icon(
                                        Icons.wb_sunny,
                                        size: 80,
                                        color: Colors.yellow,
                                      ),
                              ],
                            ),
                  const SizedBox(height: 20),
                  _weatherData == null
                      ? const SizedBox()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildWeatherDetail(
                                icon: Icons.water_drop,
                                value: '${_weatherData!.humidity}%',
                                label: 'Humidity'),
                            _buildWeatherDetail(
                                icon: Icons.air,
                                value:
                                    '${_weatherData!.windSpeed.toStringAsFixed(1)} m/s',
                                label: 'Wind'),
                            _buildWeatherDetail(
                                icon: Icons.thermostat,
                                value:
                                    '${_weatherData!.feelsLike.toStringAsFixed(1)}°C',
                                label: 'Feels Like'),
                          ],
                        ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Weekly forecast
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '5-Day Forecast',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                // Weekly forecast cards
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: _weatherForecast.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text('Forecast data not available'),
                          ),
                        )
                      : Column(
                          children:
                              List.generate(_weatherForecast.length, (index) {
                            final forecast = _weatherForecast[index];
                            return _buildForecastDay(
                              day: forecast['day'],
                              icon: forecast['icon'],
                              temp: forecast['temp'],
                              condition: forecast['condition'],
                              iconColor: forecast['color'],
                              divider: index < _weatherForecast.length - 1,
                            );
                          }),
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Plant care recommendations - now based on actual weather data
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weather-Based Plant Care',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                // Care recommendation cards based on actual weather
                if (_weatherData != null) ...[
                  // Watering recommendation based on temperature and humidity
                  _buildCareRecommendation(
                    title: _weatherData!.temperature > 25
                        ? 'Increase Watering'
                        : 'Regular Watering',
                    icon: Icons.water_drop,
                    iconColor: Colors.blue,
                    message: _weatherData!.temperature > 25 &&
                            _weatherData!.humidity < 50
                        ? 'Hot and dry conditions detected. Increase watering frequency for outdoor plants to once per day, preferably in the early morning or evening.'
                        : _weatherData!.temperature > 25
                            ? 'Warm conditions detected but humidity is adequate. Maintain regular watering schedule but check soil moisture more frequently.'
                            : 'Current conditions are moderate. Maintain your regular watering schedule based on plant type needs.',
                  ),

                  // Sun protection based on temperature and description
                  _buildCareRecommendation(
                    title: _weatherData!.description.contains('clear') ||
                            _weatherData!.description.contains('sun')
                        ? 'Sun Protection Needed'
                        : 'Light Management',
                    icon: Icons.wb_sunny,
                    iconColor: Colors.orange,
                    message: _weatherData!.description.contains('clear') ||
                            _weatherData!.description.contains('sun')
                        ? 'Strong sun detected. Consider providing shade for sensitive plants during peak hours (11am-3pm).'
                        : _weatherData!.description.contains('cloud') ||
                                _weatherData!.description.contains('overcast')
                            ? 'Limited sunlight due to cloud cover. Ensure plants that need full sun are positioned to maximize available light.'
                            : 'Current light conditions are good for most plants. Monitor sensitive varieties if conditions change.',
                  ),

                  // Wind protection based on wind speed
                  _buildCareRecommendation(
                    title: _weatherData!.windSpeed > 5
                        ? 'Wind Protection'
                        : 'Air Circulation',
                    icon: _weatherData!.windSpeed > 5
                        ? Icons.air
                        : Icons.air_outlined,
                    iconColor: _weatherData!.windSpeed > 8
                        ? Colors.red
                        : Colors.indigo,
                    message: _weatherData!.windSpeed > 8
                        ? 'Strong winds detected (${_weatherData!.windSpeed.toStringAsFixed(1)} m/s). Secure young plants and provide windbreaks for vulnerable crops.'
                        : _weatherData!.windSpeed > 5
                            ? 'Moderate wind conditions (${_weatherData!.windSpeed.toStringAsFixed(1)} m/s). Check stakes and supports on taller plants.'
                            : 'Current gentle breeze is beneficial for air circulation. No special wind protection needed.',
                  ),
                ] else ...[
                  // Fallback recommendations if weather data is not available
                  _buildCareRecommendation(
                    title: 'Watering Advisory',
                    icon: Icons.water_drop,
                    iconColor: Colors.blue,
                    message:
                        'Weather data unavailable. Check soil moisture manually before watering. As a general rule, water when the top inch of soil feels dry.',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Garden activity planner - base it on forecast if available
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ideal Days for Garden Activities',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: _weatherForecast.isEmpty
                      ? const Center(
                          child:
                              Text('Activity planning requires forecast data'),
                        )
                      : Column(
                          children: [
                            _buildGardenActivity(
                              activity: 'Planting',
                              days: _getIdealDaysForActivity('Planting'),
                              icon: Icons.spa,
                            ),
                            _buildGardenActivity(
                              activity: 'Harvesting',
                              days: _getIdealDaysForActivity('Harvesting'),
                              icon: Icons.shopping_basket,
                            ),
                            _buildGardenActivity(
                              activity: 'Pruning',
                              days: _getIdealDaysForActivity('Pruning'),
                              icon: Icons.content_cut,
                            ),
                            _buildGardenActivity(
                              activity: 'Fertilizing',
                              days: _getIdealDaysForActivity('Fertilizing'),
                              icon: Icons.compost,
                              divider: false,
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 20),

                // Location update button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoadingWeather = true;
                      });
                      _getCurrentLocation();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Updating weather for your location...'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.location_on),
                    label: const Text('Update Location & Weather'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
              height: 120), // Space for floating bottom navigation with margins
        ],
      ),
    );
  }

  // Helper method to determine ideal days for different activities based on forecast
  String _getIdealDaysForActivity(String activity) {
    if (_weatherForecast.isEmpty) return 'Data not available';

    List<String> idealDays = [];

    for (var forecast in _weatherForecast) {
      bool isIdeal = false;

      switch (activity) {
        case 'Planting':
          // Ideal for planting: moderate temperature, no strong sun, no rain
          isIdeal = !forecast['condition'].contains('Rain') &&
              !forecast['condition'].contains('Sunny');
          break;

        case 'Harvesting':
          // Ideal for harvesting: dry, sunny days
          isIdeal = forecast['condition'].contains('Sunny') ||
              forecast['condition'].contains('Clear');
          break;

        case 'Pruning':
          // Ideal for pruning: before rain or on cloudy days
          isIdeal = forecast['condition'].contains('Cloudy') ||
              (_weatherForecast.indexOf(forecast) <
                      _weatherForecast.length - 1 &&
                  _weatherForecast[_weatherForecast.indexOf(forecast) + 1]
                          ['condition']
                      .contains('Rain'));
          break;

        case 'Fertilizing':
          // Ideal for fertilizing: before light rain
          isIdeal = forecast['condition'].contains('Light Rain');
          break;
      }

      if (isIdeal) {
        idealDays.add(forecast['day']);
      }
    }

    return idealDays.isEmpty ? 'None this week' : idealDays.join(', ');
  }

  // Helper methods for weather page
  Widget _buildWeatherDetail({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildForecastDay({
    required String day,
    required IconData icon,
    required String temp,
    required String condition,
    required Color iconColor,
    bool divider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 20,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  day,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
              Text(
                condition,
                style: TextStyle(
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                temp,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (divider)
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: Colors.grey.shade200,
          ),
      ],
    );
  }

  Widget _buildCareRecommendation({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardenActivity({
    required String activity,
    required String days,
    required IconData icon,
    bool divider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF1565C0),
                  size: 20,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Best days: $days',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.calendar_today,
                size: 20,
                color: Colors.grey,
              ),
            ],
          ),
        ),
        if (divider)
          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
      ],
    );
  }

  // Information dialog for features
  void _showFeatureInfoDialog(
      BuildContext context, String title, String description) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 15),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                  ),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: _onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern header with glass-morphism effect
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF4CAF50),
                          Color(0xFF2E7D32),
                          Color(0xFF1B5E20),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: [0.0, 0.6, 1.0],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2E7D32).withOpacity(0.3),
                          spreadRadius: 0,
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'FruitVeggie',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                        shadows: [
                                          Shadow(
                                            color:
                                                Colors.black.withOpacity(0.3),
                                            offset: const Offset(0, 2),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'Smart Harvest Assistant',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withOpacity(0.9),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.2),
                                            Colors.white.withOpacity(0.1),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.person_outline,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          _showProfileDialog(context);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.2),
                                            Colors.white.withOpacity(0.1),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.logout_outlined,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          _showLogoutConfirmationDialog(
                                              context);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _isLoading
                                ? ShimmerSkeleton(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        SkeletonWidget(
                                            height: 32,
                                            width: 220,
                                            borderRadius: 4),
                                        SizedBox(height: 8),
                                        SkeletonWidget(
                                            height: 32,
                                            width: 180,
                                            borderRadius: 4),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Welcome Back! 👋',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          height: 1.3,
                                          shadows: [
                                            Shadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              offset: const Offset(0, 1),
                                              blurRadius: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Ready to explore your harvest?',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.white.withOpacity(0.9),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _isLoading
                            ? const ShimmerSkeleton(
                                child: SkeletonWidget(
                                    height: 20, width: 100, borderRadius: 4),
                              )
                            : Text(
                                'Explore Features ✨',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                        const Spacer(),
                        _isLoading
                            ? const ShimmerSkeleton(
                                child: SkeletonWidget(
                                    height: 20, width: 60, borderRadius: 4),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4CAF50),
                                      Color(0xFF2E7D32)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4CAF50)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: TextButton(
                                  onPressed: () {},
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text(
                                    'See All',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 260,
                    child: _isLoading
                        ? ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: 3,
                            itemBuilder: (context, index) {
                              return const ShimmerSkeleton(
                                child: SkeletonFeatureCard(),
                              );
                            },
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: _features.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedIndex =
                                        index + 1; // +1 because index 0 is home
                                  });
                                },
                                child: Container(
                                  width: 180,
                                  height: 240,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white,
                                        Colors.grey.shade50,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        spreadRadius: 0,
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        spreadRadius: 0,
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.8),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFF4CAF50)
                                                  .withOpacity(0.8),
                                              const Color(0xFF2E7D32)
                                                  .withOpacity(0.9),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _features[index]['icon'],
                                          size: 32,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Flexible(
                                        child: Text(
                                          _features[index]['title'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: Colors.grey.shade800,
                                            letterSpacing: 0.2,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Flexible(
                                        child: Text(
                                          _features[index]['description'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            height: 1.3,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 40),
                  // Recent scans section - replaced with new method
                  _buildRecentScansSection(),
                  // Active reminders section - add this line
                  if (_activeReminders.isNotEmpty) const SizedBox(height: 20),
                  _buildActiveRemindersSection(),
                  const SizedBox(
                      height:
                          120), // Space for floating bottom navigation with margins
                ],
              ),
            ),
            CameraPage(
              onBackToDashboard: () {
                setState(() {
                  _selectedIndex = 0;
                });
                // Refresh dashboard data when returning from camera
                refreshDashboardData();
              },
            ), // Camera page - already implemented
            _buildWeatherPage(), // Weather page - replacing Track page
            _buildHarvestPage(), // Harvest page
            _buildChartPage(), // Chart page - new addition
          ],
        ),
        bottomNavigationBar: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onPageSelected,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              selectedItemColor: const Color(0xFF4CAF50),
              unselectedItemColor: Colors.grey.shade500,
              showSelectedLabels: true,
              showUnselectedLabels: false,
              selectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: const Color(0xFF4CAF50),
                letterSpacing: 0.2,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 0),
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: _buildNavBarIcon(Icons.home_rounded, 0),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavBarIcon(_features[0]['icon'], 1),
                  label: 'Identify',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavBarIcon(Icons.cloud_outlined, 2),
                  label: 'Weather',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavBarIcon(_features[2]['icon'], 3),
                  label: 'Harvest',
                ),
                BottomNavigationBarItem(
                  icon: _buildNavBarIcon(Icons.bar_chart_rounded, 4),
                  label: 'Chart',
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4CAF50).withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () {
              setState(() {
                _selectedIndex = 1; // Navigate to camera
              });
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  // Build modern navigation bar icons with animations
  Widget _buildNavBarIcon(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(isSelected ? 12 : 8),
      decoration: BoxDecoration(
        gradient: isSelected
            ? const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
              )
            : null,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: isSelected ? 24 : 22,
        color: isSelected ? Colors.white : Colors.grey.shade500,
      ),
    );
  }

  // Modern logout confirmation dialog with improved handling
  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 5,
                    blurRadius: 15,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFE65100),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you sure you want to logout?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            try {
                              await _authService.signOut();
                              if (!context.mounted) return;

                              Navigator.of(context).pushReplacement(
                                SlidePageRoute(
                                  page: const LoginPage(),
                                  direction: SlideDirection.left,
                                  settings: const RouteSettings(name: '/login'),
                                ),
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Failed to log out: ${e.toString()}'),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Logout',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHarvestPage() {
    if (_isLoading) {
      return Center(
        child: ShimmerSkeleton(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonWidget(height: 80, width: 80, borderRadius: 40),
              SizedBox(height: 20),
              SkeletonWidget(height: 24, width: 200, borderRadius: 4),
              SizedBox(height: 10),
              SkeletonWidget(height: 16, width: 240, borderRadius: 4),
              SizedBox(height: 30),
              SkeletonWidget(height: 48, width: 150, borderRadius: 24),
            ],
          ),
        ),
      );
    }

    // Check if there's no scan data
    if (_lastProcessedProduceType == 'Produce' && _recentScans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.eco_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              'No produce scanned yet',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Use the scanner to analyze fruits and vegetables\nto see harvest recommendations',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedIndex = 1; // Navigate to camera
                });
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Scanning'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2E7D32),
                  const Color(0xFF1B5E20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Harvest',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: () {
                          // Skip if already loading (during analysis)
                          if (_isLoading) return;

                          setState(() {
                            _isLoading = true;
                          });
                          _loadRecentScans().then((_) {
                            _fetchLastProcessedImage().then((_) {
                              if (mounted) {
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            });
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    'Track your growing produce and know when it\'s ready to harvest',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 25),
                  // AI Analysis Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 80,
                                height: 80,
                                child: _lastProcessedImageBase64 != null
                                    ? Image.memory(
                                        base64Decode(
                                            _lastProcessedImageBase64!),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.eco,
                                              color: Color(0xFF2E7D32),
                                              size: 30,
                                            ),
                                          );
                                        },
                                      )
                                    : _lastProcessedImagePath != null
                                        ? Image.network(
                                            _lastProcessedImagePath!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey[200],
                                                child: const Icon(
                                                  Icons.eco,
                                                  color: Color(0xFF2E7D32),
                                                  size: 30,
                                                ),
                                              );
                                            },
                                          )
                                        : Container(
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.eco,
                                              color: Color(0xFF2E7D32),
                                              size: 30,
                                            ),
                                          ),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _lastProcessedProduceType,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  // Find the corresponding scan in recentScans
                                  _buildAIAnalysisBasedOnLatestScan(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        const Divider(),
                        const SizedBox(height: 15),
                        const Text(
                          'Care Recommendations',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._getProduceSpecificCareRecommendations(
                                _lastProcessedProduceType)
                            .map((recommendation) =>
                                _buildCareRecommendationItem(
                                  icon: recommendation['icon'] as IconData,
                                  text: recommendation['text'] as String,
                                )),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // Upcoming harvests section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Upcoming Harvests',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          SlidePageRoute(
                            page: AllHarvestsPage(
                              lastProcessedProduceType:
                                  _lastProcessedProduceType,
                              lastProcessedImagePath: _lastProcessedImagePath,
                              lastProcessedImageBase64:
                                  _lastProcessedImageBase64,
                              recentScans: _recentScans,
                              findScanDataForLatestProcessed:
                                  _findScanDataForLatestProcessed,
                              isSameScanAsLastProcessed:
                                  _isSameScanAsLastProcessed,
                              buildHarvestCard: _buildHarvestCard,
                              onRefresh: () async {
                                await _loadRecentScans();
                                await _fetchLastProcessedImage();
                              },
                            ),
                          ),
                        );
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Fixed condition for harvest cards based on actual scan data
                (_lastProcessedProduceType != 'Produce' &&
                            _lastProcessedImagePath != null) ||
                        _recentScans.isNotEmpty
                    ? Column(
                        children: [
                          // Show the latest processed produce
                          _lastProcessedProduceType != 'Produce' &&
                                  _lastProcessedImagePath != null
                              ? _buildHarvestCard(
                                  plantName: _lastProcessedProduceType,
                                  variety: 'From Recent Scan',
                                  imageUrl: _lastProcessedImagePath,
                                  imageBase64: _lastProcessedImageBase64,
                                  scanData: _findScanDataForLatestProcessed(),
                                )
                              : Container(),

                          // Only show scans that haven't been displayed as the last processed item
                          for (int i = 0; i < _recentScans.length && i < 2; i++)
                            if (!_isSameScanAsLastProcessed(_recentScans[i]))
                              _buildHarvestCard(
                                plantName: _recentScans[i]['name'] ?? 'Unknown',
                                variety: 'Recently Scanned',
                                imageUrl: _recentScans[i]['imagePath'] ??
                                    _recentScans[i]['imageUrl'],
                                imageBase64: _recentScans[i]['imageBase64'],
                                scanData: _recentScans[i],
                              ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              spreadRadius: 1,
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.eco_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No produce scanned yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use the scanner to analyze fruits and vegetables',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                const SizedBox(height: 20),

                // Setup reminder button
                // SizedBox(
                //   width: double.infinity,
                //   child: ElevatedButton.icon(
                //     onPressed: () {
                //       _showHarvestReminderDialog(context);
                //     },
                //     icon: const Icon(Icons.notifications_active),
                //     label: const Text('Setup Harvest Reminders'),
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: const Color(0xFFE65100),
                //       foregroundColor: Colors.white,
                //       padding: const EdgeInsets.symmetric(vertical: 15),
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(30),
                //       ),
                //     ),
                //   ),
                // ),

                const SizedBox(
                    height:
                        120), // Space for floating bottom navigation with margins
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Improved method to find scan data for the latest processed image with more robust matching
  Map<String, dynamic>? _findScanDataForLatestProcessed() {
    if (_recentScans.isEmpty) return null;

    // First check if any scan matches our last processed image by scanId (most reliable)
    for (final scan in _recentScans) {
      if (scan.containsKey('scanId') && scan['scanId'] != null) {
        // Check if this scan matches the last processed image path
        if (_lastProcessedImagePath != null &&
            (scan['imagePath'] == _lastProcessedImagePath ||
                scan['imageUrl'] == _lastProcessedImagePath)) {
          return scan;
        }
      }
    }

    // Then try matching by image path
    if (_lastProcessedImagePath != null) {
      for (final scan in _recentScans) {
        final scanImagePath = scan['imagePath'] ?? scan['imageUrl'];
        if (scanImagePath == _lastProcessedImagePath) {
          return scan;
        }

        // If the path is URL-encoded or has platform-specific differences
        // Try to match the last part of the path (the filename)
        if (scanImagePath != null && _lastProcessedImagePath != null) {
          final scanPathParts = scanImagePath?.split('/') ?? [];
          final lastProcessedPathParts =
              _lastProcessedImagePath?.split('/') ?? [];

          if (scanPathParts.isNotEmpty && lastProcessedPathParts.isNotEmpty) {
            final scanFilename = scanPathParts.last;
            final lastProcessedFilename = lastProcessedPathParts.last;

            if (scanFilename == lastProcessedFilename) {
              return scan;
            }
          }
        }
      }
    }

    // If no match found, return the first scan
    return _recentScans.first;
  }

  // Improved method to check if a scan is the same as the last processed one
  bool _isSameScanAsLastProcessed(Map<String, dynamic> scan) {
    if (_lastProcessedImagePath == null) return false;

    // Check scanId first (most reliable)
    if (scan.containsKey('scanId') && scan['scanId'] != null) {
      for (final existingScan in _recentScans) {
        if (existingScan.containsKey('scanId') &&
            existingScan['scanId'] == scan['scanId'] &&
            _lastProcessedImagePath ==
                (existingScan['imagePath'] ?? existingScan['imageUrl'])) {
          return true;
        }
      }
    }

    // Check image path
    final scanImagePath = scan['imagePath'] ?? scan['imageUrl'];
    if (scanImagePath == _lastProcessedImagePath) {
      return true;
    }

    // Check filename as fallback
    if (scanImagePath != null && _lastProcessedImagePath != null) {
      final scanPathParts = scanImagePath?.split('/') ?? [];
      final lastProcessedPathParts = _lastProcessedImagePath?.split('/') ?? [];

      if (scanPathParts.isNotEmpty && lastProcessedPathParts.isNotEmpty) {
        final scanFilename = scanPathParts.last;
        final lastProcessedFilename = lastProcessedPathParts.last;

        if (scanFilename == lastProcessedFilename) {
          return true;
        }
      }
    }

    return false;
  }

  // Helper method to build AI analysis details based on the latest scan
  Widget _buildAIAnalysisBasedOnLatestScan() {
    // Find the relevant scan data
    final scanData = _findScanDataForLatestProcessed();

    if (scanData == null) {
      // No scan data available
      return const Text(
        'No analysis data available',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      );
    }

    // Format the analysis information
    String analysisText = 'Recently analyzed';

    // Check if we have prediction data with better type handling
    if (scanData.containsKey('final_prediction') ||
        scanData.containsKey('gemini_prediction')) {
      // Handle both boolean and string values for final_prediction
      bool isReady = false;

      if (scanData.containsKey('final_prediction')) {
        final prediction = scanData['final_prediction'];
        if (prediction is bool) {
          isReady = prediction;
        } else if (prediction is String) {
          isReady = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      } else if (scanData.containsKey('gemini_prediction')) {
        final prediction = scanData['gemini_prediction'];
        if (prediction is bool) {
          isReady = prediction;
        } else if (prediction is String) {
          isReady = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      }

      // Get confidence with better null handling
      final confidenceValue = scanData['confidence'];
      String confidence = 'Medium';
      double confidenceDouble = 0.5;

      if (confidenceValue != null) {
        if (confidenceValue is double) {
          // Format as percentage if it's a number between 0 and 1
          confidenceDouble = confidenceValue <= 1.0
              ? confidenceValue
              : confidenceValue / 100.0;
          confidence = '${(confidenceDouble * 100).toStringAsFixed(1)}%';
        } else if (confidenceValue is int) {
          confidenceDouble = confidenceValue / 100.0;
          confidence = '$confidenceValue%';
        } else if (confidenceValue is String) {
          try {
            // Try to parse percentage string
            final String confStr = confidenceValue.replaceAll('%', '').trim();
            confidenceDouble = double.parse(confStr) / 100.0;
            confidence = '$confStr%';
          } catch (e) {
            // If parsing fails, use confidence description
            if (confidenceValue.toLowerCase().contains('high')) {
              confidence = 'High';
              confidenceDouble = 0.85;
            } else if (confidenceValue.toLowerCase().contains('medium')) {
              confidence = 'Medium';
              confidenceDouble = 0.65;
            } else if (confidenceValue.toLowerCase().contains('low')) {
              confidence = 'Low';
              confidenceDouble = 0.4;
            } else {
              // Just use the original string
              confidence = confidenceValue;
            }
          }
        }
      }

      // Create a more informative status message based on readiness and confidence
      if (isReady) {
        if (confidenceDouble >= 0.8) {
          analysisText = 'Ready to harvest now (High confidence: $confidence)';
        } else if (confidenceDouble >= 0.6) {
          analysisText = 'Ready to harvest now (Confidence: $confidence)';
        } else {
          analysisText = 'Likely ready for harvest (Confidence: $confidence)';
        }
      } else {
        analysisText = 'Not ready for harvest yet (Confidence: $confidence)';
      }

      // Intelligent days information handling using the same logic as _buildHarvestCard
      int daysUntilHarvest = 0;

      // Check if there's an explicit days_until_harvest field
      if (scanData.containsKey('days_until_harvest')) {
        final daysValue = scanData['days_until_harvest'];

        // Handle different types
        if (daysValue is int) {
          daysUntilHarvest = daysValue;
        } else if (daysValue is double) {
          daysUntilHarvest = daysValue.round();
        } else if (daysValue is String && daysValue.isNotEmpty) {
          try {
            daysUntilHarvest = int.parse(daysValue);
          } catch (e) {
            debugPrint(
                'Error parsing days_until_harvest in analysis display: $e');
            daysUntilHarvest =
                isReady ? 0 : _estimateDaysFromScanData(scanData, null);
          }
        } else {
          // For null or other types, use estimation
          daysUntilHarvest =
              isReady ? 0 : _estimateDaysFromScanData(scanData, null);
        }

        // Ensure days is consistent with readiness
        if (isReady && daysUntilHarvest > 0) {
          daysUntilHarvest = 0;
        }
      } else {
        // No explicit days field, use intelligent estimation
        daysUntilHarvest =
            isReady ? 0 : _estimateDaysFromScanData(scanData, null);
      }

      // Add days information with appropriate wording
      if (!isReady && daysUntilHarvest > 0) {
        if (daysUntilHarvest == 1) {
          analysisText += '\nExpected to be ready tomorrow';
        } else if (daysUntilHarvest <= 3) {
          analysisText +=
              '\nExpected to be ready in $daysUntilHarvest days (very soon)';
        } else if (daysUntilHarvest <= 7) {
          analysisText +=
              '\nEstimated days until harvest: $daysUntilHarvest (this week)';
        } else if (daysUntilHarvest <= 14) {
          analysisText +=
              '\nEstimated days until harvest: $daysUntilHarvest (next couple weeks)';
        } else {
          analysisText += '\nEstimated days until harvest: $daysUntilHarvest';
        }
      }
    } else {
      // Fall back to simple analysis if no prediction data
      analysisText = 'Scan information captured successfully';

      // Look for any gemini response for clues
      if (scanData.containsKey('gemini_response') ||
          scanData.containsKey('ai_response')) {
        final String responseText = scanData['gemini_response'] ??
            scanData['ai_response'] ??
            'Not available';

        // Extract key information from the response
        final String cleanResponse = responseText.replaceAll('\n', ' ').trim();

        if (cleanResponse.length <= 100) {
          analysisText = 'Analysis: $cleanResponse';
        } else {
          // Look for key sentences about ripeness or harvest
          final List<String> sentences = cleanResponse.split(RegExp(r'[.!?]'));
          String importantInfo = '';

          for (final sentence in sentences) {
            if (sentence.toLowerCase().contains('ripe') ||
                sentence.toLowerCase().contains('harvest') ||
                sentence.toLowerCase().contains('ready') ||
                sentence.toLowerCase().contains('day')) {
              importantInfo = sentence.trim();
              break;
            }
          }

          if (importantInfo.isNotEmpty) {
            analysisText = 'Analysis: $importantInfo...';
          } else {
            // Just take the first part if we couldn't find relevant sentences
            analysisText = 'Analysis: ${cleanResponse.substring(0, 97)}...';
          }
        }
      }
    }

    return Text(
      analysisText,
      style: TextStyle(
        fontSize: 14,
        color: Colors.grey[700],
        height: 1.3,
      ),
    );
  }

  // Care recommendation item for harvest page
  Widget _buildCareRecommendationItem({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // Harvest card
  Widget _buildHarvestCard({
    required String plantName,
    required String variety,
    int? daysLeft,
    String? imageUrl,
    String? imageBase64,
    Map<String, dynamic>? scanData,
  }) {
    // Enhanced logic for days until harvest calculation
    int effectiveDaysLeft;
    bool isReadyForHarvest = false;
    bool isOverripe = false;

    if (scanData != null) {
      // First check the harvestStatus field (updated in result_page.dart)
      if (scanData.containsKey('harvestStatus')) {
        final status = scanData['harvestStatus'].toString().toLowerCase();
        isReadyForHarvest = status == 'ready_for_harvest' ||
            status == 'ready' ||
            (status.contains('ready') && !status.contains('not'));
        isOverripe = status == 'overripe' || status.contains('over');
      }
      // Then check Ready for Harvest field
      else if (scanData.containsKey('Ready for Harvest')) {
        final status = scanData['Ready for Harvest'].toString().toLowerCase();
        isReadyForHarvest = status == 'ready_for_harvest' ||
            status == 'ready' ||
            (status.contains('ready') && !status.contains('not'));
        isOverripe = status == 'overripe' || status.contains('over');
      }
      // Fall back to final_prediction as a last resort
      else if (scanData.containsKey('final_prediction')) {
        // Handle both boolean and string values for final_prediction
        final prediction = scanData['final_prediction'];
        if (prediction is bool) {
          isReadyForHarvest = prediction;
        } else if (prediction is String) {
          isReadyForHarvest = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      } else if (scanData.containsKey('gemini_prediction')) {
        // Handle both boolean and string values for gemini_prediction
        final prediction = scanData['gemini_prediction'];
        if (prediction is bool) {
          isReadyForHarvest = prediction;
        } else if (prediction is String) {
          isReadyForHarvest = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      }

      debugPrint('days until harvest raw: ${scanData['daysUntilHarvest']}');
      // Normalize days_until_harvest
      if (scanData.containsKey('daysUntilHarvest')) {
        final daysValue = scanData['daysUntilHarvest'];

        // Handle different data types for days_until_harvest
        if (daysValue is int) {
          effectiveDaysLeft = daysValue;
        } else if (daysValue is double) {
          effectiveDaysLeft = daysValue.round();
        } else if (daysValue is String && daysValue.isNotEmpty) {
          try {
            effectiveDaysLeft = int.parse(daysValue);
          } catch (e) {
            print('Error parsing days_until_harvest as int: $e');
            // Use smart default based on readiness
            effectiveDaysLeft = isReadyForHarvest
                ? 0
                : isOverripe
                    ? -1
                    : _estimateDaysFromScanData(scanData, daysLeft);
          }
        } else {
          // For null or other unsupported types
          effectiveDaysLeft = isReadyForHarvest
              ? 0
              : isOverripe
                  ? -1
                  : _estimateDaysFromScanData(scanData, daysLeft);
        }
      } else {
        // No days_until_harvest in scan data - use intelligent estimation
        effectiveDaysLeft = isReadyForHarvest
            ? 0
            : isOverripe
                ? -1
                : _estimateDaysFromScanData(scanData, daysLeft);
      }

      // Handle overripe status correctly - show as -1 days (past harvest date)
      if (isOverripe && effectiveDaysLeft >= 0) {
        effectiveDaysLeft = -1;
      }

      // Ensure consistency: if ready for harvest, days should be 0
      if (isReadyForHarvest && effectiveDaysLeft > 0) {
        effectiveDaysLeft = 0;
      }
    } else {
      // Fallback to provided daysLeft or use a better default than just 7
      effectiveDaysLeft = daysLeft ?? 0;
    }

    // Calculate readiness percentage with enhanced logic
    final double effectiveReadiness;

    if (isOverripe || effectiveDaysLeft < 0) {
      // Overripe - over 100% readiness
      effectiveReadiness = 1.2; // More than 100% to indicate overripe
    } else if (isReadyForHarvest || effectiveDaysLeft == 0) {
      // Ready for harvest - 100% readiness
      effectiveReadiness = 1.0;
    } else {
      // Not ready - calculate percentage based on days left
      // Use a more intuitive scale: 30 days = 0% ready, 0 days = 100% ready
      effectiveReadiness = 1.0 - (effectiveDaysLeft / 30).clamp(0.0, 1.0);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image section
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(15),
            ),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: _buildImageWidget(imageUrl, imageBase64,
                  width: double.infinity, height: 150),
            ),
          ),

          // Content section
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.eco,
                      color: Color(0xFF2E7D32),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      variety,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  plantName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),

                // Readiness indicator
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          effectiveDaysLeft < 0
                              ? 'Past optimal harvest time'
                              : effectiveDaysLeft == 0
                                  ? 'Ready to harvest now!'
                                  : '$effectiveDaysLeft days until harvest',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: effectiveDaysLeft < 0
                                ? Colors.red[700]
                                : effectiveDaysLeft == 0
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey[700],
                          ),
                        ),
                        Text(
                          effectiveReadiness > 1.0
                              ? 'Overripe'
                              : '${(effectiveReadiness * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: effectiveReadiness > 1.0
                                ? Colors.red[700]
                                : effectiveReadiness >= 0.9
                                    ? const Color(0xFF2E7D32)
                                    : effectiveReadiness >= 0.6
                                        ? Colors.amber[700]
                                        : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: effectiveReadiness,
                        backgroundColor: Colors.grey[200],
                        color: effectiveReadiness >= 0.9
                            ? const Color(0xFF2E7D32)
                            : effectiveReadiness >= 0.6
                                ? Colors.amber[700]
                                : Colors.grey[700],
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),

                // Additional data from scan if available
                if (scanData != null && scanData.containsKey('confidence'))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Confidence: ${scanData['confidence'] is double ? (scanData['confidence'] * 100).toStringAsFixed(1) + '%' : scanData['confidence'].toString()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),

                // Add reminder button for produce not ready yet
                if (effectiveDaysLeft > 0 &&
                    scanData != null &&
                    scanData.containsKey('scanId'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _scheduleReminderFromScan(scanData),
                          icon:
                              const Icon(Icons.notifications_active, size: 16),
                          label: const Text('Set Reminder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show harvest reminder dialog
  void _showHarvestReminderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Color(0xFFE65100),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Harvest Reminders',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Get notified when your fruits and vegetables are ready to harvest for optimal flavor and nutrition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('AI-based ripeness notifications'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Custom reminder schedules'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Weather-aware recommendations'),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _setupHarvestReminders();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Harvest reminders enabled! You will be notified when your produce is ready.'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text('Enable Reminders'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Later'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Add a method to setup harvest reminders from existing scans
  Future<void> _setupHarvestReminders() async {
    try {
      final user = _authService.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You need to be logged in to set up reminders'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Setting up harvest reminders...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This may take a moment as we analyze your produce',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Check if we have any scans to process
      if (_recentScans.isEmpty) {
        // Pop the loading dialog
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No scans found to set reminders for. Try scanning some produce first!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Count set up reminders
      int reminderCount = 0;
      int updatedCount = 0;
      List<String> setReminders = [];
      Set<String> processedProduceTypes = {};

      // First check for any pending reminders in recentScans
      for (final scan in _recentScans) {
        if (scan.containsKey('name') && scan['name'] != null) {
          final String produceType = scan['name'] as String;

          // Skip if we already processed this produce type
          if (processedProduceTypes.contains(produceType)) {
            debugPrint('Skipping duplicate reminder for $produceType');
            continue;
          }

          try {
            // Check if this produce type already has an active reminder
            final existingReminders = _activeReminders
                .where((reminder) =>
                    reminder['produceType'] == produceType &&
                    !(reminder['isDismissed'] as bool? ?? false))
                .toList();

            final bool hasExistingReminder = existingReminders.isNotEmpty;

            await _scheduleReminderFromScan(scan);

            if (hasExistingReminder) {
              updatedCount++;
            } else {
              reminderCount++;
            }

            setReminders.add(produceType);
            processedProduceTypes.add(produceType);
          } catch (e) {
            debugPrint('Error setting up reminder for scan: $e');
            // Continue with other scans even if one fails
          }
        }
      }

      // Add special handling for the last processed scan if it's not in recent scans
      if (_lastProcessedProduceType != 'Produce' &&
          _lastProcessedImagePath != null &&
          _findScanDataForLatestProcessed() != null) {
        final latestScan = _findScanDataForLatestProcessed();

        // Check if we already processed this scan
        if (!processedProduceTypes.contains(_lastProcessedProduceType) &&
            latestScan != null) {
          try {
            // Check if this produce type already has an active reminder
            final existingReminders = _activeReminders
                .where((reminder) =>
                    reminder['produceType'] == _lastProcessedProduceType &&
                    !(reminder['isDismissed'] as bool? ?? false))
                .toList();

            final bool hasExistingReminder = existingReminders.isNotEmpty;

            await _scheduleReminderFromScan(latestScan);

            if (hasExistingReminder) {
              updatedCount++;
            } else {
              reminderCount++;
            }

            setReminders.add(_lastProcessedProduceType);
            processedProduceTypes.add(_lastProcessedProduceType);
          } catch (e) {
            debugPrint(
                'Error setting up reminder for latest processed scan: $e');
          }
        }
      }

      // Pop the loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      // Show success message with details
      if (mounted) {
        if (reminderCount > 0 || updatedCount > 0) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Color(0xFF2E7D32),
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        reminderCount > 0 && updatedCount > 0
                            ? 'Reminders Set Up ($reminderCount) & Updated ($updatedCount)!'
                            : reminderCount > 0
                                ? 'Reminders Set Up! ($reminderCount)'
                                : 'Reminders Updated! ($updatedCount)',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        reminderCount > 0 && updatedCount > 0
                            ? 'We set up new reminders and updated existing ones. You\'ll be notified when your produce is ready for harvest.'
                            : reminderCount > 0
                                ? 'You\'ll be notified when your produce is ready for harvest.'
                                : 'Your existing reminders have been updated with the latest information.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 15),
                      // Show the list of reminders that were set up
                      if (setReminders.isNotEmpty) ...[
                        const Divider(),
                        const SizedBox(height: 10),
                        const Text(
                          'Scheduled reminders for:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.15,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: setReminders
                                  .map((produce) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              color: Color(0xFF2E7D32),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              produce,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Refresh the reminders display
                          _loadActiveReminders();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No new reminders needed. Your existing reminders are up to date.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if open
      Navigator.of(context, rootNavigator: true).pop();

      debugPrint('Error setting up harvest reminders: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up reminders: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to schedule a reminder from scan data
  Future<void> _scheduleReminderFromScan(Map<String, dynamic> scan) async {
    try {
      debugPrint('Scheduling reminder from scan: $scan');
      // Check if we have all required data
      final String? scanId = scan['scanId'];
      final String? produceType = scan['name'];
      final String? imagePath = scan['imagePath'] ?? scan['imageUrl'];
      final String? imageBase64 =
          scan['imageBase64']; // Extract base64 image data

      // Skip if required data is missing
      if (scanId == null || produceType == null || imagePath == null) {
        debugPrint('Cannot schedule reminder: Missing required scan data');
        return;
      }

      // Check if a reminder already exists for this produce type
      bool isUpdatingExistingReminder = false;
      for (final reminder in _activeReminders) {
        if (reminder['produceType'] == produceType &&
            !(reminder['isDismissed'] as bool? ?? false)) {
          isUpdatingExistingReminder = true;
          break;
        }
      }

      // Start with null for days until harvest to force a proper calculation
      int? daysUntilHarvest;

      // Convert confidence to String to ensure type safety
      final String? confidence = scan['confidence']?.toString();

      // First check for readiness - if ready, set days to 0
      bool isReadyForHarvest = false;

      // Check multiple sources of readiness information
      // Check AI prediction first
      if (scan.containsKey('final_prediction')) {
        // Handle both boolean and string values for final_prediction
        final prediction = scan['final_prediction'];
        if (prediction is bool) {
          isReadyForHarvest = prediction;
        } else if (prediction is String) {
          isReadyForHarvest = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      } else if (scan.containsKey('gemini_prediction')) {
        // Handle both boolean and string values for gemini_prediction
        final prediction = scan['gemini_prediction'];
        if (prediction is bool) {
          isReadyForHarvest = prediction;
        } else if (prediction is String) {
          isReadyForHarvest = prediction.toLowerCase() == 'true' ||
              prediction.toLowerCase() == 'yes' ||
              prediction.toLowerCase() == 'ready';
        }
      }

      // If the produce is ready, set days to 0 (harvest today)
      if (isReadyForHarvest) {
        daysUntilHarvest = 0;
      } else {
        // If not ready, check for explicit days_until_harvest field
        if (scan.containsKey('daysUntilHarvest')) {
          final daysValue = scan['daysUntilHarvest'];

          // Handle different data types for days_until_harvest
          if (daysValue is int) {
            daysUntilHarvest = daysValue;
          } else if (daysValue is double) {
            daysUntilHarvest = daysValue.round();
          } else if (daysValue is String && daysValue.isNotEmpty) {
            try {
              daysUntilHarvest = int.parse(daysValue);
            } catch (e) {
              debugPrint('Error parsing days_until_harvest as int: $e');
              // Leave as null to use intelligent estimation
            }
          }
        }
      }

      // If we still don't have a value (null, negative, or extremely large)
      // use our intelligent estimation function
      if (daysUntilHarvest == null || daysUntilHarvest < 0) {
        daysUntilHarvest = _estimateDaysFromScanData(scan, null);
      } else if (daysUntilHarvest > 90) {
        // Cap very large values to something reasonable
        daysUntilHarvest = 90;
      }

      // Final consistency check
      if (isReadyForHarvest && daysUntilHarvest > 0) {
        daysUntilHarvest = 0;
      }

      // Schedule the reminder with the notification service
      await _notificationService.scheduleHarvestReminder(
        produceType: produceType,
        imagePath: imagePath,
        scanId: scanId,
        daysUntilHarvest: daysUntilHarvest,
        confidence: confidence,
        imageBase64:
            imageBase64, // Pass base64 image data to notification service
      );

      // Calculate human-readable date for the reminder
      final DateTime now = DateTime.now();
      final DateTime harvestDate = DateTime(
          now.year,
          now.month,
          now.day + daysUntilHarvest,
          12, // Set to noon (12 PM)
          0,
          0);
      final String formattedDate =
          DateFormat('MMM dd, yyyy').format(harvestDate);

      // Provide appropriate user feedback based on harvest timing and whether this is a new or updated reminder
      String feedbackMessage;
      if (isUpdatingExistingReminder) {
        if (daysUntilHarvest == 0) {
          feedbackMessage = 'Reminder updated for $produceType (ready today)';
        } else if (daysUntilHarvest == 1) {
          feedbackMessage =
              'Reminder updated for $produceType (ready tomorrow)';
        } else {
          feedbackMessage =
              'Reminder updated for $produceType (ready in $daysUntilHarvest days)';
        }
      } else {
        if (daysUntilHarvest == 0) {
          feedbackMessage =
              'Reminder set for $produceType today ($formattedDate)';
        } else if (daysUntilHarvest == 1) {
          feedbackMessage =
              'Reminder set for $produceType tomorrow ($formattedDate)';
        } else {
          feedbackMessage =
              'Reminder set for $produceType on $formattedDate (in $daysUntilHarvest days)';
        }
      }

      // Show user feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(feedbackMessage),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      debugPrint(isUpdatingExistingReminder
          ? 'Updated reminder for $produceType on $formattedDate (in $daysUntilHarvest days)'
          : 'Scheduled reminder for $produceType on $formattedDate (in $daysUntilHarvest days)');
    } catch (e) {
      debugPrint('Error scheduling reminder from scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set reminder: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Improve the _fetchLastProcessedImage method to load all relevant AI data
  Future<void> _fetchLastProcessedImage() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        try {
          // Try to get the most recent scan from Firestore
          final QuerySnapshot result = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('scans')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get();

          if (!mounted) return;

          if (result.docs.isNotEmpty) {
            final doc = result.docs.first;
            final latestScan = doc.data() as Map<String, dynamic>;
            final scanId = doc.id;

            // Store the scan ID for reference
            latestScan['scanId'] = scanId;

            // Check for image path and Base64
            String? imagePath =
                latestScan['imagePath'] ?? latestScan['imageUrl'];
            String? imageBase64 = latestScan['imageBase64'];

            // Try to encode to Base64 if we have a path but no Base64
            if (imagePath != null && imageBase64 == null) {
              imageBase64 = await _convertImageToBase64(imagePath);
            }

            // Check if a produce type was detected
            final produceType = latestScan['name'];

            setState(() {
              _lastProcessedImagePath = imagePath;
              _lastProcessedImageBase64 = imageBase64;
              _lastProcessedProduceType = produceType ?? 'Produce';
            });
          } else if (_recentScans.isNotEmpty) {
            // If no dedicated scan is found, use the first recent scan
            _setLastProcessedFromScan(_recentScans.first);
          } else {
            // No data found
            print('No scan data found in Firestore.');
            setState(() {
              _lastProcessedImagePath = null;
              _lastProcessedImageBase64 = null;
              _lastProcessedProduceType = 'Produce';
            });
          }
        } catch (firestoreError) {
          // Handle Firestore errors (likely permission issues)
          print(
              'Firestore error in _fetchLastProcessedImage: $firestoreError.');
          if (_recentScans.isNotEmpty) {
            // Use the first scan from _recentScans if available
            _setLastProcessedFromScan(_recentScans.first);
          } else {
            // Reset the data
            setState(() {
              _lastProcessedImagePath = null;
              _lastProcessedImageBase64 = null;
              _lastProcessedProduceType = 'Produce';
            });
          }
        }
      } else if (_recentScans.isNotEmpty) {
        // If not logged in but we have recent scans, use that
        _setLastProcessedFromScan(_recentScans.first);
      } else {
        // No user and no recent scans
        print('No user logged in and no recent scans available.');
        setState(() {
          _lastProcessedImagePath = null;
          _lastProcessedImageBase64 = null;
          _lastProcessedProduceType = 'Produce';
        });
      }
    } catch (e) {
      print('Error fetching last processed image: $e');
      setState(() {
        _lastProcessedImagePath = null;
        _lastProcessedImageBase64 = null;
        _lastProcessedProduceType = 'Produce';
      });
    }
  }

  // Add a method to load active reminders
  Future<void> _loadActiveReminders() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Check for reminders due today
      await _notificationService.checkTodayReminders();

      // Clear the image cache and reminders list before reloading
      _reminderImageCache.clear();

      final freshReminders = await _notificationService.getPendingReminders();

      // Create a map to deduplicate reminders with the same scanId
      final Map<String, Map<String, dynamic>> deduplicatedReminders = {};

      // Process reminders to ensure we have no duplicates
      for (final reminder in freshReminders) {
        final String scanId = reminder['scanId'] ?? '';

        if (scanId.isNotEmpty) {
          // If we already have this scanId, only replace it if the current one is newer
          if (deduplicatedReminders.containsKey(scanId)) {
            final Timestamp? existingTimestamp =
                deduplicatedReminders[scanId]!['updatedAt'] as Timestamp?;
            final Timestamp? newTimestamp = reminder['updatedAt'] as Timestamp?;

            if (newTimestamp != null &&
                (existingTimestamp == null ||
                    newTimestamp.compareTo(existingTimestamp) > 0)) {
              deduplicatedReminders[scanId] = reminder;
            }
          } else {
            deduplicatedReminders[scanId] = reminder;
          }
        } else {
          // For reminders without scanId, use the reminder id as the key
          final String reminderId = reminder['id'] ?? '';
          if (reminderId.isNotEmpty) {
            deduplicatedReminders[reminderId] = reminder;
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeReminders = deduplicatedReminders.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading active reminders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Add a method to build the active reminders section
  Widget _buildActiveRemindersSection() {
    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: const [
                ShimmerSkeleton(
                  child:
                      SkeletonWidget(height: 20, width: 180, borderRadius: 4),
                ),
                Spacer(),
                ShimmerSkeleton(
                  child: SkeletonWidget(height: 20, width: 60, borderRadius: 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const ShimmerSkeleton(
            child: SkeletonWidget(
                height: 80, width: double.infinity, borderRadius: 15),
          ),
        ],
      );
    } else if (_activeReminders.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Harvest Reminders',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    // Replace the refresh icon button with an improved version
                    _isRefreshingReminders
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2E7D32),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () async {
                              setState(() {
                                _isRefreshingReminders = true;
                              });
                              await _loadActiveReminders();
                              if (mounted) {
                                setState(() {
                                  _isRefreshingReminders = false;
                                });
                              }
                            },
                            tooltip: 'Refresh Reminders',
                            splashRadius: 20,
                          ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ..._activeReminders.map((reminder) => _buildReminderItem(reminder)),
        ],
      );
    } else {
      return Container(); // Don't show if no reminders
    }
  }

  // Add a method to build reminder items
  Widget _buildReminderItem(Map<String, dynamic> reminder) {
    final String reminderId = reminder['id'] ?? '';
    final String produceType = reminder['produceType'] ?? 'Unknown';
    final String imagePath = reminder['imagePath'] ?? '';
    final String? imageBase64 =
        reminder['imageBase64']; // Extract base64 image data
    final Timestamp? harvestDate = reminder['harvestDate'] as Timestamp?;
    final String formattedDate = harvestDate != null
        ? DateFormat('MMM dd, yyyy').format(harvestDate.toDate())
        : 'Unknown date';

    debugPrint('Reminder produce type: $harvestDate');
    // Generate a unique key for this reminder
    final String reminderKey = '${reminderId}_${produceType}_$formattedDate';

    return Container(
      key: ValueKey(
          reminderKey), // Add key to help Flutter identify unique items
      margin: const EdgeInsets.only(bottom: 10, left: 20, right: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          // Image with improved path handling
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 60,
              child: _buildReminderImage(
                  imagePath, reminderId, imageBase64), // Pass base64 image data
            ),
          ),
          const SizedBox(width: 15),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produceType,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Ready on $formattedDate',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                // Add days remaining if available
                if (harvestDate != null)
                  _buildDaysRemainingText(harvestDate.toDate()),
              ],
            ),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.grey, size: 20),
            onPressed: () => _cancelReminder(reminderId),
            tooltip: 'Cancel Reminder',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // Helper to build days remaining text
  Widget _buildDaysRemainingText(DateTime harvestDate) {
    final now = DateTime.now();

    // Normalize both dates to remove time component for accurate day calculation
    final normalizedNow = DateTime(now.year, now.month, now.day);
    final normalizedHarvestDate =
        DateTime(harvestDate.year, harvestDate.month, harvestDate.day);

    // Calculate difference in days
    final difference = normalizedHarvestDate.difference(normalizedNow).inDays;

    debugPrint('Harvest date: $harvestDate');
    debugPrint('Days until harvest: $difference');
    Color textColor;
    String text;

    if (difference < 0) {
      textColor = Colors.red;
      text = 'Overdue by ${-difference} day${-difference == 1 ? '' : 's'}';
    } else if (difference == 0) {
      textColor = Colors.orange;
      text = 'Ready today!';
    } else if (difference == 1) {
      textColor = Colors.orange[700]!;
      text = 'Ready tomorrow';
    } else {
      // More specific text for longer periods
      if (difference <= 3) {
        textColor = Colors.orange[700]!;
      } else if (difference <= 7) {
        textColor = Colors.green[700]!;
      } else {
        textColor = Colors.blue[700]!;
      }
      text = '$difference days remaining';
    }

    debugPrint('Days remaining text: $text with color $textColor');

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // Helper to build and cache images for reminders
  Widget _buildReminderImage(
      String imagePath, String reminderId, String? base64Image) {
    // Check if image is already in cache
    final cacheKey = '${reminderId}_${imagePath.hashCode}';
    if (_reminderImageCache.containsKey(cacheKey)) {
      return _reminderImageCache[cacheKey]!;
    }

    Widget imageWidget;

    // First try to use base64 image if available
    if (base64Image != null && base64Image.isNotEmpty) {
      try {
        final Uint8List bytes = base64.decode(base64Image);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading reminder base64 image: $error');
            // On error, fall back to path-based methods
            return _buildImageFromPath(imagePath, reminderId, cacheKey);
          },
        );
        // Cache and return the base64 image widget
        _reminderImageCache[cacheKey] = imageWidget;
        return imageWidget;
      } catch (e) {
        debugPrint('Error decoding reminder base64 image: $e');
        // Fall through to try image path
      }
    }

    // If base64 failed or wasn't available, try using the image path
    return _buildImageFromPath(imagePath, reminderId, cacheKey);
  }

  // Helper to build image from path (extracted from _buildReminderImage)
  Widget _buildImageFromPath(
      String imagePath, String reminderId, String cacheKey) {
    // If image path is empty, return placeholder
    if (imagePath.isEmpty) {
      final placeholderWidget = _buildPlaceholderImage();
      _reminderImageCache[cacheKey] = placeholderWidget;
      return placeholderWidget;
    }

    Widget imageWidget;

    // Handle different image path types
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      // Network image
      imageWidget = CachedNetworkImage(
        imageUrl: imagePath,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: const Color(0xFF2E7D32),
          ),
        ),
        errorWidget: (context, url, error) {
          debugPrint('Error loading reminder network image: $error');
          return _buildPlaceholderImage();
        },
      );
    } else {
      // Handle URL-encoded paths
      String normalizedPath = imagePath;
      if (imagePath.contains('%')) {
        try {
          normalizedPath = Uri.decodeFull(imagePath);
        } catch (e) {
          debugPrint('Error decoding reminder image path: $e');
        }
      }

      // Handle platform-specific paths
      if (Platform.isAndroid) {
        if (normalizedPath.startsWith('content://') ||
            normalizedPath.startsWith('file:///')) {
          try {
            final file = File(normalizedPath);
            if (file.existsSync()) {
              imageWidget = Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('Error loading Android reminder image: $error');
                  return _buildPlaceholderImage();
                },
              );
              // Cache and return early
              _reminderImageCache[cacheKey] = imageWidget;
              return imageWidget;
            }
          } catch (e) {
            debugPrint('Error with Android-specific reminder path: $e');
            // Continue with regular file handling
          }
        }
      } else if (Platform.isIOS) {
        debugPrint('iOS reminder path: $normalizedPath');
        // iOS-specific handling if needed
      }

      // Local file image - check if file exists first
      // debugPrint('Checking reminder image file: $normalizedPath');
      final file = File(normalizedPath);
      final fileExists = file.existsSync();

      if (fileExists) {
        try {
          imageWidget = Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Error loading reminder file image: $error');
              return _buildPlaceholderImage();
            },
          );
        } catch (e) {
          debugPrint('Exception loading reminder image file: $e');
          imageWidget = _buildPlaceholderImage();
        }
      } else {
        // If the file doesn't exist, try to use it as a network URL
        // debugPrint(
        //     'Reminder image file not found, trying as URL: $normalizedPath');

        // Check if it looks like a network URL or storage path
        if (normalizedPath.contains('://') ||
            normalizedPath.contains('storage/')) {
          imageWidget = CachedNetworkImage(
            imageUrl: normalizedPath,
            fit: BoxFit.cover,
            placeholder: (context, url) => Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xFF2E7D32),
              ),
            ),
            errorWidget: (context, url, error) {
              debugPrint('Failed to load reminder as network image: $error');
              return _buildPlaceholderImage();
            },
          );
        } else {
          // Not a valid path of any kind
          debugPrint('Invalid reminder image path: $normalizedPath');
          imageWidget = _buildPlaceholderImage();
        }
      }
    }

    // Cache the image widget
    _reminderImageCache[cacheKey] = imageWidget;
    return imageWidget;
  }

  // Helper to build placeholder image
  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(
        Icons.eco,
        color: Color(0xFF2E7D32),
        size: 30,
      ),
    );
  }

  // Add a method to cancel a reminder
  Future<void> _cancelReminder(String reminderId) async {
    if (reminderId.isEmpty) return;

    try {
      setState(() {
        _isRefreshingReminders = true;
      });

      await _notificationService.cancelReminder(reminderId);

      // First update the UI immediately by removing the canceled reminder
      setState(() {
        _activeReminders
            .removeWhere((reminder) => reminder['id'] == reminderId);
      });

      // Then reload all reminders to ensure everything is in sync
      await _loadActiveReminders();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder cancelled successfully'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );

        setState(() {
          _isRefreshingReminders = false;
        });
      }
    } catch (e) {
      debugPrint('Error cancelling reminder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel reminder: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );

        setState(() {
          _isRefreshingReminders = false;
        });
      }
    }
  }

  // Method to refresh all dashboard data at once
  Future<void> refreshDashboardData() async {
    if (!mounted) return;

    // Skip refresh if already loading (during analysis)
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    // Clear image cache to ensure fresh image loading
    _reminderImageCache.clear();

    // Create a list of futures to run in parallel with error handling
    final futures = [
      _loadRecentScans()
          .catchError((e) => debugPrint('Error loading scans: $e')),
      _loadActiveReminders()
          .catchError((e) => debugPrint('Error loading reminders: $e')),
      _fetchLastProcessedImage()
          .catchError((e) => debugPrint('Error fetching image: $e')),
    ];

    // Wait for all data loading to complete, but don't let one failure stop others
    await Future.wait(futures, eagerError: false);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    debugPrint('Dashboard data refreshed successfully');
  }

  // Update the onPageSelected method to use refreshDashboardData
  void _onPageSelected(int index) {
    final previousIndex = _selectedIndex;

    setState(() {
      _selectedIndex = index;
    });

    // Refresh data when dashboard tab is selected
    if (index == 0 && previousIndex != 0) {
      refreshDashboardData();
    }

    // Refresh weather data and care recommendations when harvest page is selected
    // Only refresh if not currently in the loading state
    if (index == 3 && !_isLoading) {
      _refreshWeatherAndCareRecommendations();
    }
  }

  // Async base64 decoding to prevent blocking the main thread
  Future<Uint8List> _decodeBase64Async(String base64String) async {
    return compute(_decodeBase64, base64String);
  }

  // Static method for use with compute
  static Uint8List _decodeBase64(String base64String) {
    return base64.decode(base64String);
  }

  // Safe cache size calculation to prevent Infinity/NaN errors
  int? _safeCacheSize(double size) {
    if (size.isInfinite || size.isNaN || size <= 0) {
      return null; // Let Flutter handle caching automatically
    }
    return size.round().clamp(1, 2048); // Reasonable cache size limits
  }

  // Method to refresh weather data and care recommendations
  Future<void> _refreshWeatherAndCareRecommendations() async {
    if (!mounted) return;

    // Skip refresh if already in loading state (during analysis)
    if (_isLoading) return;

    // Only fetch new data if weather data is old or unavailable
    if (_weatherData == null ||
        DateTime.now().difference(_weatherData!.lastUpdated).inMinutes > 30) {
      // Show subtle loading indicator if needed
      setState(() {
        _isLoadingWeather = true;
      });

      // Get current location and fetch fresh weather data
      try {
        await _getCurrentLocation();
        await _fetchWeatherData();
      } catch (e) {
        debugPrint('Error refreshing weather data: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingWeather = false;
          });
        }
      }
    }

    // Force UI update to refresh care recommendations with latest weather data
    if (mounted) {
      setState(() {
        // This will trigger a rebuild of the care recommendations
        // even if the weather data didn't change
      });
    }
  }

  // Get produce-specific care recommendations with real-time weather context
  List<Map<String, dynamic>> _getProduceSpecificCareRecommendations(
      String produceType) {
    // Convert to lowercase for case-insensitive matching
    final String type = produceType.toLowerCase();

    // Get current weather conditions to provide context-aware recommendations
    final bool isHotWeather =
        _weatherData != null && _weatherData!.temperature > 25;
    final bool isHighHumidity =
        _weatherData != null && _weatherData!.humidity > 70;
    final bool isDryConditions =
        _weatherData != null && _weatherData!.humidity < 40;
    final bool isWindy = _weatherData != null && _weatherData!.windSpeed > 5;
    final bool isSunny = _weatherData != null &&
        (_weatherData!.description.toLowerCase().contains('clear') ||
            _weatherData!.description.toLowerCase().contains('sun'));
    final bool isRainy = _weatherData != null &&
        _weatherData!.description.toLowerCase().contains('rain');

    // Get current season (Northern Hemisphere assumption)
    final DateTime now = DateTime.now();
    final int month = now.month;
    final bool isSpring = month >= 3 && month <= 5;
    final bool isSummer = month >= 6 && month <= 8;
    final bool isFall = month >= 9 && month <= 11;
    final bool isWinter = month == 12 || month <= 2;

    // Get local time to provide time-sensitive recommendations
    final int hour = now.hour;
    final bool isMorning = hour >= 5 && hour < 12;
    final bool isAfternoon = hour >= 12 && hour < 17;
    // final bool isEvening = hour >= 17 && hour < 22;

    // Default recommendations with weather context
    final List<Map<String, dynamic>> defaultRecommendations = [
      {
        'icon': Icons.water_drop,
        'text': isHotWeather
            ? 'Increase watering frequency due to current hot conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
            : isDryConditions
                ? 'Water thoroughly as humidity is low (${_weatherData?.humidity}%)'
                : isRainy
                    ? 'Reduce watering as rain is providing moisture'
                    : 'Water thoroughly and let soil dry slightly between watering',
      },
      {
        'icon': Icons.wb_sunny,
        'text': isSunny && isAfternoon
            ? 'Provide shade during peak sun hours (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
            : isSunny
                ? 'Current sunny conditions are good for growth, ensure adequate light'
                : 'Ensure consistent sunlight exposure, especially during morning hours',
      },
      {
        'icon': isWindy ? Icons.air : Icons.crop_rotate,
        'text': isWindy
            ? 'Protect from current winds (${_weatherData?.windSpeed.toStringAsFixed(1)} m/s) that can damage tender shoots'
            : 'Turn fruit occasionally for uniform coloration',
      },
    ];

    // Produce-specific recommendations with weather context
    if (type.contains('tomato')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Water deeply at the base in current hot conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C), preferably in the ${isMorning ? 'early morning' : 'evening'}'
              : isRainy
                  ? 'Check that excess rainwater drains well to prevent rot'
                  : 'Water at the base. Keep soil consistently moist but not soggy.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny && isSummer
              ? 'Current strong sunlight is ideal for ripening. Ensure 6-8 hours exposure'
              : isFall || isWinter
                  ? 'Position to maximize available sunlight during cooler months'
                  : 'Requires 6-8 hours of direct sunlight daily for best flavor.',
        },
        {
          'icon': Icons.thermostat,
          'text': isHotWeather && _weatherData!.temperature > 32
              ? 'Current temperature (${_weatherData?.temperature.toStringAsFixed(1)}°C) may stress plants. Provide afternoon shade'
              : isWinter &&
                      _weatherData != null &&
                      _weatherData!.temperature < 10
                  ? 'Protect from current cold conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
                  : 'Ideal temperature range: 65°F-85°F (18°C-29°C).',
        },
      ];
    } else if (type.contains('apple')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isDryConditions
              ? 'Increase watering due to current dry conditions (${_weatherData?.humidity}%)'
              : isRainy
                  ? 'Good rainfall conditions. Check drainage to prevent root rot'
                  : 'Regular watering until fruits are fully developed.',
        },
        {
          'icon': Icons.pest_control,
          'text': isHighHumidity
              ? 'High humidity (${_weatherData?.humidity}%) increases pest risk. Check for apple maggots and codling moths'
              : isSummer
                  ? 'Peak season for pests. Inspect regularly for apple maggots and codling moths'
                  : 'Check regularly for pests like apple maggots and codling moths.',
        },
        {
          'icon': Icons.content_cut,
          'text': isWindy
              ? 'Postpone pruning during current windy conditions (${_weatherData?.windSpeed.toStringAsFixed(1)} m/s)'
              : isFall || isWinter
                  ? 'Good season for structural pruning when tree is dormant'
                  : 'Prune to allow light to reach all fruits for even ripening.',
        },
      ];
    } else if (type.contains('pepper') || type.contains('chili')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Increase watering frequency in current hot conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
              : isDryConditions
                  ? 'Current low humidity (${_weatherData?.humidity}%) requires more frequent watering'
                  : 'Keep soil consistently moist. Avoid overwatering.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny
              ? 'Current sunny conditions are ideal for pepper development'
              : 'Requires full sun for best color and flavor development.',
        },
        {
          'icon': Icons.thermostat,
          'text': _weatherData != null
              ? 'Current temperature (${_weatherData?.temperature.toStringAsFixed(1)}°C) is ${_weatherData!.temperature > 29 ? 'high' : _weatherData!.temperature < 21 ? 'low' : 'ideal'} for pepper development'
              : 'Temperature stress can affect spiciness. Maintain 70°F-85°F (21°C-29°C).',
        },
      ];
    } else if (type.contains('strawberry')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Water more frequently in current hot weather (${_weatherData?.temperature.toStringAsFixed(1)}°C), preferably in the morning'
              : isRainy
                  ? 'Ensure good drainage during rainy conditions to prevent rot'
                  : 'Keep soil moist but not waterlogged. Use drip irrigation if possible.',
        },
        {
          'icon': Icons.grass,
          'text': isRainy
              ? 'Check mulch during rainy conditions to prevent fruit contact with wet soil'
              : 'Apply straw mulch around plants to prevent fruits touching soil.',
        },
        {
          'icon': Icons.pest_control,
          'text': isSummer
              ? 'Peak bird activity now! Use protective netting as berries ripen'
              : isHighHumidity
                  ? 'Current humid conditions (${_weatherData?.humidity}%) increase risk of mold. Improve air circulation'
                  : 'Protect from birds with netting as fruits begin to ripen.',
        },
      ];
    } else if (type.contains('orange') || type.contains('citrus')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Increase watering frequency during current heat (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
              : isDryConditions
                  ? 'Current dry conditions (${_weatherData?.humidity}% humidity) require deeper watering'
                  : 'Deep watering once weekly. Let soil dry between waterings.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny
              ? 'Current sunny conditions are ideal for citrus development'
              : isSummer
                  ? 'Ensure adequate sunlight exposure during peak growing season'
                  : 'Requires full sun for sweet fruit development.',
        },
        {
          'icon': Icons.eco,
          'text': isSpring
              ? 'Now is an ideal time to apply citrus-specific fertilizer'
              : isFall
                  ? 'Reduce fertilization as winter approaches'
                  : 'Apply citrus-specific fertilizer during growing season.',
        },
      ];
    } else if (type.contains('lettuce') || type.contains('leafy')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Increase watering during current hot weather (${_weatherData?.temperature.toStringAsFixed(1)}°C), preferably in the morning'
              : isDryConditions
                  ? 'Current dry conditions (${_weatherData?.humidity}% humidity) require more frequent light watering'
                  : 'Keep soil consistently moist. Water more frequently in hot weather.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny && isHotWeather
              ? 'Provide shade during current hot, sunny conditions to prevent bolting'
              : 'Provide partial shade in hot weather to prevent bolting.',
        },
        {
          'icon': Icons.pest_control,
          'text': isHighHumidity
              ? 'Check more frequently for slugs in current humid conditions (${_weatherData?.humidity}%)'
              : isSpring
                  ? 'Peak aphid season now. Monitor leaves carefully'
                  : 'Monitor for aphids and slugs. Use organic controls if needed.',
        },
      ];
    } else if (type.contains('grape')) {
      return [
        {
          'icon': Icons.content_cut,
          'text': isWindy
              ? 'Current windy conditions (${_weatherData?.windSpeed.toStringAsFixed(1)} m/s) may damage vines. Check trellis support'
              : isHighHumidity
                  ? 'Increase pruning during current humid conditions (${_weatherData?.humidity}%) to improve air circulation'
                  : 'Maintain good air circulation with proper pruning.',
        },
        {
          'icon': Icons.water_drop,
          'text': isHotWeather && isDryConditions
              ? 'Deep watering needed in current hot, dry conditions'
              : isRainy
                  ? 'Ensure good drainage in current rainy conditions'
                  : 'Water deeply but infrequently to encourage deep root growth.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny
              ? 'Current sunny conditions will help develop sugars in ripening grapes'
              : 'Ensure clusters receive adequate sunlight for even ripening.',
        },
      ];
    } else if (type.contains('cucumber')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Increase watering in current hot conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C), preferably in the morning'
              : isDryConditions
                  ? 'Current dry conditions (${_weatherData?.humidity}%) require more frequent watering'
                  : 'Consistent watering is essential. Use drip irrigation if possible.',
        },
        {
          'icon': Icons.crop_rotate,
          'text': isSunny
              ? 'Turn fruits regularly during sunny periods for even coloration'
              : 'Rotate fruits to ensure even development and coloration.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isWindy
              ? 'Current winds (${_weatherData?.windSpeed.toStringAsFixed(1)} m/s) may damage vines. Check trellising'
              : isSunny && isHotWeather
                  ? 'Light shade during peak heat may benefit plants in current conditions'
                  : 'Provide trellising for straighter fruits with even color.',
        },
      ];
    } else if (type.contains('avocado')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Increase watering frequency during current heat (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
              : isDryConditions
                  ? 'Water deeply in current dry conditions (${_weatherData?.humidity}% humidity)'
                  : 'Young fruits need consistent moisture. Established trees are more drought-tolerant.',
        },
        {
          'icon': Icons.thermostat,
          'text': _weatherData != null && _weatherData!.temperature < 15
              ? 'Current temperature (${_weatherData?.temperature.toStringAsFixed(1)}°C) is too cool. Protect from frost'
              : isWinter
                  ? 'Be prepared to protect from frost during winter months'
                  : 'Protect from frost. Optimal temperature range: 60°F-85°F (15°C-29°C).',
        },
        {
          'icon': Icons.hourglass_empty,
          'text': isRainy
              ? 'Delay harvest during rainy conditions for better quality'
              : 'Harvest when fruits yield slightly to gentle pressure.',
        },
      ];
    } else if (type.contains('carrot')) {
      return [
        {
          'icon': Icons.water_drop,
          'text': isHotWeather
              ? 'Light, frequent watering in current hot conditions (${_weatherData?.temperature.toStringAsFixed(1)}°C)'
              : isRainy
                  ? 'Ensure good drainage during rainy conditions to prevent rot'
                  : 'Consistent moisture for straight root development. Avoid overwatering.',
        },
        {
          'icon': Icons.grass,
          'text': isRainy
              ? 'Check soil during rainy periods to prevent compaction'
              : 'Keep soil loose and free of rocks for straight growth.',
        },
        {
          'icon': Icons.wb_sunny,
          'text': isSunny && isHotWeather
              ? 'Light shade in afternoon during current hot, sunny periods'
              : 'Can tolerate partial shade but needs full sun for best growth.',
        },
      ];
    }

    // Return default recommendations if no specific match found
    return defaultRecommendations;
  }

  // Add a helper method to intelligently estimate days until harvest based on scan data
  int _estimateDaysFromScanData(
      Map<String, dynamic> scanData, int? fallbackDays) {
    // First check if there's any gemini_response with clues
    if (scanData.containsKey('gemini_response') ||
        scanData.containsKey('ai_response')) {
      final String response =
          (scanData['gemini_response'] ?? scanData['ai_response'] ?? '')
              .toString()
              .toLowerCase();

      // Enhanced pattern matching for ripeness clues in AI text
      // Very unripe patterns
      if (response.contains('very unripe') ||
          response.contains('completely unripe') ||
          response.contains('far from ready') ||
          response.contains('early stage') ||
          response.contains('weeks away') ||
          response.contains('not close to')) {
        return 14; // Significantly unripe
      }
      // Ready now patterns
      else if (response.contains('ready to harvest') ||
          response.contains('ready for harvest') ||
          response.contains('can be harvested now') ||
          response.contains('optimal ripeness') ||
          response.contains('harvest now') ||
          response.contains('fully ripe')) {
        return 0; // Ready now
      }
      // Nearly ready patterns
      else if (response.contains('almost ripe') ||
          response.contains('nearly ready') ||
          response.contains('close to harvest') ||
          response.contains('approaching readiness') ||
          response.contains('few days') ||
          response.contains('soon be ready')) {
        return 3; // Nearly ready (3 days)
      }
      // Moderately ripe patterns
      else if (response.contains('moderately ripe') ||
          response.contains('developing') ||
          response.contains('progressing') ||
          response.contains('mid-stage') ||
          response.contains('continue to ripen')) {
        return 7; // Intermediate stage (7 days)
      }

      // Look for specific day mentions in the response
      final RegExp daysRegex = RegExp(r'(\d+)[-\s]*(day|days)');
      final Match? daysMatch = daysRegex.firstMatch(response);
      if (daysMatch != null && daysMatch.groupCount >= 1) {
        try {
          final int days = int.parse(daysMatch.group(1)!);
          if (days >= 0 && days <= 90) {
            // Reasonable range check
            return days;
          }
        } catch (e) {
          debugPrint('Error parsing days from response text: $e');
        }
      }
    }

    // If no response text available, check the produce type
    final String produceType =
        (scanData['name'] ?? '').toString().toLowerCase();

    // Enhanced produce type categorization with more specific estimates

    // Very fast ripening produce (3-5 days)
    if (produceType.contains('strawberry') ||
        produceType.contains('raspberry') ||
        produceType.contains('blackberry') ||
        produceType.contains('blueberry') ||
        produceType.contains('cherry') ||
        produceType.contains('fig')) {
      return 4; // These typically ripen very quickly
    }

    // Fast-ripening produce (5-10 days)
    if (produceType.contains('tomato') ||
        produceType.contains('banana') ||
        produceType.contains('peach') ||
        produceType.contains('plum') ||
        produceType.contains('apricot') ||
        produceType.contains('avocado') ||
        produceType.contains('mango') ||
        produceType.contains('leafy') ||
        produceType.contains('lettuce') ||
        produceType.contains('spinach') ||
        produceType.contains('kale')) {
      return 7; // These typically ripen quickly
    }

    // Medium-ripening produce (10-20 days)
    if (produceType.contains('pepper') ||
        produceType.contains('cucumber') ||
        produceType.contains('zucchini') ||
        produceType.contains('eggplant') ||
        produceType.contains('squash') ||
        produceType.contains('melon') ||
        produceType.contains('grape')) {
      return 14; // These take a moderate amount of time
    }

    // Return fallback days if provided, otherwise default to 10 days
    return fallbackDays ?? 10;
  }
  
  // Build the chart page
  Widget _buildChartPage() {
    return ChartPage(
      onRefresh: refreshDashboardData,
    );
  }
}
