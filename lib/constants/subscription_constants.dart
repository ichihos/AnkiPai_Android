// サブスクリプション関連の定数を定義
class SubscriptionConstants {
  // プロダクトID - Apple用
  static const String monthlyProductIdIOS =
      'AnkiPaiMonthlyPremium'; // Apple ID:
  static const String yearlyProductIdIOS =
      'AnkiPaiAnnualyPremium'; // Apple ID: 6744824363

  // プロダクトID - Google用
  static const String monthlyProductIdAndroid = 'anki_pai_premium_monthly';
  static const String yearlyProductIdAndroid = 'anki_pai_premium_yearly';

  // プロダクトID - Web用（Stripe等で使用）
  // 本番環境用価格ID
  static const String monthlyProductIdWeb = 'price_1RGbsBG3lcdzm6JzRch4AlCx';
  static const String yearlyProductIdWeb = 'price_1RGbrPG3lcdzm6Jz66vIt1Lz';

  // 価格情報（表示用）
  static const int monthlyPriceJPY = 380;
  static const int yearlyPriceJPY = 2980;

  // 価格情報フォーマット（表示用）
  static const String monthlyPriceDisplay = '¥380/月';
  static const String yearlyPriceDisplay = '¥2,980/年';

  // 消費税率
  static const double taxRate = 0.10; // 10%

  // プロダクトリスト取得用
  static List<String> getProductIds(String platform) {
    switch (platform) {
      case 'ios':
        return [monthlyProductIdIOS, yearlyProductIdIOS];
      case 'android':
        return [monthlyProductIdAndroid, yearlyProductIdAndroid];
      case 'web':
        return [monthlyProductIdWeb, yearlyProductIdWeb];
      default:
        return [];
    }
  }

  // 年間プランの割引率を計算
  static double getYearlyDiscountRate() {
    // 月額×12と年額を比較して割引率を計算
    const monthlyYearTotal = monthlyPriceJPY * 12;
    return (monthlyYearTotal - yearlyPriceJPY) / monthlyYearTotal;
  }

  // 年間プランの割引率を表示用にフォーマット
  static String getYearlyDiscountRateDisplay() {
    final rate = getYearlyDiscountRate() * 100;
    return '${rate.toStringAsFixed(0)}%OFF';
  }
}
