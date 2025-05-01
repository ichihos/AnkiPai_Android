import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/flash_card.dart';
import '../services/flash_card_service.dart';
import 'card_editor_screen.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class CardDetailScreen extends StatefulWidget {
  final String cardId;
  final String? setId;

  const CardDetailScreen({
    super.key,
    required this.cardId,
    this.setId,
  });

  @override
  _CardDetailScreenState createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  bool _isLoading = true;
  bool _isFlipped = false;
  FlashCard? _flashCard;

  @override
  void initState() {
    super.initState();
    _loadFlashCard();
  }

  Future<void> _loadFlashCard() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final flashCardService = Provider.of<FlashCardService>(context, listen: false);
      final flashCard = await flashCardService.getFlashCardById(widget.cardId);

      if (mounted) {
        setState(() {
          _flashCard = flashCard;
          _isLoading = false;
        });
      }

      if (flashCard == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('カードが見つかりませんでした'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カードの読み込みに失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // カードを編集
  Future<void> _editCard() async {
    if (_flashCard == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CardEditorScreen(
          cardId: _flashCard!.id,
          initialFrontText: _flashCard!.frontText,
          initialBackText: _flashCard!.backText,
          setId: widget.setId,
        ),
      ),
    );

    if (result == true) {
      _loadFlashCard();
    }
  }

  // カードを削除
  Future<void> _deleteCard() async {
    if (_flashCard == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カードを削除'),
        content: const Text('このカードを削除してもよろしいですか？この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '削除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final flashCardService = Provider.of<FlashCardService>(context, listen: false);
        await flashCardService.deleteFlashCard(_flashCard!.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('カードを削除しました')),
          );
          Navigator.of(context).pop(true); // 削除完了を親画面に伝えるためにtrueを返す
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('カードの削除に失敗しました: $e'),
              backgroundColor: Colors.red.shade400,
            ),
          );
        }
      }
    }
  }

  // カードを反転させる
  void _toggleCard() {
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('カードの詳細'),
        actions: [
          if (!_isLoading && _flashCard != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editCard,
              tooltip: 'カードを編集',
            ),
          if (!_isLoading && _flashCard != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteCard,
              tooltip: 'カードを削除',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _flashCard == null
              ? const Center(child: Text('カードが見つかりません'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // カード表示部分
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggleCard,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (Widget child, Animation<double> animation) {
                              return RotationTransition(
                                turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildCardContent(),
                          ),
                        ),
                      ),

                      // 操作ガイド
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          'タップしてカードを裏返す',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCardContent() {
    final content = _isFlipped
        ? _flashCard!.backText // 裏面（回答）
        : _flashCard!.frontText; // 表面（質問）
    
    final textColor = _isFlipped ? Colors.blue.shade800 : Colors.grey.shade800;

    return Card(
      key: ValueKey<bool>(_isFlipped),
      color: _isFlipped ? Colors.blue.shade50 : Colors.white,
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: _isFlipped ? Colors.blue.shade200 : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // カードのサイド表示
            Text(
              _isFlipped ? '回答' : '質問',
              style: TextStyle(
                color: _isFlipped ? Colors.blue.shade700 : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
              ),
            ),
            const SizedBox(height: 16.0),
            // カードのコンテンツ
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: _buildMathContent(content, textColor),
                ),
              ),
            ),
          ],
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
    
    // 最初に、ディスプレイモードの数式を処理
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
              textStyle: TextStyle(fontSize: 24, color: textColor),
            ),
          ),
        ),
      );
      
      lastEnd = match.end;
    }
    
    // 残りのテキストを処理
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
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        textAlign: TextAlign.center,
      );
    }
    
    // インライン数式を含むテキストを構築
    List<InlineSpan> spans = [];
    int lastEnd = 0;
    
    for (var match in matches) {
      // 数式の前の通常テキスト
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        ));
      }
      
      // インライン数式
      String formula = text.substring(match.start + 1, match.end - 1); // $...$ の内側
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          formula,
          textStyle: TextStyle(fontSize: 24, color: textColor),
        ),
      ));
      
      lastEnd = match.end;
    }
    
    // 数式の後の通常テキスト
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }
}
