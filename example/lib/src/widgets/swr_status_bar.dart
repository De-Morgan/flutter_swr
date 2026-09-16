import 'package:flutter/material.dart';

/// A thin status row shown while a `useSwr` key is revalidating in the
/// background (i.e. `SwrResponse.isValidating`) — collapses to nothing
/// otherwise.
class SwrStatusBar extends StatelessWidget {
  const SwrStatusBar({super.key, required this.isValidating});

  final bool isValidating;

  @override
  Widget build(BuildContext context) {
    if (!isValidating) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Refreshing…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
