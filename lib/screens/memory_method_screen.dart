import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/ai_service_interface.dart';
import '../services/card_set_service.dart';
import '../models/card_set.dart';
import '../services/flash_card_service.dart';
import '../services/gemini_service.dart';
import '../models/memory_item.dart';
import '../models/memory_technique.dart';
import '../models/ranked_memory_technique.dart';
import '../services/memory_service.dart';
import 'card_set_detail_screen.dart';
import '../widgets/loading_animation_dialog.dart';
import '../services/ad_service.dart';
// Removed unused import: '../services/subscription_service.dart';
// Removed unused import: '../models/subscription_model.dart';

// AnimationTypeを明示的にインポート

import 'package:get_it/get_it.dart';

// 複数項目検出時のアクション選択用enum
enum MultipleItemsAction {
  cancel, // キャンセル
  generateSingle, // 一つの覚え方として生成
  generateSeparate // 個別に覚え方を生成
}

class MemoryMethodScreen extends StatefulWidget {
  final MemoryItem memoryItem;
  final bool isFromPublishedLibrary;
  final bool useMultiAgentMode;
  final bool useThinkingMode;

  const MemoryMethodScreen({
    super.key,
    required this.memoryItem,
    this.isFromPublishedLibrary = false,
    this.useMultiAgentMode = false,
    this.useThinkingMode = false,
  });

  @override
  _MemoryMethodScreenState createState() => _MemoryMethodScreenState();
}

class _MemoryMethodScreenState extends State<MemoryMethodScreen> {
  // サービス
  final MemoryService memoryService = GetIt.instance<MemoryService>();
  final AuthService authService = GetIt.instance<AuthService>();
  final AIServiceInterface aiService = GetIt.instance<GeminiService>();
  final AdService adService = GetIt.instance<AdService>();

  // メモリーアイテム関連のプロパティ
  late MemoryItem _memoryItem;
  late bool _isFromPublishedLibrary;
  List<MemoryTechnique> _similarTechniques = [];
  List<MemoryTechnique> _previousTechniques = [];
  RankedMemoryTechnique? _rankedTechniques;
  bool _isPublicTechnique = false;
  bool _isUnpublishing = false;
  bool _isLoading = true;
  bool _isInitialAdShown = false; // 初回広告表示フラグ
  late PageController pageController;
  final TextEditingController _explanationController = TextEditingController();
  Timer? _debounceTimer;

  // 広告関連
  bool _isBannerAdLoaded = false;

  // OCRと複数項目関連
  bool _initialPageJumpDone = false; // ページ初期化ジャンプ完了フラグ
  bool hasMultipleItems = false;

  // AI関連設定
  late bool _useMultiAgentMode;
  late bool _useThinkingMode;

  // 考え方モード関連
  String? _thinkingModeExplanation;
  bool _isLoadingThinkingMode = false;

  // 説明入力関連
  bool _showExplanationInput = false;
  String? _aiFeedback;
  bool _isLoadingFeedback = false;

  // 表示状態管理
  bool _hideMemoryTips = false;
  bool _loadingNewTechnique = false;
  bool _loadingNextTechnique = false;
  bool _isInputDropdownExpanded = false; // 入力を見るドロップダウンの展開状態

  // AIフィードバック取得
  Future<void> _getAIFeedback() async {
    final text = _explanationController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('説明を入力してください')),
      );
      return;
    }

    // キーボードを閉じる
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoadingFeedback = true;
      // フィードバックを初期化
      _aiFeedback = null;
    });

    try {
      // 暗記内容をAIに渡す
      final contentTitle = _memoryItem.title;
      final contentText = _memoryItem.content;

      final feedback = await aiService.getFeedback(
        _explanationController.text,
        contentTitle: contentTitle,
        contentText: contentText,
      );

      if (mounted) {
        setState(() {
          _aiFeedback = feedback;
          _isLoadingFeedback = false;
        });
      }
    } catch (e) {
      print('フィードバック取得エラー: $e');
      if (mounted) {
        setState(() {
          _aiFeedback = 'フィードバックの取得中にエラーが発生しました。再度お試しください。';
          _isLoadingFeedback = false;
        });
      }
    }
  }

  // 考え方モードの説明を取得し、保存する
  Future<void> _fetchThinkingModeExplanation() async {
    if (!_useThinkingMode) return;

    setState(() {
      _isLoadingThinkingMode = true;
      _thinkingModeExplanation = null;
    });

    try {
      final content = _memoryItem.content;
      final title = _memoryItem.title;

      // AIサービスから考え方モードの説明を取得
      final explanation = await aiService.generateThinkingModeExplanation(
        content: content,
        title: title,
      );

      // 説明文が「〜と考えよう」形式になっているか確認
      String formattedExplanation = explanation;
      if (!formattedExplanation.contains('と考えよう') &&
          !formattedExplanation.contains('と覚えよう')) {
        // 末尾が「。」で終わっていれば削除
        if (formattedExplanation.endsWith('。')) {
          formattedExplanation = formattedExplanation.substring(
              0, formattedExplanation.length - 1);
        }
        // 「〜と考えよう」形式に変換
        formattedExplanation = '$formattedExplanation と考えよう';
      }

      // 生成された考え方モードの説明をMemoryTechniqueオブジェクトに変換
      final thinkingModeTechnique = MemoryTechnique(
        name: '考え方: ${_memoryItem.title}',
        description: formattedExplanation,
        type: 'thinking', // 考え方モードを示す特殊なタイプ
        tags: ['thinking', '考え方'],
        contentKeywords: [_memoryItem.title],
        isPublic: false, // デフォルトでは非公開
        itemContent: _memoryItem.content, // 元の投稿内容を保存
        // 考え方モード用のフラッシュカードを追加
        // 投稿内容を質問、考え方の説明を回答として設定
        flashcards: [
          Flashcard(
            question: _memoryItem.content,
            answer: formattedExplanation,
          ),
        ],
      );

      // 生成された考え方モードの説明をメモリーアイテムに関連付ける
      _memoryItem.memoryTechniques.add(thinkingModeTechnique);

      if (mounted) {
        setState(() {
          _thinkingModeExplanation = formattedExplanation;
          _isLoadingThinkingMode = false;
        });
      }
    } catch (e) {
      print('考え方モードの説明取得エラー: $e');
      if (mounted) {
        setState(() {
          _thinkingModeExplanation = '考え方モードの説明を取得できませんでした。後で再度お試しください。';
          _isLoadingThinkingMode = false;
        });
      }
    }
  }

  // 考え方モードのコンテンツ全体を構築する
  Widget _buildThinkingModeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 投稿内容の表示
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー部分
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.subject,
                          size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        '投稿内容',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 投稿内容本文
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildMathContent(_memoryItem.content),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 考え方モードの説明を表示
        _buildThinkingModeExplanationSection(),

        // const SizedBox(height: 16),

        // // フラッシュカード作成ボタン
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 16),
        //   child: ElevatedButton.icon(
        //     onPressed: _createFlashcardsFromThinkingMode,
        //     icon: const Icon(Icons.flash_on),
        //     label: const Text('フラッシュカード作成'),
        //     style: ElevatedButton.styleFrom(
        //       backgroundColor: Colors.teal.shade600,
        //       foregroundColor: Colors.white,
        //       minimumSize: const Size(double.infinity, 50),
        //       shape: RoundedRectangleBorder(
        //         borderRadius: BorderRadius.circular(12),
        //       ),
        //     ),
        //   ),
        // ),
      ],
    );
  }

  // TeX数式を含むテキストを正しく表示するメソッド
  Widget _buildMathContent(String content) {
    // 画面サイズに基づいてフォントサイズを調整
    final double screenWidth = MediaQuery.of(context).size.width;
    final double fontSize =
        screenWidth < 360 ? 16.0 : 18.0; // 小さい画面ではフォントサイズを小さく

    // 数式と通常テキストを分離する正規表現
    // $...$と$$...$$の両方をサポート
    final RegExp displayMathRegExp = RegExp(r'\$\$(.*?)\$\$', dotAll: true);

    // 分割用のリスト
    List<Widget> contentWidgets = [];

    // 最初に、ディスプレイモードの数式を处理
    List<RegExpMatch> displayMatches =
        displayMathRegExp.allMatches(content).toList();

    int lastEnd = 0;
    for (var match in displayMatches) {
      // 数式の前のテキスト
      if (match.start > lastEnd) {
        String textBefore = content.substring(lastEnd, match.start);
        contentWidgets.add(_processInlineMath(textBefore, fontSize));
      }

      // ディスプレイモードの数式
      String mathText = match.group(1)!;
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0), // 上下のパディングを減らす
          child: Center(
            child: _renderMathWithErrorHandling(
              mathText,
              fontSize: fontSize,
              isDisplay: true,
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    // 残りのテキストを処理
    if (lastEnd < content.length) {
      String remainingText = content.substring(lastEnd);
      contentWidgets.add(_processInlineMath(remainingText));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentWidgets,
    );
  }

  // 入力を見るドロップダウンウィジェットを構築
  Widget _buildInputDropdown() {
    return Column(
      children: [
        // ドロップダウンボタン
        InkWell(
          onTap: () {
            setState(() {
              _isInputDropdownExpanded = !_isInputDropdownExpanded;
            });
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: _isInputDropdownExpanded
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    )
                  : BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '入力を見る',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _isInputDropdownExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ),

        // ドロップダウンの内容
        if (_isInputDropdownExpanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _buildMathContent(_memoryItem.content),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // LaTeX数式をエラーハンドリング付きでレンダリングするヘルパーメソッド
  Widget _renderMathWithErrorHandling(String mathText,
      {double fontSize = 18.0, bool isDisplay = false}) {
    try {
      return Math.tex(
        mathText,
        textStyle: TextStyle(fontSize: fontSize),
        mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      );
    } catch (e) {
      // LaTeX表示エラーが発生した場合、コードとエラーメッセージを表示
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '`$mathText`',
              style: TextStyle(
                fontSize: fontSize - 2,
                fontFamily: 'monospace',
                color: Colors.red.shade800,
              ),
            ),
            Text(
              '（表示エラー）',
              style: TextStyle(
                fontSize: fontSize - 4,
                fontStyle: FontStyle.italic,
                color: Colors.red.shade800,
              ),
            ),
          ],
        ),
      );
    }
  }

  // インライン数式を処理するヘルパーメソッド
  Widget _processInlineMath(String text, [double fontSize = 18.0]) {
    final RegExp inlineMathRegExp = RegExp(r'\$(.*?)\$', dotAll: true);
    List<InlineSpan> spans = [];

    int lastEnd = 0;
    for (var match in inlineMathRegExp.allMatches(text)) {
      // 数式の前の通常テキスト
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(
              fontSize: fontSize, height: 1.4, color: Colors.grey.shade900),
        ));
      }

      // インライン数式
      String mathText = match.group(1)!;
      try {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _renderMathWithErrorHandling(mathText,
              fontSize: fontSize, isDisplay: false),
        ));
      } catch (e) {
        // 万が一のエラー発生時に別の方法でフォールバック
        spans.add(TextSpan(
          text: '$mathText（表示エラー）',
          style: TextStyle(
            fontSize: fontSize - 2,
            color: Colors.red.shade800,
            fontStyle: FontStyle.italic,
          ),
        ));
      }

      lastEnd = match.end;
    }

    // 残りのテキスト
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(
            fontSize: fontSize, height: 1.5, color: Colors.grey.shade900),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  // 考え方モードの説明を表示するセクション
  Widget _buildThinkingModeExplanationSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text(
                '考え方モード',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingThinkingMode)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    '考え方を生成中...',
                    style: TextStyle(color: Colors.purple.shade700),
                  ),
                ],
              ),
            )
          else if (_thinkingModeExplanation != null)
            // 数式をサポートする表示に変更、スクロール可能に
            Container(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * 0.3, // 画面の30%に高さ制限を下げる
              ),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // 常にスクロールを有効に
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0), // 下部に余白を追加
                  child: _buildMathContent(_thinkingModeExplanation!),
                ),
              ),
            )
          else
            const Text('考え方の生成に失敗しました。'),
          const SizedBox(height: 8),
          // 再生成ボタン
          if (!_isLoadingThinkingMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('再生成'),
                onPressed: _fetchThinkingModeExplanation,
              ),
            ),
        ],
      ),
    );
  }

  // デバウンス付きのフィードバック取得
  void _debouncedGetFeedback(String text) {
    // 自動送信は行わず、テキストを保持するだけ
  }

  // SharedPreferencesからマルチエージェントモードの設定を読み込む
  Future<void> _loadMultiAgentModeSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useMultiAgentMode = prefs.getBool('useMultiAgentMode');

      // nullの場合はデフォルト値を使用
      if (useMultiAgentMode != null) {
        setState(() {
          _useMultiAgentMode = useMultiAgentMode;
        });
      }
    } catch (e) {
      // エラーが発生してもデフォルト値を使用して続行
    }
  }

  // AIに説明するテキストを設定するヘルパーメソッド
  void _setExplanationText() {
    // 暗記法がある場合、「○は」の部分を自動入力
    if (_memoryItem.memoryTechniques.isNotEmpty) {
      final technique = _memoryItem.memoryTechniques.first;

      // 暗記法名を取得
      String subjectText = technique.name;

      // 暗記法に含まれるキーワードや内容から適切な主語を抽出
      if (technique.contentKeywords.isNotEmpty) {
        // キーワードがあれば最初のキーワードを使用
        subjectText = technique.contentKeywords.first;
      } else if (technique.itemContent.isNotEmpty) {
        // 項目内容があればそれを使用
        subjectText = technique.itemContent;
      }

      // 長すぎる場合は適切な長さに切り詰める
      if (subjectText.length > 30) {
        subjectText = '${subjectText.substring(0, 27)}...';
      }

      // 「○は」のフォーマットで設定
      _explanationController.text = '$subjectTextは';
    } else {
      // 暗記法がない場合は空にする
      _explanationController.text = '';
    }

    // ウィジェットプロパティからAIモード設定を取得
    _useMultiAgentMode = widget.useMultiAgentMode;
    _useThinkingMode = widget.useThinkingMode;

    // ページコントローラーの初期化
    pageController = PageController(viewportFraction: 0.95);
    _initialPageJumpDone = false; // 新しいコントローラー作成時にフラグをリセット

    // デバッグログ追加
    print(
        'メモリーメソッド画面のisFromPublishedLibrary: ${widget.isFromPublishedLibrary}');
    print(
        '受け取ったメモリーアイテム: ID=${_memoryItem.id}, 暗記法数=${_memoryItem.memoryTechniques.length}');
    print(
        'AIモード設定 - マルチエージェント: $_useMultiAgentMode, 考え方モード: $_useThinkingMode');

    if (_memoryItem.memoryTechniques.isNotEmpty) {
      // 暗記法がthinkingタイプの場合は考え方モードとして表示
      final firstTechnique = _memoryItem.memoryTechniques.first;
      print('暗記法の内容: ${firstTechnique.name}, タイプ: ${firstTechnique.type}');

      // 考え方タイプの暗記法かチェック - 'thinking'タイプまたは説明に「考え方モード」が含まれる場合
      bool isThinkingMode = firstTechnique.type == 'thinking' ||
          firstTechnique.name.contains('考え方') ||
          firstTechnique.description.contains('考え方モード');

      if (isThinkingMode) {
        print('考え方モードの暗記法を検出しました: ${firstTechnique.name}');
        if (firstTechnique.type != 'thinking') {
          print('暗記法のタイプは「${firstTechnique.type}」ですが、考え方モードとして扱います');
        }

        setState(() {
          _useThinkingMode = true;
          _thinkingModeExplanation = firstTechnique.description;

          // ライブラリから開いた場合、暗記法のitemContentがあればメモリーアイテムを更新
          if (widget.isFromPublishedLibrary) {
            // itemContentが空でない場合はその値を使用、空の場合は現在のcontentをそのまま使用
            String contentToUse = firstTechnique.itemContent.isNotEmpty
                ? firstTechnique.itemContent
                : _memoryItem.content;

            print('ライブラリからの表示: コンテンツを更新します');
            print('使用するコンテンツ: $contentToUse');

            // MemoryItemのcontentがfinalなので新しいインスタンスを作成
            _memoryItem = MemoryItem(
              id: _memoryItem.id,
              title: _memoryItem.title,
              content: contentToUse,
              contentType: _memoryItem.contentType,
              imageUrl: _memoryItem.imageUrl,
              mastery: _memoryItem.mastery,
              createdAt: _memoryItem.createdAt,
              lastStudiedAt: _memoryItem.lastStudiedAt,
              memoryTechniques: _memoryItem.memoryTechniques,
            );
          }
        });
        print('考え方モードの暗記法を検出しました - 考え方モードで表示します');
      }

      // AIに説明するテキストを初期化
      _setExplanationText();

      // 考え方モードが有効な場合、説明を取得
      if (_useThinkingMode) {
        _fetchThinkingModeExplanation();
      }
    } else {
      print('警告: 暗記法がありません');
    }

    // SharedPreferencesからマルチエージェントモードの設定を読み込む
    _loadMultiAgentModeSetting();

    // バナー広告をロード
    _loadBannerAd();

    setState(() {
      _isLoading = true;
    });

    // 暗記法がまだ生成されていない場合は自動的に取得
    if (_memoryItem.memoryTechniques.isEmpty) {
      print('暗記法がありません。追加で生成します。');
      // マルチエージェントモードに応じて適切なメソッドを呼び出す
      if (_useMultiAgentMode) {
        _fetchRankedMemoryTechniques();
      } else {
        _fetchMemoryTechniques();
      }
    } else {
      // 暗記法がすでにある場合は直接ロード完了
      setState(() {
        _isLoading = false;
        _initialPageJumpDone = false; // 画面更新時にフラグをリセット
      });
    }

    // 類似コンテンツの暗記法を取得
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSimilarTechniques();
    });
  }

  // バナー広告をロード
  Future<void> _loadBannerAd() async {
    if (!mounted) return;

    try {
      // 広告表示の準備が整うまで遅延
      await Future.delayed(const Duration(seconds: 3));

      final banner = await adService.loadBannerAd();
      if (banner != null && mounted) {
        setState(() {
          _isBannerAdLoaded = true;
        });
      }
    } catch (e) {
      print('バナー広告のロード中にエラーが発生しました: $e');
    }
  }

  // 暗記法を取得する
  // 暗記法再生成のロック用変数
  static bool _isRegenerationLocked = false;
  static DateTime? _lastRegenerationTime;

  Future<void> _fetchMemoryTechniques() async {
    // 既にロード中の場合はスキップ
    if (_loadingNewTechnique) {
      print('既に暗記法生成中のため、リクエストをスキップします');
      return;
    }

    // ロックされている場合はスキップ (暗記法再生成の連続呼び出し防止)
    if (_isRegenerationLocked) {
      print('暗記法再生成が既に実行中のため、リクエストをスキップします');
      return;
    }

    // 前回の再生成からの経過時間をチェック (1秒以内の再生成をブロック)
    if (_lastRegenerationTime != null) {
      final timeSinceLastRegeneration =
          DateTime.now().difference(_lastRegenerationTime!);
      if (timeSinceLastRegeneration.inMilliseconds < 1000) {
        print(
            '短時間での再生成リクエスト (${timeSinceLastRegeneration.inMilliseconds}ms) をブロックしました');
        return;
      }
    }

    // ロック開始
    _isRegenerationLocked = true;
    _lastRegenerationTime = DateTime.now();

    print('暗記法の再生成を開始します: ${_memoryItem.content}');

    setState(() {
      _loadingNewTechnique = true;
    });

    // モバイルの場合は広告のロードのみ実行
    if (!kIsWeb) {
      adService.loadRewardedAd();
    }

    try {
      if (_useMultiAgentMode) {
        // マルチエージェント方式の場合はランク付け暗記法を取得
        await _fetchRankedMemoryTechniques();
      } else if (_useThinkingMode) {
        // 考え方モードが有効な場合は複数項目検出をスキップ
        print('考え方モードが有効なため、単一項目として処理します');

        // 考え方モードで暗記法生成
        var newTechniques =
            await memoryService.suggestMemoryTechniquesWithHistory(
                _memoryItem.content, _previousTechniques,
                isThinkingMode: true, isMultiAgentMode: false);

        print('考え方モード: ${newTechniques.length}件の暗記法を生成しました');

        // 既存の暗記法をクリア
        while (_memoryItem.memoryTechniques.isNotEmpty) {
          _memoryItem.memoryTechniques.removeLast();
        }

        // 新しい暗記法を追加
        for (var technique in newTechniques) {
          _memoryItem.memoryTechniques.add(technique);
        }

        // UI状態を更新
        setState(() {
          _loadingNewTechnique = false;
          _isLoading = false;
          _initialPageJumpDone = false; // 画面更新時にフラグをリセット
        });

        // 考え方モードの場合はここで処理終了
        return;
      } else {
        // 通常モード: まず、入力内容に複数の項目が含まれているかチェック
        print('暗記項目「${_memoryItem.content}」の複数項目検出を実行');
        final multipleItemsCheck =
            await memoryService.detectMultipleItems(_memoryItem.content);
        final bool isMultipleItems =
            multipleItemsCheck['isMultipleItems'] ?? false;
        final List<dynamic> items = multipleItemsCheck['items'] ?? [];

        // 複数項目が検出された場合
        if (isMultipleItems && items.isNotEmpty) {
          print('複数の項目が検出されました: ${items.length}件');
          // 一旦ローディングを止める
          setState(() {
            _loadingNewTechnique = false;
          });

          // ユーザーにどう処理するか選択してもらうダイアログを表示
          final result = await _showMultipleItemsDialog(items);

          // ダイアログの結果に応じて処理
          if (result == MultipleItemsAction.cancel) {
            // キャンセルの場合は何もしない
            setState(() {
              _isLoading = false;
              _initialPageJumpDone = false; // 画面更新時にフラグをリセット
            });
            return;
          } else if (result == MultipleItemsAction.generateSeparate) {
            // 個別に暗記法を生成する場合
            setState(() {
              _loadingNewTechnique = true;
            });
            await _generateTechniquesForMultipleItems(items);
            return;
          } else {
            // 単一の暗記法として生成する場合は以下の通常フローで続行
            setState(() {
              _loadingNewTechnique = true;
            });
          }
        }

        // 従来方式の場合
        // 現在の梗記法を履歴に追加
        if (_memoryItem.memoryTechniques.isNotEmpty) {
          setState(() {
            // 現在の梗記法を_previousTechniquesに追加
            _previousTechniques.addAll(_memoryItem.memoryTechniques);

            // 重複を削除
            final Map<String, MemoryTechnique> uniqueTechniques = {};
            for (var technique in _previousTechniques) {
              uniqueTechniques['${technique.name}:${technique.description}'] =
                  technique;
            }
            _previousTechniques = uniqueTechniques.values.toList();
          });
        }

        var newTechniques =
            await memoryService.suggestMemoryTechniquesWithHistory(
                _memoryItem.content, _previousTechniques,
                isThinkingMode: _useThinkingMode,
                isMultiAgentMode: _useMultiAgentMode);

        print('生成された暗記法の数: ${newTechniques.length}');

        // 暗記法が空の場合はデフォルトの暗記法を追加
        if (newTechniques.isEmpty) {
          print('警告: 生成された暗記法がありません。デフォルトを使用します。');
          newTechniques = [
            MemoryTechnique(
              name: '標準学習法',
              description: 'この内容は繰り返し学習で身につけることが効果的です。',
              type: 'concept',
            )
          ];
        }

        // 暗記法にisPublicフラグを追加
        final updatedTechniques = newTechniques.map((technique) {
          return MemoryTechnique(
            name: technique.name,
            description: technique.description,
            type: technique.type,
            tags: technique.tags,
            contentKeywords: technique.contentKeywords,
            isPublic: false, // デフォルトでは非公開
          );
        }).toList();

        if (mounted) {
          setState(() {
            _memoryItem = _memoryItem.copyWith(
              memoryTechniques: updatedTechniques,
            );
            _hideMemoryTips = false;
            _loadingNewTechnique = false;
            _isLoading = false;
            _initialPageJumpDone = false; // 画面更新時にフラグをリセット

            // 新しい _similarTechniques を更新（履歴からの提案を含める）
            _similarTechniques = [
              // まず最新の履歴から最大3つを選択
              ..._previousTechniques.take(3),
              // 次に他の類似技術から最大2つを選択（すでに表示済みのものを除く）
              ..._similarTechniques
                  .where((technique) => !_previousTechniques.any((prev) =>
                      prev.name == technique.name &&
                      prev.description == technique.description))
                  .take(2)
            ];

            // 暗記法が変更されたので、AIに説明するテキストを更新
            _setExplanationText();
          });
        }
      }
    } catch (e) {
      print('暗記法の取得中にエラーが発生しました: $e');
      setState(() {
        _loadingNewTechnique = false;
        _isLoading = false;
      });
    } finally {
      // ロック解除 (2秒後に解除することで連続呼び出しを防止)
      Future.delayed(const Duration(seconds: 2), () {
        _isRegenerationLocked = false;
        print('暗記法再生成ロックを解除しました');
      });
    }
  }

  // 複数項目用のダイアログを表示する
  Future<MultipleItemsAction> _showMultipleItemsDialog(
      List<dynamic> items) async {
    // 複数項目検出フラグを設定
    setState(() {
      hasMultipleItems = true;
    });

    // ダイアログの結果を保持する変数
    MultipleItemsAction result = MultipleItemsAction.cancel;

    // ダイアログを表示
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('複数の項目が検出されました'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('入力内容から以下の複数の項目が検出されました：'),
                const SizedBox(height: 8),
                // 検出された項目のリスト（最大5件まで表示）
                ...items.take(5).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '・${item['content']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )),
                if (items.length > 5) Text('...他 ${items.length - 5} 件'),
                const SizedBox(height: 12),
                const Text('複数の項目が検出されたため、マルチエージェント機能は使用されません。'),
                const SizedBox(height: 8),
                const Text('どのように処理しますか？'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('キャンセル'),
              onPressed: () {
                result = MultipleItemsAction.cancel;
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('一つの覚え方として生成'),
              onPressed: () {
                result = MultipleItemsAction.generateSingle;
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('個別に覚え方を生成'),
              onPressed: () {
                result = MultipleItemsAction.generateSeparate;
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );

    return result;
  }

  // 複数の項目に対して個別に暗記法を生成する
  Future<void> _generateTechniquesForMultipleItems(List<dynamic> items,
      {Function(int current, int total)? onProgress}) async {
    // 状態更新はすでに_regenerateAsMultipleContentsで設定されている
    // ここでは複数項目を処理することだけに集中し、UIの変更は最小限に
    try {
      // 生成数の進行状況を追跡するカウンター
      int completedCount = 0;
      final totalCount = items.length;

      // 項目ごとに個別に暗記法を生成する場合はここを実装
      // この実装では、一括で生成するので生成後に完了として処理

      // 複数項目に対する暗記法を生成
      final techniques =
          await memoryService.generateTechniquesForMultipleItems(items);

      // 進行状況を更新
      completedCount = totalCount;
      onProgress?.call(completedCount, totalCount);

      // 暗記法が空の場合はデフォルトの暗記法を追加
      if (techniques.isEmpty) {
        print('警告: 生成された暗記法がありません。デフォルトを使用します。');
        var defaultTechniques = [
          MemoryTechnique(
            name: '標準学習法',
            description: 'この内容は繰り返し学習で身につけることが効果的です。',
            type: 'concept',
            // デフォルトのフラッシュカードを追加
            flashcards: [
              Flashcard(
                question: _memoryItem.content,
                answer: '繰り返し学習で身につけることが効果的です。',
              )
            ],
          )
        ];

        // 暗記法にisPublicフラグを追加
        final updatedTechniques = defaultTechniques.map((technique) {
          return MemoryTechnique(
            name: technique.name,
            description: technique.description,
            type: technique.type,
            tags: technique.tags,
            contentKeywords: technique.contentKeywords,
            isPublic: false, // デフォルトでは非公開
            // フラッシュカードも引き継ぐ
            flashcards: technique.flashcards,
          );
        }).toList();

        if (mounted) {
          setState(() {
            _memoryItem = _memoryItem.copyWith(
              memoryTechniques: updatedTechniques,
            );
            _hideMemoryTips = false;
            _loadingNewTechnique = false;
            _isLoading = false;
            // 複数項目検出フラグは維持 - UIの一貫性のため

            // 暗記法が変更されたので、AIに説明するテキストを更新
            _setExplanationText();
          });
        }
        return;
      }

      // 暗記法にisPublicフラグを追加し、フラッシュカードも引き継ぐ
      final updatedTechniques = techniques.map((technique) {
        return MemoryTechnique(
          name: technique.name,
          description: technique.description,
          type: technique.type,
          tags: technique.tags,
          contentKeywords: technique.contentKeywords,
          isPublic: false, // デフォルトでは非公開
          itemContent: technique.itemContent,
          itemDescription: technique.itemDescription,
          // フラッシュカードも引き継ぐ
          flashcards: technique.flashcards.isNotEmpty
              ? technique.flashcards
              : [
                  Flashcard(
                    question: technique.itemContent,
                    answer: technique.description,
                  )
                ],
        );
      }).toList();

      if (mounted) {
        setState(() {
          _memoryItem = _memoryItem.copyWith(
            memoryTechniques: updatedTechniques,
          );
          _hideMemoryTips = false;
          _loadingNewTechnique = false;
          _isLoading = false;
          hasMultipleItems = true; // 複数項目検出フラグを設定
        });
      }
    } catch (e) {
      print('複数項目に対する暗記法の生成に失敗しました: $e');
      if (mounted) {
        setState(() {
          _loadingNewTechnique = false;
          _isLoading = false;
          // エラー時にはUIを復元
          hasMultipleItems = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暗記法の生成に失敗しました')),
        );
      }
    }
  }

  // ランク付け暗記法を取得する
  Future<void> _fetchRankedMemoryTechniques() async {
    try {
      // ランク付け暗記法を取得
      final rankedTechniques = await memoryService
          .suggestRankedMemoryTechniques(_memoryItem.content);

      // 暗記法が存在する場合のみ処理を続行
      if (rankedTechniques.techniques.isNotEmpty) {
        if (mounted) {
          setState(() {
            _rankedTechniques = rankedTechniques;

            // 現在表示すべき暗記法を取得
            final currentTechnique = rankedTechniques.current;

            // 暗記法にisPublicフラグを追加して_memoryItemを更新
            final updatedTechnique = MemoryTechnique(
              name: currentTechnique.name,
              description: currentTechnique.description,
              type: currentTechnique.type,
              tags: currentTechnique.tags,
              contentKeywords: currentTechnique.contentKeywords,
              isPublic: false, // デフォルトでは非公開
            );

            _memoryItem = _memoryItem.copyWith(
              memoryTechniques: [updatedTechnique],
            );

            _hideMemoryTips = false;
            _loadingNewTechnique = false;
            _isLoading = false;
          });
        }
      } else {
        // ランク付け暗記法が取得できなかった場合はデフォルトの暗記法を生成
        print('ランク付け暗記法が空です。デフォルトの暗記法を生成します。');
        final defaultTechnique = MemoryTechnique(
          name: '標準学習法',
          description: 'この内容は繰り返し学習で身につけることが効果的です。',
          type: 'concept',
          isPublic: false, // デフォルトでは非公開
        );

        if (mounted) {
          setState(() {
            _memoryItem = _memoryItem.copyWith(
              memoryTechniques: [defaultTechnique],
            );
            _hideMemoryTips = false;
            _loadingNewTechnique = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('ランク付け暗記法の取得に失敗しました: $e');
      // エラーが発生した場合はデフォルトの暗記法を生成
      if (mounted) {
        final defaultTechnique = MemoryTechnique(
          name: '標準学習法',
          description: 'エラーが発生しましたが、この内容は繰り返し学習が効果的です。',
          type: 'concept',
          isPublic: false, // デフォルトでは非公開
        );

        setState(() {
          _memoryItem = _memoryItem.copyWith(
            memoryTechniques: [defaultTechnique],
          );
          _hideMemoryTips = false;
          _loadingNewTechnique = false;
          _isLoading = false;
        });
      }
    }
  }

  // 次のランク付け暗記法を表示
  Future<void> _showNextRankedTechnique() async {
    if (_rankedTechniques == null || _loadingNextTechnique) return;

    setState(() {
      _loadingNextTechnique = true;
    });

    try {
      // 次の暗記法に移動
      _rankedTechniques!.nextTechnique();

      // 現在の暗記法を取得
      final currentTechnique = _rankedTechniques!.current;

      // 暗記法にisPublicフラグを追加して_memoryItemを更新
      final updatedTechnique = MemoryTechnique(
        name: currentTechnique.name,
        description: currentTechnique.description,
        type: currentTechnique.type,
        tags: currentTechnique.tags,
        contentKeywords: currentTechnique.contentKeywords,
        isPublic: false, // デフォルトでは非公開
      );

      setState(() {
        _memoryItem = _memoryItem.copyWith(
          memoryTechniques: [updatedTechnique],
        );
        _loadingNextTechnique = false;

        // 暗記法が変更されたので、AIに説明するテキストを更新
        _setExplanationText();
      });
    } catch (e) {
      print('次のランク付け暗記法の表示に失敗しました: $e');
      if (mounted) {
        setState(() {
          _loadingNextTechnique = false;
        });
      }
    }
  }

  // 類似コンテンツの暗記法を取得する
  Future<void> _loadSimilarTechniques() async {
    try {
      final similarTechniques =
          await memoryService.getSimilarTechniques(_memoryItem.content);

      if (mounted) {
        setState(() {
          _similarTechniques = similarTechniques;
        });
      }
    } catch (e) {
      print('類似暗記法の取得に失敗しました: $e');
      // エラーが発生しても画面表示を続行するためにエラーをスローしない
      if (mounted) {
        setState(() {
          _similarTechniques = [];
        });
      }
    }
  }

  // 公開取り消し機能
  Future<void> _unpublishTechnique() async {
    if (_memoryItem.memoryTechniques.isEmpty) return;

    try {
      setState(() {
        _isUnpublishing = true;
      });

      // 表示中の暗記法を取得
      final technique = _memoryItem.memoryTechniques.first;

      // 公開を取り消す
      await memoryService.unpublishMemoryTechnique(technique);

      if (mounted) {
        setState(() {
          // 暗記法の公開状態を更新
          _isPublicTechnique = false;
          _isUnpublishing = false;
        });

        // 成功メッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暗記法の公開を取り消しました')),
        );
      }
    } catch (e) {
      print('公開取り消しエラー: $e');
      if (mounted) {
        setState(() {
          _isUnpublishing = false;
        });

        // エラーメッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('公開の取り消しに失敗しました: $e')),
        );
      }
    }
  }

  // 公開ステータスを更新するヘルパーメソッド
  Future<void> _updatePublicStatus(bool value) async {
    // 現在の状態と同じ場合は何もしない
    if (_isPublicTechnique == value) return;

    // 暗記法がない場合は単純に状態を更新
    if (_memoryItem.memoryTechniques.isEmpty) {
      setState(() {
        _isPublicTechnique = value;
      });
      return;
    }

    try {
      // 現在の暗記法を取得
      final technique = _memoryItem.memoryTechniques.first;

      if (value) {
        // trueの場合は公開する
        await memoryService.publishMemoryTechnique(technique);
      } else {
        // falseの場合は非公開にする
        await memoryService.unpublishMemoryTechnique(technique);
      }

      if (mounted) {
        setState(() {
          // 暗記法の公開状態を更新
          _isPublicTechnique = value;

          // メモリーアイテムの暗記法も更新
          final updatedTechniques = _memoryItem.memoryTechniques.map((t) {
            return MemoryTechnique(
              name: t.name,
              description: t.description,
              type: t.type,
              tags: t.tags,
              contentKeywords: t.contentKeywords,
              isPublic: value,
            );
          }).toList();

          _memoryItem = _memoryItem.copyWith(
            memoryTechniques: updatedTechniques,
          );
        });

        // 成功メッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(value ? '暗記法を公開しました' : '暗記法を非公開にしました')),
        );
      }
    } catch (e) {
      print('公開状態の更新エラー: $e');
      if (mounted) {
        // エラーメッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('公開状態の更新に失敗しました: $e')),
        );
      }
    }
  }

  // フラッシュカード生成用メソッド
  Future<void> _createFlashcardsFromTechnique() async {
    if (!mounted) {
      return;
    }

    // 暗記法が空の場合は処理終了
    if (_memoryItem.memoryTechniques.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暗記法の情報が取得できませんでした')),
      );
      return;
    }

    // 表示中の梗記法の情報を取得
    List<Map<String, dynamic>> flashcardDataList = [];

    // すべての暗記法のフラッシュカードを収集
    for (var technique in _memoryItem.memoryTechniques) {
      // 暗記法にフラッシュカードがあれば追加
      if (technique.flashcards.isNotEmpty) {
        for (var card in technique.flashcards) {
          flashcardDataList.add({
            'question': card.question,
            'answer': card.answer,
          });
        }
      }
    }

    // 既存のフラッシュカードがない場合はAIで検出（単一項目も複数項目も同様に処理）
    if (flashcardDataList.isEmpty) {
      try {
        // 複数項目を検出
        final multipleItemsCheck =
            await memoryService.detectMultipleItems(_memoryItem.content);
        final items = multipleItemsCheck['items'] as List<dynamic>? ?? [];

        for (var item in items) {
          final content = item['content'] as String?;
          final description = item['description'] as String?;
          if (content != null && content.isNotEmpty) {
            flashcardDataList.add({
              'question': content,
              'answer': description ?? '',
            });
          }
        }
      } catch (e) {
        print('複数項目の検出中にエラーが発生しました: $e');
      }
    }

    // 上記の処理でもデータが得られなかった場合はデフォルト動作で作成
    if (flashcardDataList.isEmpty && _memoryItem.memoryTechniques.isNotEmpty) {
      // 最初の暗記法をデフォルトとして使用
      final defaultTechnique = _memoryItem.memoryTechniques.first;

      // コンテンツをそのまま使用
      flashcardDataList.add({
        'question': _memoryItem.content,
        'answer': defaultTechnique.description,
      });
    }

    // フラッシュカードが作成できない場合
    if (flashcardDataList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暗記カードを作成できる暗記法の内容がありません')),
      );
      return;
    }

    // 選択ダイアログを表示（新規作成か既存セットへの追加か）
    await _showFlashcardSetSelectionDialog(flashcardDataList);
  }

  // カードセット選択ダイアログ
  Future<void> _showFlashcardSetSelectionDialog(
      List<Map<String, dynamic>> flashcardDataList) async {
    final cardSetService = Provider.of<CardSetService>(context, listen: false);

    // 既存のカードセットを取得
    List<CardSet> existingSets = [];
    try {
      existingSets = await cardSetService.getCardSets();
    } catch (e) {
      print('カードセット取得エラー: $e');
      // エラーが発生しても続行（新規作成のみ許可）
      existingSets = [];
    }

    if (!mounted) return;

    // ダイアログ表示
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        String? selectedSetId;
        String newSetName = '${_memoryItem.title} カードセット';
        bool isCreatingNew = true;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('暗記カードの作成'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${flashcardDataList.length}枚の暗記カードを作成します。',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // 新規作成か既存セットかの選択
                    const Text('カードセットの選択：'),
                    Row(
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: isCreatingNew,
                          onChanged: (value) {
                            setState(() {
                              isCreatingNew = true;
                            });
                          },
                        ),
                        const Text('新規カードセットを作成'),
                      ],
                    ),
                    if (isCreatingNew)
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'カードセット名',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(text: newSetName),
                          onChanged: (value) {
                            newSetName = value;
                          },
                        ),
                      ),

                    if (existingSets.isNotEmpty) ...[
                      Row(
                        children: [
                          Radio<bool>(
                            value: false,
                            groupValue: isCreatingNew,
                            onChanged: (value) {
                              setState(() {
                                isCreatingNew = false;
                                selectedSetId =
                                    selectedSetId ?? existingSets.first.id;
                              });
                            },
                          ),
                          const Text('既存のカードセットに追加'),
                        ],
                      ),
                      if (!isCreatingNew)
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: '既存カードセット',
                              border: OutlineInputBorder(),
                            ),
                            value: selectedSetId ?? existingSets.first.id,
                            items: existingSets.map((set) {
                              return DropdownMenuItem<String>(
                                value: set.id,
                                child: Text(set.title),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedSetId = value;
                              });
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('キャンセル'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('作成'),
                  onPressed: () {
                    Navigator.of(context).pop({
                      'isNewSet': isCreatingNew,
                      'setId': isCreatingNew
                          ? null
                          : (selectedSetId ??
                              (existingSets.isNotEmpty
                                  ? existingSets.first.id
                                  : null)),
                      'newSetName': isCreatingNew ? newSetName : null,
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // ダイアログがキャンセルされた場合
    if (result == null) return;

    // カードセットの取得または作成
    String? setId;
    if (result['isNewSet']) {
      try {
        final newSetRef = await cardSetService
            .addCardSet(result['newSetName'] ?? '新しいカードセット');
        setId = newSetRef.id;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('カードセットの作成に失敗しました: $e')),
          );
        }
        return;
      }
    } else {
      setId = result['setId'];
    }

    // フラッシュカードの作成
    if (setId != null) {
      // フラッシュカード生成中のローディングアニメーションを表示
      LoadingAnimationDialog.show(
        context,
        message: '暗記カードを生成中...',
        animationType: AnimationType.flashcard,
      );

      // モバイルの場合は広告のロードのみ実行
      if (!kIsWeb) {
        adService.loadInterstitialAd();
      }

      // モバイルの場合は広告のロードのみ行う (表示は別のタイミングで行う)
      if (!kIsWeb) {
        adService.loadRewardedAd();
      }
      final flashCardService =
          Provider.of<FlashCardService>(context, listen: false);
      int successCount = 0;

      for (var cardData in flashcardDataList) {
        try {
          await flashCardService.addFlashCard(
            cardData['question'] ?? '',
            cardData['answer'] ?? '',
            setId: setId,
          );
          successCount++;
        } catch (e) {
          print('暗記カード作成エラー: $e');
          // エラーがあっても続行
        }
      }

      if (mounted) {
        // ローディングアニメーションダイアログを閉じる
        Navigator.of(context, rootNavigator: true).pop();

        // 成功メッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount枚の暗記カードを作成しました'),
            duration: const Duration(seconds: 2),
          ),
        );

        // アニメーション開始から3秒後に広告を表示
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            adService.showRewardedAd();
          }
        });

        // カードセット詳細画面へ遷移
        // 少し遅らせて遷移し、メッセージを表示する時間を確保
        // setIdがnullでないことを確認する必要があります
        final String cardSetId = setId; // String?からString型への変換エラーを回避

        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;

          // CardSetDetailScreenへ遷移
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => CardSetDetailScreen(
                cardSetId: cardSetId, // 正しいパラメータ名と型を使用
              ),
            ),
          );
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // MemoryItemの初期化
    _memoryItem = widget.memoryItem;
    _isFromPublishedLibrary = widget.isFromPublishedLibrary;

    // ウィジェットプロパティからAIモード設定を取得
    _useMultiAgentMode = widget.useMultiAgentMode;
    _useThinkingMode = widget.useThinkingMode;

    // ページコントローラーの初期化
    pageController = PageController(viewportFraction: 0.95);
    _initialPageJumpDone = false; // 新しいコントローラー作成時にフラグをリセット

    // SharedPreferencesからマルチエージェントモードの設定を読み込む
    _loadMultiAgentModeSetting();

    // 公開状態の設定
    if (_isFromPublishedLibrary) {
      _isPublicTechnique = true;
    } else if (_memoryItem.memoryTechniques.isNotEmpty) {
      _isPublicTechnique = _memoryItem.memoryTechniques[0].isPublic;
    }

    setState(() {
      _isLoading = true;
    });

    // 暗記法がまだ生成されていない場合は自動的に取得
    if (_memoryItem.memoryTechniques.isEmpty) {
      _fetchMemoryTechniques().then((_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    } else {
      // 暗記法が既に存在する場合はローディング状態を解除
      setState(() {
        _isLoading = false;
      });
    }

    // 類似コンテンツの暗記法を取得
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSimilarTechniques();
    });

    // UI描画後に広告表示の準備が整うタイミングでステートを更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初回レンダリング後の処理
      if (_isLoading && !kIsWeb && mounted) {
        // アプリ起動時の広告表示は遅らせる
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && !_isInitialAdShown) {
            setState(() {
              _isInitialAdShown = true;
            });
          }
        });
      }
    });

    _initialPageJumpDone = false; // ページジャンプフラグを初期化
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _explanationController.dispose();
    pageController.dispose();
    _initialPageJumpDone = false; // 無効化
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UI描画後に広告表示の準備が整うタイミングでステートを更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // バナー広告をロード
      if (mounted) {
        _loadBannerAd();
      }
    });

    return Scaffold(
      // iOSとAndroidではバナー広告をコンテンツ内に配置するため、bottomNavigationBarは使用しない
      appBar: AppBar(
        title: Text(
          '暗記パイで覚えよう！',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.8,
            color: Colors.blue.shade900,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.blue.shade100,
        elevation: 1,
        iconTheme: IconThemeData(color: Colors.blue.shade900),
        actions: [
          // 公開ライブラリからの場合、公開取り消しボタンを表示
          if (_isFromPublishedLibrary && _isPublicTechnique)
            IconButton(
              icon: const Icon(Icons.public_off),
              tooltip: '公開を取り消す',
              color: _isUnpublishing ? Colors.grey : Colors.red.shade700,
              onPressed: _isUnpublishing ? null : _unpublishTechnique,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '別の暗記法を使う',
            color: Colors.blue.shade800,
            onPressed: _loadingNewTechnique ? null : _fetchMemoryTechniques,
          ),
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'ホームに戻る',
            color: Colors.blue.shade800,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade100,
                Colors.white,
              ],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  // スクロール挙動を改善
                  physics: const AlwaysScrollableScrollPhysics(),
                  // 下部に余分なパディングを追加
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 入力を見るドロップダウン - 考え方モード以外で表示
                      if (!_useThinkingMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildInputDropdown(),
                        ),
                      // _buildContentCard(),
                      // const SizedBox(height: 24),

                      // 暗記法ステップ
                      _buildMemoryTips(),
                      const SizedBox(height: 24),

                      // 1. 覚えたか確認するボタン - 考え方モードでは非表示
                      if (!_useThinkingMode) // 考え方モードでない場合のみ表示
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                // 覚え方と内容をマスク／マスク解除
                                _hideMemoryTips = !_hideMemoryTips;

                                // 確認モードに入るときは自動的にAI説明入力を表示
                                if (_hideMemoryTips) {
                                  _showExplanationInput = true;
                                } else {
                                  // マスク解除時はAI説明をクリア
                                  _showExplanationInput = false;
                                  _aiFeedback = null;
                                }
                              });
                            },
                            icon: Icon(
                                _hideMemoryTips
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 28),
                            label: Text(
                              _hideMemoryTips ? '覚え方を表示する' : '覚えたか確認する',
                              style: const TextStyle(fontSize: 18),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hideMemoryTips
                                  ? Colors.blue.shade600
                                  : Colors.orange.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              minimumSize: const Size(280, 56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 3,
                            ),
                          ),
                        ),

                      // AI説明入力フィールドとフィードバック
                      if (_showExplanationInput && !_useThinkingMode)
                        _buildAIExplanationSection(),

                      const SizedBox(height: 24),

                      _buildTryAnotherButton(),
                      _buildBottomButtons(),

                      // バナー広告をフラッシュカード生成ボタンの下に表示
                      if (_isBannerAdLoaded && !_isLoading && !kIsWeb)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          width: double.infinity,
                          height: 60, // 高さを固定することでレイアウトの安定性を高める
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: adService.getBannerAdWidget(),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // 複数内容として再生成する機能は削除されました

  // 別の梗記法を試すボタン
  Widget _buildTryAnotherButton() {
    // ローディング中はスピナーを表示
    if (_loadingNewTechnique || _loadingNextTechnique) {
      return const Center(child: CircularProgressIndicator());
    }

    // マルチエージェントモードかどうか
    final bool isMultiAgentAvailable =
        _useMultiAgentMode && _rankedTechniques != null;

    final List<Widget> children = [
      // ボタンを横に並べるためのRow
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 別の暗記法を生成ボタン
              TextButton.icon(
                onPressed: isMultiAgentAvailable
                    ? _showNextRankedTechnique
                    : _fetchMemoryTechniques,
                icon: const Icon(Icons.refresh),
                label:
                    Text(isMultiAgentAvailable ? '次のおすすめの覚え方を表示' : '別の暗記法を生成'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue.shade600,
                ),
              ),

              const SizedBox(width: 16),

              // 複数内容として再生成ボタンを削除
            ],
          ),
        ),
      ),
    ];

    // マルチエージェントモードのボタンは設定エリアへ移動

    // 現在使用中のモードを表示(マルチエージェントモード時のみ)
    if (_rankedTechniques != null && _useMultiAgentMode && !_isLoading) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '現在の表示: ${_rankedTechniques!.currentIndex + 1}/${_rankedTechniques!.techniques.length}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(children: children);
  }

  // 暗記法表示用ウィジェットを構築する
  Widget _buildMemoryTips() {
    // 考え方モードの場合は暗記法カードを表示せず、考え方のみを表示
    if (_useThinkingMode) {
      // デバッグログ
      print('考え方モード: 暗記法カードを非表示にし、考え方のみを表示します');

      // ダミーの暗記法が必要な場合は作成
      if (_memoryItem.memoryTechniques.isEmpty) {
        _memoryItem.memoryTechniques.add(
          MemoryTechnique(
            name: '考え方モード',
            description: '内容の本質や原理を捕えた簡潔な説明を生成します。',
            type: 'thinking',
            tags: ['考え方モード'],
          ),
        );
      }

      // 考え方モードの説明が未取得の場合は取得
      if (_thinkingModeExplanation == null && !_isLoadingThinkingMode) {
        _fetchThinkingModeExplanation();
      }

      // 投稿内容と考え方のみを表示する特別なウィジェットを返す
      return _buildThinkingModeContent();
    }

    // 通常モードの場合の以下の処理
    // デバッグログは最小限にする

    // 真の複数項目モードか確認 - 検出された項目のコンテンツがあるか確認
    bool hasDetectedItems =
        _memoryItem.memoryTechniques.any((t) => t.itemContent.isNotEmpty);

    // 実際に複数項目を検出しているか再確認
    if (hasDetectedItems) {
      hasMultipleItems = true; // クラス変数を更新
    }

    // ページコントローラーの確認とリセット
    // 初期表示時のみ先頭ページに設定（_initialPageJumpDoneがfalseの場合のみ実行）
    if (!_initialPageJumpDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pageController.hasClients) {
          pageController.jumpToPage(0);
          // 初期ジャンプが完了したのでフラグを設定
          _initialPageJumpDone = true;
        }
      });
    }

    // 暗記法が空の場合、デフォルトの暗記法を追加
    if (_memoryItem.memoryTechniques.isEmpty) {
      _memoryItem.memoryTechniques.add(
        MemoryTechnique(
          name: '標準学習法',
          description: '繰り返し学習することで記憶を定着させる方法です。',
          type: 'concept',
        ),
      );
    }

    // 暗記法の名前やタイプが空の場合、デフォルト値を設定
    if (_memoryItem.memoryTechniques.isNotEmpty) {
      final firstTechnique = _memoryItem.memoryTechniques[0];
      if (firstTechnique.name.isEmpty) {
        // copyWithの代わりに新しいMemoryTechniqueを作成して置き換える
        _memoryItem.memoryTechniques[0] = MemoryTechnique(
          name: '標準学習法',
          description: firstTechnique.description,
          type: firstTechnique.type.isEmpty ? 'concept' : firstTechnique.type,
          tags: firstTechnique.tags,
          contentKeywords: firstTechnique.contentKeywords,
          itemContent: firstTechnique.itemContent,
        );
      } else if (firstTechnique.type.isEmpty) {
        // タイプのみが空の場合、新しいMemoryTechniqueを作成
        _memoryItem.memoryTechniques[0] = MemoryTechnique(
          name: firstTechnique.name,
          description: firstTechnique.description,
          type: 'concept',
          tags: firstTechnique.tags,
          contentKeywords: firstTechnique.contentKeywords,
          itemContent: firstTechnique.itemContent,
        );
      }
    }

    // メインの暗記法カードの配列を作成
    final List<Widget> memoryCards = [];

    if (_memoryItem.memoryTechniques.isNotEmpty) {
      // 単一項目モードの場合

      // 暗記法カードのベースとなるコンテナを追加
      memoryCards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー部分
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.memory,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text('暗記法',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_memoryItem.memoryTechniques.length}個',
                            style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 暗記法の水平スクロール表示

                  // ナビゲーションボタン表示（複数カードの場合のみ）
                  if (_memoryItem.memoryTechniques.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              if (pageController.page! > 0) {
                                pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('前の暗記法'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade50,
                              foregroundColor: Colors.orange.shade700,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.orange.shade200),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (pageController.page! <
                                  _memoryItem.memoryTechniques.length - 1) {
                                pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                            icon: const Text('次の暗記法'),
                            label: const Icon(Icons.arrow_forward),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade50,
                              foregroundColor: Colors.orange.shade700,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.orange.shade200),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.45,
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: _memoryItem.memoryTechniques.length,
                      itemBuilder: (context, index) {
                        final technique = _memoryItem.memoryTechniques[index];

                        // 暗記法の種類に基づいてアイコンと色を決定
                        IconData techniqueIcon;
                        Color techniqueColor;

                        switch (technique.type) {
                          case 'mnemonic':
                            techniqueIcon = Icons.lightbulb_outline;
                            techniqueColor = Colors.orange.shade700;
                            break;
                          case 'relationship':
                            techniqueIcon = Icons.account_tree_outlined;
                            techniqueColor = Colors.green.shade700;
                            break;
                          case 'concept':
                            techniqueIcon = Icons.psychology_outlined;
                            techniqueColor = Colors.purple.shade700;
                            break;
                          default:
                            techniqueIcon = Icons.school_outlined;
                            techniqueColor = Colors.blue.shade700;
                        }

                        return _buildMemoryTipCard(
                          title: technique.name.isNotEmpty
                              ? technique.name
                              : '標準学習法',
                          content: technique.description.isNotEmpty
                              ? technique.description
                              : '繰り返し学習することで記憶を定着させる方法です。',
                          // デバッグ用テストデータを含むimageフィールド
                          image: technique.image,
                          icon: techniqueIcon,
                          color: techniqueColor,
                          hideContent: _hideMemoryTips,
                          isMainTechnique: true,
                          tags: technique.tags,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // メモ: 「他の覚え方」セクションはユーザー要望により表示しないようにしました
    // }

    if (memoryCards.isEmpty) {
      return const Center(
        child: Text(
          '暗記法が見つかりません。「試してみる」をタップして新しい暗記法を生成してみましょう。',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: memoryCards,
    );
  }

  // 暗記法のカードウィジェット
  Widget _buildMemoryTipCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
    required bool hideContent,
    required bool isMainTechnique,
    List<String>? tags,
    String? image, // イメージ説明を追加
  }) {
    return Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // 必要な高さのみ使用
            children: [
              // タイトル部分
              Row(
                children: [
                  Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // 非表示時のコンテナ
              if (hideContent)
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '覚え方は隠されています',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                )
              // コンテンツの表示部分
              else
                // 内容表示コンテナ
                Container(
                  constraints: const BoxConstraints(
                    maxHeight: 200,
                  ),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // コンテンツ表示
                          _buildMathContent(content),

                          // イメージ表示セクション（ドロップダウン形式）
                          if (image != null && image.isNotEmpty)
                            _buildImageDropdown(image),

                          // タグ
                          if (tags != null && tags.isNotEmpty)
                            Container(
                              padding:
                                  const EdgeInsets.only(top: 12, bottom: 4),
                              margin: const EdgeInsets.only(top: 12),
                              decoration: BoxDecoration(
                                  border: Border(
                                      top: BorderSide(
                                          color: Colors.grey.shade200,
                                          width: 1))),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: tags
                                    .map((tag) => Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          child: Text(
                                            tag,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ));
  }

  // AI説明入力フィールドとフィードバック
  Widget _buildAIExplanationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb,
                color: Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AIに説明してみる',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自分の言葉で説明してみてください。AIがコメントしてくれます。',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _explanationController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'ここに説明を入力してください',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      maxLines: 5,
                      onChanged: _debouncedGetFeedback,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _getAIFeedback,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '送信',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _isLoadingFeedback
                  ? Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          const CircularProgressIndicator(strokeWidth: 2),
                          const SizedBox(height: 8),
                          Text('AIがあなたの説明を評価しています...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              )),
                        ],
                      ),
                    )
                  : _aiFeedback != null
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AIフィードバック:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _aiFeedback!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade800,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  // アクションボタン
  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // フラッシュカード自動生成ボタン
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.flash_on,
                      color: Colors.amber.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '暗記カードを作成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'この暗記法から暗記カードを自動生成します。複数項目がある場合は複数のカードが作成されます。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _createFlashcardsFromTechnique,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_card),
                      SizedBox(width: 8),
                      Text('暗記カード作成'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Webのみ広告表示（フラッシュカードと公開ウィジェットの間）
          if (kIsWeb)
            // Web ads removed
            const SizedBox(height: 16),

          // 暗記法を公開するか否かのトグル
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.public,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'この覚え方を公開する',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '公開すると、他のユーザーがあなたの覚え方を参考にできます。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPublicTechnique ? '公開中' : '非公開',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isPublicTechnique
                            ? Colors.green.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                    Switch(
                      value: _isPublicTechnique,
                      onChanged: (value) {
                        _updatePublicStatus(value);
                      },
                      activeColor: Colors.green.shade600,
                      activeTrackColor: Colors.green.shade100,
                      inactiveThumbColor: Colors.grey.shade400,
                      inactiveTrackColor: Colors.grey.shade200,
                    ),
                  ],
                ),
                if (_isPublicTechnique)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'この覚え方は公開されます。完了ボタンを押すと公開ライブラリに追加されます。',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 完了ボタン
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  // 常に現在のメモリーアイテムをFirestoreに保存
                  await memoryService.updateMemoryItem(_memoryItem);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('覚え方を保存しました')),
                    );
                  }

                  // 公開設定が有効な場合、暗記法を公開ライブラリに追加
                  if (_isPublicTechnique &&
                      _memoryItem.memoryTechniques.isNotEmpty) {
                    try {
                      // マルチエージェントモードと通常モードで処理を分ける
                      MemoryTechnique techniqueToPublish;

                      if (_useMultiAgentMode && _rankedTechniques != null) {
                        // マルチエージェントモードの場合は現在表示している暗記法を登録
                        final currentTechnique = _rankedTechniques!.current;
                        techniqueToPublish = MemoryTechnique(
                          name: currentTechnique.name,
                          description: currentTechnique.description,
                          type: currentTechnique.type,
                          contentKeywords: currentTechnique.contentKeywords,
                          isPublic: _isPublicTechnique,
                        );

                        // 単一暗記法の公開
                        await memoryService
                            .publishMemoryTechnique(techniqueToPublish);
                      } else {
                        // 通常モードの場合はメモリーアイテムのすべての暗記法を登録
                        for (var technique in _memoryItem.memoryTechniques) {
                          // 暗記法のコピーを作成して公開フラグを設定
                          final techniqueToPublish = MemoryTechnique(
                            name: technique.name,
                            description: technique.description,
                            type: technique.type,
                            tags: technique.tags,
                            contentKeywords: technique.contentKeywords,
                            isPublic: true,
                            itemContent: technique.itemContent,
                            itemDescription: technique.itemDescription,
                            flashcards: technique.flashcards,
                          );

                          // 個別に公開
                          await memoryService
                              .publishMemoryTechnique(techniqueToPublish);
                        }
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('覚え方を公開しました')),
                        );
                      }
                    } catch (e) {
                      print('暗記法の公開に失敗しました: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('暗記法の公開に失敗しました: $e')),
                        );
                      }
                    }
                  }
                } catch (e) {
                  print('暗記法の保存に失敗しました: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('暗記法の保存に失敗しました: $e')),
                    );
                  }
                } finally {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.check_circle, size: 28),
              label: const Text('完了', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                minimumSize: const Size(280, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 注：以前の_buildProgressDialogメソッドは削除されました
  // 現在はLoadingAnimationDialogを使用

  // イメージヒントをドロップダウン形式で表示するウィジェット
  Widget _buildImageDropdown(String imageText) {
    // イメージ表示の状態を管理する変数
    bool isExpanded = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 12),

          // イメージヒントボタン
          InkWell(
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: Colors.blue.shade800),
                  const SizedBox(width: 6),
                  Text('イメージヒント',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue.shade800,
                      )),
                ],
              ),
            ),
          ),

          // 展開時のみイメージ内容を表示
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isExpanded ? null : 0,
            constraints: BoxConstraints(
              maxHeight: isExpanded ? 300 : 0,
            ),
            child: AnimatedOpacity(
              opacity: isExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: isExpanded
                  ? Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.lightBlue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.lightBlue.shade200, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.image_outlined,
                              color: Colors.blue.shade600, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              imageText,
                              style: TextStyle(
                                fontSize: 15,
                                fontStyle: FontStyle.italic,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ]);
      },
    );
  }
}
