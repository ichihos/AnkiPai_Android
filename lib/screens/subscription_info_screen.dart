import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/subscription_service.dart';
import '../services/stripe_payment_service.dart';
import '../models/subscription_model.dart';

class SubscriptionInfoScreen extends StatefulWidget {
  const SubscriptionInfoScreen({super.key});

  @override
  State<SubscriptionInfoScreen> createState() => _SubscriptionInfoScreenState();
}

class _SubscriptionInfoScreenState extends State<SubscriptionInfoScreen> {
  SubscriptionModel? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionInfo();

    // Web環境の場合、Stripeを初期化
    if (kIsWeb) {
      StripePaymentService.initialize();
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      final subscription = await subscriptionService.getUserSubscription();

      // デバッグ情報を出力
      print(
          'サブスクリプション情報を取得: type=${subscription.type}, status=${subscription.status}');
      if (subscription.status != null) {
        print('サブスクリプション状態: ${subscription.status}');
        print('解約予定日: ${subscription.cancelAt}');
      }

      setState(() {
        _subscription = subscription;
        _isLoading = false;
      });
    } catch (e) {
      print('サブスクリプション情報取得エラー: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('サブスクリプション情報の取得に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // プレミアムへのアップグレードダイアログを表示
  void _showPremiumUpgradeDialog(
      {SubscriptionType planType = SubscriptionType.premium_monthly}) {
    String planName = planType == SubscriptionType.premium_yearly ? '年間' : '月間';
    String price =
        planType == SubscriptionType.premium_yearly ? '¥2,980/年' : '¥380/月';

    showDialog(
      context: context,
      barrierDismissible: false, // ダイアログ外タップでの閉じるを防止
      builder: (BuildContext dialogContext) {
        // ローディング状態を管理するためのStatefulBuilderを使用
        return StatefulBuilder(
          builder: (context, setState) {
            // ローディング状態を管理
            bool isLoading = false;
            String statusMessage = '';

            // 購入処理を実行
            Future<void> processPurchase() async {
              setState(() {
                isLoading = true;
                statusMessage = '処理を開始しています...';
              });

              try {
                // Web環境ではStripePaymentServiceを使用
                if (kIsWeb) {
                  setState(() {
                    statusMessage = '決済ページへ移動します...';
                  });

                  // 少し待機して状態更新を画面に反映させる
                  await Future.delayed(const Duration(milliseconds: 100));

                  // ダイアログを閉じる
                  Navigator.pop(dialogContext);

                  // Webブラウザでの支払い処理前にSnackBar表示
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('決済ページに移動します。処理が完了するまでお待ちください...'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 3),
                    ),
                  );

                  // Stripe決済処理
                  final result =
                      await StripePaymentService.startSubscription(planType);

                  if (result['success']) {
                    // 決済画面に遷移成功
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('決済ページに移動しました。決済完了後、このページに戻ってください。'),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 8),
                        ),
                      );
                    }
                  } else {
                    // エラーメッセージを表示
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('決済ページへの移動に失敗しました: ${result['error']}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } else {
                  // ネイティブアプリでの課金処理
                  setState(() {
                    statusMessage = 'アプリ内課金を実行中です。\nストアが起動するまでお待ちください...';
                  });

                  // 少し待機して状態更新を画面に反映させる
                  await Future.delayed(const Duration(milliseconds: 500));

                  final subscriptionService =
                      Provider.of<SubscriptionService>(context, listen: false);

                  // ダイアログを閉じる
                  Navigator.pop(dialogContext);

                  // ユーザーに課金処理が開始されたことを通知
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('課金処理を開始しています。App Storeの画面が表示されます...'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 3),
                    ),
                  );

                  // プランタイプに応じた処理を実行
                  try {
                    if (planType == SubscriptionType.premium_yearly) {
                      await subscriptionService.purchaseYearlyPlan();
                    } else {
                      await subscriptionService.purchaseMonthlyPlan();
                    }

                    // 少し待機してから最新情報を読み込む（購入処理が完了する時間を考慮）
                    await Future.delayed(const Duration(seconds: 1));
                    await _loadSubscriptionInfo();

                    // 成功メッセージ
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$planName 食べ放題（プレミアム）プランに変更しました！'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('購入処理中にエラーが発生: $e');
                    // 購入キャンセルの場合は特に通知しない（ユーザーが意図的にキャンセルした場合）
                    if (!e.toString().contains('canceled') &&
                        !e.toString().contains('キャンセル') &&
                        !e.toString().contains('cancel')) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('購入処理中にエラーが発生しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      // キャンセルの場合は控えめな通知
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('購入はキャンセルされました'),
                            backgroundColor: Colors.grey,
                          ),
                        );
                      }
                    }
                  }
                }
              } catch (e) {
                // ダイアログがまだ表示されている場合は閉じる
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.pop(dialogContext);
                }

                print('購入初期化処理エラー: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('購入処理の準備中にエラーが発生しました: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                // mountedおよびdialogContextが有効か確認
                if (mounted) {
                  try {
                    // 安全にダイアログの状態を確認
                    var canPop = false;
                    try {
                      canPop = Navigator.of(dialogContext).canPop();
                    } catch (e) {
                      print('DialogContextが無効です: $e');
                    }

                    if (canPop) {
                      setState(() {
                        isLoading = false;
                      });
                    }
                  } catch (contextError) {
                    print('コンテキストエラー: $contextError');
                  }
                }
              }
            }

            return AlertDialog(
              title: Text('$planName 食べ放題（プレミアムプランへのアップグレード'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ローディング中の表示
                  if (isLoading) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],

                  // 通常の内容（ローディング中は非表示）
                  if (!isLoading) ...[
                    // 選択したプラン表示
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: planType == SubscriptionType.premium_yearly
                            ? Colors.amber.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: planType == SubscriptionType.premium_yearly
                              ? Colors.amber.shade300
                              : Colors.blue.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$planName プラン: $price',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: planType == SubscriptionType.premium_yearly
                                  ? Colors.amber.shade800
                                  : Colors.blue.shade800,
                            ),
                          ),
                          if (planType == SubscriptionType.premium_yearly)
                            const Text('お得な年間プランでは、月額換算で約２ヶ月分お得になります。',
                                style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('食べ放題（プレミアム）プランでは以下の特典があります:'),
                    const SizedBox(height: 8),
                    const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      contentPadding: EdgeInsets.zero,
                      title: Text('考え方モードとマルチエージェントモードが無制限'),
                      dense: true,
                    ),
                    const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      contentPadding: EdgeInsets.zero,
                      title: Text('カードセット数無制限'),
                      dense: true,
                    ),
                    const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      contentPadding: EdgeInsets.zero,
                      title: Text('各カードセットのカード枚数無制限'),
                      dense: true,
                    ),
                    const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      contentPadding: EdgeInsets.zero,
                      title: Text('広告の非表示'),
                      dense: true,
                    ),
                  ],
                ],
              ),
              actions: [
                // ローディング中はボタンを無効化
                if (!isLoading) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('キャンセル'),
                  ),
                  ElevatedButton(
                    onPressed: processPurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          planType == SubscriptionType.premium_yearly
                              ? Colors.amber.shade600
                              : Colors.blue.shade600,
                    ),
                    child: const Text('購入する'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // 残り使用回数を取得
  int _getRemainingUses(String mode) {
    if (_subscription == null) return 0;

    switch (mode) {
      case 'multi_agent':
        return _subscription!.remainingMultiAgentModeUses;
      case 'thinking':
        return _subscription!.remainingThinkingModeUses;
      default:
        return -1; // 標準モードは制限なし
    }
  }

  // モード別の残り使用回数テキストを取得
  String _getRemainingUsesText(String mode) {
    final remaining = _getRemainingUses(mode);
    return remaining < 0 ? '無制限' : '残り$remaining回';
  }

  // 使用状況を表示するカード
  Widget _buildUsageCard(String title, String description, String usageText,
      IconData icon, Color color) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    usageText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('暗記パイ食べ放題（プレミアム）プラン'),
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
        actions: [
          // 情報更新ボタン
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '情報を更新',
            onPressed: () async {
              if (kIsWeb) {
                // Web環境ではトークンをリフレッシュする必要がある
                final subscriptionService =
                    Provider.of<SubscriptionService>(context, listen: false);
                await subscriptionService.refreshSubscription();
              }
              _loadSubscriptionInfo();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('サブスクリプション情報を更新しました'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // プランタイトル
                    const Text(
                      'プランと料金',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 現在のプラン状態
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _subscription?.isPremium ?? false
                            ? Colors.amber.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _subscription?.isPremium ?? false
                              ? Colors.amber.shade300
                              : Colors.blue.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _subscription?.isPremium ?? false
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _subscription?.isPremium ?? false
                                ? Colors.amber.shade700
                                : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _subscription?.isPremium ?? false
                                  ? 'あなたは現在食べ放題（プレミアム）プランをご利用中です'
                                  : 'あなたは現在無料プランをご利用中です',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _subscription?.isPremium ?? false
                                    ? Colors.amber.shade700
                                    : Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // プラン比較カード
                    Row(children: [
                      // 月額プラン
                      Expanded(
                        child: Card(
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // プランタイトル
                                const Text(
                                  '月間食べ放題（プレミアム）',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // 価格
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '¥380',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      ' /月',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '税込み',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '食べ放題（プレミアム）プランを一ヶ月間ご利用いただけます',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // 月額購入ボタン
                                if (!(_subscription?.isPremium ?? false))
                                  ElevatedButton(
                                    onPressed: () => _showPremiumUpgradeDialog(
                                        planType:
                                            SubscriptionType.premium_monthly),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade600,
                                      minimumSize:
                                          const Size(double.infinity, 40),
                                    ),
                                    child: const Text('月間プランに変更',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.black)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // 年額プラン
                      Expanded(
                          child: Card(
                              elevation: 5, // 年額プランの方を強調
                              color: Colors.amber.shade50,
                              child: Stack(children: [
                                // お得バッジ
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade500,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(4),
                                        bottomLeft: Radius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      'お得',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),

                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          // プランタイトル
                                          const Text(
                                            '年間食べ放題（プレミアム）',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),

                                          // 価格
                                          const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Text(
                                                '¥2,980',
                                                style: TextStyle(
                                                  fontSize: 26,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ' /年',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              '月額換算 ¥248  (２ヶ月分お得)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '税込み',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            '食べ放題（プレミアム）プランを一年間ご利用いただけます',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // 年額購入ボタン
                                          if (!(_subscription?.isPremium ??
                                              false))
                                            ElevatedButton(
                                                onPressed: () =>
                                                    _showPremiumUpgradeDialog(
                                                        planType:
                                                            SubscriptionType
                                                                .premium_yearly),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.amber.shade600,
                                                  minimumSize: const Size(
                                                      double.infinity, 40),
                                                ),
                                                child: const Text('お得な年間プランに変更',
                                                    style: TextStyle(
                                                        color: Colors.black))),
                                        ]))
                              ]))),
                    ]),
                    const SizedBox(height: 12),

                    // 食べ放題プランの説明
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '食べ放題（プレミアム）プランでは広告の表示が無くなり、以下の機能の制限が開放されます。\n・暗記カード枚数制限\n・カードセット数制限\n・マルチエージェントモード回数制限\n・考え方モード回数制限',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      '使用状況',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // AI特殊モードの使用状況
                    _buildUsageCard(
                      'マルチエージェントモード',
                      '複数のAIエージェントが協力して暗記法を生成します',
                      _getRemainingUsesText('multi_agent'),
                      Icons.group_work_outlined,
                      Colors.purple,
                    ),

                    _buildUsageCard(
                      '考え方モード',
                      '内容の本質を捉えた説明を生成します',
                      _getRemainingUsesText('thinking'),
                      Icons.psychology_outlined,
                      Colors.teal,
                    ),

                    _buildUsageCard(
                      'カードセット数',
                      'カードセットの作成数制限',
                      _subscription?.isPremium ?? false
                          ? '無制限'
                          : '最大${SubscriptionModel.maxCardSets}セット',
                      Icons.folder_outlined,
                      Colors.blue,
                    ),

                    _buildUsageCard(
                      'カード枚数制限',
                      '1セットあたりのカード枚数制限',
                      _subscription?.isPremium ?? false
                          ? '無制限'
                          : '最大${SubscriptionModel.maxCardsPerSet}枚/セット',
                      Icons.credit_card_outlined,
                      Colors.orange,
                    ),

                    // 次回のリセット日
                    if (!(_subscription?.isPremium ?? false) &&
                        _subscription != null)
                      Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(top: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '使用量リセット日',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _subscription!.usageResetDate != null
                                    ? '次回の使用回数リセット日: ${_subscription!.usageResetDate!.year}年${_subscription!.usageResetDate!.month}月${_subscription!.usageResetDate!.day}日'
                                    : 'リセット日が設定されていません',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // サブスクリプション管理セクション
                    if (_subscription != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 32.0, bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 24),
                            const Text(
                              'サブスクリプション管理',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // サブスクリプションの状態に応じてボタンを切り替え
                            if (_subscription!.isPremium &&
                                (_subscription!.status == 'active' ||
                                    _subscription!.status == null))
                              // アクティブなプレミアムユーザー向けの解約ボタン
                              ElevatedButton(
                                onPressed: () =>
                                    _showCancelSubscriptionDialog(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red.shade700,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side:
                                        BorderSide(color: Colors.red.shade200),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cancel_outlined),
                                    SizedBox(width: 8),
                                    Text('サブスクリプションを解約する',
                                        style: TextStyle(fontSize: 16)),
                                  ],
                                ),
                              )
                            else if (_subscription!.status == 'canceling' ||
                                _subscription!.status == 'canceled')
                              // 解約済みまたは解約予定のユーザー向けの再開ボタン
                              ElevatedButton(
                                onPressed: () =>
                                    _showReactivateSubscriptionDialog(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade50,
                                  foregroundColor: Colors.green.shade700,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                        color: Colors.green.shade200),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.refresh),
                                    SizedBox(width: 8),
                                    Text('サブスクリプションを再開する',
                                        style: TextStyle(fontSize: 16)),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 8),

                            // 状態に応じた説明テキスト
                            if (_subscription!.isPremium &&
                                (_subscription!.status == 'active' ||
                                    _subscription!.status == null))
                              Text(
                                '解約すると、暗記のためのさまざまな機能が制限されます。現在の期間が終了するまでは引き続きご利用いただけます。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              )
                            else if (_subscription!.status == 'canceling')
                              Text(
                                'サブスクリプションは解約予定です。${_subscription!.cancelAt != null ? _formatDate(_subscription!.cancelAt!) : '次回の課金日'}以降は無料プランに切り替わります。再開すると現在のプランが継続されます。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              )
                            else if (_subscription!.status == 'canceled')
                              Text(
                                'サブスクリプションは現在解約されています。食べ放題（プレミアム）プランを再度ご利用いただくには、サブスクリプションを再開してください。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // 日付を文字列にフォーマットするメソッド
  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  // サブスクリプション解約確認ダイアログを表示
  Future<void> _showCancelSubscriptionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サブスクリプションの解約'),
        content: const Text(
            '本当にサブスクリプションを解約しますか？\n\n解約すると、現在の課金期間が終了した後は食べ放題（プレミアム）プランが利用できなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解約する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ローディングダイアログを表示
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('解約処理中...')
          ],
        ),
      ),
    );

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      final result = await subscriptionService.cancelSubscription();

      print('解約処理結果: $result');

      // ローディングダイアログを閉じる
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        // 成功時
        if (mounted) {
          // サブスクリプション情報を再取得して状態を更新
          await _loadSubscriptionInfo();

          // 正しく更新されたか確認するデバッグログ
          print(
              '解約後の状態: ${_subscription?.status}, タイプ: ${_subscription?.type}');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? '解約手続きが完了しました'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // マニュアルアクションが必要な場合（iOSなど）は追加の案内を表示
          if (result['requires_manual_action'] == true) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('追加手順が必要です'),
                  content:
                      const Text('サブスクリプションを完全に解約するには、開いた設定ページで手続きを完了させてください。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('了解しました'),
                    ),
                  ],
                ),
              );
            }
          }

          // UIを強制的に再描画
          setState(() {});
        }
      } else {
        // エラー時
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('解約処理に失敗しました: ${result['error'] ?? '不明なエラー'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // 例外発生時
      if (mounted) {
        Navigator.of(context).pop(); // ローディングダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('解約処理中にエラーが発生しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // サブスクリプション再開ダイアログを表示
  Future<void> _showReactivateSubscriptionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サブスクリプションの再開'),
        content:
            const Text('サブスクリプションを再開しますか？\n\n現在解約予定または解約済みのサブスクリプションを再開します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.green,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('再開する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ローディングダイアログを表示
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('サブスクリプションを再開中...')
          ],
        ),
      ),
    );

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      final result = await subscriptionService.reactivateSubscription();

      // ローディングダイアログを閉じる
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        // 成功時
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'サブスクリプションが再開されました'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // 情報を再読み込み
          _loadSubscriptionInfo();
        }
      } else {
        // エラー時
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('サブスクリプションの再開に失敗しました: ${result['error'] ?? '不明なエラー'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // 例外発生時
      if (mounted) {
        Navigator.of(context).pop(); // ローディングダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('サブスクリプションの再開中にエラーが発生しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
