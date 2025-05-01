import 'package:flutter/material.dart';

/// アプリの使い方画面
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('暗記パイの使い方'),
        elevation: 0,
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              'はじめに',
              '暗記パイは、AIを活用して暗記学習をサポートするアプリです。テキストや画像から暗記法を自動生成し、効率的な学習をお手伝いします。',
              Icons.lightbulb_outline,
              Colors.amber,
            ),
            _buildFeature(
              context,
              'テキスト入力からの暗記法生成',
              '覚えたい内容をテキスト入力すると、AIが最適な暗記法を提案します。',
              'テキストを入力 → 「暗記法を生成」ボタンをタップ → AIが暗記法を提案',
              Icons.text_fields,
              Colors.blue,
              // const AssetImage('assets/images/how_to_1.png'),
            ),
            _buildFeature(
              context,
              '画像からの暗記法生成（OCR機能）',
              '画像からテキストを自動抽出し、その内容に基づいた暗記法を生成します。',
              '画像アイコンをタップ → 画像を選択・撮影 → テキストを抽出 → 暗記法を生成',
              Icons.image_search,
              Colors.green,
              // const AssetImage('assets/images/how_to_2.png'),
            ),
            _buildFeature(
              context,
              'カードセットでの学習管理',
              '関連する暗記項目をカードセットとしてまとめて管理できます。',
              'カードセットタブを選択 → 「新規作成」ボタンをタップ → カードを追加',
              Icons.folder_copy,
              Colors.orange,
              // const AssetImage('assets/images/how_to_3.png'),
            ),
            _buildFeature(
              context,
              '公開暗記法の活用',
              '他のユーザーが公開した暗記法を閲覧・利用することができます。',
              'ライブラリタブを選択 → 公開暗記法を検索・閲覧 → 自分の暗記項目に追加',
              Icons.public,
              Colors.purple,
              // const AssetImage('assets/images/how_to_4.png'),
            ),
            _buildFeature(
              context,
              'AIモードの切り替え',
              '用途に応じて異なるAIモードを選択できます。',
              '標準モード：基本的な暗記法を生成\nマルチエージェントモード：複数のAIが協力して最適な暗記法を提案\n考え方モード：なぜその暗記法が効果的かの解説も含めて提案',
              Icons.psychology,
              Colors.teal,
              // const AssetImage('assets/images/how_to_5.png'),
            ),
            _buildTips(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // セクションを構築
  Widget _buildSection(BuildContext context, String title, String description,
      IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // 機能説明を構築
  Widget _buildFeature(
    BuildContext context,
    String title,
    String description,
    String steps,
    IconData icon,
    Color color,
    // ImageProvider? image,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 説明
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '使い方：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  steps,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                // 画像があれば表示
                // if (image != null) ...[
                //   const SizedBox(height: 16),
                //   ClipRRect(
                //     borderRadius: BorderRadius.circular(8),
                //     child: Image(
                //       image: image,
                //       fit: BoxFit.cover,
                //       width: double.infinity,
                //       height: 160,
                //     ),
                //     ),
                //   ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 暗記テクニックのヒントを構築
  Widget _buildTips(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              const Text(
                '暗記のコツ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTipItem(
            context,
            Icons.repeat,
            '間隔を空けて繰り返し復習することで記憶の定着率が上がります。',
          ),
          _buildTipItem(
            context,
            Icons.image_outlined,
            'イメージを使うと抽象的な内容も覚えやすくなります。',
          ),
          _buildTipItem(
            context,
            Icons.touch_app_outlined,
            '実際に書いたり、声に出すと記憶が定着しやすくなります。',
          ),
          _buildTipItem(
            context,
            Icons.psychology_outlined,
            '自分の既知の情報と関連付けると覚えやすくなります。',
          ),
        ],
      ),
    );
  }

  // ヒントアイテムを構築
  Widget _buildTipItem(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 14,
              color: Colors.amber.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
