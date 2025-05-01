import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:flip_card/flip_card.dart';
import '../models/flash_card.dart';
import '../services/card_set_service.dart';
import '../services/auth_service.dart';
import '../services/ad_service.dart';
import '../services/subscription_service.dart';

import 'package:flutter_math_fork/flutter_math.dart';

class CardStudyScreen extends StatefulWidget {
  final String cardSetId;
  final String cardSetTitle;

  const CardStudyScreen({
    super.key,
    required this.cardSetId,
    required this.cardSetTitle,
  });

  @override
  _CardStudyScreenState createState() => _CardStudyScreenState();
}

class _CardStudyScreenState extends State<CardStudyScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<FlashCard> _cards = [];
  List<FlashCard> _studyCards = [];
  int _currentIndex = 0;
  final GlobalKey<FlipCardState> _cardKey = GlobalKey<FlipCardState>();

  // 統計情報
  int _correctCount = 0;
  int _incorrectCount = 0;

  // ストリーム購読管理用
  StreamSubscription<List<FlashCard>>? _cardsSubscription;

  List<bool> _cardResults = []; // 各カードの正誤結果を保持するリスト

  // 広告サービス
  final AdService adService = GetIt.instance<AdService>();
  bool _isShowingInterstitialAd = false;

  // カードアニメーション用の変数
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();

    // アニメーションコントローラーを初期化
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation =
        Tween<double>(begin: 1.0, end: 0.0).animate(_animationController)
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _animationController.reverse();
              _updateCardAfterAnimation();
            }
          });

    _loadCards();
    _preloadInterstitialAd(); // インタースティシャル広告のプリロード
  }

  @override
  void dispose() {
    // ストリーム購読の解除
    _cardsSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // インタースティシャル広告をプリロード
  Future<void> _preloadInterstitialAd() async {
    if (!mounted) return;
    
    try {
      // 広告表示の準備が整うまで少し遅延
      await Future.delayed(const Duration(seconds: 1));
      
      // インタースティシャル広告をロード
      await adService.loadInterstitialAd();
    } catch (e) {
      print('インタースティシャル広告のロード中にエラーが発生しました: $e');
    }
  }

  Future<void> _loadCards() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      final isValidAuth = await authService.validateAuthentication();

      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }

      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);

      // カードセット内のカードを取得
      final cardsStream =
          await cardSetService.watchCardsInSet(widget.cardSetId);
      _cardsSubscription = cardsStream.listen(
        (cards) {
          if (mounted) {
            setState(() {
              _cards = cards;

              if (_cards.isEmpty) {
                _isLoading = false;
                return;
              }

              // カードをシャッフルして学習用のリストを作成
              _studyCards = List.from(_cards);
              _studyCards.shuffle();

              _currentIndex = 0;
              _correctCount = 0;
              _incorrectCount = 0;
              _cardResults = List.filled(_studyCards.length, false);
              _isLoading = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });

            String errorMessage = error.toString();
            // エラーメッセージをユーザーフレンドリーに調整
            if (errorMessage.contains('permission-denied')) {
              errorMessage = 'データベースのアクセス権限がありません。再度ログインしてください。';
            } else if (errorMessage.contains('ログイン')) {
              errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('カード情報の取得に失敗しました: $errorMessage'),
                backgroundColor: Colors.red.shade400,
                action: SnackBarAction(
                  label: 'ログイン',
                  textColor: Colors.white,
                  onPressed: () {
                    // ログイン画面に遷移するコードを追加したい場合はここに記述
                  },
                ),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        String errorMessage = e.toString();
        // エラーメッセージをユーザーフレンドリーに調整
        if (errorMessage.contains('permission-denied')) {
          errorMessage = 'データベースのアクセス権限がありません。再度ログインしてください。';
        } else if (errorMessage.contains('ログイン')) {
          errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('データの読み込みに失敗しました: $errorMessage'),
            backgroundColor: Colors.red.shade400,
            action: SnackBarAction(
              label: 'ログイン',
              textColor: Colors.white,
              onPressed: () {
                // ログイン画面に遷移するコードを追加したい場合はここに記述
              },
            ),
          ),
        );
      }
    }
  }

  // 進捗バーと統計情報表示用のウィジェット
  Widget _buildProgressBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // リニアプログレスバー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (_currentIndex + 1) / _studyCards.length,
                backgroundColor: Colors.grey.shade200,
                color: Colors.blue.shade400,
                minHeight: 8,
              ),
            ),
          ),

          // 進捗統計情報
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.shade100,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.credit_card,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'カード: ${_currentIndex + 1} / ${_studyCards.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green.shade600, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$_correctCount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cancel,
                              color: Colors.red.shade600, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$_incorrectCount',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // カード進捗インジケーター（水平スクロール可能）
          if (_studyCards.isNotEmpty)
            Container(
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(_studyCards.length, (index) {
                    Color color;
                    if (index > _currentIndex) {
                      color = Colors.grey.shade300; // 未学習
                    } else if (index == _currentIndex) {
                      color = Colors.blue.shade400; // 現在のカード
                    } else if (_cardResults.length > index &&
                        _cardResults[index]) {
                      color = Colors.green.shade400; // 正解
                    } else {
                      color = Colors.red.shade400; // 不正解
                    }

                    return Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: index == _currentIndex
                            ? [
                                BoxShadow(
                                    color: Colors.blue.shade200,
                                    blurRadius: 2,
                                    spreadRadius: 1)
                              ]
                            : null,
                        border: index == _currentIndex
                            ? Border.all(color: Colors.blue.shade700, width: 2)
                            : null,
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // アニメーション付きでカードを次に進めるメソッド
  void _nextCard({bool correct = false}) {
    // アニメーション中なら何もしない
    if (_isAnimating) return;

    // 現在のカードの結果を記録
    if (_cardResults.length > _currentIndex) {
      _cardResults[_currentIndex] = correct;
    }

    if (correct) {
      setState(() {
        _correctCount++;
      });
    } else {
      setState(() {
        _incorrectCount++;
      });
    }

    // 次のカードがある場合は進む
    if (_currentIndex < _studyCards.length - 1) {
      // 次のカードに移る前に、現在のカードが裏面表示なら事前に表に戻す
      // これにより次のカードへの遷移がスムーズになる
      if (_cardKey.currentState?.isFront == false && !_isAnimating) {
        // まず表に戻してからアニメーションを開始
        _cardKey.currentState?.toggleCard();
        // わずかな遅延を入れてから次のカードに移動
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _isAnimating = true;
              _animationController.forward();
            });
          }
        });
      } else {
        // すでに表面を表示している場合はそのままアニメーション
        setState(() {
          _isAnimating = true;
          _animationController.forward();
        });
      }
    } else {
      // すべてのカードを学習し終えた場合は結果画面を表示
      _showResults();
    }
  }

  // アニメーション完了後にカードを更新する
  void _updateCardAfterAnimation() {
    setState(() {
      // 重要: 先にインデックスを更新して次のカードにする
      _currentIndex++;
      // 表示フラグをリセット
      _isAnimating = false;
    });

    // 次のカードが表示された後にカードが裏返っている場合は表にする
    // これを次のフレーム描画後に実行することで画面がちらつくのを防ぐ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cardKey.currentState?.isFront == false) {
        _cardKey.currentState?.toggleCard();
      }
    });
  }

  // TeX数式を含むテキストを正しく表示するメソッド
  Widget _buildMathContent(String content, Color textColor) {
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
        contentWidgets.add(_processInlineMath(textBefore, textColor));
      }

      // ディスプレイモードの数式
      String formula =
          content.substring(match.start + 2, match.end - 2); // $$...$$ の内側
      contentWidgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Math.tex(
              formula,
              textStyle: TextStyle(fontSize: 24, color: textColor),
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    // 残りのテキストを处理
    if (lastEnd < content.length) {
      String remainingText = content.substring(lastEnd);
      contentWidgets.add(_processInlineMath(remainingText, textColor));
    }

    // 数式がない場合は単純にインライン数式処理を適用
    if (contentWidgets.isEmpty) {
      contentWidgets.add(_processInlineMath(content, textColor));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: contentWidgets,
    );
  }

  // インライン数式の処理
  Widget _processInlineMath(String text, Color textColor) {
    // $...$ 形式のインライン数式を探す
    final RegExp inlineMathRegExp = RegExp(r'\$(.*?)\$', dotAll: true);
    List<RegExpMatch> matches = inlineMathRegExp.allMatches(text).toList();

    if (matches.isEmpty) {
      // 数式がない場合は通常のテキストとして表示
      return Text(
        text,
        style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        textAlign: TextAlign.center,
      );
    }

    // インライン数式を含むテキストを构築
    List<InlineSpan> spans = [];
    int lastEnd = 0;

    for (var match in matches) {
      // 数式の前のテキスト
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
          ),
        );
      }

      // インライン数式
      String formula =
          text.substring(match.start + 1, match.end - 1); // $...$ の内側
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            formula,
            textStyle: TextStyle(fontSize: 24, color: textColor),
          ),
        ),
      );

      lastEnd = match.end;
    }

    // 残りのテキスト
    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        ),
      );
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  // カードの表示を改善
  Widget _buildCardSide(String text, Color backgroundColor, String label,
      Color borderColor, IconData icon) {
    return Card(
      elevation: 6,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: borderColor,
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: backgroundColor,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: borderColor.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: borderColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: borderColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(flex: 1),
            Expanded(
              flex: 8,
              child: Center(
                child: SingleChildScrollView(
                  child: _buildMathContent(text, Colors.blue.shade900),
                ),
              ),
            ),
            const Spacer(flex: 1),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'タップしてカードを裏返す',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResults() async {
    final double correctPercentage =
        (_correctCount / max(_correctCount + _incorrectCount, 1) * 100);
        
    try {
      // プレミアムユーザーでない場合のみ広告表示
      final subscriptionService = Provider.of<SubscriptionService>(context, listen: false);
      final subscription = await subscriptionService.getUserSubscription();
      
      // インタースティシャル広告を表示（プレミアムユーザーでない場合）
      if (!_isShowingInterstitialAd && (!subscription.isPremium)) {
        _isShowingInterstitialAd = true;
        await adService.showInterstitialAd();
        _isShowingInterstitialAd = false;
        
        // 次回用に再度広告をプリロード
        _preloadInterstitialAd();
      }
    } catch (e) {
      print('広告表示中にエラーが発生しました: $e');
      // エラーが発生しても結果表示は継続する
    }

    // AlertDialog の表示にフレーム描画後のコールバックを使用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 5,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade200.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
              ],
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ヘッダー部分
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getResultBackgroundColor(correctPercentage),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        correctPercentage >= 80
                            ? Icons.emoji_events
                            : correctPercentage >= 60
                                ? Icons.star
                                : Icons.school,
                        color: _getResultColor(correctPercentage),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '学習完了！',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            'お疲れ様でした！',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Divider(color: Colors.blue.shade100, height: 32),

                // 成績表示部分
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // 正答率表示
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                        decoration: BoxDecoration(
                          color: _getResultBackgroundColor(correctPercentage),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _getResultColor(correctPercentage)
                                  .withOpacity(0.2),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '正答率: ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${correctPercentage.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 正解・不正解カウント
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildResultBlock(
                            icon: Icons.check_circle,
                            color: Colors.green.shade600,
                            bgColor: Colors.green.shade50,
                            count: _correctCount,
                            label: '正解',
                          ),
                          Container(
                            height: 60,
                            width: 1,
                            color: Colors.grey.shade300,
                          ),
                          _buildResultBlock(
                            icon: Icons.cancel,
                            color: Colors.red.shade600,
                            bgColor: Colors.red.shade50,
                            count: _incorrectCount,
                            label: '不正解',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 評価メッセージ
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb,
                          color: Colors.amber.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getResultMessage(correctPercentage),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // バナー広告表示エリアを削除（インタースティシャル広告に置き換えるため）

                // ボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop(); // 学習画面を閉じる
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.blue.shade300),
                        ),
                      ),
                      child: Text(
                        '終了',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _restartStudy();
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('もう一度'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // 結果表示用のブロック
  Widget _buildResultBlock({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // 正答率に応じた色を返す
  Color _getResultColor(double percentage) {
    if (percentage >= 80) return Colors.green.shade700;
    if (percentage >= 70) return Colors.blue.shade700;
    if (percentage >= 60) return Colors.amber.shade700;
    if (percentage >= 50) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  // 正答率に応じた背景色を返す
  Color _getResultBackgroundColor(double percentage) {
    if (percentage >= 80) return Colors.green.shade400;
    if (percentage >= 70) return Colors.blue.shade400;
    if (percentage >= 60) return Colors.amber.shade400;
    if (percentage >= 50) return Colors.orange.shade400;
    return Colors.red.shade400;
  }

  // 正答率に応じたメッセージを返す
  String _getResultMessage(double percentage) {
    if (percentage >= 80) return '素晴らしい成績です！よく理解できています。';
    if (percentage >= 70) return '良い成績です！あともう少し復習しましょう。';
    if (percentage >= 60) return 'まずまずの成績です。もう少し復習が必要かもしれません。';
    if (percentage >= 50) return '基本的な理解はできています。定期的に復習しましょう。';
    return 'もう少し復習が必要です。焦らず繰り返し学習しましょう。';
  }

  void _restartStudy() {
    setState(() {
      // カードをシャッフル
      _studyCards.shuffle();
      _currentIndex = 0;
      _correctCount = 0;
      _incorrectCount = 0;
      _cardResults = List.filled(_studyCards.length, false);
    });

    // カードが裏返っている場合は表に戻す
    if (_cardKey.currentState?.isFront == false) {
      _cardKey.currentState?.toggleCard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '学習: ${widget.cardSetTitle}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue.shade500,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'カードをシャッフル',
            onPressed: () {
              setState(() {
                _studyCards.shuffle();
                _currentIndex = 0;
                _correctCount = 0;
                _incorrectCount = 0;
                _cardResults = List.filled(_studyCards.length, false);
              });
              // カードが裏返っている場合は表に戻す
              if (_cardKey.currentState?.isFront == false) {
                _cardKey.currentState?.toggleCard();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('カードをシャッフルしました'),
                  backgroundColor: Colors.blue.shade400,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '学習のヒント',
            onPressed: () {
              _showStudyHintDialog(context);
            },
          ),
        ],
      ),
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
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'カードを読み込み中...',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            : _cards.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.blue.shade100,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.note_alt_outlined,
                              size: 64,
                              color: Colors.blue.shade300,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'このカードセットにはカードがありません',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'カードを追加してから学習を始めましょう',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('戻る'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade500,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // 進捗バー
                      _buildProgressBar(),

                      // カード表示領域
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                          // GestureDetectorでスワイプ機能を追加
                          child: GestureDetector(
                            // 水平方向のスワイプを検出
                            onHorizontalDragEnd: (details) {
                              // スワイプの速度が一定以上ならカードを次に進める
                              if (details.primaryVelocity != null &&
                                  details.primaryVelocity!.abs() > 300) {
                                // スクリーンリーダーでフィードバックを表示
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('次のカードに進みました'),
                                    backgroundColor: Colors.green.shade400,
                                    duration: const Duration(milliseconds: 500),
                                  ),
                                );
                                // 正解として次のカードに進む
                                _nextCard(correct: true);
                              }
                            },
                            // アニメーションと組み合わせたFlipCardウィジェット
                            child: Opacity(
                              opacity: _isAnimating ? _animation.value : 1.0,
                              child: FlipCard(
                                key: _cardKey,
                                direction: FlipDirection.HORIZONTAL,
                                speed: 400,
                                front: _buildCardSide(
                                  _studyCards[_currentIndex].frontText,
                                  Colors.blue.shade50,
                                  '表面',
                                  Colors.blue.shade300,
                                  Icons.visibility,
                                ),
                                back: _buildCardSide(
                                  _studyCards[_currentIndex].backText,
                                  Colors.green.shade50,
                                  '裏面',
                                  Colors.green.shade300,
                                  Icons.check_circle_outline,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 操作ボタン
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildActionButton(
                              onPressed: () => _nextCard(correct: false),
                              icon: Icons.close,
                              label: '不正解',
                              backgroundColor: Colors.red.shade400,
                              borderColor: Colors.red.shade600,
                            ),
                            _buildActionButton(
                              onPressed: () => _nextCard(correct: true),
                              icon: Icons.check,
                              label: '正解',
                              backgroundColor: Colors.green.shade400,
                              borderColor: Colors.green.shade600,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

Widget _buildActionButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
  required Color backgroundColor,
  required Color borderColor,
}) {
  return Material(
    color: backgroundColor,
    borderRadius: BorderRadius.circular(12),
    elevation: 3,
    shadowColor: borderColor.withOpacity(0.4),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      splashColor: Colors.white.withOpacity(0.2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showStudyHintDialog(BuildContext context) {
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
                color: Colors.blue.shade200.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
            border: Border.all(color: Colors.blue.shade100),
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.lightbulb_outline,
                        color: Colors.blue.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '学習のヒント',
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
              Divider(color: Colors.blue.shade100, height: 24),
              _buildHelpItem(
                icon: Icons.touch_app,
                text: 'カードをタップして、表側と裏側を切り替えることができます',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                icon: Icons.check,
                text: '答えを確認した後、「正解」または「不正解」ボタンで自分の理解度を記録しましょう',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                icon: Icons.refresh,
                text: '学習が終わったら、「もう一度」ボタンで再度学習できます',
              ),
              const SizedBox(height: 12),
              _buildHelpItem(
                icon: Icons.shuffle,
                text: '右上の「シャッフル」ボタンで、カードの順番をランダムに変更できます',
              ),
              const SizedBox(height: 16),
              Center(
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
            ],
          ),
        ),
      );
    },
  );
}

// ヘルプ項目ウィジェット
Widget _buildHelpItem({required IconData icon, required String text}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: Colors.blue.shade700,
        ),
      ),
      const SizedBox(width: 12),
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
