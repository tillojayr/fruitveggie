# Weather API Setup Instructions

This app uses the OpenWeatherMap API to provide real-time weather information. Follow these steps to set up your own API key:

## Steps to get an API key

1. Go to [OpenWeatherMap](https://openweathermap.org/) and create a free account
2. After signing in, go to your API keys section
3. Generate a new API key if you don't already have one
4. Copy your API key

## Implementing your API key

Open the file `lib/services/weather_service.dart` and replace:

```dart
static const String _apiKey = 'YOUR_API_KEY';
```

with your actual API key:

```dart
static const String _apiKey = 'your_actual_api_key_here';
```

## Features

The weather widget provides:
- Current temperature
- Weather condition with icon
- Humidity level
- Wind speed
- "Feels like" temperature

The widget automatically refreshes every 15 minutes to provide up-to-date information.

## API Usage Limits

The free tier of OpenWeatherMap includes:
- 1,000 API calls per day
- 60 calls per minute
- Current weather data access

This is sufficient for most personal and small-scale applications. 