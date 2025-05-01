// 基本インポート
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// FieldValueをインポート
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
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
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

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
          await _functions.httpsCallable('createStripeCheckout').call({
        'plan': plan,
        'priceId': priceId,
        'platform': platform, // プラットフォーム情報を追加
      });

      final sessionId = result.data['sessionId'];
      final url = result.data['url'];

      // URLを開く
      if (url != null && url.isNotEmpty) {
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

          // URLオープン処理
          try {
            if (kIsWeb) {
              // Webの場合は別途実装のオープナーを使用
              await _openUrlInWebPlatform(url);
              print('Web用URLオープナー経由でURLが開かれました');
            } else {
              // モバイルの場合はネイティブURLランチャーを使用
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                print('ネイティブURLランチャー経由でURLが開かれました');
              } else {
                throw Exception('Could not launch $url');
              }
            }
          } catch (urlError) {
            print('URL開封エラー: $urlError');
            throw Exception('決済ページを開けませんでした: $urlError');
          }

          return response;
        } catch (e) {
          print('Stripeの決済ページを開く際にエラーが発生しました: $e');
          return {
            'success': false,
            'error': 'Stripeの決済ページを開けませんでした: $e',
          };
        }
      }

      return {
        'success': true,
        'sessionId': sessionId,
      };
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
      // 現在のユーザー情報を取得
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return null;
      }

      // Firebase Functionsを使用して最新のサブスクリプション情報を取得
      final result =
          await _functions.httpsCallable('getStripeSubscription').call({});

      if (!result.data['active']) {
        return SubscriptionModel.defaultFree(user.uid);
      }

      // Firestoreから詳細情報を取得
      final snapshot = await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(user.uid)
          .get();

      if (!snapshot.exists) {
        return SubscriptionModel.defaultFree(user.uid);
      }

      final data = snapshot.data()!;
      return SubscriptionModel.fromMap(data);
    } catch (e) {
      print('サブスクリプション情報取得エラー: $e');
      return null;
    }
  }

  /// 旧メソッド（互換性のため、cancelStripeSubscriptionに名前を変更）
  static Future<Map<String, dynamic>> cancelStripeSubscription() async {
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
          await _functions.httpsCallable('cancelStripeSubscription').call({});

      // レスポンスの処理
      if (result.data['success'] == true) {
        return {
          'success': true,
          'message': 'サブスクリプションのキャンセルが完了しました',
        };
      } else {
        return {
          'success': false,
          'error': result.data['error'] ?? 'サブスクリプションのキャンセルに失敗しました',
        };
      }
    } catch (e) {
      print('サブスクリプションキャンセルエラー: $e');
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
          await _functions.httpsCallable('createStripePortal').call({});

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
      final result =
          await _functions.httpsCallable('cancelStripeSubscription').call({
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
