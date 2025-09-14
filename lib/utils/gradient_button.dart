import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A custom button with gradient background
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final LinearGradient? gradient;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double elevation;
  final IconData? icon;
  final double? width;
  final double height;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.gradient,
    this.borderRadius = 30.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
    this.elevation = 3.0,
    this.icon,
    this.width,
    this.height = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: elevation,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.accentGradient,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Center(
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A smaller gradient button for secondary actions
class GradientIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final LinearGradient? gradient;
  final double size;
  final double borderRadius;
  final double elevation;
  final String? tooltip;

  const GradientIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.gradient,
    this.size = 50.0,
    this.borderRadius = 15.0,
    this.elevation = 2.0,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      elevation: elevation,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.accentGradient,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}
