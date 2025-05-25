import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// アプリの使い方画面
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.howToUseTitle),
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
              AppLocalizations.of(context)!.howToUseIntro,
              AppLocalizations.of(context)!.howToUseIntroContent,
              Icons.lightbulb_outline,
              Colors.amber,
            ),
            _buildFeature(
              context,
              AppLocalizations.of(context)!.howToUseFeature1Title,
              AppLocalizations.of(context)!.howToUseFeature1Content,
              AppLocalizations.of(context)!.howToUseFeature1Steps,
              Icons.text_fields,
              Colors.blue,
              // const AssetImage('assets/images/how_to_1.png'),
            ),
            _buildFeature(
              context,
              AppLocalizations.of(context)!.howToUseFeature2Title,
              AppLocalizations.of(context)!.howToUseFeature2Content,
              AppLocalizations.of(context)!.howToUseFeature2Steps,
              Icons.image_search,
              Colors.green,
              // const AssetImage('assets/images/how_to_2.png'),
            ),
            _buildFeature(
              context,
              AppLocalizations.of(context)!.howToUseFeature3Title,
              AppLocalizations.of(context)!.howToUseFeature3Content,
              AppLocalizations.of(context)!.howToUseFeature3Steps,
              Icons.folder_copy,
              Colors.orange,
              // const AssetImage('assets/images/how_to_3.png'),
            ),
            _buildFeature(
              context,
              AppLocalizations.of(context)!.howToUseFeature4Title,
              AppLocalizations.of(context)!.howToUseFeature4Content,
              AppLocalizations.of(context)!.howToUseFeature4Steps,
              Icons.public,
              Colors.purple,
              // const AssetImage('assets/images/how_to_4.png'),
            ),
            _buildFeature(
              context,
              AppLocalizations.of(context)!.howToUseFeature5Title,
              AppLocalizations.of(context)!.howToUseFeature5Content,
              AppLocalizations.of(context)!.howToUseFeature5Steps,
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
                Text(
                  AppLocalizations.of(context)!.howToUseHowTo,
                  style: const TextStyle(
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
              Text(
                AppLocalizations.of(context)!.howToUseTipsTitle,
                style: const TextStyle(
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
            AppLocalizations.of(context)!.howToUseTip1,
          ),
          _buildTipItem(
            context,
            Icons.image_outlined,
            AppLocalizations.of(context)!.howToUseTip2,
          ),
          _buildTipItem(
            context,
            Icons.touch_app_outlined,
            AppLocalizations.of(context)!.howToUseTip3,
          ),
          _buildTipItem(
            context,
            Icons.psychology_outlined,
            AppLocalizations.of(context)!.howToUseTip4,
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
