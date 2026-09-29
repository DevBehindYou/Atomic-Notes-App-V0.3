/// App metadata shown in the UI.
///
/// Keep [version] and [buildNumber] in step with `version:` in pubspec.yaml.
/// They were previously hardcoded separately in settings_page.dart and
/// about_us_page.dart, and both had drifted (the UI said 1.11.1 while the
/// pubspec said 1.12.1).
class AppInfoText {
  AppInfoText._();

  // Checked against pubspec.yaml by test/app_info_test.dart, and sent to the Server with the
  // notification feed so messages aimed at other App versions are left out.
  static const String version = "2.03.5";
  static const String buildNumber = "8";
  static const String copyright = "© 2026 Atomic Notes";

  static String get versionLabel => "Version: $version ($buildNumber)";
}
