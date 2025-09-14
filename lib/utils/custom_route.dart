import 'package:flutter/material.dart';

/// Custom route class that provides slide animation transitions for page navigation
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final SlideDirection direction;

  SlidePageRoute({
    required this.page,
    this.direction = SlideDirection.right,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Define start and end offsets based on direction
            Offset beginOffset;
            switch (direction) {
              case SlideDirection.right:
                beginOffset = const Offset(1.0, 0.0); // Slide from right
                break;
              case SlideDirection.left:
                beginOffset = const Offset(-1.0, 0.0); // Slide from left
                break;
              case SlideDirection.up:
                beginOffset = const Offset(0.0, 1.0); // Slide from bottom
                break;
              case SlideDirection.down:
                beginOffset = const Offset(0.0, -1.0); // Slide from top
                break;
            }

            // Create the slide animation
            var slideAnimation = Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            );

            // Add a fade animation on top of the slide
            var fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
            );

            // Apply both animations
            return FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}

/// Enum defining the possible directions for slide transitions
enum SlideDirection {
  right, // Slide from right to left (push forward)
  left, // Slide from left to right (go back)
  up, // Slide from bottom to top
  down // Slide from top to bottom
}
