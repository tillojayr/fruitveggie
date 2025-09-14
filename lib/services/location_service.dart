import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Stream controller for position updates
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  final List<Function(Position)> _locationListeners = [];

  // Cache for geocoded addresses
  final Map<String, String> _addressCache = {};
  static const int _maxAddressCacheSize = 20;

  // Location accuracy settings - improved for better accuracy
  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation, // Highest possible accuracy
    distanceFilter: 5, // Updates when device moves 5 meters (more frequent)
    timeLimit: Duration(seconds: 3), // Shorter timeout for faster updates
  );

  // Get current location with permission handling
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return Future.error(
            'Location services are disabled. Please enable them in your device settings.');
      }
    } catch (e) {
      debugPrint('Error checking location service status: $e');
      return Future.error('Could not check location service status: $e');
    }

    // Check location permissions
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return Future.error('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return Future.error(
            'Location permissions are permanently denied. Please enable them in your app settings.');
      }
    } catch (e) {
      debugPrint('Error checking location permissions: $e');
      return Future.error('Could not check location permissions: $e');
    }

    // When we reach here, permissions are granted
    try {
      // Use the cached position if available and recent (less than 30 seconds old for real-time updates)
      if (_lastPosition != null) {
        final now = DateTime.now();
        final positionTime = DateTime.fromMillisecondsSinceEpoch(
          _lastPosition!.timestamp.millisecondsSinceEpoch,
        );
        if (now.difference(positionTime).inSeconds < 30) {
          debugPrint(
              'Using cached position from ${now.difference(positionTime).inSeconds} seconds ago');
          return _lastPosition;
        }
      }

      // Get fresh position with best accuracy
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Validate the position data
      if (_isValidPosition(position)) {
        _lastPosition = position;
        debugPrint(
            'Got new position: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
        return position;
      } else {
        debugPrint(
            'Received invalid position data, trying again with lower accuracy');
        throw Exception('Invalid position data');
      }
    } catch (e) {
      debugPrint('Error getting location with high accuracy: $e');
      // If timeout or error, try with lower accuracy
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );

        if (_isValidPosition(position)) {
          _lastPosition = position;
          debugPrint(
              'Got position with medium accuracy: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
          return position;
        } else {
          debugPrint('Received invalid position data with medium accuracy');
          throw Exception('Invalid position data');
        }
      } catch (e) {
        debugPrint('Error getting location with reduced accuracy: $e');
        // If we still have a last position, return it even if it's old
        if (_lastPosition != null) {
          debugPrint('Returning last known position as fallback');
          return _lastPosition;
        }

        // Last attempt with low accuracy
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 3),
            ),
          );

          _lastPosition = position;
          debugPrint(
              'Got position with low accuracy: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');
          return position;
        } catch (finalError) {
          debugPrint('All location attempts failed: $finalError');
          return null;
        }
      }
    }
  }

  // Validate position data to ensure it's reasonable
  bool _isValidPosition(Position position) {
    // Check if coordinates are within valid ranges
    if (position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180) {
      return false;
    }

    // More stringent accuracy check (less than 50 meters for better precision in real-time updates)
    if (position.accuracy > 50) {
      return false;
    }

    // Check if the position timestamp is recent (within last minute)
    final positionTime = DateTime.fromMillisecondsSinceEpoch(
      position.timestamp.millisecondsSinceEpoch,
    );
    if (DateTime.now().difference(positionTime).inMinutes > 1) {
      return false;
    }

    return true;
  }

  // Start continuous location updates
  void startLocationUpdates() {
    if (_positionStreamSubscription != null) {
      return; // Already running
    }

    try {
      final Stream<Position> positionStream =
          Geolocator.getPositionStream(locationSettings: _locationSettings);

      _positionStreamSubscription = positionStream.listen((Position position) {
        // Validate position before using it
        if (_isValidPosition(position)) {
          _lastPosition = position;
          debugPrint(
              'Position update: ${position.latitude}, ${position.longitude} (accuracy: ${position.accuracy}m)');

          // Notify all listeners of the new position
          for (final listener in _locationListeners) {
            listener(position);
          }
        } else {
          debugPrint('Received invalid position update, ignoring');
        }
      }, onError: (e) {
        debugPrint('Position stream error: $e');

        // Attempt to restart the stream after a brief delay if there's an error
        Future.delayed(const Duration(seconds: 5), () {
          if (_positionStreamSubscription != null) {
            stopLocationUpdates();
            startLocationUpdates();
          }
        });
      });

      debugPrint('Location updates started');
    } catch (e) {
      debugPrint('Error starting location updates: $e');
    }
  }

  // Stop position updates
  void stopLocationUpdates() {
    if (_positionStreamSubscription != null) {
      _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
      debugPrint('Location updates stopped');
    }
  }

  // Add a listener for location updates
  void addLocationListener(Function(Position) listener) {
    if (!_locationListeners.contains(listener)) {
      _locationListeners.add(listener);

      // Start location updates if this is the first listener
      if (_locationListeners.length == 1) {
        startLocationUpdates();
      }
    }
  }

  // Remove a listener
  void removeLocationListener(Function(Position) listener) {
    _locationListeners.remove(listener);

    // Stop updates if no more listeners
    if (_locationListeners.isEmpty) {
      stopLocationUpdates();
    }
  }

  // Get the last known position without requesting a new one
  Position? getLastKnownPosition() {
    return _lastPosition;
  }

  // Get estimated address from coordinates with caching
  Future<String?> getAddressFromCoordinates(
      double latitude, double longitude) async {
    // Check if coordinates are valid
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      debugPrint('Invalid coordinates: $latitude, $longitude');
      return null;
    }

    // Round coordinates for caching to reduce API calls
    final roundedLat = (latitude * 1000).round() / 1000;
    final roundedLon = (longitude * 1000).round() / 1000;
    final cacheKey = '${roundedLat}_$roundedLon';

    // Check cache first
    if (_addressCache.containsKey(cacheKey)) {
      debugPrint(
          'Using cached address for coordinates $roundedLat, $roundedLon');
      return _addressCache[cacheKey];
    }

    try {
      // Use the geocoding package to get address
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;

        // Build a readable address string
        final List<String> addressParts = [];

        if (placemark.name != null && placemark.name!.isNotEmpty) {
          addressParts.add(placemark.name!);
        }

        if (placemark.locality != null && placemark.locality!.isNotEmpty) {
          addressParts.add(placemark.locality!);
        } else if (placemark.subLocality != null &&
            placemark.subLocality!.isNotEmpty) {
          addressParts.add(placemark.subLocality!);
        }

        if (placemark.administrativeArea != null &&
            placemark.administrativeArea!.isNotEmpty) {
          addressParts.add(placemark.administrativeArea!);
        }

        if (placemark.country != null && placemark.country!.isNotEmpty) {
          addressParts.add(placemark.country!);
        }

        final String address = addressParts.join(', ');

        // Cache the result
        _cacheAddress(cacheKey, address);

        debugPrint('Geocoded address: $address');
        return address;
      }
    } catch (e) {
      debugPrint('Error geocoding coordinates: $e');
    }

    // Fallback to coordinates if geocoding fails
    final fallbackAddress =
        'Location (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})';
    _cacheAddress(cacheKey, fallbackAddress);
    return fallbackAddress;
  }

  // Helper method to cache address and manage cache size
  void _cacheAddress(String key, String address) {
    // If cache is full, remove oldest entry
    if (_addressCache.length >= _maxAddressCacheSize) {
      final firstKey = _addressCache.keys.first;
      _addressCache.remove(firstKey);
    }

    _addressCache[key] = address;
  }

  // Clear the address cache
  void clearAddressCache() {
    _addressCache.clear();
    debugPrint('Address cache cleared');
  }
}
