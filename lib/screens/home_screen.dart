import 'dart:async';
import 'package:anki_pai/screens/subscription_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onTextChanged);
    // AIモードの設定を読み込む
    _loadAiModeSetting();
    // データの初期読み込み
    _initializeServices();
    // サブスクリプション情報を取得
    _loadSubscriptionInfo();

    // 動画広告を事前にロード
    if (!kIsWeb) {
      adService.loadInterstitialAd();
      adService.loadRewardedAd();
    }
  }

  // サブスクリプション情報を読み込む
  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isSubscriptionLoading = true;
    });

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);

      // 強制的にキャッシュをクリアして最新情報を取得
      // 特にサブスク管理が重要なため、毎回クリアして更新する
      print('ホーム画面: サブスク情報を再取得中...');
      subscriptionService.clearCache();

      // サブスクリプション情報を更新
      final subscription = await subscriptionService.refreshSubscription();
      print(
          'ホーム画面: 更新されたサブスク情報 - タイプ: ${subscription.type}, プレミアム: ${subscription.isPremium}');

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

      // エラー発生時のバックアップとして、単純取得を試行
      try {
        final subscriptionService =
            Provider.of<SubscriptionService>(context, listen: false);
        final subscription = await subscriptionService.getUserSubscription();

        if (mounted) {
          setState(() {
            _subscription = subscription;
          });
        }
      } catch (secondError) {
        print('バックアップ取得も失敗: $secondError');
      }
    }
  }

  // サービスを初期化し、データの読み込みを行う
  Future<void> _initializeServices() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.isAuthenticated()) {
        // カードセット・メモリーサービスデータのリロード
        final cardSetService =
            Provider.of<CardSetService>(context, listen: false);
        final memoryService =
            Provider.of<MemoryService>(context, listen: false);

        // 各サービスの初期化を行い、データを再読み込み
        await cardSetService.initialize();

        // 暗記アイテムのリロード
        try {
          // ここではメモリーサービスの確実な再読み込みを行う
          await memoryService.getRecentPublicTechnique(); // 最新の公開テクニックを読み込む
          await memoryService.getUserMemoryTechniques(); // ユーザーのテクニックを読み込む
          print('暗記アイテムの再読み込み成功');
        } catch (mError) {
          print('暗記アイテムの再読み込みエラー: $mError');
        }
      }
    } catch (e) {
      print('データ初期化エラー: $e');
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
          _showSubscriptionLimitDialog(
              _selectedAiMode == MODE_MULTI_AGENT ? 'マルチエージェントモード' : '考え方モード');
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
        'message': '考え方モードで処理します'
      };
      isMultipleItems = false;
      itemCount = 1;
    } else if (_useMultiAgentMode) {
      // マルチエージェントモードの場合は単一項目として処理
      print('マルチエージェントモードが有効なため、複数項目検出をスキップします');
      result = {
        'isMultipleItems': false,
        'itemCount': 1,
        'message': 'マルチエージェントモードで処理します'
      };
      isMultipleItems = false;
      itemCount = 1;
    } else {
      LoadingAnimationDialog.show(
        context,
        message: '暗記法を生成中...',
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
          ? '考え方を生成中...'
          : (_useMultiAgentMode
              ? 'AIチームが暗記法を考えています...'
              : (isMultipleItems ? '複数の暗記法を生成中...' : '暗記法を生成中...')),
      animationType: AnimationType.memory,
      // 考え方モードでは項目数を表示しない
      itemCount:
          (_useThinkingMode) ? null : (isMultipleItems ? itemCount : null),
      showItemCount: !_useThinkingMode && isMultipleItems,
    );

    // モバイルの場合は3秒後に動画広告を表示
    if (!kIsWeb) {
      adService.loadRewardedAd();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          adService.showRewardedAd();
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
          _showSubscriptionLimitDialog('考え方モード');
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
          // 実際のテキスト内容を解析して個別の項目に分割
          final List<String> lines = text.split('\n');
          final List<Map<String, dynamic>> actualItems = [];

          // 各行を個別の項目として処理
          for (int i = 0; i < lines.length && i < itemCount; i++) {
            final String line = lines[i].trim();
            if (line.isNotEmpty) {
              actualItems.add({
                'content': line,
                'type': 'text',
              });
            }
          }

          // 実際の項目数に合わせてitemCountを更新
          final int actualItemCount = actualItems.length;
          print('実際の項目数: $actualItemCount');

          final detectionInfo = <String, dynamic>{
            'itemCount': actualItemCount,
            'message': '複数項目が検出されました（標準検出）',
            'rawContent': text, // 生データも渡す
            'items': actualItems,
          };

          print('複数項目を処理します: ${actualItems.length}件');
          techniques = await memoryService.suggestMemoryTechniques(
            text,
            multipleItemsDetection: detectionInfo,
            itemCount: actualItems.length,
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
            name: '標準学習法',
            description: 'この内容は反復学習で覚えることが効果的です。',
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
        errorMessage = 'データベースのアクセス権限がありません。再度ログインしてください。';
      } else if (errorMessage.contains('ログイン')) {
        errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('追加に失敗しました: $errorMessage'),
          backgroundColor: Colors.red.shade400,
          action: SnackBarAction(
            label: 'ログイン',
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
              title: const Text('カメラで撮影',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _showImageCropOcrWidget(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Colors.green.shade600),
              title: const Text('ギャラリーから選択',
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
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child:
                            Text('OCRテキストを入力欄に設定しました。内容を確認して「送信」ボタンを押してください。'),
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
        ),
      ),
    );
  }

  // ドロップダウンメニューで選択できる例文の種類
  final List<Map<String, dynamic>> _exampleTypes = [
    {
      'type': 'ニーモニック',
      'title': '太陽系の惑星',
      'content': '水 mercury、金 Venus、地球、火星、木星、土星、天王星、海王星',
      'technique': '「水・金・地・火・木・土・天・海」の頭文字をつなげた「みずきんちかもくどってんかい」で覚えよう!。',
      'color': Colors.amber.shade100,
      'icon': Icons.wb_sunny,
    },
    {
      'type': '関係性',
      'title': '三大栄養素と役割',
      'content': 'タンパク質：筋肉や臓器の材料、炭水化物：エネルギー源、脂質：体温維持やホルモン材料',
      'technique':
          '各栄養素の役割を体の部位と結びつけて覚えよう!。タンパク質→筋肉、炭水化物→エネルギー電池、脂質→断熱材のイメージです。',
      'color': Colors.green.shade100,
      'icon': Icons.account_tree_outlined,
    },
    {
      'type': '概念',
      'title': '民主主義の3原則',
      'content': '国民主権、基本的人権の尊重、平和主義',
      'technique': '「主・人・平」の3文字で覚えよう!。',
      'color': Colors.purple.shade100,
      'icon': Icons.psychology_outlined,
    }
  ];

  // ホーム（投稿）タブ
  Widget _buildHomeTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      // SingleChildScrollViewを追加してスクロール可能にする
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー部分
            Text(
              '暗記パイを作ろう！',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'テキストや画像を入力すると、AIが最適な暗記法を提案するよ。',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 24),

            // 入力エリア（Expandedを取り除き、自由に拡大可能にする）
            _buildInputArea(),
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
    // ドロップダウンの展開状態を管理する状態変数
    bool isDropdownOpen = false;

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

    return StatefulBuilder(
      builder: (context, setState) {
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
                              'AI生成モード',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedAiMode == MODE_STANDARD
                                  ? '標準モード'
                                  : _selectedAiMode == MODE_MULTI_AGENT
                                      ? 'マルチエージェントモード'
                                      : '考え方モード',
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
                      title: '標準モード',
                      subtitle: '透明感のある暗記法を生成します',
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
                      title: 'マルチエージェントモード',
                      subtitle: '複数のAIが最適な暗記法を導き出します',
                      icon: Icons.group_work_outlined,
                      color: Colors.purple.shade600,
                      isSelected: _selectedAiMode == MODE_MULTI_AGENT,
                      onTap: () async {
                        // 無料プランで使用回数が0の場合、選択できないようにする
                        if (!_isSubscriptionLoading &&
                            _subscription != null &&
                            !(_subscription?.isPremium ?? false) &&
                            _getRemainingUses(MODE_MULTI_AGENT) <= 0) {
                          _showSubscriptionLimitDialog('マルチエージェントモード');
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
                      title: '考え方モード',
                      subtitle: '内容の本質や原理を捕えた簡潔な説明を生成',
                      icon: Icons.psychology_outlined,
                      color: Colors.teal.shade600,
                      isSelected: _selectedAiMode == MODE_THINKING,
                      onTap: () async {
                        // 無料プランで使用回数が0の場合、選択できないようにする
                        if (!_isSubscriptionLoading &&
                            _subscription != null &&
                            !(_subscription?.isPremium ?? false) &&
                            _getRemainingUses(MODE_THINKING) <= 0) {
                          _showSubscriptionLimitDialog('考え方モード');
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
    if (title == 'マルチエージェントモード') {
      modeKey = MODE_MULTI_AGENT;
    } else if (title == '考え方モード') {
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
                  '投稿例を見る',
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
    return remaining < 0 ? '無制限' : '残り$remaining回';
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
                  '暗記法:',
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
                    child: const Text('閉じる'),
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

  // 入力エリア
  Widget _buildInputArea() {
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
                hintText: '覚えたい内容を入力...',
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
                        '画像追加',
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
                              '送信',
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
                          '投稿例',
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
                                    example['title'],
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
                                    _showExamplePostDetail(
                                      example['title'],
                                      example['content'],
                                      example['type'],
                                      example['technique'],
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
                      child: const Text('閉じる'),
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
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'このアプリについて',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.help_outline, color: Colors.green.shade600),
                title: const Text('使い方'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const HowToUseScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.description_outlined,
                    color: Colors.blue.shade700),
                title: const Text('利用規約'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const TermsOfServiceScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined,
                    color: Colors.blue.shade700),
                title: const Text('プライバシーポリシー'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PrivacyPolicyScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.shopping_bag_outlined,
                    color: Colors.blue.shade700),
                title: const Text('特定商取引法に基づく表記'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const CommercialTransactionScreen()),
                  );
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
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            PieLogoSmall(),
            SizedBox(width: 8),
            AppTitleText(),
          ],
        ),
        actions: [
          Consumer<AuthService>(builder: (context, authService, child) {
            final user = authService.currentUser;
            final bool isAnonymous = user?.isAnonymous ?? true;
            if (user == null || isAnonymous) {
              return IconButton(
                icon: Icon(Icons.info_outline, color: Colors.blue.shade600),
                tooltip: 'このアプリについて',
                onPressed: () => _showLegalInfoModal(context),
              );
            }
            return const SizedBox.shrink();
          }),
          IconButton(
            icon: Icon(Icons.help_outline, color: Colors.blue.shade600),
            tooltip: '使い方',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HowToUseScreen()),
              );
            },
          ),
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
                    ),
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
                  label: const Text('ログイン'),
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
                  label: const Text('ログイン'),
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
                                  'パイ食べ放題',
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
                _buildNavItem(0, Icons.home_rounded, 'ホーム'),
                _buildNavItem(1, Icons.folder_copy, 'カードセット'),
                _buildNavItem(2, Icons.library_books_rounded, 'ライブラリ'),
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
        setState(() {
          _selectedTabIndex = index;
        });
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
