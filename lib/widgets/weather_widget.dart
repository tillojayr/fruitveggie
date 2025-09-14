import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:ui';
import 'package:intl/intl.dart';

class WeatherWidget extends StatefulWidget {
  final String city;
  final bool useLocation;
  final double? latitude;
  final double? longitude;
  final Duration refreshInterval;

  const WeatherWidget({
    super.key,
    this.city = 'London', // Default city
    this.useLocation = false,
    this.latitude,
    this.longitude,
    this.refreshInterval = const Duration(minutes: 5), // More frequent updates
  });

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget>
    with SingleTickerProviderStateMixin {
  final WeatherService _weatherService = WeatherService();
  final LocationService _locationService = LocationService();
  WeatherData? _weatherData;
  bool _isLoading = true;
  String? _errorMessage;
  late Timer _refreshTimer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  DateTime? _lastUpdated;
  Position? _currentPosition;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isListeningToLocation = false;
  String? _locationAddress;
  bool _isRefreshingWeather = false;

  @override
  void initState() {
    super.initState();

    // Animation setup
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.forward();

    // Setup location updates if using device location
    if (widget.useLocation) {
      _setupLocationUpdates();
    } else {
      // Just fetch weather for the specified city or coordinates
      _fetchWeather();
    }

    // Refresh weather data periodically
    _refreshTimer = Timer.periodic(widget.refreshInterval, (timer) {
      _fetchWeather();
    });
  }

  void _setupLocationUpdates() async {
    try {
      // Try to get initial position
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        setState(() {
          _currentPosition = position;
        });

        // Try to get address from coordinates
        _getAddressFromPosition(position);

        // Fetch weather with this position
        _fetchWeather();
      }
    } catch (e) {
      debugPrint('Initial location error: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }

    // Subscribe to ongoing location updates
    if (!_isListeningToLocation) {
      _locationService.addLocationListener(_onLocationUpdate);
      _isListeningToLocation = true;
    }
  }

  // Get address from position
  Future<void> _getAddressFromPosition(Position position) async {
    try {
      final address = await _locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (mounted && address != null) {
        setState(() {
          _locationAddress = address;
        });
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
  }

  void _onLocationUpdate(Position position) {
    // Check if the position has changed significantly (reduced to 100m for more accuracy)
    bool shouldUpdateWeather = false;

    if (_currentPosition == null) {
      shouldUpdateWeather = true;
    } else {
      // Calculate distance between previous and new position
      final double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Update if moved more than 100 meters or if last update was more than 5 minutes ago
      shouldUpdateWeather = distanceInMeters > 100 ||
          (_lastUpdated != null &&
              DateTime.now().difference(_lastUpdated!).inMinutes > 5);

      // Also update if accuracy has significantly improved
      if (position.accuracy < _currentPosition!.accuracy - 20) {
        // 20m better accuracy
        shouldUpdateWeather = true;
      }
    }

    setState(() {
      _currentPosition = position;
    });

    // Update address if location changed significantly
    if (shouldUpdateWeather) {
      _getAddressFromPosition(position);
      _fetchWeather();
    }
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _animationController.dispose();

    // Clean up location listener
    if (_isListeningToLocation) {
      _locationService.removeLocationListener(_onLocationUpdate);
    }

    super.dispose();
  }

  Future<void> _fetchWeather() async {
    if (!mounted || _isRefreshingWeather) return;

    setState(() {
      _isRefreshingWeather = true;
      if (!_isLoading) {
        _isLoading = _weatherData == null;
      }
      _errorMessage = null;
    });

    try {
      WeatherData data;

      if (widget.useLocation && _currentPosition != null) {
        // Validate position accuracy before using it (improved accuracy threshold)
        if (_currentPosition!.accuracy <= 50) {
          // Only use highly accurate positions for real-time data
          data = await _weatherService.getWeatherByLocation(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
        } else {
          // If accuracy is poor, try to get a fresh position
          final newPosition = await _locationService.getCurrentLocation();
          if (newPosition != null && newPosition.accuracy <= 50) {
            setState(() {
              _currentPosition = newPosition;
            });
            data = await _weatherService.getWeatherByLocation(
              newPosition.latitude,
              newPosition.longitude,
            );
          } else {
            // Fallback to using the position even with lower accuracy rather than failing
            debugPrint(
                'Using position with lower accuracy: ${_currentPosition!.accuracy}m');
            data = await _weatherService.getWeatherByLocation(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            );
          }
        }
      } else if (widget.latitude != null && widget.longitude != null) {
        data = await _weatherService.getWeatherByLocation(
          widget.latitude!,
          widget.longitude!,
        );
      } else {
        data = await _weatherService.getWeatherByCity(widget.city);
      }

      // Update the state only if the widget is still mounted
      if (mounted) {
        setState(() {
          _weatherData = data;
          _isLoading = false;
          _isRefreshingWeather = false;
          _lastUpdated = DateTime.now();
          _retryCount = 0; // Reset retry count on successful fetch
        });

        // Restart animation when new data arrives
        _animationController.reset();
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshingWeather = false;
          _errorMessage = 'Could not load weather data';
          _retryCount++;
        });

        debugPrint('Weather error: $e');

        // Auto-retry with exponential backoff if under max retries
        if (_retryCount < _maxRetries) {
          Future.delayed(Duration(seconds: _retryCount * 2), () {
            if (mounted) {
              _fetchWeather();
            }
          });
        }
      }
    }
  }

  String _getFormattedUpdateTime() {
    if (_lastUpdated == null) return 'Updated just now';

    final now = DateTime.now();
    final difference = now.difference(_lastUpdated!);

    if (difference.inSeconds < 60) {
      return 'Updated just now';
    } else if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes} min ago';
    } else {
      return 'Updated at ${DateFormat.Hm().format(_lastUpdated!)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 15,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: _weatherData == null && _isLoading
                ? const Center(
                    child: SizedBox(
                      height: 30,
                      width: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : _errorMessage != null
                    ? _buildErrorWidget()
                    : Stack(
                        children: [
                          if (_weatherData != null) _buildWeatherInfo(),
                          if (_isRefreshingWeather && _weatherData != null)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),

                          // Show location indicator when using real-time location
                          if (widget.useLocation && _currentPosition != null)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Tooltip(
                                message: 'Using your real-time location',
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () {
              if (widget.useLocation) {
                _setupLocationUpdates();
              } else {
                _fetchWeather();
              }
            },
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Retry',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherInfo() {
    if (_weatherData == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _locationAddress ?? _weatherData!.location,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.useLocation && _currentPosition != null)
                        Tooltip(
                          message: 'Real-time location',
                          child: Icon(
                            Icons.gps_fixed,
                            size: 12,
                            color: Colors.green.shade300,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _weatherData!.description.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _weatherData!.temperature.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        '°C',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          height: 0.9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Hero(
              tag: 'weather_icon',
              child: Image.network(
                _weatherData!.iconUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.cloud,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherDetail(
                Icons.thermostat_rounded,
                'Feels like',
                '${_weatherData!.feelsLike.toStringAsFixed(1)}°C',
              ),
              _buildWeatherDetail(
                Icons.water_drop_rounded,
                'Humidity',
                '${_weatherData!.humidity}%',
              ),
              _buildWeatherDetail(
                Icons.air_rounded,
                'Wind',
                '${_weatherData!.windSpeed.toStringAsFixed(1)} m/s',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Add additional weather details
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherDetail(
                Icons.visibility,
                'Visibility',
                '${(_weatherData!.visibility / 1000).toStringAsFixed(1)} km',
              ),
              _buildWeatherDetail(
                Icons.compress,
                'Pressure',
                '${_weatherData!.pressure} hPa',
              ),
              _buildWeatherDetail(
                Icons.cloud,
                'Cloudiness',
                '${_weatherData!.cloudiness}%',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (widget.useLocation && _currentPosition != null)
              Text(
                'Coords: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w400,
                ),
              )
            else
              const SizedBox.shrink(),
            Text(
              _getFormattedUpdateTime(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),

        // Show weather alerts if any
        if (_weatherData!.hasAlerts) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.red.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Weather Alerts',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...List.generate(
                  _weatherData!.alerts.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _weatherData!.alerts[index],
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWeatherDetail(IconData icon, String title, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
