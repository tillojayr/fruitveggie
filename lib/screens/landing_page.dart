import 'package:flutter/material.dart';
import 'login_page.dart';
import 'package:flutter/services.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main image background
          Positioned.fill(
            child: Image.asset(
              'assets/images/landing.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // White overlay at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: CurvePainter(),
              child: Container(
                height: 320,
                padding: const EdgeInsets.only(
                  top: 80,
                  left: 40,
                  right: 40,
                  bottom: 30,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'FruitVeggie',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Your Smart Harvest Companion',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Get Started button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const LoginPage(),
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
                                const begin = Offset(0.0, 1.0);
                                const end = Offset.zero;
                                const curve = Curves.easeInOutCubic;

                                var tween = Tween(begin: begin, end: end)
                                    .chain(CurveTween(curve: curve));

                                return SlideTransition(
                                  position: animation.drive(tween),
                                  child: child,
                                );
                              },
                              transitionDuration:
                                  const Duration(milliseconds: 500),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    var path = Path();

    // Start path at top left corner
    path.moveTo(0, 90);

    // Create a smoother curve using a cubic bezier curve for more control
    path.cubicTo(
        size.width * 0.25, // first control point x (25% from left)
        10, // first control point y (higher for more curve)
        size.width * 0.75, // second control point x (75% from left)
        10, // second control point y (higher for more curve)
        size.width, // end point x (right side)
        90 // end point y (same as start)
        );

    // Draw line to bottom right corner
    path.lineTo(size.width, size.height);

    // Draw line to bottom left corner
    path.lineTo(0, size.height);

    // Close the path
    path.close();

    // Draw with anti-aliasing for smoother edges
    paint.isAntiAlias = true;
    canvas.drawPath(path, paint);

    // Add a subtle shadow for depth
    var shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw a subtle line along the curve for definition
    var shadowPath = Path();
    shadowPath.moveTo(0, 90);
    shadowPath.cubicTo(
        size.width * 0.25, // first control point x
        10, // first control point y
        size.width * 0.75, // second control point x
        10, // second control point y
        size.width, // end point x
        90 // end point y
        );

    canvas.drawPath(shadowPath, shadowPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
