import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import '../models/card_set.dart';
import '../models/flash_card.dart';
import '../models/subscription_model.dart';
import '../services/card_set_service.dart';
import '../services/flash_card_service.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/ad_service.dart';
import 'card_editor_screen.dart';
import 'card_detail_screen.dart';
import 'card_study_screen.dart';

class CardSetDetailScreen extends StatefulWidget {
  final String cardSetId;

  const CardSetDetailScreen({
    super.key,
    required this.cardSetId,
  });

  @override
  _CardSetDetailScreenState createState() => _CardSetDetailScreenState();
}

class _CardSetDetailScreenState extends State<CardSetDetailScreen> {
  bool _isLoading = true;
  CardSet? _cardSet;
  List<FlashCard> _cards = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // サブスクリプション情報
  SubscriptionModel? _subscription;
  bool _isSubscriptionLoading = true;

  // ストリーム購読管理用
  StreamSubscription<CardSet?>? _cardSetSubscription;
  StreamSubscription<List<FlashCard>>? _cardsSubscription;

  // 広告関連
  final AdService _adService = GetIt.instance<AdService>();
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCardSetAndCards();
    _loadSubscriptionInfo();
    _loadBannerAd();
  }

  // サブスクリプション情報を読み込む
  Future<void> _loadSubscriptionInfo() async {
    setState(() {
      _isSubscriptionLoading = true;
    });

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      final subscription = await subscriptionService.getUserSubscription();

      if (mounted) {
        setState(() {
          _subscription = subscription;
          _isSubscriptionLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubscriptionLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // ストリーム購読の解除
    _cardSetSubscription?.cancel();
    _cardsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // バナー広告をロード
  Future<void> _loadBannerAd() async {
    if (!mounted) return;

    try {
      // 広告表示の準備が整うまで少し遅延
      await Future.delayed(const Duration(seconds: 2));

      await _adService.loadBannerAd();
      if (mounted) {
        setState(() {
          _isBannerAdLoaded = true;
        });
      }
    } catch (e) {
      print('バナー広告のロード中にエラーが発生しました: $e');
    }
  }

  Future<void> _loadCardSetAndCards() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 既存の購読があればキャンセル
      await _cardSetSubscription?.cancel();
      await _cardsSubscription?.cancel();

      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      final isValidAuth = await authService.validateAuthentication();

      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }

      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);

      // カードセットの詳細を取得
      final cardSetStream = await cardSetService.watchCardSet(widget.cardSetId);
      _cardSetSubscription = cardSetStream.listen(
        (cardSet) {
          if (mounted) {
            setState(() {
              _cardSet = cardSet;
              if (cardSet == null) {
                // カードセットが削除された場合は前の画面に戻る
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('このカードセットは削除されました'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            });
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('カードセット情報の取得に失敗しました: $error'),
                backgroundColor: Colors.red.shade400,
              ),
            );
            Navigator.of(context).pop();
          }
        },
      );

      // カードセット内のカードを取得
      final cardsStream =
          await cardSetService.watchCardsInSet(widget.cardSetId);
      _cardsSubscription = cardsStream.listen(
        (cards) {
          if (mounted) {
            setState(() {
              _cards = cards;
              _isLoading = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('カード情報の取得に失敗しました: $error'),
                backgroundColor: Colors.red.shade400,
              ),
            );
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('データの読み込みに失敗しました: $e'),
          backgroundColor: Colors.red.shade400,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  // 検索クエリでフィルタリングされたカードを取得
  List<FlashCard> get _filteredCards {
    if (_searchQuery.isEmpty) {
      return _cards;
    }

    final query = _searchQuery.toLowerCase();
    return _cards.where((card) {
      return card.frontText.toLowerCase().contains(query) ||
          card.backText.toLowerCase().contains(query);
    }).toList();
  }

  // プレミアムにアップグレードダイアログを表示
  void _showPremiumUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プレミアムプランへのアップグレード'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('プレミアムプランでは以下の特典があります:'),
            SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text('考え方モードとマルチエージェントモードが無制限'),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text('カードセット数無制限'),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text('各カードセットのカード枚数無制限'),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text('広告の非表示'),
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // 仮実装: 実際の決済処理は後で実装
              final subscriptionService =
                  Provider.of<SubscriptionService>(context, listen: false);
              await subscriptionService.upgradeToPremium();
              await _loadSubscriptionInfo();

              // 成功メッセージ
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('プレミアムプランにアップグレードしました！'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('アップグレード'),
          ),
        ],
      ),
    );
  }

  // 新しいフラッシュカードを追加
  Future<void> _addNewCard() async {
    if (_cardSet == null) return;

    // フリープランの制限チェック
    if (!_isSubscriptionLoading &&
        _subscription != null &&
        !_subscription!.isPremium) {
      if (_cards.length >= SubscriptionModel.maxCardsPerSet) {
        // 制限に達している場合はプレミアム案内ダイアログを表示
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('カード枚数の制限'),
            content: const Text(
                '無料プランでは各カードセットに最大${SubscriptionModel.maxCardsPerSet}枚までのカードしか作成できません。プレミアムプランにアップグレードすると、無制限に作成できます。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showPremiumUpgradeDialog();
                },
                child: const Text('アップグレード'),
              ),
            ],
          ),
        );
        return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CardEditorScreen(
          setId: widget.cardSetId,
        ),
      ),
    );
  }

  // フラッシュカードを編集
  Future<void> _editCard(FlashCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CardEditorScreen(
          cardId: card.id,
          initialFrontText: card.frontText,
          initialBackText: card.backText,
          setId: widget.cardSetId,
        ),
      ),
    );
  }

  // フラッシュカードを削除
  Future<void> _deleteCard(FlashCard card) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カードを削除'),
        content: const Text('このカードを削除しますか？'),
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
      try {
        final flashCardService =
            Provider.of<FlashCardService>(context, listen: false);
        await flashCardService.deleteFlashCard(card.id);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('カードを削除しました'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // カードセットで学習を開始
  Future<void> _startStudySession() async {
    if (_cardSet == null || _cards.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CardStudyScreen(
          cardSetId: widget.cardSetId,
          cardSetTitle: _cardSet!.title,
        ),
      ),
    );

    // カードセット情報を更新（最終学習日を更新するため）
    final cardSetService = Provider.of<CardSetService>(context, listen: false);
    await cardSetService.updateCardSetLastStudied(widget.cardSetId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(_cardSet?.title ?? 'カードセット詳細'),
            ),
            // プレミアムバッジ
            if (!_isSubscriptionLoading &&
                _subscription != null &&
                _subscription!.isPremium)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.white, size: 12),
                    SizedBox(width: 2),
                    Text('プレミアム',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
        backgroundColor: const Color.fromARGB(255, 53, 152, 71),
        foregroundColor: Colors.white,
        actions: [
          if (_cardSet != null && _cards.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.school),
              onPressed: _startStudySession,
              tooltip: '学習開始',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cardSet == null
              ? const Center(child: Text('カードセットが見つかりません'))
              : Column(
                  children: [
                    // カードセット情報
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cardSet!.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_cardSet!.description != null &&
                                _cardSet!.description!.isNotEmpty)
                              Text(
                                _cardSet!.description!,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.style,
                                    size: 16, color: Colors.green.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'カード数: ${_cardSet!.cardCount}',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 学習スタートボタン - よりコンパクトなデザイン
                    if (_cards.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color.fromARGB(255, 62, 175, 83)
                                  .withOpacity(0.1),
                              const Color.fromARGB(255, 141, 176, 84)
                                  .withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color.fromARGB(255, 62, 175, 83)
                                  .withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 65, 186, 87)
                                    .withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.school,
                                color: Color.fromARGB(255, 68, 187, 90),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'このセットで学習を始める',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color.fromARGB(255, 62, 175, 83),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _startStudySession,
                              icon: const Icon(Icons.play_circle_filled,
                                  size: 28),
                              label: const Text('スタート',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(255, 62, 175, 83),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 18),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 検索バー
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'カードを検索...',
                          prefixIcon:
                              Icon(Icons.search, color: Colors.orange.shade400),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.orange.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.orange.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.orange.shade400, width: 2),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          filled: true,
                          fillColor: Colors.orange.shade50.withOpacity(0.5),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),

                    // カード一覧
                    Expanded(
                      child: _filteredCards.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.note_alt_outlined,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'カードがありません'
                                        : '検索結果が見つかりませんでした',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_searchQuery.isEmpty)
                                    ElevatedButton.icon(
                                      onPressed: _addNewCard,
                                      icon: const Icon(Icons.add),
                                      label: const Text('カードを追加'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80), // 下部に広告のスペースを確保
                              itemCount: _filteredCards.length,
                              itemBuilder: (context, index) {
                                final card = _filteredCards[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CardDetailScreen(
                                            cardId: card.id,
                                            setId: widget.cardSetId,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildMathContentPreview(
                                                  card.frontText,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit),
                                                onPressed: () =>
                                                    _editCard(card),
                                                tooltip: '編集',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete),
                                                onPressed: () =>
                                                    _deleteCard(card),
                                                tooltip: '削除',
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          _buildMathContentPreview(
                                            card.backText,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                            ),
                                            maxLines: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // 広告表示エリア
                    if (!_isSubscriptionLoading && _subscription != null && !_subscription!.isPremium && _isBannerAdLoaded)
                      Container(
                        alignment: Alignment.center,
                        color: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _adService.getBannerAdWidget(),
                      ),
                  ],
                ),
      floatingActionButton: _cardSet != null
          ? FloatingActionButton(
              onPressed: _addNewCard,
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // TeX数式対応のテキストプレビューを表示するウィジェット
  Widget _buildMathContentPreview(
    String content, {
    required TextStyle style,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    // リスト表示のプレビュー内の場合は簡易表示を済ます
    if (maxLines < 3) {
      // 数式が含まれているか簡易チェック
      if (content.contains(r'$')) {
        final RegExp mathRegExp = RegExp(r'\$(.*?)\$', dotAll: true);
        List<RegExpMatch> matches = mathRegExp.allMatches(content).toList();

        if (matches.isEmpty) {
          // 数式がない場合は通常テキスト
          return Text(
            content,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          );
        }

        // 水平リスト内のプレビューの場合は数式アイコンを表示する簡易版
        return Row(
          children: [
            Icon(Icons.functions, size: 16, color: Colors.purple.shade400),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                content.replaceAll(mathRegExp, '[数式]'),
                style: style,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
              ),
            ),
          ],
        );
      } else {
        // 数式がない場合は通常テキスト
        return Text(
          content,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
      }
    }

    // 詳細表示の場合は実際に数式をレンダリング
    // 数式と通常テキストを分離する正規表現
    final RegExp displayMathRegExp = RegExp(r'\$\$(.*?)\$\$', dotAll: true);

    // 分割用のリスト
    List<Widget> contentWidgets = [];

    // 最初に、ディスプレイモードの数式を処理
    List<RegExpMatch> displayMatches =
        displayMathRegExp.allMatches(content).toList();

    int lastEnd = 0;
    for (var match in displayMatches) {
      // 数式の前のテキスト
      if (match.start > lastEnd) {
        String textBefore = content.substring(lastEnd, match.start);
        contentWidgets.add(_processInlineMath(textBefore, style));
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
              textStyle: style,
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    // 残りのテキストを処理
    if (lastEnd < content.length) {
      String remainingText = content.substring(lastEnd);
      contentWidgets.add(_processInlineMath(remainingText, style));
    }

    // 数式がない場合は単純にインライン数式処理を適用
    if (contentWidgets.isEmpty) {
      contentWidgets.add(_processInlineMath(content, style));
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: contentWidgets,
      ),
    );
  }

  // インライン数式の処理
  Widget _processInlineMath(String text, TextStyle style) {
    // $...$ 形式のインライン数式を探す
    final RegExp inlineMathRegExp = RegExp(r'\$(.*?)\$', dotAll: true);
    List<RegExpMatch> matches = inlineMathRegExp.allMatches(text).toList();

    if (matches.isEmpty) {
      // 数式がない場合は通常のテキストとして表示
      return Text(
        text,
        style: style,
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
          style: style,
        ));
      }

      // インライン数式
      String formula =
          text.substring(match.start + 1, match.end - 1); // $...$ の内側
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          formula,
          textStyle: style,
        ),
      ));

      lastEnd = match.end;
    }

    // 数式の後の通常テキスト
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.start,
    );
  }
}
