import 'package:url_launcher/url_launcher.dart';

/// Stub implementation for opening URLs on non-web platforms
/// Uses url_launcher package which works on iOS, Android, etc.
void openUrlInBrowser(String url) async {
  final Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw Exception('Could not launch $url');
  }
}
