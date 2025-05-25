import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:anki_pai/constants/subscription_constants.dart';
import 'package:anki_pai/models/subscription_model.dart';

/// Stripe決済サービスクラス
class StripeService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// チェックアウトセッションを作成してブラウザで決済画面を開く
  Future<Map<String, dynamic>> startSubscription(SubscriptionType type) async {
    try {
      // ユーザーがログインしているか確認
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      // プランとプランIDを決定
      String plan;
      String priceId;

      switch (type) {
        case SubscriptionType.premium_monthly:
          plan = 'monthly';
          priceId = kIsWeb
              ? SubscriptionConstants.monthlyProductIdWeb
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? SubscriptionConstants.monthlyProductIdIOS
                  : SubscriptionConstants.monthlyProductIdAndroid);
          break;
        case SubscriptionType.premium_yearly:
          plan = 'yearly';
          priceId = kIsWeb
              ? SubscriptionConstants.yearlyProductIdWeb
              : (defaultTargetPlatform == TargetPlatform.iOS
                  ? SubscriptionConstants.yearlyProductIdIOS
                  : SubscriptionConstants.yearlyProductIdAndroid);
          break;
        default:
          throw Exception('無効なサブスクリプションタイプです');
      }

      // プラットフォーム情報の取得
      String platform;
      if (kIsWeb) {
        platform = 'web';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        platform = 'ios';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        platform = 'android';
      } else {
        platform = 'other';
      }

      // Firebase Functionsを呼び出してチェックアウトセッションを作成
      final result =
          await _functions.httpsCallable('ankiPaiCreateStripeCheckout').call({
        'plan': plan,
        'priceId': priceId,
        'platform': platform, // プラットフォーム情報を送信
      });

      final sessionId = result.data['sessionId'];
      final url = result.data['url'];

      // URLを開く
      if (url != null && url.isNotEmpty) {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('決済URLを開けませんでした');
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

  /// 顧客ポータルを開く（サブスクリプション管理）
  Future<bool> openCustomerPortal() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('ユーザーがログインしていません');
      }

      final result =
          await _functions.httpsCallable('ankiPaiCreateStripePortal').call({});

      final url = result.data['url'];
      if (url != null && url.isNotEmpty) {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        } else {
          throw Exception('顧客ポータルURLを開けませんでした');
        }
      }

      return false;
    } catch (e) {
      print('顧客ポータルエラー: $e');
      return false;
    }
  }

  /// 現在のサブスクリプション情報を取得
  Future<SubscriptionModel?> getCurrentSubscription() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }

      // Firebase Functionsを呼び出してサブスクリプション情報を取得
      final result =
          await _functions.httpsCallable('ankiPaiGetStripeSubscription').call({});

      if (!result.data['active']) {
        return SubscriptionModel.defaultFree(user.uid);
      }

      // Firestoreからのデータを直接取得
      final snapshot =
          await _firestore.collection('subscriptions').doc(user.uid).get();

      if (!snapshot.exists) {
        return SubscriptionModel.defaultFree(user.uid);
      }

      // プラン情報を変換
      SubscriptionType type;
      final plan = result.data['plan'] ?? 'free';
      switch (plan) {
        case 'monthly':
          type = SubscriptionType.premium_monthly;
          break;
        case 'yearly':
          type = SubscriptionType.premium_yearly;
          break;
        default:
          type = SubscriptionType.free;
      }

      // サブスクリプションのデータを取得
      final data = snapshot.data()!;
      final startDate = data['current_period_start'] as Timestamp?;
      final endDate = data['current_period_end'] as Timestamp?;

      return SubscriptionModel(
        userId: user.uid,
        type: type,
        startDate: startDate?.toDate(),
        endDate: endDate?.toDate(),
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      print('サブスクリプション情報取得エラー: $e');
      return null;
    }
  }

  /// サブスクリプションが有効かどうかを確認
  Future<bool> isSubscriptionActive() async {
    try {
      final subscription = await getCurrentSubscription();
      return subscription?.isActive ?? false;
    } catch (e) {
      print('サブスクリプション確認エラー: $e');
      return false;
    }
  }
}
