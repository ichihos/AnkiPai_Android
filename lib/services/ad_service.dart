import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'subscription_service.dart';

// This is a stub implementation of AdService while Google Mobile Ads is disabled
// All ad-related functionality will return empty/dummy values

// Stub classes for Google Mobile Ads
class AdRequest {
  const AdRequest();
}

class BannerAdListener {
  final Function(dynamic)? onAdLoaded;
  final Function(dynamic, dynamic)? onAdFailedToLoad;
  
  BannerAdListener({this.onAdLoaded, this.onAdFailedToLoad});
}

class InterstitialAdLoadCallback {
  final Function(dynamic)? onAdLoaded;
  final Function(dynamic)? onAdFailedToLoad;
  
  InterstitialAdLoadCallback({this.onAdLoaded, this.onAdFailedToLoad});
}

class RewardedAdLoadCallback {
  final Function(dynamic)? onAdLoaded;
  final Function(dynamic)? onAdFailedToLoad;
  
  RewardedAdLoadCallback({this.onAdLoaded, this.onAdFailedToLoad});
}

class FullScreenContentCallback {
  final Function(dynamic)? onAdDismissedFullScreenContent;
  final Function(dynamic, dynamic)? onAdFailedToShowFullScreenContent;
  
  FullScreenContentCallback({this.onAdDismissedFullScreenContent, this.onAdFailedToShowFullScreenContent});
}

// Stub class for BannerAd
class BannerAd {
  final String adUnitId;
  final AdSize size;
  final AdRequest request;
  final dynamic listener;
  FullScreenContentCallback? fullScreenContentCallback;

  BannerAd({required this.adUnitId, required this.size, required this.request, required this.listener});

  Future<void> load() async {}
  void dispose() {}
  Future<void> show() async {}
  
  static Future<BannerAd> createAd({required String adUnitId, required AdRequest request, required dynamic adLoadCallback, dynamic rewardedAdLoadCallback}) async {
    return BannerAd(adUnitId: adUnitId, size: AdSize.banner, request: request, listener: BannerAdListener());
  }
}

// Stub classes for Interstitial and Rewarded ads
class InterstitialAd {
  FullScreenContentCallback? fullScreenContentCallback;
  
  static Future<void> load({required String adUnitId, required AdRequest request, required InterstitialAdLoadCallback adLoadCallback}) async {
    // Simulate successful loading
    final onAdLoaded = adLoadCallback.onAdLoaded;
    if (onAdLoaded != null) {
      final ad = InterstitialAd();
      onAdLoaded(ad);
    }
    return;
  }
  
  Future<void> show() async {}
  void dispose() {}
}

class RewardedAd {
  FullScreenContentCallback? fullScreenContentCallback;
  
  static Future<void> load({required String adUnitId, required AdRequest request, required RewardedAdLoadCallback rewardedAdLoadCallback}) async {
    // Simulate successful loading
    final onAdLoaded = rewardedAdLoadCallback.onAdLoaded;
    if (onAdLoaded != null) {
      final ad = RewardedAd();
      onAdLoaded(ad);
    }
    return;
  }
  
  Future<void> show({required dynamic onUserEarnedReward}) async {
    // Simulate reward immediately
    if (onUserEarnedReward != null) {
      onUserEarnedReward(null, null);
    }
  }
  
  void dispose() {}
}

// Stub class for AdSize
class AdSize {
  final double width;
  final double height;
  
  const AdSize({required this.width, required this.height});
  
  static const banner = AdSize(width: 320, height: 50);
}

// Stub class for MobileAds
class MobileAds {
  static final MobileAds _instance = MobileAds._internal();
  
  factory MobileAds() {
    return _instance;
  }
  
  MobileAds._internal();
  
  static MobileAds get instance => _instance;
  
  Future<void> initialize() async {}
}

// Stub class for AdWidget
class AdWidget extends StatelessWidget {
  final BannerAd ad;
  
  const AdWidget({super.key, required this.ad});
  
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class AdService {
  final SubscriptionService _subscriptionService =
      GetIt.instance<SubscriptionService>();

  // Ad unit IDs (will not be used in stub implementation)
  static const String _testBannerAdUnitIdAndroid = 'test-banner-ad-id';
  static const String _prodBannerAdUnitIdIOS = 'prod-banner-ad-id';
  static const String _testInterstitialAdUnitIdAndroid = 'test-interstitial-ad-id';
  static const String _prodInterstitialAdUnitIdIOS = 'prod-interstitial-ad-id';
  static const String _testRewardedAdUnitIdAndroid = 'test-rewarded-ad-id';
  static const String _prodRewardedAdUnitIdIOS = 'prod-rewarded-ad-id';

  // Ad state (all null in stub implementation)
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _isInterstitialAdLoading = false;
  bool _isRewardedAdLoading = false;
  bool _isAdInitialized = false;

  // Completer
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

  // 広告表示前にプレミアムユーザーかどうかをチェック
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
