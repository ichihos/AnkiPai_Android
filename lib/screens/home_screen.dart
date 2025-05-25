import 'dart:async';
import 'package:anki_pai/screens/subscription_info_screen.dart';
// ログビューア画面は削除されました
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Services
import '../services/memory_service.dart';
import '../services/card_set_service.dart';
import '../services/subscription_service.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../services/connectivity_service.dart';
import '../providers/language_provider.dart';

// Models
import '../models/subscription_model.dart';
import '../models/memory_technique.dart';

// Widgets
import '../widgets/common_widgets.dart';
import '../widgets/loading_animation_dialog.dart';
import '../widgets/image_crop_ocr_widget.dart';
import '../widgets/profile_avatar_widget.dart';
import '../widgets/upgrade_dialog.dart';

// Screens
import 'how_to_use_screen.dart';
import 'memory_method_screen.dart';
import 'library_screen.dart';
import 'card_sets_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'commercial_transaction_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedTabIndex = 0;
  bool _isProcessing = false;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  // サブスクリプション情報
  SubscriptionModel? _subscription;
  bool _isSubscriptionLoading = true;

  // AIモードの選択肢
  static const String MODE_STANDARD = 'standard'; // 標準モード
  static const String MODE_MULTI_AGENT = 'multi_agent'; // マルチエージェントモード
  static const String MODE_THINKING = 'thinking'; // 考え方モード

  // 選択されたAIモード
  String _selectedAiMode = MODE_STANDARD; // デフォルトは標準モード

  // 後方互換性のためのヘルパープロパティ
  bool get _useMultiAgentMode => _selectedAiMode == MODE_MULTI_AGENT;
  bool get _useThinkingMode => _selectedAiMode == MODE_THINKING;

  late final AdService adService = GetIt.instance<AdService>();

  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onTextChanged);
    // AIモードの設定を読み込む
    _loadAiModeSetting();

    // 動画広告を事前にロード
    if (!kIsWeb) {
      adService.loadInterstitialAd();
      adService.loadRewardedAd();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 最初のロードのみ実行（didChangeDependenciesは複数回呼ばれるため）
    if (_isFirstLoad) {
      _isFirstLoad = false;
      // データの初期読み込み - サービス初期化のみ行い、データ取得は延期
      _initializeServices();

      // 起動速度を上げるためにサブスク情報の補助的な値だけはロード
      _setInitialSubscriptionValue();

      // サブスクリプション情報を非同期で読み込む
      _loadSubscriptionInfoOnStartup();
    }
  }

  // 起動時の仮値を設定 (実際のデータはナビゲーション時に更新)
  void _setInitialSubscriptionValue() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid ?? '';

    setState(() {
      // 初期はローディングなしのフリーモードで表示
      _isSubscriptionLoading = false;
      _subscription = SubscriptionModel(
        userId: userId,
        type: SubscriptionType.free,
      );
    });
  }

  // タブ変更時にデータを更新する
  Future<void> _refreshDataOnTabChange(int tabIndex) async {
    // タブ変更時にサブスクリプション情報を更新
    print('タブ変更: タブ$tabIndex に切り替え - データ更新実行');
    await _loadSubscriptionInfo();

    // 必要に応じて他のデータ更新処理をタブごとに追加できる
    if (tabIndex == 0) {
      // ホームタブの場合の追加更新処理
    } else if (tabIndex == 1) {
      // カードセットタブの場合の追加更新処理
    } else if (tabIndex == 2) {
      // ライブラリタブの場合の追加更新処理
    }
  }

  // 他の画面から戻ってきたときにデータを更新する
  Future<void> _refreshDataAfterScreenReturn() async {
    // 画面遷移後にサブスクリプション情報を更新
    print('画面から戻ってきました - データ更新実行');
    await _loadSubscriptionInfo();
  }

  // サブスクリプション情報を読み込む - ナビゲーション時に呼び出される
  Future<void> _loadSubscriptionInfo() async {
    if (!mounted) return;

    // UIがレスポンシブであるようにローディング状態を設定
    setState(() {
      _isSubscriptionLoading = true;
    });

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);

      // キャッシュクリアはナビゲーション時にデータが必要な場合のみ行う
      // 起動時の不要な処理を減らす
      print('画面遷移/タブ切替: サブスク情報を取得中');

      // 通常のサブスク情報取得を実行 (重いrefreshSubscriptionは必要なときだけ実行)
      final subscription = await subscriptionService.getUserSubscription();
      print(
          'ナビゲーション後: サブスク情報 - タイプ: ${subscription.type}, プレミアム: ${subscription.isPremium}');

      if (mounted) {
        setState(() {
          _subscription = subscription;
          _isSubscriptionLoading = false;
        });
      }
    } catch (e) {
      print('サブスクリプション情報の取得エラー: $e');
      if (mounted) {
        setState(() {
          _isSubscriptionLoading = false;
        });
      }
    }
  }

  // アプリ起動時にサブスクリプション情報を読み込む
  Future<void> _loadSubscriptionInfoOnStartup() async {
    if (!mounted) return;

    try {
      final connectivityService = GetIt.instance<ConnectivityService>();
      final isOffline = connectivityService.isOffline;

      if (isOffline) {
        print('📱 オフラインモード: 起動時のサブスク情報取得をスキップします');
        return;
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      if (!authService.isAuthenticated()) {
        print('⚠️ 未認証状態: 起動時のサブスク情報取得をスキップします');
        return;
      }

      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);

      print('🚀 アプリ起動時: サブスク情報を非同期で取得中...');

      // サブスクリプション情報を非同期で取得
      final subscription = await subscriptionService.getUserSubscription();
      print(
          '✅ アプリ起動時: サブスク情報取得完了 - タイプ: ${subscription.type}, プレミアム: ${subscription.isPremium}');

      if (mounted) {
        setState(() {
          _subscription = subscription;
          _isSubscriptionLoading = false;
        });
      }
    } catch (e) {
      print('❌ アプリ起動時のサブスク情報取得エラー: $e');
      // エラー時は初期値のままとする
    }

    // 強制的にサブスク情報を更新する (購入後など必要な場合に呼び出す)
    Future<void> _forceRefreshSubscription() async {
      if (!mounted) return;

      setState(() {
        _isSubscriptionLoading = true;
      });

      try {
        final subscriptionService =
            Provider.of<SubscriptionService>(context, listen: false);

        // 強制的にキャッシュをクリアして最新情報を取得
        print('強制更新: サブスク情報を再取得中...');
        subscriptionService.clearCache();

        // サブスクリプション情報を強制的に更新
        final subscription = await subscriptionService.refreshSubscription();
        print(
            '強制更新後: サブスク情報 - タイプ: ${subscription.type}, プレミアム: ${subscription.isPremium}');

        if (mounted) {
          setState(() {
            _subscription = subscription;
            _isSubscriptionLoading = false;
          });
        }
      } catch (e) {
        print('強制更新エラー: $e');
        if (mounted) {
          setState(() {
            _isSubscriptionLoading = false;
          });
        }
      }
    }
  }

  // サービスを初期化し、データの読み込みを行う
  Future<void> _initializeServices() async {
    // didChangeDependenciesから呼ばれるため、contextは利用可能
    if (!mounted) return;

    // オフライン状態判定用の変数を定義
    bool isOffline = false;

    try {
      // ConnectivityServiceの状態を確認するのみ（main.dartで既に初期化済み）
      final connectivityService = GetIt.instance<ConnectivityService>();

      // オフライン状態を取得
      isOffline = connectivityService.isOffline;

      print('📱 接続状態確認: オフラインモード = $isOffline');

      if (isOffline) {
        print('📱 オフラインモード: ローカルストレージからデータを読み込みます');
      }

      final authService = Provider.of<AuthService>(context, listen: false);

      // オフラインモードでは認証チェックをスキップし、ローカルデータを読み込む
      if (isOffline || authService.isAuthenticated()) {
        // カードセット・メモリーサービスデータのリロード
        final cardSetService =
            Provider.of<CardSetService>(context, listen: false);
        final memoryService =
            Provider.of<MemoryService>(context, listen: false);

        // カードセットサービスの初期化
        try {
          // 初期化を実行
          await cardSetService.initialize();
          print('✅ カードセットサービスの初期化が完了しました');

          // オフラインモードの場合はローカルストレージからカードセットを読み込む
          if (isOffline) {
            try {
              // ローカルストレージからカードセットを読み込む
              await cardSetService.loadCardSetsFromLocalStorage();
              print('✅ オフラインモード: ローカルストレージからカードセットを読み込みました');
            } catch (localError) {
              print('⚠️ ローカルストレージからのカードセット読み込みエラー: $localError');
              // エラーが発生しても続行する
            }
          }
        } catch (csError) {
          print('❌ カードセットサービスの初期化エラー: $csError');

          // 初期化に失敗してもオフラインモードの場合はローカルストレージから読み込みを試みる
          if (isOffline) {
            try {
              await cardSetService.loadCardSetsFromLocalStorage();
              print('✅ オフラインモード: 初期化エラー後にローカルストレージからカードセットを読み込みました');
            } catch (localError) {
              print('⚠️ ローカルストレージからのカードセット読み込みエラー: $localError');
              // エラーが発生しても続行する
            }
          }
        }

        // メモリーサービスの初期化とデータ読み込み
        try {
          // オフラインモードの場合はローカルストレージから暗記法を読み込む
          if (isOffline) {
            try {
              // ローカルストレージから暗記法を読み込む
              await memoryService.loadMemoryTechniquesFromLocalStorage();
              print('✅ オフラインモード: ローカルストレージから暗記法を読み込みました');
            } catch (localError) {
              print('⚠️ ローカルストレージからの暗記法読み込みエラー: $localError');
              // エラーが発生しても続行する
            }
          } else {
            // オンラインモードの場合は通常の読み込みを行う
            // 最新の公開テクニックを読み込む
            try {
              await memoryService.getRecentPublicTechnique();
              print('✅ 公開暗記法の読み込み成功');
            } catch (rtError) {
              print('⚠️ 公開暗記法の読み込みエラー: $rtError');
              // エラーが発生しても続行する
            }

            // ユーザーの暗記法を読み込む
            try {
              await memoryService.getUserMemoryTechniques();
              print('✅ ユーザー暗記法の読み込み成功');
            } catch (umtError) {
              print('⚠️ ユーザー暗記法の読み込みエラー: $umtError');
              // エラーが発生しても続行する
            }
          }

          print('✅ 暗記アイテムの読み込み成功');
        } catch (mError) {
          print('❌ 暗記アイテムの読み込みエラー: $mError');
          // エラーが発生しても続行する
        }
      } else {
        print('⚠️ ユーザーが認証されていないため、データ読み込みをスキップします');
      }
    } catch (e) {
      print('❌ データ初期化エラー: $e');

      // 既に定義したisOffline変数を使用
      if (!isOffline) {
        // オンラインモードの場合のみエラーを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('データの読み込みに失敗しました。ログイン状態が無効です。')),
        );
      } else {
        print('📱 オフラインモードのため、エラーメッセージを表示しません');
      }
    }
  }

  // SharedPreferencesからAIモードの設定を読み込む
  Future<void> _loadAiModeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 新しいキーをチェック
      if (prefs.containsKey('aiMode')) {
        _selectedAiMode = prefs.getString('aiMode') ?? MODE_STANDARD;
      } else {
        // 後方互換性のために古い設定をチェック
        final oldMultiAgentSetting =
            prefs.getBool('useMultiAgentMode') ?? false;
        _selectedAiMode =
            oldMultiAgentSetting ? MODE_MULTI_AGENT : MODE_STANDARD;
      }
    });
  }

  // SharedPreferencesにAIモードの設定を保存する
  Future<void> _saveAiModeSetting(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aiMode', mode);

    // 後方互換性のために古いキーも更新
    await prefs.setBool('useMultiAgentMode', mode == MODE_MULTI_AGENT);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _inputController.removeListener(_onTextChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // テキスト入力を処理するメソッド
  Future<void> _handleTextSubmission() async {
    if (_isProcessing) return; // 既に処理中の場合は何もしない

    setState(() {
      _isProcessing = true;
    });

    final text = _inputController.text.trim();
    if (text.isEmpty) return; // 空の入力は処理しない

    // 特殊モードを使用する場合はサブスクリプション制限をチェック
    if (_selectedAiMode == MODE_MULTI_AGENT ||
        _selectedAiMode == MODE_THINKING) {
      if (!_isSubscriptionLoading &&
          _subscription != null &&
          !(_subscription?.isPremium ?? false)) {
        final remaining = _getRemainingUses(_selectedAiMode);
        if (remaining <= 0) {
          _showSubscriptionLimitDialog(_selectedAiMode == MODE_MULTI_AGENT
              ? AppLocalizations.of(context)!.multiAgentMode
              : AppLocalizations.of(context)!.thinkingMode);
          return;
        }
      }
    }

    // テキスト内に複数の項目があるか検出
    final geminiService = GetIt.instance<GeminiService>();

    // 考え方モードの場合、複数項目検出をスキップ
    Map<String, dynamic> result;
    bool isMultipleItems = false;
    int itemCount = 1;
    String detectionMessage = '';

    if (_useThinkingMode) {
      // 考え方モードの場合は単一項目として処理
      print('考え方モードが有効なため、複数項目検出をスキップします');
      result = {
        'isMultipleItems': false,
        'itemCount': 1,
        'message': AppLocalizations.of(context)!.processingWithThinkingMode
      };
      isMultipleItems = false;
      itemCount = 1;
    } else if (_useMultiAgentMode) {
      // マルチエージェントモードの場合は単一項目として処理
      print('マルチエージェントモードが有効なため、複数項目検出をスキップします');
      result = {
        'isMultipleItems': false,
        'itemCount': 1,
        'message': AppLocalizations.of(context)!.processingWithMultiAgentMode
      };
      isMultipleItems = false;
      itemCount = 1;
    } else {
      LoadingAnimationDialog.show(
        context,
        message: AppLocalizations.of(context)!.generatingMemoryTechnique,
        animationType: AnimationType.memory,
        // 考え方モードでは項目数を表示しない
        itemCount: null,
        showItemCount: false,
      );
      // 通常モードでは複数項目検出を実行
      // 複数項目の検出 - 高速検知とAIチェックの両方を行う

      result = await geminiService.detectMultipleItems(text);
      print('複数項目検出結果: $result');

      // GeminiServiceのキー名に合わせて取得
      isMultipleItems = result['isMultipleItems'] ?? false;
      itemCount = result['itemCount'] ?? 0; // 直接項目数を取得
      detectionMessage = result['message'] ?? '';

      // ログに検出詳細を出力
      if (isMultipleItems) {
        print('複数項目検出: $itemCount個の項目 (詳細: $detectionMessage)');
      }
      if (mounted) {
        Navigator.of(context).pop(); // ローディングダイアログを閉じる
      }
    }

    // 記憶法生成用のアニメーションダイアログを表示
    if (!mounted) return;
    LoadingAnimationDialog.show(
      context,
      message: _useThinkingMode
          ? AppLocalizations.of(context)!.generatingThinkingWay
          : (_useMultiAgentMode
              ? AppLocalizations.of(context)!.aiTeamGeneratingTechnique
              : (isMultipleItems
                  ? AppLocalizations.of(context)!.generatingMultipleTechniques
                  : AppLocalizations.of(context)!.generatingMemoryTechnique)),
      animationType: AnimationType.memory,
      // 考え方モードでは項目数を表示しない
      itemCount:
          (_useThinkingMode) ? null : (isMultipleItems ? itemCount : null),
      showItemCount: !_useThinkingMode && isMultipleItems,
    );

    // モバイルの場合は3秒後に動画広告を表示
    if (!kIsWeb) {
      adService.loadRewardedAd();
      Future.delayed(const Duration(seconds: 3), () async {
        if (mounted) {
          // 新しい実装では非同期で結果を受け取る
          final bool result = await adService.showRewardedAd();
          if (result && mounted) {
            // リワード広告の視聴が完了した場合の処理
            print('リワード広告視聴完了');
          }
        }
      });
    }

    try {
      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      final bool isValidAuth =
          user != null && await authService.validateAuthentication();

      // 匿名ユーザーも有効な認証として扱う
      if (!isValidAuth) {
        // 認証に問題がある場合は自動的に匿名認証を試みる
        setState(() {
          _isProcessing = false;
        });

        try {
          // 匿名認証を試みる
          await authService.signInAnonymously();
          print('処理中に匿名認証を実行しました');
          // 成功した場合は再度処理を試みる
          return _handleTextSubmission(); // 再帰的に呼び出し
        } catch (e) {
          print('処理中の匿名認証失敗: $e');

          // ログアウトせずに、直接ログイン画面に遷移する
          print('匿名ユーザーの状態で直接ログイン画面に遷移します');

          // ログイン画面に遷移
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );

          // ログイン画面から戻ってきた後、再度認証状態を確認
          if (authService.isAuthenticated() &&
              !authService.currentUser!.isAnonymous) {
            // ログインが完了していれば、再度処理を試みる
            print('ログイン後に再度処理を試みます');
            return _handleTextSubmission();
          }

          // 処理を中断
          return;
        }
      }

      final memoryService = Provider.of<MemoryService>(context, listen: false);

      // 選択されたAIモードに応じてAIを使用して暗記法を提案
      List<MemoryTechnique> techniques;
      // サブスクリプション制限のチェック
      if (_useMultiAgentMode) {
        // マルチエージェントモードの使用制限をチェック
        final subscriptionService =
            Provider.of<SubscriptionService>(context, listen: false);
        final canUseMultiAgent =
            await subscriptionService.incrementMultiAgentModeUsage();

        if (!canUseMultiAgent) {
          Navigator.pop(context); // ローディングダイアログを閉じる
          _showSubscriptionLimitDialog('マルチエージェントモード');
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        // サブスクリプション情報を更新して残り使用回数を反映
        await _loadSubscriptionInfo();
        // マルチエージェントモードがONの場合はランク付けされた暗記法を生成
        final rankedTechniques =
            await memoryService.suggestRankedMemoryTechniques(text);
        techniques = rankedTechniques.techniques;
        print('マルチエージェントモード: ${techniques.length}件の暗記法を生成しました');
      } else if (_useThinkingMode) {
        // 考え方モードの使用制限をチェック
        final subscriptionService =
            Provider.of<SubscriptionService>(context, listen: false);
        final canUseThinkingMode =
            await subscriptionService.incrementThinkingModeUsage();

        if (!canUseThinkingMode) {
          Navigator.pop(context); // ローディングダイアログを閉じる
          _showSubscriptionLimitDialog(
              AppLocalizations.of(context)!.thinkingMode);
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        // サブスクリプション情報を更新して残り使用回数を反映
        await _loadSubscriptionInfo();
        // 考え方モードの場合は考え方モード用の暗記法を生成
        try {
          // 考え方モードフラグを渡して暗記法を生成
          techniques = await memoryService.suggestMemoryTechniques(text,
              isThinkingMode: true, // 考え方モードフラグを追加
              multipleItemsDetection: result,
              itemCount: itemCount);
          print('考え方モード: ${techniques.length}件の暗記法を生成しました');

          // 考え方モードの説明はメモリーメソッド画面で生成される
        } catch (e) {
          print('考え方モードの暗記法生成エラー: $e');
          techniques = [];
        }
      } else {
        // 通常モードの場合は単一か複数項目の判定に応じて暗記法を生成
        print('検出された項目数: $itemCount');

        if (itemCount > 1) {
          // 複数項目として処理
          // AIが検出した項目数を尊重
          print('AIが検出した項目数を使用します: $itemCount件');

          // result['items']が存在する場合はそれを使用、そうでない場合は適切な形式に加工
          List<Map<String, dynamic>> itemsList;
          if (result.containsKey('items') &&
              result['items'] is List &&
              (result['items'] as List).isNotEmpty) {
            // AIが既に項目リストを提供している場合はそれを使用
            itemsList = List<Map<String, dynamic>>.from(result['items']);
            print('AIが検出した項目リストを使用します: ${itemsList.length}件');
          } else {
            // AIが項目リストを提供していない場合は、項目数に基づいてコンテンツを分割
            final List<String> lines = text
                .split('\n')
                .where((line) => line.trim().isNotEmpty)
                .take(itemCount)
                .toList();

            itemsList = [];
            for (int i = 0; i < lines.length && i < itemCount; i++) {
              itemsList.add({
                'content': lines[i].trim(),
                'type': 'text',
              });
            }
            print('テキスト分割により項目リストを作成しました: ${itemsList.length}件');
          }

          final detectionInfo = <String, dynamic>{
            'itemCount': itemCount, // AIが判断した項目数
            'message': AppLocalizations.of(context)!.multipleItemsDetected,
            'rawContent': text, // 生データも渡す
            'items': itemsList, // 項目リスト
          };

          print('複数項目を処理します: $itemCount件');
          techniques = await memoryService.suggestMemoryTechniques(
            text,
            multipleItemsDetection: detectionInfo,
            itemCount: itemCount,
          );
        } else {
          // 単一項目として処理
          techniques = await memoryService.suggestMemoryTechniques(text,
              itemCount: itemCount);
        }

        print('通常モード: ${techniques.length}件の暗記法を生成しました');
      }

      // 暗記法が空の場合はデフォルトの暗記法を追加
      if (techniques.isEmpty) {
        print('警告: 暗記法が生成されませんでした。デフォルトの暗記法を追加します。');
        techniques = [
          MemoryTechnique(
            name: AppLocalizations.of(context)!.defaultMemoryMethodName,
            description:
                AppLocalizations.of(context)!.defaultMemoryMethodDescription,
            type: 'concept',
          )
        ];
      }

      // 生成された暗記法からタイトルを取得
      String itemTitle = '';
      if (techniques.isNotEmpty && techniques[0].name.isNotEmpty) {
        itemTitle = techniques[0].name; // 最初の暗記法のnameフィールドに共通タイトルが設定されています
      } else {
        // デフォルトタイトル（最初の10文字＋...）
        itemTitle = text.length > 10 ? '${text.substring(0, 10)}...' : text;
      }

      // テキストメモリーアイテムを追加
      final docRef = await memoryService.addTextMemoryItem(
        itemTitle,
        text,
        techniques,
      );

      // 入力フィールドをクリア
      _inputController.clear();

      // ローディングダイアログを明示的に閉じる
      if (mounted) {
        Navigator.of(context).pop(); // ローディングダイアログを閉じる
      }

      // 暗記法画面に遷移
      final item = await memoryService.getMemoryItemById(docRef.id);
      if (item != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MemoryMethodScreen(
              memoryItem: item,
              useMultiAgentMode: _useMultiAgentMode,
              useThinkingMode: _useThinkingMode,
            ),
          ),
        );
      }
    } catch (e) {
      // エラー発生時はローディングダイアログを閉じる
      if (mounted) {
        Navigator.of(context).pop(); // ローディングダイアログを閉じる
      }

      String errorMessage = e.toString();
      // エラーメッセージをユーザーフレンドリーに調整
      if (errorMessage.contains('permission-denied')) {
        errorMessage = AppLocalizations.of(context)!.permissionDeniedError;
      } else if (errorMessage.contains(AppLocalizations.of(context)!.login)) {
        errorMessage = AppLocalizations.of(context)!.loginRequiredError;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.addFailed(errorMessage)),
          backgroundColor: Colors.red.shade400,
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.login,
            textColor: Colors.white,
            onPressed: () async {
              // ログイン画面に遷移
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );

              // ログイン画面から戻ってきた後、全てのサービスリスナーをリセット
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              if (authService.isAuthenticated() &&
                  !authService.currentUser!.isAnonymous) {
                final cardSetService =
                    Provider.of<CardSetService>(context, listen: false);
                final memoryService =
                    Provider.of<MemoryService>(context, listen: false);

                // 認証状態が変わったのでリスナーをクリーンアップ
                cardSetService.cleanupAllListeners();
                memoryService.cleanupAllListeners();

                try {
                  await cardSetService.initialize();
                  print('ログイン画面から戻った後のCardSetServiceの初期化が完了しました');
                } catch (e) {
                  print('ログイン画面から戻った後のCardSetServiceの初期化に失敗しました: $e');
                  // 失敗は致命的ではないので継続
                }
              }
            },
          ),
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // サンプルデータのタイトルを国際化する関数
  String _getLocalizedExampleTitle(String title, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return title;

    switch (title) {
      case '太陽系の惑星':
        return l10n.solarSystemPlanets;
      case '三大栄養素と役割':
        return l10n.threeNutrients;
      case '民主主義の3原則':
        return l10n.democracyPrinciples;
      default:
        return title;
    }
  }

  // サンプルデータの内容を国際化する関数
  String _getLocalizedExampleContent(
      String title, String content, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return content;
    final locale = Localizations.localeOf(context).languageCode;

    // 言語に応じて適切な内容を返す
    if (locale == 'en') {
      switch (title) {
        case '太陽系の惑星':
          return 'Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune';
        case '三大栄養素と役割':
          return 'Proteins: Building blocks for muscles and organs, Carbohydrates: Energy source, Lipids: Temperature regulation and hormone production';
        case '民主主義の3原則':
          return 'Sovereignty of the People, Respect for Fundamental Human Rights, Pacifism';
        default:
          return content;
      }
    }

    return content;
  }

  // サンプルデータの種類を国際化する関数
  String _getLocalizedExampleType(String type, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return type;

    switch (type) {
      case 'ニーモニック':
        return l10n.mnemonic;
      case '関係性':
        return l10n.relationship;
      case '概念':
        return l10n.concept;
      default:
        return type;
    }
  }

  // サンプルデータの技法を国際化する関数
  String _getLocalizedExampleTechnique(
      String title, String technique, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return technique;
    final locale = Localizations.localeOf(context).languageCode;

    // 言語に応じて適切な技法を返す
    if (locale == 'en') {
      switch (title) {
        case '太陽系の惑星':
          return 'Use the acronym "My Very Educated Mother Just Served Us Nachos" where each first letter represents a planet: Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune.';
        case '三大栄養素と役割':
          return 'Associate each nutrient with its function in the body: Proteins → building blocks, Carbohydrates → fuel cells, Lipids → insulation material.';
        case '民主主義の3原則':
          return 'Remember the acronym "SPR" - Sovereignty, People\'s rights, and Renunciation of war.';
        default:
          return technique;
      }
    }

    return technique;
  }

  // カメラオプション表示
  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: Colors.blue.shade600),
              title: Text(AppLocalizations.of(context)!.takePhoto,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _showImageCropOcrWidget(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Colors.green.shade600),
              title: Text(AppLocalizations.of(context)!.selectFromGallery,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _showImageCropOcrWidget(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 画像選択、トリミング、OCR処理を行うウィジェットを表示
  void _showImageCropOcrWidget(ImageSource source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // スワイプで閉じる機能を無効化（トリミング操作と競合しないように）
      enableDrag: false,
      // モーダル外タップでも閉じないように設定（必要に応じてtrueに変更可能）
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ImageCropOcrWidget(
          onOcrCompleted: (text) {
            // Step 1: Widgetが破棄されていないか確認
            if (!mounted) return;

            // Step 2: テキストが空でないか確認
            if (text.isEmpty) return;

            // Step 3: UI応答性を向上させるために非同期処理
            Future.microtask(() {
              // UI更新はメインスレッドで行う
              if (!mounted) return;

              // Step 4: 入力欄にテキストを設定
              _inputController.text = text.trim();

              // Step 5: テキストにフォーカスを当てて編集しやすくする
              _inputFocusNode.requestFocus();

              // Step 6: 成功メッセージを表示
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(AppLocalizations.of(context)!.ocrTextSet),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green.shade600,
                  duration: const Duration(seconds: 4),
                ),
              );
            });
          },
          imageSource: source,
          onClose: () => Navigator.pop(context),
          maxHeight: MediaQuery.of(context).size.height * 0.75,
          // OCR完了後に自動送信を実行する仕組みを追加
          autoSubmit: true,
          onSubmit: () {
            // まずモーダルを閉じてから自動送信処理を行う
            print('自動送信コールバックを実行します');
            Navigator.pop(context); // モーダルを確実に閉じる

            // 少し遅延させてから送信処理を実行
            Future.delayed(Duration(milliseconds: 300), () {
              if (mounted && _inputController.text.isNotEmpty) {
                _handleTextSubmission();
              }
            });
          },
        ),
      ),
    );
  }

  // ドロップダウンメニューで選択できる例文の種類
  List<Map<String, dynamic>> get _exampleTypes {
    // ここで翻訳キーを使用して国際化対応
    final l10n = AppLocalizations.of(context)!;

    return [
      {
        'type': l10n.mnemonicType,
        'title': l10n.solarSystemPlanets,
        'content': l10n.solarSystemPlanetsContent,
        'technique': l10n.solarSystemPlanetsTechnique,
        'color': Colors.amber.shade100,
        'icon': Icons.wb_sunny,
      },
      {
        'type': l10n.relationshipType,
        'title': l10n.macronutrientsAndRoles,
        'content': l10n.macronutrientsContent,
        'technique': l10n.macronutrientsTechnique,
        'color': Colors.green.shade100,
        'icon': Icons.account_tree_outlined,
      },
      {
        'type': l10n.conceptType,
        'title': l10n.democracyPrinciples,
        'content': l10n.democracyPrinciplesContent,
        'technique': l10n.democracyPrinciplesTechnique,
        'color': Colors.purple.shade100,
        'icon': Icons.psychology_outlined,
      }
    ];
  }

  // ホーム（投稿）タブ
  Widget _buildHomeTab() {
    // l10n変数を定義して国際化に使用
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      // SingleChildScrollViewを追加してスクロール可能にする
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー部分
            // AppLocalizationsを使用して多言語対応
            Text(
              l10n.createMemPie,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.memPieDescription,
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 24),

            // 入力エリア（Expandedを取り除き、自由に拡大可能にする）
            _buildPostingWidget(),
            const SizedBox(height: 16),

            // AIモードの切り替え
            _buildAIModeSetting(),
            const SizedBox(height: 24),

            // 投稿例ヘルプ（下部に配置）
            _buildPostingExampleHelp(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // AIモードの切り替えウィジェット
  Widget _buildAIModeSetting() {
    // 国際化対応済み

    // ドロップダウンの展開状態を管理する状態変数
    bool isDropdownOpen = false;

    return StatefulBuilder(
      builder: (context, setState) {
        // 選択されたモードに基づいて色とアイコンを定義
        Color selectedColor;
        IconData selectedIcon;

        switch (_selectedAiMode) {
          case MODE_MULTI_AGENT:
            selectedColor = Colors.purple.shade600;
            selectedIcon = Icons.group_work_outlined;
            break;
          case MODE_THINKING:
            selectedColor = Colors.teal.shade600;
            selectedIcon = Icons.psychology_outlined;
            break;
          default: // MODE_STANDARD
            selectedColor = Colors.blue.shade600;
            selectedIcon = Icons.auto_awesome_outlined;
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // ヘッダー部分（クリックで展開される）
              InkWell(
                onTap: () {
                  setState(() {
                    isDropdownOpen = !isDropdownOpen;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selectedColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          selectedIcon,
                          color: selectedColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.aiGenerationMode,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedAiMode == MODE_STANDARD
                                  ? AppLocalizations.of(context)!.standardMode
                                  : _selectedAiMode == MODE_MULTI_AGENT
                                      ? AppLocalizations.of(context)!
                                          .multiAgentMode
                                      : AppLocalizations.of(context)!
                                          .thinkingMode,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: selectedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isDropdownOpen
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey.shade700,
                      ),
                    ],
                  ),
                ),
              ),

              // ドロップダウンメニュー部分
              AnimatedCrossFade(
                firstChild: Container(height: 0),
                secondChild: Column(
                  children: [
                    const Divider(
                        height: 1, thickness: 1, indent: 20, endIndent: 20),
                    const SizedBox(height: 4),

                    // 標準モード
                    _buildAIModeOption(
                      title: AppLocalizations.of(context)!.standardMode,
                      subtitle:
                          AppLocalizations.of(context)!.standardModeDescription,
                      icon: Icons.auto_awesome_outlined,
                      color: Colors.blue.shade600,
                      isSelected: _selectedAiMode == MODE_STANDARD,
                      onTap: () async {
                        await _saveAiModeSetting(MODE_STANDARD);
                        setState(() {
                          _selectedAiMode = MODE_STANDARD;
                          isDropdownOpen = false;
                        });
                      },
                    ),

                    // マルチエージェントモード
                    _buildAIModeOption(
                      title: AppLocalizations.of(context)!.multiAgentMode,
                      subtitle: AppLocalizations.of(context)!
                          .multiAgentModeDescription,
                      icon: Icons.group_work_outlined,
                      color: Colors.purple.shade600,
                      isSelected: _selectedAiMode == MODE_MULTI_AGENT,
                      onTap: () async {
                        // 無料プランで使用回数が0の場合、選択できないようにする
                        if (!_isSubscriptionLoading &&
                            _subscription != null &&
                            !(_subscription?.isPremium ?? false) &&
                            _getRemainingUses(MODE_MULTI_AGENT) <= 0) {
                          _showSubscriptionLimitDialog(
                              AppLocalizations.of(context)!.multiAgentMode);
                          return;
                        }

                        await _saveAiModeSetting(MODE_MULTI_AGENT);
                        setState(() {
                          _selectedAiMode = MODE_MULTI_AGENT;
                          isDropdownOpen = false;
                        });
                      },
                    ),

                    // 考え方モード
                    _buildAIModeOption(
                      title: AppLocalizations.of(context)!.thinkingMode,
                      subtitle:
                          AppLocalizations.of(context)!.thinkingModeDescription,
                      icon: Icons.psychology_outlined,
                      color: Colors.teal.shade600,
                      isSelected: _selectedAiMode == MODE_THINKING,
                      onTap: () async {
                        // 無料プランで使用回数が0の場合、選択できないようにする
                        if (!_isSubscriptionLoading &&
                            _subscription != null &&
                            !(_subscription?.isPremium ?? false) &&
                            _getRemainingUses(MODE_THINKING) <= 0) {
                          _showSubscriptionLimitDialog(
                              AppLocalizations.of(context)!.thinkingMode);
                          return;
                        }

                        await _saveAiModeSetting(MODE_THINKING);
                        setState(() {
                          _selectedAiMode = MODE_THINKING;
                          isDropdownOpen = false;
                        });
                      },
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
                crossFadeState: isDropdownOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        );
      },
    );
  }

  // AIモードオプションのウィジェット
  Widget _buildAIModeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    String modeKey = '';
    final l10n = AppLocalizations.of(context);
    if (title == l10n?.multiAgentMode) {
      modeKey = MODE_MULTI_AGENT;
    } else if (title == l10n?.thinkingMode) {
      modeKey = MODE_THINKING;
    } else {
      modeKey = MODE_STANDARD;
    }

    // 残り使用回数を表示するか判定
    bool showUsageLimit = !_isSubscriptionLoading &&
        _subscription != null &&
        (modeKey == MODE_MULTI_AGENT || modeKey == MODE_THINKING);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? color : Colors.black87,
                          ),
                        ),
                      ),
                      if (showUsageLimit)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getRemainingUsesText(modeKey),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: (_subscription?.isPremium ?? false) ||
                                      _getRemainingUses(modeKey) > 0
                                  ? Colors.black87
                                  : Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  // 投稿例ヘルプ部分を構築
  Widget _buildPostingExampleHelp() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: _showPostingExamplesPopup,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.postingExamples,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: Colors.blue.shade700),
            ],
          ),
        ),
      ),
    );
  }

  // 使用制限のダイアログを表示
  void _showSubscriptionLimitDialog(String modeName) {
    // 改良されたアップグレードダイアログを表示
    UpgradeDialog.show(
      context: context,
      mode: modeName == 'マルチエージェントモード' ? 'multi_agent' : 'thinking',
      remainingUses: 0,
      totalUses: modeName == 'マルチエージェントモード'
          ? SubscriptionModel.maxMultiAgentModeUsage
          : SubscriptionModel.maxThinkingModeUsage,
    );
  }

  // サブスクリプションの残り使用回数を取得
  int _getRemainingUses(String mode) {
    if (_subscription == null) return 0;

    switch (mode) {
      case MODE_MULTI_AGENT:
        return _subscription!.remainingMultiAgentModeUses;
      case MODE_THINKING:
        return _subscription!.remainingThinkingModeUses;
      default:
        return -1; // 標準モードは制限なし
    }
  }

  // モード別の残り使用回数テキストを取得
  String _getRemainingUsesText(String mode) {
    final remaining = _getRemainingUses(mode);
    final l10n = AppLocalizations.of(context)!;
    if (remaining < 0) {
      return l10n.unlimitedUses; // 無制限
    } else {
      return l10n
          .remainingUses(remaining); // 残り{count}回 - パラメータを持つメッセージは関数として呼び出す
    }
  }

  // 投稿例の詳細を表示するポップアップ
  void _showExamplePostDetail(
    String title,
    String content,
    String type,
    String technique,
    Color color,
    IconData icon,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(color: color),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.blue.shade800, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey.shade600),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                Divider(color: color, height: 24),
                Text(
                  '内容:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    content,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.memoryTechniqueLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            size: 18,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              technique,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(AppLocalizations.of(context)!.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ヒント項目
  Widget TipItem({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.blue.shade600,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.blue.shade900,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  // ユーザー入力を受け付けるウィジェット
  Widget _buildPostingWidget() {
    // l10n変数を定義して国際化に使用
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // テキスト入力フィールド（可変サイズ）
          Container(
            width: double.infinity,
            // 最大高さの制限を解除し、入力内容に応じて自由に拡張
            constraints: const BoxConstraints(
              minHeight: 200,
            ),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade200, width: 1),
            ),
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              maxLines: null,
              minLines: 8,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              textInputAction: TextInputAction.newline,
              enabled: !_isProcessing,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue.shade900,
              ),
              decoration: InputDecoration(
                hintText: l10n.enterContentToMemorize,
                hintStyle: TextStyle(color: Colors.blue.shade300),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
                // 無効化状態のカスタムスタイルを追加
                disabledBorder: InputBorder.none,
                // テキストフィールドの丸みを親コンテナと一致させる
                filled: true,
                fillColor: Colors.transparent,
                // 環境に合わせて調整する
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // アクションボタンエリア
          Row(
            children: [
              // カメラ/画像アップロードボタン
              InkWell(
                onTap: _isProcessing ? null : _showImageSourceOptions,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isProcessing
                        ? Colors.grey.shade200
                        : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 24,
                        color: _isProcessing
                            ? Colors.grey.shade400
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.addImage,
                        style: TextStyle(
                          color: _isProcessing
                              ? Colors.grey.shade400
                              : Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),

              // 送信ボタン
              InkWell(
                onTap: () {
                  if (!_isProcessing &&
                      _inputController.text.trim().isNotEmpty) {
                    _handleTextSubmission();
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isProcessing
                        ? Colors.grey.shade200
                        : _inputController.text.trim().isEmpty
                            ? Colors.grey.shade200
                            : Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow:
                        _isProcessing || _inputController.text.trim().isEmpty
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.blue.shade300.withOpacity(0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.grey),
                          ),
                        )
                      : Row(
                          children: [
                            Text(
                              l10n.send,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _inputController.text.trim().isEmpty
                                    ? Colors.grey.shade400
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.send,
                              size: 20,
                              color: _inputController.text.trim().isEmpty
                                  ? Colors.grey.shade400
                                  : Colors.white,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 投稿例ポップアップを表示
  void _showPostingExamplesPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade200.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.lightbulb_outline,
                            color: Colors.blue.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.postingExamples,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade600),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.blue.shade100, height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._exampleTypes.map((example) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: example['color'],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(example['icon'],
                                        color: Colors.blue.shade800, size: 20),
                                  ),
                                  title: Text(
                                    _getLocalizedExampleTitle(
                                        example['title'], context),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  subtitle: Text(
                                    example['type'],
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700),
                                  ),
                                  onTap: () {
                                    final localizedTitle =
                                        _getLocalizedExampleTitle(
                                            example['title'], context);
                                    final localizedContent =
                                        _getLocalizedExampleContent(
                                            example['title'],
                                            example['content'],
                                            context);
                                    final localizedType =
                                        _getLocalizedExampleType(
                                            example['type'], context);
                                    final localizedTechnique =
                                        _getLocalizedExampleTechnique(
                                            example['title'],
                                            example['technique'],
                                            context);

                                    _showExamplePostDetail(
                                      localizedTitle,
                                      localizedContent,
                                      localizedType,
                                      localizedTechnique,
                                      example['color'],
                                      example['icon'],
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 16.0, bottom: 16.0),
                                  child: Text(
                                    example['content'],
                                    style: const TextStyle(fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_exampleTypes.last != example)
                                  const Divider(height: 8),
                              ],
                            )),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade400,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(AppLocalizations.of(context)!.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // アプリについての情報を提供するモーダルを表示
  void _showLegalInfoModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  AppLocalizations.of(context)!.aboutThisApp,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.help_outline, color: Colors.green.shade600),
                title: Text(AppLocalizations.of(context)!.howToUse),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const HowToUseScreen()),
                  ).then((_) {
                    // 画面から戻ったときにデータを更新
                    _refreshDataAfterScreenReturn();
                  });
                },
              ),
              // デバッグログビューアは削除されました
              ListTile(
                leading: Icon(Icons.description_outlined,
                    color: Colors.blue.shade700),
                title: Text(AppLocalizations.of(context)!.termsOfService),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const TermsOfServiceScreen()),
                  ).then((_) {
                    // 画面から戻ったときにデータを更新
                    _refreshDataAfterScreenReturn();
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined,
                    color: Colors.blue.shade700),
                title: Text(AppLocalizations.of(context)!.privacyPolicy),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PrivacyPolicyScreen()),
                  ).then((_) {
                    // 画面から戻ったときにデータを更新
                    _refreshDataAfterScreenReturn();
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.shopping_bag_outlined,
                    color: Colors.blue.shade700),
                title:
                    Text(AppLocalizations.of(context)!.commercialTransaction),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const CommercialTransactionScreen()),
                  ).then((_) {
                    // 画面から戻ったときにデータを更新
                    _refreshDataAfterScreenReturn();
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PieLogoSmall(),
            const SizedBox(width: 8),
            const Flexible(
              child: AppTitleText(),
            ),
          ],
        ),
        actions: [
          // 非ログイン時に表示するアイコンボタンたち
          Consumer<AuthService>(builder: (context, authService, child) {
            final user = authService.currentUser;
            final bool isAnonymous = user?.isAnonymous ?? true;

            if (user == null || isAnonymous) {
              // 非ログイン時に言語、情報、ヘルプボタンをまとめて表示する
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 言語切り替えボタン
                  Consumer<LanguageProvider>(
                    builder: (context, languageProvider, child) {
                      return IconButton(
                        icon: const Icon(Icons.language, size: 20),
                        color: Colors.blue.shade600,
                        tooltip: l10n.selectLanguage,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          // 言語を循環的に切り替える（日本語→英語→中国語→日本語）
                          Locale newLocale;
                          String message;

                          switch (languageProvider.currentLocale.languageCode) {
                            case 'ja':
                              newLocale = const Locale('en');
                              message = l10n.languageSwitchedEnglish;
                              break;
                            case 'en':
                              newLocale = const Locale('zh');
                              message = l10n.languageSwitchedChinese;
                              break;
                            case 'zh':
                              newLocale = const Locale('ja');
                              message = l10n.languageSwitchedJapanese;
                              break;
                            default:
                              newLocale = const Locale('ja');
                              message = l10n.languageSwitchedJapanese;
                          }

                          languageProvider.changeLocale(newLocale);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  // Aboutボタン
                  IconButton(
                    icon: Icon(Icons.info_outline,
                        color: Colors.blue.shade600, size: 20),
                    tooltip: l10n.aboutApp,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _showLegalInfoModal(context),
                  ),

                  // ヘルプボタン
                  IconButton(
                    icon: Icon(Icons.help_outline,
                        color: Colors.blue.shade600, size: 20),
                    tooltip: l10n.howToUse,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const HowToUseScreen()),
                      ).then((_) {
                        // 画面から戻ったときにデータを更新
                        _refreshDataAfterScreenReturn();
                      });
                    },
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          }),

          // プロフィールボタン
          Consumer<AuthService>(
            builder: (context, authService, child) {
              final user = authService.currentUser;
              final bool isAnonymous = user?.isAnonymous ?? true;

              // 未ログインまたは匿名ユーザーのときはプロフィールボタンを表示しない
              if (user == null || isAnonymous) {
                return const SizedBox.shrink();
              } else {
                // 通常ユーザー時のみプロフィールボタンを表示
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ProfileAvatarWidget(
                    size: 36,
                    showPremiumIndicator: _subscription?.isPremium == true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ProfileScreen()),
                    ).then((_) {
                      // 画面から戻ったときにデータを更新
                      _refreshDataAfterScreenReturn();
                    }),
                    showBorder: true,
                    borderColor: Colors.white,
                    borderWidth: 1.5,
                  ),
                );
              }
            },
          ),
          Consumer<AuthService>(
            builder: (context, authService, child) {
              // 認証状態に基づいてボタンを表示
              final user = authService.currentUser;
              final bool isAnonymous = user?.isAnonymous ?? false;

              if (user == null) {
                // 非認証状態（通常あり得ない）
                return TextButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(AppLocalizations.of(context)!.login),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  },
                );
              } else if (isAnonymous) {
                // 匿名認証状態 - ログインボタンを表示
                return TextButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(AppLocalizations.of(context)!.login),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                  ),
                  onPressed: () async {
                    // まず匿名ユーザーをログアウト
                    final authService =
                        Provider.of<AuthService>(context, listen: false);

                    // リスナーを事前にクリーンアップ
                    final cardSetService =
                        Provider.of<CardSetService>(context, listen: false);
                    final memoryService =
                        Provider.of<MemoryService>(context, listen: false);

                    try {
                      cardSetService.cleanupAllListeners();
                      memoryService.cleanupAllListeners();

                      print('ログイン画面遷移前にログアウトします');
                      await authService.signOut();
                      print('ログアウト完了');
                    } catch (e) {
                      print('ログアウト時のエラー: $e');
                      // ログアウトに失敗してもログイン画面には遷移する
                    }

                    // ログイン画面に遷移
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );

                    // ログイン画面から戻ってきた後はUIを更新する
                    setState(() {});

                    // 認証状態を確認してユーザーの状態を更新
                    if (Provider.of<AuthService>(context, listen: false)
                            .isAuthenticated() &&
                        !Provider.of<AuthService>(context, listen: false)
                            .currentUser!
                            .isAnonymous) {
                      print('ログイン後に正規ユーザーとして再表示します');

                      // データリロードを行い、表示を更新
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        // フレームの描画後にデータをリロード
                        _initializeServices();
                      });
                    }
                  },
                );
              } else {
                // 通常ユーザー認証状態ではアップグレードボタンを表示
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFf5a742), // 明るいオレンジ
                          Color(0xFFf1c761), // 明るい黄色
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.2),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: !_isSubscriptionLoading &&
                              _subscription != null &&
                              !(_subscription?.isPremium ?? false)
                          ? InkWell(
                              borderRadius: BorderRadius.circular(16),
                              splashColor: Colors.orange.shade200,
                              onTap: () {
                                // サブスク情報画面に遷移
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const SubscriptionInfoScreen()),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                child: Text(
                                  AppLocalizations.of(context)!.upgradeButton,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(
                                        offset: const Offset(0.5, 0.5),
                                        blurRadius: 1.0,
                                        color: Colors.brown.shade700
                                            .withOpacity(0.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(), // プレミアム（有料）ユーザーには表示しない
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F7FA), // 明るい水色
              Color(0xFFFFF9C4), // 明るい黄色
            ],
          ),
        ),
        child: SafeArea(
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              _buildHomeTab(),
              const CardSetsScreen(),
              const LibraryScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, l10n.homeNavLabel),
                _buildNavItem(1, Icons.folder_copy,
                    AppLocalizations.of(context)!.myCardSets),
                _buildNavItem(
                    2, Icons.library_books_rounded, l10n.libraryNavLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ナビゲーションアイテムウィジェット
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;

    return InkWell(
      onTap: () {
        // タブが切り替えられた場合、データを再読込
        if (_selectedTabIndex != index) {
          setState(() {
            _selectedTabIndex = index;
          });

          // 必要なデータをタブ遷移時に更新
          _refreshDataOnTabChange(index);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.shade100 : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.blue.shade600 : Colors.grey.shade400,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.blue.shade600 : Colors.grey.shade400,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
