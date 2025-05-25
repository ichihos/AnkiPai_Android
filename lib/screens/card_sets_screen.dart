import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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

            final l10n = AppLocalizations.of(context)!;
            String errorMessage = error.toString();
            // エラーメッセージをユーザーフレンドリーに調整
            if (errorMessage.contains('permission-denied')) {
              errorMessage = l10n.permissionDeniedError;
            } else if (errorMessage.contains('ログイン')) {
              errorMessage = l10n.invalidLoginStateError;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    AppLocalizations.of(context)!.dataLoadFailed(errorMessage)),
                backgroundColor: Colors.red.shade400,
                action: SnackBarAction(
                  label: l10n.loginButtonLabel,
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
          content:
              Text(AppLocalizations.of(context)!.dataLoadFailed(errorMessage)),
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
                Text(AppLocalizations.of(context)!
                    .deletingCardSet(cardSet.title)),
                const SizedBox(height: 4),
                Text(AppLocalizations.of(context)!.pleaseWait,
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
            content: Text(AppLocalizations.of(context)!.cardSetDeleted),
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
            content:
                Text(AppLocalizations.of(context)!.deleteFailed(e.toString())),
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
        title: Text(AppLocalizations.of(context)!.premiumUpgrade),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!.premiumBenefits),
            SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.thinkingModeUnlimited),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.cardSetsUnlimited),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.cardsPerSetUnlimited),
              dense: true,
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.noAdsDisplay),
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
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
                SnackBar(
                  content:
                      Text(AppLocalizations.of(context)!.upgradedToPremium),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text(AppLocalizations.of(context)!.upgrade),
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
            title: Text(AppLocalizations.of(context)!.cardSetLimit),
            content: Text(AppLocalizations.of(context)!
                .cardSetLimitMessage(SubscriptionModel.maxCardSets)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.close),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showPremiumUpgradeDialog();
                },
                child: Text(AppLocalizations.of(context)!.upgrade),
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
        title: Text(AppLocalizations.of(context)!.newCardSet),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.title,
                hintText: AppLocalizations.of(context)!.titleExample,
              ),
              maxLength: 50,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.descriptionOptional,
                hintText: AppLocalizations.of(context)!.descriptionExample,
              ),
              maxLength: 200,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(AppLocalizations.of(context)!.pleaseEnterTitle),
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
            child: Text(AppLocalizations.of(context)!.create),
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
            content: Text(AppLocalizations.of(context)!.cardSetCreated),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.creationFailed(e.toString())),
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
        title: Text(AppLocalizations.of(context)!.editCardSet),
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
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(AppLocalizations.of(context)!.pleaseEnterTitle),
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
            child: Text(AppLocalizations.of(context)!.update),
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
            content: Text(AppLocalizations.of(context)!.cardSetUpdated),
            backgroundColor: Colors.green.shade400,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.updateFailed(e.toString())),
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
                        AppLocalizations.of(context)!.aboutCardSets,
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
                Text(
                  AppLocalizations.of(context)!.cardSetHelpTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    AppLocalizations.of(context)!.cardSetHelpDescription,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      height: 1.5,
                    ),
                  ),
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
                    child:
                        Text(AppLocalizations.of(context)!.cardSetHelpConfirm),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                            AppLocalizations.of(context)!.myCardSets,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          Text(
                            AppLocalizations.of(context)!.cardSetSubtitle,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade900,
                            ),
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            maxLines: 3,
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
                        hintText: AppLocalizations.of(context)!.searchCardSets,
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
                                  AppLocalizations.of(context)!.loadingCardSets,
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
                                            ? AppLocalizations.of(context)!
                                                .noCardSets
                                            : AppLocalizations.of(context)!
                                                .noSearchResults,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _searchQuery.isEmpty
                                            ? AppLocalizations.of(context)!
                                                .createNewCardSetFromButton
                                            : AppLocalizations.of(context)!
                                                .changeSearchCriteria,
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
                                              SnackBar(
                                                content: Text(
                                                    AppLocalizations.of(
                                                            context)!
                                                        .noCardsInSet),
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
                                                    tooltip:
                                                        AppLocalizations.of(
                                                                context)!
                                                            .cardEditTooltip,
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.edit,
                                                      color:
                                                          Colors.blue.shade600,
                                                    ),
                                                    onPressed: () =>
                                                        _editCardSet(cardSet),
                                                    tooltip:
                                                        AppLocalizations.of(
                                                                context)!
                                                            .setEditTooltip,
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.delete,
                                                      color:
                                                          Colors.red.shade400,
                                                    ),
                                                    tooltip:
                                                        AppLocalizations.of(
                                                                context)!
                                                            .deleteTooltip,
                                                    onPressed: () async {
                                                      final confirm =
                                                          await showDialog<
                                                              bool>(
                                                        context: context,
                                                        builder: (context) =>
                                                            AlertDialog(
                                                          title: Text(
                                                              AppLocalizations.of(
                                                                      context)!
                                                                  .deleteCardSetTitle),
                                                          content: Text(
                                                            AppLocalizations.of(
                                                                    context)!
                                                                .deleteCardSetConfirm,
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          context)
                                                                      .pop(
                                                                          false),
                                                              child: Text(
                                                                  AppLocalizations.of(context)!.cancelButton),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          context)
                                                                      .pop(
                                                                          true),
                                                              child: Text(
                                                                AppLocalizations.of(context)!.deleteButton,
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
                                                  )
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
                                                        AppLocalizations.of(
                                                                    context)!
                                                                .lastStudyTime +
                                                            ': ${DateFormat('yyyy/MM/dd HH:mm').format(cardSet.lastStudiedAt!)}',
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
                    label: Text(AppLocalizations.of(context)!.createNew),
                  )
                ]))));
  }
}
