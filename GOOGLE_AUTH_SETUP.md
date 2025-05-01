# Google認証の設定方法

## エラー修正: redirect_uri_mismatch (400)

Firebaseにデプロイしたアプリで「redirect_uri_mismatch」エラーが発生した場合、Google Cloud Consoleの認証情報にリダイレクトURIを追加する必要があります。

## 手順

1. [Google Cloud Console](https://console.cloud.google.com/)にアクセスしてログイン

2. 左側のメニューから「APIとサービス」→「認証情報」を選択

3. プロジェクト「anki-pai」を選択

4. OAuth 2.0 クライアントIDを探して選択（Web クライアント）

5. 「承認済みのリダイレクトURI」セクションに以下のURIを追加:

```
https://anki-pai.firebaseapp.com/__/auth/handler
https://anki-pai.web.app/__/auth/handler
```

6. 「保存」ボタンをクリックして変更を適用

## 参考: 認証に必要なドメイン一覧

FirebaseとGoogle認証を一緒に使う場合は、以下のドメインをリダイレクトURIとして登録しておくと良いでしょう:

1. ローカル開発用:
   - http://localhost:端口番号
   - http://localhost:端口番号/login
   - http://localhost:端口番号/__/auth/handler

2. デプロイ用:
   - https://anki-pai.web.app
   - https://anki-pai.web.app/login
   - https://anki-pai.web.app/__/auth/handler
   - https://anki-pai.firebaseapp.com
   - https://anki-pai.firebaseapp.com/login
   - https://anki-pai.firebaseapp.com/__/auth/handler

## その他のトラブルシューティング

実装の変更により、ログイン方法を「Popup」から「リダイレクト」に変更しました。これにより:

1. より多くのブラウザで安定して動作します
2. ポップアップブロッカーの影響を受けません
3. Webブラウザでのログイン体験が向上します

エラーが解決しない場合は、ブラウザのコンソールでより詳細なエラーメッセージを確認し、
適切な対応策を検討してください。
