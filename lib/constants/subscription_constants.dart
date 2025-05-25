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

  // 価格情報（表示用）- 日本円
  static const int monthlyPriceJPY = 380;
  static const int yearlyPriceJPY = 2980;

  // 価格情報（表示用）- 米ドル
  static const double monthlyPriceUSD = 1.99;
  static const double yearlyPriceUSD = 19.99;

  // 価格情報フォーマット（表示用）- 日本円
  static const String monthlyPriceDisplayJPY = '¥380/月';
  static const String yearlyPriceDisplayJPY = '¥2,980/年';

  // 価格情報フォーマット（表示用）- 英語
  static const String monthlyPriceDisplayEN = '\$1.99/month';
  static const String yearlyPriceDisplayEN = '\$19.99/year';

  // 価格情報フォーマット（表示用）- 米ドル
  static const String monthlyPriceDisplayUSD = '\$1.99/month';
  static const String yearlyPriceDisplayUSD = '\$19.99/year';

  // 後方互換性のための定数
  static const String monthlyPriceDisplay = monthlyPriceDisplayJPY;
  static const String yearlyPriceDisplay = yearlyPriceDisplayJPY;

  // 消費税率
  static const double taxRate = 0.10; // 10%

  // ロケールベースの価格表示取得メソッド
  // 英語表示の場合はすべてドル表示にする
  static String getMonthlyPriceDisplay(String locale) {
    if (locale.startsWith('ja')) {
      // 日本語の場合は円表示
      return monthlyPriceDisplayJPY;
    } else {
      // 英語の場合はすべてドル表示
      return monthlyPriceDisplayUSD;
    }
  }

  // ロケールベースの年間価格表示取得メソッド
  // 英語表示の場合はすべてドル表示にする
  static String getYearlyPriceDisplay(String locale) {
    if (locale.startsWith('ja')) {
      // 日本語の場合は円表示
      return yearlyPriceDisplayJPY;
    } else {
      // 英語の場合はすべてドル表示
      return yearlyPriceDisplayUSD;
    }
  }

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
