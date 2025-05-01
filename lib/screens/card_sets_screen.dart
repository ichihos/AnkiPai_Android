import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/card_set.dart';
import '../models/subscription_model.dart';
import '../services/card_set_service.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import 'card_set_detail_screen.dart';
import 'card_study_screen.dart';

class CardSetsScreen extends StatefulWidget {
  const CardSetsScreen({super.key});

  @override
  _CardSetsScreenState createState() => _CardSetsScreenState();
}

class _CardSetsScreenState extends State<CardSetsScreen> {
  bool _isLoading = true;
  List<CardSet> _cardSets = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // サブスクリプション情報
  SubscriptionModel? _subscription;
  bool _isSubscriptionLoading = true;

  // ストリーム購読管理用
  StreamSubscription<List<CardSet>>? _cardSetsSubscription;

  @override
  void initState() {
    super.initState();
    _loadCardSets();
    _loadSubscriptionInfo();
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
    _cardSetsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCardSets() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 既存の購読があればキャンセル
      await _cardSetsSubscription?.cancel();

      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      final isValidAuth = await authService.validateAuthentication();

      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }

      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);

      // リアルタイム監視の設定
      final cardSetsStream = await cardSetService.watchCardSets();

      _cardSetsSubscription = cardSetsStream.listen(
        (items) {
          if (mounted) {
            setState(() {
              _cardSets = items;
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

  // 検索クエリでフィルタリングされたアイテムを取得
  List<CardSet> get _filteredItems {
    if (_searchQuery.isEmpty) {
      return _cardSets;
    }

    final query = _searchQuery.toLowerCase();
    return _cardSets.where((item) {
      return item.title.toLowerCase().contains(query) ||
          (item.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  // カードセットを削除
  Future<void> _deleteCardSet(CardSet cardSet) async {
    // 削除中のローディングダイアログを表示
    showDialog(
      context: context,
      barrierDismissible: false, // ユーザーがダイアログを閉じられないようにする
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('「${cardSet.title}」を削除中...'),
                const SizedBox(height: 4),
                const Text('しばらくお待ちください',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );

    try {
      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);
      await cardSetService.deleteCardSet(cardSet.id);

      // ダイアログを閉じる
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('カードセットを削除しました'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      }
    } catch (e) {
      // ダイアログを閉じる
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
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

  // 新しいカードセットを作成
  Future<void> _createCardSet() async {
    // フリープランの制限チェック
    if (!_isSubscriptionLoading &&
        _subscription != null &&
        !_subscription!.isPremium) {
      if (_cardSets.length >= SubscriptionModel.maxCardSets) {
        // 制限に達している場合はプレミアム案内ダイアログを表示
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('カードセット数の制限'),
            content: const Text(
                '無料プランでは最大${SubscriptionModel.maxCardSets}つまでのカードセットしか作成できません。プレミアムプランにアップグレードすると、無制限に作成できます。'),
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

    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しいカードセットを作成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
                hintText: '例: 英単語帳',
              ),
              maxLength: 50,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: '説明 (オプション)',
                hintText: '例: 日常会話で使う単語',
              ),
              maxLength: 200,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('タイトルを入力してください'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(context).pop({
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim().isNotEmpty
                    ? descriptionController.text.trim()
                    : null,
              });
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final cardSetService =
            Provider.of<CardSetService>(context, listen: false);
        await cardSetService.addCardSet(
          result['title']!,
          description: result['description'],
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('カードセットを作成しました'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('作成に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // カードセットを編集
  Future<void> _editCardSet(CardSet cardSet) async {
    final titleController = TextEditingController(text: cardSet.title);
    final descriptionController =
        TextEditingController(text: cardSet.description ?? '');

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カードセットを編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'タイトル',
              ),
              maxLength: 50,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: '説明 (オプション)',
              ),
              maxLength: 200,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('タイトルを入力してください'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(context).pop({
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim().isNotEmpty
                    ? descriptionController.text.trim()
                    : null,
              });
            },
            child: const Text('更新'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final cardSetService =
            Provider.of<CardSetService>(context, listen: false);
        await cardSetService.updateCardSet(
          cardSet.id,
          title: result['title'],
          description: result['description'],
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('カードセットを更新しました'),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // ヘルプポップアップを表示
  void _showCardSetHelpPopup() {
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
                      child: Icon(Icons.help_outline,
                          color: Colors.blue.shade700, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'カードセットについて',
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
                  icon: Icons.create_new_folder_outlined,
                  text: 'カードセットは関連するカードをまとめる便利な方法です',
                ),
                const SizedBox(height: 12),
                _buildHelpItem(
                  icon: Icons.category_outlined,
                  text: '科目、トピック、分野ごとにカードセットを作成できます',
                ),
                const SizedBox(height: 12),
                _buildHelpItem(
                  icon: Icons.shuffle,
                  text: 'カードセット内のカードはランダムに表示したり、順番に学習したりできます',
                ),
                const SizedBox(height: 12),
                _buildHelpItem(
                  icon: Icons.timeline,
                  text: '学習の進捗状況はカードセットごとに記録されます',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.transparent, // 透明な背景
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
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  // ヘッダー部分
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'マイカードセット',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          Text(
                            '覚えたい内容をカードにまとめよう',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.help_outline,
                            color: Colors.blue.shade600),
                        onPressed: _showCardSetHelpPopup,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 検索バー
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: Colors.blue.shade100, width: 1),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'カードセットを検索...',
                        prefixIcon:
                            Icon(Icons.search, color: Colors.blue.shade400),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 15),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // カードセット一覧（空の場合と読み込み中の場合の処理）
                  Expanded(
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'カードセットを読み込み中...',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _filteredItems.isEmpty
                            ? Center(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
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
                                          Icons.folder_open,
                                          size: 64,
                                          color: Colors.blue.shade300,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        _searchQuery.isEmpty
                                            ? 'カードセットがありません'
                                            : '検索結果が見つかりませんでした',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _searchQuery.isEmpty
                                            ? '「＋」ボタンから新しいカードセットを作成しましょう'
                                            : '検索条件を変更してみてください',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.blue.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  final cardSet = _filteredItems[index];
                                  // 色の配列
                                  final colors = [
                                    Colors.blue.shade100,
                                    Colors.green.shade100,
                                    Colors.purple.shade100,
                                    Colors.orange.shade100,
                                    Colors.pink.shade100,
                                  ];
                                  // インデックスに基づいて色を選択（循環）
                                  final color = colors[index % colors.length];
                                  final iconData = [
                                    Icons.folder,
                                    Icons.book,
                                    Icons.school,
                                    Icons.psychology,
                                    Icons.science,
                                  ][index % 5];

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.5),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                      border:
                                          Border.all(color: color, width: 1),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          // カードがない場合は通知を表示
                                          if (cardSet.cardCount <= 0) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content:
                                                    Text('このカードセットにはカードがありません'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            return;
                                          }

                                          // カードがある場合は学習を開始
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  CardStudyScreen(
                                                cardSetId: cardSet.id,
                                                cardSetTitle: cardSet.title,
                                              ),
                                            ),
                                          );

                                          // 最終学習日を更新（非同期で行い、エラーは無視）
                                          Future.delayed(Duration.zero,
                                              () async {
                                            try {
                                              final cardSetService =
                                                  Provider.of<CardSetService>(
                                                      context,
                                                      listen: false);
                                              await cardSetService
                                                  .updateCardSetLastStudied(
                                                      cardSet.id);
                                            } catch (_) {}
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            10),
                                                    decoration: BoxDecoration(
                                                      color: color
                                                          .withOpacity(0.5),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Icon(
                                                      iconData,
                                                      color:
                                                          Colors.blue.shade800,
                                                      size: 24,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      cardSet.title,
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .blue.shade900,
                                                      ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.edit_note,
                                                      color:
                                                          Colors.blue.shade600,
                                                    ),
                                                    onPressed: () {
                                                      Navigator.of(context)
                                                          .push(
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              CardSetDetailScreen(
                                                            cardSetId:
                                                                cardSet.id,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    tooltip: 'カード編集',
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.edit,
                                                      color:
                                                          Colors.blue.shade600,
                                                    ),
                                                    onPressed: () =>
                                                        _editCardSet(cardSet),
                                                    tooltip: '編集',
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.delete,
                                                      color:
                                                          Colors.red.shade400,
                                                    ),
                                                    onPressed: () async {
                                                      final confirm =
                                                          await showDialog<
                                                              bool>(
                                                        context: context,
                                                        builder: (context) =>
                                                            AlertDialog(
                                                          title: const Text(
                                                              'カードセットを削除'),
                                                          content: Text(
                                                            '「${cardSet.title}」を削除しますか？\n含まれるすべてのカードも削除されます。',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          context)
                                                                      .pop(
                                                                          false),
                                                              child: const Text(
                                                                  'キャンセル'),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          context)
                                                                      .pop(
                                                                          true),
                                                              child: const Text(
                                                                '削除',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .red),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm == true) {
                                                        await _deleteCardSet(
                                                            cardSet);
                                                      }
                                                    },
                                                    tooltip: '削除',
                                                  ),
                                                ],
                                              ),
                                              if (cardSet.description != null &&
                                                  cardSet
                                                      .description!.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 12, left: 46),
                                                  child: Text(
                                                    cardSet.description!,
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade800,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16, left: 46),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.blue.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                          color: Colors
                                                              .blue.shade100,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.credit_card,
                                                            size: 16,
                                                            color: Colors
                                                                .blue.shade700,
                                                          ),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            'カード: ${cardSet.cardCount}',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: Colors.blue
                                                                  .shade700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.grey.shade50,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                          color: Colors
                                                              .grey.shade200,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .calendar_today,
                                                            size: 14,
                                                            color: Colors
                                                                .grey.shade700,
                                                          ),
                                                          const SizedBox(
                                                              width: 4),
                                                          Text(
                                                            DateFormat(
                                                                    'yyyy/MM/dd')
                                                                .format(cardSet
                                                                    .createdAt),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey
                                                                  .shade700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (cardSet.lastStudiedAt != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8, left: 46),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.history,
                                                        color: Colors
                                                            .blue.shade400,
                                                        size: 14,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '最終学習: ${DateFormat('yyyy/MM/dd HH:mm').format(cardSet.lastStudiedAt!)}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .blue.shade400,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),

                  // 新規作成ボタン
                  FloatingActionButton.extended(
                    onPressed: _createCardSet,
                    backgroundColor: Colors.blue.shade500,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    icon: const Icon(Icons.add),
                    label: const Text('新規作成'),
                  )
                ]))));
  }
}
