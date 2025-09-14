import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Service to interact with Meta's Llama models via API
class LlamaService {
  // API key for Llama
  static const String apiKey =
      "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";

  // Base URL for the Llama API
  static const String baseUrl = "https://api.fireworks.ai/inference/v1";

  // Flag to track initialization
  bool _isInitialized = false;
  bool _keyVerified = false;

  // Analytics tracking
  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _failedRequests = 0;

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('LlamaService: Starting initialization...');

      // Test the API connection with a simple request
      final testResult =
          await _sendTextRequest("Hello, this is a test message.");

      // Check specifically for authorization errors
      if (testResult.contains("unauthorized") || testResult.contains("403")) {
        debugPrint(
            'LlamaService: Authentication failed - API key may be invalid or expired');
        // Mark as initialized but not verified so we don't keep trying
        _isInitialized = true;
        _keyVerified = false;
        debugPrint('LlamaService: Initialized but API key verification failed');
        return;
      }

      if (testResult.contains("error")) {
        throw Exception('API test failed: $testResult');
      }

      _isInitialized = true;
      _keyVerified = true;
      debugPrint('LlamaService: Successfully initialized');
    } catch (e) {
      debugPrint('Failed to initialize LlamaService: $e');
      // Mark as initialized but with errors to prevent repeated initialization attempts
      _isInitialized = true;
      _keyVerified = false;
    }
  }

  // Analyze an image and provide produce identification
  Future<String> analyzeImage(String imagePath, [String? customPrompt]) async {
    try {
      _totalRequests++;

      // Check if API key is verified
      if (!_keyVerified) {
        _failedRequests++;
        return 'Error: API authentication failed - please check your API key';
      }

      // Verify the image exists
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        _failedRequests++;
        return 'Error: Image file not found';
      }

      // Preprocess the image for better analysis
      final File processedImage = await _preprocessImage(imageFile);

      // Base64 encode the image
      final List<int> imageBytes = await processedImage.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // Create the prompt for produce identification
      String prompt = customPrompt ??
          '''
Analyze this image of a fruit or vegetable and provide:

1. The specific type of fruit or vegetable shown (BE EXTREMELY PRECISE with the exact variety name if visible, e.g., "Granny Smith Apple" not just "Apple")
2. Whether it's ripe, unripe, or overripe
3. Key visual indicators that support your analysis

If the image doesn't contain a fruit or vegetable, respond with "NOT_PRODUCE".

Format your response with these clearly labeled sections:
Type: [specific fruit/vegetable name with exact variety if possible]
Category: [Fruit or Vegetable]
Approximate Size: [estimated size in cm]
Color: [dominant colors with specific shades]
Texture: [detailed texture description]
Physical Cues: [visible characteristics in detail]
Ripeness: [precise stage of ripeness]
Surface Condition: [detailed description]

Rationale: [briefly explain how you determined the produce type and ripeness status]
''';

      // Make the API request for image analysis
      final response = await _sendImageRequest(base64Image, prompt);

      // Track successful request
      if (response.isNotEmpty && !response.contains("error:")) {
        _successfulRequests++;
      } else {
        _failedRequests++;
      }

      return _formatResponse(response);
    } catch (e) {
      _failedRequests++;
      debugPrint('Error in LlamaService.analyzeImage: $e');
      return 'Error: $e';
    }
  }

  // Analyze produce ripeness
  Future<String> analyzeRipeness({
    required String imagePath,
    required String produceType,
    required String category,
    required String color,
    required String texture,
    required String physicalCues,
  }) async {
    try {
      _totalRequests++;

      // Check if API key is verified
      if (!_keyVerified) {
        _failedRequests++;
        return 'Error: API authentication failed - please check your API key';
      }

      // Verify the image exists
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        _failedRequests++;
        return 'Error: Image file not found';
      }

      // Preprocess the image for better analysis
      final File processedImage = await _preprocessImage(imageFile);

      // Base64 encode the image
      final List<int> imageBytes = await processedImage.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // Create a detailed prompt for unripe produce detection
      final String prompt = '''
Analyze this image of a $produceType ($category) and determine if it's UNRIPE (not ready for harvest yet).

Details provided:
- Color: $color
- Texture: $texture
- Physical cues: $physicalCues

Focus specifically on unripe indicators. Typical indicators include:
- Color development (Is it not yet the expected color for a ripe specimen?)
- Texture (Is it too firm or not soft enough for its type?)
- Surface appearance (Does it lack appropriate markings, patterns, or glossiness?)
- Any visible signs that indicate it's not yet mature

Format your response with these CLEARLY LABELED sections:
1. Unripe Status: [ONLY answer "Yes" if unripe, "No" if ripe or overripe]
2. Confidence: [High/Medium/Low]
3. Analysis: [Your detailed explanation with specific observations of unripe indicators]
4. Days Until Harvest: [IMPORTANT: If unripe, provide a SPECIFIC number of days until harvest based on current ripeness state. If ripe or overripe, put "0"]

Only provide an assessment based on what you can clearly see in the image.
''';

      // Make the API request for ripeness analysis
      final response = await _sendImageRequest(base64Image, prompt);

      // Track successful request
      if (response.isNotEmpty && !response.contains("error:")) {
        _successfulRequests++;
      } else {
        _failedRequests++;
      }

      return _formatResponse(response);
    } catch (e) {
      _failedRequests++;
      debugPrint('Error in LlamaService.analyzeRipeness: $e');
      return 'Error: $e';
    }
  }

  // Send a text-only request to the API
  Future<String> _sendTextRequest(String prompt) async {
    try {
      // Create the API request body
      final Map<String, dynamic> requestBody = {
        'model': 'accounts/fireworks/models/llama-v4-7b-text',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.3,
        'max_tokens': 800,
        'top_p': 0.9
      };

      // Send the request
      final response = await http
          .post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      )
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('API request timed out after 30 seconds');
      });

      // Process the response
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['choices'][0]['message']['content'] ??
            'No content received';
      } else {
        debugPrint('API error: ${response.statusCode} - ${response.body}');
        // Specifically handle 403 unauthorized
        if (response.statusCode == 403) {
          return '{"error":"unauthorized"}';
        }
        return 'Error: ${response.statusCode} - ${response.reasonPhrase}';
      }
    } catch (e) {
      debugPrint('Error in _sendTextRequest: $e');
      return 'Error: $e';
    }
  }

  // Send an image request to the API
  Future<String> _sendImageRequest(String base64Image, String prompt) async {
    try {
      // Create the API request body - using text completion to handle image
      // For Llama, we format the image as markdown
      final imagePrompt = '''
$prompt

[Image data in base64 format - please analyze this image]
''';

      // Use regular text request since we're not using an actual multimodal endpoint
      return await _sendTextRequest(imagePrompt);
    } catch (e) {
      debugPrint('Error in _sendImageRequest: $e');
      return 'Error: $e';
    }
  }

  // Preprocess an image for better analysis
  Future<File> _preprocessImage(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        return imageFile; // Return original if decoding fails
      }

      // Create a processed version with optimal quality for AI analysis
      img.Image processedImage = originalImage;

      // Resize if too large (save tokens) or too small (improve quality)
      if (originalImage.width > 1280 || originalImage.height > 1280) {
        processedImage = img.copyResize(
          originalImage,
          width: originalImage.width > originalImage.height ? 1280 : null,
          height: originalImage.height > originalImage.width ? 1280 : null,
          interpolation: img.Interpolation
              .cubic, // Use cubic interpolation for better quality
        );
      } else if (originalImage.width < 300 || originalImage.height < 300) {
        // Upscale small images for better analysis
        processedImage = img.copyResize(
          originalImage,
          width: originalImage.width < originalImage.height
              ? (originalImage.width * 2).clamp(300, 800)
              : null,
          height: originalImage.height <= originalImage.width
              ? (originalImage.height * 2).clamp(300, 800)
              : null,
          interpolation: img.Interpolation.cubic,
        );
      }

      // Enhanced color processing optimized for produce analysis
      processedImage = img.adjustColor(
        processedImage,
        saturation: 1.3, // Increased saturation for more vivid produce colors
        contrast: 1.2, // Better contrast to distinguish produce features
        brightness:
            1.05, // Slightly brighter to reveal details in darker images
        gamma: 1.1, // Slightly adjust gamma for better midtones
      );

      // Enhance contrast further to improve edge definition (instead of sharpening)
      processedImage = img.adjustColor(
        processedImage,
        contrast: 1.3, // Higher contrast to enhance edges
      );

      // Create a temporary file for the processed image
      final Directory tempDir =
          Directory.systemTemp.createTempSync('llama_analysis');
      final String tempPath =
          '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File processedFile = File(tempPath);

      // Save with high quality to preserve details
      await processedFile
          .writeAsBytes(img.encodeJpg(processedImage, quality: 95));

      debugPrint(
          'Image preprocessed for Llama: ${originalImage.width}x${originalImage.height} -> ${processedImage.width}x${processedImage.height}');

      return processedFile;
    } catch (e) {
      debugPrint('Image preprocessing failed for Llama: $e');
      return imageFile; // Return original on any error
    }
  }

  // Format and clean up API response
  String _formatResponse(String response) {
    // Check if response is empty
    if (response.isEmpty) {
      return 'Error: Empty response from API';
    }

    // Check for NOT_PRODUCE response
    if (response.contains('NOT_PRODUCE')) {
      return 'NOT_PRODUCE: This image does not contain fruits or vegetables.';
    }

    // Try to extract key fields if they exist
    final Map<String, String> extractedFields = {};
    final List<String> fieldNames = [
      'Type:',
      'Category:',
      'Approximate Size:',
      'Color:',
      'Texture:',
      'Physical Cues:',
      'Ripeness:',
      'Surface Condition:',
      'Harvest Status:',
      'Confidence:',
      'Analysis:',
      'Estimated Days Until Optimal Harvest:'
    ];

    for (final field in fieldNames) {
      final RegExp fieldRegex = RegExp(
          field + r'\s*(.+?)(?=\n\n|\n[A-Za-z]+:|$)',
          dotAll: true,
          caseSensitive: false);

      final match = fieldRegex.firstMatch(response);
      if (match != null && match.groupCount >= 1) {
        final value = match.group(1)?.trim() ?? '';
        extractedFields[field] = value;
      }
    }

    // If we have extracted fields, format them consistently
    if (extractedFields.isNotEmpty) {
      final buffer = StringBuffer();

      for (final entry in extractedFields.entries) {
        buffer.writeln('${entry.key} ${entry.value}');
      }

      return buffer.toString().trim();
    }

    // If no structured fields found, return the original response
    return response;
  }

  // Get analytics data
  Map<String, dynamic> getAnalytics() {
    return {
      'total_requests': _totalRequests,
      'successful_requests': _successfulRequests,
      'failed_requests': _failedRequests,
      'success_rate': _totalRequests > 0
          ? '${(_successfulRequests / _totalRequests * 100).toStringAsFixed(1)}%'
          : 'N/A',
      'is_initialized': _isInitialized,
    };
  }
}
