/// Web向けユーザーエージェント取得用のスタブファイル
/// dart:io環境では使用されず、dart:html環境でのみ使用される
library;

class Window {
  Navigator navigator = Navigator();
}

class Navigator {
  String userAgent = 'stub_user_agent';
}

final Window window = Window();
