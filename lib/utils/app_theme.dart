import 'package:flutter/material.dart';

/// App theme utilities and gradient definitions
class AppTheme {
  // Primary gradient - Balanced Green to Orange (fruit/veggie inspired)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFF2E7D32), // Dark Green
      Color(0xFF4CAF50), // Medium Green
      Color(0xFF8BC34A), // Light Green
      Color(0xFFFFB300), // Amber
      Color(0xFFFF9800), // Orange
      Color(0xFFE65100), // Deep Orange
    ],
    stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Secondary gradient - Slightly lighter variation
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [
      Color(0xFF43A047), // Medium Green
      Color(0xFF66BB6A), // Light Green
      Color(0xFFAED581), // Lighter Green
      Color(0xFFFFA000), // Amber
    ],
    stops: [0.0, 0.3, 0.6, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Accent gradient - For buttons and interactive elements
  static const LinearGradient accentGradient = LinearGradient(
    colors: [
      Color(0xFF2E7D32), // Dark Green
      Color(0xFF66BB6A), // Light Green
      Color(0xFFFFB300), // Amber
      Color(0xFFE65100), // Deep Orange
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Gradient decoration for containers
  static BoxDecoration gradientBoxDecoration({
    double borderRadius = 15,
    LinearGradient? gradient,
  }) {
    return BoxDecoration(
      gradient: gradient ?? primaryGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          spreadRadius: 1,
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // Gradient text style
  static TextStyle gradientTextStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.bold,
    LinearGradient? gradient,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      foreground: Paint()
        ..shader = (gradient ?? primaryGradient).createShader(
          const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
        ),
    );
  }
}

// Extension on Widget to apply gradient background
extension GradientWidgetExtension on Widget {
  Widget withGradientBackground({
    LinearGradient? gradient,
    double borderRadius = 15,
  }) {
    return Container(
      decoration: AppTheme.gradientBoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius,
      ),
      child: this,
    );
  }
}
