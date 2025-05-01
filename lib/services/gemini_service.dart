import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'ai_service_interface.dart';

/// Gemini APIを使用した記憶法生成サービス
class GeminiService implements AIServiceInterface {
  // Firebase Functionsインスタンスを特定リージョンで取得
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-northeast1', // Geminiファンクションが配置されているリージョン
  );

  // キャッシュ用Map
  final Map<String, String> _feedbackCache = {};
  GeminiService() {
    print('Gemini Service initialized via Firebase Functions');
  }

  @override
  bool get hasValidApiKey => _isUserAuthenticated();

  /// 入力内容から複数の項目を検出します（最適化版）
  @override
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    if (!hasValidApiKey) {
      return {
        'isMultipleItems': false,
        'items': [],
        'rawContent': content,
        'itemCount': 0,
        'message': 'VertexAI認証エラー',
      };
    }

    // 高速検出の結果と項目数を計算
    final quickDetectResult = _quickCountItems(content);
    final bool isMultipleItems = quickDetectResult['isMultiple'] as bool;
    final int itemCount = quickDetectResult['count'] as int;

    // 高速検知で複数項目を検出した場合
    if (isMultipleItems) {
      // コンテンツを行に分割し、実際の内容を使用してアイテム配列を作成
      final List<String> lines = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(itemCount)
          .toList();

      List<Map<String, String>> contentItems = [];

      // 行ごとにアイテムを作成（行がない場合はダミー項目を作成）
      for (int i = 0; i < itemCount; i++) {
        String itemContent = i < lines.length ? lines[i].trim() : '項目 ${i + 1}';

        contentItems.add({
          'content': itemContent,
          'description': '',
        });
      }

      return {
        'isMultipleItems': true,
        'items': contentItems, // 実際のコンテンツを含むアイテム配列
        'rawContent': content, // 生のデータも保持
        'itemCount': itemCount,
        'message': '複数の学習項目が検出されました（高速検出）',
      };
    }

    // 複数項目判定に特化したシンプルなプロンプト（コンテンツの重複を避ける）
    final prompt = '''あなたは学習テキストを解析して、テキストが複数の独立した学習項目を含むかどうかを判定する専門家です。
下記のテキストに対して、複数の個別項目が含まれているかどうかを判断してください。複数項目の詳細な内容は必要ありません。

以下のパターンは複数項目として判定すべきです：
1. 単語とその意味のペア（例: "abandon 放棄する"、"cosine コサイン"）
2. 表形式のデータ
3. 区切り文字（,、|、-、:、→ など）で区切られた項目リスト
4. 番号付きリストの各項目
5. 箇条書きリスト
6. 行ごとに区切られた単語や定義

判定するテキスト:
"""$content"""

JSON形式で結果を返してください。項目の詳細内容やカテゴリは不要です:
{
  "isMultipleItems": true/false,  // 複数の独立した学習項目か
  "itemCount": 数値,  // おおよその項目数
  "type": "vocabulary/list/mixed/single"  // 項目の種類（語彙/リスト/混合/単一）
}''';

    try {
      final response = await generateText(
        model: 'gemini-2.5-flash-preview-04-17',
        prompt: prompt,
        temperature: 0.2, // 低い温度で一貫性を保つ
        maxTokens: 20000, // 軽量な応答なので少ないトークン数で十分
      );

      // レスポンスからJSONを抽出
      try {
        // 新しい軽量フォーマットを処理
        final Map<String, dynamic> parsedResponse = jsonDecode(response);

        // isMultipleItemsフラグを取得
        final bool isMultipleItems = parsedResponse['isMultipleItems'] ?? false;

        // 複数項目がないと判断された場合は空のリストを返す
        if (!isMultipleItems) {
          return {
            'isMultipleItems': false,
            'items': [],
            'rawContent': content, // 生のデータを保持
            'itemCount': 0,
            'message': '複数項目は検出されませんでした',
          };
        }

        // 複数項目があると判断された場合、行分割で項目を抽出
        final String itemType = parsedResponse['type'] ?? 'mixed';

        // 複数項目の場合は項目をパースしてリスト化
        final List<Map<String, String>> parsedItems = [];
        // 単純なOCRの組み立てによる項目抽出
        final lines = content
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .take(20) // 最大項目数を制限して過剰検出を防止
            .toList();

        // 各行を項目として追加
        for (final line in lines) {
          parsedItems.add({
            'content': line.trim(),
            'description': '',
          });
        }

        return {
          'isMultipleItems': true,
          'items': parsedItems, // List<Map>型の項目リストを返す
          'rawContent': content, // 生のデータも保持
          'itemCount': parsedItems.length,
          'itemType': itemType,
          'message': '複数の学習項目が検出されました（約${parsedItems.length}項目、タイプ:$itemType）',
        };
      } catch (e) {
        print('複数項目検出のJSON解析エラー: $e');
        // JSON解析エラーの場合も高速パターンマッチングを試みる

        return {
          'isMultipleItems': false,
          'items': [],
          'message': '解析エラーが発生しました: $e',
        };
      }
    } catch (e) {
      print('複数項目検出エラー: $e');

      return {
        'isMultipleItems': false,
        'items': [],
        'message': 'エラーが発生しました: $e',
      };
    }
  }

  /// 単一項目に対して暗記法を生成するプライベートメソッド
  Future<Map<String, dynamic>?> _generateSingleItemTechnique(
      String content, String description) async {
    print('個別項目の記憶法生成: $content');
    final prompt = '''あなたは記憶術と学習法の専門家です。以下の個別項目に対して、シンプルでわかりやすい覚え方を1つ提案してください。

項目内容: "$content"
${description.isNotEmpty ? '補足説明: "$description"' : ''}

【重要】以下の例のように、シンプルで直接的な覚え方を提案してください:

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。
例3: listen (聞く) → 「listenはリスが ん？と耳をすませて聞いている」とイメージする。
例4: substance (物質) → 「sub:下に、stance:立つもの」という語源から土台→物質と覚える。
例5: H,He,Li,Be,B,C,N,O,F,Ne → 「水兵リーベぼくの船」と覚える。

イメージ部分は必須ではありませんが、短く入れても構いません。
覚え方の部分は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。

また、暗記のためのフラッシュカードを1つだけ作成してください。シンプルに一問一答の形にしてください。

以下のJSON形式で返してください:
{
  "name": "タイトル",  //15字以内目安
  "description": "〇〇は△△と覚えよう", // 具体的かつ簡潔な記憶方法の説明（30文字以内を目指す）
  "image": "短いイメージ描写（任意、なくても可）", // 30文字以内、省略可能
  "type": "mnemonic",  // "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
  "tags": ["カテゴリ"], // 項目の学習分野を示すタグ（最大2つ）
  "contentKeywords": ["キーワード"], // 内容から抽出した重要キーワード（最大2つ）
  "flashcards": [
    {
      "question": "〇〇", // 質問
      "answer": "△△" // 答え
    }
  ]
}''';

    try {
      final response = await generateText(
        prompt: prompt,
        temperature: 0.7,
        maxTokens: 20000,
      );

      // JSONを解析
      try {
        print("koko$response");
        final technique = jsonDecode(response);
        // 元の項目情報を保存
        technique['itemContent'] = content;
        technique['itemDescription'] = description;

        // タグとキーワードがなければ追加
        if (!technique.containsKey('tags') || technique['tags'] == null) {
          technique['tags'] = [];
        }
        if (!technique.containsKey('contentKeywords') ||
            technique['contentKeywords'] == null) {
          technique['contentKeywords'] = [
            content.split(' ').isNotEmpty ? content.split(' ').first : content
          ];
        }

        // 'flashcards'フィールドがない場合は作成
        if (!technique.containsKey('flashcards') ||
            technique['flashcards'] == null) {
          // 古い形式の'flashcard'フィールドがあれば変換
          if (technique.containsKey('flashcard') &&
              technique['flashcard'] != null) {
            technique['flashcards'] = [technique['flashcard']];
            technique.remove('flashcard'); // 古いフィールドを削除
          } else {
            // デフォルトのフラッシュカードを作成
            technique['flashcards'] = [
              {
                'question': content,
                'answer': description.isNotEmpty ? description : ''
              }
            ];
          }
        }

        return technique;
      } catch (e) {
        print('JSON解析エラー: $e');
        return null;
      }
    } catch (e) {
      print('暗記法生成エラー: $e');
      return null;
    }
  }

  /// 高速パターンマッチングで複数項目と項目数を検出
  Map<String, dynamic> _quickCountItems(String content) {
    // 項目数をカウントするための変数
    int bulletCount = 0;
    int lineCount = 0;

    // 行数と「-」で始まる項目数をカウント
    final lines =
        content.split('\n').where((line) => line.trim().isNotEmpty).toList();
    lineCount = lines.length;

    // 「-」で始まる項目を検出
    final bulletPattern = RegExp(r'^\s*-\s+(.+)$');
    for (String line in lines) {
      if (bulletPattern.hasMatch(line.trim())) {
        bulletCount++;
      }
    }

    // 項目数を決定 (「-」形式があればその数、なければ行数)
    final int itemCount = bulletCount > 0 ? bulletCount : lineCount;

    // 複数項目かどうかを判断
    final bool isMultiple = _quickDetectMultipleItems(content);

    if (bulletCount > 0) {
      print('OCR形式に基づく項目検出: - で始まる項目が $bulletCount 個検出されました');
    } else if (isMultiple) {
      print('整列された単語リストを検出: $lineCount 行');
    }

    return {
      'isMultiple': isMultiple,
      'count': itemCount,
      'bulletCount': bulletCount,
      'lineCount': lineCount,
      'itemContent': content,
    };
  }

  /// 高速パターンマッチングを使用して明らかな複数項目パターンを検出
  bool _quickDetectMultipleItems(String content) {
    // 空のコンテンツはチェックしない
    if (content.trim().isEmpty) return false;

    // TITLEなどの特定フォーマットをチェック
    if (content.startsWith('TITLE') || content.contains('\nTITLE')) {
      return false;
    }

    // テキストの行に分割
    List<String> lines = content.split('\n');

    // 英単語リストのOCR検出用パターン
    // chair　6　椅子 のようなパターンを検出
    if (lines.length > 2) {
      int wordsWithNumbersFound = 0;

      // 英単語 数字 日本語 パターン
      final wordNumberJapanesePattern = RegExp(
          r'[a-zA-Z]+\s+\d+\s+[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]');

      // 修正: 数字の位置が自由でも検出できるようにする
      final wordWithNumberPattern = RegExp(
          r'[a-zA-Z]+.{0,10}\d+.{0,10}[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]');

      for (String line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // 英単語リストのパターンを検査
        if (wordNumberJapanesePattern.hasMatch(trimmed) ||
            wordWithNumberPattern.hasMatch(trimmed)) {
          wordsWithNumbersFound++;
        }
      }

      // 数字を含む英単語行が3行以上あれば複数項目と判定
      if (wordsWithNumbersFound >= 3) {
        print('英単語・数字・日本語パターンを検出: $wordsWithNumbersFound 行');
        return true;
      }
    }

    // 後方互換性のためのオリジナルのパターンチェックも維持
    // 複数行があり、各行に番号（インデックス）がついている場合、それは複数項目と判断
    if (lines.length > 2) {
      // 番号付きリストパターン（1 apple りんご、1. apple りんご など）
      int numberedLines = 0;
      int numberedHyphenLines = 0; // 番号付きハイフン区切りパターンをカウント

      // 番号で始まる行の検出
      final numberedPattern = RegExp(r'^\s*\d+[\s.．、]');

      // 番号付きハイフン区切りパターン（1. 英単語 - 日本語）の検出
      final numberedHyphenPattern = RegExp(r'^\s*\d+[\s.．、][^-]+-');

      for (String line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // 番号付き行の判定
        if (numberedPattern.hasMatch(trimmed)) {
          numberedLines++;

          // 番号付き行がハイフンを含むか判定
          if (trimmed.contains('-') ||
              numberedHyphenPattern.hasMatch(trimmed)) {
            numberedHyphenLines++;
          }
        }
      }

      // 少なくとも2行が番号付きハイフン区切りであれば複数項目と判断
      if (numberedHyphenLines >= 2) {
        print('番号付きハイフン区切り行を検出: $numberedHyphenLines 行');
        return true;
      }

      // 少なくとも3行が番号付きであれば複数項目と判断
      if (numberedLines >= 3) {
        print('番号付き行を検出: $numberedLines 行');
        return true;
      }
    }

    // ハイフン区切りパターンの検出
    if (lines.length > 2) {
      int hyphenLines = 0;
      final hyphenPattern = RegExp(r'\S+\s+-\s+\S+'); // 英単語 - 日本語パターン

      for (String line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // 語彙リストでよく使われるハイフン区切りを検出
        if (hyphenPattern.hasMatch(trimmed) || trimmed.contains(' - ')) {
          hyphenLines++;
        }
      }

      // 少なくとも2行がハイフン区切りであれば複数項目と判断
      if (hyphenLines >= 2) {
        print('ハイフン区切り行を検出: $hyphenLines 行');
        return true;
      }
    }

    // 整列された単語リストの検出（全角スペースやタブで整列されたパターン）
    if (lines.length > 2) {
      // 2行以上が同様のパターン（単語と意味が全角スペースやタブで区切られている）を持つかチェック
      int alignedRows = 0;

      // Web環境でも動作する正規表現パターン
      // 英単語＋全角スペース＋日本語のパターン
      final alignedPattern1 = RegExp(r'\S+[\s　\t]+[^\x00-\x7F]');

      // 数字＋全角スペース＋英単語＋全角スペース＋日本語のパターン
      final alignedPattern2 = RegExp(r'\d+[\s　\t]+\S+[\s　\t]+[^\x00-\x7F]');

      for (String line in lines) {
        String trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (alignedPattern1.hasMatch(trimmed) ||
            alignedPattern2.hasMatch(trimmed)) {
          alignedRows++;
        }
      }

      // 少なくとも2行がパターンにマッチしたら複数項目と判断
      if (alignedRows >= 2) {
        print('整列された単語リストを検出: $alignedRows 行');
        return true;
      }
    }

    // 単語パターン検出（英語 日本語、英語：日本語、など）
    // 複数行の場合に特定のパターンを検出
    if (lines.length > 1) {
      int patternMatches = 0;
      // Web環境でも動作する正規表現パターン
      // 日本語の文字を含む、より簡素化されたパターン
      final vocabPattern1 = RegExp(r'^\s*\S+\s+[^\x00-\x7F]+'); // 英単語+日本語
      final vocabPattern2 =
          RegExp(r'^\s*\S+\s*[-=:：・]\s*[^\x00-\x7F]+'); // 英単語=日本語
      final vocabPattern3 =
          RegExp(r'^\s*[^\x00-\x7F]+\s*[-=:：・]\s*\S+'); // 日本語=英語

      // 最大10行をチェック
      int checkLines = math.min(lines.length, 10);
      for (int i = 0; i < checkLines; i++) {
        String line = lines[i].trim();
        if (line.isEmpty) continue;

        if (vocabPattern1.hasMatch(line) ||
            vocabPattern2.hasMatch(line) ||
            vocabPattern3.hasMatch(line)) {
          patternMatches++;
        }
      }

      // 非空行の20%以上が単語パターンにマッチする場合、複数項目と判断（閾値を30%から20%に下げる）
      int nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;
      if (nonEmptyLines > 0 && patternMatches / nonEmptyLines >= 0.2) {
        print('語彙パターンを検出: $patternMatches / $nonEmptyLines 行がマッチ');
        return true;
      }
    }

    // 箇条書きや番号付きリストの検出
    int bulletPoints = 0;
    final bulletPattern = RegExp(r'^\s*[\-\*•◦‣⁃・]\s+\S+'); // 箇条書き
    final numberPattern = RegExp(r'^\s*[0-9]{1,2}[\.\)]\s+\S+'); // 番号付きリスト

    for (String line in lines) {
      if (bulletPattern.hasMatch(line) || numberPattern.hasMatch(line)) {
        bulletPoints++;
      }
    }

    // 3つ以上の箇条書きまたは番号付きリスト項目があれば複数項目と判断
    if (bulletPoints >= 3) {
      print('リストパターンを検出: $bulletPoints 項目');
      return true;
    }

    // 「単語1,単語2,単語3」のようなカンマ区切りパターン
    if (content.contains(',') &&
        content.split(',').length >= 3 &&
        content.split(',').every((part) => part.trim().isNotEmpty)) {
      print('カンマ区切りパターンを検出');
      return true;
    }

    // 表形式データの検出（|で区切られた行が複数ある）
    int tableRows = 0;
    for (String line in lines) {
      if (line.contains('|') && line.split('|').length >= 3) {
        tableRows++;
      }
    }

    if (tableRows >= 2) {
      print('表形式データを検出: $tableRows 行');
      return true;
    }

    // テキスト形式の語彙データ（従来のcheck）
    if (_isTextFormattedVocabulary(content)) {
      print('テキスト形式の語彙データを検出');
      return true;
    }

    return false;
  }

  /// テキスト形式の語彙データをアイテムリストに変換する
  List<Map<String, String>> _parseTextFormattedVocabulary(String text) {
    final List<Map<String, String>> result = [];
    final List<String> lines = text.split('\n');

    for (String line in lines) {
      line = line.trim();
      // 空行をスキップ
      if (line.isEmpty) continue;

      // コロンで単語と意味を分割し、セミコロンを削除
      final parts = line.split(':');
      if (parts.length >= 2) {
        String word = parts[0].trim();
        String meaning = parts[1].trim();

        // 最後のセミコロンを削除
        if (meaning.endsWith(';')) {
          meaning = meaning.substring(0, meaning.length - 1);
        }

        if (word.isNotEmpty) {
          result.add({'content': word, 'description': meaning});
        }
      }
    }

    return result;
  }

  /// コンテンツがテキスト形式の語彙データかどうか確認
  bool _isTextFormattedVocabulary(String content) {
    // 最初の数行を確認
    final lines = content.trim().split('\n');
    if (lines.isEmpty) return false;

    // 少なくとも最初の3行かげ1行が形式に匹合していればtrue
    final checkLines = lines.take(3).toList();
    for (String line in checkLines) {
      if (line.trim().isNotEmpty &&
          line.contains(':') &&
          (line.contains(';') || line.endsWith(';'))) {
        return true;
      }
    }

    return false;
  }

  /// 複数項目に対してまとめて暗記法を生成します
  Future<List<Map<String, dynamic>>> generateMemoryTechniquesWithBatching(
    List<dynamic> items, {
    Function(double progress, int processedItems, int totalItems)?
        progressCallback,
    int? itemCount,
    bool isQuickDetection = false,
    String? rawContent,
  }) async {
    // バッチサイズの設定（項目数に応じて自動調整）
    int determineBatchSize(int totalCount) {
      if (totalCount <= 10) return totalCount; // 10個以下はそのまま処理
      return 10; // 多数項目の場合は小さいバッチサイズ
    }

    // 結果リスト
    List<Map<String, dynamic>> allResults = [];

    // 項目数の決定
    final int totalItems = isQuickDetection && itemCount != null
        ? itemCount
        : itemCount ?? items.length;

    // バッチサイズの計算
    final int batchSize = determineBatchSize(totalItems);

    // バッチ数の計算
    final int batchCount = (totalItems / batchSize).ceil();

    print('バッチ処理を開始: 全$totalItems項目を$batchSize項目ずつ$batchCountバッチに分割');

    // 並列処理用のバッチ一覧を作成
    List<Future<List<Map<String, dynamic>>>> batchFutures = [];

    // 各バッチを作成し並列処理をするための準備
    for (int i = 0; i < batchCount; i++) {
      // バッチの開始と終了インデックスを計算
      final int startIdx = i * batchSize;
      int endIdx = (i + 1) * batchSize;
      if (endIdx > items.length) endIdx = items.length;

      // バッチの項目を抽出
      List<dynamic> batchItems;
      String? batchRawContent;

      if (isQuickDetection && rawContent != null) {
        // 高速検出の場合は項目の区切り("-"で始まる行)を考慮して分割
        final List<String> lines = rawContent.split('\n');

        // 各行が"-"で始まるかどうかをチェック
        List<int> itemStartIndices = [];
        for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
          if (lines[lineIdx].trim().startsWith('-')) {
            itemStartIndices.add(lineIdx);
          }
        }

        // バッチに含める項目の開始インデックスと終了インデックスを計算
        final int itemStartIdx = startIdx;
        final int itemEndIdx = endIdx > items.length ? items.length : endIdx;

        // バッチに含める行の範囲を決定
        int lineStartIdx = 0;
        int lineEndIdx = lines.length;

        if (itemStartIndices.isNotEmpty) {
          // 項目のインデックスから対応する行インデックスを特定
          if (itemStartIdx < itemStartIndices.length) {
            lineStartIdx = itemStartIndices[itemStartIdx];
          }

          if (itemEndIdx < itemStartIndices.length) {
            lineEndIdx = itemStartIndices[itemEndIdx];
          }
        }

        // 指定範囲の行を抽出
        final List<String> batchLines = lines.sublist(
            lineStartIdx < lines.length ? lineStartIdx : lines.length - 1,
            lineEndIdx < lines.length ? lineEndIdx : lines.length);

        batchRawContent = batchLines.join('\n');
        batchItems = items.sublist(itemStartIdx, itemEndIdx);

        print(
            '項目区切りに基づくバッチ: 行 $lineStartIdx-$lineEndIdx, 項目 $itemStartIdx-$itemEndIdx');
      } else {
        // 通常の場合は項目リストをそのまま分割
        batchItems = items.sublist(startIdx, endIdx);
        batchRawContent = null;
      }

      print('バッチ処理準備 ${i + 1}/$batchCount: ${batchItems.length}項目');

      // 進捗状況のコールバックを作成
      final int batchIndex = i; // 変数をクロージャ内で使用するためにキャプチャ
      void batchProgressCallback(double progress, int processed, int total) {
        // バッチ内での進捗をグローバル進捗に変換
        final globalProgress =
            (batchIndex / batchCount) * 0.8 + (progress * 0.8 / batchCount);
        progressCallback?.call(
            globalProgress, batchIndex * batchSize + processed, totalItems);
      }

      // 各バッチの処理を非同期関数として定義
      Future<List<Map<String, dynamic>>> processBatch() async {
        // バッチごとのitemCountを計算
        // 高速検出時は全体のitemCountからバッチに対応する割合を計算
        int? batchItemCount;
        if (isQuickDetection && itemCount != null) {
          // 各バッチに適切な項目数を割り当て
          double ratio = batchItems.length / items.length;
          batchItemCount = (itemCount * ratio).ceil();
          print(
              'バッチ${batchIndex + 1}: 項目割合=${ratio.toStringAsFixed(2)}, 割当項目数=$batchItemCount');
        }

        // 各項目に正しい番号を設定するためのオフセットを計算
        // バッチの開始項目序号を正しく働かせるための文字列生成
        final int startIndex = startIdx;
        final String batchRangeText;
        if (isQuickDetection && itemCount != null) {
          // 高速検出時は項目番号を計算
          final int endIndexEstimate =
              startIndex + batchItems.length <= itemCount
                  ? startIndex + batchItems.length
                  : itemCount;
          batchRangeText = "項目${startIndex + 1}～$endIndexEstimate";
        } else {
          batchRangeText = "バッチ${batchIndex + 1}の項目一覧";
        }

        print(
            'バッチ${batchIndex + 1}: 項目範囲=$batchRangeText, 開始インデックス=$startIndex');

        // バッチの項目番号を詳細に表示
        List<String> itemDescriptions = [];
        for (int idx = 0; idx < batchItems.length; idx++) {
          dynamic item = batchItems[idx];
          String content = item['content'] ?? 'unknown';
          itemDescriptions.add('項目${startIndex + idx + 1}: $content');
        }
        print('バッチ${batchIndex + 1}の項目内容: ${itemDescriptions.join(', ')}');

        // 項目番号のオフセット情報を含む上書きプロンプトを作成
        String batchPromptHeader =
            "バッチ${batchIndex + 1}/$batchCount: $batchRangeText\n\n重要: 各項目のitemIndexは$startIndexから始まる整数で指定してください。\n";

        // バッチごとに既存の関数を呼び出し
        final batchResults = await generateMemoryTechniquesForMultipleItems(
          batchItems,
          progressCallback: batchProgressCallback,
          itemCount: batchItemCount ?? batchItems.length, // バッチに適した項目数を使用
          isQuickDetection: isQuickDetection,
          rawContent:
              batchPromptHeader + (batchRawContent ?? ""), // プロンプトにバッチ情報を追加
          batchOffset: startIndex, // 項目番号のオフセットを渡す
        );

        // バッチ処理の進捗状況をログ出力
        print(
            'バッチ ${batchIndex + 1}/$batchCount 完了: ${batchResults.length}件の暗記法を生成');

        return batchResults;
      }

      // バッチ処理をリストに追加
      batchFutures.add(processBatch());
    }

    // すべてのバッチを並列実行
    print('並列処理開始: $batchCount個のバッチを同時実行');
    final batchResultsList = await Future.wait(batchFutures);

    // 結果をフラット化して統合
    for (final batchResults in batchResultsList) {
      allResults.addAll(batchResults);
    }

    print('並列処理完了: 合計${allResults.length}件の暗記法を生成');

    // 全体の進捗完了を通知
    progressCallback?.call(1.0, totalItems, totalItems);

    return allResults;
  }

  @override
  Future<List<Map<String, dynamic>>> generateMemoryTechniquesForMultipleItems(
    List<dynamic> items, {
    Function(double progress, int processedItems, int totalItems)?
        progressCallback,
    int? itemCount,
    bool isQuickDetection = false,
    String? rawContent, // 高速検知時の生データ
    bool isThinkingMode = false,
    bool isMultiAgentMode = false,
    int batchOffset = 0, // バッチ処理時の項目インデックスオフセット
  }) async {
    if (!hasValidApiKey) {
      return [];
    }

    List<Map<String, dynamic>> results = [];

    print('複数項目に対して暗記法を生成します。項目数: ${itemCount ?? items.length}');
    print('項目内容:$itemCount');

    // 進行状況の初期化を報告
    progressCallback?.call(0.0, 0, itemCount ?? items.length);

    // テキスト形式の語彙データを処理する特別ケース
    if (items.length == 1 && items[0]['content'] is String) {
      final String content = items[0]['content'];

      // テキスト形式の語彙データか確認
      if (_isTextFormattedVocabulary(content)) {
        print('テキスト形式の語彙データを検出しました');
        // テキストをアイテムリストに変換
        final vocabularyItems = _parseTextFormattedVocabulary(content);
        print('テキストから${vocabularyItems.length}個の語彙アイテムを抽出しました');

        // 変換したアイテムがあれば、それを使用して処理を続ける
        if (vocabularyItems.isNotEmpty) {
          items = vocabularyItems;
          print('変換された単語リストで暗記法を生成します');
          // 進行状況を更新
          progressCallback?.call(
              0.1, 0, vocabularyItems.length + (itemCount ?? 0));
        }
      }
    }

    // アイテム数が1つの場合は通常の生成方法を使用
    if (items.length + (itemCount ?? 0) == 1) {
      final item = items[0];
      final content = item['content'];
      final description = item['description'] ?? '';

      print('単一項目の記憶法生成: $content');
      final technique =
          await _generateSingleItemTechnique(content, description);
      if (technique != null) {
        results.add(technique);
      }
      // 処理完了を報告
      progressCallback?.call(1.0, 1, 1);
      return results;
    }

    // 複数アイテム処理時の最適化
    print('複数項目の暗記法生成を実行します（最適化版）');

    // 高速検出フラグと生データの確認
    if (isQuickDetection && rawContent != null) {
      print('高速検出データを使用した暗記法生成モードを有効化します');
    }

    // アイテムの内容を取得
    List<String> contentList = [];
    List<String> descriptionList = [];

    for (var item in items) {
      contentList.add(item['content'] ?? '');
      descriptionList.add(item['description'] ?? '');
    }

    // 進行状況を更新
    progressCallback?.call(0.1, 0, items.length);

    // 高速検知時は生データを使用する
    String prompt;

    if (isQuickDetection) {
      // 高速検知時は生のOCRデータを使用し、JSON変換を行わない
      print('高速検知された複数項目に対して生データを使用した暗記法を生成します（項目数: $itemCount）');
      prompt =
          '''あなたは暗記学習をサポートする専門家です。以下の$itemCount個の項目に対して、全体を表す簡潔なタイトル（20文字以内）とそれぞれの項目に対するシンプルでわかりやすい覚え方を提案してください。

【重要】以下の例のようなシンプルで直感的な覚え方を目指してください:

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。
例3: listen (聞く) → 「listenはリスが ん？と耳をすませて聞いている」とイメージする。
例4: substance (物質) → 「sub:下に、stance:立つもの」という語源から土台→物質と覚える。
例5: H,He,Li,Be,B,C,N,O,F,Ne → 「水兵リーベぼくの船」と覚える。

覚え方の文は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。イメージ部分は必要ない場合は省略しても構いません。
各項目にはそれぞれに適切なアプローチを選択して暗記法を考えてください。

学習項目一覧（簡易的に構造化されたテキストのため、区切りは適切に判断すること）:
$rawContent

以下の特別なJSON形式で返してください。トークン数削減のため、全ての項目に共通のフィールドを最初に指定し、個別の暗記法はそれを参照します:

{
 "commonTitle": "学習内容の簡潔なタイトル（20文字以内）", // 全項目をまとめた簡潔なタイトル
  "commonType": "mnemonic", // 全項目に共通のタイプ: "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方)
  "commonTags": ["共通カテゴリ"], // 全項目に共通のタグ（学習分野など）
  "commonContentKeywords": ["共通キーワード"], // 全項目に共通のキーワード
  "techniques": [
    {
      "itemIndex": 0, // 対応する項目のインデックス（0始まり）
      "originalContent": "元の内容", // 元の項目内容
      "name": "タイトル",  //15字以内目安
      "description": "〇〇は△△と覚えよう", // 具体的かつ簡潔な記憶方法の説明（30文字以内を目指す）
      "image": "短いイメージ描写（省略可能）", // オプショナル、30文字以内
      "flashcards": [{
        "question": "質問",
        "answer": "回答"
      }]
    }
    // 各項目に対して同様のオブジェクトを生成してください
  ]
}

重要な注意事項:
1. 必ず$itemCount個の項目全てに対して個別の暗記法を生成してください。
2. 各暗記法のitemIndexは、必ず対応する項目のインデックスを正確に指定してください（最初の項目は0、次は1など）。
3. 暗記法のoriginalContentには、元の項目内容をそのまま含めてください。
4. 各項目に対して、シンプルで覚えやすい暗記法をカスタマイズして提案してください。
5. フラッシュカードの内容に数式を含む場合は\$で囲まれるtex表記としてください''';
    } else {
      // 通常の暗記法生成時は項目リストを使用
      prompt =
          '''あなたは暗記学習をサポートする専門家です。以下の${contentList.length}個の項目に対して、全体を表す簡潔なタイトル（20文字以内）とそれぞれの項目に対するシンプルでわかりやすい覚え方を提案してください。

【重要】以下の例のようなシンプルで直感的な覚え方を目指してください:

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。
例3: listen (聞く) → 「listenはリスが ん？と耳をすませて聞いている」とイメージする。
例4: substance (物質) → 「sub:下に、stance:立つもの」という語源から土台→物質と覚える。
例5: H,He,Li,Be,B,C,N,O,F,Ne → 「水兵リーベぼくの船」と覚える。

覚え方の文は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。イメージ部分は必要ない場合は省略しても構いません。
各項目にはそれぞれに適切なアプローチを選択して暗記法を考えてください。

学習項目一覧:
${contentList.asMap().entries.map((entry) {
        int i = entry.key;
        String content = entry.value;
        String description =
            i < descriptionList.length ? descriptionList[i] : '';
        return '【項目${i + 1}】 "$content" ${description.isNotEmpty ? "(補足: $description)" : ""}';
      }).join('\n')}

以下の特別なJSON形式で返してください。トークン数削減のため、全ての項目に共通のフィールドを最初に指定し、個別の暗記法はそれを参照します:

{
 "commonTitle": "学習内容の簡潔なタイトル（20文字以内）", // 全項目をまとめた簡潔なタイトル
  "commonType": "mnemonic", // 全項目に共通のタイプ: "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方)
  "commonTags": ["共通カテゴリ"], // 全項目に共通のタグ（学習分野など）
  "commonContentKeywords": ["共通キーワード"], // 全項目に共通のキーワード
  "techniques": [
    {
      "itemIndex": 0, // 対応する項目のインデックス（0始まり）
      "originalContent": "元の内容", // 元の項目内容
      "name": "タイトル",  //15字以内目安
      "description": "〇〇は△△と覚えよう", // 具体的かつ簡潔な記憶方法の説明（30文字以内を目指す）
      "image": "短いイメージ描写（省略可能）", // オプショナル、30文字以内
      "flashcards": [{
        "question": "質問",
        "answer": "回答"
      }]
    }
    // 各項目に対して同様のオブジェクトを生成してください
  ]
}

重要な注意事項:
1. 必ず${contentList.length}個の項目全てに対して個別の暗記法を生成してください。
2. 各暗記法のitemIndexは、必ず対応する項目のインデックスを正確に指定してください（最初の項目は0、次は1など）。
3. 暗記法のoriginalContentには、元の項目内容をそのまま含めてください。
4. 各項目に対して、シンプルで覚えやすい暗記法をカスタマイズして提案してください。
5. フラッシュカードの内容に数式を含む場合は\$で囲まれるtex表記としてください''';
    }
    // 項目数に応じてトークン上限を計算 - 「aborted」エラーを避けるため、より効率的な計算を実施
    // 単語リストかその他かによって必要トークン数も変わる
    final bool isVocabularyList =
        contentList.every((content) => content.split(' ').length <= 2);

    // アイテム数を正しく計算
    int totalItems;
    if (isQuickDetection && itemCount != null) {
      // 高速検出時は生データの項目数のみ使用
      totalItems = itemCount;
    } else {
      // 通常処理時はcontentリストの長さを使用
      totalItems = contentList.length;
    }

    // 項目数に応じた進行的なスケーリングを適用
    // 項目が多くなるにつれて、項目あたりのトークン割り当てを少なくする
    int baseTokens;
    int tokenPerItem;

    if (isVocabularyList) {
      // 単語リストの場合
      if (totalItems <= 10) {
        baseTokens = 2000;
        tokenPerItem = 2000; // 少数項目の場合はより詳細な暗記法
      } else if (totalItems <= 20) {
        baseTokens = 2000;
        tokenPerItem = 1500; // 中程度の項目数
      } else if (totalItems <= 40) {
        baseTokens = 2000;
        tokenPerItem = 1200; // より多くの項目
      } else {
        baseTokens = 2500;
        tokenPerItem = 1000; // 非常に多くの項目
      }
    } else {
      // 複雑な項目リストの場合
      if (totalItems <= 5) {
        baseTokens = 2000;
        tokenPerItem = 4000; // 少数の複雑な項目には多めのトークン
      } else if (totalItems <= 15) {
        baseTokens = 2000;
        tokenPerItem = 3000; // 中程度の項目数
      } else if (totalItems <= 30) {
        baseTokens = 2500;
        tokenPerItem = 2000; // より多くの項目には効率化が必要
      } else {
        baseTokens = 3000;
        tokenPerItem = 1600; // 非常に多くの項目
      }
    }

    // 項目数に応じたトークン数を計算
    int calculatedTokens = baseTokens + (totalItems * tokenPerItem);

    // 最少 2000トークン、最大 12000トークンに制限 (Geminiの制限に合わせる)
    int maxTokens = calculatedTokens.clamp(2000, 12000);

    print('項目数: $totalItems, 適用トークン上限: $maxTokens, 語彙リスト: $isVocabularyList');

    final response = await generateText(
      prompt: prompt,
      temperature: 0.7,
      maxTokens: maxTokens,
    );

    // JSONを解析
    try {
      // JSONをパース
      final responseData = jsonDecode(response);
      print(
          'Geminiからのレスポンスを受信: ${response.substring(0, math.min(100, response.length))}...');
      print('レスポンスフィールド: ${responseData.keys.join(', ')}');

      // レスポンスデータから暗記法を抽出
      List<dynamic> techniquesList = [];

      // 2つの形式をサポート:
      // 1. techniquesフィールドがある場合
      // 2. 直接暗記法オブジェクトが返される場合

      if (responseData.containsKey('techniques') &&
          responseData['techniques'] != null &&
          responseData['techniques'] is List) {
        // 形式1: techniques配列を使用
        techniquesList = responseData['techniques'];
        print('techniquesフィールドから${techniquesList.length}個の暗記法を取得');
      } else if (responseData.containsKey('name') &&
          responseData.containsKey('description')) {
        // 形式2: 直接オブジェクトが返されている場合
        print('直接暗記法オブジェクトを受信しました');
        techniquesList = [responseData]; // レスポンス全体を暗記法として使用
      } else {
        print('techniquesフィールドが見つからず、直接暗記法オブジェクトでもありません');
        print('利用可能なフィールド: ${responseData.keys.join(', ')}');

        // フォールバックの暗記法を生成
        Map<String, dynamic> fallbackTechnique = {
          'commonTitle': '学習アイテム',
          'type': 'mnemonic',
          'itemContent':
              isQuickDetection && rawContent != null ? rawContent : '',
          'name': '単純書き込み法',
          'description': '対象を整理してリスト化して覚えよう',
          'tags': ['memory']
        };

        return [fallbackTechnique];
      }

      // 共通フィールドを取得
      String commonType;
      if (responseData['commonType'] is String) {
        commonType = responseData['commonType'];
      } else if (responseData['commonType'] is int) {
        // 数値を文字列に変換
        commonType = responseData['commonType'].toString();
      } else {
        commonType = 'mnemonic';
      }

      final commonTags = responseData['commonTags'] ?? [];
      final commonContentKeywords = responseData['commonContentKeywords'] ?? [];

      // 暗記法リストの確認
      print('取得した暗記法の数: ${techniquesList.length}');

      // commonTitleを抽出して各テクニックに追加
      if (responseData.containsKey('commonTitle')) {
        final commonTitle = responseData['commonTitle'];
        for (var technique in techniquesList) {
          technique['commonTitle'] = commonTitle;
        }
      }

      // 技術リストの数と項目数の確認
      print('受信した暗記法数: ${techniquesList.length}, 元の項目数: ${contentList.length}');

      // 各暗記法を処理
      for (int i = 0; i < techniquesList.length; i++) {
        var technique = techniquesList[i];

        // 高速検出時は暗記法のインデックスをそのまま使用
        if (isQuickDetection) {
          // 暗記法の内容をそのまま使用する
          String originalContent = '';
          if (technique.containsKey('originalContent') &&
              technique['originalContent'] != null &&
              technique['originalContent'].toString().isNotEmpty) {
            originalContent = technique['originalContent'].toString();
          }

          // 直接暗記法に必要な情報を設定
          technique['itemContent'] = originalContent;
          technique['itemDescription'] = '';
          // バッチオフセットを考慮してitemIndexを設定
          int itemIndexValue = i;
          if (technique.containsKey('itemIndex') &&
              technique['itemIndex'] is int) {
            itemIndexValue = technique['itemIndex'];
          }
          technique['itemIndex'] = itemIndexValue + batchOffset; // バッチオフセットを追加

          print('高速検出モード: 暗記法${i + 1}を処理');
        } else {
          // 通常モードでの処理
          // itemIndexがレスポンスに含まれている場合はそれを使用
          int targetIndex;
          if (technique.containsKey('itemIndex') &&
              technique['itemIndex'] is int) {
            // バッチオフセットを考慮してitemIndexを設定
            int rawItemIndex = technique['itemIndex'];
            // バッチオフセットを適用
            targetIndex = rawItemIndex + batchOffset;
            print(
                '暗記法${i + 1}の指定itemIndex: $targetIndex (生インデックス: $rawItemIndex, オフセット: $batchOffset)');
          } else {
            // itemIndexがない場合はリストの順序を使用
            targetIndex = i < items.length ? i : items.length - 1;
            // バッチオフセットを考慮
            targetIndex = targetIndex + batchOffset;
            print('暗記法${i + 1}のitemIndexが指定されていないため、インデックス$targetIndexを使用');
          }

          // 対応する項目を取得
          targetIndex = targetIndex.clamp(0, items.length - 1); // 範囲内に収める

          // items配列が空でない場合のみアクセス
          if (items.isNotEmpty) {
            final item = items[targetIndex];
            final content = item['content'] ?? '';
            final description = item['description'] ?? '';

            // 項目の情報を保存
            technique['itemContent'] = content;
            technique['itemDescription'] = description;
            technique['itemIndex'] = targetIndex; // オフセットを適用したインデックスを設定
          }
        }

        // 元の項目内容がoriginalContentとして含まれているか確認
        if (!technique.containsKey('originalContent') ||
            technique['originalContent'] == null ||
            technique['originalContent'] == '元の内容') {
          // 元の項目内容が正しく含まれていない場合は追加
          technique['originalContent'] = technique['itemContent'] ?? '';
        }

        // 共通フィールドを追加
        technique['type'] = technique['type'] ?? commonType;

        // タグの処理（共通タグを使用、個別タグがあれば追加）
        if (!technique.containsKey('tags') || technique['tags'] == null) {
          technique['tags'] = [...commonTags];
        } else {
          // 既存のタグに共通タグを追加（重複を避ける）
          List<String> existingTags = List<String>.from(technique['tags']);
          for (var tag in commonTags) {
            if (!existingTags.contains(tag)) {
              existingTags.add(tag);
            }
          }
          technique['tags'] = existingTags;
        }

        // キーワードの処理（共通キーワードを使用、個別キーワードがあれば追加）
        if (!technique.containsKey('contentKeywords') ||
            technique['contentKeywords'] == null) {
          technique['contentKeywords'] = [...commonContentKeywords];
        } else {
          // 既存のキーワードに共通キーワードを追加（重複を避ける）
          List<String> existingKeywords =
              List<String>.from(technique['contentKeywords']);
          for (var keyword in commonContentKeywords) {
            if (!existingKeywords.contains(keyword)) {
              existingKeywords.add(keyword);
            }
          }
          technique['contentKeywords'] = existingKeywords;
        }

        // フラッシュカードがなければ追加
        if (!technique.containsKey('flashcards') ||
            technique['flashcards'] == null) {
          // すでにitemContentが設定されているので、それを使用
          final itemContent = technique['itemContent'] ?? '';
          final itemDescription = technique['itemDescription'] ?? '';

          technique['flashcards'] = [
            {
              'question': itemContent,
              'answer': itemDescription.isNotEmpty ? itemDescription : ''
            }
          ];
        }

        results.add(technique);
      }
    } catch (e) {
      print('JSON解析エラー: $e');
      // エラー発生時は単一のフォールバック生成に変更（個別リクエストの辺延を完全に防止）

      // レスポンス内容の生成に必要な情報を取得
      String content = '';
      String description = '';

      // データソースの選択：高速検出からか、順序リストからか
      if (isQuickDetection && rawContent != null) {
        // 高速検出時はrawContentを使用
        content = rawContent;
      } else if (items.isNotEmpty) {
        // 順序リストから最初の項目を使用
        content = items[0]['content'] ?? '';
        description = items[0]['description'] ?? '';
      }

      // コンソールにハッシュ値を記録（デバッグ用）
      print('コンテンツハッシュ値: ${content.hashCode}');

      // 共通のフォールバック暗記法を追加
      results.add({
        'name': 'シンプル暗記法',
        'description': '重要ポイントに焦点を当てて、イメージ化で覚えよう',
        'type': 'concept',
        'tags': ['学習'],
        'contentKeywords': content.isNotEmpty ? [content.split(' ').first] : [],
        'itemContent': content,
        'itemDescription': description,
        'flashcards': [
          {
            'question': content,
            'answer': description.isNotEmpty ? description : ''
          }
        ]
      });
    }

    return results;
  }

  /// テキストから有効なJSONを抽出する
  String _extractValidJson(String text) {
    try {
      // JSONオブジェクトを探すパターン
      final RegExp jsonObjPattern = RegExp(r'\{[\s\S]*?\}', dotAll: true);
      final matches = jsonObjPattern.allMatches(text);

      for (final match in matches) {
        final jsonCandidate = match.group(0) ?? '';
        try {
          // 正しくJSONとしてパースできるか確認
          final parsed = jsonDecode(jsonCandidate);
          // 必要なフィールドが含まれているか確認
          if (parsed is Map &&
              parsed.containsKey('name') &&
              parsed.containsKey('description') &&
              parsed.containsKey('type')) {
            return jsonCandidate; // 有効なJSONを返す
          }
        } catch (e) {
          // この候補がパースできないお登録なく次を試す
          continue;
        }
      }

      // JSON配列を探すパターン
      final RegExp jsonArrayPattern =
          RegExp(r'\[\s*\{[\s\S]*?\}\s*\]', dotAll: true);
      final arrayMatches = jsonArrayPattern.allMatches(text);

      for (final match in arrayMatches) {
        final jsonCandidate = match.group(0) ?? '';
        try {
          // 正しくJSONとしてパースできるか確認
          jsonDecode(jsonCandidate);
          return jsonCandidate; // 有効なJSONを返す
        } catch (e) {
          // この候補がパースできないお登録なく次を試す
          continue;
        }
      }

      // 有効なJSONが見つからない場合
      print('有効なJSONが見つかりませんでした: $text');
      return _createFallbackJson(text); // フォールバックJSONを作成
    } catch (e) {
      print('JSON抽出エラー: $e');
      return _createFallbackJson(text);
    }
  }

  /// フォールバック用のJSONを作成
  String _createFallbackJson(String text) {
    try {
      // 簡略化したコンテンツ
      String shortText = text;
      if (text.length > 100) {
        shortText = '${text.substring(0, 100)}...';
      }

      // フォールバック用のJSONを作成
      final fallback = {
        'name': 'シンプル暗記法',
        'description': '重要ポイントに焦点を当てて、イメージ化で覚えよう',
        'type': 'concept',
        'tags': ['学習'],
        'contentKeywords': ['学習', '記憶'],
        'flashcards': [
          {'question': '重要ポイントは？', 'answer': shortText}
        ]
      };

      return jsonEncode(fallback);
    } catch (e) {
      print('フォールバックJSON作成エラー: $e');
      // 絶対に失敗しないバックアップ
      return '{"name":"シンプル暗記法","description":"重要ポイントに焦点を当てて覚えよう","type":"concept","tags":["学習"],"contentKeywords":["学習"],"flashcards":[{"question":"重要ポイントは？","answer":"内容を確認してください"}]}';
    }
  }

  /// ユーザー認証状態を確認
  bool _isUserAuthenticated() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser != null;
  }

  @override
  Future<String> generateText({
    required String prompt,
    String model = 'gemini-2.5-pro-preview-03-25', // Geminiのモデルをデフォルトに変更
    double temperature = 0.7,
    int maxTokens = 20000,
  }) async {
    try {
      if (!_isUserAuthenticated()) {
        print('ユーザーが認証されていません');
        return _createFallbackJson('認証が必要です');
      }

      // Gemini API向けのリクエストを作成
      final Map<String, dynamic> requestData = {
        'model': model,
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'You are a helpful assistant specializing in memory techniques. ' 'IMPORTANT: Always respond with valid JSON. DO NOT use markdown code blocks (```). ' +
                    'DO NOT include backticks, explanations, or any other text. ' +
                    'Return ONLY the raw JSON object as requested in the prompt. ' +
                    'Your entire response must be parseable as JSON.\n\n' +
                    prompt
              }
            ]
          }
        ],
        'generation_config': {
          'temperature': temperature,
          'max_output_tokens': maxTokens,
        }
      };

      try {
        // Gemini APIを呼び出すFirebase Function
        final HttpsCallable callable = _functions.httpsCallable('proxyGemini');

        // リクエストデータを正しい形式に変更
        final functionRequestData = {'data': requestData};

        print('リクエスト開始: Gemini API向けにリクエストを送信します');
        print('パラメータ: モデル=$model, トークン数=$maxTokens, 温度=$temperature');

        // Firebase Function呼び出し
        final result = await callable.call(functionRequestData);
        print('レスポンス受信: Gemini APIからレスポンスを受信しました');
        final data = result.data;
        print('レスポンス内容: $data');

        // レスポンスの構造確認
        if (data == null) {
          print('エラー: レスポンスデータがnullです');
          return _createFallbackJson('サーバーからのレスポンスを受信できませんでした');
        }

        print('レスポンス形式確認: ${data.runtimeType} - ${data.keys.join(', ')}');

        // エラー情報の確認
        if (data is Map && data.containsKey('error_info')) {
          print('エラー情報を検出: ${data['error_info']}');
          return _createFallbackJson('エラー: ${data['error_info']}');
        }

        // Gemini APIは直接textフィールドを返す
        if (data is Map && data.containsKey('text')) {
          String content = data['text'];
          print('有効なレスポンスを受信しました');

          // Markdownコードブロック（```）の除去
          content = _cleanMarkdownCodeBlocks(content);

          // APIからのレスポンスが有効なJSONか確認
          try {
            // そのままJSONとしてパースできるか確認
            jsonDecode(content); // パースの確認のみ、変数は使わない
            print('=== Geminiからのレスポンス（有効JSON） ===');
            return content; // 有効なJSONならそのまま返す
          } catch (e) {
            print('=== Geminiからの無効なレスポンス ===');
            print('パースエラー: $e');
            // レスポンスからJSONを抽出してみる
            print('テキストからJSONを抽出してみます...');
            final extractedJson = _extractValidJson(content);
            return extractedJson;
          }
        } else {
          print('無効なレスポンス形式です: textフィールドが見つかりません');
          print('利用可能なフィールド: ${data is Map ? data.keys.join(', ') : 'なし'}');
          return _createFallbackJson('サーバーからのレスポンス形式が無効です');
        }
      } catch (funcError) {
        print('関数実行エラー: $funcError');
        String errorMsg = 'Firebase関数の呼び出し中にエラーが発生しました';

        if (funcError is FirebaseFunctionsException) {
          final code = funcError.code;
          final details = funcError.details;
          print('エラーコード: $code, 詳細: ${details ?? 'なし'}');
          errorMsg = 'エラー($code): ${funcError.message}';
        }

        return _createFallbackJson(errorMsg);
      }
    } catch (outerError) {
      print('全体エラー: $outerError');
      return _createFallbackJson('APIリクエスト中に予期しないエラーが発生しました');
    }
  }

  /// AIによるユーザーの暗記法説明評価
  @override
  Future<String> getFeedback(String userExplanation,
      {String? contentTitle, String? contentText}) async {
    if (!_isUserAuthenticated()) {
      return '認証が必要です。ログインしてください。';
    }

    // 同じ入力に対して同じフィードバックを返すためのキャッシュを使用
    // キャッシュキーを作成
    final cacheKey =
        '$userExplanation-${contentTitle ?? ""}-${contentText ?? ""}';

    // キャッシュにあればそれを返す
    if (_feedbackCache.containsKey(cacheKey)) {
      return _feedbackCache[cacheKey]!;
    }

    final contentInfo = contentTitle != null && contentText != null
        ? '''
暗記内容のタイトル: $contentTitle
暗記内容: $contentText

'''
        : '';

    final prompt = '''
あなたはユーザーの暗記を補助するAIアシスタントです。ユーザーが暗記物の内容についてあなたに説明します。ユーザーが本質的なところを正しく暗記できているかどうかを評価してください。

$contentInfoユーザーの説明：
$userExplanation

日本語で簡潔に優しく回答してください。以下のなかから評価してください：
1. 内容の正確さ
2. 理解度
3. 足りない点と改善案

JSON形式ではなく、直接テキストとして回答してください。
''';

    try {
      // 新しいFirebase Functionを呼び出し
      final HttpsCallable callable = _functions.httpsCallable('proxyGemini');

      // Gemini APIに適した形式でリクエストを構築
      final requestData = {
        'model': 'gemini-2.5-flash-preview-04-17',
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generation_config': {'temperature': 0.5, 'max_output_tokens': 20000}
      };

      // Firebase Functionsに送信するデータ形式に変換
      final functionRequestData = {'data': requestData};

      print('getFeedback: Gemini API向けにリクエストを送信します');
      final result = await callable.call(functionRequestData);
      final data = result.data;

      // Gemini APIのレスポンス形式をチェック
      String feedback;

      // 新しいGemini APIのレスポンス形式（text形式）をチェック
      if (data.containsKey('text') && data['text'] is String) {
        // text形式のレスポンスを直接使用
        feedback = data['text'];
        print('フィードバック - テキスト形式のレスポンスを検出: $feedback');
      }
      // 従来の形式（choices形式）もチェック（互換性のため）
      else if (data.containsKey('choices') &&
          data['choices'] is List &&
          data['choices'].isNotEmpty &&
          data['choices'][0].containsKey('message') &&
          data['choices'][0]['message'].containsKey('content')) {
        final content = data['choices'][0]['message']['content'];

        // JSON形式かチェック
        try {
          if (content.trim().startsWith('{') && content.trim().endsWith('}')) {
            final parsedJson = jsonDecode(content);

            // JSONから評価内容を抽出
            if (parsedJson is Map && parsedJson.containsKey('feedback')) {
              feedback = parsedJson['feedback'];
            } else if (parsedJson is Map && parsedJson.containsKey('content')) {
              feedback = parsedJson['content'];
            } else {
              // 基本的な構造がない場合はJSON全体を返す
              feedback = content;
            }
          } else {
            // JSONではないテキストの場合はそのまま使用
            feedback = content;
          }
        } catch (jsonError) {
          // JSON解析エラーの場合は元のテキストを使用
          print('フィードバックJSON解析エラー: $jsonError');
          feedback = content;
        }
      } else {
        // 未知の形式の場合はエラーメッセージを返す
        feedback = 'フィードバックの取得に失敗しました。レスポンス形式が無効です。';
        print('未知のレスポンス形式: $data');
      }

      // キャッシュに保存
      _feedbackCache[cacheKey] = feedback;

      return feedback;
    } catch (e) {
      print('フィードバック生成エラー: $e');
      return 'ご説明ありがとうございます。現在サーバーに接続できませんので、評価を行うことができません。しばらくしてから再度お試しください。';
    }
  }

  /// 「考え方モード」で内容の本質を捕えた簡潔な説明を生成します
  @override
  Future<String> generateThinkingModeExplanation({
    required String content,
    String? title,
  }) async {
    if (!_isUserAuthenticated()) {
      return 'エラー: ログインが必要です。';
    }

    // タイトルがあれば含める
    final titleInfo = title != null ? '学習内容のタイトル: $title\n' : '';

    final prompt = '''
あなたは暗記学習をサポートする専門家です。与えられた内容について、内容の本質や原理を捕えた「考え方」を生成してください。

これは個々の事実を記憶するのではなく、内容の行間を読み、原理や関係性を理解することで記憶を定着させる「考え方モード」です。

以下の学習内容に対して、「～は～と考えよう」という形式で簡潔な説明を優しく提供してください。

$titleInfo学習内容:
$content

説明は1～2文程度の簡潔なものにしてください。必要以上に詳細にならないように、わかりやすさを重視してください。例えば、sinの微分がcosになる内容なら「sinは変化率がちょうどcosで表されると考えよう。微分の公式と加法定理から導出できるね。」のような説明です。

この回答はユーザーに直接表示されます。

非常に重要: この回答はプレーンテキストまたはLaTeXで直接返してください。JSONやマークダウンなどの特殊形式は一切使用しないでください。「～は～と考えよう」という形式で説明だけを簡潔に返してください。
''';

    try {
      // 新しいFirebase Functionを呼び出し（V2バージョン）
      final HttpsCallable callable = _functions.httpsCallable('proxyGemini');
      // generateTextメソッドと同じリクエスト形式を使用
      final Map<String, dynamic> requestData = {
        'model': 'gemini-2.5-pro-preview-03-25', // 考え方モードにはPro版が適している
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': '暗記学習の専門家として、以下の内容について「～と考えよう」形式で簡潔に回答してください。\n' 'プレーンテキストのみ使用し、JSONやマークダウンは使わないでください。\n\n' +
                    prompt
              }
            ]
          }
        ],
        'generation_config': {
          // generationConfigをgeneration_configに変更
          'temperature': 0.7,
          'max_output_tokens': 20000 // max_tokensをmax_output_tokensに変更
        }
      };

      // リクエストデータを正しい形式に変更
      final functionRequestData = {'data': requestData};

      final result = await callable.call(functionRequestData);
      final data = result.data;
      print('Geminiからのレスポンスを受信: $data');

      // 新しいGemini APIのレスポンス形式（text形式）をチェック
      if (data.containsKey('text') && data['text'] is String) {
        // text形式のレスポンスを直接使用
        String responseText = data['text'];
        print('考え方モード - テキスト形式のレスポンスを検出: $responseText');
        return responseText;
      }
      // 従来の形式（choices形式）もチェック（互換性のため）
      else if (data.containsKey('choices') &&
          data['choices'] is List &&
          data['choices'].isNotEmpty &&
          data['choices'][0].containsKey('message') &&
          data['choices'][0]['message'].containsKey('content')) {
        String responseContent = data['choices'][0]['message']['content'];
        print('考え方モード - 従来形式のレスポンスを検出');

        try {
          // JSON形式のレスポンスをテキストとして抽出する処理
          if (responseContent.trim().startsWith('{') &&
              responseContent.trim().endsWith('}')) {
            final parsedJson = jsonDecode(responseContent);

            // 各種フィールドからテキストを抽出
            if (parsedJson is Map) {
              // 優先順位でフィールドをチェック
              final possibleFields = [
                '考え方',
                'thinking',
                'explanation',
                'description'
              ];

              for (final field in possibleFields) {
                if (parsedJson.containsKey(field) &&
                    parsedJson[field] is String) {
                  return parsedJson[field];
                }
              }

              // 上記フィールドがない場合は、最初のString値を使用
              for (final key in parsedJson.keys) {
                if (parsedJson[key] is String) {
                  return parsedJson[key];
                }
              }
            }
          }
        } catch (e) {
          print('JSON解析エラー（考え方モード）: $e');
          // エラー時は元のテキストを使用
        }

        // テキストを整形して返す
        final cleanedExplanation =
            _cleanThinkingModeExplanation(responseContent);
        return cleanedExplanation;
      } else {
        return '考え方モードの生成に失敗しました。レスポンス形式が無効です。';
      }
    } catch (e) {
      print('考え方モードの生成エラー: $e');
      return '考え方モードの生成に失敗しました。後で再度お試しください。';
    }
  }

  /// Markdownのコードブロック記法（```）を除去する
  String _cleanMarkdownCodeBlocks(String text) {
    if (text.isEmpty) {
      return '';
    }

    // ```json ... ``` のようなコードブロック記法を除去
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(.+?)\s*```', dotAll: true);
    final match = codeBlockRegex.firstMatch(text);

    if (match != null) {
      // コードブロック内のコンテンツのみを取得
      final extractedJson = match.group(1);
      print('コードブロックからJSONを抽出: $extractedJson');
      return extractedJson?.trim() ?? '';
    }

    // 先頭と末尾の```を削除
    String cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final firstEndBlock = cleaned.indexOf('```', 3);
      if (firstEndBlock != -1) {
        cleaned =
            cleaned.substring(cleaned.indexOf('\n') + 1, firstEndBlock).trim();
      } else {
        // 終了マークがない場合は先頭の```のみ削除
        cleaned = cleaned.substring(cleaned.indexOf('\n') + 1).trim();
      }
    }

    return cleaned;
  }

  // 考え方モードの説明から余計な言葉を削除するヘルパーメソッド
  String _cleanThinkingModeExplanation(String explanation) {
    // 「これは」「つまり」「要するに」などの導入句を除去
    final patterns = [
      RegExp(r'^これは'),
      RegExp(r'^つまり'),
      RegExp(r'^要するに'),
      RegExp(r'^実は'),
      RegExp(r'^簡単に言うと'),
      RegExp(r'^以上、'),
      RegExp(r'^ハイ、'),
      RegExp(r'^分かりました。'),
      RegExp(r'^この内容は'),
    ];

    String cleaned = explanation.trim();

    for (var pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }

    // 最初の文字を大文字にして読みやすくする
    if (cleaned.isNotEmpty) {
      final firstChar = cleaned.substring(0, 1);
      final rest = cleaned.substring(1);
      cleaned = firstChar + rest;
    }

    return cleaned.trim();
  }
}
