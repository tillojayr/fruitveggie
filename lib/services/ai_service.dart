import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'gemini_service.dart';
import 'llama_service.dart'; // Add import for LlamaService

// Add String extension for capitalize
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class AIService {
  final GeminiService _geminiService = GeminiService();
  final LlamaService _llamaService =
      LlamaService(); // Add LlamaService instance
  bool _isInitialized = false;

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('AI Service: Starting initialization...');
      // Initialize Gemini service
      try {
        debugPrint('AI Service: Initializing Gemini service...');
        await _geminiService.initialize();
        debugPrint('AI Service: Gemini service initialized successfully');
      } catch (geminiError) {
        debugPrint('AI Service: Gemini initialization failed: $geminiError');
        throw Exception('Gemini initialization failed: $geminiError');
      }

      // Initialize Llama service
      try {
        debugPrint('AI Service: Initializing Llama service...');
        await _llamaService.initialize();
        debugPrint('AI Service: Llama service initialized successfully');
      } catch (llamaError) {
        // Don't throw an exception for Llama failure - we can proceed with just Gemini
        debugPrint(
            'AI Service: Llama initialization failed: $llamaError - continuing with Gemini only');
      }

      _isInitialized = true;
      debugPrint('AI Service successfully initialized');
    } catch (e) {
      debugPrint('Error initializing AI Service: $e');
      throw Exception('Failed to initialize AI Service: $e');
    }
  }

  // Analysis using both Gemini and Llama
  Future<Map<String, dynamic>> analyzeHarvestReadiness({
    required File imageFile,
    required String category,
    required String type,
    required dynamic
        size, // Changed from double to dynamic to handle both string and double
    required String texture,
    required String color,
    required String physicalCues,
    Function(Map<String, dynamic>)? progressCallback,
  }) async {
    debugPrint('AI Service: Starting analyzeHarvestReadiness...');
    // Check if initialization is needed
    if (!_isInitialized) {
      debugPrint('AI Service: Not initialized, initializing now...');
      await initialize();
    }

    // Results container
    Map<String, dynamic> results = {
      'success': false,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Initial progress update
      if (progressCallback != null) {
        progressCallback({
          'status': 'Starting analysis',
          'progress': 0.1,
        });
      }

      // Run Gemini analysis with retry mechanism
      debugPrint('Starting Gemini AI analysis for $type ($category)');

      // Update progress
      if (progressCallback != null) {
        progressCallback({
          'status': 'Running initial image analysis with Gemini',
          'progress': 0.3,
        });
      }

      // Enhanced prompt with more specific details and focus on unripe produce detection
      final String geminiPrompt = '''
Analyze this image of a $type ($category) and determine if it's UNRIPE (not ready for harvest yet), and explain why.

Details provided:
- Size: ${size is double ? size.toString() : size} cm
- Texture: $texture
- Color: $color
- Physical cues: $physicalCues

Please provide a thorough analysis of whether this fruit/vegetable is UNRIPE (not ready for harvest), and explain why.
Include specific visual indicators you can see in the image that support your conclusion.

CRITICAL INSTRUCTIONS:
- FIRST and MOST IMPORTANT priority: accurately assess if the produce is UNRIPE based on color, texture, and physical appearance
- Be VERY PRECISE about why you think it's unripe vs. ripe
- For unripe crops, ALWAYS provide estimated days until harvest (be specific)
- For green produce: verify if green color is natural when ripe (like green apple) or indicates unripeness
- For all produce: describe color depth and intensity - is it bright, dull, deep, pale? 
- If the fruit/vegetable shows clear signs of being unripe, classify as "Unripe" with the specific indicators
- Include specific explanations for your days-until-harvest prediction

Format your response with these CLEARLY LABELED sections:
1. Unripe Status: [ONLY answer "Yes" if unripe, "No" if ripe or overripe]
2. Confidence: [High/Medium/Low]
3. Analysis: [Your detailed analysis with SPECIFIC visual indicators]
4. Days Until Harvest: [If unripe, estimate SPECIFIC number of days]

If the fruit is green and should be another color when ripe, it is almost certainly unripe.
If the fruit shows even SLIGHT signs of being unripe, mark as "Yes" for Unripe Status.
If the fruit shows signs of ripeness or excessive softness, bruising, or dark spots beyond optimal ripeness, indicate it as "No" for Unripe Status.
''';

      // Get the image path from the File object
      final String imagePath = imageFile.path;

      // Update progress
      if (progressCallback != null) {
        progressCallback({
          'status': 'Processing image with Gemini',
          'progress': 0.4,
        });
      }

      // Call Gemini with the image path and retry if needed
      String geminiResponse;
      try {
        geminiResponse =
            await _geminiService.analyzeImage(imagePath, geminiPrompt);
        debugPrint('Received Gemini response (${geminiResponse.length} chars)');

        // Validate that the response has sufficient content
        if (geminiResponse.length < 50 || geminiResponse.contains('Error:')) {
          debugPrint(
              'Gemini response too short or contains error, trying backup model');
          throw Exception('Insufficient response from primary model');
        }
      } catch (e) {
        debugPrint('First Gemini attempt failed, trying backup model: $e');

        // Update progress
        if (progressCallback != null) {
          progressCallback({
            'status': 'Trying alternative Gemini analysis',
            'progress': 0.45,
          });
        }

        // Try with backup model
        geminiResponse =
            await _geminiService.analyzeImageWithBackupModel(imagePath);

        // Validate backup response
        if (geminiResponse.length < 50 || geminiResponse.contains('Error:')) {
          debugPrint(
              'Backup model response too short or contains error, using fallback analysis');
          // Create a fallback response based on the provided details
          geminiResponse =
              _generateFallbackAnalysis(type, color, texture, physicalCues);
        }
      }

      // Always store the gemini response for reference
      results['gemini_analysis'] = geminiResponse;
      results['ai_success'] = true;

      // Now run the Llama analysis for comparison and validation
      if (progressCallback != null) {
        progressCallback({
          'status': 'Running secondary analysis with Llama',
          'progress': 0.6,
        });
      }

      // Create a ripeness-specific prompt for Llama
      String llamaResponse;
      try {
        // Use the specialized ripeness analysis method
        llamaResponse = await _llamaService.analyzeRipeness(
          imagePath: imagePath,
          produceType: type,
          category: category,
          color: color,
          texture: texture,
          physicalCues: physicalCues,
        );

        debugPrint('Received Llama response (${llamaResponse.length} chars)');

        // Store the Llama analysis
        results['llama_analysis'] = llamaResponse;
      } catch (e) {
        debugPrint('Llama analysis failed: $e');
        // If Llama fails, we still have Gemini results, so continue
        results['llama_error'] = e.toString();
        llamaResponse = '';
      }

      // Ensure we always have a detailed analysis
      results['detailed_analysis'] = geminiResponse;

      // Update progress
      if (progressCallback != null) {
        progressCallback({
          'status': 'Combining AI analyses',
          'progress': 0.8,
        });
      }

      // Extract a simple yes/no from Gemini's response with improved pattern matching
      bool? geminiPrediction;
      String confidenceLevel = 'Medium';
      int? daysUntilHarvest;

      // Check for unripe status information in the structured format first
      final unripePattern = RegExp(r'Unripe\s*Status\s*:\s*([^:\n]+)(?=\n|$)',
          caseSensitive: false);
      final unripeMatch = unripePattern.firstMatch(geminiResponse);

      if (unripeMatch != null && unripeMatch.group(1) != null) {
        final unripeDesc = unripeMatch.group(1)!.toLowerCase().trim();
        debugPrint('Found unripe indicator: $unripeDesc');

        // Check if explicitly unripe
        if (unripeDesc.contains('yes') ||
            unripeDesc.contains('unripe') ||
            unripeDesc.contains('not ripe') ||
            unripeDesc.contains('not ready') ||
            unripeDesc.contains('immature') ||
            unripeDesc.contains('still growing') ||
            unripeDesc.contains('needs more time')) {
          geminiPrediction = true; // True means unripe
          debugPrint('Detected UNRIPE produce from Unripe Status field');
        }
        // Check if ripe or overripe
        else if (unripeDesc.contains('no') ||
            unripeDesc.contains('ripe') ||
            unripeDesc.contains('ready') ||
            unripeDesc.contains('overripe') ||
            unripeDesc.contains('over-ripe') ||
            unripeDesc.contains('over ripe') ||
            unripeDesc.contains('too ripe') ||
            unripeDesc.contains('past its prime')) {
          geminiPrediction = false; // False means ripe or overripe
          debugPrint(
              'Detected RIPE or OVERRIPE produce from Unripe Status field');
        }
      }

      // If we couldn't determine from the Unripe Status field, look for alternative indicators
      if (geminiPrediction == null) {
        final readyPattern = RegExp(
            r'Harvest\s+Status\s*:\s*(Ready|Overripe|Not Ready)',
            caseSensitive: false);
        final readyMatch = readyPattern.firstMatch(geminiResponse);

        if (readyMatch != null) {
          final answer = readyMatch.group(1)?.toLowerCase() ?? '';
          debugPrint('Found harvest status indicator: $answer');

          // Not Ready means unripe
          if (answer.contains('not ready')) {
            geminiPrediction = true; // True means unripe
            debugPrint('Detected UNRIPE produce');
          } else {
            geminiPrediction = false; // False means ripe or overripe
            debugPrint('Detected RIPE or OVERRIPE produce');
          }
        } else {
          // Fallback patterns if the format isn't exact
          final altReadyPattern = RegExp(
              r'(not ready|unripe|immature|needs more time|ready for harvest|can be harvested|harvest now|overripe|over-ripe|over ripe|past prime|too ripe)',
              caseSensitive: false);
          final altReadyMatch = altReadyPattern.firstMatch(geminiResponse);

          if (altReadyMatch != null) {
            final altAnswer = altReadyMatch.group(0)?.toLowerCase() ?? '';
            debugPrint(
                'Found alternative harvest readiness indicator: $altAnswer');

            // Check for unripe indicators
            if (altAnswer.contains('not ready') ||
                altAnswer.contains('unripe') ||
                altAnswer.contains('immature') ||
                altAnswer.contains('needs more time')) {
              geminiPrediction = true; // True means unripe
              debugPrint('Detected UNRIPE produce from alternative pattern');
            } else {
              geminiPrediction = false; // False means ripe or overripe
              debugPrint(
                  'Detected RIPE or OVERRIPE produce from alternative pattern');
            }
          }
        }
      }

      // Also extract prediction from Llama if available
      bool? llamaPrediction;
      if (llamaResponse.isNotEmpty) {
        final llamaUnripePattern = RegExp(
            r'Unripe\s*Status\s*:\s*([^:\n]+)(?=\n|$)',
            caseSensitive: false);
        final llamaUnripeMatch = llamaUnripePattern.firstMatch(llamaResponse);

        if (llamaUnripeMatch != null && llamaUnripeMatch.group(1) != null) {
          final answer = llamaUnripeMatch.group(1)?.toLowerCase() ?? '';
          debugPrint('Found Llama unripe status indicator: $answer');

          // Check for unripe status
          if (answer.contains('yes') ||
              answer.contains('unripe') ||
              answer.contains('not ripe') ||
              answer.contains('not ready')) {
            llamaPrediction = true; // True means unripe
            debugPrint('Llama detected UNRIPE produce');
          } else {
            llamaPrediction = false; // False means ripe or overripe
            debugPrint('Llama detected RIPE or OVERRIPE produce');
          }
        }

        // If only Llama has a prediction, use it
        if (geminiPrediction == null && llamaPrediction != null) {
          geminiPrediction = llamaPrediction;
          debugPrint('Using Llama prediction as primary prediction');
        }

        // If both models have predictions and they disagree, reconcile based on confidence
        if (geminiPrediction != null &&
            llamaPrediction != null &&
            geminiPrediction != llamaPrediction) {
          // Extract Llama confidence
          String llamaConfidence = 'Medium';
          final llamaConfidencePattern = RegExp(
              r'Confidence\s*:\s*(High|Medium|Low)',
              caseSensitive: false);
          final llamaConfidenceMatch =
              llamaConfidencePattern.firstMatch(llamaResponse);

          if (llamaConfidenceMatch != null &&
              llamaConfidenceMatch.group(1) != null) {
            llamaConfidence = llamaConfidenceMatch.group(1)!;
          }

          // If Llama has higher confidence, use its prediction
          if ((llamaConfidence == 'High' && confidenceLevel != 'High') ||
              (llamaConfidence == 'Medium' && confidenceLevel == 'Low')) {
            geminiPrediction = llamaPrediction;
            confidenceLevel =
                'Medium'; // When models disagree, lower confidence
            debugPrint(
                'Models disagree! Using Llama prediction with reconciled confidence');
          } else {
            // Otherwise still use Gemini but with lower confidence
            confidenceLevel = 'Medium';
            debugPrint(
                'Models disagree! Keeping Gemini prediction with reconciled confidence');
          }

          // Note the disagreement
          results['models_disagree'] = true;
        }
      }

      // Extract confidence level with improved pattern matching
      final confidencePattern = RegExp(
          r'Confidence\s*:\s*(High|Medium|Low|high|medium|low)',
          caseSensitive: false);
      final confidenceMatch = confidencePattern.firstMatch(geminiResponse);

      if (confidenceMatch != null && confidenceMatch.groupCount >= 1) {
        confidenceLevel = confidenceMatch.group(1) ?? 'Medium';
        // Standardize confidence level format to first letter uppercase
        confidenceLevel = confidenceLevel.substring(0, 1).toUpperCase() +
            confidenceLevel.substring(1).toLowerCase();
        debugPrint('Found confidence level: $confidenceLevel');
      } else {
        // Improved confidence inference from language patterns
        final String responseLower = geminiResponse.toLowerCase();

        // Keywords that indicate high confidence
        final bool hasHighConfidenceTerms =
            responseLower.contains('definitely') ||
                responseLower.contains('certainly') ||
                responseLower.contains('clear evidence') ||
                responseLower.contains('no doubt') ||
                responseLower.contains('obvious') ||
                responseLower.contains('clearly') ||
                responseLower.contains('absolutely') ||
                responseLower.contains('perfect example') ||
                responseLower.contains('extremely confident');

        // Keywords that indicate medium confidence
        final bool hasMediumConfidenceTerms =
            responseLower.contains('likely') ||
                responseLower.contains('appears to be') ||
                responseLower.contains('probably') ||
                responseLower.contains('seems') ||
                responseLower.contains('should be') ||
                responseLower.contains('moderately') ||
                responseLower.contains('most likely');

        // Keywords that indicate low confidence
        final bool hasLowConfidenceTerms = responseLower.contains('might') ||
            responseLower.contains('possibly') ||
            responseLower.contains('not sure') ||
            responseLower.contains('unclear') ||
            responseLower.contains('difficult to determine') ||
            responseLower.contains('hard to tell') ||
            responseLower.contains('could be') ||
            responseLower.contains('may be') ||
            responseLower.contains('uncertain');

        // Count confidence indicators
        int highIndicators = hasHighConfidenceTerms ? 1 : 0;
        int mediumIndicators = hasMediumConfidenceTerms ? 1 : 0;
        int lowIndicators = hasLowConfidenceTerms ? 1 : 0;

        // Add image quality assessment as a factor
        if (responseLower.contains('high quality image') ||
            responseLower.contains('clear image') ||
            responseLower.contains('good visibility')) {
          highIndicators++;
        } else if (responseLower.contains('poor quality') ||
            responseLower.contains('blurry') ||
            responseLower.contains('low resolution') ||
            responseLower.contains('difficult to see')) {
          lowIndicators++;
        }

        // Look for explicit confidence statements
        if (responseLower.contains('high confidence') ||
            responseLower.contains('confident that')) {
          highIndicators += 2;
        } else if (responseLower.contains('low confidence') ||
            responseLower.contains('not confident')) {
          lowIndicators += 2;
        }

        // Determine confidence level based on indicators
        if (highIndicators > mediumIndicators &&
            highIndicators > lowIndicators) {
          confidenceLevel = 'High';
          debugPrint('Inferred high confidence from language patterns');
        } else if (lowIndicators > highIndicators &&
            lowIndicators > mediumIndicators) {
          confidenceLevel = 'Low';
          debugPrint('Inferred low confidence from language patterns');
        } else {
          confidenceLevel =
              'Medium'; // Default or when medium has the most indicators
          debugPrint(
              'Inferred medium confidence from language patterns or using default');
        }
      }

      // Extract days until harvest with improved pattern matching
      daysUntilHarvest =
          _extractDaysUntilHarvest(geminiResponse, llamaResponse);

      // Update results
      results['unripe_prediction'] = geminiPrediction;
      results['confidence'] = confidenceLevel;
      results['days_until_harvest'] = daysUntilHarvest;

      // Update progress
      if (progressCallback != null) {
        progressCallback({
          'status': 'Analysis complete',
          'progress': 1.0,
        });
      }

      return results;
    } catch (e) {
      debugPrint('Error during analysis: $e');
      results['error'] = e.toString();
      return results;
    }
  }

  // Helper function to extract days until harvest from AI response
  int? _extractDaysUntilHarvest(String geminiResponse, String llamaResponse) {
    // First try to find explicit days mentioned in a dedicated section in Gemini response
    final RegExp daysSection =
        RegExp(r'Days Until Harvest\s*:\s*(\d+)', caseSensitive: false);
    final daysSectionMatch = daysSection.firstMatch(geminiResponse);

    if (daysSectionMatch != null && daysSectionMatch.group(1) != null) {
      return int.parse(daysSectionMatch.group(1)!);
    }

    // Check for days in Llama response too
    if (llamaResponse.isNotEmpty) {
      final llamaDaysMatch = daysSection.firstMatch(llamaResponse);
      if (llamaDaysMatch != null && llamaDaysMatch.group(1) != null) {
        return int.parse(llamaDaysMatch.group(1)!);
      }
    }

    // Then look for days mentioned anywhere in the text
    final RegExp daysRegex = RegExp(
        r'(\d+)[-\s]*(day|days)[^\.]*until[^\.]*harvest',
        caseSensitive: false);
    final daysMatch = daysRegex.firstMatch(geminiResponse);

    if (daysMatch != null && daysMatch.group(1) != null) {
      return int.parse(daysMatch.group(1)!);
    }

    // Check Llama response for days mentioned
    if (llamaResponse.isNotEmpty) {
      final llamaDaysRegexMatch = daysRegex.firstMatch(llamaResponse);
      if (llamaDaysRegexMatch != null && llamaDaysRegexMatch.group(1) != null) {
        return int.parse(llamaDaysRegexMatch.group(1)!);
      }
    }

    // Look for estimated days in a different format
    final estimatedDaysRegex = RegExp(
        r'Estimated Days Until Optimal Harvest\s*:\s*(\d+)',
        caseSensitive: false);
    final estimatedDaysMatch = estimatedDaysRegex.firstMatch(geminiResponse);

    if (estimatedDaysMatch != null && estimatedDaysMatch.group(1) != null) {
      return int.parse(estimatedDaysMatch.group(1)!);
    }

    // Extract produce type for more accurate estimation
    String produceType =
        _extractProduceType(geminiResponse, llamaResponse).toLowerCase();

    // Extract ripeness indicators
    String combinedText = ('$geminiResponse $llamaResponse').toLowerCase();

    // If produce is ready for harvest, return 0
    if (combinedText.contains('ready for harvest') ||
        combinedText.contains('harvest status: ready') ||
        combinedText.contains('can be harvested now') ||
        combinedText.contains('optimal ripeness') ||
        combinedText.contains('harvest now') ||
        combinedText.contains('fully ripe')) {
      return 0;
    }

    // If produce is overripe, return -1 (past harvest date)
    if (combinedText.contains('overripe') ||
        combinedText.contains('over-ripe') ||
        combinedText.contains('over ripe') ||
        combinedText.contains('too ripe') ||
        combinedText.contains('past its prime')) {
      return -1;
    }

    // Check for specific ripeness indicators
    bool isVeryUnripe = combinedText.contains('very unripe') ||
        combinedText.contains('completely unripe') ||
        combinedText.contains('far from ready') ||
        combinedText.contains('early stage') ||
        combinedText.contains('weeks away') ||
        combinedText.contains('not close to');

    bool isNearlyReady = combinedText.contains('almost ripe') ||
        combinedText.contains('nearly ready') ||
        combinedText.contains('close to harvest') ||
        combinedText.contains('approaching readiness') ||
        combinedText.contains('few days') ||
        combinedText.contains('soon be ready');

    bool isModeratelyRipe = combinedText.contains('moderately ripe') ||
        combinedText.contains('developing') ||
        combinedText.contains('progressing') ||
        combinedText.contains('mid-stage') ||
        combinedText.contains('continue to ripen');

    // If unripe, estimate based on produce type and ripeness indicators
    if (combinedText.contains('not ready') ||
        combinedText.contains('unripe') ||
        combinedText.contains('immature') ||
        isVeryUnripe ||
        isNearlyReady ||
        isModeratelyRipe) {
      // Very fast ripening produce (3-5 days)
      if (produceType.contains('strawberry') ||
          produceType.contains('raspberry') ||
          produceType.contains('blackberry') ||
          produceType.contains('blueberry') ||
          produceType.contains('cherry') ||
          produceType.contains('fig')) {
        return isNearlyReady
            ? 2
            : isModeratelyRipe
                ? 3
                : 4;
      }

      // Fast-ripening produce (5-10 days)
      if (produceType.contains('tomato') ||
          produceType.contains('banana') ||
          produceType.contains('peach') ||
          produceType.contains('plum') ||
          produceType.contains('apricot') ||
          produceType.contains('avocado') ||
          produceType.contains('mango') ||
          produceType.contains('papaya') ||
          produceType.contains('leafy') ||
          produceType.contains('lettuce') ||
          produceType.contains('spinach') ||
          produceType.contains('kale')) {
        return isNearlyReady
            ? 3
            : isModeratelyRipe
                ? 5
                : isVeryUnripe
                    ? 10
                    : 7;
      }

      // Medium-ripening produce (10-20 days)
      if (produceType.contains('pepper') ||
          produceType.contains('cucumber') ||
          produceType.contains('zucchini') ||
          produceType.contains('eggplant') ||
          produceType.contains('squash') ||
          produceType.contains('melon') ||
          produceType.contains('grape')) {
        return isNearlyReady
            ? 5
            : isModeratelyRipe
                ? 10
                : isVeryUnripe
                    ? 18
                    : 14;
      }

      // Slow-ripening produce (20+ days)
      if (produceType.contains('apple') ||
          produceType.contains('pear') ||
          produceType.contains('citrus') ||
          produceType.contains('orange') ||
          produceType.contains('lemon') ||
          produceType.contains('lime') ||
          produceType.contains('grapefruit') ||
          produceType.contains('root') ||
          produceType.contains('potato') ||
          produceType.contains('carrot') ||
          produceType.contains('beet') ||
          produceType.contains('radish') ||
          produceType.contains('onion') ||
          produceType.contains('garlic') ||
          produceType.contains('pumpkin') ||
          produceType.contains('winter squash')) {
        return isNearlyReady
            ? 7
            : isModeratelyRipe
                ? 14
                : isVeryUnripe
                    ? 28
                    : 21;
      }

      // Default based on ripeness indicators
      return isNearlyReady
          ? 3
          : isModeratelyRipe
              ? 7
              : isVeryUnripe
                  ? 14
                  : 7;
    }

    // If we couldn't determine, return null
    return null;
  }

  // Helper method to extract produce type from AI responses with improved real-time accuracy
  String _extractProduceType(String geminiResponse, String llamaResponse) {
    // Try to extract from Type: field
    final typeRegex = RegExp(r'Type\s*:\s*([^\n]+)', caseSensitive: false);
    final geminiTypeMatch = typeRegex.firstMatch(geminiResponse);
    final llamaTypeMatch =
        llamaResponse.isNotEmpty ? typeRegex.firstMatch(llamaResponse) : null;

    String extractedType = '';

    // First try to get type from Gemini (usually more accurate)
    if (geminiTypeMatch != null && geminiTypeMatch.group(1) != null) {
      extractedType = geminiTypeMatch.group(1)!.trim();
      debugPrint('Extracted produce type from Gemini: $extractedType');
    }
    // Then try Llama if Gemini didn't provide a type
    else if (llamaTypeMatch != null && llamaTypeMatch.group(1) != null) {
      extractedType = llamaTypeMatch.group(1)!.trim();
      debugPrint('Extracted produce type from Llama: $extractedType');
    }

    // If we found a type, normalize it
    if (extractedType.isNotEmpty) {
      // Remove any qualifiers or descriptors
      final normalizedType = _normalizeProduceType(extractedType);
      debugPrint('Normalized produce type: $normalizedType');
      return normalizedType;
    }

    // If no Type field, try to find mentions of common produce
    final commonProduce = [
      'apple',
      'banana',
      'orange',
      'mango',
      'tomato',
      'potato',
      'carrot',
      'avocado',
      'strawberry',
      'blueberry',
      'pepper',
      'cucumber',
      'zucchini',
      'eggplant',
      'lettuce',
      'kale',
      'spinach',
      'grape',
      'melon',
      'watermelon',
      'pear',
      'peach',
      'plum',
      'cherry',
      'papaya',
      'pineapple',
      'kiwi',
      'lemon',
      'lime',
      'grapefruit',
      'broccoli',
      'cauliflower',
      'cabbage',
      'onion',
      'garlic',
      'bell pepper',
      'chili pepper',
      'jalapeño',
      'squash',
      'pumpkin',
      'radish',
      'beet',
      'turnip',
      'sweet potato',
      'cantaloupe',
      'honeydew'
    ];

    String combinedText = ('$geminiResponse $llamaResponse').toLowerCase();

    // First check for exact matches
    for (final produce in commonProduce) {
      // Look for the produce name as a whole word
      final wordBoundaryRegex =
          RegExp(r'\b' + produce + r'\b', caseSensitive: false);
      if (wordBoundaryRegex.hasMatch(combinedText)) {
        debugPrint('Found exact produce match: $produce');
        return produce;
      }
    }

    // Then check for partial matches (for compound names like "bell pepper")
    for (final produce in commonProduce) {
      if (combinedText.contains(produce)) {
        debugPrint('Found partial produce match: $produce');
        return produce;
      }
    }

    // If we still don't have a match, check for category and make a best guess
    if (combinedText.contains('fruit')) {
      // Check for common fruit characteristics
      if (combinedText.contains('citrus')) return 'citrus fruit';
      if (combinedText.contains('berry') || combinedText.contains('berries')) {
        return 'berry';
      }
      return 'fruit';
    } else if (combinedText.contains('vegetable')) {
      // Check for common vegetable characteristics
      if (combinedText.contains('leafy')) return 'leafy vegetable';
      if (combinedText.contains('root')) return 'root vegetable';
      return 'vegetable';
    }

    debugPrint('Could not determine produce type, using unknown');
    return 'unknown';
  }

  // Helper method to normalize produce type names
  String _normalizeProduceType(String rawType) {
    // Convert to lowercase
    String normalized = rawType.toLowerCase();

    // Remove common qualifiers
    final qualifiers = [
      'ripe',
      'unripe',
      'green',
      'fresh',
      'raw',
      'organic',
      'whole',
      'large',
      'small',
      'medium',
      'sized'
    ];

    for (final qualifier in qualifiers) {
      normalized = normalized.replaceAll(qualifier, '').trim();
    }

    // Handle specific varieties and map to generic types
    if (normalized.contains('granny smith') ||
        normalized.contains('fuji') ||
        normalized.contains('gala') ||
        normalized.contains('red delicious')) {
      normalized = 'apple';
    }

    if (normalized.contains('roma') ||
        normalized.contains('cherry tomato') ||
        normalized.contains('beefsteak')) {
      normalized = 'tomato';
    }

    if (normalized.contains('bell pepper') ||
        normalized.contains('sweet pepper')) {
      normalized = 'bell pepper';
    }

    if (normalized.contains('jalapeño') ||
        normalized.contains('jalapeno') ||
        normalized.contains('chili') ||
        normalized.contains('chile')) {
      normalized = 'chili pepper';
    }

    // Remove any remaining punctuation and extra spaces
    normalized = normalized.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }

  // Helper function to generate a fallback analysis
  String _generateFallbackAnalysis(
      String type, String color, String texture, String physicalCues) {
    final String fallbackAnalysis = '''
Fallback analysis for $type:
- Color: $color
- Texture: $texture
- Physical cues: $physicalCues

This is a fallback analysis because the primary AI model failed to provide a sufficient response.
The analysis is based on the provided details and the ripeness rules for this produce type.

Harvest Status: Not Ready
Confidence: Low
Analysis: Fallback analysis based on provided details and ripeness rules
Days Until Harvest: 7 (default)
''';
    return fallbackAnalysis;
  }

  // New method for automatic produce detection and analysis using both models
  Future<Map<String, dynamic>> analyzeProduceAutomatically({
    required File imageFile,
    Function(Map<String, dynamic>)? progressCallback,
  }) async {
    // Check if initialization is needed
    if (!_isInitialized) {
      await initialize();
    }

    // Results container
    Map<String, dynamic> results = {
      'success': false,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Initial progress update
      if (progressCallback != null) {
        progressCallback({
          'status': 'Starting automatic produce analysis',
          'progress': 0.1,
        });
      }

      // Get the image path
      final String imagePath = imageFile.path;

      // Update progress
      if (progressCallback != null) {
        progressCallback({
          'status': 'Processing image for analysis',
          'progress': 0.2,
        });
      }

      // Run multiple analyses in parallel for better performance
      final geminiPrompt = '''
Analyze this image and identify the specific fruit or vegetable shown.

IMPORTANT: As your FIRST priority, carefully assess if this is actually an image of a fruit or vegetable.
If the image does NOT show any fruit or vegetable (such as an object, animal, person, landscape, etc.), respond EXACTLY with the following format:
"NOT_PRODUCE: This image does not contain fruits or vegetables."

Do NOT analyze any image that isn't clearly a fruit or vegetable. Common non-produce items to reject:
- Animals, people, or body parts
- Furniture, vehicles, or electronics
- Landscapes, buildings, or scenery
- Man-made objects of any kind
- Processed foods (bread, pasta, meals)
- Meat, fish, or poultry
- Flowers or decorative plants

Only if you are CERTAIN the image contains a fruit or vegetable, provide your response in this EXACT format with ALL fields:
Type: [specific fruit/vegetable name - BE PRECISE with the name, avoid generic terms]
Category: [Fruit or Vegetable]
Approximate Size: [estimated size in cm]
Color: [dominant color - be specific about shade and intensity]
Texture: [texture description - firm, soft, smooth, rough, etc.]
Physical Cues: [any visible physical characteristics like spots, bruises, glossiness]
Ripeness: [IMPORTANT: assess if unripe, ripe, or overripe - BE VERY SPECIFIC]
Surface Condition: [smooth, bumpy, glossy, dull, etc.]

Focus particularly on the ripeness assessment - look for these key indicators:
- For green produce: is the green color due to being unripe or is this its natural color when ripe?
- For fruit: check for color development, firmness, and surface quality
- For vegetables: assess size, color intensity, and physical damage
- If you can tell it's unripe, CLEARLY state this in the Ripeness field

THE RIPENESS ASSESSMENT IS THE MOST CRITICAL PART OF YOUR ANALYSIS.
''';

      // Run Gemini analysis with retry mechanism
      String geminiResponse = '';
      try {
        // Update progress
        if (progressCallback != null) {
          progressCallback({
            'status': 'Running primary AI analysis',
            'progress': 0.3,
          });
        }

        geminiResponse =
            await _geminiService.analyzeImage(imagePath, geminiPrompt);

        // Validate response quality
        if (geminiResponse.length < 50 || geminiResponse.contains('Error:')) {
          throw Exception('Insufficient response from primary model');
        }
      } catch (e) {
        debugPrint('First Gemini attempt failed, trying backup model: $e');

        // Update progress
        if (progressCallback != null) {
          progressCallback({
            'status': 'Using backup analysis model',
            'progress': 0.35,
          });
        }

        // Try with backup model with additional retry
        try {
          geminiResponse =
              await _geminiService.analyzeImageWithBackupModel(imagePath);

          if (geminiResponse.length < 50 || geminiResponse.contains('Error:')) {
            throw Exception('Backup model response insufficient');
          }
        } catch (secondError) {
          // If both attempts fail, try with a simplified prompt
          debugPrint(
              'Backup model failed, using simplified prompt: $secondError');

          final simplifiedPrompt = '''
What fruit or vegetable is shown in this image? 
Is it ripe, unripe, or overripe? 
Provide details about its color, texture, and condition.
''';

          try {
            geminiResponse =
                await _geminiService.analyzeImage(imagePath, simplifiedPrompt);
          } catch (finalError) {
            debugPrint('All Gemini attempts failed: $finalError');
            geminiResponse =
                'Error: Unable to analyze image after multiple attempts';
          }
        }
      }

      // Store the Gemini response
      results['gemini_analysis'] = geminiResponse;

      // Run parallel Llama analysis for validation
      String llamaResponse = '';
      try {
        // Update progress
        if (progressCallback != null) {
          progressCallback({
            'status': 'Running secondary analysis for verification',
            'progress': 0.5,
          });
        }

        llamaResponse = await _llamaService.analyzeImage(imagePath);
        results['llama_analysis'] = llamaResponse;
      } catch (e) {
        debugPrint('Llama analysis failed: $e');
        results['llama_error'] = e.toString();
      }

      // Extract and reconcile results from both models
      if (progressCallback != null) {
        progressCallback({
          'status': 'Combining analysis results',
          'progress': 0.7,
        });
      }

      // Parse Gemini response to extract structured data
      final Map<String, String> geminiFields =
          _extractStructuredFields(geminiResponse);

      // Parse Llama response if available
      final Map<String, String> llamaFields = llamaResponse.isNotEmpty
          ? _extractStructuredFields(llamaResponse)
          : {};

      // Combine and reconcile results with preference to Gemini but validation from Llama
      final String detectedType =
          _reconcileProduceType(geminiFields['Type'], llamaFields['Type']);

      final String detectedCategory = _reconcileProduceCategory(
          geminiFields['Category'], llamaFields['Category']);

      // Extract ripeness status with high accuracy
      final String ripeness =
          _extractRipenessStatus(geminiResponse, llamaResponse);

      // Determine if produce is ready for harvest
      final bool isReadyForHarvest =
          _determineHarvestReadiness(ripeness, geminiResponse, llamaResponse);

      // Extract days until harvest for unripe produce
      int? daysUntilHarvest =
          _extractDaysUntilHarvest(geminiResponse, llamaResponse);

      // Check for non-produce images in either response
      if (geminiResponse.contains('NOT_PRODUCE') ||
          llamaResponse.contains('NOT_PRODUCE') ||
          (detectedType.isEmpty || detectedType.toLowerCase() == 'unknown')) {
        debugPrint('AI detected non-produce image: NOT_PRODUCE response found');

        results['not_produce'] = true;
        results['error'] =
            'This image does not contain any fruits or vegetables. Please try an image of a fruit or vegetable.';
        results['success'] = false;

        return results;
      }

      // Populate the results
      results['detected_type'] = detectedType;
      results['detected_category'] = detectedCategory;
      results['ripeness_status'] = ripeness;
      results['ready_for_harvest'] = isReadyForHarvest;
      results['confidence_level'] =
          _determineConfidenceLevel(geminiResponse, llamaResponse);

      if (daysUntilHarvest != null) {
        results['days_until_harvest'] = daysUntilHarvest;
      }

      // Add detailed analysis
      results['detailed_analysis'] = _generateDetailedAnalysis(
          detectedType, ripeness, geminiFields, llamaFields);

      // Mark as successful
      results['success'] = true;

      return results;
    } catch (e) {
      debugPrint('Error in analyzeProduceAutomatically: $e');
      results['error'] = e.toString();
      return results;
    }
  }

  // Helper method to extract structured fields from AI responses
  Map<String, String> _extractStructuredFields(String response) {
    final Map<String, String> fields = {};
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
      'Days Until Harvest:',
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
        fields[field.replaceAll(':', '')] = value;
      }
    }

    return fields;
  }

  // Improved method to extract ripeness status with higher accuracy
  String _extractRipenessStatus(String geminiResponse, String llamaResponse) {
    // First check for explicit Harvest Status field
    final harvestStatusRegex = RegExp(
        r'Harvest\s+Status\s*:\s*(Ready|Overripe|Not Ready)',
        caseSensitive: false);

    final geminiMatch = harvestStatusRegex.firstMatch(geminiResponse);
    final llamaMatch = llamaResponse.isNotEmpty
        ? harvestStatusRegex.firstMatch(llamaResponse)
        : null;

    if (geminiMatch != null) {
      return geminiMatch.group(1)?.trim() ?? 'Unknown';
    }

    if (llamaMatch != null) {
      return llamaMatch.group(1)?.trim() ?? 'Unknown';
    }

    // Check for Ripeness field
    final ripenessRegex =
        RegExp(r'Ripeness\s*:\s*([^:\n]+)(?=\n|$)', caseSensitive: false);

    final geminiRipenessMatch = ripenessRegex.firstMatch(geminiResponse);

    if (geminiRipenessMatch != null && geminiRipenessMatch.group(1) != null) {
      final ripenessDesc = geminiRipenessMatch.group(1)!.toLowerCase().trim();

      if (ripenessDesc.contains('unripe') ||
          ripenessDesc.contains('not ripe') ||
          ripenessDesc.contains('not ready') ||
          ripenessDesc.contains('immature')) {
        return 'Not Ready';
      } else if (ripenessDesc.contains('overripe') ||
          ripenessDesc.contains('over-ripe') ||
          ripenessDesc.contains('over ripe') ||
          ripenessDesc.contains('too ripe')) {
        return 'Overripe';
      } else if (ripenessDesc.contains('ripe') ||
          ripenessDesc.contains('ready') ||
          ripenessDesc.contains('mature')) {
        return 'Ready';
      }
    }

    // Fallback to general text analysis
    final String combinedText =
        '${geminiResponse.toLowerCase()} ${llamaResponse.toLowerCase()}';

    if (combinedText.contains('not ready for harvest') ||
        combinedText.contains('not ready to harvest') ||
        combinedText.contains('unripe') ||
        combinedText.contains('immature')) {
      return 'Not Ready';
    } else if (combinedText.contains('overripe') ||
        combinedText.contains('over-ripe') ||
        combinedText.contains('past its prime')) {
      return 'Overripe';
    } else if (combinedText.contains('ready for harvest') ||
        combinedText.contains('ripe') ||
        combinedText.contains('can be harvested')) {
      return 'Ready';
    }

    return 'Unknown';
  }

  // Determine confidence level based on model agreement
  String _determineConfidenceLevel(
      String geminiResponse, String llamaResponse) {
    // Extract confidence from responses
    final confidenceRegex =
        RegExp(r'Confidence\s*:\s*(High|Medium|Low)', caseSensitive: false);

    final geminiMatch = confidenceRegex.firstMatch(geminiResponse);
    final llamaMatch = llamaResponse.isNotEmpty
        ? confidenceRegex.firstMatch(llamaResponse)
        : null;

    // If both models provide confidence and they agree, use that
    if (geminiMatch != null && llamaMatch != null) {
      final geminiConfidence = geminiMatch.group(1)?.trim().toLowerCase() ?? '';
      final llamaConfidence = llamaMatch.group(1)?.trim().toLowerCase() ?? '';

      if (geminiConfidence == llamaConfidence) {
        return geminiConfidence.capitalize();
      }

      // If they disagree, use the lower confidence
      if (geminiConfidence == 'low' || llamaConfidence == 'low') {
        return 'Low';
      } else if (geminiConfidence == 'medium' || llamaConfidence == 'medium') {
        return 'Medium';
      }
    }

    // If only one model provides confidence, use that
    if (geminiMatch != null) {
      return geminiMatch.group(1)?.trim() ?? 'Medium';
    }

    if (llamaMatch != null) {
      return llamaMatch.group(1)?.trim() ?? 'Medium';
    }

    // Default confidence level
    return 'Medium';
  }

  // Helper method to determine if produce is ready for harvest
  bool _determineHarvestReadiness(
      String ripeness, String geminiResponse, String llamaResponse) {
    final String lowerRipeness = ripeness.toLowerCase();
    final String lowerGemini = geminiResponse.toLowerCase();
    final String lowerLlama = llamaResponse.toLowerCase();

    // Check explicit ripeness status first
    if (lowerRipeness.contains('ready for harvest') ||
        lowerRipeness.contains('ready to harvest') ||
        lowerRipeness.contains('optimal time') ||
        lowerRipeness.contains('harvest now')) {
      return true;
    }

    if (lowerRipeness.contains('not ready') ||
        lowerRipeness.contains('unripe') ||
        lowerRipeness.contains('needs more time') ||
        lowerRipeness.contains('too early')) {
      return false;
    }

    // Check Gemini response for harvest indicators
    bool geminiReady = lowerGemini.contains('ready for harvest') ||
        lowerGemini.contains('ready to harvest') ||
        lowerGemini.contains('optimal time') ||
        lowerGemini.contains('harvest now');

    bool geminiNotReady = lowerGemini.contains('not ready') ||
        lowerGemini.contains('unripe') ||
        lowerGemini.contains('needs more time') ||
        lowerGemini.contains('too early');

    // Check Llama response for harvest indicators
    bool llamaReady = lowerLlama.contains('ready for harvest') ||
        lowerLlama.contains('ready to harvest') ||
        lowerLlama.contains('optimal time') ||
        lowerLlama.contains('harvest now');

    bool llamaNotReady = lowerLlama.contains('not ready') ||
        lowerLlama.contains('unripe') ||
        lowerLlama.contains('needs more time') ||
        lowerLlama.contains('too early');

    // If both models agree, use their consensus
    if (geminiReady && llamaReady) return true;
    if (geminiNotReady && llamaNotReady) return false;

    // If models disagree or are unclear, be conservative and return false
    return false;
  }

  // Clean up resources when the service is no longer needed
  Future<void> dispose() async {
    try {
      debugPrint('AI Service: Disposing resources...');
      // Dispose both services
      // Note: Neither service has an explicit dispose method,
      // but we include this for future maintenance
      debugPrint('AI Service: Resources disposed successfully');
    } catch (e) {
      debugPrint('Error disposing AI Service: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    if (!_isInitialized) {
      await initialize();
    }

    final results = {
      'success': false,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Use Gemini for initial image analysis
      final String imagePath = imageFile.path;
      final String prompt = '''
Analyze this image and tell me what fruit or vegetable it is.
Provide your response in this format:
Type: [fruit/vegetable name]
Category: [Fruit/Vegetable]
''';

      final String geminiResponse =
          await _geminiService.analyzeImage(imagePath, prompt);
      results['gemini_analysis'] = geminiResponse;

      // Also use Llama for analysis and comparison
      final String llamaResponse = await _llamaService.analyzeImage(imagePath);
      results['llama_analysis'] = llamaResponse;

      // Extract produce details from both responses
      final Map<String, String> geminiDetails =
          _extractProduceDetails(geminiResponse);
      final Map<String, String> llamaDetails =
          _extractProduceDetails(llamaResponse);

      // Combine the results - if they agree, we have higher confidence
      final String detectedType =
          _reconcileProduceType(geminiDetails['Type'], llamaDetails['Type']);
      final String detectedCategory = _reconcileProduceCategory(
          geminiDetails['Category'], llamaDetails['Category']);

      results['detected_type'] = detectedType;
      results['detected_category'] = detectedCategory;
      results['confidence'] = _calculateConfidence(geminiDetails, llamaDetails);
      results['success'] = true;

      return results;
    } catch (e) {
      debugPrint('Error analyzing image: $e');
      results['error'] = e.toString();
      return results;
    }
  }

  // New helper method to reconcile produce type from multiple AI models
  String _reconcileProduceType(String? geminiType, String? llamaType) {
    // If both identified the same type, we have high confidence
    if (geminiType != null &&
        llamaType != null &&
        geminiType.toLowerCase() == llamaType.toLowerCase() &&
        geminiType.toLowerCase() != "unknown") {
      return geminiType;
    }

    // If only one model identified a type, use that
    if (geminiType != null && geminiType.toLowerCase() != "unknown") {
      return geminiType;
    }

    if (llamaType != null && llamaType.toLowerCase() != "unknown") {
      return llamaType;
    }

    // Default fallback
    return "Unknown";
  }

  // New helper method to reconcile produce category
  String _reconcileProduceCategory(
      String? geminiCategory, String? llamaCategory) {
    // If both identified the same category, we have high confidence
    if (geminiCategory != null &&
        llamaCategory != null &&
        geminiCategory.toLowerCase() == llamaCategory.toLowerCase() &&
        geminiCategory.toLowerCase() != "unknown") {
      return geminiCategory;
    }

    // If only one model identified a category, use that
    if (geminiCategory != null && geminiCategory.toLowerCase() != "unknown") {
      return geminiCategory;
    }

    if (llamaCategory != null && llamaCategory.toLowerCase() != "unknown") {
      return llamaCategory;
    }

    // Default fallback
    return "Unknown";
  }

  // New helper method to calculate confidence based on model agreement
  double _calculateConfidence(
      Map<String, String> geminiDetails, Map<String, String> llamaDetails) {
    double confidence = 0.5; // Base confidence

    // If both models agreed on type, increase confidence
    if (geminiDetails['Type'] != null &&
        llamaDetails['Type'] != null &&
        geminiDetails['Type']!.toLowerCase() ==
            llamaDetails['Type']!.toLowerCase() &&
        geminiDetails['Type']!.toLowerCase() != "unknown") {
      confidence += 0.3;
    }

    // If both models agreed on category, increase confidence
    if (geminiDetails['Category'] != null &&
        llamaDetails['Category'] != null &&
        geminiDetails['Category']!.toLowerCase() ==
            llamaDetails['Category']!.toLowerCase() &&
        geminiDetails['Category']!.toLowerCase() != "unknown") {
      confidence += 0.2;
    }

    return confidence.clamp(0.0, 1.0);
  }

  // Helper method to generate detailed result message for overripe produce
  String _generateDetailedAnalysis(String detectedType, String ripeness,
      Map<String, String> geminiFields, Map<String, String> llamaFields) {
    // Start with a base analysis
    final StringBuffer analysis = StringBuffer();

    // Add type and category
    analysis.writeln('Type: $detectedType');

    // Add category if available
    final String category =
        geminiFields['Category'] ?? llamaFields['Category'] ?? 'Unknown';
    analysis.writeln('Category: $category');

    // Add color information
    final String color =
        geminiFields['Color'] ?? llamaFields['Color'] ?? 'Unknown';
    analysis.writeln('Color: $color');

    // Add texture information
    final String texture =
        geminiFields['Texture'] ?? llamaFields['Texture'] ?? 'Unknown';
    analysis.writeln('Texture: $texture');

    // Add physical cues
    final String physicalCues = geminiFields['Physical Cues'] ??
        llamaFields['Physical Cues'] ??
        'Unknown';
    analysis.writeln('Physical Cues: $physicalCues');

    // Add surface condition
    final String surface = geminiFields['Surface Condition'] ??
        llamaFields['Surface Condition'] ??
        'Unknown';
    analysis.writeln('Surface Condition: $surface');

    // Add harvest status
    analysis.writeln('Harvest Status: $ripeness');

    // Add detailed analysis if available
    String detailedAnalysis = '';
    if (geminiFields.containsKey('Analysis')) {
      detailedAnalysis = geminiFields['Analysis'] ?? '';
    } else if (llamaFields.containsKey('Analysis')) {
      detailedAnalysis = llamaFields['Analysis'] ?? '';
    }

    if (detailedAnalysis.isNotEmpty) {
      analysis.writeln('\nAnalysis: $detailedAnalysis');
    }

    return analysis.toString();
  }

  // New method for special handling of difficult-to-analyze produce types

  // Helper method to extract produce details from AI response
  Map<String, String> _extractProduceDetails(String response) {
    final Map<String, String> details = {
      'Type': 'Unknown',
      'Category': 'Unknown',
      'Approximate Size': '5 cm',
      'Color': 'Unknown',
      'Texture': 'Unknown',
      'Physical Cues': '',
      'Ripeness': 'Unknown',
      'Surface Condition': 'Unknown'
    };

    // Check if this is a non-produce response
    if (response.contains('NOT_PRODUCE') ||
        response.contains('This image does not contain fruits or vegetables')) {
      details['Type'] = 'Not Produce';
      details['Category'] = 'Not Produce';
      return details;
    }

    // List of fields to extract
    final fields = [
      'Type',
      'Category',
      'Approximate Size',
      'Color',
      'Texture',
      'Physical Cues',
      'Ripeness',
      'Surface Condition'
    ];

    // Extract each field from the response
    for (final field in fields) {
      final RegExp fieldRegex = RegExp(
        '$field\\s*:\\s*([^\\n]+)',
        caseSensitive: false,
      );
      final match = fieldRegex.firstMatch(response);
      if (match != null && match.groupCount >= 1) {
        final value = match.group(1)?.trim();
        if (value != null &&
            value.isNotEmpty &&
            value.toLowerCase() != 'unknown') {
          details[field] = value;
        }
      }
    }

    return details;
  }
}
