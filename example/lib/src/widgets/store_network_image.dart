import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A [CachedNetworkImage] with sensible defaults for product photos:
/// a spinner placeholder and a broken-image fallback, so a bad/slow image
/// URL never breaks the surrounding layout.
class StoreNetworkImage extends StatelessWidget {
  const StoreNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
  });

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (context, url) => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 32, color: Colors.grey),
      ),
    );
  }
}
