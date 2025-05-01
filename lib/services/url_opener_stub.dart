/// Non-web implementation stub
/// スタブファイル - 非Webプラットフォーム用
/// dart:htmlのインターフェース互換性のための実装
library;

/// HTMLのwindowオブジェクトのスタブインターフェース
class _Window {
  /// URLを新しいウィンドウで開くスタブメソッド
  void open(String url, String target) {
    // 非Webプラットフォームではスタブのみで実際には何も行わない
    print('非Webプラットフォームでwindow.openが呼ばれました: $url');
  }
}

/// HTMLウィンドウへのスタブアクセス
final window = _Window();

/// Web用関数のスタブ実装
void openUrlWeb(String url) {
  // 非Webプラットフォームでは何も行わない
  print('非WebプラットフォームでopenUrlWebが呼ばれました: $url');
}
