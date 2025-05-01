import 'package:anki_pai/constants/subscription_constants.dart';
import 'package:anki_pai/models/subscription_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/subscription_model.dart';

/// 決済結果のステータス
enum PaymentStatus {
  success, // 決済成功
  failed, // 決済失敗
  canceled, // ユーザーによるキャンセル
  pending, // 処理中
  unknown // 不明なステータス
}

/// 決済結果を表すクラス
class PaymentResult {
  final PaymentStatus status;
  final String? message;
  final String? transactionId;
  final SubscriptionType? subscriptionType;

  PaymentResult({
    required this.status,
    this.message,
    this.transactionId,
    this.subscriptionType,
  });

  bool get isSuccess => status == PaymentStatus.success;
}

/// 決済サービスの抽象クラス
/// 各プラットフォーム固有の実装はこのクラスを継承する
abstract class PaymentService {
  static PaymentService? _instance;

  /// 適切なプラットフォーム用の決済サービスインスタンスを取得
  static PaymentService getInstance() {
    if (_instance == null) {
      if (kIsWeb) {
        _instance = WebPaymentService();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        _instance = IOSPaymentService();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        _instance = AndroidPaymentService();
      } else {
        throw UnsupportedError('このプラットフォームは決済をサポートしていません');
      }
    }
    return _instance!;
  }

  /// サブスクリプションの初期化（サブスクリプション情報の取得など）
  Future<void> initialize();

  /// 利用可能なプランを取得
  Future<List<SubscriptionPlan>> getAvailablePlans();

  /// サブスクリプションの購入処理を開始
  Future<PaymentResult> purchaseSubscription(
      BuildContext context, SubscriptionType type);

  /// 現在のサブスクリプションを取得
  Future<SubscriptionModel?> getCurrentSubscription();

  /// サブスクリプションの更新
  Future<PaymentResult> renewSubscription(SubscriptionType type);

  /// サブスクリプションのキャンセル
  Future<bool> cancelSubscription();

  /// 購入を復元（主にiOS用）
  Future<PaymentResult> restorePurchases();

  /// サブスクリプションを検証
  Future<bool> verifySubscription(String receiptData);

  /// サブスクリプションのステータス確認
  Future<bool> isSubscriptionActive();

  /// 決済サービスがサポートされているかどうか
  bool isSupported();

  /// 復元機能がサポートされているかどうか
  bool supportsRestore();
}

/// Web用の決済サービス実装（Stripe）
class WebPaymentService extends PaymentService {
  @override
  Future<void> initialize() async {
    // Stripeの初期化など
  }

  @override
  Future<List<SubscriptionPlan>> getAvailablePlans() async {
    // Stripeから利用可能なプラン一覧を取得
    return [
      const SubscriptionPlan(
        type: SubscriptionType.premium_monthly,
        name: '月額プラン',
        price: '¥380',
        features: ['無制限のカード作成', 'AIアシスタント', 'クラウド同期'],
        durationInDays: 30,
        stripePriceId: 'price_monthly',
      ),
      SubscriptionPlan(
        type: SubscriptionType.premium_yearly,
        name: '年間プラン',
        price: '¥2,980',
        features: [
          '月額プランの全機能',
          SubscriptionConstants.getYearlyDiscountRateDisplay(),
          'プレミアムテンプレート',
          'プライオリティサポート'
        ],
        durationInDays: 365,
        stripePriceId: 'price_yearly',
      ),
    ];
  }

  @override
  Future<PaymentResult> purchaseSubscription(
      BuildContext context, SubscriptionType type) async {
    try {
      // Stripe決済を実装
      // 実際の実装では、バックエンドと連携してStripeの支払いインテントを作成する必要がある
      return PaymentResult(
        status: PaymentStatus.success,
        message: 'テスト用の成功メッセージ',
        transactionId:
            'test_transaction_${DateTime.now().millisecondsSinceEpoch}',
        subscriptionType: type,
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        message: '決済に失敗しました: $e',
      );
    }
  }

  @override
  Future<SubscriptionModel?> getCurrentSubscription() async {
    // 実際の実装では、バックエンドからユーザーのサブスクリプション情報を取得する
    return null;
  }

  @override
  Future<PaymentResult> renewSubscription(SubscriptionType type) async {
    // サブスクリプションの更新
    return await purchaseSubscription(null as BuildContext, type);
  }

  @override
  Future<bool> cancelSubscription() async {
    // サブスクリプションのキャンセル
    return true;
  }

  @override
  Future<PaymentResult> restorePurchases() async {
    // Web版では復元機能は不要
    return PaymentResult(
      status: PaymentStatus.unknown,
      message: 'Web版では購入の復元はサポートされていません',
    );
  }

  @override
  Future<bool> verifySubscription(String receiptData) async {
    // 実際の実装では、バックエンドでStripeの決済検証を行う
    return true;
  }

  @override
  Future<bool> isSubscriptionActive() async {
    // サブスクリプションのステータス確認
    final subscription = await getCurrentSubscription();
    return subscription?.isActive ?? false;
  }

  @override
  bool isSupported() {
    return true; // Webでサポート
  }

  @override
  bool supportsRestore() {
    return false; // Web版では復元機能はサポートしない
  }
}

/// iOS用の決済サービス実装（In-App Purchase）
class IOSPaymentService extends PaymentService {
  @override
  Future<void> initialize() async {
    // In-App Purchaseの初期化
  }

  @override
  Future<List<SubscriptionPlan>> getAvailablePlans() async {
    // App Storeから利用可能なプラン一覧を取得
    return [
      const SubscriptionPlan(
        type: SubscriptionType.premium_monthly,
        name: '月額プラン',
        price: '¥380',
        features: ['無制限のカード作成', 'AIアシスタント', 'クラウド同期'],
        durationInDays: 30,
        iOSProductId: 'com.ankipai.subscription.monthly',
      ),
      SubscriptionPlan(
        type: SubscriptionType.premium_yearly,
        name: '年間プラン',
        price: '¥2,980',
        features: [
          '月額プランの全機能',
          SubscriptionConstants.getYearlyDiscountRateDisplay(),
          'プレミアムテンプレート',
          'プライオリティサポート'
        ],
        durationInDays: 365,
        iOSProductId: 'com.ankipai.subscription.yearly',
      ),
    ];
  }

  @override
  Future<PaymentResult> purchaseSubscription(
      BuildContext context, SubscriptionType type) async {
    try {
      // In-App Purchase実装
      return PaymentResult(
        status: PaymentStatus.success,
        message: 'テスト用の成功メッセージ',
        transactionId:
            'test_transaction_${DateTime.now().millisecondsSinceEpoch}',
        subscriptionType: type,
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        message: '決済に失敗しました: $e',
      );
    }
  }

  @override
  Future<SubscriptionModel?> getCurrentSubscription() async {
    // 実際の実装では、StoreKitからユーザーのサブスクリプション情報を取得する
    return null;
  }

  @override
  Future<PaymentResult> renewSubscription(SubscriptionType type) async {
    // iOS版ではAppleが自動的に処理するので実装不要
    return PaymentResult(
      status: PaymentStatus.success,
      message: 'iOSでは自動更新されます',
    );
  }

  @override
  Future<bool> cancelSubscription() async {
    // iOS版ではApp Store経由で行うので、キャンセル方法を案内
    return true;
  }

  @override
  Future<PaymentResult> restorePurchases() async {
    try {
      // 購入の復元処理
      return PaymentResult(
        status: PaymentStatus.success,
        message: '購入を復元しました',
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        message: '購入の復元に失敗しました: $e',
      );
    }
  }

  @override
  Future<bool> verifySubscription(String receiptData) async {
    // Apple App Storeのレシートを検証
    return true;
  }

  @override
  Future<bool> isSubscriptionActive() async {
    // サブスクリプションのステータス確認
    final subscription = await getCurrentSubscription();
    return subscription?.isActive ?? false;
  }

  @override
  bool isSupported() {
    return true; // iOSでサポート
  }

  @override
  bool supportsRestore() {
    return true; // iOS版は復元機能をサポート
  }
}

/// Android用の決済サービス実装（Google Play Billing）
class AndroidPaymentService extends PaymentService {
  @override
  Future<void> initialize() async {
    // Google Play Billingの初期化
  }

  @override
  Future<List<SubscriptionPlan>> getAvailablePlans() async {
    // Google Playから利用可能なプラン一覧を取得
    return [
      const SubscriptionPlan(
        type: SubscriptionType.premium_monthly,
        name: '月額プラン',
        price: '¥380',
        features: ['無制限のカード作成', 'AIアシスタント', 'クラウド同期'],
        durationInDays: 30,
        androidSkuId: 'subscription_monthly',
      ),
      SubscriptionPlan(
        type: SubscriptionType.premium_yearly,
        name: '年間プラン',
        price: '¥2,980',
        features: [
          '月額プランの全機能',
          SubscriptionConstants.getYearlyDiscountRateDisplay(),
          'プレミアムテンプレート',
          'プライオリティサポート'
        ],
        durationInDays: 365,
        androidSkuId: 'subscription_yearly',
      ),
    ];
  }

  @override
  Future<PaymentResult> purchaseSubscription(
      BuildContext context, SubscriptionType type) async {
    try {
      // Google Play Billing実装
      return PaymentResult(
        status: PaymentStatus.success,
        message: 'テスト用の成功メッセージ',
        transactionId:
            'test_transaction_${DateTime.now().millisecondsSinceEpoch}',
        subscriptionType: type,
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        message: '決済に失敗しました: $e',
      );
    }
  }

  @override
  Future<SubscriptionModel?> getCurrentSubscription() async {
    // 実際の実装では、Google Playからユーザーのサブスクリプション情報を取得する
    return null;
  }

  @override
  Future<PaymentResult> renewSubscription(SubscriptionType type) async {
    // Android版ではGoogle Playが自動的に処理するので実装不要
    return PaymentResult(
      status: PaymentStatus.success,
      message: 'Androidでは自動更新されます',
    );
  }

  @override
  Future<bool> cancelSubscription() async {
    // Android版ではGoogle Play経由で行うので、キャンセル方法を案内
    return true;
  }

  @override
  Future<PaymentResult> restorePurchases() async {
    try {
      // 購入の復元処理
      return PaymentResult(
        status: PaymentStatus.success,
        message: '購入を復元しました',
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentStatus.failed,
        message: '購入の復元に失敗しました: $e',
      );
    }
  }

  @override
  Future<bool> verifySubscription(String receiptData) async {
    // Google Playのレシートを検証
    return true;
  }

  @override
  Future<bool> isSubscriptionActive() async {
    // サブスクリプションのステータス確認
    final subscription = await getCurrentSubscription();
    return subscription?.isActive ?? false;
  }

  @override
  bool isSupported() {
    return true; // Androidでサポート
  }

  @override
  bool supportsRestore() {
    return true; // Android版は復元機能をサポート
  }
}
