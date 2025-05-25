import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/subscription_service.dart';
import '../services/stripe_payment_service.dart';
import '../models/subscription_model.dart';
import '../constants/subscription_constants.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    // ウィジェットがまだマウントされているか確認
    if (!mounted) return;

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

      // ウィジェットがまだマウントされているか確認
      if (mounted) {
        setState(() {
          _subscription = subscription;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('サブスクリプション情報取得エラー: $e');
      // ウィジェットがまだマウントされているか確認
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.subscriptionInfo + ': $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // プレミアムへのアップグレードダイアログを表示
  void _showPremiumUpgradeDialog(
      {SubscriptionType planType = SubscriptionType.premium_monthly}) {
    String planName = planType == SubscriptionType.premium_yearly
        ? AppLocalizations.of(context)!.yearlyLabel
        : AppLocalizations.of(context)!.monthlyLabel;

    // ロケールに基づいた価格表示
    final locale = Localizations.localeOf(context).toString();
    String price = planType == SubscriptionType.premium_yearly
        ? SubscriptionConstants.getYearlyPriceDisplay(locale)
        : SubscriptionConstants.getMonthlyPriceDisplay(locale);

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
                  statusMessage =
                      AppLocalizations.of(context)!.processingPayment;
                });

                try {
                  // Web環境ではStripePaymentServiceを使用
                  if (kIsWeb) {
                    setState(() {
                      statusMessage =
                          AppLocalizations.of(context)!.processingPayment;
                    });

                    // 少し待機して状態更新を画面に反映させる
                    await Future.delayed(const Duration(milliseconds: 100));

                    // ダイアログを閉じる
                    Navigator.pop(dialogContext);

                    // Webブラウザでの支払い処理前にSnackBar表示
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .redirectingToPaymentPage),
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
                          SnackBar(
                            content: Text(AppLocalizations.of(context)!
                                .paymentPageRedirected),
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
                            content:
                                Text('決済ページへの移動に失敗しました: ${result['error']}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  } else {
                    // ネイティブアプリでの課金処理
                    setState(() {
                      statusMessage =
                          AppLocalizations.of(context)!.processingInAppPurchase;
                    });

                    // 少し待機して状態更新を画面に反映させる
                    await Future.delayed(const Duration(milliseconds: 500));

                    final subscriptionService =
                        Provider.of<SubscriptionService>(context,
                            listen: false);

                    // ダイアログを閉じる
                    Navigator.pop(dialogContext);

                    // ユーザーに課金処理が開始されたことを通知
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .startingBillingProcess),
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
                            content: Text(
                                '${planName} ${AppLocalizations.of(context)!.premiumPlanChanged}'),
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
                  bool isDialogContextValid = false;
                  try {
                    // dialogContextの安全なチェック方法
                    isDialogContextValid = ModalRoute.of(dialogContext) != null;
                  } catch (contextError) {
                    print('ダイアログコンテキストの参照エラー: $contextError');
                    isDialogContextValid = false;
                  }

                  // ダイアログが有効な場合のみ閉じる処理を行う
                  if (isDialogContextValid) {
                    try {
                      Navigator.pop(dialogContext);
                    } catch (navError) {
                      print('ダイアログの閉じる処理エラー: $navError');
                    }
                  }

                  print('購入初期化処理エラー: $e');
                  // 非同期処理後の安全なUI更新
                  // Futureで遅延実行してマイクロタスクキューをクリアにする
                  Future.microtask(() {
                    if (mounted) {
                      try {
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('購入処理の準備中にエラーが発生しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } catch (scaffoldError) {
                        print('スナックバー表示エラー: $scaffoldError');
                        // エラーメッセージを表示できない場合はコンソールにログ記録のみ
                      }
                    }
                  });
                } finally {
                  // 操作の完了時にローディング状態をリセット
                  Future.microtask(() {
                    if (mounted) {
                      try {
                        // ダイアログのコンテキストに依存せずに状態を更新
                        setState(() {
                          isLoading = false;
                        });
                      } catch (stateError) {
                        print('状態更新エラー: $stateError');
                      }
                    }
                  });
                }
              }

              return AlertDialog(
                title:
                    Text('$planName ${AppLocalizations.of(context)!.premium}'),
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
                                color:
                                    planType == SubscriptionType.premium_yearly
                                        ? Colors.amber.shade800
                                        : Colors.blue.shade800,
                              ),
                            ),
                            if (planType == SubscriptionType.premium_yearly)
                              Text(
                                  AppLocalizations.of(context)!
                                      .yearlyPlanBenefit,
                                  style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)!.premiumPlanBenefits),
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
                      child: Text(AppLocalizations.of(context)!.purchase),
                    ),
                  ],
                ],
              );
            },
          );
        });
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

  // Get remaining uses text by mode
  String _getRemainingUsesText(String mode) {
    final remaining = _getRemainingUses(mode);
    if (remaining < 0) {
      return AppLocalizations.of(context)!.unlimitedUsage;
    } else {
      // The remainingUses string is a function that takes a count parameter
      return AppLocalizations.of(context)!.remainingUses(remaining);
    }
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
        title: Text(AppLocalizations.of(context)!.subscriptionInfo),
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
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.refreshSubscriptionInfo),
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
                    // Plan title
                    Text(
                      AppLocalizations.of(context)!.plansAndPricing,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Current plan status
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
                                  ? AppLocalizations.of(context)!
                                      .currentlyUsingPremium
                                  : AppLocalizations.of(context)!
                                      .currentlyUsingFree,
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

                    // Plan comparison cards
                    Row(children: [
                      // Monthly plan
                      Expanded(
                        child: Card(
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Plan title
                                Text(
                                  AppLocalizations.of(context)!
                                      .monthlyPremiumPlan,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // 価格 - ロケールベースの表示
                                Builder(builder: (context) {
                                  final locale = Localizations.localeOf(context)
                                      .toString();
                                  final isJapanese = locale.startsWith('ja');

                                  // 通貨記号と金額部分 - 英語表示はすべてドルにする
                                  String currencySymbol =
                                      isJapanese ? '¥' : '\$';
                                  String amount = isJapanese ? '380' : '1.99';
                                  // 期間表記
                                  String period = isJapanese ? '/月' : '/month';

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        currencySymbol + amount,
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        ' ' + period,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context)!.taxIncluded,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  AppLocalizations.of(context)!
                                      .monthlyPremiumDescription,
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
                                    child: Text(
                                        AppLocalizations.of(context)!
                                            .switchToMonthlyPlan,
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.black)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Yearly plan
                      Expanded(
                          child: Card(
                              elevation: 5, // 年額プランの方を強調
                              color: Colors.amber.shade50,
                              child: Stack(children: [
                                // Best value badge
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
                                    child: Text(
                                      AppLocalizations.of(context)!.bestValue,
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
                                          // Plan title
                                          Text(
                                            AppLocalizations.of(context)!
                                                .yearlyPremiumPlan,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),

                                          // 価格
                                          // 価格 - ロケールベースの表示
                                          Builder(builder: (context) {
                                            final locale =
                                                Localizations.localeOf(context)
                                                    .toString();
                                            final isJapanese =
                                                locale.startsWith('ja');

                                            // 通貨記号と金額部分 - 英語表示はすべてドルにする
                                            String currencySymbol =
                                                isJapanese ? '¥' : '\$';
                                            String amount =
                                                isJapanese ? '2,980' : '19.99';
                                            // 期間表記
                                            String period =
                                                isJapanese ? '/年' : '/year';

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.baseline,
                                              textBaseline:
                                                  TextBaseline.alphabetic,
                                              children: [
                                                Text(
                                                  currencySymbol + amount,
                                                  style: const TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  ' ' + period,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
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
                                            child: Text(
                                              AppLocalizations.of(context)!
                                                  .monthlyConversion,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            AppLocalizations.of(context)!
                                                .taxIncluded,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            AppLocalizations.of(context)!
                                                .yearlyPremiumDescription,
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
                                                child: Text(
                                                    AppLocalizations.of(
                                                            context)!
                                                        .switchToYearlyPlan,
                                                    style: TextStyle(
                                                        color: Colors.black))),
                                        ]))
                              ]))),
                    ]),
                    const SizedBox(height: 12),

                    // Premium plan description
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
                              AppLocalizations.of(context)!
                                  .premiumPlanBenefitsDescription,
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

                    // Usage status
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.usageStatus,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // AI特殊モードの使用状況
                    _buildUsageCard(
                      AppLocalizations.of(context)!.multiAgentMode,
                      AppLocalizations.of(context)!.multiAgentDescription,
                      _getRemainingUsesText('multi_agent'),
                      Icons.people_alt_outlined,
                      Colors.purple,
                    ),

                    _buildUsageCard(
                      AppLocalizations.of(context)!.thinkingMode,
                      AppLocalizations.of(context)!.thinkingModeDescription,
                      _getRemainingUsesText('thinking'),
                      Icons.psychology,
                      Colors.teal,
                    ),

                    _buildUsageCard(
                      AppLocalizations.of(context)!.cardSetsLimit,
                      AppLocalizations.of(context)!.cardSetsLimitDescription,
                      _subscription?.isPremium ?? false
                          ? AppLocalizations.of(context)!.unlimited
                          : AppLocalizations.of(context)!.maxCardSets(
                              SubscriptionModel.maxCardSets.toString()),
                      Icons.folder_outlined,
                      Colors.blue,
                    ),

                    _buildUsageCard(
                      AppLocalizations.of(context)!.cardsPerSetLimit,
                      AppLocalizations.of(context)!.cardsPerSetLimitDescription,
                      _subscription?.isPremium ?? false
                          ? AppLocalizations.of(context)!.unlimited
                          : AppLocalizations.of(context)!.maxCardsPerSet(
                              SubscriptionModel.maxCardsPerSet.toString()),
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
                              Text(
                                AppLocalizations.of(context)!.usageResetDate,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _subscription!.usageResetDate != null
                                    ? AppLocalizations.of(context)!
                                        .nextResetDate(_formatResetDate(
                                            _subscription!.usageResetDate!))
                                    : AppLocalizations.of(context)!
                                        .noResetDateSet,
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
                            Text(
                              AppLocalizations.of(context)!
                                  .subscriptionManagement,
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.cancel_outlined),
                                    const SizedBox(width: 8),
                                    Text(
                                        AppLocalizations.of(context)!
                                            .unsubscribe,
                                        style: const TextStyle(fontSize: 16)),
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.refresh),
                                    SizedBox(width: 8),
                                    Text(
                                      AppLocalizations.of(context)!
                                          .reactivateSubscription,
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 8),

                            // 状態に応じた説明テキスト
                            if (_subscription!.isPremium &&
                                (_subscription!.status == 'active' ||
                                    _subscription!.status == null))
                              Text(
                                AppLocalizations.of(context)!
                                    .unsubscribeExplanation,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                                textAlign: TextAlign.center,
                              )
                            else if (_subscription!.status == 'canceling')
                              Text(
                                _getPremiumCancellingText(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              )
                            else if (_subscription!.status == 'canceled')
                              Text(
                                AppLocalizations.of(context)!
                                    .premiumPlanCancelled,
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

  // 日付のフォーマット
  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  // リセット日のフォーマット
  String _formatResetDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  // Helper method to properly format localization with date parameter
  String _getPremiumCancellingText() {
    String dateText = _subscription!.cancelAt != null
        ? _formatDate(_subscription!.cancelAt!)
        : '次回の課金日';
    // The premiumPlanCancellationPending string is a function that takes a date parameter
    return AppLocalizations.of(context)!
        .premiumPlanCancellationPending(dateText);
  }

  // サブスクリプション解約確認ダイアログを表示
  Future<void> _showCancelSubscriptionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.subscriptionCancellation),
        content:
            Text(AppLocalizations.of(context)!.cancelSubscriptionConfirmation),
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
                  content: Text(AppLocalizations.of(context)!
                      .completeCancellationInSettings),
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
        title: Text(AppLocalizations.of(context)!.reactivateSubscriptionTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!
                .reactivateSubscriptionConfirmation),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
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
              content: Text(result['message'] ??
                  AppLocalizations.of(context)!.subscriptionReactivated),
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
              content: Text(
                  'サブスクリプションの再開に失敗しました: ${result['error'] ?? AppLocalizations.of(context)!.unknownError}'),
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
