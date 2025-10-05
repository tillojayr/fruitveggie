import 'package:flutter/material.dart';
import 'package:fruitveggie/services/sms_service.dart';
import 'dart:io';
import 'dart:async'; // Add import for TimeoutException
import 'dart:math' show pi, sin; // Add import for pi and sin functions
import 'dart:convert'; // For base64Encode
import '../services/image_analysis_service.dart'; // Image analysis service import
import '../utils/app_theme.dart'; // Corrected import
import '../widgets/analysis_animation.dart'; // Import our custom analysis animation
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ResultPage extends StatefulWidget {
  final String imagePath;
  // Make all parameters optional since we'll use automatic detection
  final String? category;
  final String? type;
  final dynamic
      size; // Changed from double? to dynamic to handle both string and double
  final String? texture;
  final String? color;
  final String? physicalCues;
  final bool useAutoDetection;
  final VoidCallback? onDataSaved; // Add callback for when data is saved

  const ResultPage({
    super.key,
    required this.imagePath,
    this.category,
    this.type,
    this.size,
    this.texture,
    this.color,
    this.physicalCues,
    this.useAutoDetection = true, // Default to automatic detection
    this.onDataSaved, // Add the callback parameter
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> with TickerProviderStateMixin {
  final ImageAnalysisService _imageAnalysisService =
      ImageAnalysisService(); // Initialize properly
  String _analysisResult = '';
  bool _isAnalyzing = true;
  bool _hasError = false;
  String _errorMessage = '';
  final Map<String, String> _parsedResults = {};
  bool _isGalleryImage = false;
  late AnimationController _animationController;
  late AnimationController _resultsAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isInitialAnalysis = true;
  String _analysisStatus = 'Initializing...';

  // Store detected produce details
  String _detectedType = '';

  // Add a field to store the results for later use
  Map<String, dynamic> _analysisResults = {};

  // Add this variable to the _ResultPageState class
  bool _resultsSaved = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animationController.repeat();

    // Initialize results animation controller
    _resultsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Create fade and slide animations for results
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _resultsAnimationController,
      curve: Curves.easeOutCubic,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resultsAnimationController,
      curve: Curves.easeOutCubic,
    ));

    if (!mounted) return;

    // ImageAnalysisService doesn't need initialization

    // Detect image source
    _detectImageSource();

    // Use a longer delay to allow the UI to render completely first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Add a small delay to ensure UI is fully rendered
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        try {
          _analyzeImage();
        } catch (e) {
          if (!mounted) return;
          debugPrint('Error starting analysis: $e');
          setState(() {
            _isAnalyzing = false;
            _hasError = true;
            _errorMessage = 'Failed to start analysis: ${e.toString()}';
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _resultsAnimationController.dispose();
    super.dispose();
  }

  // Detect if the image is from gallery or camera
  void _detectImageSource() {
    try {
      // Check if the image path contains typical gallery path indicators
      final String path = widget.imagePath.toLowerCase();
      _isGalleryImage = path.contains('gallery') ||
          path.contains('picture') ||
          path.contains('image') ||
          path.contains('dcim') ||
          path.contains('download');

      debugPrint(
          'Image source detected as: ${_isGalleryImage ? 'Gallery' : 'Camera'}');
    } catch (e) {
      debugPrint('Error detecting image source: $e');
      _isGalleryImage = false;
    }
  }

  Future<void> _analyzeImage() async {
    try {
      if (!_isInitialAnalysis) {
        setState(() {
          _isAnalyzing = true;
          _hasError = false;
          _errorMessage = '';
          _analysisResult = '';
          _parsedResults.clear();
          _analysisStatus = 'Initializing...';
          _detectedType = '';
        });
      }

      _isInitialAnalysis = false;
      debugPrint('Starting image analysis for: ${widget.imagePath}');

      // Verify image exists and has valid size
      final imageFile = File(widget.imagePath);
      try {
        if (!await imageFile.exists()) {
          throw Exception('Image file does not exist');
        }

        final fileSize = await imageFile.length();
        debugPrint('Image exists: ${await imageFile.exists()}');
        debugPrint('Image size: $fileSize bytes');

        // Check if image is too small or too large
        if (fileSize < 1024) {
          // Less than 1KB
          throw Exception('Image file is too small, likely corrupted');
        }

        if (fileSize > 20 * 1024 * 1024) {
          // More than 20MB
          throw Exception(
              'Image file is too large, please use a smaller image');
        }
      } catch (e) {
        setState(() {
          _hasError = true;
          _isAnalyzing = false;
          _errorMessage = 'Error accessing image: ${e.toString()}';
        });
        return;
      }

      // Show initial loading state with partial results
      setState(() {
        _parsedResults['Status'] = 'Analyzing...';
        _parsedResults['Type'] = 'Detecting...';
      });

      // Add timeout for analysis to prevent hanging
      Map<String, dynamic> results;

      if (widget.useAutoDetection) {
        // Use automatic detection
        // Use the new ImageAnalysisService
        results = await _imageAnalysisService
            .analyze(imageFile)
            .timeout(const Duration(seconds: 60), onTimeout: () {
          throw TimeoutException('Analysis timed out after 60 seconds');
        });

        debugPrint('Image analysis completed with results: $results');
        // Convert the new service response to the expected format
        results = _convertImageAnalysisResponse(results);

        // Store results for later use
        _analysisResults = results;

        // Directly apply AI output to UI and stop further text-based parsing
        _setUiFromImageAnalysis(results);
        return;
      }
    } catch (e) {
      debugPrint('Error in _analyzeImage: $e');
      _handleAnalysisError(e.toString());
    }
  }

  // Convert ImageAnalysisService response to the expected format
  Map<String, dynamic> _convertImageAnalysisResponse(
      Map<String, dynamic> response) {
    final int ripeness = response['ripeness'] ?? 50;
    final bool okayToHarvest = response['okay_to_harvest'] ?? false;
    final int daysToHarvest = response['days_to_harvest'] ?? 7;
    final String description =
        response['image_description'] ?? 'No description available';
    final String aiType = (response['type'] ?? '').toString();
    final String aiCategory = (response['category'] ?? '').toString();
    final String confidence = (response['confidence'] ?? "90").toString();
    final int confidencePercent = response['confidence'] ?? 90;
    final bool notProduce = response['not_produce'] == true;

    // If AI indicates it's okay to harvest, fetch the current user's phone from
    // Firestore and send an SMS notification in the background. We do this
    // asynchronously (fire-and-forget) so we don't change this function's
    // synchronous return type or block the UI.
    if (okayToHarvest == true) {
      (() async {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) {
            debugPrint('SMS not sent: no authenticated user');
            return;
          }

          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();

          if (!userDoc.exists) {
            debugPrint('SMS not sent: user document not found for uid $uid');
            return;
          }

          final data = userDoc.data();
          if (data == null) {
            debugPrint('SMS not sent: user document has no data');
            return;
          }

          // Try common phone field names
          final dynamic phoneField = data['phone'];

          final String? phoneNumberStr = phoneField?.toString();
          if (phoneNumberStr == null || phoneNumberStr.isEmpty) {
            debugPrint('SMS not sent: no phone number for user $uid');
            return;
          }

          try {
            final smsService = await SmsService.create();
            final String produceName = aiType.isNotEmpty
                ? aiType
                : (response['produce_type'] ?? 'your produce').toString();
            final String message =
                'Good news — your $produceName appears ready to harvest now. Ripeness: ${ripeness.toString()}%.';

            final bool sent = await smsService.sendSms(
              message: message,
              recipient: phoneNumberStr,
            );

            debugPrint('SMS send result for $phoneNumberStr: $sent');
          } catch (e) {
            debugPrint('Error creating or using SmsService: $e');
          }
        } catch (e) {
          debugPrint('Error fetching user data or sending SMS: $e');
        }
      })();
    }
    // Determine harvest status based on ripeness and okay_to_harvest
    String harvestStatus;
    if (okayToHarvest) {
      harvestStatus = 'ready_for_harvest';
    } else if (ripeness < 30) {
      harvestStatus = 'unripe';
    } else if (ripeness > 80) {
      harvestStatus = 'overripe';
    } else {
      harvestStatus = 'unripe';
    }

    return {
      'success': true,
      'timestamp': DateTime.now().toIso8601String(),
      'ripeness': ripeness,
      'detected_type':
          aiType.isNotEmpty ? aiType : response['produce_type'] ?? 'Unknown',
      'detected_category': aiCategory.isNotEmpty
          ? aiCategory
          : response['category'] ?? 'Unknown',
      'ripeness_status': harvestStatus,
      'ready_for_harvest': okayToHarvest,
      'days_until_harvest': daysToHarvest,
      'confidence_level': confidence,
      'confidence_percent': confidencePercent,
      'not_produce': notProduce,
      'detailed_analysis': description,
      'final_prediction': okayToHarvest,
      'gemini_analysis': description,
      'tensorflow_result': harvestStatus,
      'reconciled_result': harvestStatus,
    };
  }

  // Apply ImageAnalysisService results directly to UI and finish
  void _setUiFromImageAnalysis(Map<String, dynamic> results) {
    if (!mounted) return;
    setState(() {
      _analysisResults = results;
      _parsedResults.clear();

      // Handle non-produce detection
      if (results['not_produce'] == true) {
        _analysisResult = results['detailed_analysis'] ??
            'No fruits or vegetables detected in the image.';
        _parsedResults['Type'] = 'Not Produce';
        _parsedResults['Category'] = 'N/A';
        _parsedResults['Ready for Harvest'] = 'unknown';
        _isAnalyzing = false;
        _hasError = true;
        _errorMessage = 'This image does not contain a fruit or vegetable.';
        _analysisStatus = 'Complete';
        return;
      }

      // Map fields directly from AI output
      _detectedType = (results['detected_type'] ?? 'Unknown').toString();
      _parsedResults['Type'] = _detectedType;
      _parsedResults['Category'] =
          (results['detected_category'] ?? 'Unknown').toString();

      // Harvest readiness and ripeness
      final String harvestState = (results['reconciled_result'] ??
              (results['ready_for_harvest'] == true
                  ? 'ready_for_harvest'
                  : 'unripe'))
          .toString();
      _parsedResults['Ready for Harvest'] = harvestState;

      if (results.containsKey('ripeness')) {
        _parsedResults['Ripeness'] = '${results['ripeness']}%';
      }

      if (results.containsKey('days_until_harvest')) {
        _parsedResults['Estimated Days Until Harvest'] =
            results['days_until_harvest'].toString();
      }

      // Detailed analysis/description
      _analysisResult = (results['detailed_analysis'] ?? '').toString();

      if (results.containsKey('confidence_percent')) {
        _parsedResults['Analysis Confidence'] =
            '${results['confidence_percent']}%';
      } else if (results.containsKey('confidence_level')) {
        _parsedResults['Analysis Confidence'] =
            '${results['confidence_level'].toString()}%';
      }

      _isAnalyzing = false;
      _hasError = false;
      _analysisStatus = 'Complete';
    });

    // Trigger result animations
    _resultsAnimationController.forward();
  }

  void _handleAnalysisError(String errorMessage) {
    setState(() {
      _analysisResult = _formatAIAnalysisResult(errorMessage);
      _isAnalyzing = false;
      _hasError = true;
      _errorMessage = errorMessage.replaceAll('Error: ', '');

      // If we have any color information in the error message, try to use it
      String extractedColor = '';
      final colorMatch = RegExp(r'(?:color|colored|colours?):?\s*([a-zA-Z]+)')
          .firstMatch(errorMessage);
      if (colorMatch != null && colorMatch.group(1) != null) {
        extractedColor = colorMatch.group(1)!;
      }

      // Use a better default type based on any available information
      String fallbackType = _determineProduceTypeFromColor(extractedColor, '',
          results: {'error_message': errorMessage});

      // Set default values for the UI that align with dataset structure
      _detectedType = fallbackType;
      _parsedResults['Category'] = _determineProduceCategory(fallbackType);
      _parsedResults['Type'] = _detectedType;
      _parsedResults['Size'] = _getDefaultSizeForType(_detectedType);
      _parsedResults['Texture'] = _getDefaultTextureForType(_detectedType);
      _parsedResults['Color'] = _getDefaultColorForType(_detectedType);
      _parsedResults['Physical Cues'] =
          _getDefaultPhysicalCuesForType(_detectedType);
      _parsedResults['Ready for Harvest'] = 'ready_for_harvest';

      // Store basic analysis results for error case
      _analysisResults = {
        'detected_type': fallbackType,
        'days_until_harvest': 0,
        'final_prediction': true,
        'detailed_analysis':
            'Could not perform detailed analysis due to: $errorMessage'
      };

      // Add the error message for display
      _parsedResults['Error'] = _errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analysis Result'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
        ),
        // Single action: allow saving the analyzed result
        floatingActionButton: (!_isAnalyzing && !_hasError)
            ? FloatingActionButton.extended(
                onPressed: _resultsSaved
                    ? null
                    : () => _saveResultsToFirestore(_analysisResults),
                backgroundColor:
                    _resultsSaved ? Colors.grey : const Color(0xFF2E7D32),
                icon: Icon(_resultsSaved ? Icons.check : Icons.save),
                label: Text(_resultsSaved ? 'Saved' : 'Check Status'),
                tooltip: _resultsSaved
                    ? 'Analysis already saved'
                    : 'Save this analysis to your scans',
              )
            : null,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFF8F9FA), // Very light gray
                Color(0xFFE3F2FD), // Very light blue
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              // Display the image with enhanced styling
              Container(
                height: 280,
                width: double.infinity,
                color: Colors.transparent,
                child: Stack(
                  children: [
                    // Animated background circles for visual interest
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Positioned(
                          top: 20 +
                              (5 * sin(_animationController.value * 2 * pi)),
                          right: 40,
                          child: Transform.scale(
                            scale: 1.0 +
                                (0.05 *
                                    sin(_animationController.value * 2 * pi)),
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return Positioned(
                          bottom: 30 +
                              (3 *
                                  sin((_animationController.value + 0.5) *
                                      2 *
                                      pi)),
                          left: 30,
                          child: Transform.scale(
                            scale: 1.0 +
                                (0.03 *
                                    sin((_animationController.value + 0.3) *
                                        2 *
                                        pi)),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Enhanced image in the center with modern styling
                    Center(
                      child: Container(
                        height: 220,
                        width: 220,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
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
                              color: Colors.black.withOpacity(0.3),
                              spreadRadius: 0,
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                            BoxShadow(
                              color: Colors.white.withOpacity(0.1),
                              spreadRadius: 0,
                              blurRadius: 20,
                              offset: const Offset(0, -5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  spreadRadius: 0,
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.file(
                              File(widget.imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Enhanced fallback when image can't be loaded
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.grey.shade200,
                                        Colors.grey.shade300,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.8),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Colors.grey.shade600,
                                          size: 40,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        "Image could not be loaded",
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Show detected type if available (as an enhanced animated overlay label)
                    Positioned(
                      bottom: 15,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _detectedType.isEmpty
                                  ? 1.0 +
                                      (0.02 *
                                          sin(_animationController.value *
                                              2 *
                                              pi))
                                  : 1.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      spreadRadius: 0,
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.1),
                                      spreadRadius: 0,
                                      blurRadius: 10,
                                      offset: const Offset(0, -2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        child: Icon(
                                          _detectedType.isEmpty
                                              ? Icons.search
                                              : Icons.eco_outlined,
                                          key: ValueKey(_detectedType.isEmpty
                                              ? 'search'
                                              : 'eco'),
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                      child: Text(
                                        _detectedType.isEmpty
                                            ? "Analyzing..."
                                            : _detectedType,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Add the harvest status widget after the image display
              if (!_isAnalyzing && !_hasError) _buildHarvestStatusWidget(),

              // Display analysis status or error
              if (_isAnalyzing)
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildAnalyzingView(),
                  ),
                )
              else if (_hasError)
                Expanded(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            spreadRadius: 3,
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 60,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Analysis Error',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage,
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              _analyzeImage(); // Try again
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  const Color(0xFF2E7D32), // Dark Green
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'Try Again',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: AnimatedBuilder(
                    animation: _resultsAnimationController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Ready for Harvest status card
                                if (_parsedResults
                                    .containsKey('Ready for Harvest'))
                                  Builder(builder: (context) {
                                    debugPrint(
                                        'Displaying harvest readiness card with status: ${_parsedResults['Ready for Harvest']}');
                                    final gradientColors =
                                        _getHarvestStatusGradient(
                                                _parsedResults[
                                                    'Ready for Harvest']!)
                                            .colors;
                                    final gradientDesc =
                                        '${gradientColors[0].toString()} to ${gradientColors[1].toString()}';
                                    debugPrint('Using gradient: $gradientDesc');
                                    debugPrint(
                                        'Days until harvest data: ${_analysisResults.containsKey('days_until_harvest') ? _analysisResults['days_until_harvest'] : 'none'}');

                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 20),
                                      decoration: BoxDecoration(
                                        gradient: _getHarvestStatusGradient(
                                            _parsedResults[
                                                'Ready for Harvest']!),
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _getHarvestStatusGradient(
                                                    _parsedResults[
                                                        'Ready for Harvest']!)
                                                .colors[1]
                                                .withOpacity(0.3),
                                            spreadRadius: 0,
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            spreadRadius: 0,
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withOpacity(0.3),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _getHarvestStatusIcon(
                                                        _parsedResults[
                                                            'Ready for Harvest']!),
                                                    color: Colors.white,
                                                    size: 28,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Harvest Status',
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(0.9),
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(6),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.25),
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                          0.6),
                                                                  width: 1),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 10),
                                                          Expanded(
                                                            child: Text(
                                                              _getReadableHarvestState(
                                                                  _parsedResults[
                                                                      'Ready for Harvest']!),
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 26,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                letterSpacing:
                                                                    -0.6,
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 20),

                                            // Success confetti-like accents when ready for harvest
                                            if (_parsedResults[
                                                        'Ready for Harvest']
                                                    ?.toLowerCase() ==
                                                'ready_for_harvest')
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    bottom: 12),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withOpacity(0.2),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                            color: Colors.white
                                                                .withOpacity(
                                                                    0.4)),
                                                      ),
                                                      child: const Icon(
                                                        Icons.check_circle,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        'Great news! This crop looks ready to harvest.',
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.95),
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        softWrap: true,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    )
                                                  ],
                                                ),
                                              ),
                                            // Add days until harvest if available and produce is unripe
                                            if (_parsedResults[
                                                        'Ready for Harvest']!
                                                    .toLowerCase()
                                                    .contains('not ready') ||
                                                _parsedResults[
                                                            'Ready for Harvest']!
                                                        .toLowerCase() ==
                                                    'unripe' ||
                                                _parsedResults[
                                                            'Ready for Harvest']!
                                                        .toLowerCase() ==
                                                    'not_ready')
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.2),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber
                                                            .withOpacity(0.3),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      child: Icon(
                                                        Icons.schedule_outlined,
                                                        color: Colors
                                                            .amber.shade50,
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            'Estimated Harvest Time',
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                      0.9),
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              letterSpacing:
                                                                  0.3,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                            (() {
                                                              // Get days using our more accurate prediction method
                                                              int days =
                                                                  _predictDaysUntilHarvest(
                                                                      _analysisResults);

                                                              // Ensure we never show negative days in the UI
                                                              if (days < 0)
                                                                days = 0;

                                                              // Format days with proper pluralization
                                                              if (days == 0) {
                                                                return 'Ready now';
                                                              } else if (days ==
                                                                  1) {
                                                                return 'In 1 day';
                                                              } else {
                                                                return 'In $days days';
                                                              }
                                                            })(),
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  -0.3,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            // Show ripeness percentage if available
                                            if (_parsedResults
                                                .containsKey('Ripeness'))
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .donut_large_outlined,
                                                        color: Colors.white
                                                            .withOpacity(0.9),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        'Ripeness: ${_parsedResults['Ripeness']}',
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.95),
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            // Show confidence level if available
                                            if (_parsedResults.containsKey(
                                                'Analysis Confidence'))
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.verified_outlined,
                                                        color: Colors.white
                                                            .withOpacity(0.9),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          'Confidence: ${_parsedResults['Analysis Confidence']}',
                                                          style: TextStyle(
                                                            color: Colors.white
                                                                .withOpacity(
                                                                    0.95),
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        width: 60,
                                                        height: 6,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.3),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(3),
                                                        ),
                                                        child:
                                                            FractionallySizedBox(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          widthFactor:
                                                              _getConfidenceValue(
                                                                  _parsedResults[
                                                                      'Analysis Confidence']!),
                                                          child: Container(
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  Colors.white,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          3),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            // Add recommendation for action
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 16),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.tips_and_updates,
                                                    color: Colors.white70,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _getActionRecommendation(
                                                          _parsedResults[
                                                              'Ready for Harvest']!),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),

                                // Analysis details
                                if (_analysisResult.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white,
                                          Color(0xFFF5F7FA),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF546E7A)
                                              .withOpacity(0.1),
                                          spreadRadius: 0,
                                          blurRadius: 20,
                                          offset: const Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          spreadRadius: 0,
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Color(0xFFE9ECEF),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Color(0xFF546E7A),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                  Icons.analytics_outlined,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Detailed Analysis',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2C3E50),
                                                  letterSpacing: -0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Colors.grey.shade200,
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              _analysisResult ==
                                                          'No detailed analysis available' ||
                                                      _analysisResult.isEmpty
                                                  ? 'Analysis is based on the visual characteristics of this $_detectedType. The color, texture, and overall appearance indicate the current harvest readiness status.'
                                                  : _ensureAnalysisMatchesStatus(
                                                      _analysisResult),
                                              style: TextStyle(
                                                fontSize: 15,
                                                height: 1.6,
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),

                                          // Add key characteristics section for better information display
                                          if (_parsedResults
                                                  .containsKey('Color') ||
                                              _parsedResults
                                                  .containsKey('Texture') ||
                                              _parsedResults
                                                  .containsKey('Physical Cues'))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 24),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    height: 1,
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 16),
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFE9ECEF),
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .featured_play_list_outlined,
                                                        color:
                                                            Color(0xFF2C3E50),
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Key Characteristics',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Color(0xFF2C3E50),
                                                          letterSpacing: -0.3,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  if (_parsedResults
                                                      .containsKey('Color'))
                                                    _buildCharacteristicRow(
                                                      'Color',
                                                      _enhanceCharacteristicDetail(
                                                          'Color',
                                                          _parsedResults[
                                                              'Color']!,
                                                          _detectedType),
                                                      Icons.color_lens,
                                                    ),
                                                  if (_parsedResults
                                                      .containsKey('Texture'))
                                                    _buildCharacteristicRow(
                                                      'Texture',
                                                      _enhanceCharacteristicDetail(
                                                          'Texture',
                                                          _parsedResults[
                                                              'Texture']!,
                                                          _detectedType),
                                                      Icons.texture,
                                                    ),
                                                  if (_parsedResults
                                                      .containsKey(
                                                          'Physical Cues'))
                                                    _buildCharacteristicRow(
                                                      'Physical Cues',
                                                      _enhanceCharacteristicDetail(
                                                          'Physical Cues',
                                                          _parsedResults[
                                                              'Physical Cues']!,
                                                          _detectedType),
                                                      Icons.visibility,
                                                    ),

                                                  // Add ideal characteristics for comparison
                                                  const SizedBox(height: 20),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    decoration: BoxDecoration(
                                                      color: Color(0xFFF8F9FA),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                      border: Border.all(
                                                        color:
                                                            Color(0xFFE9ECEF),
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .lightbulb_outline,
                                                              color: Color(
                                                                  0xFF34495E),
                                                              size: 18,
                                                            ),
                                                            const SizedBox(
                                                                width: 8),
                                                            Text(
                                                              'Ideal Harvest Characteristics',
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                    0xFF34495E),
                                                                letterSpacing:
                                                                    -0.2,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 12),
                                                        Text(
                                                          _getIdealCharacteristics(
                                                              _detectedType),
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors
                                                                .grey[700],
                                                            height: 1.4,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                          // Add days until harvest if not in the status card
                                          if (_parsedResults[
                                                      'Ready for Harvest']!
                                                  .toLowerCase()
                                                  .contains('unripe') ||
                                              _parsedResults[
                                                          'Ready for Harvest']!
                                                      .toLowerCase() ==
                                                  'unripe' ||
                                              _parsedResults[
                                                          'Ready for Harvest']!
                                                      .toLowerCase() ==
                                                  'not_ready' ||
                                              _parsedResults[
                                                      'Ready for Harvest']!
                                                  .toLowerCase()
                                                  .contains('not ready'))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 16),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.calendar_today,
                                                    color: Colors.orange[700],
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    (() {
                                                      // Get days using our more accurate prediction method
                                                      int days =
                                                          _predictDaysUntilHarvest(
                                                              _analysisResults);

                                                      // Handle negative days for overripe produce
                                                      if (days < 0) {
                                                        return 'Produce is past optimal harvest time';
                                                      }

                                                      // Format days with proper pluralization
                                                      String dayText = days == 1
                                                          ? '1 day'
                                                          : '$days days';
                                                      return 'Estimated days until harvest: $dayText';
                                                    })(),
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.orange[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 20),
                                          if (_parsedResults.containsKey(
                                              'Analysis Confidence'))
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .psychology_outlined,
                                                        color: _getConfidenceColor(
                                                            _parsedResults[
                                                                'Analysis Confidence']!),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Analysis Confidence',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                          color:
                                                              Color(0xFF2C3E50),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Container(
                                                          height: 8,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .grey.shade200,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child:
                                                              FractionallySizedBox(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            widthFactor:
                                                                _getConfidenceValue(
                                                                    _parsedResults[
                                                                        'Analysis Confidence']!),
                                                            child: Container(
                                                              decoration:
                                                                  BoxDecoration(
                                                                gradient:
                                                                    LinearGradient(
                                                                  colors: [
                                                                    _getConfidenceColor(
                                                                        _parsedResults[
                                                                            'Analysis Confidence']!),
                                                                    _getConfidenceColor(_parsedResults[
                                                                            'Analysis Confidence']!)
                                                                        .withOpacity(
                                                                            0.7),
                                                                  ],
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        _parsedResults[
                                                            'Analysis Confidence']!,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                          color: _getConfidenceColor(
                                                              _parsedResults[
                                                                  'Analysis Confidence']!),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
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
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzingView() {
    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Neural network animation
            AnalysisAnimation(
              controller: _animationController,
              imageFile: File(widget.imagePath),
            ),
            const SizedBox(height: 12),

            // Modern loading indicator with percentage
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  // Analysis status with custom loading animation
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Custom pulse animation container
                      Container(
                        height: 28,
                        width: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return Container(
                                height: 14 +
                                    6 *
                                        sin(_animationController.value *
                                            2 *
                                            pi),
                                width: 14 +
                                    6 *
                                        sin(_animationController.value *
                                            2 *
                                            pi),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary
                                          .withOpacity(0.6),
                                      blurRadius: 12,
                                      spreadRadius: 1 *
                                          sin(_animationController.value *
                                              2 *
                                              pi),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Status text without gradient
                      Flexible(
                        child: Text(
                          _analysisStatus,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Progress bar
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, _) {
                      // Simulate progress from 0 to 100%
                      final progress = _animationController.value;
                      final repeatValue = progress - progress.floor();
                      final displayProgress =
                          repeatValue * 0.3 + 0.5 + 0.2 * sin(progress * pi);
                      final percent =
                          (displayProgress * 100).toInt().clamp(0, 99);

                      return Column(
                        children: [
                          // Progress percentage
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              '$percent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          // Custom styled progress bar
                          Container(
                            height: 6,
                            width: MediaQuery.of(context).size.width * 0.7,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Stack(
                              children: [
                                // Progress fill
                                FractionallySizedBox(
                                  widthFactor: displayProgress.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary
                                              .withOpacity(0.5),
                                          blurRadius: 6,
                                          spreadRadius: 0.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Animated highlight (removing gradient)
                                Positioned(
                                  left: MediaQuery.of(context).size.width *
                                          0.7 *
                                          displayProgress -
                                      20,
                                  child: Container(
                                    height: 6,
                                    width: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(3),
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
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'AI is analyzing your produce to determine its ripeness and harvest readiness',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),

            // Show any preliminary results
            if (_parsedResults.isNotEmpty &&
                _parsedResults.containsKey('Type') &&
                _detectedType.isNotEmpty &&
                _detectedType != "Detecting...")
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.9),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Detected: $_detectedType',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper to get human-readable harvest state
  String _getReadableHarvestState(String harvestState) {
    final lowerCaseState = harvestState.toLowerCase();

    switch (lowerCaseState) {
      case 'unripe':
        return 'Not ready for harvest';
      case 'ready_for_harvest':
      case 'ready for harvest':
      case 'ready': // Add this case to handle the 'Ready' state from _getHarvestReadinessFromAIResults
        return 'Ready for harvest';
      case 'overripe':
        return 'Past optimal harvest time';
      case 'not ready': // Add this case to handle the 'Not Ready' state from _getHarvestReadinessFromAIResults
      case 'not_ready':
        return 'Not ready for harvest';
      default:
        // Handle cases where the analysis string contains harvest readiness info
        if (lowerCaseState.contains('yes') ||
            (lowerCaseState.contains('ready') &&
                !lowerCaseState.contains('not ready'))) {
          return 'Ready for harvest';
        } else if (lowerCaseState.contains('not ready') ||
            lowerCaseState.contains('no') ||
            lowerCaseState.contains('unripe')) {
          return 'Not ready for harvest';
        } else if (lowerCaseState.contains('over') ||
            lowerCaseState.contains('past')) {
          return 'Past optimal harvest time';
        } else {
          return 'Status: $harvestState';
        }
    }
  }

  // Helper to get icon based on harvest status
  IconData _getHarvestStatusIcon(String harvestState) {
    final lowerCaseState = harvestState.toLowerCase();

    // Cases for unripe/not ready
    if (lowerCaseState == 'unripe' ||
        lowerCaseState == 'not ready' ||
        lowerCaseState == 'not_ready' ||
        lowerCaseState.contains('not ready')) {
      return Icons.hourglass_bottom;
    }
    // Cases for ready
    else if (lowerCaseState == 'ready_for_harvest' ||
        lowerCaseState == 'ready' ||
        (lowerCaseState.contains('ready') && !lowerCaseState.contains('not')) ||
        lowerCaseState.contains('yes') ||
        (lowerCaseState.contains('harvest') &&
            !lowerCaseState.contains('not'))) {
      return Icons.check_circle_rounded;
    }
    // Cases for overripe
    else if (lowerCaseState == 'overripe' ||
        lowerCaseState.contains('over') ||
        lowerCaseState.contains('past')) {
      return Icons.warning;
    }
    // Default case
    else {
      return Icons.help_outline;
    }
  }

  // Helper to get gradient based on harvest status
  LinearGradient _getHarvestStatusGradient(String harvestState) {
    final lowerCaseState = harvestState.toLowerCase();

    // Warning orange gradient for not ready (stronger)
    if (lowerCaseState == 'unripe' ||
        lowerCaseState == 'not ready' ||
        lowerCaseState == 'not_ready' ||
        lowerCaseState.contains('not ready')) {
      return LinearGradient(
        colors: [
          const Color(0xFFFF9800), // Deep orange
          const Color(0xFFFFB74D), // Medium orange
          const Color(0xFFFFB74D), // Light orange
        ],
        stops: const [0.0, 0.5, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Success green gradient for ready (make greener and more saturated)
    else if (lowerCaseState == 'ready' ||
        lowerCaseState == 'ready_for_harvest' ||
        (lowerCaseState.contains('ready') && !lowerCaseState.contains('not'))) {
      return LinearGradient(
        colors: [
          const Color(0xFF2E7D32), // Dark green
          const Color(0xFF388E3C), // Strong green
          const Color(0xFF66BB6A), // Medium green
        ],
        stops: const [0.0, 0.5, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Subtle red gradient for overripe
    else if (lowerCaseState == 'overripe' ||
        lowerCaseState.contains('over') ||
        lowerCaseState.contains('past')) {
      return LinearGradient(
        colors: [
          const Color(0xFFFDE7E7), // Very light red
          const Color(0xFFFFCDD2), // Light red
          const Color(0xFFEF9A9A), // Soft red
        ],
        stops: const [0.0, 0.5, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Default gradient
    else {
      return AppTheme.secondaryGradient;
    }
  }

  // Enhanced formatting of AI analysis result
  String _formatAIAnalysisResult(String rawAnalysis) {
    if (rawAnalysis.isEmpty) {
      return 'No analysis available';
    }

    debugPrint('Formatting raw analysis (${rawAnalysis.length} chars)');

    // Handle special case when raw analysis is an error message
    if (rawAnalysis.startsWith('Error:') ||
        rawAnalysis.toLowerCase().contains('could not analyze') ||
        rawAnalysis.toLowerCase().contains('failed to analyze')) {
      debugPrint(
          'Raw analysis contains error message, returning minimal error info');
      return 'Analysis could not be completed. Please try again with a clearer image.';
    }

    // Remove any "Analysis:" prefix from the text
    String formatted = rawAnalysis;

    // Remove common headers to get to the content
    final headersToRemove = [
      RegExp(
          r'Ready\s+for\s+Harvest\s*:\s*(?:Yes|No|yes|no|Ready|Not Ready|Overripe).*?\n',
          caseSensitive: false),
      RegExp(
          r'Confidence\s*:\s*(?:High|Medium|Low|high|medium|low|Very High|Very Low).*?\n',
          caseSensitive: false),
      RegExp(
          r'(?:Estimated\s+)?Days\s+Until\s+(?:Optimal\s+)?Harvest\s*:\s*\d+.*?\n',
          caseSensitive: false),
      RegExp(r'^Analysis\s*:\s*', caseSensitive: false),
      RegExp(r'^Harvest Status\s*:\s*(?:Ready|Not Ready|Overripe).*?\n',
          caseSensitive: false),
      RegExp(r'Ripeness\s*:\s*.*?\n', caseSensitive: false),
    ];

    // Try to extract just the analysis section if it exists
    final analysisMatch = RegExp(r'Analysis\s*:\s*(.*?)(?=\n\d|\nEstimated|$)',
            caseSensitive: false, dotAll: true)
        .firstMatch(rawAnalysis);

    if (analysisMatch != null && analysisMatch.group(1) != null) {
      // We found a well-formatted analysis section
      formatted = analysisMatch.group(1)!.trim();
      debugPrint('Extracted specific analysis section using regex');
    } else {
      // Remove headers individually
      for (final header in headersToRemove) {
        formatted = formatted.replaceFirst(header, '');
      }

      // If it starts with a number followed by period (like "1."), remove it
      formatted = formatted.replaceFirst(RegExp(r'^\d+\.\s*'), '');
    }

    // Handle any automatic analysis flags
    if (formatted.contains('AUTOMATIC COLOR ANALYSIS:')) {
      final colorAnalysis = RegExp(
              r'AUTOMATIC COLOR ANALYSIS:(.*?)(?=\n\n|\n[A-Z]|$)',
              dotAll: true)
          .firstMatch(formatted)
          ?.group(1)
          ?.trim();

      if (colorAnalysis != null) {
        // Create a more user-friendly color analysis section
        final colorSection = '\n\nColor Analysis: $colorAnalysis';
        formatted = formatted.replaceFirst(
                RegExp(r'AUTOMATIC COLOR ANALYSIS:.*?\n\n', dotAll: true), '') +
            colorSection;
      }
    }

    // Handle SPECIAL NOTE sections
    if (formatted.contains('SPECIAL NOTE:')) {
      final specialNote =
          RegExp(r'SPECIAL NOTE:(.*?)(?=\n\n|\n[A-Z]|$)', dotAll: true)
              .firstMatch(formatted)
              ?.group(1)
              ?.trim();

      if (specialNote != null) {
        // Create a more user-friendly note section
        final noteSection = '\n\nImportant Note: $specialNote';
        formatted = formatted.replaceFirst(
                RegExp(r'SPECIAL NOTE:.*?\n\n', dotAll: true), '') +
            noteSection;
      }
    }

    // Enhance formatting by identifying and highlighting key sections
    final lowerFormatted = formatted.toLowerCase();
    if (lowerFormatted.contains('color:') ||
        lowerFormatted.contains('texture:') ||
        lowerFormatted.contains('ripeness:')) {
      // This analysis contains structured data, make sure it's properly formatted
      formatted = formatted.replaceAll(
          RegExp(r'(?:Color|Texture|Ripeness|Shape|Size)\s*:\s*'), '\nKey: ');
    }

    // Clean up any repeated newlines or spaces
    formatted = formatted.replaceAll(
        RegExp(r' {2,}'), ' '); // Replace multiple spaces with a single space

    // Trim excess whitespace and newlines
    formatted = formatted.trim();

    // Ensure paragraphs are properly separated but not with excessive newlines
    formatted = formatted.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // If formatting stripped too much content, fall back to original with minimal cleaning
    if (formatted.length < 20 && rawAnalysis.length > 50) {
      debugPrint('Formatting removed too much content, using minimal cleaning');
      formatted = rawAnalysis
          .replaceFirst(RegExp(r'^Analysis\s*:\s*', caseSensitive: false), '')
          .trim();
    }

    debugPrint('Formatted analysis (${formatted.length} chars)');
    return formatted;
  }

  // Verify and standardize produce type
  String _verifyProduceType(String detectedType) {
    if (detectedType.isEmpty || detectedType.toLowerCase() == 'unknown') {
      return 'Apple';
    }

    // Standardize common produce types
    String type = detectedType.toLowerCase().trim();

    // Standardize common names including more varieties and alternative names
    Map<String, String> typeMapping = {
      // Fruits
      'watermelon': 'Watermelon',
      'water melon': 'Watermelon',
      'papaya': 'Papaya',
      'pawpaw': 'Papaya',
      'pineapple': 'Pineapple',
      'pine apple': 'Pineapple',
      'guava': 'Guava',
      'jackfruit': 'Jackfruit',
      'jack fruit': 'Jackfruit',
      'mango': 'Mango',
      'banana': 'Banana',
      'plaintain': 'Plantain',
      'apple': 'Apple',
      'green apple': 'Green Apple',
      'granny smith': 'Green Apple',
      'red apple': 'Red Apple',
      'gala apple': 'Red Apple',
      'fuji apple': 'Red Apple',
      'honeycrisp': 'Red Apple',
      'tomato': 'Tomato',
      'roma tomato': 'Tomato',
      'cherry tomato': 'Cherry Tomato',
      'avocado': 'Avocado',
      'hass avocado': 'Avocado',
      'lemon': 'Lemon',
      'lime': 'Lime',
      'key lime': 'Lime',
      'orange': 'Orange',
      'navel orange': 'Orange',
      'mandarin': 'Mandarin Orange',
      'tangerine': 'Mandarin Orange',
      'clementine': 'Mandarin Orange',
      'grape': 'Grape',
      'grapes': 'Grape',
      'red grape': 'Red Grape',
      'green grape': 'Green Grape',
      'strawberry': 'Strawberry',
      'strawberries': 'Strawberry',
      'blueberry': 'Blueberry',
      'blueberries': 'Blueberry',
      'raspberry': 'Raspberry',
      'blackberry': 'Blackberry',
      'kiwi': 'Kiwi',
      'kiwifruit': 'Kiwi',
      'pomegranate': 'Pomegranate',
      'dragon fruit': 'Dragon Fruit',
      'pitaya': 'Dragon Fruit',
      'coconut': 'Coconut',
      'fig': 'Fig',
      'passion fruit': 'Passion Fruit',
      'passionfruit': 'Passion Fruit',
      'peach': 'Peach',
      'plum': 'Plum',
      'pear': 'Pear',
      'asian pear': 'Asian Pear',
      'nashi': 'Asian Pear',
      'apricot': 'Apricot',
      'persimmon': 'Persimmon',

      // Vegetables
      'corn': 'Corn',
      'maize': 'Corn',
      'sweet corn': 'Corn',
      'eggplant': 'Eggplant',
      'aubergine': 'Eggplant',
      'brinjal': 'Eggplant',
      'okra': 'Okra',
      'ladies finger': 'Okra',
      'ladiesfinger': 'Okra',
      'lady finger': 'Okra',
      'gumbo': 'Okra',
      'squash': 'Squash',
      'pumpkin': 'Pumpkin',
      'butternut': 'Butternut Squash',
      'butternut squash': 'Butternut Squash',
      'acorn squash': 'Acorn Squash',
      'zucchini': 'Zucchini',
      'courgette': 'Zucchini',
      'beans': 'String Beans',
      'string beans': 'String Beans',
      'green beans': 'String Beans',
      'snap beans': 'String Beans',
      'french beans': 'String Beans',
      'cucumber': 'Cucumber',
      'gherkin': 'Cucumber',
      'carrot': 'Carrot',
      'potato': 'Potato',
      'sweet potato': 'Sweet Potato',
      'yam': 'Yam',
      'bell pepper': 'Bell Pepper',
      'capsicum': 'Bell Pepper',
      'red pepper': 'Red Bell Pepper',
      'green pepper': 'Green Bell Pepper',
      'yellow pepper': 'Yellow Bell Pepper',
      'chili': 'Chili',
      'chilli': 'Chili',
      'hot pepper': 'Chili',
      'cabbage': 'Cabbage',
      'red cabbage': 'Red Cabbage',
      'lettuce': 'Lettuce',
      'romaine': 'Romaine Lettuce',
      'iceberg': 'Iceberg Lettuce',
      'broccoli': 'Broccoli',
      'broccolini': 'Broccolini',
      'cauliflower': 'Cauliflower',
      'onion': 'Onion',
      'red onion': 'Red Onion',
      'yellow onion': 'Yellow Onion',
      'white onion': 'White Onion',
      'spring onion': 'Spring Onion',
      'scallion': 'Spring Onion',
      'green onion': 'Spring Onion',
      'garlic': 'Garlic',
      'ginger': 'Ginger',
      'celery': 'Celery',
      'asparagus': 'Asparagus',
      'spinach': 'Spinach',
      'kale': 'Kale',
      'radish': 'Radish',
      'turnip': 'Turnip',
      'beetroot': 'Beetroot',
      'beet': 'Beetroot',
      'artichoke': 'Artichoke',
      'leek': 'Leek',
      'bok choy': 'Bok Choy',
      'pak choi': 'Bok Choy',
      'mushroom': 'Mushroom',
      'mushrooms': 'Mushroom',
    };

    // First check for exact match
    if (typeMapping.containsKey(type)) {
      return typeMapping[type]!;
    }

    // Then check for partial matches using word containment
    for (var key in typeMapping.keys) {
      // Check if the key is a full word within the detected type
      if (RegExp('\\b${RegExp.escape(key)}\\b', caseSensitive: false)
          .hasMatch(type)) {
        return typeMapping[key]!;
      }
    }

    // Finally check for any substring match for less precise matches
    for (var key in typeMapping.keys) {
      if (type.contains(key)) {
        return typeMapping[key]!;
      }
    }

    // If not found in mapping, capitalize first letter and each word
    return type
        .split(' ')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ');
  }

  // Extract produce type from analysis text if not detected directly
  String _extractProduceTypeFromAnalysis(String analysisText) {
    if (analysisText.isEmpty) return _determineProduceTypeFromColor('', '');

    // Initialize confidence scoring system
    Map<String, int> typeConfidenceScores = {};

    // Define comprehensive categories of produce with common varieties
    final Map<String, List<String>> produceCategories = {
      'apple': [
        'granny smith',
        'honeycrisp',
        'gala',
        'fuji',
        'golden delicious',
        'red delicious',
        'pink lady',
        'mcintosh',
        'cripps pink'
      ],
      'banana': ['cavendish', 'plantain', 'lady finger', 'red banana', 'burro'],
      'citrus': [
        'orange',
        'lemon',
        'lime',
        'grapefruit',
        'mandarin',
        'tangerine',
        'clementine',
        'kumquat'
      ],
      'berry': [
        'strawberry',
        'blueberry',
        'raspberry',
        'blackberry',
        'cranberry',
        'mulberry',
        'gooseberry',
        'elderberry'
      ],
      'tropical': [
        'mango',
        'papaya',
        'pineapple',
        'guava',
        'passion fruit',
        'dragon fruit',
        'lychee',
        'star fruit',
        'jackfruit',
        'durian'
      ],
      'melon': [
        'watermelon',
        'cantaloupe',
        'honeydew',
        'canary melon',
        'galia melon'
      ],
      'stone fruit': [
        'peach',
        'plum',
        'nectarine',
        'apricot',
        'cherry',
        'mango'
      ],
      'vegetable fruit': [
        'tomato',
        'eggplant',
        'bell pepper',
        'chili pepper',
        'cucumber',
        'zucchini',
        'squash',
        'pumpkin',
        'okra'
      ],
      'leafy green': [
        'lettuce',
        'spinach',
        'kale',
        'arugula',
        'swiss chard',
        'collard greens',
        'cabbage',
        'bok choy',
        'romaine',
        'iceberg'
      ],
      'root': [
        'potato',
        'carrot',
        'radish',
        'beet',
        'turnip',
        'sweet potato',
        'parsnip',
        'ginger',
        'onion',
        'garlic',
        'shallot'
      ],
      'cruciferous': [
        'broccoli',
        'cauliflower',
        'brussels sprout',
        'bok choy',
        'cabbage',
        'kohlrabi'
      ],
      'other': [
        'avocado',
        'coconut',
        'artichoke',
        'mushroom',
        'asparagus',
        'celery',
        'leek',
        'olive'
      ]
    };

    // Flatten the map to get all produce for easy searching
    List<String> allProduce = [];
    produceCategories.forEach((category, produceList) {
      allProduce.addAll(produceList);
    });

    // First, look for Type: field which is specifically formatted by our AI service
    final typeLinePattern = RegExp(
        r'Type\s*:\s*([A-Za-z]+(?:\s+[A-Za-z]+){0,2})',
        caseSensitive: false);
    final typeMatch = typeLinePattern.firstMatch(analysisText);
    if (typeMatch != null && typeMatch.group(1) != null) {
      String matchedType = typeMatch.group(1)!.trim();
      // Verify it's not an invalid value
      if (matchedType.toLowerCase() != 'unknown' &&
          matchedType.toLowerCase() != 'fruit' &&
          matchedType.toLowerCase() != 'vegetable') {
        // High confidence for explicitly labeled type
        typeConfidenceScores[matchedType.toLowerCase()] = 15;
      }
    }

    // Look for direct mentions of types with strong indicators
    final List<RegExp> directTypePatterns = [
      // Look for phrases that clearly identify the produce type
      RegExp(
          r'[Tt]he (?:image|photo) shows (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]his is (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'[Tt]he produce (?:is|appears to be) (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'[Ii] can identify this as (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'[Tt]his (?:fruit|vegetable) is (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]he image depicts (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'(?:analyzing|analysis of) (?:a|an|the) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'(?:image|photo) of (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      // Additional patterns for higher accuracy
      RegExp(r'[Tt]his ([A-Za-z]+(?:\s[A-Za-z]+){0,2}) is'),
      RegExp(r'[Aa] ([A-Za-z]+(?:\s[A-Za-z]+){0,2}) that is'),
      RegExp(r'[Tt]he ([A-Za-z]+(?:\s[A-Za-z]+){0,2}) in the image'),
      RegExp(r'[Ii]dentified as (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]he ([A-Za-z]+(?:\s[A-Za-z]+){0,2}) appears to be'),
      RegExp(r'[Tt]he produce type is ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]his is clearly (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]he image contains (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Ww]e can see (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'[Tt]he variety is ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r"[Ii]t's (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})")
    ];

    // Words to exclude which are not actual produce types
    List<String> excludeWords = [
      'ripe',
      'unripe',
      'overripe',
      'green',
      'yellow',
      'red',
      'the',
      'this',
      'produce',
      'fruit',
      'vegetable',
      'food',
      'item',
      'large',
      'small',
      'medium',
      'fresh',
      'harvest',
      'ready',
      'firm',
      'soft',
      'hard',
      'typical',
      'common',
      'standard',
      'normal',
      'healthy'
    ];

    // Check each direct pattern for a clear identification
    for (var pattern in directTypePatterns) {
      final match = pattern.firstMatch(analysisText);
      if (match != null && match.group(1) != null) {
        String possibleType = match.group(1)!.trim().toLowerCase();

        // Check if the found type is not in the exclusion list
        if (!excludeWords.contains(possibleType)) {
          // Check if it's a known produce or variety
          bool isKnownProduce = false;

          // Check direct matches in all produce
          if (allProduce.contains(possibleType)) {
            typeConfidenceScores[possibleType] =
                (typeConfidenceScores[possibleType] ?? 0) + 10;
            isKnownProduce = true;
          }

          // Check if it's a variety of a known produce
          if (!isKnownProduce) {
            produceCategories.forEach((category, varieties) {
              for (String variety in varieties) {
                if (possibleType.contains(variety) ||
                    variety.contains(possibleType) ||
                    possibleType.contains(category)) {
                  typeConfidenceScores[variety] =
                      (typeConfidenceScores[variety] ?? 0) + 5;
                  isKnownProduce = true;
                  break;
                }
              }
            });
          }

          // If not a known produce but found in a strong pattern, add it anyway
          if (!isKnownProduce) {
            typeConfidenceScores[possibleType] =
                (typeConfidenceScores[possibleType] ?? 0) + 8;
          }
        }
      }
    }

    // If not found with direct patterns, look for mentions of known produce types
    final List<String> commonProduceTypes = [
      'apple',
      'banana',
      'orange',
      'watermelon',
      'papaya',
      'pineapple',
      'guava',
      'jackfruit',
      'tomato',
      'potato',
      'carrot',
      'broccoli',
      'lettuce',
      'corn',
      'eggplant',
      'okra',
      'squash',
      'mango',
      'cucumber',
      'lemon',
      'lime',
      'avocado',
      'strawberry',
      'blueberry',
      'grape',
      'pepper',
      'onion',
      'garlic',
      'bell pepper',
      'kiwi',
      'peach',
      'pear',
      'plum',
      'cherry',
      'pomegranate',
      'fig',
      'passion fruit',
      'dragon fruit',
      'zucchini',
      'cauliflower',
      'cabbage',
      'bok choy',
      'kale',
      'spinach',
      'sweet potato',
      'radish',
      'turnip',
      'celery',
      'asparagus',
      'artichoke'
    ];

    // Check for common produce types mentioned in the text with word boundaries
    for (String produceType in commonProduceTypes) {
      // Use word boundaries to ensure we're catching complete words
      if (RegExp(r'\b' + produceType + r'\b', caseSensitive: false)
          .hasMatch(analysisText)) {
        // Get position of the mention for relevance scoring
        int position = analysisText.toLowerCase().indexOf(produceType);
        int positionScore = position < 200 ? 3 : (position < 500 ? 2 : 1);

        // Count occurrences for frequency scoring
        int occurrences =
            RegExp(r'\b' + produceType + r'\b', caseSensitive: false)
                .allMatches(analysisText)
                .length;
        int frequencyScore = occurrences > 3 ? 3 : occurrences;

        // Add to confidence score
        typeConfidenceScores[produceType] =
            (typeConfidenceScores[produceType] ?? 0) +
                4 +
                positionScore +
                frequencyScore;
      }
    }

    // Try broader patterns if no high confidence matches
    final broaderPatterns = [
      RegExp(
          r'(?:appears to be|looks like|seems to be|is likely|probably) (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'([A-Za-z]+(?:\s[A-Za-z]+){0,2}) (?:shown in|visible in|in the image|in the photo)'),
      RegExp(
          r'has the characteristics of (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(r'resembles (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
      RegExp(
          r'(?:typical|characteristic) of (?:a|an) ([A-Za-z]+(?:\s[A-Za-z]+){0,2})'),
    ];

    for (var pattern in broaderPatterns) {
      final match = pattern.firstMatch(analysisText);
      if (match != null && match.group(1) != null) {
        String possibleType = match.group(1)!.trim().toLowerCase();

        if (!excludeWords.contains(possibleType)) {
          // Check if it's a known produce
          if (allProduce.contains(possibleType)) {
            typeConfidenceScores[possibleType] =
                (typeConfidenceScores[possibleType] ?? 0) + 6;
          } else {
            // Check if it's a variety or contains known produce
            produceCategories.forEach((category, varieties) {
              for (String variety in varieties) {
                if (possibleType.contains(variety) ||
                    variety.contains(possibleType)) {
                  typeConfidenceScores[variety] =
                      (typeConfidenceScores[variety] ?? 0) + 3;
                  break;
                }
              }
            });
          }
        }
      }
    }

    // Extract color information if no type is found
    String extractedColor = '';
    final colorMatches =
        RegExp(r'(?:color is|colored|color appears to be) ([a-zA-Z]+)')
            .firstMatch(analysisText);
    if (colorMatches != null && colorMatches.group(1) != null) {
      extractedColor = colorMatches.group(1)!;
    }

    // Extract texture information
    String extractedTexture = '';
    final textureMatches =
        RegExp(r'(?:texture is|textured|surface is) ([a-zA-Z]+)')
            .firstMatch(analysisText);
    if (textureMatches != null && textureMatches.group(1) != null) {
      extractedTexture = textureMatches.group(1)!;
    }

    // Extract shape information
    String extractedShape = '';
    final shapeMatches = RegExp(r'(?:shape is|shaped like|appears) ([a-zA-Z]+)')
        .firstMatch(analysisText);
    if (shapeMatches != null && shapeMatches.group(1) != null) {
      extractedShape = shapeMatches.group(1)!;
    }

    // If we have color/texture information, boost confidence for matching produce
    if (extractedColor.isNotEmpty) {
      // Map colors to typical produce
      Map<String, List<String>> colorToProduceMap = {
        'red': ['apple', 'strawberry', 'tomato', 'cherry', 'bell pepper'],
        'yellow': ['banana', 'lemon', 'pineapple', 'bell pepper'],
        'green': [
          'apple',
          'kiwi',
          'lime',
          'avocado',
          'bell pepper',
          'lettuce',
          'broccoli'
        ],
        'orange': ['orange', 'mango', 'papaya', 'cantaloupe', 'carrot'],
        'purple': ['eggplant', 'plum', 'grape', 'blackberry'],
        'brown': ['potato', 'kiwi', 'coconut'],
        'white': ['cauliflower', 'garlic', 'onion']
      };

      colorToProduceMap.forEach((color, produceList) {
        if (extractedColor.toLowerCase().contains(color)) {
          for (String produce in produceList) {
            typeConfidenceScores[produce] =
                (typeConfidenceScores[produce] ?? 0) + 2;
          }
        }
      });
    }

    // Collect everything we could find about the produce
    Map<String, dynamic> extractedData = {
      'analysis_text': analysisText,
      'color': extractedColor,
      'texture': extractedTexture,
      'shape': extractedShape,
    };

    // Find the produce type with the highest confidence score
    String detectedType = '';
    int highestConfidence = 0;

    typeConfidenceScores.forEach((produce, confidence) {
      if (confidence > highestConfidence) {
        highestConfidence = confidence;
        detectedType = produce;
      }
    });

    if (detectedType.isNotEmpty) {
      return _verifyProduceType(detectedType);
    }

    // If no type found or no high confidence match, use color/texture to determine
    if (extractedColor.isNotEmpty ||
        extractedTexture.isNotEmpty ||
        extractedShape.isNotEmpty) {
      return _determineProduceTypeFromColor(extractedColor, extractedTexture,
          results: extractedData);
    }

    // If no type found in the analysis, make a guess based on color
    return _determineProduceTypeFromColor('', '',
        results: {'analysis_text': analysisText});
  }

  // Determine produce type from color when type is unknown
  String _determineProduceTypeFromColor(String color, String texture,
      {Map<String, dynamic>? results}) {
    // If both color and texture are unknown/empty, first check analysis text
    if ((color.isEmpty || color.toLowerCase() == 'unknown') &&
        (texture.isEmpty || texture.toLowerCase() == 'unknown') &&
        results != null) {
      // Try to extract from AI analysis text first
      for (String key in [
        'detailed_analysis',
        'gemini_analysis',
        'gemini_result',
        'analysis_text'
      ]) {
        if (results.containsKey(key) &&
            results[key] != null &&
            results[key].toString().isNotEmpty) {
          String analysisText = results[key].toString();
          String possibleType = _extractProduceTypeFromAnalysis(analysisText);
          if (possibleType != 'Unknown') {
            return possibleType;
          }
        }
      }
    }

    // Try to use the TensorFlow confidence data if available
    if (results != null && results.containsKey('tensorflow_confidence_map')) {
      // If we have confidence scores for different types, use the highest one
      Map<String, double> confidenceMap =
          Map<String, double>.from(results['tensorflow_confidence_map'] ?? {});
      if (confidenceMap.isNotEmpty) {
        // Find the type with the highest confidence score
        String highestType = '';
        double highestScore =
            0.3; // Only consider types with at least 30% confidence

        confidenceMap.forEach((type, score) {
          if (score > highestScore) {
            highestScore = score;
            highestType = type;
          }
        });

        if (highestType.isNotEmpty) {
          return _verifyProduceType(highestType);
        }
      }
    }

    // If TensorFlow doesn't have reliable data, check if we have tentative_type
    if (results != null &&
        results.containsKey('tentative_type') &&
        results['tentative_type'] != null &&
        !results['tentative_type']
            .toString()
            .toLowerCase()
            .contains('unknown')) {
      return _verifyProduceType(results['tentative_type'].toString());
    }

    // Check if we have physical cues to work with
    String physicalCues = '';
    if (results != null && results.containsKey('detected_physical_cues')) {
      physicalCues =
          (results['detected_physical_cues'] ?? '').toString().toLowerCase();
    } else if (results != null && results.containsKey('Physical Cues')) {
      physicalCues = (results['Physical Cues'] ?? '').toString().toLowerCase();
    }

    // Parse shape information to help with identification
    bool isRound = physicalCues.contains('round') ||
        physicalCues.contains('circular') ||
        physicalCues.contains('spherical');
    bool isElongated = physicalCues.contains('elongated') ||
        physicalCues.contains('long') ||
        physicalCues.contains('cylindrical');
    bool isBumpy = physicalCues.contains('bumpy') ||
        physicalCues.contains('rough') ||
        physicalCues.contains('irregular');
    bool isLeafy =
        physicalCues.contains('leaf') || physicalCues.contains('leaves');

    // Default produce types based on color, texture, and shape
    final String colorLower = color.toLowerCase();
    final String textureLower = texture.toLowerCase();

    // If we have more detailed color/texture/shape information, make a more accurate guess
    if (colorLower.isNotEmpty ||
        textureLower.isNotEmpty ||
        physicalCues.isNotEmpty) {
      // Green produce
      if (colorLower.contains('green')) {
        if (isRound && textureLower.contains('smooth')) {
          return 'Green Apple';
        } else if (isLeafy && textureLower.contains('soft')) {
          return 'Lettuce';
        } else if (isBumpy && textureLower.contains('firm')) {
          return 'Broccoli';
        } else if (isElongated && textureLower.contains('firm')) {
          return 'Cucumber';
        } else if (isRound && textureLower.contains('firm')) {
          return 'Watermelon';
        } else if (physicalCues.contains('waxy') ||
            physicalCues.contains('peel')) {
          return 'Avocado';
        } else if (isRound) {
          return 'Guava';
        } else {
          return 'Broccoli';
        }
      }
      // Red produce
      else if (colorLower.contains('red')) {
        if (isRound && textureLower.contains('smooth')) {
          return 'Apple';
        } else if (isRound && textureLower.contains('firm')) {
          return 'Tomato';
        } else if (isElongated) {
          return 'Red Pepper';
        } else {
          return 'Tomato';
        }
      }
      // Yellow produce
      else if (colorLower.contains('yellow')) {
        if (isElongated &&
            (textureLower.contains('soft') ||
                physicalCues.contains('curved'))) {
          return 'Banana';
        } else if (isRound && textureLower.contains('rough')) {
          return 'Lemon';
        } else if (isElongated && textureLower.contains('firm')) {
          return 'Corn';
        } else if (textureLower.contains('spiky') ||
            physicalCues.contains('spiky')) {
          return 'Pineapple';
        } else if (textureLower.contains('rough')) {
          return 'Jackfruit';
        } else {
          return 'Banana';
        }
      }
      // Orange colored produce
      else if (colorLower.contains('orange')) {
        if (isRound && textureLower.contains('rough')) {
          return 'Orange';
        } else if (isElongated && textureLower.contains('firm')) {
          return 'Carrot';
        } else if (isRound) {
          return 'Papaya';
        } else {
          return 'Orange';
        }
      }
      // Purple produce
      else if (colorLower.contains('purple')) {
        if (isElongated || textureLower.contains('smooth')) {
          return 'Eggplant';
        } else {
          return 'Eggplant';
        }
      }
      // Brown produce
      else if (colorLower.contains('brown')) {
        if (isRound && textureLower.contains('rough')) {
          return 'Potato';
        } else if (isBumpy) {
          return 'Potato';
        } else {
          return 'Potato';
        }
      }
      // White produce
      else if (colorLower.contains('white') || colorLower.contains('pale')) {
        if (isRound && textureLower.contains('firm')) {
          return 'Onion';
        } else if (textureLower.contains('firm')) {
          return 'Garlic';
        } else {
          return 'Onion';
        }
      }
    }

    // Check the texture if color didn't help
    if (textureLower.isNotEmpty) {
      if (textureLower.contains('smooth') && isRound) {
        return 'Apple';
      } else if (textureLower.contains('rough') && isRound) {
        return 'Orange';
      } else if (textureLower.contains('fuzzy')) {
        return 'Kiwi';
      } else if (textureLower.contains('spiky')) {
        return 'Pineapple';
      }
    }

    // If we still don't know, use the physical cues alone with more detailed matching
    if (physicalCues.isNotEmpty) {
      // Round/Spherical fruits and vegetables
      if (physicalCues.contains('round') ||
          physicalCues.contains('spherical')) {
        if (physicalCues.contains('stem') && physicalCues.contains('red')) {
          return 'Apple';
        } else if (physicalCues.contains('segment') ||
            physicalCues.contains('citrus')) {
          return 'Orange';
        } else if (physicalCues.contains('small') &&
            physicalCues.contains('red')) {
          return 'Cherry Tomato';
        } else if (physicalCues.contains('smooth') &&
            physicalCues.contains('red')) {
          return 'Tomato';
        } else if (physicalCues.contains('small') &&
            physicalCues.contains('purple')) {
          return 'Plum';
        } else if (physicalCues.contains('green') &&
            physicalCues.contains('hard')) {
          return 'Watermelon';
        } else if (physicalCues.contains('rough') &&
            physicalCues.contains('brown')) {
          return 'Potato';
        } else if (physicalCues.contains('papery') ||
            physicalCues.contains('layers')) {
          return 'Onion';
        } else {
          return 'Apple'; // Default for round objects
        }
      }
      // Elongated/cylindrical fruits and vegetables
      else if (physicalCues.contains('long') ||
          physicalCues.contains('elongated') ||
          physicalCues.contains('cylindrical')) {
        if (physicalCues.contains('yellow') ||
            physicalCues.contains('curved')) {
          return 'Banana';
        } else if (physicalCues.contains('green') &&
            physicalCues.contains('smooth')) {
          return 'Cucumber';
        } else if (physicalCues.contains('orange') ||
            physicalCues.contains('tapered')) {
          return 'Carrot';
        } else if (physicalCues.contains('purple') ||
            physicalCues.contains('glossy')) {
          return 'Eggplant';
        } else if (physicalCues.contains('cob') ||
            physicalCues.contains('kernel')) {
          return 'Corn';
        } else if (physicalCues.contains('pod') ||
            physicalCues.contains('bean')) {
          return 'String Beans';
        } else {
          return 'Banana'; // Default for elongated objects
        }
      }
      // Leafy vegetables
      else if (physicalCues.contains('leaf') ||
          physicalCues.contains('leaves') ||
          physicalCues.contains('leafy')) {
        if (physicalCues.contains('head') || physicalCues.contains('round')) {
          return 'Lettuce';
        } else if (physicalCues.contains('dark') &&
            physicalCues.contains('curly')) {
          return 'Kale';
        } else if (physicalCues.contains('flat') &&
            physicalCues.contains('green')) {
          return 'Spinach';
        } else if (physicalCues.contains('stalk') ||
            physicalCues.contains('stem')) {
          return 'Celery';
        } else {
          return 'Leafy Greens';
        }
      }
      // Berries and small fruits
      else if (physicalCues.contains('small') &&
          physicalCues.contains('fruit')) {
        if (physicalCues.contains('red') &&
            (physicalCues.contains('seeds') ||
                physicalCues.contains('pitted'))) {
          return 'Strawberry';
        } else if (physicalCues.contains('blue') ||
            physicalCues.contains('dark blue')) {
          return 'Blueberry';
        } else if (physicalCues.contains('red') &&
            physicalCues.contains('cluster')) {
          return 'Raspberry';
        } else if (physicalCues.contains('green') &&
            physicalCues.contains('bunch')) {
          return 'Green Grape';
        } else if (physicalCues.contains('purple') &&
            physicalCues.contains('bunch')) {
          return 'Red Grape';
        } else {
          return 'Berry';
        }
      }
      // Unique physical features
      else if (physicalCues.contains('spiky') ||
          physicalCues.contains('crown')) {
        return 'Pineapple';
      } else if (physicalCues.contains('fuzzy') &&
          physicalCues.contains('brown')) {
        return 'Kiwi';
      } else if (physicalCues.contains('stem') &&
          physicalCues.contains('red')) {
        return 'Apple';
      } else if (physicalCues.contains('peel') &&
          physicalCues.contains('yellow')) {
        return 'Banana';
      } else if (physicalCues.contains('floret') ||
          physicalCues.contains('tree-like')) {
        return 'Broccoli';
      } else if (physicalCues.contains('rough') &&
          physicalCues.contains('netted')) {
        return 'Cantaloupe';
      }
    }

    // As a last resort, check if any common produce names appear in the analysis text
    if (results != null) {
      for (String key in [
        'detailed_analysis',
        'gemini_analysis',
        'gemini_result',
        'analysis_text'
      ]) {
        if (results.containsKey(key) && results[key] != null) {
          String analysisText = results[key].toString().toLowerCase();

          // First look for specific variety mentions with context patterns
          Map<Pattern, String> varietyPatterns = {
            RegExp(r'\bgranny smith\b|\bgreen apple\b'): 'Green Apple',
            RegExp(r'\bhoneycrisp\b|\bfuji\b|\bgala\b|\bred delicious\b|\bred apple\b'):
                'Red Apple',
            RegExp(r'\bcherry tomato\b|\bsmall tomato\b|\btomato cluster\b'):
                'Cherry Tomato',
            RegExp(r'\broma tomato\b|\bplum tomato\b|\blarge tomato\b'):
                'Tomato',
            RegExp(r'\bbell pepper\b|\bsweet pepper\b|\bcapsicum\b'):
                'Bell Pepper',
            RegExp(r'\bred bell pepper\b|\bred capsicum\b'): 'Red Bell Pepper',
            RegExp(r'\bgreen bell pepper\b|\bgreen capsicum\b'):
                'Green Bell Pepper',
            RegExp(r'\byellow bell pepper\b|\byellow capsicum\b'):
                'Yellow Bell Pepper',
            RegExp(r'\bhass avocado\b'): 'Avocado',
            RegExp(r'\bred cabbage\b'): 'Red Cabbage',
            RegExp(r'\biceberg lettuce\b'): 'Iceberg Lettuce',
            RegExp(r'\bromaine lettuce\b'): 'Romaine Lettuce',
            RegExp(r'\bbutternut squash\b'): 'Butternut Squash',
            RegExp(r'\bacorn squash\b'): 'Acorn Squash',
            RegExp(r'\bsweet potato\b|\byam\b'): 'Sweet Potato',
            RegExp(r'\bspring onion\b|\bgreen onion\b|\bscallion\b'):
                'Spring Onion',
          };

          // Check each pattern against the analysis text
          for (var pattern in varietyPatterns.keys) {
            if (pattern.allMatches(analysisText).isNotEmpty) {
              return varietyPatterns[pattern]!;
            }
          }

          // Then check for generic produce names with word boundary matching
          // for more accurate detection
          List<String> produceNames = [
            'apple',
            'banana',
            'orange',
            'tomato',
            'potato',
            'carrot',
            'broccoli',
            'lettuce',
            'cucumber',
            'eggplant',
            'aubergine',
            'avocado',
            'mango',
            'papaya',
            'pineapple',
            'watermelon',
            'strawberry',
            'blueberry',
            'raspberry',
            'kiwi',
            'grape',
            'grapefruit',
            'lemon',
            'lime',
            'coconut',
            'pear',
            'peach',
            'plum',
            'apricot',
            'pomegranate',
            'persimmon',
            'corn',
            'maize',
            'okra',
            'squash',
            'zucchini',
            'beans',
            'pepper',
            'chili',
            'cabbage',
            'kale',
            'spinach',
            'celery',
            'garlic',
            'onion',
            'shallot',
            'leek',
            'asparagus',
            'artichoke'
          ];

          // Use word boundary matching for more precise detection
          for (String produceName in produceNames) {
            if (RegExp(r'\b' + produceName + r'\b').hasMatch(analysisText)) {
              return _verifyProduceType(produceName);
            }
          }
        }
      }
    }

    // If we have no information at all, return a random common fruit instead of always Apple
    List<String> commonProduce = [
      'Apple',
      'Banana',
      'Orange',
      'Tomato',
      'Potato',
      'Carrot',
      'Broccoli',
      'Lettuce'
    ];

    // Use a simple deterministic approach to pick one based on the timestamp
    int index = DateTime.now().millisecondsSinceEpoch % commonProduce.length;
    return commonProduce[index];
  }

  // Determine produce category based on type
  String _determineProduceCategory(String produceType) {
    final String type = produceType.toLowerCase();

    // List of common fruits
    final List<String> commonFruits = [
      'watermelon',
      'papaya',
      'pineapple',
      'guava',
      'jackfruit',
      'mango',
      'apple',
      'banana',
      'orange',
      'grape',
      'strawberry',
      'melon'
    ];

    // List of common vegetables
    final List<String> commonVegetables = [
      'corn',
      'eggplant',
      'okra',
      'squash',
      'beans',
      'carrot',
      'potato',
      'onion',
      'garlic',
      'tomato',
      'lettuce',
      'cabbage',
      'broccoli'
    ];

    // Check if type matches any fruit
    if (commonFruits.any((fruit) => type.contains(fruit))) {
      return 'Fruit';
    }

    // Check if type matches any vegetable
    if (commonVegetables.any((vegetable) => type.contains(vegetable))) {
      return 'Vegetable';
    }

    // Default to 'Fruit' when type doesn't match any known produce
    return 'Fruit';
  }

  // Validate and format size to standard format
  String _validateAndFormatSize(String sizeText, String produceType) {
    // Default value for each produce type
    final Map<String, String> defaultSizes = {
      'watermelon': '20-30 cm',
      'papaya': '15-25 cm',
      'pineapple': '20-30 cm',
      'guava': '5-8 cm',
      'jackfruit': '30-50 cm',
      'corn': '15-25 cm',
      'eggplant': '10-15 cm',
      'okra': '5-10 cm',
      'squash': '20-30 cm',
      'beans': '10-20 cm',
    };

    // Try to standardize the format
    if (sizeText.contains('cm') || sizeText.contains('centimeter')) {
      // Already has units, just normalize format
      return sizeText
          .replaceAll('centimeter', 'cm')
          .replaceAll('centimeters', 'cm');
    }

    // Check if size is just a number
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(sizeText.trim())) {
      return '${sizeText.trim()} cm';
    }

    // Check for default size based on produce type
    for (var key in defaultSizes.keys) {
      if (produceType.toLowerCase().contains(key)) {
        return defaultSizes[key]!;
      }
    }

    return 'Unknown';
  }

  // Map color to standard dataset values
  String _mapColorToDataset(String colorText) {
    // Normalize the color text
    String normalizedColor = colorText.toLowerCase().trim();

    // Map for common color descriptions
    Map<String, String> colorMapping = {
      'red': 'Red',
      'green': 'Green',
      'yellow': 'Yellow',
      'orange': 'Orange',
      'purple': 'Purple',
      'brown': 'Brown',
      'pink': 'Pink',
      'white': 'White',
    };

    // Check for color matches
    for (var key in colorMapping.keys) {
      if (normalizedColor.contains(key)) {
        return colorMapping[key]!;
      }
    }

    // For more complex descriptions
    if (normalizedColor.contains('yellowish') ||
        normalizedColor.contains('pale yellow')) {
      return 'Light Yellow';
    }

    if (normalizedColor.contains('dark green')) {
      return 'Dark Green';
    }

    if (normalizedColor.contains('light green')) {
      return 'Light Green';
    }

    // If no match found, use original value with first letter capitalized
    if (colorText.isNotEmpty) {
      return colorText.substring(0, 1).toUpperCase() + colorText.substring(1);
    }

    return 'Unknown';
  }

  // Map texture to standard dataset values
  String _mapTextureToDataset(String textureText) {
    // Normalize the texture text
    String normalizedTexture = textureText.toLowerCase().trim();

    // Map for common texture descriptions
    Map<String, String> textureMapping = {
      'smooth': 'Smooth',
      'rough': 'Rough',
      'soft': 'Soft',
      'hard': 'Firm',
      'firm': 'Firm',
      'bumpy': 'Bumpy',
      'fuzzy': 'Fuzzy',
      'spiky': 'Spiky',
      'sticky': 'Sticky',
    };

    // Check for texture matches
    for (var key in textureMapping.keys) {
      if (normalizedTexture.contains(key)) {
        return textureMapping[key]!;
      }
    }

    // If no match found, use original value with first letter capitalized
    if (textureText.isNotEmpty) {
      return textureText.substring(0, 1).toUpperCase() +
          textureText.substring(1);
    }

    return 'Unknown';
  }

  // Map physical cues to standard dataset values
  String _mapPhysicalCuesToDataset(String cuesText) {
    if (cuesText.isEmpty) return 'Unknown';

    // Just use the original cues with improved formatting
    String formatted = cuesText.trim();

    // Capitalize first letter if not already capitalized
    if (formatted.isNotEmpty && formatted[0].toLowerCase() == formatted[0]) {
      formatted =
          formatted.substring(0, 1).toUpperCase() + formatted.substring(1);
    }

    return formatted;
  }

  // Preprocess ML result text for better matching
  String _preprocessMlResult(String mlResult) {
    // Convert to lowercase for consistent matching
    String cleanResult = mlResult.toLowerCase();

    // Check for key words that indicate ripeness state
    if (cleanResult.contains('unripe') ||
        cleanResult.contains('not ready') ||
        cleanResult.contains('too early') ||
        cleanResult.contains('wait longer')) {
      return 'unripe';
    }

    if (cleanResult.contains('ready for harvest') ||
        cleanResult.contains('optimal') ||
        cleanResult.contains('ideal') ||
        cleanResult.contains('good time')) {
      return 'ready_for_harvest';
    }

    if (cleanResult.contains('overripe') ||
        cleanResult.contains('too late') ||
        cleanResult.contains('past prime')) {
      return 'overripe';
    }

    // Default case - default to ready for harvest when uncertain
    return 'ready_for_harvest';
  }

  // Map ripeness state to standard values
  String _mapRipenessState(String preprocessedResult) {
    // We already preprocessed the string to one of these values
    if (preprocessedResult == 'unripe' ||
        preprocessedResult == 'ready_for_harvest' ||
        preprocessedResult == 'overripe') {
      return preprocessedResult;
    }

    // Additional checks for common text patterns
    if (preprocessedResult.toLowerCase().contains('not ready') ||
        preprocessedResult.toLowerCase().contains('unripe')) {
      return 'unripe';
    }

    if (preprocessedResult.toLowerCase().contains('ready') ||
        preprocessedResult.toLowerCase().contains('optimal') ||
        preprocessedResult.toLowerCase().contains('yes')) {
      return 'ready_for_harvest';
    }

    if (preprocessedResult.toLowerCase().contains('over') ||
        preprocessedResult.toLowerCase().contains('past')) {
      return 'overripe';
    }

    // Default to ready for harvest when uncertain
    return 'ready_for_harvest';
  }

  // Calculate overall confidence score
  double _calculateOverallConfidence(Map<String, dynamic> results) {
    // Start with a medium confidence
    double confidence = 0.5;

    // Check for prediction_confidence or detection_confidence from newer AI service
    if (results.containsKey('detection_confidence')) {
      String confidenceLevel =
          results['detection_confidence'].toString().toLowerCase();
      if (confidenceLevel.contains('high')) {
        confidence = 0.9;
      } else if (confidenceLevel.contains('medium')) {
        confidence = 0.7;
      } else if (confidenceLevel.contains('low')) {
        confidence = 0.4;
      } else if (confidenceLevel.contains('very')) {
        confidence = confidenceLevel.contains('very high') ? 0.95 : 0.25;
      }
      debugPrint('Using detection_confidence: $confidenceLevel -> $confidence');
    } else if (results.containsKey('prediction_confidence')) {
      String confidenceLevel =
          results['prediction_confidence'].toString().toLowerCase();
      if (confidenceLevel.contains('high')) {
        confidence = 0.9;
      } else if (confidenceLevel.contains('medium')) {
        confidence = 0.7;
      } else if (confidenceLevel.contains('low')) {
        confidence = 0.4;
      }
      debugPrint(
          'Using prediction_confidence: $confidenceLevel -> $confidence');
    }

    // If there's a tensorflow confidence score, use that
    if (results.containsKey('tensorflow_confidence') &&
        results['tensorflow_confidence'] is double) {
      confidence = results['tensorflow_confidence'];
      debugPrint('Using tensorflow_confidence: $confidence');
    }

    // If there's a combined confidence score, use that instead
    if (results.containsKey('combined_confidence') &&
        results['combined_confidence'] is double) {
      confidence = results['combined_confidence'];
      debugPrint('Using combined_confidence: $confidence');
    }

    // NEW: Adjust confidence based on model agreement
    if (results.containsKey('models_agree') &&
        results['models_agree'] == true) {
      confidence += 0.15; // Significant boost when models agree
      debugPrint('Boosting confidence due to model agreement: +0.15');
    }

    // NEW: Adjust confidence based on physical characteristics matching expected values
    if (results.containsKey('detected_type') &&
        results.containsKey('detected_color') &&
        results.containsKey('detected_texture')) {
      String detectedType = results['detected_type'].toString().toLowerCase();
      String detectedColor = results['detected_color'].toString().toLowerCase();
      String detectedTexture =
          results['detected_texture'].toString().toLowerCase();

      // Check color matches for specific produce types
      bool colorMatches = false;
      if ((detectedType.contains('apple') &&
              (detectedColor.contains('red') ||
                  detectedColor.contains('green') ||
                  detectedColor.contains('yellow'))) ||
          (detectedType.contains('banana') &&
              (detectedColor.contains('yellow') ||
                  detectedColor.contains('green'))) ||
          (detectedType.contains('tomato') &&
              (detectedColor.contains('red') ||
                  detectedColor.contains('green'))) ||
          (detectedType.contains('mango') &&
              (detectedColor.contains('green') ||
                  detectedColor.contains('yellow') ||
                  detectedColor.contains('red')))) {
        colorMatches = true;
        confidence += 0.05;
        debugPrint('Color matches expected for $detectedType: +0.05');
      }

      // Check texture matches for specific produce types
      bool textureMatches = false;
      if ((detectedType.contains('apple') &&
              detectedTexture.contains('firm')) ||
          (detectedType.contains('banana') &&
              detectedTexture.contains('smooth')) ||
          (detectedType.contains('tomato') &&
              detectedTexture.contains('smooth')) ||
          (detectedType.contains('avocado') &&
              (detectedTexture.contains('firm') ||
                  detectedTexture.contains('soft')))) {
        textureMatches = true;
        confidence += 0.05;
        debugPrint('Texture matches expected for $detectedType: +0.05');
      }

      // If both color and texture match expected values, add extra confidence
      if (colorMatches && textureMatches) {
        confidence += 0.05;
        debugPrint('Both color and texture match: additional +0.05');
      }
    }

    // NEW: Adjust confidence if result is consistent with ripeness rules
    if (results.containsKey('detected_type') &&
        results.containsKey('ripeness_rule_match') &&
        results['ripeness_rule_match'] == true) {
      confidence += 0.1;
      debugPrint('Result matches ripeness rules: +0.1');
    }

    // NEW: Penalize confidence for low quality images
    if (results.containsKey('low_quality_image') &&
        results['low_quality_image'] == true) {
      confidence -= 0.15;
      debugPrint('Low quality image: -0.15');
    }

    // Limit confidence to the range [0.1, 0.98]
    if (confidence < 0.1) confidence = 0.1;
    if (confidence > 0.98) confidence = 0.98;

    debugPrint('Final calculated confidence: $confidence');
    return confidence;
  }

  // Get confidence level text
  String _getConfidenceLevel(double confidence) {
    if (confidence < 0.3) return 'Very Low';
    if (confidence < 0.5) return 'Low';
    if (confidence < 0.7) return 'Moderate';
    if (confidence < 0.9) return 'High';
    return 'Very High';
  }

  // Organize results in a logical order for display
  void _organizeResults() {
    // Create a temporary map with ordered results
    final Map<String, String> orderedResults = {};

    // Define the order of fields
    final List<String> fieldOrder = [
      'Category',
      'Type',
      'Size',
      'Texture',
      'Color',
      'Physical Cues',
      'Ready for Harvest',
      'Ripeness',
      'Harvest Analysis',
      'Analysis Confidence',
      'Note',
    ];

    // Replace any "Unknown" values with appropriate defaults
    if (_parsedResults.containsKey('Type')) {
      final String produceType = _parsedResults['Type']!;

      if (_parsedResults.containsKey('Size') &&
          (_parsedResults['Size'] == 'Unknown' ||
              _parsedResults['Size']!.isEmpty)) {
        _parsedResults['Size'] = _getDefaultSizeForType(produceType);
      }

      if (_parsedResults.containsKey('Color') &&
          (_parsedResults['Color'] == 'Unknown' ||
              _parsedResults['Color']!.isEmpty)) {
        _parsedResults['Color'] = _getDefaultColorForType(produceType);
      }

      if (_parsedResults.containsKey('Texture') &&
          (_parsedResults['Texture'] == 'Unknown' ||
              _parsedResults['Texture']!.isEmpty)) {
        _parsedResults['Texture'] = _getDefaultTextureForType(produceType);
      }

      if (_parsedResults.containsKey('Physical Cues') &&
          (_parsedResults['Physical Cues'] == 'Unknown' ||
              _parsedResults['Physical Cues']!.isEmpty)) {
        _parsedResults['Physical Cues'] =
            _getDefaultPhysicalCuesForType(produceType);
      }
    }

    // Copy fields in the defined order
    for (String field in fieldOrder) {
      if (_parsedResults.containsKey(field)) {
        orderedResults[field] = _parsedResults[field]!;
      }
    }

    // Add any remaining fields not in the order list
    for (var entry in _parsedResults.entries) {
      if (!orderedResults.containsKey(entry.key)) {
        orderedResults[entry.key] = entry.value;
      }
    }

    // Replace the original map with the ordered one
    _parsedResults.clear();
    _parsedResults.addAll(orderedResults);
  }

  // Update the ripeness calculation based on harvest readiness
  void _updateRipenessPercentage(Map<String, dynamic> results) {
    if (_parsedResults.containsKey('Ready for Harvest')) {
      String harvestState = _parsedResults['Ready for Harvest']!;
      int daysUntilHarvest = _predictDaysUntilHarvest(results);

      // Map text descriptions to percentages based on the detailed analysis
      if (harvestState.toLowerCase().contains('unripe')) {
        _parsedResults['Ripeness'] = '25% - Unripe';
      } else if (harvestState.toLowerCase().contains('partially') ||
          harvestState.toLowerCase().contains('semi')) {
        _parsedResults['Ripeness'] = '50% - Partially ripe';
      } else if (harvestState.toLowerCase().contains('mostly') ||
          harvestState.toLowerCase().contains('nearly')) {
        _parsedResults['Ripeness'] = '75% - Nearly ripe';
      } else if (harvestState.toLowerCase().contains('ready') &&
          !harvestState.toLowerCase().contains('not ready')) {
        _parsedResults['Ripeness'] = '100% - Fully ripe';
      } else if (harvestState.toLowerCase().contains('over')) {
        _parsedResults['Ripeness'] = '120% - Overripe';
      }

      // Add days until harvest to the ripeness display
      if (_parsedResults['Ripeness'] != null) {
        if (daysUntilHarvest > 0) {
          _parsedResults['Ripeness'] =
              '${_parsedResults['Ripeness']!} (Estimated $daysUntilHarvest days until harvest)';
        } else if (daysUntilHarvest == 0) {
          _parsedResults['Ripeness'] =
              '${_parsedResults['Ripeness']!} (Ready for harvest now)';
        } else {
          _parsedResults['Ripeness'] =
              '${_parsedResults['Ripeness']!} (Past optimal harvest time)';
        }
      }
    }
  }

  // Helper to get default size for a given type
  String _getDefaultSizeForType(String type) {
    final String typeLower = type.toLowerCase();

    // Common sizes for fruits
    if (typeLower.contains('apple')) {
      return '7-10 cm';
    }
    if (typeLower.contains('banana')) {
      return '15-25 cm';
    }
    if (typeLower.contains('orange')) {
      return '6-10 cm';
    }
    if (typeLower.contains('watermelon')) {
      return '20-30 cm';
    }
    if (typeLower.contains('papaya')) {
      return '15-25 cm';
    }
    if (typeLower.contains('pineapple')) {
      return '20-30 cm';
    }
    if (typeLower.contains('guava')) {
      return '5-8 cm';
    }
    if (typeLower.contains('jackfruit')) {
      return '30-50 cm';
    }
    if (typeLower.contains('lemon')) {
      return '5-8 cm';
    }
    if (typeLower.contains('mango')) {
      return '10-15 cm';
    }

    // Common sizes for vegetables
    if (typeLower.contains('corn')) {
      return '15-25 cm';
    }
    if (typeLower.contains('eggplant')) {
      return '10-15 cm';
    }
    if (typeLower.contains('okra')) {
      return '5-10 cm';
    }
    if (typeLower.contains('squash')) {
      return '20-30 cm';
    }
    if (typeLower.contains('tomato')) {
      return '5-8 cm';
    }
    if (typeLower.contains('potato')) {
      return '5-10 cm';
    }
    if (typeLower.contains('onion')) {
      return '5-10 cm';
    }
    if (typeLower.contains('carrot')) {
      return '10-20 cm';
    }
    if (typeLower.contains('broccoli')) {
      return '10-20 cm';
    }
    if (typeLower.contains('lettuce')) {
      return '15-25 cm';
    }

    // Default size for unknown types
    return '10-15 cm';
  }

  // Helper to get default color for a given type
  String _getDefaultColorForType(String type) {
    final String typeLower = type.toLowerCase();

    // Common colors for fruits
    if (typeLower.contains('apple')) {
      if (typeLower.contains('green')) {
        return 'Green';
      }
      return 'Red';
    }
    if (typeLower.contains('banana')) {
      return 'Yellow';
    }
    if (typeLower.contains('orange')) {
      return 'Orange';
    }
    if (typeLower.contains('watermelon')) {
      return 'Green';
    }
    if (typeLower.contains('papaya')) {
      return 'Green/Yellow';
    }
    if (typeLower.contains('pineapple')) {
      return 'Yellow/Brown';
    }
    if (typeLower.contains('guava')) {
      return 'Green';
    }
    if (typeLower.contains('jackfruit')) {
      return 'Green/Yellow';
    }
    if (typeLower.contains('lemon')) {
      return 'Yellow';
    }
    if (typeLower.contains('mango')) {
      return 'Green/Yellow/Red';
    }

    // Common colors for vegetables
    if (typeLower.contains('corn')) {
      return 'Yellow';
    }
    if (typeLower.contains('eggplant')) {
      return 'Purple';
    }
    if (typeLower.contains('okra')) {
      return 'Green';
    }
    if (typeLower.contains('squash')) {
      return 'Green/Yellow';
    }
    if (typeLower.contains('tomato')) {
      return 'Red';
    }
    if (typeLower.contains('potato')) {
      return 'Brown';
    }
    if (typeLower.contains('onion')) {
      return 'White/Purple';
    }
    if (typeLower.contains('carrot')) {
      return 'Orange';
    }
    if (typeLower.contains('broccoli')) {
      return 'Green';
    }
    if (typeLower.contains('lettuce')) {
      return 'Green';
    }

    // Default color for unknown types
    return 'Green';
  }

  // Helper to get default texture for a given type
  String _getDefaultTextureForType(String type) {
    final String typeLower = type.toLowerCase();

    // Common textures for fruits
    if (typeLower.contains('apple')) {
      return 'Smooth';
    }
    if (typeLower.contains('banana')) {
      return 'Smooth';
    }
    if (typeLower.contains('orange')) {
      return 'Rough';
    }
    if (typeLower.contains('watermelon')) {
      return 'Smooth';
    }
    if (typeLower.contains('papaya')) {
      return 'Smooth';
    }
    if (typeLower.contains('pineapple')) {
      return 'Rough';
    }
    if (typeLower.contains('guava')) {
      return 'Smooth';
    }
    if (typeLower.contains('jackfruit')) {
      return 'Rough';
    }
    if (typeLower.contains('lemon')) {
      return 'Rough';
    }
    if (typeLower.contains('mango')) {
      return 'Smooth';
    }

    // Common textures for vegetables
    if (typeLower.contains('corn')) {
      return 'Firm';
    }
    if (typeLower.contains('eggplant')) {
      return 'Smooth';
    }
    if (typeLower.contains('okra')) {
      return 'Fuzzy';
    }
    if (typeLower.contains('squash')) {
      return 'Firm';
    }
    if (typeLower.contains('tomato')) {
      return 'Smooth';
    }
    if (typeLower.contains('potato')) {
      return 'Rough';
    }
    if (typeLower.contains('onion')) {
      return 'Papery';
    }
    if (typeLower.contains('carrot')) {
      return 'Firm';
    }
    if (typeLower.contains('broccoli')) {
      return 'Bumpy';
    }
    if (typeLower.contains('lettuce')) {
      return 'Leafy';
    }

    // Default texture for unknown types
    return 'Smooth';
  }

  // Helper to get default physical cues for a given type
  String _getDefaultPhysicalCuesForType(String type) {
    final String typeLower = type.toLowerCase();

    // Common physical cues for fruits
    if (typeLower.contains('apple')) {
      return 'Round shape';
    }
    if (typeLower.contains('banana')) {
      return 'Curved elongated shape';
    }
    if (typeLower.contains('orange')) {
      return 'Round with dimpled skin';
    }
    if (typeLower.contains('watermelon')) {
      return 'Large oval shape with striped pattern';
    }
    if (typeLower.contains('papaya')) {
      return 'Oblong shape with seeds inside';
    }
    if (typeLower.contains('pineapple')) {
      return 'Prickly exterior with crown of leaves';
    }
    if (typeLower.contains('guava')) {
      return 'Small round fruit with small seeds';
    }
    if (typeLower.contains('jackfruit')) {
      return 'Large with spiky exterior';
    }
    if (typeLower.contains('lemon')) {
      return 'Oval citrus fruit with pointed ends';
    }
    if (typeLower.contains('mango')) {
      return 'Oblong fruit with large seed';
    }

    // Common physical cues for vegetables
    if (typeLower.contains('corn')) {
      return 'Cylindrical with husk and silk';
    }
    if (typeLower.contains('eggplant')) {
      return 'Oblong or oval shape with glossy skin';
    }
    if (typeLower.contains('okra')) {
      return 'Elongated pods with ridge patterns';
    }
    if (typeLower.contains('squash')) {
      return 'Varied shapes with thick rind';
    }
    if (typeLower.contains('tomato')) {
      return 'Round or oval with smooth skin';
    }
    if (typeLower.contains('potato')) {
      return 'Oblong with eyes on the surface';
    }
    if (typeLower.contains('onion')) {
      return 'Round layered bulb';
    }
    if (typeLower.contains('carrot')) {
      return 'Elongated root vegetable with tapering end';
    }
    if (typeLower.contains('broccoli')) {
      return 'Tree-like florets on thick stem';
    }
    if (typeLower.contains('lettuce')) {
      return 'Leafy head with ruffled leaves';
    }

    // Default physical cues for unknown types
    return 'Distinctive shape and appearance';
  }

  // Get confidence color based on level
  Color _getConfidenceColor(String confidenceText) {
    if (confidenceText.toLowerCase().contains('high') ||
        (confidenceText.contains('%') &&
            double.tryParse(confidenceText.split('%')[0]) != null &&
            double.parse(confidenceText.split('%')[0]) > 75)) {
      return Colors.green[700]!;
    } else if (confidenceText.toLowerCase().contains('medium') ||
        (confidenceText.contains('%') &&
            double.tryParse(confidenceText.split('%')[0]) != null &&
            double.parse(confidenceText.split('%')[0]) > 40)) {
      return Colors.orange[700]!;
    } else {
      return Colors.red[700]!;
    }
  }

  // Get confidence value as a fraction for progress indicators
  double _getConfidenceValue(String confidenceText) {
    if (confidenceText.contains('%')) {
      final percentage = double.tryParse(confidenceText.split('%')[0]);
      if (percentage != null) return (percentage.clamp(0, 100)) / 100;
    }

    return 100.0; // Default to full if parsing fails
  }

  // Method to get action recommendation based on harvest status
  String _getActionRecommendation(String harvestState) {
    final lowerCaseState = harvestState.toLowerCase();
    final String type = _detectedType.toLowerCase();

    if (lowerCaseState.contains('unripe') ||
        lowerCaseState.contains('not ready')) {
      // Specific recommendations for unripe produce
      if (type.contains('banana')) {
        return 'Store at room temperature and wait for yellow color with slight brown spots.';
      } else if (type.contains('tomato')) {
        return 'Keep at room temperature away from direct sunlight until red and slightly soft.';
      } else if (type.contains('avocado')) {
        return 'Store at room temperature until skin darkens and yields to gentle pressure.';
      } else if (type.contains('mango') || type.contains('papaya')) {
        return 'Keep at room temperature until fruit softens and develops a sweet aroma.';
      } else if (type.contains('pineapple')) {
        return 'Wait for the fruit to develop a golden color and sweet tropical aroma.';
      } else {
        return 'Continue monitoring for ripeness signs: color changes, softening, and aroma development.';
      }
    } else if (lowerCaseState.contains('ready') ||
        lowerCaseState.contains('harvest')) {
      // Specific recommendations for ready produce
      if (type.contains('banana')) {
        return 'Harvest now. For best flavor, pick when yellow with small brown spots.';
      } else if (type.contains('tomato')) {
        return 'Perfect time to harvest. Pick gently to avoid damaging the plant.';
      } else if (type.contains('avocado')) {
        return 'Ready to pick. Use within 1-2 days for optimal ripeness.';
      } else if (type.contains('mango') || type.contains('papaya')) {
        return 'Harvest now. Fruit should be slightly soft with sweet aroma.';
      } else if (type.contains('pineapple')) {
        return 'Optimal time to harvest. Cut at base with sharp knife.';
      } else {
        return 'Perfect time to harvest for optimal flavor and texture.';
      }
    } else if (lowerCaseState.contains('over') ||
        lowerCaseState.contains('past')) {
      // Specific recommendations for overripe produce
      if (type.contains('banana')) {
        return 'Best for banana bread or smoothies. Store in refrigerator to slow ripening.';
      } else if (type.contains('tomato')) {
        return 'Use immediately in cooked dishes. Store in refrigerator if needed.';
      } else if (type.contains('avocado')) {
        return 'Use immediately. Best for guacamole or other mashed preparations.';
      } else if (type.contains('mango') || type.contains('papaya')) {
        return 'Best used in smoothies or cooking. Store in refrigerator.';
      } else if (type.contains('pineapple')) {
        return 'Use soon in juices or cooking. May be more acidic than optimal.';
      } else {
        return 'Past optimal harvest time but may still be usable. Check for spoilage.';
      }
    } else {
      // Generic monitoring advice
      if (type.contains('banana') ||
          type.contains('avocado') ||
          type.contains('mango')) {
        return 'Monitor color changes and softness daily.';
      } else if (type.contains('tomato') || type.contains('bell pepper')) {
        return 'Check color development and firmness regularly.';
      } else if (type.contains('pineapple') || type.contains('papaya')) {
        return 'Watch for color changes and check aroma development.';
      } else {
        return 'Monitor closely and check for ripeness indicators daily.';
      }
    }
  }

  // Ensure the detailed analysis matches the ripeness status displayed
  String _ensureAnalysisMatchesStatus(String analysis) {
    // Get the current harvest readiness status
    final String harvestStatus = _parsedResults['Ready for Harvest'] ?? '';
    final String lowerAnalysis = analysis.toLowerCase();

    // Debug logging to trace actual values
    debugPrint('Current harvest status value: "$harvestStatus"');

    // Check if there's a contradiction between status and analysis text
    bool statusIsReady = harvestStatus.toLowerCase().contains('ready') &&
        !harvestStatus.toLowerCase().contains('not ready');

    bool statusIsUnripe = harvestStatus.toLowerCase().contains('not ready') ||
        harvestStatus.toLowerCase() == 'unripe';

    bool statusIsOverripe = harvestStatus.toLowerCase().contains('overripe') ||
        harvestStatus.toLowerCase().contains('over-ripe');

    // Additional debug logging
    debugPrint(
        'Status is ready: $statusIsReady, Status is unripe: $statusIsUnripe, Status is overripe: $statusIsOverripe');

    // Check what the analysis text indicates
    bool analysisIndicatesNotReady = lowerAnalysis.contains('not ready') ||
        lowerAnalysis.contains('unripe') ||
        lowerAnalysis.contains('needs more time') ||
        lowerAnalysis.contains('too early');

    bool analysisIndicatesReady = lowerAnalysis.contains('ready for harvest') ||
        lowerAnalysis.contains('ready to be harvested') ||
        lowerAnalysis.contains('can be harvested') ||
        lowerAnalysis.contains('optimal time') ||
        (lowerAnalysis.contains('ripe') &&
            !lowerAnalysis.contains('unripe') &&
            !lowerAnalysis.contains('not ready'));

    bool analysisIndicatesOverripe = lowerAnalysis.contains('overripe') ||
        lowerAnalysis.contains('over-ripe') ||
        lowerAnalysis.contains('over ripe') ||
        lowerAnalysis.contains('past its prime') ||
        lowerAnalysis.contains('too ripe');

    // Check if days until harvest information is already in the analysis text
    bool containsDaysInfo = lowerAnalysis.contains('days until harvest') ||
        lowerAnalysis.contains('days before harvest') ||
        lowerAnalysis.contains('harvest in') ||
        lowerAnalysis.contains('wait for') ||
        RegExp(r'ready in \d+ days').hasMatch(lowerAnalysis);

    // If the analysis is too brief or vague, enhance it with detailed information
    if (analysis.length < 100 || analysis == 'No detailed analysis available') {
      final String type = _detectedType.toLowerCase();
      String enhancedAnalysis = '';

      if (statusIsUnripe) {
        if (type.contains('tomato')) {
          enhancedAnalysis =
              "This tomato is not ready for harvest yet. The current color indicates it needs more time to develop full ripeness. Tomatoes begin green and gradually transition to their final color (red, yellow, or orange depending on variety) as they ripen. The texture is still firm, which is characteristic of unripe tomatoes. Continue to provide adequate sunlight and consistent watering for optimal development.";
        } else if (type.contains('banana')) {
          enhancedAnalysis =
              "This banana is still in its developmental stage and not yet ready for harvest. The green color indicates high starch content that has not yet converted to sugars. As bananas ripen, the green chlorophyll breaks down, revealing the yellow pigments beneath. For optimal ripening, keep at room temperature away from direct sunlight.";
        } else if (type.contains('apple')) {
          enhancedAnalysis =
              "This apple requires more time on the tree to develop optimal flavor, sugar content, and texture. The current state shows insufficient color development typical of mature apples of this variety. Harvesting too early will result in starchy, less flavorful fruit that won't properly develop even after picking.";
        } else if (type.contains('avocado')) {
          enhancedAnalysis =
              "This avocado is not yet harvest-ready. The firm texture and current skin color indicate it needs more time to mature. Avocados soften after harvesting, not on the tree, but they must reach maturity before picking for proper ripening afterward. Once harvested, store at room temperature to continue the ripening process.";
        } else {
          enhancedAnalysis =
              "This $_detectedType requires more time to develop optimal harvest characteristics. Continue monitoring for changes in color, texture, and size that are typical indicators of ripeness for this produce type.";
        }

        // Replace the original analysis
        analysis = enhancedAnalysis;
      } else if (statusIsReady) {
        if (type.contains('tomato')) {
          enhancedAnalysis =
              "This tomato has reached its optimal harvest stage. The color has fully developed, and the fruit yields slightly to gentle pressure without being soft. The skin is smooth and glossy, and there's a slight aroma at the stem end - all indicators of peak ripeness.";
        } else if (type.contains('banana')) {
          enhancedAnalysis =
              "This banana is at its ideal harvest stage. The yellow color indicates that starches have converted to sugars, providing optimal sweetness. The texture is firm but beginning to soften, which is perfect for consumption. No brown spots indicate it hasn't begun to overripen.";
        } else if (type.contains('apple')) {
          enhancedAnalysis =
              "This apple displays the characteristic color development for its variety and has reached optimal harvest maturity. The flesh is firm but not hard, and it should separate easily from the tree when gently twisted - indications that it has developed full flavor.";
        } else if (type.contains('avocado')) {
          enhancedAnalysis =
              "This avocado is ready for harvest. It shows appropriate skin color for its variety and yields slightly to gentle pressure without being soft or mushy. The stem end gives slightly when pressed, indicating the flesh has developed properly.";
        } else {
          enhancedAnalysis =
              "This $_detectedType displays the characteristic signs of harvest readiness. It has reached optimal development in terms of color, size, and texture for its type. Harvesting now will ensure the best flavor and storage quality.";
        }

        // Replace the original analysis
        analysis = enhancedAnalysis;
      }
    }

    // If the produce is not ready and we have days until harvest data, ensure it's prominently displayed
    if (statusIsUnripe &&
        _analysisResults.containsKey('days_until_harvest') &&
        !containsDaysInfo) {
      int days = _analysisResults['days_until_harvest'] as int;
      String daysInfo =
          '\n\n📅 HARVEST FORECAST: This $_detectedType will be ready for harvest in approximately $days days. ';

      // Add care instructions based on produce type
      final String type = _detectedType.toLowerCase();
      if (type.contains('tomato')) {
        daysInfo +=
            'Continue to provide adequate sunlight and water regularly. Look for progressive color change from green to red (or variety color) and slight softening.';
      } else if (type.contains('banana') ||
          type.contains('mango') ||
          type.contains('papaya')) {
        daysInfo +=
            'Keep at room temperature and away from direct sunlight to continue ripening. Monitor for color changes from green to yellow/orange and slight softening.';
      } else if (type.contains('apple')) {
        daysInfo +=
            'Monitor for complete color development, increasing sweetness, and slight give when pressed gently. The apple should develop more aromatic qualities as it approaches harvest readiness.';
      } else if (type.contains('avocado')) {
        daysInfo +=
            'Keep at room temperature to continue ripening. The skin will darken and the fruit will yield slightly to gentle pressure when ready.';
      } else if (type.contains('pepper') || type.contains('bell pepper')) {
        daysInfo +=
            'Monitor for full size development and thicker walls. For sweet peppers, allowing them to ripen fully enhances their sweetness and nutritional content.';
      } else {
        daysInfo +=
            'Continue monitoring for characteristic color changes, appropriate firmness, and size indicative of harvest readiness for this produce type.';
      }

      analysis = '$daysInfo\n\n$analysis';
    }

    // Add a clear harvest status at the beginning of the analysis if it's not already present
    if (!lowerAnalysis.contains('harvest status') &&
        !lowerAnalysis.contains('ready for harvest:') &&
        !lowerAnalysis.contains('ripeness:')) {
      String statusPrefix;
      if (statusIsReady) {
        statusPrefix = "Harvest Status: Ready for harvest\n\n";
      } else if (statusIsOverripe) {
        statusPrefix = "Harvest Status: Past optimal harvest time\n\n";
      } else if (statusIsUnripe) {
        // Include days until harvest in the status prefix if available
        if (_analysisResults.containsKey('days_until_harvest')) {
          int days = _analysisResults['days_until_harvest'] as int;
          statusPrefix =
              "Harvest Status: Not ready for harvest yet (estimated $days days until ready)\n\n";
        } else {
          statusPrefix = "Harvest Status: Not ready for harvest yet\n\n";
        }
      } else {
        statusPrefix = "";
      }

      analysis = statusPrefix + analysis;
    }

    // If there's a contradiction, correct the analysis text
    if (statusIsReady && analysisIndicatesNotReady && !analysisIndicatesReady) {
      debugPrint(
          'Fixing contradiction: Status says ready but analysis says not ready');

      // Replace contradicting phrases
      analysis = analysis
          .replaceAll(RegExp(r'not ready for harvest', caseSensitive: false),
              'ready for harvest')
          .replaceAll(RegExp(r'needs more time', caseSensitive: false),
              'has reached optimal ripeness')
          .replaceAll(
              RegExp(r'too early', caseSensitive: false), 'at the perfect time')
          .replaceAll(RegExp(r'unripe', caseSensitive: false), 'ripe');

      // If the text still indicates unripeness, add a correction
      if (analysis.toLowerCase().contains('not ready') ||
          analysis.toLowerCase().contains('needs more time')) {
        analysis =
            'This $_detectedType is ready for harvest. It has reached optimal ripeness with good color development and texture.\n\n$analysis';
      }
    }

    if (statusIsUnripe &&
        analysisIndicatesReady &&
        !analysisIndicatesNotReady) {
      debugPrint(
          'Fixing contradiction: Status says not ready but analysis says ready');

      // Replace contradicting phrases
      analysis = analysis
          .replaceAll(RegExp(r'ready for harvest', caseSensitive: false),
              'not yet ready for harvest')
          .replaceAll(RegExp(r'can be harvested', caseSensitive: false),
              'should wait before harvesting')
          .replaceAll(
              RegExp(r'optimal time', caseSensitive: false), 'still developing')
          .replaceAll(RegExp(r'ripe and ready', caseSensitive: false),
              'still ripening');

      // If the text still indicates ripeness, add a correction
      if (analysis.toLowerCase().contains('ready for harvest') ||
          analysis.toLowerCase().contains('can be harvested')) {
        final String type = _detectedType.toLowerCase();
        String specificGuidance = '';

        // Add crop-specific guidance
        if (type.contains('tomato')) {
          specificGuidance =
              " Look for progressive color change from green to red (or variety color) and slight softening. The fruit should have smooth skin and begin developing a sweet aroma as it approaches readiness.";
        } else if (type.contains('banana')) {
          specificGuidance =
              " The color should change from green to yellow with the green chlorophyll breaking down. The fruit will become slightly softer and develop a sweet aroma.";
        } else if (type.contains('apple')) {
          specificGuidance =
              " Look for development of characteristic variety color, increasing sweetness, and a slight give when gently pressed. The fruit should develop aromatic qualities.";
        } else if (type.contains('avocado')) {
          specificGuidance =
              " Monitor for skin color changes and texture that yields slightly to gentle pressure without being mushy.";
        } else {
          specificGuidance =
              " Continue monitoring for characteristic ripeness indicators for this specific crop type.";
        }

        // Add days until harvest information if available
        if (_analysisResults.containsKey('days_until_harvest')) {
          int days = _analysisResults['days_until_harvest'] as int;
          analysis =
              'This $_detectedType is not ready for harvest yet. It still needs about $days more days to develop fully.$specificGuidance\n\n$analysis';
        } else {
          analysis =
              'This $_detectedType is not ready for harvest yet. It still needs more time to develop fully.$specificGuidance\n\n$analysis';
        }
      }
    }

    if (statusIsOverripe && !analysisIndicatesOverripe) {
      debugPrint(
          'Fixing contradiction: Status says overripe but analysis doesn\'t');

      // Add overripe status if not mentioned
      if (!analysis.toLowerCase().contains('overripe') &&
          !analysis.toLowerCase().contains('over-ripe') &&
          !analysis.toLowerCase().contains('past its prime')) {
        analysis =
            'This $_detectedType is past its optimal harvest time and may be overripe. '
            'It should be used soon for best quality.\n\n$analysis';
      }
    }

    return analysis;
  }

  // Display the enhanced results from multiple AI models
  void _setFinalResults(Map<String, dynamic> results) {
    setState(() {
      _isAnalyzing = false;

      // Store the full results for later use
      _analysisResults = results;

      // Extract the prediction
      bool? unripePrediction = results['unripe_prediction'];
      String confidence = results['confidence'] ?? 'Medium';
      int? daysUntilHarvest = results['days_until_harvest'];

      // Set the detected type if available
      if (results.containsKey('detected_type') &&
          results['detected_type'] != null &&
          results['detected_type'].toString().isNotEmpty) {
        _detectedType = results['detected_type'];
        _parsedResults['Type'] = _detectedType;
      }

      // Set the harvest status based on the unripe prediction
      if (unripePrediction != null) {
        if (unripePrediction == true) {
          // Unripe
          _parsedResults['Ready for Harvest'] = 'not_ready';
          _parsedResults['Unripe Status'] = 'Yes';
        } else {
          // Ripe or overripe
          if (results.containsKey('overripe') && results['overripe'] == true) {
            _parsedResults['Ready for Harvest'] = 'overripe';
            _parsedResults['Unripe Status'] = 'No (Overripe)';
          } else {
            _parsedResults['Ready for Harvest'] = 'ready_for_harvest';
            _parsedResults['Unripe Status'] = 'No (Ripe)';
          }
        }
      } else {
        // Default to not ready if we couldn't determine
        _parsedResults['Ready for Harvest'] = 'unknown';
        _parsedResults['Unripe Status'] = 'Unknown';
      }

      // Add confidence level
      _parsedResults['Confidence'] = confidence;

      // Add days until harvest if available
      if (daysUntilHarvest != null) {
        if (daysUntilHarvest > 0) {
          _parsedResults['Days Until Harvest'] = '$daysUntilHarvest days';
        } else if (daysUntilHarvest == 0) {
          _parsedResults['Days Until Harvest'] = 'Ready now';
        } else if (daysUntilHarvest < 0) {
          _parsedResults['Days Until Harvest'] = 'Past optimal harvest';
        }
      }

      // Format the detailed analysis
      if (results.containsKey('detailed_analysis') &&
          results['detailed_analysis'] != null &&
          results['detailed_analysis'].toString().isNotEmpty) {
        _analysisResult = _formatAIAnalysisResult(results['detailed_analysis']);
      } else {
        _analysisResult = 'No detailed analysis available.';
      }

      debugPrint('Final unripe status: ${_parsedResults['Unripe Status']}');
      debugPrint(
          'Readable harvest status: ${_getReadableHarvestState(_parsedResults['Ready for Harvest']!)}');
    });
  }

  // This method displays the appropriate UI based on the harvest readiness status
  Widget _buildHarvestStatusWidget() {
    if (!_parsedResults.containsKey('Ready for Harvest') ||
        !_parsedResults.containsKey('Unripe Status')) {
      return const SizedBox.shrink();
    }

    _parsedResults['Ready for Harvest']!.toLowerCase();
    final String unripeStatus = _parsedResults['Unripe Status']!;
    final bool isUnripe = unripeStatus.toLowerCase().contains('yes');
    final bool isOverripe = unripeStatus.toLowerCase().contains('overripe');

    // Colors for different statuses
    final Color statusColor =
        isUnripe ? Colors.orange : (isOverripe ? Colors.red : Colors.green);

    // Icons for different statuses
    final IconData statusIcon = isUnripe
        ? Icons.access_time
        : (isOverripe ? Icons.warning : Icons.check_circle);

    // Status text
    final String statusText = isUnripe
        ? "Unripe - Not Ready for Harvest"
        : (isOverripe
            ? "Overripe - Past Optimal Harvest"
            : "Ripe - Ready for Harvest");

    // Days until harvest info
    final String daysText = _parsedResults.containsKey('Days Until Harvest')
        ? _parsedResults['Days Until Harvest']!
        : (isUnripe ? "Unknown days until ready" : "Ready now");

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isUnripe)
            Text(
              daysText,
              style: TextStyle(
                fontSize: 16,
                color: statusColor.withOpacity(0.8),
              ),
            ),
          if (_parsedResults.containsKey('Confidence'))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                "Confidence: ${_parsedResults['Confidence']}",
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // NEW: Enhanced method to determine ripeness based on color patterns
  String _analyzeRipenessFromColors(String type, String colorDesc) {
    final String typeLC = type.toLowerCase();
    final String colorLC = colorDesc.toLowerCase();

    // Banana ripeness patterns
    if (typeLC.contains('banana')) {
      if (colorLC.contains('green')) {
        return 'unripe';
      } else if (colorLC.contains('yellow') && colorLC.contains('brown spot')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('yellow')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('brown') || colorLC.contains('black')) {
        return 'overripe';
      }
    }

    // Tomato ripeness patterns
    else if (typeLC.contains('tomato')) {
      if (colorLC.contains('green')) {
        return 'unripe';
      } else if (colorLC.contains('green') && colorLC.contains('red')) {
        return 'unripe'; // Starting to ripen but not ready
      } else if (colorLC.contains('red') && !colorLC.contains('dark')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('dark red') || colorLC.contains('soft')) {
        return 'overripe';
      }
    }

    // Avocado ripeness patterns
    else if (typeLC.contains('avocado')) {
      if (colorLC.contains('bright green') || colorLC.contains('light green')) {
        return 'unripe';
      } else if (colorLC.contains('dark green') || colorLC.contains('black')) {
        // For avocados, color alone isn't sufficient - need texture info
        return 'ready_for_harvest'; // Default to ready, but should be combined with texture
      }
    }

    // Mango ripeness patterns
    else if (typeLC.contains('mango')) {
      if (colorLC.contains('green') && !colorLC.contains('yellow')) {
        return 'unripe';
      } else if (colorLC.contains('yellow') ||
          colorLC.contains('orange') ||
          colorLC.contains('red')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('brown') || colorLC.contains('black spot')) {
        return 'overripe';
      }
    }

    // Papaya ripeness patterns
    else if (typeLC.contains('papaya')) {
      if (colorLC.contains('green') && !colorLC.contains('yellow')) {
        return 'unripe';
      } else if (colorLC.contains('yellow') || colorLC.contains('orange')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('orange') && colorLC.contains('soft')) {
        return 'overripe';
      }
    }

    // Apple ripeness patterns - varies by type
    else if (typeLC.contains('apple')) {
      // Granny Smith apples are supposed to be green
      if (typeLC.contains('granny smith') && colorLC.contains('green')) {
        return 'ready_for_harvest';
      }
      // Red apple varieties
      else if ((typeLC.contains('gala') ||
              typeLC.contains('fuji') ||
              typeLC.contains('red delicious')) &&
          colorLC.contains('red')) {
        return 'ready_for_harvest';
      }
      // Generic assessment
      else if (colorLC.contains('green') && !typeLC.contains('granny')) {
        return 'unripe';
      } else if (colorLC.contains('red') || colorLC.contains('yellow')) {
        return 'ready_for_harvest';
      } else if (colorLC.contains('brown') || colorLC.contains('bruise')) {
        return 'overripe';
      }
    }

    // Default returns null to use other detection methods
    return '';
  }

  // Add this before _updateRipenessPercentage
  void _enhanceRipenessDetection(Map<String, dynamic> results) {
    // Only run if we have both type and color
    if (!_parsedResults.containsKey('Type') ||
        !_parsedResults.containsKey('Color') ||
        _parsedResults['Type'] == null ||
        _parsedResults['Color'] == null) {
      return;
    }

    String type = _parsedResults['Type']!;
    String color = _parsedResults['Color']!;

    // Get ripeness assessment based on color patterns
    String colorBasedRipeness = _analyzeRipenessFromColors(type, color);

    // Only apply if we got a result and no clear harvest status already exists
    if (colorBasedRipeness.isNotEmpty &&
        (!_parsedResults.containsKey('Ready for Harvest') ||
            _parsedResults['Ready for Harvest'] == null ||
            _parsedResults['Ready for Harvest']!.isEmpty ||
            _parsedResults['Ready for Harvest'] == 'unknown')) {
      debugPrint('Applied color-pattern based ripeness: $colorBasedRipeness');
      _parsedResults['Ready for Harvest'] = colorBasedRipeness;

      // Update results map for confidence calculation
      results['color_pattern_match'] = true;
    }
    // If we have conflicting information with high confidence results, log but don't override
    else if (colorBasedRipeness.isNotEmpty &&
        _parsedResults.containsKey('Ready for Harvest') &&
        _parsedResults['Ready for Harvest'] != colorBasedRipeness) {
      debugPrint(
          'Color pattern suggests $colorBasedRipeness but keeping existing '
          '${_parsedResults['Ready for Harvest']} assessment');

      // Still note this in results for potential use
      results['color_pattern_suggests'] = colorBasedRipeness;
    }
  }

  // Add this method to save results to Firestore
  Future<void> _saveResultsToFirestore(Map<String, dynamic> results) async {
    // Check if results have already been saved to avoid duplicates
    if (_resultsSaved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Results already saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // NEW: Check if the image contains a non-produce item or should not be saved
    if ((results.containsKey('not_produce') &&
            results['not_produce'] == true) ||
        (results.containsKey('should_not_save') &&
            results['should_not_save'] == true)) {
      debugPrint(
          'Not saving scan: Image does not contain fruits or vegetables');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cannot save: Image does not contain fruits or vegetables'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Get the current harvest readiness status
    final String harvestStatus = _parsedResults['Ready for Harvest'] ?? '';
    final bool isReady = harvestStatus.toLowerCase() == 'ready_for_harvest' ||
        harvestStatus.toLowerCase() == 'ready';
    final bool isOverripe = harvestStatus.toLowerCase() == 'overripe';
    final bool isNotReady = harvestStatus.toLowerCase() == 'unripe' ||
        harvestStatus.toLowerCase() == 'not ready' ||
        harvestStatus.toLowerCase().contains('not ready');

    // Only proceed if the crop is not ready for harvest
    // if (isReady || isOverripe) {
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(
    //         content: Text(
    //             'Only crops not ready for harvest can be saved for monitoring.'),
    //         behavior: SnackBarBehavior.floating,
    //         backgroundColor: Colors.orange,
    //       ),
    //     );
    //   }
    //   return;
    // }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Cannot save results: No user logged in');
        return;
      }

      // Convert image to base64 string to ensure it's directly available in Firestore
      String? imageBase64;
      try {
        final File imageFile = File(widget.imagePath);
        if (await imageFile.exists()) {
          final Uint8List bytes = await imageFile.readAsBytes();
          // Compress image before saving
          final img.Image? originalImage = img.decodeImage(bytes);
          if (originalImage != null) {
            // Resize to a reasonable size to reduce storage requirements
            final int maxDimension = 800;
            img.Image resizedImage = originalImage;

            if (originalImage.width > maxDimension ||
                originalImage.height > maxDimension) {
              if (originalImage.width > originalImage.height) {
                resizedImage = img.copyResize(
                  originalImage,
                  width: maxDimension,
                  height: (originalImage.height *
                          maxDimension /
                          originalImage.width)
                      .round(),
                );
              } else {
                resizedImage = img.copyResize(
                  originalImage,
                  width: (originalImage.width *
                          maxDimension /
                          originalImage.height)
                      .round(),
                  height: maxDimension,
                );
              }
            }

            // Encode as JPEG with quality 85 for better compression
            final Uint8List compressedBytes =
                Uint8List.fromList(img.encodeJpg(resizedImage, quality: 85));
            imageBase64 = base64Encode(compressedBytes);
            debugPrint(
                'Successfully encoded image to base64. Size: ${(imageBase64.length / 1024).round()}KB');
          } else {
            debugPrint('Failed to decode image');
          }
        } else {
          debugPrint('Image file does not exist: ${widget.imagePath}');
        }
      } catch (e) {
        debugPrint('Error converting image to base64: $e');
      }

      // Ensure we have accurate days_until_harvest in the data
      // Always use our enhanced prediction method for consistency
      int daysUntilHarvest = _predictDaysUntilHarvest(results);

      // If days are negative (overripe), set to 0 for database storage
      if (daysUntilHarvest < 0) {
        daysUntilHarvest = 0;
      }

      // Update the results map with our accurate estimate
      results['days_until_harvest'] = daysUntilHarvest;

      debugPrint('Final days until harvest estimate: $daysUntilHarvest days');

      // Use the actual harvest status from the analysis instead of forcing "unripe"
      String statusToSave = isNotReady ? 'unripe' : 'not_ready';
      final double confidence = int.parse(results['confidence_level']) / 100;

      debugPrint('Determined status to save: $results');
      debugPrint('Determined status to save: $_parsedResults');
      // Prepare data to save
      debugPrint('Preparing to save scan data for user ${results}');
      debugPrint('Confidence level: $confidence');
      final data = {
        'name': results['Type'] ?? _detectedType,
        'category': results['detected_category'] ?? 'Unknown',
        'imagePath': widget.imagePath,
        'imageBase64': imageBase64, // Add base64 encoded image data
        'confidence': confidence,
        'harvestStatus': results['ripeness_status'] ?? statusToSave,
        'daysUntilHarvest': results['days_until_harvest'] ?? daysUntilHarvest,
        'timestamp': FieldValue.serverTimestamp(),
        'hasAnalysis': true,
        'ripeness': results['ripeness'] ?? 'unknown',
        'harvestDate': Timestamp.fromDate(
          DateTime.now().add(Duration(days: daysUntilHarvest)),
        ),
        'detailedAnalysis': results['detailed_analysis'] ?? '',
      };

      debugPrint(
          'Saving crop scan results for $_detectedType with status: $statusToSave');

      // Save it to Firestore first
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scans')
          .add(data);

      debugPrint('Scan saved with ID: ${docRef.id}');

      // Mark results as saved to prevent duplicates
      setState(() {
        _resultsSaved = true;
      });

      // Trigger data refresh callback to update parent pages
      if (widget.onDataSaved != null) {
        widget.onDataSaved!();
      }

      // Show success message without automatically setting reminder
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Crop monitoring saved successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Set Reminder',
              textColor: Colors.white,
              onPressed: () async {
                // Only set reminder if user explicitly requests it
                final NotificationService notificationService =
                    NotificationService();
                await notificationService.scheduleHarvestReminder(
                  produceType: _detectedType,
                  imagePath: widget.imagePath,
                  scanId: docRef.id,
                  daysUntilHarvest: daysUntilHarvest,
                  confidence: _parsedResults['Analysis Confidence'],
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Harvest reminder set for $daysUntilHarvest days from now'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
            ),
          ),
        );
      }

      debugPrint('Harvest reminder scheduled for $daysUntilHarvest days');
      debugPrint('Scan results saved successfully');
    } catch (e) {
      debugPrint('Error saving scan results: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving results: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Enhanced function to predict days until harvest based on AI analysis and crop type
  int _predictDaysUntilHarvest(Map<String, dynamic> results) {
    // Default prediction
    int days = 0;
    String type = _detectedType.toLowerCase();
    String lowerAnalysis = _analysisResult.toLowerCase();

    // Get the current harvest readiness status
    String harvestStatus =
        (_parsedResults['Ready for Harvest'] ?? '').toLowerCase();
    bool isReady = harvestStatus == 'ready_for_harvest' ||
        harvestStatus == 'ready' ||
        (harvestStatus.contains('ready') && !harvestStatus.contains('not'));
    bool isOverripe = harvestStatus == 'overripe' ||
        harvestStatus.contains('over') ||
        harvestStatus.contains('past');
    bool isNotReady = harvestStatus == 'unripe' ||
        harvestStatus == 'not ready' ||
        harvestStatus == 'not_ready' ||
        harvestStatus.contains('not ready');

    // First check if AI provided a direct days_until_harvest value
    if (results.containsKey('days_until_harvest') &&
        results['days_until_harvest'] != null) {
      // Verify the value makes sense with the harvest status
      days = results['days_until_harvest'] as int;

      // If days are positive but status is ready, correct to 0
      if (days > 0 && isReady) {
        debugPrint(
            'Correcting days_until_harvest from $days to 0 because status is ready');
        return 0;
      }

      // If days are 0 but status is not ready, use default estimation
      if (days == 0 && isNotReady) {
        debugPrint(
            'Days value 0 contradicts not ready status, will re-estimate');
      } else {
        return days;
      }
    }

    // Check for days mentioned in the analysis text
    final RegExp daysRegex = RegExp(r'(\d+)[-\s]*(day|days)');
    Match? match = daysRegex.firstMatch(lowerAnalysis);
    if (match != null && match.group(1) != null) {
      days = int.parse(match.group(1)!);
      debugPrint('Extracted $days days from analysis text');

      // Verify extracted days make sense with status
      if (days > 0 && isReady) {
        debugPrint(
            'Text mentioned $days days but status is ready, correcting to 0');
        return 0;
      } else if (days == 0 && isNotReady) {
        debugPrint(
            'Text mentioned 0 days but status is not ready, will re-estimate');
      } else {
        return days;
      }
    }

    // Make decisions based on harvest status
    if (isReady) {
      debugPrint('Produce is ready for harvest, setting days to 0');
      return 0;
    } else if (isOverripe) {
      debugPrint('Produce is overripe, setting days to -1');
      return -1; // Already overripe
    } else if (isNotReady) {
      // Get color and texture to refine the estimate
      String? color = _parsedResults['Color']?.toLowerCase() ?? '';
      String? texture = _parsedResults['Texture']?.toLowerCase() ?? '';

      // Define a ripening schedule map with scientific data for common produce types
      final Map<String, Map<String, dynamic>> ripeningSchedule = {
        'banana': {
          'stages': {
            'green': 7, // Full green bananas
            'green_yellow': 4, // Starting to turn yellow
            'yellow_green': 2, // Mostly yellow with green tips
            'yellow': 1, // Fully yellow
            'yellow_spots': 0, // Yellow with brown spots (ready)
          },
          'textures': {'very_firm': 5, 'firm': 2, 'soft': 0},
          'default': 4
        },
        'avocado': {
          'stages': {
            'bright_green': 8,
            'green': 5,
            'dark_green': 3,
          },
          'textures': {'hard': 7, 'firm': 3, 'slight_give': 1, 'soft': 0},
          'default': 5
        },
      };

      // Try to find a match in our ripening schedule
      if (ripeningSchedule.containsKey(type)) {
        // Check if we can determine by color
        if (ripeningSchedule[type]!.containsKey('stages')) {
          Map<String, int> stages =
              Map<String, int>.from(ripeningSchedule[type]!['stages']);

          // Find the closest color match
          for (var colorKey in stages.keys) {
            if (color.contains(colorKey)) {
              debugPrint(
                  'Found color match for $type: $colorKey = ${stages[colorKey]} days');
              return stages[colorKey]!;
            }
          }
        }

        // Check if we can determine by texture
        if (ripeningSchedule[type]!.containsKey('textures')) {
          Map<String, int> textures =
              Map<String, int>.from(ripeningSchedule[type]!['textures']);

          // Find the closest texture match
          for (var textureKey in textures.keys) {
            if (texture.contains(textureKey)) {
              debugPrint(
                  'Found texture match for $type: $textureKey = ${textures[textureKey]} days');
              return textures[textureKey]!;
            }
          }
        }

        // Use default for this produce type if no specific match
        if (ripeningSchedule[type]!.containsKey('default')) {
          int defaultDays = ripeningSchedule[type]!['default'] as int;
          debugPrint('Using default days for $type: $defaultDays days');
          return defaultDays;
        }
      }

      // Generic estimate based on produce category if no specific match
      if (type.contains('berry') ||
          type.contains('leafy') ||
          type.contains('herb')) {
        return 3; // Quick ripening produce
      } else if (type.contains('stone fruit') || type.contains('tropical')) {
        return 5; // Medium ripening
      } else if (type.contains('root') || type.contains('winter')) {
        return 10; // Slow ripening
      }
    }

    // Default fallback if no other conditions matched
    return 7; // Default to a week
  }

  Widget _buildCharacteristicRow(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF0F4F8).withOpacity(0.8),
                  Color(0xFFE3F2FD).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Color(0xFF546E7A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.primaryGradient.colors[0],
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _enhanceCharacteristicDetail(
      String characteristic, String value, String produceType) {
    // Enhance the characteristic details based on the produce type
    if (value.isEmpty) return 'Not detected';

    // Add more context to the characteristic based on the produce type
    switch (characteristic) {
      case 'Color':
        if (produceType.toLowerCase().contains('tomato')) {
          return '$value - Tomatoes typically change from green to red as they ripen';
        } else if (produceType.toLowerCase().contains('banana')) {
          return '$value - Bananas change from green to yellow to brown as they ripen';
        } else if (produceType.toLowerCase().contains('avocado')) {
          return '$value - Avocados darken as they ripen';
        }
        break;
      case 'Texture':
        if (produceType.toLowerCase().contains('avocado')) {
          return '$value - Ripe avocados yield slightly to gentle pressure';
        } else if (produceType.toLowerCase().contains('peach') ||
            produceType.toLowerCase().contains('nectarine')) {
          return '$value - Ripe stone fruits should give slightly when pressed';
        }
        break;
      case 'Physical Cues':
        if (produceType.toLowerCase().contains('pineapple')) {
          return '$value - A ripe pineapple has a sweet aroma at the base';
        } else if (produceType.toLowerCase().contains('melon')) {
          return '$value - Ripe melons often have a sweet aroma and slight give at the blossom end';
        }
        break;
    }

    return value;
  }

  // Helper method to get ideal characteristics for each produce type
  String _getIdealCharacteristics(String produceType) {
    final type = produceType.toLowerCase();

    // Fruits
    if (type.contains('apple')) {
      return 'Firm, vibrant color, no soft spots. Red varieties should be deep red, green varieties bright green.';
    } else if (type.contains('banana')) {
      return 'Yellow skin with brown spots, slightly firm but yielding to gentle pressure.';
    } else if (type.contains('orange')) {
      return 'Deep orange color, firm but slightly springy, heavy for size.';
    } else if (type.contains('mango')) {
      return 'Slight give when pressed, sweet aroma at stem, yellow-orange color with possible red blush.';
    } else if (type.contains('avocado')) {
      return 'Yields to gentle pressure but not soft, dark skin (Hass variety).';
    } else if (type.contains('strawberry')) {
      return 'Bright red color throughout, slight shine, fresh green cap.';
    } else if (type.contains('grape')) {
      return 'Firm, plump, well-colored with slight bloom coating.';
    } else if (type.contains('pear')) {
      return 'Yields to gentle pressure at neck, aromatic, minimal blemishes.';
    } else if (type.contains('peach')) {
      return 'Sweet aroma, gives slightly to pressure, golden/pink color.';
    } else if (type.contains('plum')) {
      return 'Firm with slight give, rich color, slight powdery coating.';
    }

    // Vegetables
    else if (type.contains('tomato')) {
      return 'Rich red color, firm but slightly soft, glossy skin.';
    } else if (type.contains('potato')) {
      return 'Firm, no sprouts, no green areas, clean skin.';
    } else if (type.contains('carrot')) {
      return 'Bright orange, firm, smooth skin, no splits.';
    } else if (type.contains('cucumber')) {
      return 'Dark green, firm, smooth skin, medium size.';
    } else if (type.contains('lettuce')) {
      return 'Crisp leaves, bright color, no wilting or browning.';
    } else if (type.contains('pepper') || type.contains('bell pepper')) {
      return 'Firm, glossy, rich color, heavy for size.';
    } else if (type.contains('broccoli')) {
      return 'Dark green, compact head, no yellowing florets.';
    } else if (type.contains('cauliflower')) {
      return 'White/cream color, firm, compact head, no discoloration.';
    } else if (type.contains('onion')) {
      return 'Firm, dry papery skin, no soft spots or sprouting.';
    } else if (type.contains('garlic')) {
      return 'Firm bulb, tight skin, no sprouting, heavy for size.';
    } else if (type.contains('eggplant')) {
      return 'Glossy skin, firm, heavy for size, rich purple color.';
    } else if (type.contains('zucchini')) {
      return 'Firm, glossy skin, 6-8 inches long, no soft spots.';
    } else if (type.contains('squash')) {
      return 'Hard shell, rich color, heavy for size, no soft spots.';
    }

    // Berries
    else if (type.contains('blueberry')) {
      return 'Deep blue with whitish bloom, firm, dry, plump.';
    } else if (type.contains('raspberry')) {
      return 'Bright red, easily detaches when ripe, plump segments.';
    } else if (type.contains('blackberry')) {
      return 'Deep black, glossy, plump, easily detaches when ripe.';
    }

    // Tropical Fruits
    else if (type.contains('pineapple')) {
      return 'Golden yellow color, sweet aroma, leaves easily pull out.';
    } else if (type.contains('papaya')) {
      return 'Mostly yellow-orange skin, yields to pressure, sweet aroma.';
    } else if (type.contains('kiwi')) {
      return 'Yields to gentle pressure, fuzzy skin, no wrinkles.';
    }

    // Citrus
    else if (type.contains('lemon')) {
      return 'Bright yellow, firm but slightly springy, smooth skin.';
    } else if (type.contains('lime')) {
      return 'Deep green to yellow-green, firm, smooth skin.';
    } else if (type.contains('grapefruit')) {
      return 'Heavy for size, firm but not hard, characteristic color.';
    }

    // Root Vegetables
    else if (type.contains('beet')) {
      return 'Firm, smooth skin, deep color, medium size.';
    } else if (type.contains('radish')) {
      return 'Firm, crisp, bright color, smooth skin.';
    } else if (type.contains('turnip')) {
      return 'Firm, heavy for size, smooth skin, no blemishes.';
    } else if (type.contains('sweet potato')) {
      return 'Firm, smooth skin, uniform color, no soft spots.';
    }

    // Default case
    else {
      return 'Firm texture, rich color, free from blemishes or soft spots.';
    }
  }
}
