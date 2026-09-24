import 'package:flutter/material.dart';
import 'package:flutter_swr/flutter_swr.dart';

import 'retry_error.dart';

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
