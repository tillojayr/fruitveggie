import 'dart:io';
import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class GeminiService {
  static const String apiKey = 'AIzaSyC07lXkD3GWhW_tLOZgekWxrzeqgbN39c4';
  final GenerativeModel _model;
  final GenerativeModel _backupModel;
  final GenerativeModel _textModel;

  // Add a flag to track initialization
  bool _isInitialized = false;

  // Counters for analytics
  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _failedRequests = 0;

  GeminiService()
      : _model = GenerativeModel(
          model: 'gemini-2.0-flash',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature:
                0.2, // Increased from 0.1 to be more creative with low quality images
            maxOutputTokens: 2000,
            topP: 0.95,
            topK: 40,
          ),
          // Safety settings to avoid content filtering issues
          safetySettings: [
            SafetySetting(
                HarmCategory.dangerousContent, HarmBlockThreshold.none),
            SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
            SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
            SafetySetting(
                HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
          ],
        ),
        // Backup model with slightly different settings
        _backupModel = GenerativeModel(
          model: 'gemini-2.0-flash',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.3, // Increased from 0.2 for more flexibility
            maxOutputTokens: 2000,
            topP: 0.97,
            topK: 50,
          ),
          // Safety settings to avoid content filtering issues
          safetySettings: [
            SafetySetting(
                HarmCategory.dangerousContent, HarmBlockThreshold.none),
            SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
            SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
            SafetySetting(
                HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
          ],
        ),
        _textModel = GenerativeModel(
          model: 'gemini-pro',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            temperature: 0.2, // Increased from 0.1
            maxOutputTokens: 2000,
            topP: 0.95,
            topK: 40,
          ),
        );

  // Initialize method to ensure the service is ready
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('GeminiService: Starting initialization...');
      // Perform a simple test query to ensure the API key is valid
      // Use a simple text prompt without any complex content
      debugPrint('GeminiService: Testing API connection...');
      try {
        // Try to initialize with the main model first
        await _model.generateContent([Content.text('Test connection')]);
        _isInitialized = true;
        debugPrint(
            'Gemini service initialized successfully with gemini-2.0-flash');
      } catch (apiError) {
        debugPrint('Primary model validation failed: $apiError');
        try {
          // Try with backup model
          await _backupModel.generateContent([Content.text('Test connection')]);
          _isInitialized = true;
          debugPrint(
              'Gemini service initialized with backup gemini-2.0-flash model');
        } catch (backupError) {
          // Finally try with text-only model (which might have different capabilities)
          await _textModel.generateContent([Content.text('Test connection')]);
          _isInitialized = true;
          debugPrint('Gemini service initialized with text-only model');
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize Gemini service: $e');
      // Don't throw here, just log the error
    }
  }

  Future<String> analyzeImage(String imagePath, [String? customPrompt]) async {
    try {
      _totalRequests++;

      // Verify image exists and has valid size
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        _failedRequests++;
        return 'Error: Image file not found';
      }

      // NEW: Preprocess the image to improve analysis quality
      final File processedImageFile = await _preprocessImage(imageFile);
      final String processedImagePath = processedImageFile.path;
      debugPrint('Image preprocessed: $processedImagePath');

      // Add non-produce image detection prompt if no custom prompt is provided
      String prompt = customPrompt ??
          '''
Analyze this image and identify the specific fruit or vegetable shown.

IMPORTANT: As your FIRST priority, carefully assess if this is actually an image of a raw, unprocessed fruit or vegetable.
If the image does NOT show any raw fruit or vegetable (such as an object, animal, person, landscape, etc.), respond EXACTLY with the following format:
"NOT_PRODUCE: This image does not contain fruits or vegetables."

Do NOT analyze any image that isn't clearly a raw, unprocessed fruit or vegetable. REJECT all of the following:
- Animals, people, or body parts
- Furniture, vehicles, electronics, or any man-made objects
- Landscapes, buildings, or scenery
- Processed foods (bread, pasta, meals, cooked dishes)
- Meat, fish, poultry, or dairy products
- Flowers, decorative plants, or non-edible vegetation
- Prepared salads or cut fruit plates
- Packaged or canned foods
- Drawings, cartoons, or illustrations of produce
- Blurry or extremely poor quality images where content is not clearly identifiable

Only if you are CERTAIN the image contains a fruit or vegetable, provide your response in this EXACT format with ALL fields:
Type: [specific fruit/vegetable name - BE EXTREMELY PRECISE with the exact variety name if visible (e.g., "Granny Smith Apple" not just "Apple")]
Category: [Fruit or Vegetable]
Approximate Size: [estimated size in cm]
Color: [dominant color - be specific about shade and intensity]
Texture: [texture description - firm, soft, smooth, rough, etc.]
Physical Cues: [any visible physical characteristics like spots, bruises, glossiness]
Unripe Status: [IMPORTANT: assess if unripe - answer "Yes" if unripe, "No" if ripe or overripe - BE VERY SPECIFIC]
Surface Condition: [smooth, bumpy, glossy, dull, etc.]

Focus particularly on the unripe assessment - look for these key indicators:
- For green produce: is the green color due to being unripe or is this its natural color when ripe?
- For fruit: check for color development, firmness, and surface quality
- For vegetables: assess size, color intensity, and physical damage
- If you can tell it's unripe, CLEARLY state "Yes" in the Unripe Status field
- If it's ripe or overripe, CLEARLY state "No" in the Unripe Status field

THE UNRIPE ASSESSMENT AND PRECISE PRODUCE TYPE IDENTIFICATION ARE THE MOST CRITICAL PARTS OF YOUR ANALYSIS.
''';

      // Read image bytes from the preprocessed image
      final imageBytes = await processedImageFile.readAsBytes();

      // Create parts for the content
      final parts = [
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ];

      // Create content with parts
      final content = [Content.multi(parts)];

      // Execute the model with timeout
      final response = await _model
          .generateContent(content)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Gemini API request timed out after 30 seconds');
      });

      final result = response.text ?? '';

      // Track successful requests
      if (result.isNotEmpty && !result.contains('Error:')) {
        _successfulRequests++;
      } else {
        _failedRequests++;
      }

      // First check - direct NOT_PRODUCE response
      if (result.contains('NOT_PRODUCE:') ||
          result.toLowerCase().contains('this image does not contain') ||
          result.toLowerCase().contains('no fruits or vegetables')) {
        debugPrint(
            'Gemini detected non-produce image - performing second validation');

        // Second validation - try again with a more strict prompt
        final secondPrompt = '''
VERIFICATION CHECK:
Carefully examine this image again and answer this single question:
Is this image clearly showing a raw, unprocessed fruit or vegetable?

Respond ONLY with one of these two options:
1. "CONFIRMED_NOT_PRODUCE" - if the image shows anything other than a raw fruit or vegetable
2. "PRODUCE_DETECTED: [type of produce]" - only if you are highly confident a raw fruit or vegetable is visible

Common items that should be rejected (not fruits/vegetables):
- Any cooked or prepared food
- Flowers or plants that aren't edible vegetables
- Processed foods of any kind
- Meat, fish, or other animal products
- Any man-made object
- Any living creature
- Landscapes or buildings
''';

        final secondParts = [
          TextPart(secondPrompt),
          DataPart('image/jpeg', imageBytes),
        ];

        final secondContent = [Content.multi(secondParts)];
        final secondResponse = await _model
            .generateContent(secondContent)
            .timeout(const Duration(seconds: 25), onTimeout: () {
          throw TimeoutException('Second verification timed out');
        });
        final secondResult = secondResponse.text ?? '';

        if (secondResult.contains('CONFIRMED_NOT_PRODUCE') ||
            !secondResult.contains('PRODUCE_DETECTED')) {
          debugPrint('Second validation confirmed non-produce image');
          return 'NOT_PRODUCE: No fruits or vegetables detected in image. The app only works with fruits and vegetables.';
        } else if (secondResult.contains('PRODUCE_DETECTED')) {
          debugPrint(
              'Second validation found potential produce - proceeding with analysis');
          // Extract what it might be for better error handling
          final detectedMatch =
              RegExp(r'PRODUCE_DETECTED:?\s*(.*?)(?:\.|$)', dotAll: true)
                  .firstMatch(secondResult);
          final potentialProduce = detectedMatch?.group(1)?.trim() ??
              'something that might be produce';

          // Return a more specific analysis that will be treated as valid produce
          return '''
Type: ${potentialProduce.split(' ').last}
Category: ${potentialProduce.toLowerCase().contains('fruit') ? 'Fruit' : 'Vegetable'}
Approximate Size: 5-10 cm
Color: Mixed
Texture: Unknown
Physical Cues: Partially visible
Unripe Status: Unknown
Surface Condition: Unknown
''';
        }
      }

      // Special handling for low quality images - be more lenient
      if (result.contains('LOW_QUALITY:')) {
        debugPrint('Gemini detected low quality image - attempting recovery');

        // Try to extract any hints of produce type from the response
        final String lowerResult = result.toLowerCase();
        final List<String> commonProduce = [
          'apple',
          'banana',
          'orange',
          'mango',
          'papaya',
          'tomato',
          'potato',
          'carrot',
          'lettuce',
          'cucumber',
          'pepper',
          'eggplant',
          'broccoli'
        ];

        String detectedType = 'Unknown';
        for (final type in commonProduce) {
          if (lowerResult.contains(type)) {
            detectedType =
                type.substring(0, 1).toUpperCase() + type.substring(1);
            break;
          }
        }

        if (detectedType != 'Unknown') {
          debugPrint(
              'Recovered potential produce type from low quality image: $detectedType');
          return '''
Type: $detectedType
Category: ${[
            'apple',
            'banana',
            'orange',
            'mango',
            'papaya'
          ].contains(detectedType.toLowerCase()) ? 'Fruit' : 'Vegetable'}
Approximate Size: 5-10 cm
Color: Mixed
Texture: Unknown
Physical Cues: Unclear from image
Unripe Status: Unknown
Surface Condition: Unknown
''';
        }

        return 'LOW_QUALITY: Image quality is too poor for reliable analysis. Please try again with a clearer photo.';
      }

      // More lenient format validation - check if it contains at least one key field
      if (!result.toLowerCase().contains('type:') &&
          !result.toLowerCase().contains('category:') &&
          result.length < 30) {
        debugPrint(
            'Response does not match any expected produce fields - performing recovery check');

        // Check for common words that indicate produce is present but format was wrong
        final String lowerResult = result.toLowerCase();
        final bool containsProduceTerms = lowerResult.contains('fruit') ||
            lowerResult.contains('vegetable') ||
            lowerResult.contains('produce') ||
            lowerResult.contains('food') ||
            lowerResult.contains('ripe');

        if (containsProduceTerms) {
          debugPrint(
              'Found produce terms in non-formatted response - attempting to extract info');

          // Extract possible type
          String possibleType = 'Unknown';
          final List<String> commonProduce = [
            'apple',
            'banana',
            'orange',
            'mango',
            'papaya',
            'tomato',
            'potato',
            'carrot',
            'lettuce',
            'cucumber',
            'pepper',
            'eggplant',
            'broccoli'
          ];

          for (final type in commonProduce) {
            if (lowerResult.contains(type)) {
              possibleType =
                  type.substring(0, 1).toUpperCase() + type.substring(1);
              break;
            }
          }

          // Extract category
          final String category =
              lowerResult.contains('fruit') ? 'Fruit' : 'Vegetable';

          // Return a formatted response
          return '''
Type: $possibleType
Category: $category
Approximate Size: Unknown
Color: Unknown
Texture: Unknown
Physical Cues: Unknown
Unripe Status: Unknown
Surface Condition: Unknown
''';
        }

        return 'NOT_PRODUCE: Unable to identify any fruit or vegetable in this image. Please ensure the image clearly shows a fruit or vegetable.';
      }

      // NEW: Validate and clean up the response format
      final String cleanedResponse = _validateAndCleanResponse(result);
      return cleanedResponse;
    } catch (e) {
      _failedRequests++;
      debugPrint('Error in analyzeImage: $e');
      return 'Error: $e';
    }
  }

  // Add a method to use the backup model
  Future<String> analyzeImageWithBackupModel(String imagePath) async {
    try {
      _totalRequests++;
      debugPrint(
          'GeminiService: Starting backup image analysis with gemini-2.0-flash...');
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        _failedRequests++;
        return 'Error: Image file not found';
      }

      // NEW: Preprocess the image for better analysis
      final File processedImageFile = await _preprocessImage(imageFile);
      final imageBytes = await processedImageFile.readAsBytes();

      final img.Image? decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        _failedRequests++;
        return 'Error: Unable to decode image';
      }

      // Resize image if needed to avoid token limits
      img.Image processedImage = decodedImage;
      if (decodedImage.width > 1024 || decodedImage.height > 1024) {
        processedImage = img.copyResize(
          decodedImage,
          width: decodedImage.width > decodedImage.height ? 1024 : null,
          height: decodedImage.height >= decodedImage.width ? 1024 : null,
        );
      }

      // Re-encode as JPEG with quality 85
      final encodedBytes = img.encodeJpg(processedImage, quality: 85);
      debugPrint(
          'GeminiService: Processed image size: ${encodedBytes.length} bytes');

      // Enhanced prompt for ripeness analysis with specific days until harvest request
      final promptText = '''
Analyze this fruit or vegetable and determine if it's ready for harvest.

IMPORTANT: Be extremely detailed in your analysis. Examine the following aspects:
1. Color - Is it the appropriate color for a ripe specimen? Note any color patterns, gradients, or variations.
2. Texture - Does it appear to have the right firmness/softness for optimal harvest?
3. Surface condition - Look for glossiness, dullness, blemishes, or other surface indicators of ripeness.
4. Size - Is it fully grown or still developing?
5. Other visual cues - Note any distinctive features that indicate ripeness level.

Your task is to determine if this produce is READY FOR HARVEST, OVERRIPE, or NOT READY.

Please provide your analysis with this EXACT format:
1. Harvest Status: [ONLY answer "Ready", "Overripe", or "Not Ready"]
2. Confidence: [High/Medium/Low]
3. Analysis: [Provide detailed explanation with specific observations about color, texture, and physical appearance]
4. Estimated Days Until Optimal Harvest: [IMPORTANT: If not ready, provide a SPECIFIC number of days until harvest based on current ripeness state. If ready or overripe, put "0"]

If you can't clearly identify the produce, analyze what you can see.
''';

      // Create image part and content
      final imagePart = DataPart('image/jpeg', encodedBytes);
      final content = [
        Content.multi([
          TextPart(promptText),
          imagePart,
        ])
      ];

      // Try with backup model
      debugPrint('GeminiService: Using backup model with different parameters');
      final response = await _backupModel
          .generateContent(content)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Backup model API timeout after 30 seconds');
      });

      final responseText = response.text;
      if (responseText == null || responseText.isEmpty) {
        _failedRequests++;
        return 'Error: Empty response from backup model';
      }

      _successfulRequests++;
      debugPrint('GeminiService: Backup model analysis successful');

      // Validate and clean the response
      return _validateAndCleanResponse(responseText);
    } catch (e) {
      _failedRequests++;
      debugPrint('Error in analyzeImageWithBackupModel: $e');
      return 'Error analyzing image with backup model: ${e.toString()}';
    }
  }

  // NEW: Get analytics about the service usage
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

  // Enhanced image preprocessing to improve analysis quality
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
      // Apply color adjustments to make produce features more visible
      processedImage = img.adjustColor(
        processedImage,
        saturation: 1.3, // Increased saturation for more vivid produce colors
        contrast: 1.2, // Better contrast to distinguish produce features
        brightness:
            1.05, // Slightly brighter to reveal details in darker images
      );

      // Apply adaptive histogram equalization for better feature detection
      processedImage = img.adjustColor(
        processedImage,
        gamma: 1.1, // Slightly adjust gamma for better midtones
      );

      // Enhance contrast further to improve edge definition (instead of sharpening)
      processedImage = img.adjustColor(
        processedImage,
        contrast: 1.3, // Higher contrast to enhance edges
      );

      // Create a temporary file for the processed image
      final Directory tempDir =
          Directory.systemTemp.createTempSync('produce_analysis');
      final String tempPath =
          '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File processedFile = File(tempPath);

      // Save with high quality to preserve details
      await processedFile
          .writeAsBytes(img.encodeJpg(processedImage, quality: 98));

      debugPrint(
          'Image preprocessed: Original size: ${originalImage.width}x${originalImage.height}, '
          'New size: ${processedImage.width}x${processedImage.height}');

      return processedFile;
    } catch (e) {
      debugPrint('Image preprocessing failed: $e');
      return imageFile; // Return original on any error
    }
  }

  // NEW: Validate and clean up AI response format
  String _validateAndCleanResponse(String response) {
    // Check if response is empty or too short
    if (response.isEmpty || response.length < 10) {
      return 'Error: Empty or too short response';
    }

    // Check for specific format fields if this is a produce analysis
    if (response.contains('Type:') || response.contains('Category:')) {
      // Make sure all required fields are present
      final requiredFields = ['Type:', 'Category:', 'Color:', 'Texture:'];
      final missingFields =
          requiredFields.where((field) => !response.contains(field)).toList();

      if (missingFields.isNotEmpty) {
        // Try to fix missing fields
        String fixedResponse = response;

        for (final field in missingFields) {
          // Add placeholders for missing fields
          if (!fixedResponse.contains(field)) {
            fixedResponse += '\n$field Unknown';
          }
        }

        // Ensure Unripe Status field is present
        if (!fixedResponse.contains('Unripe Status:')) {
          fixedResponse += '\nUnripe Status: Unknown';
        }

        // Ensure Surface Condition field is present
        if (!fixedResponse.contains('Surface Condition:')) {
          fixedResponse += '\nSurface Condition: Unknown';
        }

        return fixedResponse;
      }
    }
    // For harvest readiness analysis
    else if (response.contains('Harvest Status:') ||
        response.contains('Ready for Harvest:')) {
      // Standardize the format for consistency
      String standardized = response;

      // Ensure "Harvest Status" is the standard field name
      if (response.contains('Ready for Harvest:') &&
          !response.contains('Harvest Status:')) {
        // Find the value from Ready for Harvest
        final harvestMatch = RegExp(r'Ready for Harvest:\s*(Yes|No|yes|no)',
                caseSensitive: false)
            .firstMatch(standardized);
        if (harvestMatch != null && harvestMatch.groupCount >= 1) {
          final value = harvestMatch.group(1)?.toLowerCase() ?? 'no';
          final status = value == 'yes' ? 'Ready' : 'Not Ready';

          // Replace the text directly
          standardized = standardized.replaceFirst(
              'Ready for Harvest:', 'Harvest Status:');

          // Fix the value if needed
          standardized = standardized.replaceFirst(
              RegExp(r'Harvest Status:\s*(Yes|No|yes|no)',
                  caseSensitive: false),
              'Harvest Status: $status');
        }
      }

      // Ensure Confidence field exists
      if (!standardized.contains('Confidence:')) {
        standardized += '\nConfidence: Medium';
      }

      // Ensure Analysis field exists
      if (!standardized.contains('Analysis:')) {
        standardized +=
            '\nAnalysis: Based on visual assessment of the produce.';
      }

      // Ensure Days Until Harvest field exists
      if (!standardized.contains('Days Until') &&
          !standardized.contains('Estimated Days')) {
        // Check if ready or not
        final isReady = standardized.contains('Status: Ready') ||
            standardized.contains('Status: Overripe');
        standardized +=
            '\nEstimated Days Until Optimal Harvest: ${isReady ? '0' : '7'}';
      }

      return standardized;
    }

    // If no specific format is detected, return as is
    return response;
  }
}
