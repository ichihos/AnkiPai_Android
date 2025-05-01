import 'dart:html' as html;

/// Web-specific implementation for opening URLs in browser
void openUrlInBrowser(String url) {
  html.window.open(url, '_blank');
}
