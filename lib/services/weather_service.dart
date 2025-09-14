import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:async';

// Model class for weather data
class WeatherData {
  final String location;
  final double temperature;
  final String description;
  final String iconCode;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final DateTime lastUpdated;
  final List<String> alerts;
  final double latitude; // Added latitude
  final double longitude; // Added longitude
  final double visibility; // Added visibility in meters
  final int pressure; // Added pressure in hPa
  final int cloudiness; // Added cloudiness percentage

  WeatherData({
    required this.location,
    required this.temperature,
    required this.description,
    required this.iconCode,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.latitude,
    required this.longitude,
    required this.visibility,
    required this.pressure,
    required this.cloudiness,
    DateTime? lastUpdated,
    List<String>? alerts,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        alerts = alerts ?? [];

  String get iconUrl => 'https://openweathermap.org/img/wn/$iconCode@2x.png';

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    // Extract any alerts if available
    List<String> alerts = [];

    // Check for extreme conditions
    final double temp = json['main']['temp'] - 273.15;
    final int humidity = json['main']['humidity'];
    final double windSpeed = json['wind']['speed'];
    final String description =
        json['weather'][0]['description'].toString().toLowerCase();
    final int pressure = json['main']['pressure'];
    final int visibility = json['visibility'];

    // Generate alerts based on conditions
    if (temp > 35) {
      alerts.add(
          'Extreme heat warning! Stay hydrated and avoid prolonged sun exposure.');
    } else if (temp > 30) {
      alerts.add('High temperature alert. Take precautions when outdoors.');
    }

    if (temp < 0) {
      alerts.add('Freezing conditions. Protect sensitive plants.');
    }

    if (humidity > 90) {
      alerts.add(
          'Very high humidity. Plants may be susceptible to fungal diseases.');
    } else if (humidity < 20) {
      alerts.add('Very low humidity. Plants may need extra watering.');
    }

    if (windSpeed > 10) {
      alerts.add('Strong winds. Secure outdoor plants and items.');
    }

    if (description.contains('rain') && description.contains('heavy')) {
      alerts.add('Heavy rain alert. Check drainage for outdoor plants.');
    }

    if (description.contains('thunder') || description.contains('storm')) {
      alerts.add(
          'Thunderstorm alert. Move sensitive plants indoors if possible.');
    }

    if (description.contains('snow')) {
      alerts.add('Snow conditions. Protect plants from frost damage.');
    }

    // Add alerts for low visibility
    if (visibility < 1000) {
      alerts.add('Very low visibility. Take caution when traveling.');
    }

    // Add alerts for extreme pressure changes
    if (pressure < 990) {
      alerts.add('Low pressure system. Weather changes may be coming.');
    }

    return WeatherData(
      location: json['name'],
      temperature: temp,
      description: json['weather'][0]['description'],
      iconCode: json['weather'][0]['icon'],
      feelsLike: (json['main']['feels_like'] - 273.15),
      humidity: json['main']['humidity'],
      windSpeed: json['wind']['speed'],
      latitude: json['coord']['lat'].toDouble(),
      longitude: json['coord']['lon'].toDouble(),
      visibility: json['visibility'].toDouble(),
      pressure: json['main']['pressure'],
      cloudiness: json['clouds']['all'],
      lastUpdated: DateTime.now(),
      alerts: alerts,
    );
  }

  // Check if there are any weather alerts
  bool get hasAlerts => alerts.isNotEmpty;
}

// Model class for forecast data
class ForecastData {
  final String day;
  final double temperature;
  final double minTemperature;
  final double maxTemperature;
  final String description;
  final String iconCode;
  final int humidity;
  final double windSpeed;
  final DateTime date;

  ForecastData({
    required this.day,
    required this.temperature,
    required this.minTemperature,
    required this.maxTemperature,
    required this.description,
    required this.iconCode,
    required this.humidity,
    required this.windSpeed,
    required this.date,
  });

  String get iconUrl => 'https://openweathermap.org/img/wn/$iconCode@2x.png';

  factory ForecastData.fromJson(Map<String, dynamic> json) {
    final temp = json['main']['temp'].toDouble();
    final minTemp = json['main']['temp_min'].toDouble();
    final maxTemp = json['main']['temp_max'].toDouble();
    final date = DateTime.fromMillisecondsSinceEpoch(json['dt'] * 1000);

    // Get day name
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];
    final dayName = dayNames[date.weekday % 7];

    return ForecastData(
      day: dayName,
      temperature: temp,
      minTemperature: minTemp,
      maxTemperature: maxTemp,
      description: json['weather'][0]['description'],
      iconCode: json['weather'][0]['icon'],
      humidity: json['main']['humidity'],
      windSpeed: json['wind']['speed'].toDouble(),
      date: date,
    );
  }
}

class WeatherService {
  static const String _apiKey = '4b3ba05439881193d303740effff31c9';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  // Cache management
  final Map<String, _CachedWeatherData> _cityCache = {};
  final Map<String, _CachedWeatherData> _coordCache = {};
  final Map<String, _CachedForecastData> _forecastCache = {};

  // Cache timeout (1 minute for real-time updates)
  static const Duration _cacheTimeout = Duration(minutes: 1);

  // HTTP client with timeout
  final http.Client _client = http.Client();

  // Get weather by city name with caching
  Future<WeatherData> getWeatherByCity(String city) async {
    if (city.isEmpty) {
      throw Exception('City name cannot be empty');
    }

    final cacheKey = city.toLowerCase().trim();

    // Check if we have a valid cached response
    if (_cityCache.containsKey(cacheKey)) {
      final cachedData = _cityCache[cacheKey]!;
      if (DateTime.now().difference(cachedData.timestamp) < _cacheTimeout) {
        debugPrint('Using cached weather data for $city');
        return cachedData.data;
      }
      // Cache expired, remove it
      _cityCache.remove(cacheKey);
    }

    try {
      final encodedCity = Uri.encodeComponent(city);
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/weather?q=$encodedCity&appid=$_apiKey'),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(response.body);
        final weatherData = WeatherData.fromJson(jsonData);

        // Cache the result
        _cityCache[cacheKey] = _CachedWeatherData(
          data: weatherData,
          timestamp: DateTime.now(),
        );

        return weatherData;
      } else if (response.statusCode == 404) {
        throw Exception('City not found: $city');
      } else {
        throw Exception(
            'Failed to load weather data: ${response.statusCode} - ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Request timed out. Check your internet connection.');
    } catch (e) {
      debugPrint('Error fetching weather for $city: $e');
      rethrow;
    }
  }

  // Get weather by coordinates with caching
  Future<WeatherData> getWeatherByLocation(double lat, double lon) async {
    // Validate coordinates
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw Exception(
          'Invalid coordinates: latitude must be between -90 and 90, longitude between -180 and 180');
    }

    // Round coordinates to 4 decimal places for better accuracy (approximately 11 meters)
    final roundedLat = (lat * 10000).round() / 10000;
    final roundedLon = (lon * 10000).round() / 10000;
    final cacheKey = '${roundedLat}_$roundedLon';

    // Check if we have a valid cached response
    if (_coordCache.containsKey(cacheKey)) {
      final cachedData = _coordCache[cacheKey]!;
      // Reduced cache timeout to 1 minute for real-time updates
      if (DateTime.now().difference(cachedData.timestamp) <
          const Duration(minutes: 1)) {
        debugPrint(
            'Using cached weather data for coordinates $roundedLat,$roundedLon');
        return cachedData.data;
      }
      // Cache expired, remove it
      _coordCache.remove(cacheKey);
    }

    try {
      // Use OneCall API for more accurate and detailed weather data
      final response = await _client
          .get(
            Uri.parse(
                '$_baseUrl/weather?lat=$roundedLat&lon=$roundedLon&appid=$_apiKey&units=metric'),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(response.body);
        final weatherData = WeatherData.fromJson(jsonData);

        // Cache the result
        _coordCache[cacheKey] = _CachedWeatherData(
          data: weatherData,
          timestamp: DateTime.now(),
        );

        return weatherData;
      } else {
        throw Exception(
            'Failed to load weather data: ${response.statusCode} - ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Request timed out. Check your internet connection.');
    } catch (e) {
      debugPrint('Error fetching weather for coordinates $lat,$lon: $e');
      rethrow;
    }
  }

  // Get plant care recommendations based on weather
  List<String> getPlantCareRecommendations(WeatherData weather) {
    final List<String> recommendations = [];
    final double temp = weather.temperature;
    final int humidity = weather.humidity;
    final String description = weather.description.toLowerCase();
    final double windSpeed = weather.windSpeed;
    final int cloudiness = weather.cloudiness;

    // Temperature-based recommendations
    if (temp > 30) {
      recommendations
          .add('Water plants more frequently due to high temperatures.');
      recommendations.add('Consider providing shade for sensitive plants.');
    } else if (temp < 5) {
      recommendations.add(
          'Protect plants from frost damage with covers or bring them indoors.');
      recommendations
          .add('Reduce watering as plants need less water in cold weather.');
    }

    // Humidity-based recommendations
    if (humidity < 30) {
      recommendations.add(
          'Increase humidity around plants by misting or using a humidifier.');
    } else if (humidity > 80) {
      recommendations
          .add('Monitor plants for fungal diseases due to high humidity.');
      recommendations.add('Ensure good air circulation around plants.');
    }

    // Weather condition-based recommendations
    if (description.contains('rain')) {
      recommendations
          .add('Skip watering today as natural rainfall is sufficient.');
      recommendations.add('Check drainage to prevent waterlogging.');
    }

    if (description.contains('sun') || description.contains('clear')) {
      recommendations.add('Great day for outdoor gardening activities!');
      recommendations.add('Consider harvesting fruits and vegetables.');
    }

    if (description.contains('cloud')) {
      recommendations
          .add('Ideal conditions for transplanting or repotting plants.');
    }

    // Wind-based recommendations
    if (windSpeed > 8) {
      recommendations.add('Protect delicate plants from strong winds.');
    }

    // Cloudiness-based recommendations
    if (cloudiness > 80) {
      recommendations.add(
          'Limited sunlight today. Consider moving sun-loving plants to brighter spots.');
    }

    if (recommendations.isEmpty) {
      recommendations.add('Regular plant care recommended today.');
    }

    return recommendations;
  }

  // Get 5-day weather forecast by coordinates
  Future<List<ForecastData>> getForecastByLocation(
      double lat, double lon) async {
    // Validate coordinates
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw Exception(
          'Invalid coordinates: latitude must be between -90 and 90, longitude between -180 and 180');
    }

    // Round coordinates to 4 decimal places for better accuracy
    final roundedLat = (lat * 10000).round() / 10000;
    final roundedLon = (lon * 10000).round() / 10000;
    final cacheKey = '${roundedLat}_$roundedLon';

    // Check if we have a valid cached response
    if (_forecastCache.containsKey(cacheKey)) {
      final cachedData = _forecastCache[cacheKey]!;
      // Cache forecast for 30 minutes as it changes less frequently
      if (DateTime.now().difference(cachedData.timestamp) <
          const Duration(minutes: 30)) {
        debugPrint(
            'Using cached forecast data for coordinates $roundedLat,$roundedLon');
        return cachedData.data;
      }
      // Cache expired, remove it
      _forecastCache.remove(cacheKey);
    }

    try {
      final response = await _client
          .get(
            Uri.parse(
                '$_baseUrl/forecast?lat=$roundedLat&lon=$roundedLon&appid=$_apiKey&units=metric'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(response.body);
        final List<dynamic> forecastList = jsonData['list'];

        // Group forecasts by day and take one forecast per day (around noon)
        final Map<String, ForecastData> dailyForecasts = {};

        for (final item in forecastList) {
          final forecast = ForecastData.fromJson(item);
          final dateKey =
              '${forecast.date.year}-${forecast.date.month}-${forecast.date.day}';

          // Take the forecast closest to noon (12:00) for each day
          if (!dailyForecasts.containsKey(dateKey) ||
              (forecast.date.hour >= 12 && forecast.date.hour < 15)) {
            dailyForecasts[dateKey] = forecast;
          }
        }

        // Convert to list and take first 5 days
        final List<ForecastData> forecastData = dailyForecasts.values.toList();
        forecastData.sort((a, b) => a.date.compareTo(b.date));
        final List<ForecastData> fiveDayForecast =
            forecastData.take(5).toList();

        // Cache the result
        _forecastCache[cacheKey] = _CachedForecastData(
          data: fiveDayForecast,
          timestamp: DateTime.now(),
        );

        return fiveDayForecast;
      } else {
        throw Exception(
            'Failed to load forecast data: ${response.statusCode} - ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Request timed out. Check your internet connection.');
    } catch (e) {
      debugPrint('Error fetching forecast for coordinates $lat,$lon: $e');
      rethrow;
    }
  }

  // Get 5-day weather forecast by city name
  Future<List<ForecastData>> getForecastByCity(String city) async {
    if (city.isEmpty) {
      throw Exception('City name cannot be empty');
    }

    try {
      final encodedCity = Uri.encodeComponent(city);
      final response = await _client
          .get(
            Uri.parse(
                '$_baseUrl/forecast?q=$encodedCity&appid=$_apiKey&units=metric'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(response.body);
        final List<dynamic> forecastList = jsonData['list'];

        // Group forecasts by day and take one forecast per day (around noon)
        final Map<String, ForecastData> dailyForecasts = {};

        for (final item in forecastList) {
          final forecast = ForecastData.fromJson(item);
          final dateKey =
              '${forecast.date.year}-${forecast.date.month}-${forecast.date.day}';

          // Take the forecast closest to noon (12:00) for each day
          if (!dailyForecasts.containsKey(dateKey) ||
              (forecast.date.hour >= 12 && forecast.date.hour < 15)) {
            dailyForecasts[dateKey] = forecast;
          }
        }

        // Convert to list and take first 5 days
        final List<ForecastData> forecastData = dailyForecasts.values.toList();
        forecastData.sort((a, b) => a.date.compareTo(b.date));
        return forecastData.take(5).toList();
      } else if (response.statusCode == 404) {
        throw Exception('City not found: $city');
      } else {
        throw Exception(
            'Failed to load forecast data: ${response.statusCode} - ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Request timed out. Check your internet connection.');
    } catch (e) {
      debugPrint('Error fetching forecast for $city: $e');
      rethrow;
    }
  }

  // Clear all caches
  void clearCache() {
    _cityCache.clear();
    _coordCache.clear();
    _forecastCache.clear();
    debugPrint('Weather cache cleared');
  }

  // Dispose HTTP client
  void dispose() {
    _client.close();
  }
}

// Helper class for caching
class _CachedWeatherData {
  final WeatherData data;
  final DateTime timestamp;

  _CachedWeatherData({
    required this.data,
    required this.timestamp,
  });
}

// Helper class for caching forecast data
class _CachedForecastData {
  final List<ForecastData> data;
  final DateTime timestamp;

  _CachedForecastData({
    required this.data,
    required this.timestamp,
  });
}
