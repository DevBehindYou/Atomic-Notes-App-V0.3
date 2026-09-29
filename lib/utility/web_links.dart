import 'package:url_launcher/url_launcher.dart';

/// Pages on the Atomic Notes website that the App links to, and the one way
/// the App opens a web address: in the phone's own browser.
class WebLinks {
  WebLinks._();

  static const String site = 'https://atomic-notes-community.vercel.app';

  /// How to support the project and get Atomic Coins early.
  static const String support = '$site/support-atomic-notes';

  /// Whether [url] is a web page the App hands to the browser. Only https:
  /// notification buttons come from the Controller, and nothing else is
  /// opened outside the App.
  static bool isWeb(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Opens [url] in the browser. False when it is not a web page or no app
  /// could open it.
  static Future<bool> open(String url) async {
    if (!isWeb(url)) return false;
    try {
      return await launchUrl(Uri.parse(url.trim()),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
