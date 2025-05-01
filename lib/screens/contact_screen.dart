import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  // お問い合わせメールアドレス
  final String _contactEmail = 'AnkiPai.app@gmail.com'; // 実際のメールアドレス

  Future<void> launchMail(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      final Error error = ArgumentError('Error launching $url');
      throw error;
    }
  }

  void openMailApp() async {
    final title = Uri.encodeComponent('お問い合わせ');
    final body = Uri.encodeComponent(
        '暗記Paiに関するお問い合わせ、ご意見、バグ報告などございましたら、お気軽にお問い合わせください。');
    const mailAddress = 'AnkiPai.app@gmail.com'; //メールアドレス

    return launchMail(
      'mailto:$mailAddress?subject=$title&body=$body',
    );
  }

  // メールアドレスをコピー
  void _copyEmailToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _contactEmail));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('メールアドレスをコピーしました'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お問い合わせ'),
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
            // アイコンとタイトル
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 80,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'お問い合わせ',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // お問い合わせ方法の説明
            Text(
              '暗記Paiに関するご質問、ご意見、バグ報告などがございましたら、以下のメールアドレスまでお気軽にお問い合わせください。',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // メールアドレス表示カード
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.email, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      Text(
                        'メールアドレス',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      _contactEmail,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (!kIsWeb) {
                              openMailApp();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Webブラウザではメールを開くことができません。お問い合わせメールアドレスをコピーして、メールソフトで送信してください。'),
                                  backgroundColor: Colors.black,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.mail_outline),
                          label: const Text('メールを送信'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color.fromARGB(255, 53, 152, 71),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _copyEmailToClipboard(context),
                        icon: const Icon(Icons.copy),
                        tooltip: 'コピー',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 注意事項
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text(
                        'お問い合わせの際の注意事項',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• お問い合わせの内容によっては、回答に時間がかかる場合があります。\n'
                    '• アプリのバージョン、お使いのデバイスの情報をお知らせいただくと、より早く問題解決ができます。\n'
                    '• バグ報告の際は、発生状況をできるだけ詳しくお知らせください。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
