import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// APIトークン管理サービス
/// AI APIにアクセスするための一時トークンを管理する
class ApiTokenService {
  
  // トークン情報
  String? _token;
  DateTime? _tokenExpiry;
  
  // Firebase Functions
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // トークン取得中かどうかのフラグ
  bool _isGettingToken = false;
  
  // トークン取得待ちのCompleterのリスト
  final List<Completer<String>> _tokenCompleters = [];
  
  /// トークンが有効かどうかを確認
  bool get isTokenValid {
    if (_token == null || _tokenExpiry == null) {
      return false;
    }
    
    // 有効期限の5分前にトークンを無効とみなす（更新のためのバッファ）
    final now = DateTime.now();
    return _tokenExpiry!.isAfter(now.add(const Duration(minutes: 5)));
  }
  
  /// 一時APIトークンを取得する
  Future<String> getToken() async {
    // 有効なトークンがある場合はそれを返す
    if (isTokenValid) {
      return _token!;
    }
    
    // 既に取得処理中の場合は、トークンが取得されるまで待機
    if (_isGettingToken) {
      final completer = Completer<String>();
      _tokenCompleters.add(completer);
      return completer.future;
    }
    
    // トークン取得処理を開始
    _isGettingToken = true;
    
    try {
      // Firebase Functionsを呼び出してトークンを取得
      final result = await _functions
          .httpsCallable('ankiPaiGenerateAPIToken')
          .call();
      
      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true && data['token'] != null) {
        _token = data['token'] as String;
        
        // 有効期限を設定（サーバーからの有効期限を使用）
        final expiresIn = data['expiresIn'] as int? ?? 900; // デフォルト15分
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        
        debugPrint('APIトークンを取得しました。有効期限: ${_tokenExpiry!.toIso8601String()}');
        
        // 待機中のCompletersにトークンを提供
        for (final completer in _tokenCompleters) {
          if (!completer.isCompleted) {
            completer.complete(_token);
          }
        }
        _tokenCompleters.clear();
        
        return _token!;
      } else {
        throw Exception('トークン取得エラー: ${data['message'] ?? "不明なエラー"}');
      }
    } catch (e) {
      debugPrint('APIトークン取得中にエラーが発生しました: $e');
      
      // エラーを待機中のCompletersに通知
      for (final completer in _tokenCompleters) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
      _tokenCompleters.clear();
      
      rethrow;
    } finally {
      _isGettingToken = false;
    }
  }
  
  /// トークンを無効化（強制更新が必要な場合など）
  void invalidateToken() {
    _token = null;
    _tokenExpiry = null;
    debugPrint('APIトークンを無効化しました');
  }
  
  /// APIプロキシを使用してAPIを呼び出す（将来的な実装用）
  Future<Map<String, dynamic>> callApiViaProxy({
    required String endpoint,
    required String method,
    required Map<String, dynamic> data,
    String apiType = 'deepseek',
  }) async {
    final token = await getToken();
    
    final result = await _functions.httpsCallable('apiProxy').call({
      'token': token,
      'endpoint': endpoint,
      'method': method,
      'data': data,
      'apiType': apiType,
    });
    
    return result.data as Map<String, dynamic>;
  }
  
  /// サービスの破棄
  void dispose() {
    _token = null;
    _tokenExpiry = null;
    
    // 未完了のCompletersをエラーで完了
    for (final completer in _tokenCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('サービスが破棄されました'));
      }
    }
    _tokenCompleters.clear();
  }
}
