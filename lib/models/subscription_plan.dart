import 'package:anki_pai/models/subscription_model.dart';

/// サブスクリプションプランの情報を保持するクラス
class SubscriptionPlan {
  final SubscriptionType type;
  final String name;
  final String price;
  final List<String> features;
  final int durationInDays;

  // プラットフォーム固有のID
  final String? iOSProductId;
  final String? androidSkuId;
  final String? stripePriceId;

  const SubscriptionPlan({
    required this.type,
    required this.name,
    required this.price,
    required this.features,
    required this.durationInDays,
    this.iOSProductId,
    this.androidSkuId,
    this.stripePriceId,
  });

  // 月額換算の価格を取得
  String get monthlyEquivalent {
    if (type == SubscriptionType.free) return '無料';
    if (type == SubscriptionType.premium_monthly) return price;

    // 価格から数値だけを抽出（¥980 → 980）
    final priceValue =
        double.tryParse(price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

    return '月額換算 ¥${priceValue.round()}';
  }

  // 割引率を計算
  String? get discountRate {
    if (type == SubscriptionType.free ||
        type == SubscriptionType.premium_monthly) {
      return null;
    }

    // 基準となる月額プランの価格（¥980と仮定）
    const double monthlyPrice = 980.0;

    // このプランの月額換算
    final thisMonthlyPrice =
        double.tryParse(monthlyEquivalent.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0.0;

    if (thisMonthlyPrice <= 0) return null;

    // 割引率を計算
    final discountPercentage =
        ((monthlyPrice - thisMonthlyPrice) / monthlyPrice * 100).round();

    if (discountPercentage <= 0) return null;

    return '$discountPercentage%お得';
  }

  // 各プラットフォーム向けの商品IDを取得
  String? getProductId(String platform) {
    switch (platform) {
      case 'ios':
        return iOSProductId;
      case 'android':
        return androidSkuId;
      case 'web':
        return stripePriceId;
      default:
        return null;
    }
  }
}
