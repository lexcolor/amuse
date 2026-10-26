import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../metadata/providers.dart';
import '../theme.dart';
import 'artwork.dart';

/// Real album art for [track] when it can be found (embedded or online),
/// fading in over the generated placeholder. Radio station logos sit on a
/// light tile instead, since most are drawn for white backgrounds.
class CoverArt extends ConsumerWidget {
  const CoverArt({super.key, required this.track, this.size = 48, this.radius});

  final Track track;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = radius ?? size * 0.14;
    final placeholder = Artwork(
      seed: ref.enriched(track).artSeed,
      size: size,
      radius: r,
      icon: track.isLive ? Icons.radio_rounded : null,
    );
    final file = ref.watch(coverProvider(track)).value;
    if (file == null) return placeholder;

    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final logo = track.isLive;
    return Container(
      width: size,
      height: size,
      padding: logo ? EdgeInsets.all(size * 0.1) : null,
      decoration: BoxDecoration(
        color: logo ? AmuseColors.textPrimary : null,
        borderRadius: BorderRadius.circular(r),
        boxShadow: size >= 120
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: size * 0.25, offset: Offset(0, size * 0.06))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Image.file(
          file,
          fit: logo ? BoxFit.contain : BoxFit.cover,
          cacheWidth: pixels,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return Stack(fit: StackFit.expand, children: [
              if (!logo) placeholder,
              AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: child,
              ),
            ]);
          },
        ),
      ),
    );
  }
}
