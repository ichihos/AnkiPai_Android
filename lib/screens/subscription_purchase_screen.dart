import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/subscription_model.dart';
import '../services/payment_service.dart';
import '../constants/subscription_constants.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SubscriptionPurchaseScreen extends StatefulWidget {
  final SubscriptionType? initialType;

  const SubscriptionPurchaseScreen({
    super.key,
    this.initialType,
  });

  @override
  _SubscriptionPurchaseScreenState createState() => _SubscriptionPurchaseScreenState();
}

class _SubscriptionPurchaseScreenState extends State<SubscriptionPurchaseScreen> {
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _errorMessage;
  SubscriptionType _selectedType = SubscriptionType.premium_monthly;
  PaymentService? _paymentService;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? SubscriptionType.premium_monthly;
    _initializePaymentService();
  }

  Future<void> _initializePaymentService() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // プラットフォームに応じた決済サービスを取得
      _paymentService = PaymentService.getInstance();
      await _paymentService?.initialize();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'サブスクリプション情報の取得に失敗しました: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _purchaseSubscription() async {
    if (_paymentService == null) return;

    try {
      setState(() {
        _isPurchasing = true;
        _errorMessage = null;
      });

      final result = await _paymentService!.purchaseSubscription(context, _selectedType);

      if (mounted) {
        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.subscriptionPurchaseCompleted),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // 成功して画面を閉じる
        } else {
          setState(() {
            _errorMessage = result.message ?? '購入処理に失敗しました';
            _isPurchasing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '購入処理中にエラーが発生しました: $e';
          _isPurchasing = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    if (_paymentService == null || !_paymentService!.supportsRestore()) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await _paymentService!.restorePurchases();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.purchaseRestored),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // 成功して画面を閉じる
        } else {
          setState(() {
            _errorMessage = result.message ?? '購入の復元に失敗しました';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '購入の復元中にエラーが発生しました: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.premiumPlan),
        elevation: 0,
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildFeaturesList(),
          const SizedBox(height: 24),
          _buildPlanOptions(),
          const SizedBox(height: 16),
          if (_errorMessage != null) _buildErrorMessage(),
          const SizedBox(height: 16),
          _buildPriceInfo(),
          const SizedBox(height: 24),
          _buildTermsInfo(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.shade300,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium,
                size: 32,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 12),
              Text(
                'プレミアム機能を利用する',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'プレミアムプランに登録して、さらに効率的に学習を進めましょう。暗記帳を無制限に作成し、AIアシスタントをフル活用できます。',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    final premiumFeatures = [
      {
        'title': '無制限のカード作成',
        'description': '無制限に暗記カードを作成できます',
        'icon': Icons.layers,
      },
      {
        'title': 'AIアシスタント',
        'description': '効率的な暗記をサポートするAIアシスタント',
        'icon': Icons.psychology,
      },
      {
        'title': 'クラウド同期',
        'description': '複数デバイスでのシームレスな学習体験',
        'icon': Icons.cloud_sync,
      },
      {
        'title': '高度な分析',
        'description': '学習パターンの詳細な分析と洞察',
        'icon': Icons.analytics,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'プレミアム特典',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...premiumFeatures.map((feature) => _buildFeatureItem(
              title: feature['title'] as String,
              description: feature['description'] as String,
              icon: feature['icon'] as IconData,
            )),
      ],
    );
  }

  Widget _buildFeatureItem({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.green.shade700,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
        ],
      ),
    );
  }

  Widget _buildPlanOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'プランを選択',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPlanOption(
                title: '月額',
                price: SubscriptionConstants.monthlyPriceDisplay,
                type: SubscriptionType.premium_monthly,
                isPopular: false,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildPlanOption(
                title: '年間',
                price: SubscriptionConstants.yearlyPriceDisplay,
                type: SubscriptionType.premium_yearly,
                isPopular: true,
                discountLabel: SubscriptionConstants.getYearlyDiscountRateDisplay(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanOption({
    required String title,
    required String price,
    required SubscriptionType type,
    required bool isPopular,
    String? discountLabel,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.green.shade500 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.green.shade100,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'おすすめ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.green.shade700 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.green.shade700 : Colors.grey.shade700,
              ),
            ),
            if (discountLabel != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  discountLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInfo() {
    String priceDisplay;
    String? periodInfo;
    
    switch (_selectedType) {
      case SubscriptionType.premium_monthly:
        priceDisplay = SubscriptionConstants.monthlyPriceDisplay;
        periodInfo = '月額自動更新';
        break;
      case SubscriptionType.premium_yearly:
        priceDisplay = SubscriptionConstants.yearlyPriceDisplay;
        periodInfo = '年間自動更新';
        break;
      default:
        priceDisplay = '';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '選択したプラン',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                priceDisplay,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (periodInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                periodInfo,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTermsInfo() {
    return Column(
      children: [
        Text(
          '利用規約、プライバシーポリシーに同意の上ご購入ください。購読はいつでもキャンセル可能です。',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (kIsWeb)
          Text(
            'Web版では、Stripe決済を使用します。安全な決済処理のため、カード情報はAnkiPaiのサーバーには保存されません。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        if (!kIsWeb)
          Text(
            '購入はApp Storeアカウント/Google Playアカウントに請求されます。期間終了の24時間前までに自動更新を解除しない限り、購読は自動的に更新されます。',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPurchasing ? null : _purchaseSubscription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 53, 152, 71),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: _isPurchasing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '購入する',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (_paymentService?.supportsRestore() ?? false)
              TextButton(
                onPressed: _isLoading ? null : _restorePurchases,
                child: Text(
                  '以前の購入を復元',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
