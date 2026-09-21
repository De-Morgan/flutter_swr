import 'package:flutter/material.dart';
import 'package:flutter_swr/flutter_swr.dart';

/// Renders a [SwrResponse]'s loading/error/data states consistently across
/// the app: a spinner while loading, a message-and-retry panel on error
/// (calling [onRetry], normally the bound `mutate()` from the same
/// `useSwr` call), and [builder] once data is available.
class SwrView<T> extends StatelessWidget {
  const SwrView({
    super.key,
    required this.response,
    required this.onRetry,
    required this.builder,
  });

  final SwrResponse<T> response;
  final Future<void> Function() onRetry;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return response.map(
      data: (r) => builder(context, r.data as T),
      error: (r) =>
          RetryErrorView(message: r.error.toString(), onRetry: onRetry),
      loading: (_) => const Center(child: CircularProgressIndicator()),
      // A failed background revalidation shouldn't hide data already on
      // screen — only fall through to the full-screen error panel when
      // there's no data to show at all.
      skipError: true,
    );
  }
}

/// A standalone error-with-retry panel, usable outside [SwrView] too (e.g.
/// for a form submission failure).
class RetryErrorView extends StatelessWidget {
  const RetryErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
