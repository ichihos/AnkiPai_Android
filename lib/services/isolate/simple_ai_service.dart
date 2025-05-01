import 'dart:convert';
import 'dart:math' as math;
import 'package:anki_pai/models/memory_technique.dart';
import 'package:anki_pai/models/ranked_memory_technique.dart';
import 'package:http/http.dart' as http;

/// Isolate内で使用する簡易版AIサービス
/// BackgroundProcessorのIsolateから呼び出され、API呼び出しを実行する
/// Gemini APIを直接使用する実装（トークンベース）
class SimpleAIService {
  // HTTPクライアント
  final http.Client _httpClient = http.Client();

  // APIトークン
  final String apiToken;

  // Gemini APIの設定
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1';
  static const String _geminiProModel = 'models/gemini-2.5-pro-preview-03-25';
  static const String _geminiFlashModel =
      'models/gemini-2.5-flash-preview-04-17';
  static const String _generateContentEndpoint = 'generateContent';

  // キャッシュ用Map
  final Map<String, String> _feedbackCache = {};

  SimpleAIService({required this.apiToken}) {
    print('SimpleAIService initialized with token-based API access');
  }

  // APIキーが有効か確認
  bool get hasValidApiKey => apiToken.isNotEmpty;

  /// Gemini APIを使用してテキスト生成
  Future<String> generateText({
    required String prompt,
    String model = 'gemini-2.5-pro-preview-03-25',
    double temperature = 0.7,
    int maxTokens = 20000,
  }) async {
    try {
      if (!hasValidApiKey) {
        return _createFallbackJson('有効なAPIトークンがありません');
      }

      // APIエンドポイントを決定
      final String modelPath;
      if (model.contains('flash')) {
        modelPath = _geminiFlashModel;
      } else {
        modelPath = _geminiProModel;
      }

      // APIリクエストを作成
      final url = Uri.parse(
          '$_baseUrl/$modelPath:$_generateContentEndpoint?key=$apiToken');

      // Vertex AI Gemini API向けのリクエストボディを作成
      final requestBody = {
        'contents': [
          {
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
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
          'topP': 0.95,
          'topK': 40,
        }
      };

      print('リクエスト開始: Vertex AI Gemini APIを呼び出します (model: $model)');
      print('トークン別APIアクセス: エンドポイントに直接リクエストします');

      // API呼び出し
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('レスポンス受信: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('エラー: Vertex AI Gemini APIエラー ${response.statusCode}');
        print('エラーレスポンス: ${response.body}');
        return _createFallbackJson('エラーコード: ${response.statusCode}');
      }

      // レスポンスの解析
      final data = json.decode(response.body);
      print('レスポンス形式: ${data.keys.join(', ')}');

      if (data == null) {
        print('エラー: レスポンスデータがnullです');
        return _createFallbackJson('サーバーからのレスポンスを受信できませんでした');
      }

      // レスポンス構造をチェックしてテキストを抽出
      String text;
      if (data.containsKey('candidates') &&
          data['candidates'] is List &&
          data['candidates'].isNotEmpty &&
          data['candidates'][0].containsKey('content') &&
          data['candidates'][0]['content'].containsKey('parts') &&
          data['candidates'][0]['content']['parts'] is List &&
          data['candidates'][0]['content']['parts'].isNotEmpty) {
        text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        print('有効なレスポンスを受信: Vertex AI Gemini標準レスポンス形式');
      } else {
        print(
            'レスポンス形式が予期と異なります: ${json.encode(data).substring(0, math.min(300, json.encode(data).length))}');
        return _createFallbackJson('レスポンス形式が無効です');
      }

      // Markdownコードブロック（```）の除去
      final cleanedContent = _cleanMarkdownCodeBlocks(text);

      // APIからのレスポンスが有効なJSONか確認
      try {
        // そのままJSONとしてパースできるか確認
        jsonDecode(cleanedContent); // パースの確認のみ、変数は使わない
        print('有効なJSONレスポンスを確認しました');
        return cleanedContent; // 有効なJSONならそのまま返す
      } catch (e) {
        print('パースエラー: $e');
        // レスポンスからJSONを抽出してみる
        print('テキストからJSONを抽出します...');
        final extractedJson = _extractValidJson(cleanedContent);
        return extractedJson;
      }
    } catch (e) {
      print('全体エラー: $e');
      return _createFallbackJson('APIリクエスト中に予期しないエラーが発生しました');
    }
  }

  /// 入力内容から複数の項目を検出します
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    if (!hasValidApiKey) {
      return {
        'isMultipleItems': false,
        'items': [],
        'rawContent': content,
        'itemCount': 0,
        'message': 'APIトークンエラー',
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
5. 箱条書きリスト
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
      // Gemini APIを直接呼び出すように変更
      final url = Uri.parse(
          '$_baseUrl/$_geminiFlashModel:$_generateContentEndpoint?key=$apiToken');
      final response = await _httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 1000,
            'topP': 0.95,
            'topK': 40,
          },
        }),
      );

      if (response.statusCode != 200) {
        print('複数項目検出 APIエラー: ${response.statusCode}');
        return {
          'isMultipleItems': false,
          'items': [],
          'message': 'APIエラー: ${response.statusCode}',
        };
      }

      // レスポンスの解析
      final responseData = json.decode(response.body);
      final text = responseData['candidates'][0]['content']['parts'][0]['text']
          as String;

      // レスポンスからJSONを抽出
      try {
        // 新しい軽量フォーマットを処理
        final Map<String, dynamic> parsedResponse = jsonDecode(text);

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

  /// AIによるユーザーの暗記法説明評価
  @override
  Future<String> getFeedback(String userExplanation,
      {String? contentTitle, String? contentText}) async {
    if (!hasValidApiKey) {
      return '有効なAPIトークンがありません。API設定を確認してください。';
    }

    // 同じ入力に対して同じフィードバックを返すためのキャッシュを使用
    // キャッシュキーを作成
    final cacheKey =
        '${contentTitle ?? ''}_${contentText ?? ''}_$userExplanation';

    // キャッシュにある場合はそれを返す
    if (_feedbackCache.containsKey(cacheKey)) {
      print('キャッシュからフィードバックを取得します');
      return Future.value(_feedbackCache[cacheKey]);
    }

    // タイトルとコンテンツの情報
    final titleInfo = contentTitle != null ? 'タイトル: $contentTitle\n' : '';
    final contentInfo = contentText != null ? '学習内容: $contentText\n\n' : '';

    // プロンプトの作成
    final prompt = '''
$titleInfo$contentInfoユーザーの説明：
$userExplanation

日本語で簡潔に優しく回答してください。以下のなかから評価してください：
1. 内容の正確さ
2. 理解度
3. 足りない点と改善案

JSON形式ではなく、直接テキストとして回答してください。
''';

    try {
      print('フィードバック生成: Vertex AI Gemini APIにリクエスト送信');
      final result = await generateText(
        prompt: prompt,
        model: 'gemini-2.5-flash-preview-04-17', // フィードバックには高速モデルが適している
        temperature: 0.5,
        maxTokens: 1000,
      );

      // キャッシュに保存
      _feedbackCache[cacheKey] = result;
      return result;
    } catch (e) {
      print('フィードバック生成エラー: $e');
      return 'ご説明ありがとうございます。現在サーバーに接続できませんので、評価を行うことができません。しばらくしてから再度お試しください。';
    }
  }

  /// 「考え方モード」で内容の本質を捕えた簡潔な説明を生成します
  Future<String> generateThinkingModeExplanation({
    required String content,
    String? title,
  }) async {
    try {
      if (!hasValidApiKey) {
        return '有効なAPIトークンがありません。API設定を確認してください。';
      }

      // タイトルがあれば含める
      final titleInfo = title != null ? '学習内容のタイトル: $title\n' : '';

      // プロンプトを作成
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

      print('考え方モード生成: Vertex AI Gemini APIにリクエスト送信');

      // Pro版モデルを使用（考え方の説明には高品質な出力が必要）
      const modelPath = _geminiProModel;
      final url = Uri.parse(
          '$_baseUrl/$modelPath:$_generateContentEndpoint?key=$apiToken');

      // リクエストボディを作成
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 400,
          'topP': 0.95,
          'topK': 40,
        }
      };

      // API呼び出し
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode != 200) {
        print('エラー: 考え方モード生成 API ${response.statusCode}');
        return '考え方モードの生成に失敗しました。しばらくしてから再度お試しください。';
      }

      // レスポンスの解析
      final data = json.decode(response.body);

      if (data == null) {
        return '考え方モードの生成中にエラーが発生しました。';
      }

      // レスポンス構造をチェックしてテキストを抽出
      if (data.containsKey('candidates') &&
          data['candidates'] is List &&
          data['candidates'].isNotEmpty &&
          data['candidates'][0].containsKey('content') &&
          data['candidates'][0]['content'].containsKey('parts') &&
          data['candidates'][0]['content']['parts'] is List &&
          data['candidates'][0]['content']['parts'].isNotEmpty) {
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        print('有効な考え方モードレスポンスを受信');

        // コードブロックやJSON表記を除去してテキストのみを返す
        final cleanedText = _cleanThinkingModeExplanation(text);
        return cleanedText;
      } else {
        print(
            'レスポンス形式が予期と異なります: ${json.encode(data).substring(0, math.min(300, json.encode(data).length))}');
        return '考え方モードの生成に失敗しました。レスポンス形式が無効です。';
      }
    } catch (e) {
      print('考え方モード生成エラー: $e');
      return '考え方モードの生成中に予期しないエラーが発生しました。';
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

  /// 考え方モードの説明から余計な言葉を削除するヘルパーメソッド
  String _cleanThinkingModeExplanation(String explanation) {
    // 「これは」「つまり」などの導入句を除去
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

  /// 第一エージェント: 6個の覚え方を生成する
  Future<List<MemoryTechnique>> generateMemoryTechniques(String content) async {
    if (!hasValidApiKey) {
      return [
        MemoryTechnique(
          name: '標準学習法',
          description: '繰り返し練習で覚えよう',
          type: 'concept',
        ),
      ];
    }

    final prompt = '''
あなたは暗記学習をサポートする専門家です。以下の内容に対して、シンプルでわかりやすい覚え方10個を提案してください。

【重要】以下の例のようなシンプルで直感的な覚え方を目指してください:

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。
例3: listen (聞く) → 「listenはリスが ん？と耳をすませて聞いている」とイメージする。
例4: substance (物質) → 「sub:下に、stance:立つもの」という語源から土台→物質と覚える。
例5: H,He,Li,Be,B,C,N,O,F,Ne → 「水兵リーベぼくの船」と覚える。

覚え方の文は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。イメージは必要ない場合は省略しても構いません。

回答は必ず以下のJSON形式でお願いします（UTF-8エンコーディングで回答してください）:

{
  "content": "$content", 
  "techniques": [
    {
      "name": "タイトル",  //15字以内目安
      "description": "〇〇は△△と覚えよう", // 具体的かつ簡潔な記憶方法の説明（30文字以内）
      "image": "短いイメージ描写（省略可能）", // オプショナル、30文字以内
      "type": "mnemonic"  // "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
    },
    /* ...他の9個の覚え方も同様の形式で... */
  ]
}

必ずこの正確なJSON形式を維持し、他の説明文を含めないでください。
覚え方はシンプルで直感的、覚えやすいものにしてください。
必ず10個の覚え方を提案してください。

記憶すべき内容:
"""
$content
"""
''';

    try {
      final jsonResponse = await generateText(
        prompt: prompt,
        model: 'gemini-2.5-pro-preview-03-25', // 高品質モデルを使用
        temperature: 0.7, // 創造性と一貫性のバランス
        maxTokens: 30000, // 十分な長さを確保
      );

      print('=== First Agent Response ===');
      print(jsonResponse);
      print('===========================');

      // JSONレスポンスからテクニックを取り出す
      return _parseTechniquesFromJson(jsonResponse);
    } catch (e) {
      print('第一エージェントでの生成に失敗しました: $e');
      return [
        MemoryTechnique(
          name: '標準学習法',
          description: '$contentは繰り返し練習で覚えよう',
          type: 'concept',
        ),
      ];
    }
  }

  /// 第二エージェント: 生成された10個の覚え方を評価し、上位3つを選定する
  Future<RankedMemoryTechnique> evaluateAndRankTechniques(
    String content,
    List<MemoryTechnique> techniques,
  ) async {
    // 3個に満たない場合は、そのまま返す（評価の必要なし）
    if (techniques.length <= 3) {
      return RankedMemoryTechnique(techniques: techniques);
    }

    final techniquesJson = jsonEncode(techniques
        .map((t) => {
              'name': t.name,
              'description': t.description,
              'type': t.type,
            })
        .toList());

    final prompt = '''
あなたは記憶と学習の評価を専門とするエージェントです。
以下の内容に対して生成された覚え方について、正確性と覚えやすさの観点から評価し、上位3つを選択してください。

評価基準:
1. 正確性: 内容を正確に反映しているか
2. 覚えやすさ: 言葉のリズム、イメージのしやすさ、連想のしやすさ
3. 実用性: 実際に使いやすく、長期記憶に残りやすいか

各覚え方には、その内容を表す短く分かりやすいタイトルを必ず付けてください。「覚え方1」「第1位」などの単なる順位や番号だけではなく、内容を反映した具体的なタイトル（例：「音韻連想法」「イメージマッピング」「時系列連結法」など）を付けてください。

また、各覚え方について以下の情報も指定してください：
1. タイプ: 「mnemonic」(語呂合わせ), 「relationship」(関係性), 「concept」(考え方) のいずれかを必ず指定
2. タグ: 学習カテゴリを表すタグ（5つ以内）
3. キーワード: 内容の重要単語（5つ以内）

以下のJSON形式で回答してください:

{
  "evaluation": [
    {
      "rank": 1,
      "name": "最も優れた覚え方の具体的なタイトル",
      "description": "最も優れた覚え方の説明",
      "type": "mnemonic",  // "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
      "tags": ["タグ1", "タグ2"],  // 学習カテゴリを表すタグ（5つ以内）
      "contentKeywords": ["キーワード1", "キーワード2"],  // 内容の重要単語（5つ以内）
      "flashcards": [
        {
          "front": "質問の例・前面",
          "back": "回答の例・裏面"
        }
      ]  // この要素はメモリテクニックから生成されたフラッシュカード
    },
    {
      "rank": 2,
      "name": "2番目に優れた覚え方の具体的なタイトル",
      "description": "2番目に優れた覚え方の説明",
      "type": "relationship",  // "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
      "tags": ["タグ1", "タグ2"],  // 学習カテゴリを表すタグ（5つ以内）
      "contentKeywords": ["キーワード1", "キーワード2"],  // 内容の重要単語（5つ以内）
      "flashcards": [
        {
          "front": "質問の例・前面",
          "back": "回答の例・裏面"
        }
      ]  // この要素はメモリテクニックから生成されたフラッシュカード
    },
    {
      "rank": 3,
      "name": "3番目に優れた覚え方の具体的なタイトル",
      "description": "3番目に優れた覚え方の説明",
      "type": "concept",  // "mnemonic"(語呂合わせ), "relationship"(関係性), "concept"(考え方) のいずれか
      "tags": ["タグ1", "タグ2"],  // 学習カテゴリを表すタグ（5つ以内）
      "contentKeywords": ["キーワード1", "キーワード2"],  // 内容の重要単語（5つ以内）
      "flashcards": [
        {
          "front": "質問の例・前面",
          "back": "回答の例・裏面"
        }
      ]  // この要素はメモリテクニックから生成されたフラッシュカード
    }
  ]
}

必ずこの正確なJSON形式を維持し、他の説明文を含めないでください。

記憶すべき内容:
"""
$content
"""

提案された覚え方:
$techniquesJson
''';

    try {
      // Geminiリクエストフォーマットに合わせたリクエスト
      final jsonResponse = await generateText(
        prompt: prompt,
        model: 'gemini-2.5-pro-preview-03-25', // 評価タスクにはプロモデルが適切
        temperature: 0.3, // 低温度で評価の一貫性を確保
        maxTokens: 20000, // JSON応答に十分な長さ
      );

      print('=== Second Agent Response ===');
      print(jsonResponse.substring(0, math.min(200, jsonResponse.length)));
      print('===========================');

      try {
        // JSONレスポンスからランク付けされたテクニックを取り出す
        return _parseRankedTechniquesFromJson(jsonResponse);
      } catch (parseError) {
        print('JSONパースエラー: $parseError');
        print(
            '受信したレスポンス形式が不正: ${jsonResponse.substring(0, math.min(300, jsonResponse.length))}...');

        // 代替策：手動でJSONを構築して上位3つの技術を返す
        final topThreeTechniques = techniques.take(3).toList();
        final List<Map<String, dynamic>> evaluationItems = [];

        for (int i = 0; i < topThreeTechniques.length; i++) {
          final technique = topThreeTechniques[i];
          evaluationItems.add({
            'rank': i + 1,
            'name': technique.name,
            'description': technique.description,
            'type': technique.type,
            'tags': technique.tags,
            'contentKeywords': technique.contentKeywords,
          });
        }

        final fixedJson = json.encode({'evaluation': evaluationItems});
        return _parseRankedTechniquesFromJson(fixedJson);
      }
    } catch (e) {
      print('第二エージェントでの評価に失敗しました: $e');

      // エラー時は、最初の3つ（または全部）を返す
      final limitedTechniques =
          techniques.length > 3 ? techniques.sublist(0, 3) : techniques;

      return RankedMemoryTechnique(
        techniques: limitedTechniques,
      );
    }
  }

  /// マルチエージェントプロセス全体を実行する
  Future<RankedMemoryTechnique> generateRankedMemoryTechniques(
      String content) async {
    print('マルチエージェントモードで記憶テクニック生成を開始');

    try {
      // 第一エージェント: 覚え方を生成
      final techniques = await generateMemoryTechniques(content);
      print('エージェント1: ${techniques.length}個の記憶法を生成しました');

      // テクニックが生成されなかった場合
      if (techniques.isEmpty) {
        print('エージェント1から有効な記憶法が生成されませんでした');
        return RankedMemoryTechnique(techniques: [
          MemoryTechnique(
            name: '標準学習法',
            description: '$contentは繰り返し学習と関連付けで覚えよう',
            type: 'concept',
            tags: ['基本', '反復学習'],
            contentKeywords: ['基本', '学習', '記憶'],
            flashcards: [
              Flashcard(
                  question: '$contentを説明してください',
                  answer: '$contentは繰り返し学習と関連付けで記憶できます')
            ],
          ),
        ]);
      }

      // 第二エージェント: 生成された覚え方を評価・ランク付け
      return await evaluateAndRankTechniques(content, techniques);
    } catch (e) {
      print('マルチエージェントモードエラー: $e');
      return RankedMemoryTechnique(techniques: [
        MemoryTechnique(
          name: 'ベーシック学習法',
          description: '$contentは繰り返し練習で覚えよう',
          type: 'concept',
          tags: ['基本'],
        ),
      ]);
    }
  }

  // JSONレスポンスから暗記法を取り出す
  List<MemoryTechnique> _parseTechniquesFromJson(String jsonString) {
    try {
      // 余分なテキストを削除してJSONのみを抽出
      final String cleanedJson = _extractJsonString(jsonString);

      final Map<String, dynamic> data = jsonDecode(cleanedJson);

      if (data.containsKey('techniques') && data['techniques'] is List) {
        final List<dynamic> techniquesData = data['techniques'];

        return techniquesData.map((item) {
          return MemoryTechnique(
            name: item['name'] ?? '名称なし',
            description: item['description'] ?? '説明なし',
            type: item['type'] ?? 'mnemonic',
            tags:
                item['tags'] != null ? List<String>.from(item['tags']) : ['一般'],
            contentKeywords: item['contentKeywords'] != null
                ? List<String>.from(item['contentKeywords'])
                : [],
          );
        }).toList();
      }
    } catch (e) {
      print('JSONのパースエラー: $e');
      print('対象のJSON文字列: $jsonString');
    }

    return [];
  }

  // JSONレスポンスからランク付けされた暗記法を取り出す
  RankedMemoryTechnique _parseRankedTechniquesFromJson(String jsonString) {
    try {
      // 余分なテキストを削除してJSONのみを抽出
      final String cleanedJson = _extractJsonString(jsonString);
      print(
          'Cleaned JSON: ${cleanedJson.substring(0, math.min(100, cleanedJson.length))}...');

      // JSONをデコードする前に形式を確認
      Map<String, dynamic> data;
      try {
        data = jsonDecode(cleanedJson);
      } catch (e) {
        print('JSON解析エラー: $e');
        print('解析対象JSON: $cleanedJson');
        throw FormatException('JSONデコードに失敗しました: $e');
      }

      if (data.containsKey('evaluation') && data['evaluation'] is List) {
        final List<dynamic> evaluationData = data['evaluation'];
        final List<MemoryTechnique> techniques = [];

        // 配列型のフィールドを安全に処理する関数
        List<String> extractStringList(dynamic value) {
          if (value is List) {
            return value.map((item) => item.toString()).toList();
          }
          // 文字列の場合はカンマで分割して処理（Geminiもタグを文字列で返すことがある）
          if (value is String) {
            return value
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          return [];
        }

        // コンテンツからキーワードを抽出
        // Gemini APIでは、キーワード抽出は自動的に行われるため、カスタムメソッドは不要になりました

        // ランクで並べ替え
        for (var item in evaluationData) {
          print('Processing ranked technique: $item');

          // タグとキーワードを処理（第2エージェントの新しいフォーマット対応）
          List<String> tags = extractStringList(item['tags']);
          // AIランク位のタグは追加しないように変更

          // 一般カテゴリが含まれていなければ追加
          if (tags.isEmpty || !tags.contains('一般')) {
            tags.insert(0, '一般');
          }

          // フラッシュカードの扱い（新しい形式に対応）
          List<Flashcard> flashcards = [];
          if (item.containsKey('flashcards') && item['flashcards'] is List) {
            for (var cardData in item['flashcards']) {
              if (cardData is Map &&
                  cardData.containsKey('front') &&
                  cardData.containsKey('back')) {
                flashcards.add(
                  Flashcard(
                    question: cardData['front'] ?? '',
                    answer: cardData['back'] ?? '',
                  ),
                );
              }
            }
          }

          techniques.add(MemoryTechnique(
            name: item['name'] ?? '標準学習法',
            description: item['description'] ?? '繰り返し学習することで記憶を定着させる方法です。',
            type: item['type'] ?? 'concept',
            tags: tags,
            contentKeywords: extractStringList(item['contentKeywords']),
            flashcards: flashcards,
          ));
        }

        return RankedMemoryTechnique(techniques: techniques);
      }
    } catch (e) {
      print('ランク付けJSONのパースエラー: $e');
      print('対象のJSON文字列: $jsonString');
    }

    return RankedMemoryTechnique(techniques: []);
  }

  // 文字列からJSON部分を抽出するヘルパーメソッド
  // JSON文字列を抽出し、必要に応じて修復するメソッド
  String _extractJsonString(String input) {
    // 入力文字列がnullまたは空の場合は空の辞書型JSONを返す
    if (input.isEmpty) {
      return '{}';
    }

    // Step 1: 最初に通常の方法でJSONを探す
    // より積極的なJSONの検出 - 括弧の開始から終了までを検出
    final RegExp jsonRegex = RegExp(r'(\{[\s\S]*\}|\[[\s\S]*\])');
    final match = jsonRegex.firstMatch(input);

    if (match != null) {
      String extracted = match.group(0) ?? input;
      
      if (extracted.startsWith('"') && extracted.endsWith('"')) {
        extracted = extracted.substring(1, extracted.length - 1);
      }
      if (extracted.startsWith('"') && extracted.endsWith('"')) {
        extracted = extracted.substring(1, extracted.length - 1);
      }

      // エスケープされた引用符や改行コードを正規化
      extracted = extracted.replaceAll('\\"', '"');
      extracted = extracted.replaceAll('\\n', '\n');

      // JSONとして有効か確認
      try {
        jsonDecode(extracted);
        return extracted; // 有効なJSONなので返す
      } catch (e) {
        // 無効なJSONなので修復を試みる
        print('抽出されたJSONが無効です。修復を試みます: ${e.toString()}');
      }
    }

    // Step 2: 通常の方法で見つからなかった場合や無効だった場合、不完全なJSONを検出して修復を試みる
    try {
      return _repairIncompleteJson(input);
    } catch (e) {
      print('JSONの修復に失敗しました: ${e.toString()}');
      // どうしても修復できない場合は元の入力を返す
      return input;
    }
  }

  // 不完全なJSONを修復するメソッド
  String _repairIncompleteJson(String input) {
    // 最初の'{' または '[' を見つける
    int startIndex = input.indexOf('{');
    if (startIndex == -1) {
      startIndex = input.indexOf('[');
    }
    if (startIndex == -1) {
      return input; // JSONの開始文字が見つからない
    }

    // 開始文字から抽出
    String jsonPart = input.substring(startIndex);

    // 括弧のバランスをチェック
    int curlyCount = 0;
    int squareCount = 0;
    List<String> tokens = [];

    for (int i = 0; i < jsonPart.length; i++) {
      String char = jsonPart[i];
      if (char == '{') curlyCount++;
      if (char == '}') curlyCount--;
      if (char == '[') squareCount++;
      if (char == ']') squareCount--;
      tokens.add(char);
    }

    // 不完全なJSONの修復
    // 中括弧が不足している場合
    while (curlyCount > 0) {
      tokens.add('}');
      curlyCount--;
    }

    // 角括弧が不足している場合
    while (squareCount > 0) {
      tokens.add(']');
      squareCount--;
    }

    // 修復されたJSONを作成
    String repairedJson = tokens.join('');

    // 修復されたJSONが有効かチェック
    try {
      jsonDecode(repairedJson);
      print('JSONの修復に成功しました');
      return repairedJson;
    } catch (e) {
      print('修復後もJSONが無効です: ${e.toString()}');

      // 最後の手段：形式を整えてデフォルト値を返す
      if (repairedJson.startsWith('{')) {
        return '{"content":"データの解析に失敗しました", "techniques":[]}';
      } else if (repairedJson.startsWith('[')) {
        return '[]';
      }
      return input;
    }
  }
}
