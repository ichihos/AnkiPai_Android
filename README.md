# 暗記Pai (Anki Pai)

記憶学習支援アプリケーション

## 概要

暗記Pai（アンキパイ）は学習コンテンツの管理と記憶法（メモリーテクニック）の生成・共有を支援するクロスプラットフォームアプリケーションです。AIを活用した記憶法の提案と効率的な学習をサポートします。

## 主要機能

### 基本機能
- メモリーアイテム管理（学習コンテンツの作成・保存・共有）
- AIによるメモリーテクニック（記憶法）の生成と管理
- 複数の記憶方法を提案する「マルチエージェントモード」
- 考え方の本質を教えてくれる「思考モード」
- OCR機能による画像からのテキスト抽出と学習項目化
- フラッシュカード機能と復習スケジュール管理
- ユーザー間での記憶法の共有とコミュニティ機能

### サブスクリプション機能
- 複数プラットフォーム対応（Android/iOS/Web）
- 各プラットフォーム固有の決済システム対応
  - Android: Google Play Billing
  - iOS: In-App Purchase
  - Web: Stripe

### アカウント機能
- メールアドレス、Google、Apple IDによるアカウント連携
- ユーザープロフィール管理とカスタマイズ
- 学習データのクラウド同期

## 設定方法

### 環境変数の設定

`.env` ファイルをプロジェクトルートに作成し、以下の変数を設定してください:

```
# AI API設定
DEEPSEEK_API_KEY=your_deepseek_api_key_here
GEMINI_API_KEY=your_gemini_api_key_here
OPENAI_API_KEY=your_openai_api_key_here

# Google Cloud Vision API設定（OCR用）
GOOGLE_BROWSER_KEY=your_browser_key_here
GOOGLE_IOS_KEY=your_ios_key_here
GOOGLE_ANDROID_KEY=your_android_key_here

# Stripe設定（Web決済用）
STRIPE_PUBLIC_KEY=your_stripe_public_key_here
STRIPE_SECRET_KEY=your_stripe_secret_key_here
```

各APIキーは以下のURLから取得できます：
- [DeepSeek AI](https://platform.deepseek.com)
- [Google AI Studio (Gemini)](https://aistudio.google.com/)
- [OpenAI](https://openai.com/)
- [Google Cloud Console](https://console.cloud.google.com/)
- [Stripe Dashboard](https://dashboard.stripe.com/)

### Firebase設定

1. Firebaseプロジェクトを作成し、以下のサービスを有効化:
   - Authentication (認証)
   - Firestore Database (データベース)
   - Storage (ファイルストレージ)
   - Functions (バックエンド関数)

2. 設定ファイルを配置:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
   - Web: `web/firebase-config.js`

## 開発環境

- Flutter: 3.19以上
- Dart: 3.0.0以上
- Firebase: 最新版推奨
- Android Studio / Visual Studio Code

## バックグラウンドサービス

アプリケーションには以下のバックグラウンドサービスが実装されています:
- AI処理サービス（記憶法生成、フィードバック提供）
- 定期的な復習通知
- コンテンツ同期機能

Flutter開発についての詳細は[オンラインドキュメント](https://docs.flutter.dev/)を参照してください。
# AnkiPai_Android
# AnkiPai_Android
# AnkiPai_Android
# AnkiPai_Android
