import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/flash_card.dart';
import '../services/flash_card_service.dart';
import '../services/auth_service.dart';
import 'create_flash_card_screen.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class FlashCardScreen extends StatefulWidget {
  const FlashCardScreen({super.key});

  @override
  _FlashCardScreenState createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  List<FlashCard> _flashCards = [];
  bool _isLoading = true;
  final FlashCardService _flashCardService = FlashCardService();
  StreamSubscription<List<FlashCard>>? _flashCardsSubscription;

  @override
  void initState() {
    super.initState();
    _setupFlashCardsListener();
  }

  // リアルタイムリスナーのセットアップ
  Future<void> _setupFlashCardsListener() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // ユーザーがログインしているか確認
      final user = authService.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません。';
      }
      
      // トークンをリフレッシュ
      final isValidAuth = await authService.validateAuthentication();
      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }
      
      // リアルタイムでフラッシュカードを監視するストリームを取得
      final flashCardsStream = await _flashCardService.watchFlashCards();
      
      // 既存のサブスクリプションがあればキャンセル
      _flashCardsSubscription?.cancel();
      
      // 新しいサブスクリプションを設定
      _flashCardsSubscription = flashCardsStream.listen(
        (cards) {
          if (mounted) {
            setState(() {
              _flashCards = cards;
              _isLoading = false;
            });
          }
        },
        onError: (error) {
          print('フラッシュカードの監視エラー: $error');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            
            // エラーメッセージをユーザーフレンドリーに調整
            String errorMessage = error.toString();
            if (errorMessage.contains('permission-denied')) {
              errorMessage = 'アクセス権限がありません。再度ログインして試してください。';
            } else if (errorMessage.contains('ログイン')) {
              errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.flashCardMonitoringFailed(errorMessage)),
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
      print('フラッシュカードの監視セットアップエラー: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // エラーメッセージをユーザーフレンドリーに調整
        String errorMessage = e.toString();
        if (errorMessage.contains('permission-denied')) {
          errorMessage = 'アクセス権限がありません。再度ログインして試してください。';
        } else if (errorMessage.contains('ログイン')) {
          errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.flashCardMonitoringSetupFailed(errorMessage)),
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
  
  // 非同期でのフラッシュカード読み込み（バックアップメソッド）
  Future<void> _loadFlashCards() async {
    // ウィジェットがまだツリーに存在するか確認
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // ユーザーがログインしているか確認
      final user = authService.currentUser;
      if (user == null) {
        throw 'ユーザーがログインしていません。';
      }
      
      // トークンをリフレッシュ
      final isValidAuth = await authService.validateAuthentication();
      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }
      
      // Firestoreからデータを一度だけ取得
      final cards = await _flashCardService.getFlashCards();

      // setStateを呼び出す前にmountedを確認
      if (!mounted) return;
      
      setState(() {
        _flashCards = cards;
        _isLoading = false;
      });
    } catch (e) {
      print('フラッシュカードの読み込みエラー: $e');
      
      // setStateを呼び出す前にmountedを確認
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });

      // エラーメッセージをユーザーフレンドリーに調整
      String errorMessage = e.toString();
      if (errorMessage.contains('permission-denied')) {
        errorMessage = 'アクセス権限がありません。再度ログインして試してください。';
      } else if (errorMessage.contains('ログイン')) {
        errorMessage = 'ログイン状態が無効です。再度ログインしてください。';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.flashCardLoadingFailed(errorMessage)),
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

  @override
  void dispose() {
    // ウィジェットが破棄されるときにリスナーをキャンセル
    _flashCardsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _flashCards.isEmpty
              ? _buildEmptyState()
              : _buildFlashCardsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateFlashCardScreen(),
            ),
          );

          if (result == true) {
            // リアルタイムリスナーが設定されているため、手動で更新する必要はありません
            // 念のためリスナーの再接続を試みる
            _setupFlashCardsListener();
          }
        },
        backgroundColor: Colors.blue.shade600,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.card_membership,
            size: 80,
            color: Colors.blue.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            '暗記カードがありません',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '右下の + ボタンから暗記カードを追加してください',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashCardsList() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _flashCards.length + 1, // +1 for the "add new" card
      itemBuilder: (context, index) {
        // Last item is the "add new" card
        if (index == _flashCards.length) {
          return _buildAddNewCard();
        }

        final card = _flashCards[index];
        return _buildFlashCard(card);
      },
    );
  }

  Widget _buildFlashCard(FlashCard card) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      child: InkWell(
        onTap: () {
          _showFlashCardDetail(card);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    card.frontText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Divider(color: Colors.blue.shade100),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${card.createdAt.month}/${card.createdAt.day}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Icon(
                    Icons.touch_app,
                    size: 16,
                    color: Colors.blue.shade300,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddNewCard() {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.shade100,
          width: 1,
        ),
      ),
      child: DottedBorder(
        borderType: BorderType.RRect,
        radius: const Radius.circular(16),
        padding: EdgeInsets.zero,
        color: Colors.blue.shade300,
        strokeWidth: 1,
        dashPattern: const [6, 3],
        child: InkWell(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateFlashCardScreen(),
              ),
            );

            if (result == true) {
              _loadFlashCards();
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 40,
                color: Colors.blue.shade300,
              ),
              const SizedBox(height: 8),
              Text(
                '新しい暗記カード',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TeX数式を含むテキストを正しく表示するメソッド
  Widget _buildMathContent(String content, Color textColor) {
    // 数式と通常テキストを分離する正規表現
    // $...$と$$...$$の両方をサポート
    final RegExp displayMathRegExp = RegExp(r'\$\$(.*?)\$\$', dotAll: true);
    
    // 分割用のリスト
    List<Widget> contentWidgets = [];
    
    // 最初に、ディスプレイモードの数式を处理
    List<RegExpMatch> displayMatches = displayMathRegExp.allMatches(content).toList();
    
    int lastEnd = 0;
    for (var match in displayMatches) {
      // 数式の前のテキスト
      if (match.start > lastEnd) {
        String textBefore = content.substring(lastEnd, match.start);
        contentWidgets.add(_processInlineMath(textBefore, textColor));
      }
      
      // ディスプレイモードの数式
      String formula = content.substring(match.start + 2, match.end - 2); // $$...$$ の内側
      contentWidgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Math.tex(
              formula,
              textStyle: TextStyle(fontSize: 18, color: textColor),
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
        style: TextStyle(fontSize: 18, color: textColor, fontWeight: FontWeight.bold),
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
            style: TextStyle(fontSize: 18, color: textColor, fontWeight: FontWeight.bold),
          ),
        );
      }
      
      // インライン数式
      String formula = text.substring(match.start + 1, match.end - 1); // $...$ の内側
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            formula,
            textStyle: TextStyle(fontSize: 18, color: textColor),
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
          style: TextStyle(fontSize: 18, color: textColor, fontWeight: FontWeight.bold),
        ),
      );
    }
    
    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  void _showFlashCardDetail(FlashCard card) {
    bool isShowingFront = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isShowingFront = !isShowingFront;
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        height: 200,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isShowingFront
                              ? Colors.blue.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isShowingFront
                                ? Colors.blue.shade200
                                : Colors.green.shade200,
                          ),
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            child: _buildMathContent(
                              isShowingFront ? card.frontText : card.backText,
                              isShowingFront ? Colors.blue.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'カードをタップして${isShowingFront ? '裏面' : '表面'}を見る',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            // TODO: 編集機能を実装
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: Text(AppLocalizations.of(context)!.edit),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            side: BorderSide(color: Colors.blue.shade200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            // TODO: 削除機能を実装
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.delete, size: 18),
                          label: Text(AppLocalizations.of(context)!.delete),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
