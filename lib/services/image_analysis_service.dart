import 'package:universal_io/io.dart';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class ImageAnalysisService {
  static const String _apiKey = 'AIzaSyC07lXkD3GWhW_tLOZgekWxrzeqgbN39c4';
  late final GenerativeModel _model;
  bool _isInitialized = false;

  // Predefined prompt for Google Gemini AI
  static const String _analysisPrompt = '''
You are an expert agricultural AI system that analyzes images of fruits and vegetables.
Return ONLY a valid JSON object (no code fences, no extra text) with these exact fields:

{
  "ripeness": <integer 0-100>,
  "okay_to_harvest": <true|false>,
  "days_to_harvest": <integer, 0 if ready now>,
  "image_description": "<concise description incl. color, shape, and condition>",
  "type": "<specific produce name, e.g., Tomato, Banana>",
  "category": "<Fruit or Vegetable>",
  "confidence": "<Integer 0-100>",
  "not_produce": <true|false>,
  "produce_type": "<e.g., Citrus, Berry, Leafy Green, Root, etc.>"
}

Rules:
- Never include explanations, text outside JSON, or commentary.
- Ripeness 0 means unripe, 100 means fully ripe.
- If spoiled/overripe, set "okay_to_harvest": false and "days_to_harvest": 0.
- Ensure the JSON is syntactically valid and complete (all fields present).
 - If the image does NOT contain any fruit or vegetable (e.g., people, animals, objects, landscapes, processed food), set "not_produce": true and fill other fields conservatively (ripeness: 0, okay_to_harvest: false, days_to_harvest: 0, image_description: brief reason). In this case still return a valid JSON.
''';

  ImageAnalysisService() {
    _initializeModel();
  }

  void _initializeModel() {
    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1, // Low temperature for consistent JSON output
        maxOutputTokens: 500,
        topP: 0.8,
        topK: 20,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
      ],
    );
    _isInitialized = true;
  }

  /// Analyzes an image file and returns structured analysis results
  ///
  /// [imageFile] - The image file to analyze
  ///
  /// Returns a Map with the following structure:
  /// {
  ///   "ripeness": int (0-100),
  ///   "okay_to_harvest": bool,
  ///   "days_to_harvest": int,
  ///   "image_description": String
  /// }
  Future<Map<String, dynamic>> analyze(File imageFile) async {
    if (!_isInitialized) {
      _initializeModel();
    }

    try {
      debugPrint('ImageAnalysisService: Starting image analysis...');

      // Read the image file
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Create content with image and prompt
      final content = [
        Content.multi([
          TextPart(_analysisPrompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      // Generate content using Gemini
      final response = await _model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception('No response received from Gemini AI');
      }

      debugPrint('ImageAnalysisService: Raw response: ${response.text}');

      // Parse the JSON response
      final Map<String, dynamic> result = _parseJsonResponse(response.text!);

      debugPrint('ImageAnalysisService: Parsed result: $result');

      return result;
    } catch (e) {
      debugPrint('ImageAnalysisService: Error during analysis: $e');

      // Return default values in case of error
      return {
        "ripeness": 50,
        "okay_to_harvest": false,
        "days_to_harvest": 7,
        "image_description": "Unable to analyze image due to error: $e"
      };
    }
  }

  /// Parses the JSON response from Gemini AI
  Map<String, dynamic> _parseJsonResponse(String response) {
    try {
      // Clean the response - remove any markdown formatting or extra text
      String cleanedResponse = response.trim();

      // Remove markdown code blocks if present
      if (cleanedResponse.startsWith('```json')) {
        cleanedResponse = cleanedResponse.substring(7);
      }
      if (cleanedResponse.startsWith('```')) {
        cleanedResponse = cleanedResponse.substring(3);
      }
      if (cleanedResponse.endsWith('```')) {
        cleanedResponse =
            cleanedResponse.substring(0, cleanedResponse.length - 3);
      }

      cleanedResponse = cleanedResponse.trim();

      // Try to find JSON object in the response
      final jsonStart = cleanedResponse.indexOf('{');
      final jsonEnd = cleanedResponse.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        final jsonString = cleanedResponse.substring(jsonStart, jsonEnd + 1);
        final Map<String, dynamic> parsed = jsonDecode(jsonString);

        // Validate and sanitize the response
        return _validateAndSanitizeResponse(parsed);
      } else {
        throw Exception('No valid JSON found in response');
      }
    } catch (e) {
      debugPrint('ImageAnalysisService: JSON parsing error: $e');
      throw Exception('Failed to parse JSON response: $e');
    }
  }

  /// Validates and sanitizes the parsed response
  Map<String, dynamic> _validateAndSanitizeResponse(
      Map<String, dynamic> parsed) {
    return {
      "ripeness": _validateRipeness(parsed["ripeness"]),
      "okay_to_harvest": _validateBoolean(parsed["okay_to_harvest"]),
      "days_to_harvest": _validateDaysToHarvest(parsed["days_to_harvest"]),
      "image_description": _validateDescription(parsed["image_description"]),
      // pass through type and category if present
      "type": _validateDescription(parsed["type"]),
      "category": _validateDescription(parsed["category"]),
      "confidence": parsed["confidence"],
      "not_produce": _validateBoolean(parsed["not_produce"]),
    };
  }

  int _validateRipeness(dynamic value) {
    if (value is int) {
      return value.clamp(0, 100);
    } else if (value is String) {
      final parsed = int.tryParse(value);
      return parsed?.clamp(0, 100) ?? 50;
    }
    return 50; // Default value
  }

  bool _validateBoolean(dynamic value) {
    if (value is bool) {
      return value;
    } else if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false; // Default value
  }

  int _validateDaysToHarvest(dynamic value) {
    if (value is int) {
      return value.clamp(0, 365); // Reasonable range
    } else if (value is String) {
      final parsed = int.tryParse(value);
      return parsed?.clamp(0, 365) ?? 7;
    }
    return 7; // Default value
  }

  String _validateDescription(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return "No description available"; // Default value
  }

  /// Dispose resources
  void dispose() {
    // No specific disposal needed for GenerativeModel
    _isInitialized = false;
  }
}
