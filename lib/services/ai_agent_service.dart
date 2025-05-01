import 'dart:convert';
import 'dart:math';
import '../models/memory_technique.dart';
import '../models/ranked_memory_technique.dart';
import 'ai_service_interface.dart';

class AIAgentService {
  final AIServiceInterface _aiService;

  AIAgentService(this._aiService);

  /// 第一エージェント: 6個の覚え方を生成する
  Future<List<MemoryTechnique>> generateMemoryTechniques(String content) async {
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
      final jsonResponse = await _aiService.generateText(
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
      final jsonResponse = await _aiService.generateText(
        prompt: prompt,
        model: 'gemini-2.5-pro-preview-03-25', // 評価タスクにはプロモデルが適切
        temperature: 0.3, // 低温度で評価の一貫性を確保
        maxTokens: 20000, // JSON応答に十分な長さ
      );

      print('=== Second Agent Response ===');
      print(jsonResponse.substring(0, min(200, jsonResponse.length)));
      print('===========================');

      try {
        // JSONレスポンスからランク付けされたテクニックを取り出す
        return _parseRankedTechniquesFromJson(jsonResponse);
      } catch (parseError) {
        print('JSONパースエラー: $parseError');
        print(
            '受信したレスポンス形式が不正: ${jsonResponse.substring(0, min(300, jsonResponse.length))}...');

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
          'Cleaned JSON: ${cleanedJson.substring(0, min(100, cleanedJson.length))}...');

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

      // DeepSeekの応答でよくある引用符で囲まれたJSONを処理
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
