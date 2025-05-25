import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Functionsに関する問題をデバッグするためのサービス
class FirebaseDebugService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Firebase Functionsのベースエンドポイント
  // 注：実際のプロジェクトIDに合わせて変更する必要がある
  static const String _baseUrl =
      'https://asia-northeast1-anki-pai.cloudfunctions.net';

  /// シンプルデバッグ関数をHTTP直接呼び出しで実行する
  Future<Map<String, dynamic>> callSimpleDebug() async {
    return await testDirectFunctionCall(functionName: 'ankiPaiSimpleDebug');
  }

  /// ストライプサブスクリプション関数をHTTP直接呼び出しで実行する
  Future<Map<String, dynamic>> callStripeSubscription() async {
    return await testDirectFunctionCall(
        functionName: 'ankiPaiStripeSubscription');
  }

  /// ストライプサブスクリプション解約関数をHTTP直接呼び出しで実行する
  Future<Map<String, dynamic>> callStripeCancelSubscription() async {
    return await testDirectFunctionCall(
        functionName: 'ankiPaiCancelSubscription');
  }

  /// ストライプサブスクリプション再開関数をHTTP直接呼び出しで実行する
  Future<Map<String, dynamic>> callStripeReactivateSubscription() async {
    return await testDirectFunctionCall(
        functionName: 'ankiPaiReactivateSubscription');
  }

  /// ストライプチェックアウト関数をHTTP直接呼び出しで実行する
  Future<Map<String, dynamic>> callStripeCheckout(
      {required String priceId}) async {
    return await testDirectFunctionCall(
        functionName: 'ankiPaiCreateStripeCheckout',
        params: {'priceId': priceId});
  }

  /// 直接HTTPリクエストを使ってFunction呼び出しをテストする
  Future<Map<String, dynamic>> testDirectFunctionCall(
      {required String functionName, Map<String, dynamic>? params}) async {
    try {
      // 認証トークンを取得
      final User? user = _auth.currentUser;
      if (user == null) {
        return {'error': '認証されていません'};
      }

      // IDトークンを取得 - Firebase Functionsの認証に必要
      final String? idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return {'error': 'IDトークンが取得できませんでした'};
      }

      // シンプルな直接エンドポイントURLを構築
      final url = '$_baseUrl/$functionName';
      print('リクエスト先URL: $url');

      // IDトークンと認証バイパスフラグを含むJSONペイロード作成
      Map<String, dynamic> dataWithToken = {
        'idToken': idToken,
        'uid': user.uid, // ユーザーIDを明示的に送信
        'debug_mode': true, // デバッグモードを有効化
        'skip_auth_check': true, // 認証チェックをスキップ
        'direct_http_call': true // HTTP直接呼び出しフラグ
      };

      if (params != null && params.isNotEmpty) {
        dataWithToken.addAll(params);
      }

      final payload = {'data': dataWithToken};
      print('リクエストペイロード: $payload');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      print('HTTP レスポンスステータス: ${response.statusCode}');
      print('HTTP レスポンス本文: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return {
          'status': 'success',
          'http_response': responseData,
        };
      } else {
        return {
          'status': 'error',
          'http_status': response.statusCode,
          'http_body': response.body,
        };
      }
    } catch (e) {
      print('直接HTTP呼び出しエラー: $e');
      return {'error': e.toString()};
    }
  }

  /// Firebase Functionsの設定を診断する
  Future<Map<String, dynamic>> diagnoseFirebaseSetup() async {
    final Map<String, dynamic> results = {};

    try {
      // 1. 認証状態の確認
      final User? user = _auth.currentUser;
      results['auth_status'] =
          user != null ? 'authenticated' : 'not_authenticated';
      if (user != null) {
        results['user_id'] = user.uid;
        results['email'] = user.email;

        // 2. トークンの取得テスト
        try {
          final String? tokenNullable = await user.getIdToken();
          final String token = tokenNullable ?? '';
          results['token_fetch'] = 'success';
          results['token_preview'] =
              '${token.isNotEmpty ? token.substring(0, math.min(10, token.length)) : "empty"}...';
        } catch (e) {
          results['token_fetch'] = 'error';
          results['token_error'] = e.toString();
        }
      }

      // 3. 直接HTTP呼び出しのテスト
      results['direct_http_test'] =
          await testDirectFunctionCall(functionName: 'ankiPaiSimpleDebug');
    } catch (e) {
      results['overall_error'] = e.toString();
    }

    return results;
  }
}
