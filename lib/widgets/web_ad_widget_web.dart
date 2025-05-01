import 'dart:html';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Creates a web advertisement view for web platform
/// This implementation uses IFrameElement to load the ad content
Widget createWebAdView({
  required String adId,
  required double height,
  required double width,
  required String adSrc,
}) {
  // Register a platform view factory for this ad ID
  // This allows Flutter to use a native web element (iframe) within the Flutter app
  ui_web.platformViewRegistry.registerViewFactory(
    adId,
    (int viewId) => IFrameElement()
      ..style.height = '${height.toInt()}px'
      ..style.width = '${width.toInt()}px'
      ..src = adSrc
      ..style.border = 'none'
      // Add allow attribute for security
      ..setAttribute('allow', 'scripts same-origin forms')
      // Prevent scrolling if the ad content is larger than the iframe
      ..style.overflow = 'hidden',
  );

  // Return a sized box containing the platform view
  return SizedBox(
    height: height,
    width: width,
    child: HtmlElementView(
      viewType: adId,
    ),
  );
}
