import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/memory_item.dart';
import '../models/memory_technique.dart';
import '../services/memory_service.dart';
import '../services/auth_service.dart';
import 'memory_method_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  _LibraryScreenState createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _isLoading = true;
  List<MemoryItem> _memoryItems = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ストリーム購読管理用
  StreamSubscription<List<MemoryItem>>? _memoryItemsSubscription;

  // 最近公開された暗記法
  MemoryTechnique? _recentPublicTechnique;
  bool _isLoadingPublicTechnique = true;

  // 自分の暗記法
  List<MemoryTechnique> _userMemoryTechniques = [];

  // 自分が公開した暗記法
  List<MemoryTechnique> _userPublishedTechniques = [];
  bool _isLoadingUserPublishedTechniques = false;

  // 他のユーザーの公開覚え方の検索結果
  List<MemoryTechnique> _searchedPublicTechniques = [];
  bool _isSearchingPublicTechniques = false;

  @override
  void initState() {
    super.initState();
    _loadMemoryItems();
    _loadRecentPublicTechnique(); // 公開された覚え方はボタンで表示するためここで取得
    _loadUserMemoryTechniques();
    _loadUserPublishedTechniques(); // 自分が公開した覚え方をロード
  }

  @override
  void dispose() {
    // ストリーム購読の解除
    _memoryItemsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMemoryItems() async {
    // mountedプロパティの確認を追加
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 既存の購読があればキャンセル
      await _memoryItemsSubscription?.cancel();

      // 認証状態を確認
      final authService = Provider.of<AuthService>(context, listen: false);
      final isValidAuth = await authService.validateAuthentication();

      if (!isValidAuth) {
        throw '認証状態が無効です。再度ログインしてください。';
      }

      final memoryService = Provider.of<MemoryService>(context, listen: false);

      // リアルタイム監視の設定
      final memoryItemsStream = await memoryService.watchMemoryItems();

      _memoryItemsSubscription = memoryItemsStream.listen(
        (items) {
          if (mounted) {
            setState(() {
              _memoryItems = items;
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
      // mountedプロパティの確認を追加
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

  // 検索クエリでフィルタリングされたアイテム、公開された覚え方、自分の覚え方を取得
  List<MemoryItem> get _filteredItems {
    if (_searchQuery.isEmpty) {
      return _memoryItems;
    }

    final query = _searchQuery.toLowerCase();
    return _memoryItems.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.content.toLowerCase().contains(query);
    }).toList();
  }

  // 検索に一致する公開された覚え方があるかどうか
  bool get _hasMatchingPublicTechnique {
    if (_searchQuery.isEmpty || _recentPublicTechnique == null) {
      return false;
    }

    final query = _searchQuery.toLowerCase();
    return _recentPublicTechnique!.name.toLowerCase().contains(query) ||
        _recentPublicTechnique!.description.toLowerCase().contains(query);
  }

  // 検索に一致する自分の覚え方があるかどうか
  bool get _hasMatchingUserTechniques {
    if (_searchQuery.isEmpty || _userMemoryTechniques.isEmpty) {
      return false;
    }

    final query = _searchQuery.toLowerCase();
    return _userMemoryTechniques.any((technique) {
      return technique.name.toLowerCase().contains(query) ||
          technique.description.toLowerCase().contains(query);
    });
  }

  // 最近公開された暗記法を取得
  Future<void> _loadRecentPublicTechnique() async {
    setState(() {
      _isLoadingPublicTechnique = true;
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      // Firestoreから最近の暗記法を1件取得
      final technique = await memoryService.getRecentPublicTechnique();

      if (mounted) {
        setState(() {
          _recentPublicTechnique = technique;
          _isLoadingPublicTechnique = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recentPublicTechnique = null;
          _isLoadingPublicTechnique = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('最近の暗記法の取得に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // 自分が公開した覚え方ダイアログを表示
  void _showPublishedTechniquesDialog() async {
    setState(() {
      _isLoadingUserPublishedTechniques = true;
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      final userPublishedTechniques =
          await memoryService.getUserPublishedTechniques();

      if (!mounted) return;

      setState(() {
        _userPublishedTechniques = userPublishedTechniques;
        _isLoadingUserPublishedTechniques = false;
      });

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ダイアログヘッダー
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '自分が公開した覚え方',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 検索ボックス（ダイアログ内でも検索可能に）
                if (_searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '「$_searchQuery」で検索中',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                // 自分が公開した覚え方のコンテンツ
                _isLoadingUserPublishedTechniques
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.green.shade600),
                          ),
                        ),
                      )
                    : _userPublishedTechniques.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Text(
                                '公開した覚え方はまだありません',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              ..._getFilteredUserPublishedTechniques()
                                  .map((technique) {
                                return _buildMemoryTechniqueCard(technique);
                              }),
                            ],
                          ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingUserPublishedTechniques = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('公開覚え方の読み込みに失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // ユーザーの暗記法を取得
  Future<void> _loadUserMemoryTechniques() async {
    if (!mounted) return;

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      // Firestoreからユーザーの暗記法を取得
      final techniques = await memoryService.getUserMemoryTechniques();

      if (mounted) {
        setState(() {
          _userMemoryTechniques = techniques;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userMemoryTechniques = [];
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('自分の暗記法の取得に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // メモリーアイテムを削除
  Future<void> _deleteMemoryItem(MemoryItem item) async {
    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      await memoryService.deleteMemoryItem(item.id);

      setState(() {
        _memoryItems.removeWhere((i) => i.id == item.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('項目を削除しました'),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          // 検索欄と公開暗記法ボタン
          Row(
            children: [
              // 検索バー
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.blue.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade100.withOpacity(0.2),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: '覚え方を検索...',
                        hintStyle: TextStyle(color: Colors.blue.shade300),
                        prefixIcon:
                            Icon(Icons.search, color: Colors.blue.shade500),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon:
                                    const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
              // 公開暗記法ボタン
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  onPressed: () => _showPublishedTechniquesDialog(),
                  icon: Icon(
                    Icons.public,
                    color: Colors.green.shade700,
                    size: 28,
                  ),
                  tooltip: '公開された覚え方',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green.shade50,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 検索結果セクションまたは通常のコンテンツ
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadMemoryItems,
                    color: Colors.blue.shade600,
                    child: ListView(
                      padding: const EdgeInsets.only(
                          top: 8, left: 16, right: 16, bottom: 16),
                      children: [
                        // 他の人の公開覚え方（1件表示）
                        if (_recentPublicTechnique != null &&
                            (_searchQuery.isEmpty ||
                                _hasMatchingPublicTechnique))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '他の人の覚え方',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ),
                              _buildRecentPublicTechniqueCard(),
                              const SizedBox(height: 16),
                            ],
                          ),

                        // 自分の暗記法セクションは表示しないように削除しました
                        // 公開済みの覚え方は右上のボタンから確認できます

                        // メモリーアイテムリスト
                        if (_filteredItems.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '自分の覚え方',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                              ..._filteredItems
                                  .map((item) => _buildMemoryItemCard(item)),
                            ],
                          )
                        else if (_searchQuery.isNotEmpty &&
                            !_hasMatchingUserTechniques &&
                            !_hasMatchingPublicTechnique)
                          _buildEmptyState(),

                        // 他の人の覚え方から検索ボタン
                        if (_searchQuery.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: _isSearchingPublicTechniques
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _searchedPublicTechniques.isEmpty
                                    ? ElevatedButton.icon(
                                        onPressed: _searchPublicTechniques,
                                        icon: const Icon(Icons.public),
                                        label:
                                            Text('他の人の覚え方から「$_searchQuery」を検索'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.green.shade100,
                                          foregroundColor:
                                              Colors.green.shade800,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: Text(
                                              '他の人の覚え方検索結果',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                          ),
                                          ..._searchedPublicTechniques
                                              .map((technique) {
                                            return _buildMemoryTechniqueCard(
                                                technique);
                                          }),
                                        ],
                                      ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // 空の状態表示
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books,
            size: 80,
            color: Colors.blue.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'ライブラリにはまだ項目がありません'
                : '「$_searchQuery」に一致する項目はありません',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'ホーム画面から新しい暗記アイテムを追加しましょう！'
                : '別のキーワードで検索してみてください',
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade900,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 日付のフォーマット
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return '今日';
    } else if (difference == 1) {
      return '昨日';
    } else if (difference < 7) {
      return '$difference日前';
    } else {
      return DateFormat('yyyy/MM/dd').format(date);
    }
  }

  // 最近公開された暗記法カードの作成
  Widget _buildRecentPublicTechniqueCard() {
    if (_isLoadingPublicTechnique) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.green.shade200),
        ),
        color: Colors.white.withOpacity(0.9),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, color: Colors.green.shade600, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '最近公開された覚え方',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    if (_recentPublicTechnique == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.shade200),
      ),
      color: Colors.white.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  '最近公開された覚え方',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _recentPublicTechnique!.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _recentPublicTechnique!.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.green.shade900,
              ),
            ),
            if (_recentPublicTechnique!.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _recentPublicTechnique!.tags.map((tag) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loadRecentPublicTechnique,
                icon:
                    Icon(Icons.refresh, size: 16, color: Colors.green.shade600),
                label: Text(
                  '別の覚え方を見る',
                  style: TextStyle(color: Colors.green.shade600),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // メモリーアイテムカードの作成
  Widget _buildMemoryItemCard(MemoryItem item) {
    // タグを取得（重複を削除）
    final allTags = <String>[];
    for (var technique in item.memoryTechniques) {
      allTags.addAll(technique.tags);
    }
    final uniqueTags = allTags.toSet().toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      color: Colors.white.withOpacity(0.9),
      child: InkWell(
        onTap: () {
          // 暗記法が公開済みか確認
          // 最新の公開状態をユーザーの公開覚え方リストから確認
          bool isPublished = false;

          if (item.memoryTechniques.isNotEmpty) {
            // まずメモリーアイテム自体の状態を確認
            final memoryTechnique = item.memoryTechniques.first;

            // デバッグ用のログを追加
            print('メモリーテクニック名: ${memoryTechnique.name}');
            print('メモリーテクニックタイプ: ${memoryTechnique.type}');
            print('元のisPublic値: ${memoryTechnique.isPublic}');
            print('公開済みリストのサイズ: ${_userPublishedTechniques.length}');

            // 公開済みリストの内容を確認
            for (var tech in _userPublishedTechniques) {
              print('公開済み: ${tech.name}');
            }

            // 次に公開済みリストにあるか確認
            bool foundInPublishedList =
                _userPublishedTechniques.any((publishedTechnique) {
              return publishedTechnique.name == memoryTechnique.name;
            });

            print('公開済みリストに含まれているか: $foundInPublishedList');

            // IDまたは名前での比較
            isPublished = foundInPublishedList || memoryTechnique.isPublic;
            print('最終的な公開状態: $isPublished');
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MemoryMethodScreen(
                memoryItem: item,
                isFromPublishedLibrary: isPublished,
              ),
            ),
          ).then((_) {
            // 画面から戻ってきた時に、再読み込みを行う
            _loadMemoryItems();
            _loadUserPublishedTechniques(); // 公開状態の更新を反映させる
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // タイトル行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // 覚え方（メモリーテクニック）の表示
              if (item.memoryTechniques.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.memoryTechniques.first.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // タグ表示
              if (uniqueTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: uniqueTags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '作成: ${_formatDate(item.createdAt)}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.delete,
                            size: 18, color: Colors.red.shade400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          // 削除確認ダイアログ
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('確認'),
                              content: const Text('この暗記アイテムを削除しますか？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('キャンセル'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _deleteMemoryItem(item);
                                  },
                                  child: Text(
                                    '削除',
                                    style:
                                        TextStyle(color: Colors.red.shade600),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 暗記法のタイプに応じたアイコンを取得
  IconData _getIconForTechniqueType(String type) {
    switch (type) {
      case 'mnemonic':
        return Icons.lightbulb_outline;
      case 'relationship':
        return Icons.account_tree_outlined;
      case 'concept':
        return Icons.psychology_outlined;
      case 'thinking': // 考え方モード
        return Icons.insights;
      default:
        return Icons.school_outlined;
    }
  }

  // 暗記法のタイプに応じた色を取得
  MaterialColor _getColorForTechniqueType(String type) {
    switch (type) {
      case 'mnemonic':
        return Colors.orange;
      case 'relationship':
        return Colors.green;
      case 'concept':
        return Colors.purple;
      case 'thinking': // 考え方モード
        return Colors.teal;
      default:
        return Colors.blue;
    }
  }

  // 公開覚え方から検索する
  Future<void> _searchPublicTechniques() async {
    if (_searchQuery.isEmpty) return;

    setState(() {
      _isSearchingPublicTechniques = true;
      _searchedPublicTechniques = [];
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      final results = await memoryService.searchPublicTechniques(_searchQuery);

      if (mounted) {
        setState(() {
          _searchedPublicTechniques = results;
          _isSearchingPublicTechniques = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearchingPublicTechniques = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('公開覚え方の検索に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // 自分が公開した覚え方を検索クエリでフィルタリング
  List<MemoryTechnique> _getFilteredUserPublishedTechniques() {
    if (_searchQuery.isEmpty) {
      return _userPublishedTechniques;
    }

    final query = _searchQuery.toLowerCase();
    return _userPublishedTechniques.where((technique) {
      return technique.name.toLowerCase().contains(query) ||
          technique.description.toLowerCase().contains(query) ||
          technique.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  // 自分が公開した覚え方をロード
  Future<void> _loadUserPublishedTechniques() async {
    if (!mounted) return;

    setState(() {
      _isLoadingUserPublishedTechniques = true;
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      final techniques = await memoryService.getUserPublishedTechniques();

      if (mounted) {
        setState(() {
          _userPublishedTechniques = techniques;
          _isLoadingUserPublishedTechniques = false;
        });
      }
    } catch (e) {
      print('公開済み覚え方の取得エラー: $e');
      if (mounted) {
        setState(() {
          _isLoadingUserPublishedTechniques = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('公開済み覚え方の取得に失敗しました: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  // 暤記法カードを构築
  Widget _buildMemoryTechniqueCard(MemoryTechnique technique) {
    // 考え方モードかどうかチェック
    final isThinkingMode = technique.type == 'thinking';

    // 考え方モードの場合、要素部分を持つか確認
    final hasItemContent = technique.itemContent.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: _getColorForTechniqueType(technique.type).withOpacity(0.3)),
      ),
      color: Colors.white.withOpacity(0.9),
      child: InkWell(
        onTap: () {
          // MemoryTechniqueをMemoryItemに変換して渡す
          final memoryItem = MemoryItem(
            id: 'technique_${technique.hashCode}', // 一意のIDを生成
            title: technique.name,
            // 考え方モードの場合、元の内容を使用
            content: isThinkingMode && hasItemContent
                ? technique.itemContent
                : technique.description,
            contentType: 'text',
            memoryTechniques: [technique],
            createdAt: DateTime.now(), // 現在時刻を使用
          );

          // デバッグ用のログ追加
          print('ダイアログからの遷移: ${technique.name}');
          print('ダイアログ内のisPublic値: ${technique.isPublic}');

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MemoryMethodScreen(
                memoryItem: memoryItem,
                isFromPublishedLibrary: true, // ダイアログからの遷移は常に公開済みとして扱う
                useThinkingMode: isThinkingMode, // 考え方モードかどうかを渡す
              ),
            ),
          ).then((_) {
            // 画面から戻ってきた時に、必要な再読み込みを行う
            _loadUserPublishedTechniques();
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_getIconForTechniqueType(technique.type),
                      color: _getColorForTechniqueType(technique.type),
                      size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      technique.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            _getColorForTechniqueType(technique.type).shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 考え方モードの場合はバッジを表示
                  if (isThinkingMode)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      child: Text(
                        '考え方',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.teal.shade700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                // 考え方モードの場合、元の内容と考え方を両方表示
                isThinkingMode && hasItemContent
                    ? '元の内容: ${technique.itemContent.length > 50 ? '${technique.itemContent.substring(0, 50)}...' : technique.itemContent}\n\n考え方: ${technique.description}'
                    : technique.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
                maxLines: isThinkingMode ? 4 : 2, // 考え方モードはより多くの行を表示
                overflow: TextOverflow.ellipsis,
              ),
              if (technique.tags.isNotEmpty) const SizedBox(height: 8),
              if (technique.tags.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: technique.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            _getColorForTechniqueType(technique.type).shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getColorForTechniqueType(technique.type)
                              .shade200,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 10,
                          color: _getColorForTechniqueType(technique.type)
                              .shade700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
