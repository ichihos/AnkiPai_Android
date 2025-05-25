import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/subscription_model.dart';
import '../constants/subscription_constants.dart';
import '../widgets/upgrade_dialog.dart';
import 'card_set_service.dart';
import 'flash_card_service.dart';
import 'storekit_service.dart';
import 'firebase_debug_service.dart';
import 'connectivity_service.dart';

class SubscriptionService {
  final GetIt _getIt = GetIt.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  // StoreKit 2サービス - iOS専用
  final StoreKitService _storeKitService = StoreKitService();

  // 現在のサブスクリプション情報をキャッシュ
  SubscriptionModel? _cachedSubscription;

  // サブスクリプション情報ストリームコントローラ
  final StreamController<SubscriptionModel> _subscriptionController =
      StreamController<SubscriptionModel>.broadcast();
  Stream<SubscriptionModel> get subscriptionStream =>
      _subscriptionController.stream;

  // 購入ストリームサブスクリプション
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;

  // 商品情報
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;
  
  // サブスクリプションがアクティブかどうかを確認するゲッター
  bool get hasActiveSubscription {
    // キャッシュがあれば、キャッシュから確認
    if (_cachedSubscription != null) {
      return _cachedSubscription!.type != SubscriptionType.free && 
             (_cachedSubscription!.status == 'active' || _cachedSubscription!.status == null);
    }
    // キャッシュがない場合はフリープランとみなす
    return false;
  }

  // キャッシュクリア
  void clearCache() {
    _cachedSubscription = null;
    print('サブスクリプション情報のキャッシュをクリアしました');
  }

  // サービスの初期化
  Future<void> initialize() async {
    // オフラインかどうかを確認
    final connectivityService = GetIt.instance<ConnectivityService>();
    final isOffline = connectivityService.isOffline;

    if (isOffline) {
      print('📱 オフラインモード: サブスクリプションサービスをオフラインモードで初期化します');

      // オフラインモードではフリープランとして初期化
      _cachedSubscription = SubscriptionModel(
        userId: 'offline_user',
        type: SubscriptionType.free,
        thinkingModeUsed: 0,
        multiAgentModeUsed: 0,
      );
      _subscriptionController.add(_cachedSubscription!);
      return;
    }

    // オンラインモードの処理
    final user = _auth.currentUser;
    if (user == null) {
      print('サブスクリプションサービス: ユーザーがログインしていません');
      return;
    }

    try {
      // 初期化時にキャッシュをクリア
      clearCache();

      // Firebase Authトークンを更新
      await user.getIdToken(true);
      print('初期化: ユーザートークン更新完了 (${user.uid})');

      // アプリ内購入の初期化
      await _initializeInAppPurchase();

      // Stripeから最新情報を取得してFirestoreを更新
      try {
        print('初期化: HTTP直接呼び出しでStripe情報を取得');
        // HTTP直接呼び出しでストライプサブスクリプションを取得
        final debugService = FirebaseDebugService();
        final stripeHttpResult = await debugService.callStripeSubscription();

        // HTTP直接呼び出し結果の処理
        if (stripeHttpResult.containsKey('status') &&
            stripeHttpResult['status'] == 'success' &&
            stripeHttpResult['http_response'] != null &&
            stripeHttpResult['http_response']['result'] != null) {
          final resultData = stripeHttpResult['http_response']['result'];
          // Stripeでサブスクリプションが有効な場合、Firestoreの情報を更新
          if (resultData['active'] == true) {
            print('初期化: アクティブなサブスクリプション発見 - Firestore更新中');
            await _forceUpdateSubscriptionFromStripe(resultData, user.uid);
          }
        } else {
          print('初期化: HTTPレスポンスから有効なデータが取得できませんでした');
        }
      } catch (stripeError) {
        print('初期化: Stripe情報取得エラー: $stripeError');
        // Stripe実行エラーは無視して続行
      }

      // 最終的なサブスクリプション情報を取得してキャッシュ
      final subscription = await _loadSubscription();
      print(
          'サブスクリプションタイプ: ${subscription.type}, プレミアムステータス: ${subscription.isPremium}');

      print('サブスクリプションサービス初期化完了: ユーザーID ${user.uid}');
    } catch (e) {
      print('サブスクリプションサービス初期化エラー: $e');
      // エラー時はフリープランとして初期化
      _cachedSubscription = SubscriptionModel(
        userId: 'offline_user',
        type: SubscriptionType.free,
        thinkingModeUsed: 0,
        multiAgentModeUsed: 0,
      );
      _subscriptionController.add(_cachedSubscription!);
      throw Exception('サブスクリプションサービスの初期化に失敗しました: $e');
    }
  }

  // ユーザーのサブスクリプション情報を取得
  Future<SubscriptionModel> getUserSubscription() async {
    // オフラインかどうかを確認
    final connectivityService = GetIt.instance<ConnectivityService>();
    final isOffline = connectivityService.isOffline;

    if (isOffline) {
      print('📱 オフラインモード: フリープランとしてサブスクリプション情報を返します');

      // キャッシュがあれば返す
      if (_cachedSubscription != null) {
        return _cachedSubscription!;
      }

      // オフラインモードではフリープランを返す
      _cachedSubscription = SubscriptionModel(
        userId: 'offline_user',
        type: SubscriptionType.free,
        thinkingModeUsed: 0,
        multiAgentModeUsed: 0,
      );
      return _cachedSubscription!;
    }

    // オンラインモードの場合
    // キャッシュがあれば返す
    if (_cachedSubscription != null) {
      await _checkUsageReset(_cachedSubscription!);
      return _cachedSubscription!;
    }

    // なければ読み込む
    try {
      return await _loadSubscription();
    } catch (e) {
      print('サブスクリプション情報の読み込みエラー: $e');
      // エラー時はフリープランを返す
      _cachedSubscription = SubscriptionModel(
        userId: 'offline_user',
        type: SubscriptionType.free,
        thinkingModeUsed: 0,
        multiAgentModeUsed: 0,
      );
      return _cachedSubscription!;
    }
  }

  // サブスクリプション情報を更新する
  Future<SubscriptionModel> refreshSubscription() async {
    print('Starting subscription refresh process');
    // キャッシュをクリア
    clearCache();

    // Firebase Authトークンを更新
    final user = _auth.currentUser;
    if (user == null) {
      print('Cannot refresh subscription: User not logged in');
      throw Exception('ユーザーがログインしていません');
    }

    await user.getIdToken(true);
    print('User token refreshed: ${user.uid}');

    // Stripeデバッグ情報を取得
    try {
      print('Debugging Stripe configuration...');
      final functions = FirebaseFunctions.instance;
      final debugResult =
          await functions.httpsCallable('ankiPaiDebugStripeSecrets').call();
      print('Stripe debug result: ${debugResult.data}');
    } catch (debugError) {
      print('Stripe debug error: $debugError');
    }

    // シンプルなデバッグ関数をHTTP直接呼び出しで実行
    try {
      print('HTTP直接呼び出しでシンプルデバッグ関数を実行します...');
      final debugService = FirebaseDebugService();
      final httpDebugResult = await debugService.callSimpleDebug();
      print('HTTP直接呼び出しデバッグ結果: $httpDebugResult');
    } catch (httpDebugError) {
      print('HTTP直接呼び出しデバッグエラー: $httpDebugError');
    }

    // HTTP直接呼び出しによるストライプサブスクリプション取得
    try {
      print('HTTP直接呼び出しでストライプサブスクリプションを取得します...');
      final debugService = FirebaseDebugService();
      final stripeHttpResult = await debugService.callStripeSubscription();
      print('HTTP直接呼び出しストライプ結果: $stripeHttpResult');

      // 結果が有効な場合、このデータを使用してサブスクリプション情報を更新する
      if (stripeHttpResult.containsKey('status') &&
          stripeHttpResult['status'] == 'success' &&
          stripeHttpResult['http_response'] != null &&
          stripeHttpResult['http_response']['result'] != null) {
        final resultData = stripeHttpResult['http_response']['result'];
        if (resultData['active'] == true) {
          print('ストライプHTTP呼び出しで有効なサブスクリプションが見つかりました');
          await _forceUpdateSubscriptionFromStripe(resultData, user.uid);
          // 新しく最新のサブスクリプション情報をロードする
          return await _loadSubscription();
        }
      }
    } catch (stripeHttpError) {
      print('HTTP直接呼び出しストライプエラー: $stripeHttpError');
    }

    // HTTP直接呼び出しが失敗した場合にのみSDK呼び出しを使用する
    try {
      // Stripeサーバーから直接サブスクリプション情報を取得
      print('バックアップ: SDKを使用してサブスクリプションデータをリクエスト');
      final functions = FirebaseFunctions.instance;
      final result =
          await functions.httpsCallable('ankiPaiStripeSubscription').call({});

      // Stripeでサブスクリプションが有効な場合、Firestoreの情報を更新
      if (result.data['active'] == true) {
        print('SDK呼び出しで有効なサブスクリプションが見つかりました');
        await _forceUpdateSubscriptionFromStripe(result.data, user.uid);
        return await _loadSubscription();
      }
    } catch (e) {
      // エラーログを模索エラーとして表示しない
      print('バックアップSDK呼び出しも失敗しました。ローカルデータからロードします');
      // エラーが発生しても継続、ローカルデータから情報を取得する
    }

    // 最新のサブスクリプション情報を取得
    return await _loadSubscription();
  }

  // Stripe情報からFirestoreのサブスクリプションを強制的に更新
  Future<void> _forceUpdateSubscriptionFromStripe(
      Map<String, dynamic> stripeData, String uid) async {
    print('Forcing subscription update from Stripe data: $stripeData');

    try {
      final subscription = stripeData['subscription'] as Map<String, dynamic>?;
      if (subscription == null) {
        print('No subscription data found in Stripe response');
        return;
      }

      // プランタイプを確認
      final plan = subscription['plan'] as String? ?? 'monthly';
      final subscriptionType =
          plan == 'yearly' ? 'premium_yearly' : 'premium_monthly';

      print('Setting subscription type to: $subscriptionType');

      // 期間情報を取得
      final Map<String, dynamic> dataToUpdate = {
        'type': subscriptionType,
        'userId': uid,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // 開始日を設定
      if (subscription['start_date'] != null) {
        try {
          final startTimestamp = Timestamp.fromMillisecondsSinceEpoch(
              (subscription['start_date'] as int) * 1000);
          dataToUpdate['startDate'] = startTimestamp;
          print('Start date set to: ${startTimestamp.toDate()}');
        } catch (e) {
          print('Error parsing start_date: $e');
        }
      }

      // 終了日を設定
      if (subscription['current_period_end'] != null) {
        try {
          final endTimestamp = Timestamp.fromMillisecondsSinceEpoch(
              (subscription['current_period_end'] as int) * 1000);
          dataToUpdate['endDate'] = endTimestamp;
          dataToUpdate['current_period_end'] = endTimestamp; // 重要な新しいフィールド
          print('End date set to: ${endTimestamp.toDate()}');
        } catch (e) {
          print('Error parsing current_period_end: $e');
        }
      }

      // Firestoreに保存
      await _firestore
          .collection('subscriptions')
          .doc(uid)
          .set(dataToUpdate, SetOptions(merge: true));

      // キャッシュをクリアして最新情報が確実に使用されるようにする
      clearCache();

      print('Subscription data updated successfully in Firestore');
    } catch (e) {
      print('Error updating subscription from Stripe: $e');
      throw Exception('サブスクリプション情報の更新に失敗しました: $e');
    }
  }

  // サブスクリプション情報を読み込む
  Future<SubscriptionModel> _loadSubscription() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません');
    }

    try {
      final docRef = _firestore.collection('subscriptions').doc(user.uid);
      final docSnapshot = await docRef.get();

      SubscriptionModel subscription;
      if (docSnapshot.exists) {
        // 既存のサブスクリプション情報を取得
        final data = docSnapshot.data() as Map<String, dynamic>;
        subscription = SubscriptionModel.fromMap(data);
      } else {
        // 新規ユーザーの場合はデフォルトの無料プランを作成
        subscription = SubscriptionModel.defaultFree(user.uid);
        await docRef.set(subscription.toMap());
      }

      // 使用回数のリセットをチェック
      subscription = await _checkUsageReset(subscription);

      // キャッシュを更新
      _cachedSubscription = subscription;

      // ストリームに通知
      _subscriptionController.add(subscription);

      return subscription;
    } catch (e) {
      print('サブスクリプション情報取得エラー: $e');
      throw Exception('サブスクリプション情報の取得に失敗しました: $e');
    }
  }

  // 使用回数のリセットが必要かチェック
  Future<SubscriptionModel> _checkUsageReset(
      SubscriptionModel subscription) async {
    // プレミアムプランはチェック不要
    if (subscription.isPremium) return subscription;

    final now = DateTime.now();

    // リセット日が設定されていないか、リセット日を過ぎている場合
    if (subscription.usageResetDate == null ||
        now.isAfter(subscription.usageResetDate!)) {
      // 使用回数をリセットして次のリセット日を設定
      final updatedSubscription = subscription.copyWith(
        thinkingModeUsed: 0,
        multiAgentModeUsed: 0,
        usageResetDate: subscription.calculateNextResetDate(),
      );

      // Firestoreに保存
      await _updateSubscription(updatedSubscription);

      return updatedSubscription;
    }

    return subscription;
  }

  // 思考モードの使用回数をインクリメント
  Future<bool> incrementThinkingModeUsage() async {
    final subscription = await getUserSubscription();

    // プレミアムユーザーは無制限
    if (subscription.isPremium) return true;

    // 使用可能回数を超えている場合
    if (subscription.remainingThinkingModeUses <= 0) {
      return false;
    }

    // 使用回数をインクリメント
    final updatedSubscription = subscription.incrementThinkingModeUsage();
    await _updateSubscription(updatedSubscription);

    return true;
  }

  // 思考モードの使用回数をチェックし、必要に応じてアップグレードダイアログを表示
  Future<bool> checkThinkingModeUsage(BuildContext context) async {
    final subscription = await getUserSubscription();

    // プレミアムユーザーは無制限
    if (subscription.isPremium) return true;

    // 使用可能回数を超えている場合
    if (subscription.remainingThinkingModeUses <= 0) {
      // アップグレードダイアログを表示
      final willUpgrade = await UpgradeDialog.show(
        context: context,
        mode: 'thinking',
        remainingUses: subscription.remainingThinkingModeUses,
        totalUses: SubscriptionModel.maxThinkingModeUsage,
      );

      return willUpgrade;
    }

    return true;
  }

  // マルチエージェントモードの使用回数をインクリメント
  Future<bool> incrementMultiAgentModeUsage() async {
    final subscription = await getUserSubscription();

    // プレミアムユーザーは無制限
    if (subscription.isPremium) return true;

    // 使用可能回数を超えている場合
    if (subscription.remainingMultiAgentModeUses <= 0) {
      return false;
    }

    // 使用回数をインクリメント
    final updatedSubscription = subscription.incrementMultiAgentModeUsage();
    await _updateSubscription(updatedSubscription);

    return true;
  }

  // マルチエージェントモードの使用回数をチェックし、必要に応じてアップグレードダイアログを表示
  Future<bool> checkMultiAgentModeUsage(BuildContext context) async {
    final subscription = await getUserSubscription();

    // プレミアムユーザーは無制限
    if (subscription.isPremium) return true;

    // 使用可能回数を超えている場合
    if (subscription.remainingMultiAgentModeUses <= 0) {
      // アップグレードダイアログを表示
      final willUpgrade = await UpgradeDialog.show(
        context: context,
        mode: 'multi_agent',
        remainingUses: subscription.remainingMultiAgentModeUses,
        totalUses: SubscriptionModel.maxMultiAgentModeUsage,
      );

      return willUpgrade;
    }

    return true;
  }

  // サブスクリプション情報を更新
  Future<void> _updateSubscription(SubscriptionModel subscription) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません');
    }

    try {
      await _firestore
          .collection('subscriptions')
          .doc(user.uid)
          .set(subscription.toMap());

      // キャッシュを更新
      _cachedSubscription = subscription;

      // ストリームに通知
      _subscriptionController.add(subscription);
    } catch (e) {
      print('サブスクリプション更新エラー: $e');
      throw Exception('サブスクリプション情報の更新に失敗しました: $e');
    }
  }

  // プレミアムプランにアップグレード
  Future<void> upgradeToPremium(
      {SubscriptionType planType = SubscriptionType.premium_monthly,
      DateTime? endDate}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません');
    }

    final now = DateTime.now();
    DateTime subscriptionEndDate;

    // プランタイプに基づいて終了日を計算
    if (endDate != null) {
      subscriptionEndDate = endDate;
    } else if (planType == SubscriptionType.premium_yearly) {
      // 年間プラン: 1年後
      subscriptionEndDate = DateTime(now.year + 1, now.month, now.day);
    } else {
      // 月額プラン: 1ヶ月後
      subscriptionEndDate = DateTime(now.year, now.month + 1, now.day);
    }

    final currentSubscription = await getUserSubscription();
    final updatedSubscription = currentSubscription.copyWith(
      type: planType,
      startDate: now,
      endDate: subscriptionEndDate,
      lastUpdated: now,
    );

    await _updateSubscription(updatedSubscription);
  }

  // 無料プランにダウングレード
  Future<void> downgradeToFree() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません');
    }

    final now = DateTime.now();

    final currentSubscription = await getUserSubscription();
    final updatedSubscription = currentSubscription.copyWith(
      type: SubscriptionType.free,
      endDate: now, // 即時終了
      lastUpdated: now,
    );

    await _updateSubscription(updatedSubscription);
  }

  /// サブスクリプションを解約する
  ///
  /// Web版とiOS版の両方に対応したサブスクリプション解約機能を提供します
  Future<Map<String, dynamic>> cancelSubscription() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'ユーザーがログインしていません'};
      }

      // Web版とiOS版の分岐
      if (kIsWeb) {
        // Web版はサーバーサイドのStripe関数で解約
        return await cancelWebSubscription();
      } else if (Platform.isIOS) {
        // iOS版はApp Storeでの解約に誘導
        return await cancelIosSubscription();
      } else {
        return {'success': false, 'error': 'サポートされていないプラットフォームです'};
      }
    } catch (e) {
      print('サブスクリプション解約エラー: $e');
      return {'success': false, 'error': '解約処理中にエラーが発生しました: $e'};
    }
  }

  /// Web版のサブスクリプション解約
  ///
  /// HTTP直接呼び出しでFirebase FunctionsにcancelStripeSubscriptionV2を呼び出し、
  /// Stripe APIを使用してサブスクリプションを解約するとともに、
  /// Firestoreのデータも更新します。
  Future<Map<String, dynamic>> cancelWebSubscription() async {
    try {
      // 認証情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      print('サブスクリプション解約処理: HTTP直接呼び出しで解約関数を実行します');

      // HTTP直接呼び出しを使用
      final debugService = FirebaseDebugService();
      final httpResult = await debugService.callStripeCancelSubscription();
      print('HTTP直接呼び出し解約結果: $httpResult');

      if (httpResult.containsKey('status') &&
          httpResult['status'] == 'success' &&
          httpResult['http_response'] != null &&
          httpResult['http_response']['result'] != null) {
        final resultData = httpResult['http_response']['result'];
        if (resultData['success'] == true) {
          // 解約成功時、Firestoreのサブスクリプション情報を更新
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            try {
              // 現在の課金期間終了時に解約予定を記録
              var cancelAtTimestamp;
              if (resultData['current_period_end'] != null) {
                final periodEnd = DateTime.fromMillisecondsSinceEpoch(
                    resultData['current_period_end'] * 1000);
                cancelAtTimestamp = Timestamp.fromDate(periodEnd);
              }

              await _firestore
                  .collection('subscriptions')
                  .doc(user.uid)
                  .update({
                'status': 'canceling', // 解約予定ステータスに更新
                'cancel_at_period_end': true,
                'canceled_at': FieldValue.serverTimestamp(),
                'cancel_at': cancelAtTimestamp,
              });

              // キャッシュをクリアして即度次回の読み込み時に最新情報が反映されるようにする
              clearCache();
              print('解約ステータスをFirestoreに反映させました（解約予定）');
            } catch (e) {
              print('解約ステータスの更新エラー: $e');
            }
          }

          return {
            'success': true,
            'message': resultData['message'] ?? 'サブスクリプションのキャンセルが完了しました。',
            'subscription': resultData['subscription'],
            'current_period_end': resultData['current_period_end']
          };
        }
      }

      // HTTP直接呼び出しが失敗した場合
      print('HTTP直接呼び出しが失敗しました: $httpResult');
      return {
        'success': false,
        'error':
            'サブスクリプション解約中にエラーが発生しました: ${httpResult['http_body'] ?? '不明なエラー'}'
      };
    } catch (e) {
      print('サブスクリプション解約エラー: $e');
      return {'success': false, 'error': '解約処理中にエラーが発生しました: $e'};
    }
  }

  /// iOS版のサブスクリプション解約
  Future<Map<String, dynamic>> cancelIosSubscription() async {
    try {
      // iOSの場合はApp Storeの設定ページで解約する必要がある
      // iOSの仕様上、アプリから直接解約することはできないので、
      // ユーザーにApp Storeの設定ページを開くように案内する

      // iOSのサブスクリプション設定ページを開く
      await _storeKitService.openSubscriptionSettings();

      return {
        'success': true,
        'message': 'サブスクリプション設定ページが開かれました\n設定ページで解約手続きを行ってください',
        'requires_manual_action': true
      };
    } catch (e) {
      return {'success': false, 'error': 'サブスクリプション設定ページを開けませんでした: $e'};
    }
  }

  /// サブスクリプションを再開する
  ///
  /// 解約予定のサブスクリプションを再開し、継続させるようにする
  Future<Map<String, dynamic>> reactivateSubscription() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'ユーザーがログインしていません'};
      }

      // Web版とiOS版の分岐
      if (kIsWeb) {
        // Web版はサーバーサイド関数で再開
        return await reactivateWebSubscription();
      } else if (Platform.isIOS) {
        // iOS版はApp Storeでの再開に誘導
        return await reactivateIosSubscription();
      } else {
        return {'success': false, 'error': 'サポートされていないプラットフォームです'};
      }
    } catch (e) {
      print('サブスクリプション再開エラー: $e');
      return {'success': false, 'error': '再開処理中にエラーが発生しました: $e'};
    }
  }

  /// Web版のサブスクリプション再開
  Future<Map<String, dynamic>> reactivateWebSubscription() async {
    try {
      // 認証情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      print('サブスクリプション再開処理: HTTP直接呼び出しで再開関数を実行します');

      // HTTP直接呼び出しに変更
      final debugService = FirebaseDebugService();
      final httpResult = await debugService.callStripeReactivateSubscription();
      print('HTTP直接呼び出し再開結果: $httpResult');

      if (httpResult.containsKey('status') &&
          httpResult['status'] == 'success' &&
          httpResult['http_response'] != null &&
          httpResult['http_response']['result'] != null) {
        final resultData = httpResult['http_response']['result'];
        if (resultData['success'] == true) {
          return {
            'success': true,
            'message': resultData['message'] ?? 'サブスクリプションの再開が完了しました。',
            'subscription': resultData['subscription']
          };
        }
      }

      // HTTP呼び出しが成功しなかった場合のSDKバックアップ処理
      print('バックアップ: SDKを使用して再開処理を実行');
      final callable = FirebaseFunctions.instance
          .httpsCallable('ankiPaiReactivateSubscription');
      final result = await callable.call({});
      final responseData = result.data as Map<dynamic, dynamic>;

      // 成功時
      if (responseData['success'] == true) {
        // 再読込みを行い、最新の状態を反映させる
        await getUserSubscription(); // 最新のサブスクリプション情報を取得

        return {
          'success': true,
          'message': responseData['message'] ?? 'サブスクリプションが正常に再開されました。',
        };
      } else {
        // エラーの場合
        return {
          'success': false,
          'error': responseData['error'] ?? '再開中に予期せぬエラーが発生しました'
        };
      }
    } catch (e) {
      return {'success': false, 'error': '再開処理中にエラーが発生しました: $e'};
    }
  }

  /// iOS版のサブスクリプション再開
  Future<Map<String, dynamic>> reactivateIosSubscription() async {
    try {
      // iOSの場合はApp Storeの設定ページで再開する必要がある
      // ユーザーにApp Storeの設定ページを開くように案内する

      // iOSのサブスクリプション設定ページを開く
      await _storeKitService.openSubscriptionSettings();

      return {
        'success': true,
        'message': 'サブスクリプション設定ページが開かれました\n設定ページで再開手続きを行ってください',
        'requires_manual_action': true
      };
    } catch (e) {
      return {'success': false, 'error': 'サブスクリプション設定ページを開けませんでした: $e'};
    }
  }

  // カードセット数制限のチェック
  Future<bool> canCreateCardSet() async {
    final subscription = await getUserSubscription();
    if (subscription.isPremium) return true;

    final cardSetService = _getIt<CardSetService>();
    final ownedCardSets = await cardSetService.getUserCardSets();

    return ownedCardSets.length < SubscriptionModel.maxCardSets;
  }

  // カードセット数の制限を確認し、必要に応じてアップグレードダイアログを表示
  Future<bool> checkCardSetLimit(BuildContext context) async {
    final subscription = await getUserSubscription();
    if (subscription.isPremium) return true;

    final cardSetService = _getIt<CardSetService>();
    final ownedCardSets = await cardSetService.getUserCardSets();

    if (ownedCardSets.length >= SubscriptionModel.maxCardSets) {
      // アップグレードダイアログを表示
      final willUpgrade = await UpgradeDialog.show(
        context: context,
        mode: 'card_sets',
      );

      return willUpgrade;
    }

    return true;
  }

  // カード数制限のチェック
  Future<bool> canAddCardToSet(String cardSetId) async {
    final subscription = await getUserSubscription();
    if (subscription.isPremium) return true;

    final flashCardService = _getIt<FlashCardService>();
    final cardCount = await flashCardService.getCardCountForSet(cardSetId);

    return cardCount < SubscriptionModel.maxCardsPerSet;
  }

  // カード数の制限を確認し、必要に応じてアップグレードダイアログを表示
  Future<bool> checkCardLimit(BuildContext context, String cardSetId) async {
    final subscription = await getUserSubscription();
    if (subscription.isPremium) return true;

    final flashCardService = _getIt<FlashCardService>();
    final cardCount = await flashCardService.getCardCountForSet(cardSetId);

    if (cardCount >= SubscriptionModel.maxCardsPerSet) {
      // アップグレードダイアログを表示
      final willUpgrade = await UpgradeDialog.show(
        context: context,
        mode: 'cards_per_set',
      );

      return willUpgrade;
    }

    return true;
  }

  // アプリ内課金の初期化
  Future<void> _initializeInAppPurchase() async {
    try {
      print('アプリ内課金システムを初期化中...');
      final isAvailable = await _inAppPurchase.isAvailable();

      // Web環境ではデスクトップブラウザでの課金APIサポートが限定的
      if (kIsWeb) {
        print('Web環境では課金機能をシミュレーションモードで実行します');

        // Web用のダミー商品情報を生成
        _createDummyProductsForWeb();
        return;
      }

      // アプリ内課金が利用可能かチェック
      if (!isAvailable) {
        print('アプリ内課金が利用できません。デバイスがサポートしているか確認してください。');
        return;
      }

      print('アプリ内課金が利用可能です。初期化を続行します...');

      // iOSの場合はStoreKit 2を使用
      if (Platform.isIOS && !kIsWeb) {
        print('iOS向けにStoreKit 2を初期化します');
        await _storeKitService.initialize();

        // StoreKit 2のステータス更新リスナーを設定
        _storeKitService.purchaseStatusStream.listen((status) {
          if (status == PurchaseStatus.purchased ||
              status == PurchaseStatus.restored) {
            // 購入または復元完了時にサブスクリプション情報を更新
            refreshSubscription();
          }
        });

        // StoreKit 2から商品情報を取得
        _products = _storeKitService.products;
        return;
      }

      // Android/その他のプラットフォーム向け
      if (!kIsWeb) {
        // 既存のサブスクリプションを解除
        _purchaseStreamSubscription?.cancel();

        // ストアからの購入情報を監視
        final purchaseStream = _inAppPurchase.purchaseStream;
        _purchaseStreamSubscription = purchaseStream.listen(
          _handlePurchaseUpdates,
          onDone: () {
            print('購入ストリームが終了しました');
            _purchaseStreamSubscription?.cancel();
          },
          onError: (error) => print('購入ストリームエラー: $error'),
        );

        print('購入ストリームのリスナーを設定しました');

        // 利用可能な商品情報を取得
        await _loadProducts();
      }
    } catch (e) {
      print('アプリ内課金初期化エラー: $e');
      // エラーが発生してもアプリ自体は動作させる
    }
  }

  // Web環境用のダミー商品情報を生成
  void _createDummyProductsForWeb() {
    // Web版では課金APIをシミュレートするダミープロダクトを使用
    _products = [
      _createDummyProductDetail(
        id: SubscriptionConstants.monthlyProductIdWeb,
        title: 'プレミアムプラン（月額）',
        description: '月々のプレミアムサブスクリプション',
        price: '980円',
        currencyCode: 'JPY',
        currencySymbol: '¥',
      ),
      _createDummyProductDetail(
        id: SubscriptionConstants.yearlyProductIdWeb,
        title: 'プレミアムプラン（年間）',
        description: '年間プレミアムサブスクリプション（30%お得）',
        price: '9,800円',
        currencyCode: 'JPY',
        currencySymbol: '¥',
      ),
    ];

    print('Web用ダミー商品情報を生成しました: ${_products.length}件');
  }

  // Web用のダミー商品詳細を作成
  ProductDetails _createDummyProductDetail({
    required String id,
    required String title,
    required String description,
    required String price,
    required String currencyCode,
    required String currencySymbol,
  }) {
    return ProductDetails(
      id: id,
      title: title,
      description: description,
      price: price,
      rawPrice: id.contains('yearly') ? 9800 : 980,
      currencyCode: currencyCode,
    );
  }

  // 商品情報の取得
  Future<void> _loadProducts() async {
    try {
      // Web環境では別途実装済み
      if (kIsWeb) {
        print('Web環境ではネイティブの課金APIを使用しません');
        return;
      }

      // プラットフォームごとのプロダクトIDを取得
      String platform;
      if (Platform.isIOS) {
        platform = 'ios';
        print('iOSプラットフォームを検出しました');
      } else if (Platform.isAndroid) {
        platform = 'android';
        print('Androidプラットフォームを検出しました');
      } else {
        print('サポートされていないプラットフォーム');
        return;
      }

      final productIds = SubscriptionConstants.getProductIds(platform);
      print('商品情報を取得中: ${productIds.join(', ')}');

      final ProductDetailsResponse productResponse =
          await _inAppPurchase.queryProductDetails(productIds.toSet());

      if (productResponse.error != null) {
        print('商品情報取得エラー: ${productResponse.error}');
        return;
      }

      if (productResponse.productDetails.isEmpty) {
        print('警告: App Store/Google Playから商品情報が取得できませんでした');
        print('商品IDが正しく設定されているか、また開発者アカウントで商品が正しく登録されているか確認してください');

        // 空の商品リストではなく、ダミーの商品情報を使用する
        if (platform == 'ios') {
          print('テスト用にiOS向けダミー商品情報を生成します');
          _products = [
            _createDummyProductDetail(
              id: SubscriptionConstants.monthlyProductIdIOS,
              title: 'プレミアムプラン（月額）',
              description: '月々のプレミアムサブスクリプション',
              price: '¥380',
              currencyCode: 'JPY',
              currencySymbol: '¥',
            ),
            _createDummyProductDetail(
              id: SubscriptionConstants.yearlyProductIdIOS,
              title: 'プレミアムプラン（年間）',
              description: '年間プレミアムサブスクリプション（お得なプラン）',
              price: '¥2,980',
              currencyCode: 'JPY',
              currencySymbol: '¥',
            ),
          ];
        } else {
          print('テスト用にAndroid向けダミー商品情報を生成します');
          _products = [
            _createDummyProductDetail(
              id: SubscriptionConstants.monthlyProductIdAndroid,
              title: 'プレミアムプラン（月額）',
              description: '月々のプレミアムサブスクリプション',
              price: '¥380',
              currencyCode: 'JPY',
              currencySymbol: '¥',
            ),
            _createDummyProductDetail(
              id: SubscriptionConstants.yearlyProductIdAndroid,
              title: 'プレミアムプラン（年間）',
              description: '年間プレミアムサブスクリプション（お得なプラン）',
              price: '¥2,980',
              currencyCode: 'JPY',
              currencySymbol: '¥',
            ),
          ];
        }
        print('ダミー商品情報を生成しました: ${_products.length}件');
        return;
      }

      _products = productResponse.productDetails;
      print('取得した商品情報: ${_products.length}件');
      for (var product in _products) {
        print('- ${product.id}: ${product.title} (${product.price})');
      }
    } catch (e) {
      print('商品情報の取得に失敗しました: $e');
      // エラーは無視して空の商品リストで続行
      _products = [];
    }
  }

  // 月額プランを購入
  Future<void> purchaseMonthlyPlan() async {
    await _makePurchase(SubscriptionType.premium_monthly);
  }

  // 年間プランを購入
  Future<void> purchaseYearlyPlan() async {
    await _makePurchase(SubscriptionType.premium_yearly);
  }

  // 購入処理
  Future<void> _makePurchase(SubscriptionType planType) async {
    try {
      // ユーザーがログインしているか確認
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // Web版は課金APIをシミュレート
      if (kIsWeb) {
        // Web版ではシミュレーションモードで自動的に購入成功とする
        print('Web環境では購入をシミュレーションします');

        // Web環境では即時シミュレーション
        await _simulateWebPurchase(planType);
        return;
      }

      // iOS向けにStoreKit 2を使用
      if (Platform.isIOS) {
        print('iOS向けStoreKit 2で購入処理を実行します');
        if (planType == SubscriptionType.premium_yearly) {
          await _storeKitService.purchaseYearlyPlan();
        } else {
          await _storeKitService.purchaseMonthlyPlan();
        }
        return;
      }

      // Android/その他向け処理

      // 先に商品情報が取得されているか確認
      if (_products.isEmpty) {
        print('商品情報が取得されていません。再取得を試みます。');
        await _loadProducts();

        // 再取得後も空なら例外
        if (_products.isEmpty) {
          throw Exception('商品情報の取得に失敗しました');
        }
      }

      // プラットフォームごとの処理
      String productId;
      if (Platform.isAndroid) {
        // Android版
        productId = planType == SubscriptionType.premium_yearly
            ? SubscriptionConstants.yearlyProductIdAndroid
            : SubscriptionConstants.monthlyProductIdAndroid;
      } else {
        throw Exception('サポートされていないプラットフォーム');
      }

      print('購入を開始: プロダクトID=$productId');

      // 対象の商品情報を探す
      final productDetails = _products.firstWhere(
        (product) => product.id == productId,
        orElse: () => throw Exception(
            '商品情報が見つかりません: $productId\n利用可能な商品: ${_products.map((p) => p.id).join(', ')}'),
      );

      print('商品が見つかりました: ${productDetails.title} (${productDetails.id})');

      // 購入リクエストを作成
      final purchaseParam = PurchaseParam(productDetails: productDetails);

      // 購入処理を開始
      bool purchaseStarted;
      if (productDetails.id.contains('monthly') ||
          productDetails.id.contains('yearly')) {
        // サブスクリプション商品
        print('サブスクリプション購入を開始します');
        purchaseStarted =
            await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        // 消費型商品
        print('消費型商品購入を開始します');
        purchaseStarted =
            await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      }

      if (!purchaseStarted) {
        throw Exception('購入処理の開始に失敗しました');
      }

      print('購入処理が開始されました。ストアからの応答を待っています...');
    } catch (e) {
      print('購入処理エラー: $e');
      throw Exception('購入処理に失敗しました: $e');
    }
  }

  /// Web環境でのStripe Checkout処理
  Future<void> _simulateWebPurchase(SubscriptionType planType) async {
    try {
      print('Stripe決済処理を開始します...');

      // 選択されたプランにpriceIdを設定
      String priceId;
      if (planType == SubscriptionType.premium_yearly) {
        priceId = 'price_1RGbsYG3lcdzm6JzSNzLzknn'; // 年間プランの価格ID
      } else {
        priceId = 'price_1RGbsBG3lcdzm6JzRch4AlCx'; // 月額プランの価格ID
      }

      // HTTP直接呼び出しでStripe Checkoutセッションを作成
      print('HTTP直接呼び出しでチェックアウトセッションを作成します');
      final debugService = FirebaseDebugService();
      final checkoutResult =
          await debugService.callStripeCheckout(priceId: priceId);
      print('Stripeチェックアウト結果: $checkoutResult');

      if (checkoutResult.containsKey('status') &&
          checkoutResult['status'] == 'success' &&
          checkoutResult['http_response'] != null &&
          checkoutResult['http_response']['result'] != null) {
        final resultData = checkoutResult['http_response']['result'];
        final String? checkoutUrl = resultData['checkout_url'];

        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          // 支払いURLをブラウザで開く
          print('Stripe支払いページを開きます: $checkoutUrl');
          await launchUrl(Uri.parse(checkoutUrl),
              mode: LaunchMode.externalApplication);
          return;
        }
      }

      // 失敗またはチェックアウトURLが取得できなかった場合
      print('チェックアウトURLの取得に失敗しました。バックアップ処理を実行します。');

      // バックアップ処理（テスト環境でのプレースホルダー）
      print('注意: 実サーバーへの接続が失敗しました。テストモードを使用します。');

      // デバッグ用のシミュレーション処理
      await Future.delayed(const Duration(seconds: 1));
      final now = DateTime.now();
      DateTime endDate = (planType == SubscriptionType.premium_yearly)
          ? DateTime(now.year + 1, now.month, now.day)
          : DateTime(now.year, now.month + 1, now.day);

      await upgradeToPremium(planType: planType, endDate: endDate);
      print('購入が成功しました！（テストモード）');
    } catch (e) {
      print('購入処理エラー: $e');
      rethrow;
    }
  }

  // 購入情報の更新を処理
  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    print('購入更新イベントを受信: ${purchaseDetailsList.length}件');
    for (var purchaseDetails in purchaseDetailsList) {
      print(
          '購入ステータス: ${purchaseDetails.status.toString()} - 商品ID: ${purchaseDetails.productID}');
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // 処理中
        print('購入処理中: ${purchaseDetails.productID}');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // エラー
        print('購入エラー: ${purchaseDetails.error?.message}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // 購入完了または復元完了
        print('購入完了: ${purchaseDetails.productID}');

        // 購入検証と有効化処理
        await _verifyAndDeliverProduct(purchaseDetails);
      }

      // 購入完了の確認（iOSとAndroidで処理が異なる）
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  // 購入検証と商品の提供
  Future<void> _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) async {
    try {
      print('購入検証を開始: ${purchaseDetails.productID}');

      // 購入したプランを判断
      SubscriptionType planType;
      if (purchaseDetails.productID
              .contains(SubscriptionConstants.yearlyProductIdIOS) ||
          purchaseDetails.productID
              .contains(SubscriptionConstants.yearlyProductIdAndroid) ||
          purchaseDetails.productID.contains('yearly')) {
        planType = SubscriptionType.premium_yearly;
        print('年間プランが購入されました');
      } else {
        planType = SubscriptionType.premium_monthly;
        print('月額プランが購入されました');
      }

      // サブスクリプションの有効期限を設定
      final now = DateTime.now();
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
      await upgradeToPremium(planType: planType, endDate: endDate);

      print('サブスクリプションが正常に更新されました: $planType');

      // キャッシュをクリアして最新情報を取得
      clearCache();
      await refreshSubscription();

      // サーバーへの購入情報登録処理（必要に応じて）
      // 課金情報をFirestoreに記録
      try {
        final user = _auth.currentUser;
        if (user != null) {
          await _firestore.collection('purchase_records').add({
            'userId': user.uid,
            'productId': purchaseDetails.productID,
            'purchaseTime': FieldValue.serverTimestamp(),
            'transactionId': purchaseDetails.purchaseID,
            'planType': planType.toString(),
            'startDate': now.toIso8601String(),
            'endDate': endDate.toIso8601String(),
          });
          print('購入記録がFirestoreに保存されました');
        }
      } catch (e) {
        // 購入記録のエラーはサブスクリプション自体に影響しないよう無視
        print('購入記録の保存中にエラーが発生しました: $e');
      }
    } catch (e) {
      print('購入検証エラー: $e');
      throw Exception('購入の検証に失敗しました: $e');
    }
  }

  // 復元処理
  Future<void> restorePurchases() async {
    try {
      // iOS向けStoreKit 2処理
      if (Platform.isIOS && !kIsWeb) {
        await _storeKitService.restorePurchases();
        return;
      }

      // その他のプラットフォーム
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      print('購入の復元に失敗しました: $e');
      throw Exception('購入の復元に失敗しました: $e');
    }
  }

  void dispose() {
    _purchaseStreamSubscription?.cancel();
    _subscriptionController.close();

    // StoreKit 2のリソース解放
    if (Platform.isIOS && !kIsWeb) {
      _storeKitService.dispose();
    }
  }
}
