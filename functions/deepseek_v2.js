const functions = require('firebase-functions');
const axios = require('axios');

/**
 * DeepSeek API向けの新しいプロキシ関数（V2）
 * 既存の関数のキャッシュ問題を回避するために新規作成
 */
exports.proxyDeepSeekV2 = functions
  .region('asia-northeast1') // asia-northeast1リージョンに統一
  .runWith({
    memory: '1GB',
    timeoutSeconds: 300
  })
  .https.onCall(async (data, context) => {
    // 認証チェック
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'ユーザー認証が必要です'
      );
    }

    try {
      // 設定全体をデバッグ（APIキーは一部マスク）
      const fullConfig = functions.config();
      console.log('Firebase設定オブジェクト:', JSON.stringify({
        hasDeepseek: !!fullConfig.deepseek,
        configKeys: fullConfig ? Object.keys(fullConfig) : [],
        deepseekKeys: fullConfig.deepseek ? Object.keys(fullConfig.deepseek) : []
      }));

      // 新しいAPIキー設定を使用
      let apiKey;
      try {
        apiKey = functions.config().deepseek.newkey;
        console.log(`APIキー取得: ${apiKey ? 'OK（設定あり）' : '失敗（設定なし）'}`);
      } catch (configError) {
        console.error('設定アクセスエラー:', configError);
        throw new functions.https.HttpsError(
          'failed-precondition',
          'DeepSeek API設定へのアクセスでエラーが発生しました'
        );
      }
      
      if (!apiKey) {
        console.error('新しいDeepSeek APIキーが設定されていません');
        throw new functions.https.HttpsError(
          'failed-precondition',
          'DeepSeek APIキーの設定が見つかりません、Firebase設定で deepseek.newkey が必要です'
        );
      }
      
      // APIキーの形式を検証
      if (!apiKey.startsWith('sk-')) {
        console.error(`DeepSeek APIキーの形式が無効です: ${apiKey.substring(0, 5)}...`);
        throw new functions.https.HttpsError(
          'invalid-argument',
          'APIキーの形式が無効です（sk-で始まる必要があります）'
        );
      }

      // リクエストデータを取得
      const requestData = data.data || {};
      if (!requestData.model || !requestData.messages) {
        console.error('不正なリクエストデータ:', requestData);
        throw new functions.https.HttpsError(
          'invalid-argument',
          'リクエストデータが不正です',
          { received: requestData }
        );
      }

      console.log('DeepSeekV2 APIへリクエストを送信:', {
        model: requestData.model,
        messagesCount: requestData.messages.length,
        timestamp: new Date().toISOString()
      });

      // リクエストパラメータを最適化
      if (requestData.model === 'deepseek-chat') {
        requestData.model = 'deepseek-chat';
      }

      if (requestData.model === 'deepseek-reasoner') {
        requestData.model = 'deepseek-reasoner';
      }

      // APIリクエスト情報をログに出力
      console.log(`APIキーの長さ: ${apiKey.length}文字, 先頭: ${apiKey.substring(0, 5)}...`);
      console.log(`リクエスト開始時間: ${new Date().toISOString()}`);
      console.log('DeepSeek API URL: https://api.deepseek.com/v1/chat/completions');

      let response;
      try {
        console.log('DeepSeek APIリクエスト実行開始');
        // DeepSeek APIリクエスト実行
        response = await axios({
          method: 'post',
          url: 'https://api.deepseek.com/v1/chat/completions',
          headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
          },
          data: requestData,
          timeout: 300000,  // 300秒タイムアウト（複数項目処理のためタイムアウト延長）
          validateStatus: (status) => true  // すべてのステータスコードを許可
        });
        
        console.log(`DeepSeek APIレスポンス受信完了: ステータス ${response.status}`);

        console.log(`APIレスポンス受信: ステータス ${response.status}`);
        
        // エラーステータスコードをチェック
        if (response.status !== 200) {
          console.error(`エラーレスポンス: ${response.status}`);
          console.error('レスポンス内容:', response.data);
          
          if (response.status === 401) {
            throw new functions.https.HttpsError(
              'unauthenticated',
              'DeepSeek API認証エラー: APIキーが無効です',
              response.data
            );
          } else {
            throw new functions.https.HttpsError(
              'internal',
              `DeepSeek APIエラー: ステータス ${response.status}`,
              response.data
            );
          }
        }

        // レスポンスのJSONをサニタイズして返す
        try {
          // レスポンスがJSONを含むか確認
          if (response.data && response.data.choices && 
              response.data.choices.length > 0 && 
              response.data.choices[0].message && 
              response.data.choices[0].message.content) {
            
            let content = response.data.choices[0].message.content;
            console.log('レスポンス内容の最初の50文字:', content.substring(0, Math.min(50, content.length)));
            
            // JSONレスポンスを修正
            if (content.includes('{') && content.includes('}')) {
              // コードブロックのクリーンアップ
              if (content.includes('```json')) {
                const startIdx = content.indexOf('```json') + 7;
                const endIdx = content.indexOf('```', startIdx);
                if (endIdx > startIdx) {
                  content = content.substring(startIdx, endIdx).trim();
                  console.log('マークダウンコードブロックからJSONを抽出しました');
                }
              } else if (content.includes('```')) {
                // jsonがない場合のコードブロック
                const startIdx = content.indexOf('```') + 3;
                const nextLine = content.indexOf('\n', startIdx);
                const endIdx = content.indexOf('```', nextLine > startIdx ? nextLine : startIdx);
                if (endIdx > startIdx) {
                  content = content.substring(nextLine > startIdx ? nextLine : startIdx, endIdx).trim();
                  console.log('マークダウンコードブロックからテキストを抽出しました');
                }
              }
              
              // JSONを有効な形式に修正する試み
              try {
                // そのままJSONとしてパースできるか確認
                const jsonObject = JSON.parse(content);
                console.log('DeepSeekからの有効なJSONを確認しました');
                
                // 必要なフィールドがあるか確認
                if (!jsonObject.name) {
                  jsonObject.name = '自動生成暗記法';
                }
                if (!jsonObject.description) {
                  jsonObject.description = '内容に基づいて自動生成された暗記法です';
                }
                if (!jsonObject.type) {
                  jsonObject.type = 'concept';
                }
                
                // 修正したJSONを保存
                response.data.choices[0].message.content = JSON.stringify(jsonObject);
                console.log('レスポンスJSONを修正しました');
              } catch (jsonError) {
                // JSONではない場合や不完全なJSONの場合
                console.warn('JSONパース失敗:', jsonError.message);
                
                // 不完全なJSONの修正を試みる
                try {
                  // 最後の}がないやつを修正
                  if (content.trim().startsWith('{') && !content.trim().endsWith('}')) {
                    const fixedContent = content.trim() + '}';
                    try {
                      // 修正したコンテンツで再試行
                      const repaired = JSON.parse(fixedContent);
                      console.log('不完全なJSONを修正しました');
                      response.data.choices[0].message.content = JSON.stringify(repaired);
                    } catch (e) {
                      console.warn('修正試行失敗:', e.message);
                    }
                  }
                } catch (repairError) {
                  console.warn('JSON修正失敗:', repairError.message);
                }
              }
            }
          }
        } catch (sanitizeError) {
          console.warn('JSONサニタイズ中にエラー発生:', sanitizeError.message);
          // エラー発生時も元のレスポンスを継続して返す
        }
        
        return response.data;
      } catch (requestError) {
        console.error('API呼び出しエラー:', requestError.message);
        
        // フォールバックレスポンスを生成
        return {
          choices: [{
            message: {
              content: JSON.stringify({
                name: 'シンプル暗記法',
                description: '重要ポイントを覚えよう',
                type: 'concept',
                tags: ['学習'],
                contentKeywords: ['キーワード'],
                flashcards: [{
                  question: '質問',
                  answer: '回答'
                }]
              })
            }
          }],
          error_info: requestError.message
        };
      }
    } catch (error) {
      console.error('DeepSeekV2 全体エラー:', error.message);
      console.error('エラースタック:', error.stack);
      
      // シンプルなフォールバックレスポンスを返す（エラーを投げない）
      return {
        choices: [{
          message: {
            content: JSON.stringify({
              name: 'シンプル暗記法',
              description: 'APIエラーが発生しました。もう一度試してください。',
              type: 'concept',
              tags: ['エラー'],
              contentKeywords: ['エラー'],
              flashcards: [{
                question: 'エラーが発生しました',
                answer: 'もう一度試してください'
              }]
            })
          }
        }],
        error_info: `DeepSeek APIエラー: ${error.message}`
      };
    }
  });
