import 'dart:convert';
import 'package:http/http.dart' as http;

/// バックグラウンド処理のためのシンプルなAIサービス
/// メインスレッドのAIサービスと分離し、Isolate内でも動作可能
class SimpleAIService {
  final String? deepseekApiKey;
  final String? openaiApiKey;
  final http.Client _httpClient = http.Client();
  
  SimpleAIService({this.deepseekApiKey, this.openaiApiKey});
  
  /// DeepSeekAPIを使って複数項目を検出
  Future<Map<String, dynamic>> detectMultipleItems(String content) async {
    try {
      if (deepseekApiKey == null || deepseekApiKey!.isEmpty) {
        return {'isMultipleItems': false};
      }
      
      final prompt = '''
複数の学習項目が含まれているか判断し、含まれている場合は分割してください。
内容：
$content

次のJSON形式で返してください：
{
  "isMultipleItems": true/false,
  "items": []
}
''';       
      
      final url = Uri.parse('https://api.deepseek.com/v1/chat/completions');
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $deepseekApiKey',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.1,
          'max_tokens': 800,
        }),
      );
      
      if (response.statusCode != 200) {
        print('DeepSeek API error: ${response.body}');
        return {'isMultipleItems': false};
      }
      
      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];
      
      // JSONを抽出
      try {
        final Map<String, dynamic> result = json.decode(_extractJsonFromText(responseText));
        return result;
      } catch (e) {
        print('JSON解析エラー: $e');
        return {'isMultipleItems': false};
      }
    } catch (e) {
      print('複数項目検出エラー: $e');
      return {'isMultipleItems': false};
    }
  }
  
  /// 複数項目に対する暗記法を生成
  Future<List<Map<String, dynamic>>> generateTechniquesForItems(List<dynamic> items) async {
    try {
      // 配列を5件ずつのバッチに分割して処理
      const int batchSize = 5;
      final List<Map<String, dynamic>> allTechniques = [];
      
      for (int i = 0; i < items.length; i += batchSize) {
        final int end = (i + batchSize < items.length) ? i + batchSize : items.length;
        final batch = items.sublist(i, end);
        
        // バッチごとに暗記法を生成
        final batchItems = batch.map((item) => {
          'content': item['content'] ?? '',
          'description': item['description'] ?? ''
        }).toList();
        
        final batchTechniques = await _generateMemoryTechniques(batchItems);
        allTechniques.addAll(batchTechniques);
      }
      
      return allTechniques;
    } catch (e) {
      print('複数項目の暗記法生成エラー: $e');
      return [];
    }
  }
  
  /// 単一項目の暗記法を生成
  Future<List<Map<String, dynamic>>> generateTechniquesForSingleItem(String content) async {
    try {
      final items = [
        {'content': content, 'description': ''}
      ];
      
      return await _generateMemoryTechniques(items);
    } catch (e) {
      print('単一項目の暗記法生成エラー: $e');
      return [];
    }
  }
  
  /// 暗記法生成の共通処理
  Future<List<Map<String, dynamic>>> _generateMemoryTechniques(List<dynamic> items) async {
    try {
      if (deepseekApiKey == null || deepseekApiKey!.isEmpty) {
        return _fallbackToOpenAI(items);
      }
      
      final contentList = items.map((item) => item['content'].toString()).toList();
      
      // DeepSeekの暗記法生成プロンプト
      final prompt = '''
あなたは暗記学習をサポートする専門家です。以下の${contentList.length}個の項目に対して、全体を表す簡潔なタイトル（20文字以内）とそれぞれの項目に対するシンプルでわかりやすい覚え方を提案してください。

【重要】以下の例のようなシンプルで直感的な覚え方を目指してください:

例1: wash (洗う) → 「washはウォッシュレットで洗う」と連想する。
例2: home (自宅) → 「homeはホーム(home)に帰る」でそのまま覚える。

覚え方の文は必ず「〜は〜と覚えよう」「〜は〜と連想しよう」などの形式にしてください。

学習項目一覧:
${contentList.asMap().entries.map((entry) {
  int i = entry.key;
  String content = entry.value;
  String description = '';
  if (items[i] is Map && items[i].containsKey('description')) {
    description = items[i]['description'] ?? '';
  }
  return '【項目${i + 1}】 "$content" ${description.isNotEmpty ? "(補足: $description)" : ""}';
}).join('\n')}

以下のJSON形式で返してください:
{
  "commonTitle": "学習内容の簡潔なタイトル（20文字以内）",
  "commonType": "mnemonic",
  "commonTags": ["共通カテゴリ"],
  "techniques": [
    {
      "itemIndex": 0,
      "originalContent": "元の内容",
      "name": "記憶法名",
      "description": "〜は〜と覚えよう",
      "type": "mnemonic",
      "image": "イメージ"
    }
  ]
}
''';      
      
      final url = Uri.parse('https://api.deepseek.com/v1/chat/completions');
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $deepseekApiKey',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 2000,
        }),
      );
      
      if (response.statusCode != 200) {
        print('DeepSeek API error: ${response.body}');
        return _fallbackToOpenAI(items);
      }
      
      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];
      
      // JSONを抽出して解析
      try {
        final cleanedJson = _extractJsonFromText(responseText);
        final Map<String, dynamic> result = json.decode(cleanedJson);
        
        if (!result.containsKey('techniques') || result['techniques'] == null) {
          return _fallbackToOpenAI(items);
        }
        
        // Map<String, dynamic>のリストに変換
        return List<Map<String, dynamic>>.from(result['techniques']);
      } catch (e) {
        print('JSON解析エラー: $e');
        return _fallbackToOpenAI(items);
      }
    } catch (e) {
      print('DeepSeek暗記法生成エラー: $e');
      return _fallbackToOpenAI(items);
    }
  }
  
  /// OpenAIへのフォールバック
  Future<List<Map<String, dynamic>>> _fallbackToOpenAI(List<dynamic> items) async {
    try {
      if (openaiApiKey == null || openaiApiKey!.isEmpty) {
        // フォールバックできないのでサンプル暗記法を返す
        return _generateSampleTechniques(items);
      }
      
      final contentList = items.map((item) => item['content'].toString()).toList();
      
      // OpenAIの暗記法生成プロンプト（簡略化）
      final prompt = '''
以下の内容に対する暗記法を提案してください：
${contentList.join('\n')}

JSON形式で返してください。
''';        
      
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');
      final response = await _httpClient.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openaiApiKey',
        },
        body: json.encode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );
      
      if (response.statusCode != 200) {
        return _generateSampleTechniques(items);
      }
      
      final responseData = json.decode(response.body);
      final responseText = responseData['choices'][0]['message']['content'];
      
      try {
        final cleanedJson = _extractJsonFromText(responseText);
        final data = json.decode(cleanedJson);
        
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('techniques')) {
          return List<Map<String, dynamic>>.from(data['techniques']);
        } else {
          return _generateSampleTechniques(items);
        }
      } catch (e) {
        return _generateSampleTechniques(items);
      }
    } catch (e) {
      return _generateSampleTechniques(items);
    }
  }
  
  /// サンプル暗記法生成（両方のAPIが失敗した場合のフォールバック）
  List<Map<String, dynamic>> _generateSampleTechniques(List<dynamic> items) {
    final List<Map<String, dynamic>> techniques = [];
    
    for (int i = 0; i < items.length; i++) {
      final content = items[i]['content'] ?? 'コンテンツなし';
      techniques.add({
        'itemIndex': i,
        'originalContent': content,
        'name': '標準学習法',
        'description': 'この内容は繰り返し学習することで記憶を定着させましょう',
        'type': 'concept',
        'image': '',
      });
    }
    
    return techniques;
  }
  
  /// テキストからJSONを抽出するヘルパーメソッド
  String _extractJsonFromText(String text) {
    // コードブロックの抽出試行
    final codeBlockRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final codeBlockMatch = codeBlockRegex.firstMatch(text);
    
    if (codeBlockMatch != null && codeBlockMatch.groupCount >= 1) {
      return codeBlockMatch.group(1)!.trim();
    }
    
    // 波括弧で囲まれた部分を抽出
    final jsonRegex = RegExp(r'\{[\s\S]*\}');
    final jsonMatch = jsonRegex.firstMatch(text);
    
    if (jsonMatch != null) {
      return jsonMatch.group(0)!;
    }
    
    // 見つからない場合は元のテキストを返す
    return text;
  }
  
  // クリーンアップ
  void dispose() {
    _httpClient.close();
  }
}
