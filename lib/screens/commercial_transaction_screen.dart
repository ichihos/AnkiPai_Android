import 'package:flutter/material.dart';

/// 特定商取引法に基づく表記画面
class CommercialTransactionScreen extends StatelessWidget {
  const CommercialTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('特定商取引法に基づく表記'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('販売業社名'),
              _buildContentText('細辻一'),
              _buildSectionTitle('代表者'),
              _buildContentText('細辻一'),
              _buildSectionTitle('所在地'),
              _buildContentText('メールアドレスへご請求いただければ、遅滞なく開示いたします。'),
              _buildSectionTitle('電話番号'),
              _buildContentText('メールアドレスへご請求いただければ、遅滞なく開示いたします。'),
              _buildSectionTitle('連絡先'),
              _buildContentText('メールアドレス: AnkiPai.app@gmail.com'),
              _buildSectionTitle('商品の販売価格'),
              _buildContentText('暗記Pai月間プレミアムプラン：380円（税込）\n'
                  '暗記Pai年間プレミアムプラン：2,980円（税込）'),
              _buildSectionTitle('商品代金以外の必要料金'),
              _buildContentText('なし（インターネット接続料金はお客様負担となります）'),
              _buildSectionTitle('引き渡し時期'),
              _buildContentText('お支払い完了後、即時にご利用いただけます。'),
              _buildSectionTitle('支払方法'),
              _buildContentText(
                  'クレジットカード（Visa, Mastercard, American Express, JCB, Discover）\n'
                  '※決済処理はStripe社のシステムを使用しています。'),
              _buildSectionTitle('支払時期'),
              _buildContentText('月間プレミアムプラン：申込時及び毎月の契約応当日に自動決済\n'
                  '年間プレミアムプラン：申込時及び毎年の契約応当日に自動決済'),
              _buildSectionTitle('キャンセル・返品・交換について'),
              _buildContentText('デジタルコンテンツの性質上、お申込み後のキャンセル・返品・返金はお受けしておりません。\n'
                  'サブスクリプションはいつでも解約可能ですが、日割り計算による返金は行いません。\n'
                  '解約後は契約期間満了まで引き続きサービスをご利用いただけます。'),
              _buildSectionTitle('動作環境'),
              _buildContentText('iOS: iOS 14.0以上\n'
                  'Android: Android 6.0以上\n'
                  'Web: 最新版のGoogle Chrome, Safari, Firefox, Microsoft Edge'),
              _buildSectionTitle('サービス提供の停止・中断について'),
              _buildContentText(
                  '以下の場合、事前の通知なくサービスの全部または一部の提供を停止または中断する場合があります。\n'
                  '・システムの保守点検または更新を定期的または緊急に行う場合\n'
                  '・地震、落雷、火災、停電、天災などの不可抗力により、サービスの提供が困難となった場合\n'
                  '・その他、運営者が停止または中断を必要と判断した場合'),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '最終更新日: 2025年4月16日',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// セクションタイトルを構築
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Color.fromARGB(255, 53, 152, 71),
        ),
      ),
    );
  }

  /// コンテンツテキストを構築
  Widget _buildContentText(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
        ),
      ),
    );
  }
}
