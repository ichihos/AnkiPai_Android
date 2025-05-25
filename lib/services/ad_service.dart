import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/subscription_service.dart';

class AdService {
  final SubscriptionService _subscriptionService =
      GetIt.instance<SubscriptionService>();

  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;

  AdService._internal() {
    print('AdService: 初期化');
  }

  // 広告ユニットID
  static const String _testBannerAdUnitIdAndroid =
      'ca-app-pub-1198819922308744~6529175909';
  static const String _prodBannerAdUnitIdIOS =
      'ca-app-pub-1198819922308744/5001169916';
  static const String _testInterstitialAdUnitIdAndroid =
      'ca-app-pub-1198819922308744~6529175909';
  static const String _prodInterstitialAdUnitIdIOS =
      'ca-app-pub-1198819922308744/1783963725';
  static const String _testRewardedAdUnitIdAndroid =
      'ca-app-pub-1198819922308744/6884811814';
  static const String _prodRewardedAdUnitIdIOS =
      'ca-app-pub-1198819922308744/6243193302';

  // 広告の状態
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _isInterstitialAdLoading = false;
  bool _isRewardedAdLoading = false;
  bool _isAdInitialized = false;

  // コンプリータ
  Completer<bool>? _rewardedAdCompleter;

  // バナー広告IDを取得
  String get _bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testBannerAdUnitIdAndroid;
    if (Platform.isIOS) return _prodBannerAdUnitIdIOS;
    return '';
  }

  // インタースティシャル広告IDを取得
  String get _interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testInterstitialAdUnitIdAndroid;
    if (Platform.isIOS) return _prodInterstitialAdUnitIdIOS;
    return '';
  }

  // リワード広告IDを取得
  String get _rewardedAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testRewardedAdUnitIdAndroid;
    if (Platform.isIOS) return _prodRewardedAdUnitIdIOS;
    return '';
  }

  // 広告を初期化
  Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    try {
      await MobileAds.instance.initialize();
      _isAdInitialized = true;
    } catch (e) {}
  }

  // 広告表示確認
  Future<bool> _shouldShowAds() async {
    try {
      final subscription = await _subscriptionService.getUserSubscription();
      return !subscription.isPremium;
    } catch (e) {
      return false; // エラーが発生した場合は広告を表示しない
    }
  }

  // バナー広告をロード
  Future<BannerAd?> loadBannerAd() async {
    if (kIsWeb || !_isAdInitialized) return null;

    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return null;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {},
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    );

    try {
      await _bannerAd!.load();
      return _bannerAd;
    } catch (e) {
      _bannerAd?.dispose();
      _bannerAd = null;
      return null;
    }
  }

  // バナー広告ウィジェットを取得
  Widget getBannerAdWidget() {
    if (_bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  // インタースティシャル広告をロード
  Future<void> loadInterstitialAd() async {
    if (kIsWeb || !_isAdInitialized || _isInterstitialAdLoading) return;

    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return;

    _isInterstitialAdLoading = true;

    try {
      await InterstitialAd.load(
        adUnitId: _interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isInterstitialAdLoading = false;

            // 広告クローズ時のコールバック設定
            _interstitialAd!.fullScreenContentCallback =
                FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _interstitialAd = null;
                // 次の広告をプリロード
                loadInterstitialAd();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                _interstitialAd = null;
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isInterstitialAdLoading = false;
          },
        ),
      );
    } catch (e) {
      _isInterstitialAdLoading = false;
    }
  }

  // インタースティシャル広告を表示
  Future<bool> showInterstitialAd() async {
    if (kIsWeb || !_isAdInitialized) return true;

    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return true;

    if (_interstitialAd == null) {
      // バックグラウンドで次回のために広告をロード
      loadInterstitialAd();
      return true; // 広告がなくても処理を続行
    }

    try {
      await _interstitialAd!.show();
      return true;
    } catch (e) {
      _interstitialAd?.dispose();
      _interstitialAd = null;
      return true; // エラーが発生しても処理を続行
    }
  }

  // リワード広告をロード
  Future<void> loadRewardedAd() async {
    if (kIsWeb || !_isAdInitialized || _isRewardedAdLoading) return;

    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return;

    _isRewardedAdLoading = true;

    try {
      await RewardedAd.load(
        adUnitId: _rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _isRewardedAdLoading = false;

            // 広告クローズ時のコールバック設定
            _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                _rewardedAd = null;

                // 広告が閉じられた場合でもリワードが付与されていれば成功
                if (_rewardedAdCompleter != null &&
                    !_rewardedAdCompleter!.isCompleted) {
                  _rewardedAdCompleter!.complete(false);
                }

                // 次の広告をプリロード
                loadRewardedAd();
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                ad.dispose();
                _rewardedAd = null;

                if (_rewardedAdCompleter != null &&
                    !_rewardedAdCompleter!.isCompleted) {
                  _rewardedAdCompleter!.complete(true); // エラーでも処理を続行
                }
              },
            );
          },
          onAdFailedToLoad: (error) {
            _isRewardedAdLoading = false;
          },
        ),
      );
    } catch (e) {
      _isRewardedAdLoading = false;
    }
  }

  // リワード広告を表示し、視聴完了を待つ
  Future<bool> showRewardedAd() async {
    if (kIsWeb || !_isAdInitialized) return true;

    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return true;

    if (_rewardedAd == null) {
      // バックグラウンドで次回のために広告をロード
      loadRewardedAd();
      return true; // 広告がなくても処理を続行
    }

    _rewardedAdCompleter = Completer<bool>();

    try {
      _rewardedAd!.show(
        onUserEarnedReward: (_, reward) {
          if (_rewardedAdCompleter != null &&
              !_rewardedAdCompleter!.isCompleted) {
            _rewardedAdCompleter!.complete(true);
          }
        },
      );

      // 広告視聴の結果を待つ
      return await _rewardedAdCompleter!.future;
    } catch (e) {
      _rewardedAd?.dispose();
      _rewardedAd = null;

      if (_rewardedAdCompleter != null && !_rewardedAdCompleter!.isCompleted) {
        _rewardedAdCompleter!.complete(true);
      }

      return true; // エラーが発生しても処理を続行
    }
  }

  // 広告表示のダイアログを表示
  Future<bool> showAdRequiredDialog(
      BuildContext context, String actionName) async {
    final shouldShowAds = await _shouldShowAds();
    if (!shouldShowAds) return true;

    // プリロードされたリワード広告があるかチェック
    if (_rewardedAd == null) {
      await loadRewardedAd();
      // 広告がロードされるまで少し待つ
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!context.mounted) return false;

    // ダイアログを表示
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('広告視聴が必要です'),
        content: Text('$actionNameを続けるには、短い広告を視聴してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('広告を視聴'),
          ),
        ],
      ),
    );

    if (result != true) return false;

    // リワード広告を表示
    return await showRewardedAd();
  }

  // リソース解放
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _bannerAd = null;
    _interstitialAd = null;
    _rewardedAd = null;
  }
}
