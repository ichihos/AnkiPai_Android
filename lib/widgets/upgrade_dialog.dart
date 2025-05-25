import 'package:flutter/material.dart';
import '../screens/subscription_info_screen.dart';
import '../models/subscription_model.dart';
import '../services/stripe_payment_service.dart';
import 'dart:math';

/// プレミアムプランへのアップグレードを促すダイアログ
class UpgradeDialog {
  /// プランアップグレードを促すダイアログを表示
  ///
  /// [context] - ビルドコンテキスト
  /// [mode] - 制限に達した機能のモード（'multi_agent', 'thinking'など）
  /// [remainingUses] - 残りの使用可能回数（通常は0）
  /// [totalUses] - 合計使用可能回数
  static Future<bool> show({
    required BuildContext context,
    required String mode,
    int remainingUses = 0,
    int? totalUses,
  }) async {
    // モードに応じたタイトルとメッセージを設定
    String title;
    String message;
    IconData icon;
    Color iconColor;

    switch (mode) {
      case 'multi_agent':
        title = 'マルチエージェントモード使用制限';
        message =
            'マルチエージェントモードの無料利用回数（${totalUses ?? SubscriptionModel.maxMultiAgentModeUsage}回）を使い切りました。'
            'プレミアムプランにアップグレードすると、マルチエージェントモードを無制限に使用できます。';
        icon = Icons.group_work_outlined;
        iconColor = Colors.purple;

        break;
      case 'thinking':
        title = '考え方モード使用制限';
        message =
            '考え方モードの無料利用回数（${totalUses ?? SubscriptionModel.maxThinkingModeUsage}回）を使い切りました。'
            'プレミアムプランにアップグレードすると、考え方モードを無制限に使用できます。';
        icon = Icons.psychology_outlined;
        iconColor = Colors.teal;
        break;
      case 'card_sets':
        title = 'カードセット数の制限';
        message = '無料プランでは最大${SubscriptionModel.maxCardSets}セットまでしか作成できません。'
            'プレミアムプランにアップグレードすると、カードセットを無制限に作成できます。';
        icon = Icons.folder_outlined;
        iconColor = Colors.blue;
        break;
      case 'cards_per_set':
        title = 'カード枚数の制限';
        message =
            '無料プランでは1セットあたり最大${SubscriptionModel.maxCardsPerSet}枚までしか作成できません。'
            'プレミアムプランにアップグレードすると、1セットあたりのカード枚数制限がなくなります。';
        icon = Icons.credit_card_outlined;
        iconColor = Colors.orange;
        break;
      default:
        title = '使用制限に達しました';
        message = 'プレミアムプランにアップグレードすると、この機能を無制限に使用できます。';
        icon = Icons.lock_outline;
        iconColor = Colors.red.shade700;
    }

    // ダイアログを表示して結果を返す
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: min(MediaQuery.of(context).size.width * 0.9, 450),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダー（プレミアムプラン）
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.shade700,
                      Colors.amber.shade300,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                width: double.infinity,
                child: Column(
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'プレミアムプラン',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '全ての機能を最大限に活用',
                      style: TextStyle(color: Colors.white.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),

              // コンテンツ（スクロール可能）
              Flexible(
                  child: SingleChildScrollView(
                      child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // タイトルと説明
                    Row(
                      children: [
                        Icon(icon, color: iconColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(message),
                    const SizedBox(height: 24),

                    // 特典リスト
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'プレミアム特典',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildBenefitRow(Icons.check_circle_outline,
                              Colors.green.shade700, '思考モードとマルチエージェントモードが無制限'),
                          _buildBenefitRow(Icons.check_circle_outline,
                              Colors.green.shade700, 'カードセット数無制限'),
                          _buildBenefitRow(Icons.check_circle_outline,
                              Colors.green.shade700, '各カードセットのカード枚数無制限'),
                          _buildBenefitRow(Icons.check_circle_outline,
                              Colors.green.shade700, '広告の非表示'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 料金プラン
                    Row(
                      children: [
                        Expanded(
                          child: _buildPriceOption(
                            'monthly',
                            '月額プラン',
                            '¥380',
                            '/月',
                            context,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _buildPriceOption(
                                'yearly',
                                '年間プラン',
                                '¥2,980',
                                '/年',
                                context,
                                isRecommended: true,
                              ),
                              Positioned(
                                top: -10,
                                right: -10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'かなりお得',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ))),

              // アクションボタン
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('後で'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(true);
                          // 詳細画面へ
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SubscriptionInfoScreen(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('詳細を見る'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  // 特典表示用のウィジェット
  static Widget _buildBenefitRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // 価格オプション表示用のウィジェット
  static Widget _buildPriceOption(String plan, String title, String price,
      String period, BuildContext context,
      {bool isRecommended = false}) {
    return GestureDetector(
      onTap: () async {
        try {
          // プランタイプを決定
          final type = plan == 'yearly'
              ? SubscriptionType.premium_yearly
              : SubscriptionType.premium_monthly;
          
          // 重要: コンテキスト参照エラーを避けるため、BuildContextをキャプチャ
          final NavigatorState navigator = Navigator.of(context);
          final ScaffoldMessengerState scaffoldMessenger = ScaffoldMessenger.of(context);
          
          // 安全にダイアログを閉じる
          navigator.pop(true);
          
          // 決済の実行前にマイクロ遅延を入れる
          await Future.delayed(const Duration(milliseconds: 300));

          try {
            // Stripe決済開始 - 外部ブラウザで開きます
            final result = await StripePaymentService.startSubscription(type);
            
            // 注意: URLが開かれた後はエラーメッセージを表示しない (コンテキストが存在しない可能性があるため)
            // URLが開く前に失敗した場合のみエラーを表示
            if (result['success'] != true && result['url'] == null) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('決済の開始に失敗しました。後ほどお試しください。')),
              );
            }
          } catch (e) {
            // エラー処理 - URLが開く前に発生したエラーのみ表示
            scaffoldMessenger.showSnackBar(
              SnackBar(content: Text('決済ページ読み込みエラー: $e')),
            );
          }
        } catch (e) {
          // 初期化時の例外処理
          print('購入初期化処理エラー: $e');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isRecommended ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRecommended ? Colors.blue.shade300 : Colors.grey.shade300,
            width: isRecommended ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isRecommended ? Colors.blue.shade700 : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isRecommended ? Colors.blue.shade700 : Colors.black,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                // 選択されたプランでStripe決済を開始
                Navigator.of(context).pop(true);

                try {
                  final type = plan == 'yearly'
                      ? SubscriptionType.premium_yearly
                      : SubscriptionType.premium_monthly;

                  // Stripe決済開始
                  final result =
                      await StripePaymentService.startSubscription(type);

                  if (result['success'] != true) {
                    // 決済開始に失敗した場合
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('決済の開始に失敗しました。後ほどお試しください。')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('エラーが発生しました: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isRecommended ? Colors.blue.shade600 : Colors.grey.shade200,
                foregroundColor: isRecommended ? Colors.white : Colors.black87,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'アップグレード',
                style: TextStyle(
                    fontWeight:
                        isRecommended ? FontWeight.bold : FontWeight.normal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
