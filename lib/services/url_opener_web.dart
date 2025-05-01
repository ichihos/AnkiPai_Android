// Webプラットフォーム専用実装
// dart:htmlは条件付きインポートが必要
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' if (dart.library.io) 'url_opener_stub.dart' as html;

/// Web-specific implementation for opening URLs in the browser
/// Enhanced for mobile browser compatibility
void openUrlWeb(String url) {
  try {
    // 方法1: window.locationを使用（モバイルブラウザで最も信頼性が高い）
    // ただし新しいタブではなく現在のタブで開く
    html.window.location.href = url;
  } catch (e) {
    try {
      // 方法2: window.openを試す（モバイルブラウザでは制限あり）
      final newWindow = html.window.open(url, '_blank');

      // Safari対策：window.openがnullを返す場合の処理
      if (newWindow.closed == true) {
        // 方法3: aタグを作成して強制的にクリック
        final anchor = html.AnchorElement()
          ..href = url
          ..target = '_blank'
          ..rel = 'noopener noreferrer';

        // DOMに追加せずにクリックすることでポップアップブロックを回避する可能性がある
        anchor.click();
      }
    } catch (e) {
      // すべての方法が失敗した場合、ユーザーに通知またはフォールバック処理
      print('Failed to open URL: $e');
    }
  }
}
