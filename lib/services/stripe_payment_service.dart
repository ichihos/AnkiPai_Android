// 基本インポート
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Firebase関連
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// FieldValueをインポート
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;

// Stripe関連
import 'package:flutter_stripe/flutter_stripe.dart';

// クロスプラットフォームのURLオープナー
import 'url_opener.dart';

import '../models/subscription_model.dart';
import '../constants/subscription_constants.dart';

/// Stripe決済サービスクラス（Web専用）
class StripePaymentService {
  // Stripeの公開キー - 環境に応じて適切なキーを設定してください
  static const String _publishableKey =
      'pk_live_51REAH6G3lcdzm6JzYs2V15FdbzZyyrUlmQ6FZ8JxwAbyoh6Gpc4CotfsrC8XbOAUv71NUQLr9ftMVXq9OMPRm4tm005IAE08ob';

  // すべてのメソッドをstaticにするため、FirebaseFunctionsもstaticで定義
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  // Stripe初期化フラグ
  static bool _isInitialized = false;

  /// Opens a URL in the browser - platform-specific implementation
  static Future<void> openUrlInBrowser(String url) async {
    try {
      // 改良したUrlOpenerクラスを使用する
      // これにより、Webとネイティブの両方で適切に処理される
      await UrlOpener.openUrl(url);
    } catch (e) {
      print('URLオープンエラー: $e');
    }
  }

  /// Stripeサービスの初期化
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('Stripe already initialized');
      return;
    }

    if (kIsWeb) {
      // Webの場合はStripeのAPIキーを設定する
      Stripe.publishableKey = _publishableKey;
      print(
          'Stripe publishable key set: ${_publishableKey.substring(0, 10)}...');
      _isInitialized = true;
    }
  }

  /// 決済シートを表示してサブスクリプションを開始
  static Future<Map<String, dynamic>> startSubscription(
      SubscriptionType type) async {
    try {
      if (!kIsWeb) {
        throw Exception('この決済方法はWeb環境でのみ利用可能です');
      }

      // 初期化されていなければ初期化
      if (!_isInitialized) {
        await initialize();
      }

      // 現在のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // プランと価格IDを決定
      String plan;
      String priceId;

      switch (type) {
        case SubscriptionType.premium_monthly:
          plan = 'monthly';
          priceId = SubscriptionConstants.monthlyProductIdWeb;
          break;
        case SubscriptionType.premium_yearly:
          plan = 'yearly';
          priceId = SubscriptionConstants.yearlyProductIdWeb;
          break;
        default:
          throw Exception('無効なサブスクリプションタイプです');
      }

      // プラットフォーム情報を取得して渡す
      String platform = 'web';
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }

      print('デバイスプラットフォーム: $platform');
      print('決済処理の開始: プラットフォーム=$platform');

      // Firebase Functionsを呼び出してチェックアウトセッションを作成
      final result =
          await _functions.httpsCallable('ankiPaiCreateStripeCheckout').call({
        'plan': plan,
        'priceId': priceId,
        'platform': platform, // プラットフォーム情報を追加
      });

      // v1とv2の両方に対応するために、レスポンスデータを安全に取得
      final sessionId = result.data['sessionId'];
      final url = result.data['url'];

      // レスポンスとURLの検証
      if (url == null || url.isEmpty) {
        print('エラー: URLが無効です');
        return {
          'success': false,
          'error': 'StripeのURLが取得できませんでした',
        };
      }

      // URLを開く
      try {
        // 先にレスポンスを準備して、後でURLを開く
        final response = {
          'success': true,
          'sessionId': sessionId,
        };

        // ブラウザでURLを開く処理を改善
        // 小さな遅延を入れて処理の軽量化
        await Future.delayed(const Duration(milliseconds: 100));
        print('決済URLを開きます: $url');

        // URLを開く前に、先にレスポンスを準備
        // URL開封後の状態更新エラーを回避するため
        const futureDelay = Duration(milliseconds: 500);

        // URLの開封を安全に実行する関数
        Future<void> safelyOpenUrl() async {
          try {
            if (kIsWeb) {
              // Webの場合は別途実装のオープナーを使用
              print('Web用URLオープナーでオープンします：$url');
              await _openUrlInWebPlatform(url);
              print('Web用URLオープナー経由でURLが開かれました');
            } else {
              // モバイルの場合はネイティブURLランチャーを使用
              print('ネイティブURLランチャーでオープンします：$url');
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                // 外部アプリモードでオープン（コンテキスト参照問題を回避）
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                print('ネイティブURLランチャー経由でURLが開かれました');
              } else {
                throw Exception('Could not launch $url');
              }
            }
          } catch (urlError) {
            print('URL開封エラー: $urlError');
            // エラーログのみ記録し、例外は投げない
          }
        }

        // 非同期でURLを開く - メインスレッドに影響を与えないように
        Future.delayed(futureDelay).then((_) => safelyOpenUrl());

        // URLが開く前に成功レスポンスを返し、コンテキストエラーを回避

        return response;
      } catch (e) {
        print('Stripeの決済ページを開く際にエラーが発生しました: $e');
        return {
          'success': false,
          'error': 'Stripeの決済ページを開けませんでした: $e',
        };
      }
    } catch (e) {
      print('Stripe決済エラー: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// サブスクリプションの現在の状態を取得
  static Future<SubscriptionModel?> getCurrentSubscription() async {
    try {
      print('★★★ getCurrentSubscription開始');

      // 現在のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('ユーザーがログインしていません');
        return null;
      }

      print('サブスクリプション情報取得: UID=${user.uid}');

      // シンプルなテスト関数を使用してみる
      try {
        print('★ シンプルテスト関数 getSimpleSubscriptionV2 を呼び出します');
        final simpleResult = await _functions
            .httpsCallable('ankiPaiGetSimpleSubscription')
            .call({});
        print('シンプルテスト関数からのレスポンス: ${simpleResult.data}');

        // シンプル関数が成功した場合
        if (simpleResult.data != null && simpleResult.data['active'] == true) {
          print('シンプル関数がアクティブなサブスクリプションを検出しました');

          // Firestoreから詳細情報を取得
          return await _getSubscriptionFromFirestore(user.uid);
        }

        // シンプル関数が失敗したか無料プランを返した場合
        if (simpleResult.data != null && simpleResult.data['active'] == false) {
          print('シンプル関数が無料プランを返しました');
          return SubscriptionModel.defaultFree(user.uid);
        }

        // シンプル関数がエラーを返した場合、通常の関数を試す
        print('シンプル関数のレスポンスが不明確です。標準関数を試みます');
      } catch (simpleError) {
        print('シンプルテスト関数呼び出しエラー: $simpleError');
        // シンプル関数が失敗した場合、エラーログを表示するが継続する
      }

      // 通常の処理を試行
      try {
        // 通常のFirebase Functionsを使用して最新のサブスクリプション情報を取得
        print('getStripeSubscription関数を呼び出します');
        final result = await _functions
            .httpsCallable('ankiPaiGetStripeSubscription')
            .call({});
        print('getStripeSubscription関数からのレスポンス: ${result.data}');

        // データがnullの場合のエラーハンドリング
        if (result.data == null) {
          print('警告: getStripeSubscriptionからnullデータが返されました');
          // Firestoreデータをフォールバックとして試す
          return await _getSubscriptionFromFirestore(user.uid);
        }

        // 'active'フィールドの存在を確認
        final isActive = result.data['active'] ?? false;
        if (!isActive) {
          print('アクティブなサブスクリプションはありません。無料プランを返します');
          return SubscriptionModel.defaultFree(user.uid);
        }

        print('アクティブなサブスクリプションが見つかりました');

        // Stripeからの情報でサブスクリプションデータを構築するオプション
        if (result.data.containsKey('type') &&
            result.data.containsKey('plan')) {
          print('Stripe APIからのデータを使用してサブスクリプションを構築します');
          final subscriptionMap = <String, dynamic>{
            'user_id': user.uid,
            'type': result.data['type'] ?? 'premium_monthly',
            'plan': result.data['plan'] ?? 'monthly',
            'status': result.data['status'] ?? 'active',
            'subscription_id': result.data['subscriptionId'],
            'price_id': result.data['priceId'],
            'cancel_at_period_end': result.data['cancelAtPeriodEnd'] ?? false,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          };

          // 日付情報がある場合は追加
          if (result.data.containsKey('currentPeriodEnd')) {
            subscriptionMap['current_period_end'] = DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch;
          }

          return SubscriptionModel.fromMap(subscriptionMap);
        }

        // Firestoreから詳細情報を取得
        return await _getSubscriptionFromFirestore(user.uid);
      } catch (functionError) {
        print('Firebase Functions呼び出しエラー: $functionError');
        // Functionsエラーの場合はFirestoreから情報取得を試みる
        return await _getSubscriptionFromFirestore(user.uid);
      }
    } catch (e) {
      print('サブスクリプション情報取得エラー（最上位）: $e');
      return null;
    }
  }

  /// Firestoreからサブスクリプション情報を取得（フォールバック処理）
  static Future<SubscriptionModel?> _getSubscriptionFromFirestore(
      String uid) async {
    try {
      print('Firestoreからサブスクリプション情報を取得: UID=$uid');
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(uid)
          .get();

      if (!snapshot.exists) {
        print('Firestoreにサブスクリプション情報が存在しません。無料プランを返します');
        return SubscriptionModel.defaultFree(uid);
      }

      final data = snapshot.data()!;
      print('Firestoreからサブスクリプションデータを取得: ${data['type'] ?? 'type不明'}');
      return SubscriptionModel.fromMap(data);
    } catch (e) {
      print('Firestoreからのサブスクリプション情報取得エラー: $e');
      return SubscriptionModel.defaultFree(uid);
    }
  }

  /// サブスクリプションをキャンセルする（課金期間終了時）
  /// V2対応版の実装
  static Future<Map<String, dynamic>> cancelStripeSubscription() async {
    try {
      print('★★★ cancelStripeSubscription開始');

      // Firebaseの認証情報を取得
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) {
        print('ユーザーがログインしていません');
        return {
          'success': false,
          'error': 'ユーザーがログインしていません',
        };
      }

      print('★★★ ユーザーUID: ${user.uid}');

      // 認証トークンを取得
      try {
        final idToken = await user.getIdToken();
        if (idToken != null && idToken.isNotEmpty) {
          print(
              '★★★ idToken取得成功: ${idToken.substring(0, min(20, idToken.length))}...');
        } else {
          print('★★★ idTokenがnullまたは空です');
          throw Exception('idTokenが取得できませんでした');
        }

        print(
            'サブスクリプション解約処理: Firebase FunctionsのcancelStripeSubscriptionV2を呼び出します');

        print('★★★ パラメータ: { idToken: "***" }');

        // まずは引数なしで試す
        try {
          print('★★★ 引数なしで試行');
          final resultWithoutParams = await _functions
              .httpsCallable('ankiPaiCancelStripeSubscription')
              .call({});
          print('★★★ 引数なしの場合の結果: ${resultWithoutParams.data}');

          // 結果を返す
          if (resultWithoutParams.data['success'] == true) {
            // 成功時はローカルのFirestoreを更新
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({
                'subscription': {
                  'cancelAtPeriodEnd': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
              });
              print('★★★ Firestore更新成功');
            } catch (firestoreError) {
              print('★★★ Firestore更新エラー (非致命的): $firestoreError');
            }

            return {
              'success': true,
              'message': 'サブスクリプションのキャンセルが完了しました。現在の課金期間終了時に解約されます。',
              'cancelAt': resultWithoutParams.data['current_period_end'],
            };
          }

          // 成功しなかった場合は、idTokenありの方法を試す
          print('★★★ 引数なしで失敗、idTokenありで再試行');
        } catch (noParamError) {
          print('★★★ 引数なしでの呼び出しエラー: $noParamError');
          // このエラーは無視して引数ありで再試行
        }

        // idTokenありで試す
        print('★★★ idTokenありで試行');
        final result = await _functions
            .httpsCallable('ankiPaiCancelStripeSubscription')
            .call({
          'idToken': idToken,
        });

        print('★★★ cancelStripeSubscriptionの結果: ${result.data}');

        if (result.data['success'] == true) {
          // 成功時はローカルのFirestoreを更新 (V1と同じパターン)
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({
              'subscription': {
                'cancelAtPeriodEnd': true,
                'updatedAt': FieldValue.serverTimestamp(),
              },
            });
            print('★★★ Firestore更新成功');
          } catch (firestoreError) {
            print('★★★ Firestore更新エラー (非致命的): $firestoreError');
          }

          return {
            'success': true,
            'message': 'サブスクリプションのキャンセルが完了しました。現在の課金期間終了時に解約されます。',
            'cancelAt': result.data['current_period_end'],
          };
        } else {
          print('★★★ エラーレスポンス: ${result.data}');
          return {
            'success': false,
            'error': result.data['error'] ?? 'サブスクリプションのキャンセルに失敗しました',
          };
        }
      } catch (tokenError) {
        print('★★★ idToken取得エラー: $tokenError');
        return {
          'success': false,
          'error': 'idTokenの取得に失敗しました: $tokenError',
        };
      }
    } catch (e) {
      print('★★★ サブスクリプションキャンセルエラー: $e');
      return {
        'success': false,
        'error': 'サブスクリプションのキャンセル中にエラーが発生しました: $e',
      };
    }
  }

  /// サブスクリプションポータルを開く
  static Future<Map<String, dynamic>> openSubscriptionPortal() async {
    try {
      // Firebaseの認証情報を取得
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) {
        print('ユーザーがログインしていません');
        return {
          'success': false,
          'error': 'ユーザーがログインしていません',
        };
      }

      // ポータルセッションを作成
      final result =
          await _functions.httpsCallable('ankiPaiCreateStripePortal').call({});

      // ポータルURLを取得
      final url = result.data['url'];
      if (url == null || url.isEmpty) {
        throw Exception('ポータルURLが取得できませんでした');
      }

      // ポータルURLを開く
      await openUrlInBrowser(url);

      return {
        'success': true,
        'url': url,
      };
    } catch (e) {
      print('ポータルセッション作成エラー: $e');
      return {
        'success': false,
        'error': 'ポータルの作成中にエラーが発生しました: $e',
      };
    }
  }

  /// 解約予定のサブスクリプションを再開する
  /// V2対応の実装
  static Future<Map<String, dynamic>> reactivateSubscription() async {
    try {
      // Firebaseの認証情報を取得
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) {
        print('ユーザーがログインしていません');
        return {
          'success': false,
          'error': 'ユーザーがログインしていません',
        };
      }

      // 認証トークンを取得
      final idToken = await user.getIdToken();

      print(
          'サブスクリプション再開処理: Firebase FunctionsのreactivateStripeSubscriptionを呼び出します');

      final result = await _functions
          .httpsCallable('ankiPaiReactivateStripeSubscription')
          .call({
        'idToken': idToken,
      });

      print('reactivateStripeSubscriptionの結果: ${result.data}');

      if (result.data['success'] == true) {
        // 成功時はローカルのFirestoreを更新
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'subscription': {
              'cancelAtPeriodEnd': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          });
        } catch (firestoreError) {
          print('Firestore更新エラー (非致命的): $firestoreError');
        }

        return {
          'success': true,
          'message': 'サブスクリプションが正常に再開されました。課金期間終了後もプランが継続されます。',
        };
      } else {
        return {
          'success': false,
          'error': result.data['error'] ?? 'サブスクリプションの再開に失敗しました',
        };
      }
    } catch (e) {
      print('サブスクリプション再開エラー: $e');
      return {
        'success': false,
        'error': 'サブスクリプションの再開中にエラーが発生しました: $e',
      };
    }
  }

  /// Webプラットフォームで専用の方法でURLを開くメソッド
  /// プラットフォーム互換のための実装
  static Future<void> _openUrlInWebPlatform(String url) async {
    // 単に別の静的メソッドに委託
    await openUrlInBrowser(url);
  }

  /// サブスクリプションを解約する
  static Future<Map<String, dynamic>> cancelSubscription() async {
    try {
      if (!kIsWeb) {
        throw Exception('この機能はWeb環境でのみ利用可能です');
      }

      // 初期化されていなければ初期化
      if (!_isInitialized) {
        await initialize();
      }

      // 現在のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // 最新のIDTokenを取得
      final idToken = await user.getIdToken();

      // Firebase Functionを呼び出してサブスクリプションを解約する
      final result = await _functions
          .httpsCallable('ankiPaiCancelStripeSubscription')
          .call({
        'idToken': idToken,
      });

      // 成功した場合
      if (result.data['success'] == true) {
        // ローカルのFirestoreも更新する
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'subscriptionStatus': 'inactive',
            'subscriptionEndDate': FieldValue.serverTimestamp(),
          });
        } catch (firestoreError) {
          print('Firestore最終更新エラー: $firestoreError');
        }

        return {
          'success': true,
          'message': 'サブスクリプションが正常に解約されました',
        };
      } else {
        return {
          'success': false,
          'error': result.data['error'] ?? '不明なエラー',
        };
      }
    } catch (e) {
      print('サブスクリプションの解約に失敗しました: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
