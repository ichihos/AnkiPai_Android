import 'package:flutter/material.dart';

/// Creates a stub advertisement view for non-web platforms
/// This implementation returns an empty widget since ads are not supported on non-web platforms
Widget createWebAdView({
  required String adId,
  required double height,
  required double width,
  required String adSrc,
}) {
  // Return an empty container on non-web platforms
  return const SizedBox.shrink();
}
