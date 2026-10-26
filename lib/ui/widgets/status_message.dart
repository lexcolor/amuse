import 'package:flutter/material.dart';

import '../theme.dart';

/// A centred icon, title and message, with an optional action. Used for
/// empty, error and sign-in states.
class StatusMessage extends StatelessWidget {
  const StatusMessage({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: Icon(icon, size: 32, color: AmuseColors.accent),
            ),
            const SizedBox(height: 20),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            SelectableText(body, style: text.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ]),
        ),
      ),
    );
  }
}

/// Fills the rest of a scroll view with [child], centred, and lets it scroll
/// when it's taller than the space left. Unlike `SliverFillRemaining`, this
/// lays [child] out for real instead of trusting its intrinsic height, which
/// wrapped text and buttons under-report (the message overflowed).
class SliverRest extends StatelessWidget {
  const SliverRest({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) => SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.remainingPaintExtent),
            child: Center(child: child),
          ),
        ),
      );
}
