// Web環境用のスタブファイル

// Platform APIのスタブ実装
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isWeb => true;
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => 'browser';
}
