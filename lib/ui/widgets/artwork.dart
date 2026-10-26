import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder cover art: a seeded gradient with soft light blooms.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.seed, this.size = 48, this.radius, this.icon});

  final String seed;
  final double size;
  final double? radius;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (light, dark) = artPalette(seed);
    final r = radius ?? size * 0.14;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ),
        boxShadow: size >= 120
            ? [BoxShadow(color: dark.withValues(alpha: 0.55), blurRadius: size * 0.3, offset: Offset(0, size * 0.08))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -size * 0.25,
              top: -size * 0.3,
              width: size * 0.9,
              height: size * 0.9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
            Center(
              child: Icon(
                icon ?? Icons.music_note_rounded,
                size: size * 0.38,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
