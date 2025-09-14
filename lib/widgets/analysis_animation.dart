import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' show sin, pi, Random, cos;

/// A modern analysis animation that shows a futuristic scanning effect over an image
class AnalysisAnimation extends StatefulWidget {
  final AnimationController controller;
  final File imageFile;

  const AnalysisAnimation({
    super.key,
    required this.controller,
    required this.imageFile,
  });

  @override
  State<AnalysisAnimation> createState() => _AnalysisAnimationState();
}

class _AnalysisAnimationState extends State<AnalysisAnimation> {
  final List<Particle> _particles = [];
  final int particleCount = 30;
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    // Generate particles
    for (int i = 0; i < particleCount; i++) {
      _particles.add(Particle(random));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Futuristic scanning effect on the image
        Container(
          height: 300,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The image
                Image.file(
                  widget.imageFile,
                  fit: BoxFit.cover,
                ),

                // Modern data matrix overlay
                CustomPaint(
                  painter: ModernGridPainter(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),

                // Animated AI scan visualization
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    return Stack(
                      children: [
                        // Animated holographic scanner
                        Positioned(
                          top: widget.controller.value * 300,
                          left: 0,
                          right: 0,
                          height: 60,
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.3),
                                  Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.7),
                                  Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.screen,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha: 0.3),
                                    Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha: 0.5),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.3, 0.7, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Horizontal scanner line with pulse effect
                        Positioned(
                          top: widget.controller.value * 300,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.8),
                                  blurRadius: 12,
                                  spreadRadius: 3,
                                ),
                              ],
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).colorScheme.secondary,
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.2, 0.8, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Moving dots/particles animation
                        CustomPaint(
                          painter: ParticleEffectPainter(
                            particles: _particles,
                            animationValue: widget.controller.value,
                            baseColor: Theme.of(context).primaryColor,
                          ),
                          size: Size.infinite,
                        ),

                        // Detection boxes that appear randomly
                        ...List.generate(3, (index) {
                          final startTime = 0.3 * index;
                          final endTime = startTime + 0.5;
                          final animValue = widget.controller.value;

                          // Only show each box within its time window
                          if (animValue < startTime || animValue > endTime) {
                            return const SizedBox.shrink();
                          }

                          // Determine a random position for each box
                          final rnd = Random(index * 7);
                          final size = 30.0 + rnd.nextDouble() * 70.0;
                          final left = rnd.nextDouble() * (300 - size);
                          final top = rnd.nextDouble() * (300 - size);

                          // Animate the opacity within the time window
                          final opacity =
                              (animValue - startTime) / (endTime - startTime);
                          final fadeInOut = sin(opacity * pi);

                          return Positioned(
                            left: left,
                            top: top,
                            child: Opacity(
                              opacity: fadeInOut * 0.8,
                              child: Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary
                                          .withValues(alpha: 0.8),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(4),
                                        bottomRight: Radius.circular(4),
                                      ),
                                    ),
                                    child: Text(
                                      'ID-${(index * 723 + 172) % 1000}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),

                // Modern futuristic analysis badge
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          const Color(0xFF2E7D32)
                              .withValues(alpha: 0.7), // Dark Green
                          const Color(0xFF4CAF50)
                              .withValues(alpha: 0.7), // Medium Green
                          const Color(0xFF8BC34A)
                              .withValues(alpha: 0.6), // Light Green
                        ],
                        stops: const [0.0, 0.3, 0.6, 1.0],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'AI ANALYSIS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Data points label
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) {
                      // Calculate a random number that increases over time
                      final baseValue = 256;
                      final maxIncrease = 1024;
                      final randomIncrease =
                          (widget.controller.value * maxIncrease).toInt();
                      final displayValue = baseValue + randomIncrease;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              const Color(0xFFE65100)
                                  .withValues(alpha: 0.7), // Deep Orange
                              const Color(0xFFFF9800)
                                  .withValues(alpha: 0.7), // Orange
                            ],
                            stops: const [0.0, 0.5, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.analytics_outlined,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$displayValue POINTS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

/// Particle class for the floating particle effect
class Particle {
  double x;
  double y;
  double size;
  double velocity;
  double opacity;
  double angle;

  Particle(Random random)
      : x = random.nextDouble() * 300,
        y = random.nextDouble() * 300,
        size = random.nextDouble() * 4 + 1,
        velocity = random.nextDouble() * 1.5 + 0.5,
        opacity = random.nextDouble() * 0.6 + 0.2,
        angle = random.nextDouble() * 2 * pi;

  void update(double animationValue, Random random) {
    // Move the particle based on animation value
    angle += 0.02;
    x += cos(angle) * velocity * sin(animationValue * pi);
    y += sin(angle) * velocity * cos(animationValue * pi);

    // Reset if out of bounds
    if (x < 0 || x > 300 || y < 0 || y > 300) {
      x = random.nextDouble() * 300;
      y = random.nextDouble() * 300;
      angle = random.nextDouble() * 2 * pi;
    }

    // Pulse the opacity
    opacity = 0.2 + 0.6 * (0.5 + 0.5 * sin(animationValue * 3 * pi + x / 30));
  }
}

/// Painter for the modern grid pattern
class ModernGridPainter extends CustomPainter {
  final Color color;

  ModernGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final gridSize = 20.0;

    // Draw horizontal lines with varying opacity
    for (int i = 0; i < size.height / gridSize + 1; i++) {
      final y = i * gridSize;
      final opacity = 0.3 + 0.7 * (1 - (y / size.height));
      paint.color = color.withValues(alpha: opacity * 0.6);

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    // Draw vertical lines with varying opacity
    for (int i = 0; i < size.width / gridSize + 1; i++) {
      final x = i * gridSize;
      final opacity = 0.3 + 0.7 * (1 - (x / size.width));
      paint.color = color.withValues(alpha: opacity * 0.6);

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Draw a few diagonal accent lines
    paint.color = color.withValues(alpha: 0.4);
    for (int i = -5; i < 10; i += 4) {
      final offset = i * gridSize * 2;
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter for the floating particle effect
class ParticleEffectPainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;
  final Color baseColor;
  final Random random = Random();

  ParticleEffectPainter({
    required this.particles,
    required this.animationValue,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Update particle position and properties
      particle.update(animationValue, random);

      // Draw the particle
      final paint = Paint()
        ..color = baseColor.withValues(alpha: particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size,
        paint,
      );

      // Add a subtle glow effect
      final glowPaint = Paint()
        ..color = baseColor.withValues(alpha: particle.opacity * 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size * 2,
        glowPaint,
      );

      // Connect nearby particles with lines
      for (final otherParticle in particles) {
        if (particle == otherParticle) continue;

        final dx = particle.x - otherParticle.x;
        final dy = particle.y - otherParticle.y;
        final distance = (dx * dx + dy * dy);

        // Only connect particles within a certain distance
        if (distance < 2500) {
          final opacity = (1 - distance / 2500) * 0.2 * particle.opacity;

          final linePaint = Paint()
            ..color = baseColor.withValues(alpha: opacity)
            ..strokeWidth = 0.5;

          canvas.drawLine(
            Offset(particle.x, particle.y),
            Offset(otherParticle.x, otherParticle.y),
            linePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
