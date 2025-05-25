import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service to handle connectivity state and provide offline capabilities
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  bool _isOffline = false;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  /// Singleton instance
  static final ConnectivityService _instance = ConnectivityService._internal();

  /// Factory constructor
  factory ConnectivityService() => _instance;

  /// Private constructor
  ConnectivityService._internal();

  /// Get current offline state
  bool get isOffline {
    print('📱 ConnectivityService.isOfflineの確認: $_isOffline');
    return _isOffline;
  }

  /// デバッグ用: 強制的にオフラインモードを設定
  void setForceOffline(bool value) {
    _isOffline = value;
    print('📱 強制オフラインモードを${value ? "有効" : "無効"}にしました');
  }

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    print('📱 ConnectivityServiceの初期化を開始します');

    // デバッグ用: 強制的にオフラインモードを設定する場合はここをコメント解除
    // _isOffline = true;
    // print('📱 デバッグ用: 強制的にオフラインモードを設定しました');
    // return;

    // Check initial connectivity state
    await checkConnectivity();

    // Start listening to connectivity changes
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      _updateConnectionStatus(result);
    });

    print('📱 ConnectivityServiceの初期化が完了しました: オフライン=$_isOffline');
  }

  /// Check current connectivity status
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      // Update connection status based on the result
      _updateConnectionStatus(result);
      return _isOffline;
    } catch (e) {
      print('❌ Connectivity check error: $e');
      // Assume offline if we can't check
      _isOffline = true;
      return true;
    }
  }

  /// Update connection status based on connectivity result
  void _updateConnectionStatus(ConnectivityResult result) {
    if (result == ConnectivityResult.none) {
      _isOffline = true;
      print('📱 Device is OFFLINE');
    } else {
      _isOffline = false;
      print('📱 Device is ONLINE (${result.name})');
    }
  }

  /// Dispose of resources
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
