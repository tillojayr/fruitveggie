import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'result_page.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_theme.dart';
import 'dart:io';
import '../utils/custom_route.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.onBackToDashboard});

  final VoidCallback? onBackToDashboard;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isRearCameraSelected = true;
  final ImagePicker _picker = ImagePicker();

  // Safely dispose camera to free ImageReader buffers
  Future<void> _disposeCameraSafely() async {
    try {
      final controller = _controller;
      // Clear the controller reference first to prevent further access
      _controller = null;
      _initializeControllerFuture = null;
      
      if (controller != null) {
        if (controller.value.isInitialized) {
          try {
            // Stop image stream first if it's running
            if (controller.value.isStreamingImages) {
              await controller.stopImageStream();
            }
            // Then pause preview
            await controller.pausePreview();
          } catch (_) {}
        }
        
        // Add a small delay to ensure all pending operations complete
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Finally dispose the controller
        await controller.dispose();
        
        // Force a garbage collection suggestion
        // This won't guarantee GC but helps in some cases
        Future.microtask(() {
          print('Camera resources released, suggesting GC');
        });
      }
    } catch (e) {
      print('Error while disposing camera: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes to manage camera resources
    final CameraController? cameraController = _controller;

    // If the controller is null or not initialized, no need to do anything
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // App is in background or route is changing - release camera resources
      _disposeCameraSafely();
    } else if (state == AppLifecycleState.resumed) {
      // App is in foreground - reinitialize camera
      _initializeCamera();
    }
  }

  @override
  void initState() {
    super.initState();
    // Register for lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;

    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No cameras found on device')),
          );
        }
        return;
      }

      // Select camera based on user preference
      final firstCamera = _isRearCameraSelected 
          ? cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first)
          : cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.last);

      // Dispose of the previous controller if it exists
      await _disposeCameraSafely();

      // Use low resolution to prevent buffer overflows
      // Lower resolution means fewer buffers needed
      _controller = CameraController(
        firstCamera,
        ResolutionPreset.low,  // Use low resolution to prevent buffer issues
        enableAudio: false,    // Disable audio to reduce resource usage
        imageFormatGroup: ImageFormatGroup.jpeg, // Use JPEG for better memory usage
      );

      // Add delay to ensure previous camera instance is fully released
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Initialize with a timeout to prevent hanging
      _initializeControllerFuture = _controller?.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Camera initialization timed out, retrying...');
          if (mounted) {
            _initializeCamera(); // Retry initialization
          }
          throw Exception('Camera initialization timed out');
        },
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing camera: $e')),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (!mounted) return;

    try {
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null && mounted) {
        // Show the image processing options
        _showImageProcessingOptions(pickedFile.path);
      } else if (mounted) {
        // User canceled the picker
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image selected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!mounted) return;
        if (widget.onBackToDashboard != null) {
          widget.onBackToDashboard!();
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Camera'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!mounted) return;
              if (widget.onBackToDashboard != null) {
                widget.onBackToDashboard!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                _showCaptureGuideDialog(context);
              },
              tooltip: 'Capture Tips',
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: CameraPreview(_controller!),
                  ),
                  Positioned(
                    top: 40,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 40),
                          const Text(
                            'Capture Fruit/Vegetable',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isRearCameraSelected
                                  ? Icons.camera_front
                                  : Icons.camera_rear,
                              color: Colors.white,
                            ),
                            onPressed: () async {
                              // Disable the button while switching
                              if (_initializeControllerFuture == null) return;

                              setState(() {
                                _isRearCameraSelected = !_isRearCameraSelected;
                              });

                              await _initializeCamera();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 40),
                          height: 60,
                          width: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.photo_library_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: _pickImageFromGallery,
                          ),
                        ),
                        Container(
                          height: 80,
                          width: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 5),
                          ),
                          child: ClipOval(
                            child: Material(
                              color: Colors.white,
                              child: InkWell(
                                onTap: () async {
                                  try {
                                    await _initializeControllerFuture;
                                    
                                    // Add a flag to prevent multiple taps
                                    if (_controller == null || !_controller!.value.isInitialized) {
                                      return;
                                    }
                                    
                                    // Pause preview before taking picture to free up resources
                                    try {
                                      await _controller!.pausePreview();
                                    } catch (_) {}
                                    
                                    // Take picture with memory-optimized settings
                                    final image = await _controller!.takePicture();
                                    
                                    // Force release any pending image buffers
                                    try {
                                      // Resume and pause again to flush buffers
                                      await _controller!.resumePreview();
                                      await Future.delayed(const Duration(milliseconds: 100));
                                      await _controller!.pausePreview();
                                    } catch (_) {}

                                    if (!mounted) return;

                                    // Show options for automatic or manual analysis
                                    _showImageProcessingOptions(image.path);
                                  } catch (e) {
                                    print('Error taking picture: $e');
                                    
                                    // Try to recover the camera
                                    if (mounted) {
                                      _initializeCamera();
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              return Container(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryGradient.colors[1]),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Ensure camera is fully disposed to release buffers
    _disposeCameraSafely();
    super.dispose();
  }

  // Add this new method for showing capture tips
  void _showCaptureGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
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
                    color: const Color(0xFF2E7D32).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    color: const Color(0xFF2E7D32),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tips for Better Analysis',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  '• Ensure good lighting on the produce',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Center the fruit/vegetable in the frame',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Capture the entire produce in the shot',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Avoid shadows and reflections',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Hold steady to avoid blurry images',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Text(
                    'Note: The app will try to analyze even low-quality images, but better photos will give more accurate results.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF0D47A1),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Got it!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Function to show a bottom sheet with options after capturing an image
  void _showImageProcessingOptions(String imagePath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 60,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath),
              width: 150,
              height: 150,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Process Image',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyze with AI'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.pop(context); // Close the bottom sheet
                
                // Dispose camera completely before navigating 
                // This is critical to prevent ImageReader buffer overflow
                _disposeCameraSafely().then((_) {
                  // Force a small delay to ensure resources are freed
                  return Future.delayed(const Duration(milliseconds: 300));
                }).then((_) {
                  // Navigate to result page with automatic detection
                  Navigator.push(
                    context,
                    SlidePageRoute(
                      page: ResultPage(
                        imagePath: imagePath,
                        useAutoDetection: true,
                        onDataSaved: () {
                          if (widget.onBackToDashboard != null) {
                            widget.onBackToDashboard!();
                          }
                        },
                      ),
                    ),
                  ).then((_) {
                    // Re-initialize camera when returning to this page
                    if (mounted) {
                      // Delay camera initialization to ensure resources are free
                      Future.delayed(const Duration(milliseconds: 500), () {
                        _initializeCamera();
                      });
                    }
                  });
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'AI will identify the produce type and analyze harvest readiness',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 4),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
