import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/subscription_constants.dart';
import '../models/subscription_model.dart';
import 'subscription_service.dart';

/// StoreKitサービス - iOS向けのStoreKit 2 APIを活用したサブスクリプション処理
class StoreKitService {
  // シングルトンインスタンス
  static final StoreKitService _instance = StoreKitService._internal();
  factory StoreKitService() => _instance;
  StoreKitService._internal();

  // StoreKit特有のヘルパーインスタンス
  late InAppPurchaseStoreKitPlatformAddition _storeKitPlatformAddition;

  // 商品詳細
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  // 商品詳細のゲッターのみ残し、メソッドは後半の実装に統合

  // デリゲート管理
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;
  final StreamController<PurchaseStatus> _purchaseStatusController =
      StreamController<PurchaseStatus>.broadcast();
  Stream<PurchaseStatus> get purchaseStatusStream =>
      _purchaseStatusController.stream;

  // 初期化と設定
  Future<bool> initialize() async {
    if (!Platform.isIOS) {
      print('StoreKitサービス: iOS以外のプラットフォームでは初期化をスキップします');
      return false;
    }

    try {
      print('StoreKit 2サービスを初期化中...');

      // InAppPurchaseが使用可能かチェック
      if (!await InAppPurchase.instance.isAvailable()) {
        print('警告: InAppPurchaseが利用可能ではありません。App Storeへの接続を確認してください。');
        return false;
      }

      // StoreKit固有のプラットフォーム機能を取得
      final iosPlatformAddition = InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      _storeKitPlatformAddition = iosPlatformAddition;

      // StoreKit 2の設定
      await _configureStoreKit2();

      // 商品情報をロード
      bool productsLoaded = await _loadProducts();

      // トランザクションリスナーを設定
      await _setupTransactionListener();

      print('StoreKit 2サービスの初期化が完了しました');
      return productsLoaded;
    } catch (e) {
      print('StoreKit 2サービス初期化エラー: $e');
      return false;
    }
  }

  // StoreKit 2の設定
  Future<void> _configureStoreKit2() async {
    try {
      // トランザクションの更新をリッスンするための設定
      await _storeKitPlatformAddition
          .setDelegate(ExamplePaymentQueueDelegate());

      // 最新のStoreKit 2 APIを使用して保留中のトランザクションをチェック
      final transactions = await SKPaymentQueueWrapper().transactions();
      for (var transaction in transactions) {
        print(
            '保留中のトランザクション: ${transaction.payment.productIdentifier}, 状態: ${transaction.transactionState}');
      }
    } catch (e) {
      print('StoreKit 2設定エラー: $e');
    }
  }

  // 商品情報のロード
  Future<bool> _loadProducts() async {
    try {
      final productIds = SubscriptionConstants.getProductIds('ios');
      print('iOS商品情報を取得中: ${productIds.join(', ')}');

      // StoreKit 2を使用して商品情報を取得
      final ProductDetailsResponse response =
          await InAppPurchase.instance.queryProductDetails(productIds.toSet());

      if (response.error != null) {
        print('商品情報取得エラー: ${response.error}');
        return false;
      }

      // 製品が見つからなかった場合
      if (response.productDetails.isEmpty) {
        print('App Storeから商品情報が取得できませんでした。以下のIDで検索しましたが見つかりませんでした:');
        print('- ${SubscriptionConstants.monthlyProductIdIOS}');
        print('- ${SubscriptionConstants.yearlyProductIdIOS}');
        print('App Store Connect設定を確認してください。');

        // ダミーの商品情報を生成（UI表示用）
        _products = [
          ProductDetails(
            id: SubscriptionConstants.monthlyProductIdIOS, // 正確なiOS商品ID
            title: '月額プレミアムプラン',
            description: '毎月自動更新される暗記アシスタントのサブスクリプション',
            price: '¥380',
            rawPrice: 380.0,
            currencyCode: 'JPY',
            currencySymbol: '¥',
          ),
          ProductDetails(
            id: SubscriptionConstants.yearlyProductIdIOS, // 正確なiOS商品ID
            title: '年額プレミアムプラン',
            description: '毎年自動更新される暗記アシスタントのサブスクリプション',
            price: '¥2,980',
            rawPrice: 2980.0,
            currencyCode: 'JPY',
            currencySymbol: '¥',
          )
        ];

        return false;
      }

      _products = response.productDetails;

      print('取得した商品情報: ${_products.length}件');
      for (var product in _products) {
        print('- ${product.id}: ${product.title} (${product.price})');
      }
      return true;
    } catch (e) {
      print('商品情報の取得に失敗しました: $e');
      print('開発・テスト用にダミーの商品情報を生成します');
      _createDummyProducts();
      return false;
    }
  }

  // 開発・テスト用のダミー商品情報を生成
  void _createDummyProducts() {
    _products = [
      ProductDetails(
        id: SubscriptionConstants.monthlyProductIdIOS,
        title: 'プレミアムプラン（月額）',
        description: '月々のプレミアムサブスクリプション',
        price: '¥380',
        rawPrice: 380,
        currencyCode: 'JPY',
      ),
      ProductDetails(
        id: SubscriptionConstants.yearlyProductIdIOS,
        title: 'プレミアムプラン（年間）',
        description: '年間プレミアムサブスクリプション（お得なプラン）',
        price: '¥2,980',
        rawPrice: 2980,
        currencyCode: 'JPY',
      ),
    ];
    print('ダミー商品情報を生成しました: ${_products.length}件');
    for (var product in _products) {
      print('- ${product.id}: ${product.title} (${product.price})');
    }
  }

  // トランザクションリスナーの設定
  Future<void> _setupTransactionListener() async {
    // 既存のサブスクリプションをキャンセル
    _purchaseStreamSubscription?.cancel();

    // ストアからの購入情報を監視
    final purchaseStream = InAppPurchase.instance.purchaseStream;
    _purchaseStreamSubscription = purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        print('購入ストリームが終了しました');
        _purchaseStreamSubscription?.cancel();
      },
      onError: (error) => print('購入ストリームエラー: $error'),
    );

    print('StoreKit 2トランザクションリスナーを設定しました');
  }

  // トランザクション処理
  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      print(
          '購入状態更新: ${purchaseDetails.status} - 商品ID: ${purchaseDetails.productID}');

      // 状態に基づいた処理
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          print('購入処理中...');
          _purchaseStatusController.add(PurchaseStatus.pending);
          break;

        case PurchaseStatus.purchased:
          print('購入完了');
          _verifyAndDeliverProduct(purchaseDetails);
          _purchaseStatusController.add(PurchaseStatus.purchased);
          break;

        case PurchaseStatus.restored:
          print('購入復元完了');
          _verifyAndDeliverProduct(purchaseDetails);
          _purchaseStatusController.add(PurchaseStatus.restored);
          break;

        case PurchaseStatus.error:
          print('購入エラー: ${purchaseDetails.error?.message}');
          _purchaseStatusController.add(PurchaseStatus.error);
          break;

        case PurchaseStatus.canceled:
          print('購入キャンセル');
          _purchaseStatusController.add(PurchaseStatus.canceled);
          break;
      }

      // 購入の完了処理
      if (purchaseDetails.pendingCompletePurchase) {
        InAppPurchase.instance.completePurchase(purchaseDetails);
      }
    }
  }

  // 購入検証と商品提供
  Future<void> _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) async {
    try {
      print('StoreKit 2による購入検証: ${purchaseDetails.productID}');

      // トランザクション詳細の取得
      if (purchaseDetails is AppStorePurchaseDetails) {
        print('レシートデータを取得しました。サーバー検証を実行できます。');
        // ここでサーバーサイド検証を実装可能
        // await _verifyReceiptWithServer(receiptData, purchaseDetails.productID);

        // サブスクリプション情報の取得
        if (purchaseDetails.verificationData.localVerificationData.isNotEmpty) {
          final verificationData =
              purchaseDetails.verificationData.localVerificationData;
          final previewLength =
              verificationData.length > 50 ? 50 : verificationData.length;
          print(
              'ローカル検証データ: ${verificationData.substring(0, previewLength)}...');
        }

        // 購入日（StoreKit 2からの情報）
        DateTime purchaseDate;
        try {
          if (purchaseDetails.transactionDate != null) {
            // String値をintに変換してからDateTimeを生成
            final transactionDateInt =
                int.tryParse(purchaseDetails.transactionDate.toString());
            if (transactionDateInt != null) {
              purchaseDate =
                  DateTime.fromMillisecondsSinceEpoch(transactionDateInt);
            } else {
              // 変換できない場合は現在時刻を使用
              purchaseDate = DateTime.now();
              print(
                  '警告: transactionDateをintに変換できませんでした: ${purchaseDetails.transactionDate}');
            }
          } else {
            purchaseDate = DateTime.now();
          }
        } catch (e) {
          // 例外が発生した場合は現在時刻を使用
          purchaseDate = DateTime.now();
          print('警告: 日付変換中にエラーが発生しました: $e');
        }

        print('購入日: $purchaseDate');

        // サブスクリプションを有効化する
        // SubscriptionServiceを呼び出してサブスクリプションをアップグレード
        await _upgradeSubscription(purchaseDetails.productID, purchaseDate);
      }
    } catch (e) {
      print('StoreKit 2での購入検証エラー: $e');
    }
  }

  // サブスクリプションをアップグレードするヘルパーメソッド
  Future<void> _upgradeSubscription(
      String productId, DateTime purchaseDate) async {
    try {
      print('サブスクリプションのアップグレードを開始: $productId');

      // GetItからSubscriptionServiceを取得
      final subscriptionService = GetIt.instance<SubscriptionService>();

      // 購入したプランを判断
      SubscriptionType planType;
      if (productId.contains(SubscriptionConstants.yearlyProductIdIOS) ||
          productId.contains('yearly') ||
          productId.contains('Annualy')) {
        planType = SubscriptionType.premium_yearly;
        print('年間プランが購入されました');
      } else {
        planType = SubscriptionType.premium_monthly;
        print('月額プランが購入されました');
      }

      // サブスクリプションの有効期限を設定
      final now = purchaseDate;
      DateTime endDate;

      if (planType == SubscriptionType.premium_yearly) {
        // 年間プラン: 1年後
        endDate = DateTime(now.year + 1, now.month, now.day);
      } else {
        // 月額プラン: 1ヶ月後
        endDate = DateTime(now.year, now.month + 1, now.day);
      }

      print('サブスクリプション期間: ${now.toString()} から ${endDate.toString()} まで');

      // サブスクリプションをアップグレード
      await subscriptionService.upgradeToPremium(
          planType: planType, endDate: endDate);

      print('サブスクリプションが正常に更新されました: $planType');

      // キャッシュをクリアして最新情報を取得
      subscriptionService.clearCache();
      await subscriptionService.refreshSubscription();
    } catch (e) {
      print('サブスクリプションアップグレードエラー: $e');
      throw Exception('サブスクリプションのアップグレードに失敗しました: $e');
    }
  }

  // 月額プランの購入
  Future<void> purchaseMonthlyPlan() async {
    await _makePurchase(SubscriptionType.premium_monthly);
  }

  // 年間プランの購入
  Future<void> purchaseYearlyPlan() async {
    await _makePurchase(SubscriptionType.premium_yearly);
  }

  // 購入実行
  Future<void> _makePurchase(SubscriptionType planType) async {
    try {
      // プラットフォームチェック
      if (!Platform.isIOS) {
        print('iOS以外の環境ではStoreKitは使用できません');
        throw Exception('この端末ではApp Store決済は利用できません');
      }

      // iOS用の正しい商品IDを決定
      final productId = planType == SubscriptionType.premium_yearly
          ? SubscriptionConstants.yearlyProductIdIOS // 'AnkiPaiAnnualyPremium'
          : SubscriptionConstants
              .monthlyProductIdIOS; // 'AnkiPaiMonthlyPremium'

      print('StoreKit 2で購入開始: $productId (iOS専用商品ID)');

      // 商品リストが空の場合、再取得を試みる
      bool productsLoaded = false;
      if (_products.isEmpty) {
        print('商品リストが空です。商品情報を再取得します...');
        productsLoaded = await _loadProducts();
      } else {
        // 商品リストがある場合もダミーではないことを確認
        // iOS専用の商品IDで検索
        final realProducts = _products
            .where((product) =>
                product.id == SubscriptionConstants.monthlyProductIdIOS ||
                product.id == SubscriptionConstants.yearlyProductIdIOS)
            .toList();

        if (realProducts.isEmpty) {
          // 再取得が必要
          print('実際の商品情報が見つかりません。商品情報を再取得します...');
          productsLoaded = await _loadProducts();
        } else {
          productsLoaded = true;
          print('有効な商品リストがあります: ${realProducts.map((p) => p.id).join(', ')}');
        }
      }

      // 商品情報の取得に失敗した場合はエラー
      if (!productsLoaded) {
        throw Exception('商品情報の取得に失敗しました。App Storeへの接続を確認してください。');
      }

      // 利用可能な商品を表示
      print('利用可能な商品一覧:');
      for (var product in _products) {
        print('- ${product.id}: ${product.title} (${product.price})');
      }

      // すべての商品情報を表示（デバッグ用）
      print('利用可能な全商品リスト:');
      for (var p in _products) {
        print('ID: ${p.id}, タイトル: ${p.title}, 価格: ${p.price}');
      }

      // iOS用の商品情報を厳密に検索
      final matchingProducts = _products
          .where((product) => product.id == productId && product.id.isNotEmpty)
          .toList();

      if (matchingProducts.isEmpty) {
        print('商品が見つかりません: $productId');
        throw Exception(
            '指定された商品ID「$productId」が利用可能な商品として見つかりません。App Storeの設定を確認してください。');
      }

      final productDetails = matchingProducts.first;
      print(
          '購入する商品: ${productDetails.id} - ${productDetails.title} (${productDetails.price})');

      // App Storeに接続できているか確認
      if (!await InAppPurchase.instance.isAvailable()) {
        throw Exception('App Storeへの接続が利用できません。ネットワーク接続を確認してください。');
      }

      // 購入パラメータの設定 - iOS用に最適化
      final purchaseParam = PurchaseParam(
        productDetails: productDetails,
        // applicationUsernameは最新のin_app_purchaseパッケージではサポートされていない可能性があるため削除
      );

      print('購入リクエスト準備完了: ${productDetails.id}');

      // 購入リクエストの開始
      final success = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      print('購入リクエスト結果: $success');
    } catch (e) {
      print('StoreKit 2での購入エラー: $e');
      rethrow;
    }
  }

  // 過去の購入を復元
  Future<void> restorePurchases() async {
    try {
      print('StoreKit 2で購入を復元中...');
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      print('購入復元エラー: $e');
      rethrow;
    }
  }

  // サブスクリプションステータスの確認
  Future<Map<String, dynamic>> checkSubscriptionStatus() async {
    if (!Platform.isIOS) {
      return {'error': 'iOS以外のプラットフォームではサポートされていません'};
    }

    try {
      // レシートデータの取得
      final String receiptData = await SKReceiptManager.retrieveReceiptData();

      if (receiptData.isEmpty) {
        return {'status': 'no_purchases', 'message': '購入履歴がありません'};
      }

      print('レシートデータが取得できました: ${receiptData.length}バイト');

      // ここでサーバーサイド検証を実装
      // return await _verifyReceiptWithServer(receiptData);

      // デモ用の応答
      return {
        'status': 'active',
        'products': [
          {
            'product_id': SubscriptionConstants.monthlyProductIdIOS,
            'expires_date':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          }
        ]
      };
    } catch (e) {
      print('サブスクリプションステータス確認エラー: $e');
      return {'error': e.toString()};
    }
  }

  // リソースの解放
  void dispose() {
    _purchaseStreamSubscription?.cancel();
    _purchaseStatusController.close();
  }

  /// iOSのサブスクリプション設定ページを開く
  ///
  /// iOSではアプリ内から直接サブスクリプションを解約することができないため、
  /// 設定ページを開いてユーザーに手動で解約してもらう必要があります。
  /// iOS 14以降では、設定アプリのサブスクリプション管理画面に直接誘導します。
  Future<bool> openSubscriptionSettings() async {
    if (!Platform.isIOS) {
      print('この機能はiOSのみで利用可能です');
      return false;
    }

    try {
      // まずはApp-Prefsスキームの直接リンクを試す
      // iOS 14以降のサブスクリプション設定URL
      final subscriptionsUrl = Uri.parse('App-Prefs:root=SUBSCRIPTIONS');
      if (await canLaunchUrl(subscriptionsUrl)) {
        await launchUrl(subscriptionsUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      // 次に設定アプリのSTOREセクションを試す
      final storeUrl = Uri.parse('App-Prefs:root=STORE');
      if (await canLaunchUrl(storeUrl)) {
        await launchUrl(storeUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      // 最後の手段として、ブラウザでApp Storeのサブスクリプションページを開く
      final webUrl = Uri.parse('https://apps.apple.com/account/subscriptions');
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        return true;
      }

      print('サブスクリプション設定ページを開くための全ての方法が失敗しました');
      return false;
    } catch (e) {
      print('サブスクリプション設定画面を開けませんでした: $e');
      return false;
    }
  }
}

/// StoreKit 2 デリゲートの実装
class ExamplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
      SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}
