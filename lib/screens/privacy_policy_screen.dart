import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プライバシーポリシー'),
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 53, 152, 71),
                Color.fromARGB(255, 40, 130, 60),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'プライバシーポリシー',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '本アプリ「暗記Pai」（以下、本アプリ）は、個人情報を適切に取り扱うことの重要性を認識し、以下の通りプライバシーポリシー（以下、本ポリシー）を定めます。',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '第1条（収集する個人情報）',
              '本アプリが収集する個人情報は、以下のものを含みます：\n・利用者が自己の意思で提供するメールアドレス\n・利用者が公開する暗記法に含まれる情報（利用者名、投稿内容等）\n・利用者がアップロードした画像（OCR機能使用時）\n・デバイス情報（OSバージョン、デバイスの種類など）\n・利用統計情報（アプリの使用頻度、機能の使用状況など）',
            ),
            _buildSection(
              '第2条（個人情報の利用目的）',
              '・収集したメールアドレスは、本アプリの認証に利用します。\n・利用者名と投稿内容は、本アプリ内でのコミュニケーション促進のために利用することがあります。\n・アップロードされた画像は、OCR（文字認識）機能および暗記法生成のために利用します。\n・デバイス情報と利用統計情報は、アプリの改善とカスタマイズのために利用します。',
            ),
            _buildSection(
              '第3条（個人情報の管理）',
              '収集したメールアドレスは、Firebaseに保存され、利用者自身および本アプリの開発者のみがアクセス可能となります。公開された暗記法やコメントに含まれる情報は、本アプリの利用者にも公開されることになります。アップロードされた画像は、OCR処理のためにGoogle Cloud Visionサービスで一時的に処理されることがあります。',
            ),
            _buildSection(
              '第4条（利用者の権利）',
              '利用者は、自己の個人情報について、変更する権利を有します。この権利を行使するには、本アプリの設定から行うことができます。また、自分の公開した暗記法やコメントを編集または削除する権利も有します。',
            ),
            _buildSection(
              '第5条（アカウントの削除）',
              '利用者はいつでもアカウントを削除する権利を有します。アカウントを削除するには、プロフィール画面の設定セクションにある「アカウントを削除」ボタンをタップしてください。\n\nアカウントを削除すると、以下の情報が完全に削除されます：\n・ユーザーアカウント情報（メールアドレス、認証情報など）\n・プロフィール情報およびプロフィール画像\n・ユーザーが作成した暦記法やカードセット\n・ユーザーに関連するすべてのデータ\n\nこの操作は取り消すことができず、データは復元できません。アカウント削除後、再度登録することが可能ですが、以前のデータは引き継がれません。',
            ),
            _buildSection(
              '第6条（不満の申し立て）',
              '本アプリの個人情報の取り扱いに関する不満がある場合は、以下のメールアドレスまでご連絡ください\nAnkiPai.app@gmail.com',
            ),
            _buildSection(
              '第7条（外部サービスの利用）',
              '本アプリは以下の外部サービスを利用しており、それぞれのプライバシーポリシーが適用されます。\n\n・Firebase: ユーザー認証、データ保存\n・Google Cloud Vision API: 画像のテキスト認識（OCR）\n・OpenAI API: 暗記法の生成\n・Vertex AI Gemini: 暗記法の生成\n・Google AdMob: 広告配信\n\nこれらのサービスはそれぞれ独自のプライバシーポリシーを持っており、本アプリのプライバシーポリシーとは別に適用されます。',
            ),
            _buildSection(
              '第8条（広告について）',
              '本アプリはGoogle AdMobを使用して広告を配信しています。AdMobは広告を表示するために、デバイスID、IPアドレス、位置情報などの情報を収集することがあります。これらの情報の収集と使用については、Googleのプライバシーポリシー（https://policies.google.com/privacy）に従います。広告IDは設定からリセットまたはオプトアウトすることができます。',
            ),
            _buildSection(
              '第9条（プライバシーポリシーの変更）',
              '当社は、必要と認めた場合には、ユーザーに通知することなく本ポリシーを改定することができます。本ポリシーの改定は、当社が指定する方法によりユーザーに通知した時点より効力を生じるものとします。',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '2025年4月25日改定',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
