const functions = require('firebase-functions');
const axios = require('axios');

/**
 * 画像のOCR処理に特化したシンプルな関数
 * GPT-4.1 miniを使用して画像からテキストを抽出する
 */
exports.performOcr = functions
  .region('asia-northeast1') // リージョンを明示的に指定
  .runWith({
    memory: '1GB',     // メモリを増やす
    timeoutSeconds: 60 // タイムアウトを設定
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
      const userId = context.auth.uid;
      console.log(`OCR処理開始 (ユーザー: ${userId})`);

      // APIキーを取得
      const apiKey = functions.config().openai.apikey;
      if (!apiKey) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'APIキーが設定されていません'
        );
      }

      // リクエストデータの検証
      let base64Image = data.imageData;
      if (!base64Image) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          '画像データがありません'
        );
      }
      
      // 形式を確認（data:image/jpeg;base64, のプレフィックスがあるか）
      if (base64Image.startsWith('data:')) {
        // すでにデータ URI 形式の場合はそのまま使用
        console.log('データ URI 形式の画像データが提供されています');
      } else {
        // 純粋なBase64の場合はプレフィックスを追加
        console.log('プレフィックスなしの純粋なBase64データをデータ URI 形式に変換します');
        base64Image = `data:image/jpeg;base64,${base64Image}`;
      }

      console.log(`画像データサイズ: ${base64Image.length} 文字, 先頭部分: ${base64Image.substring(0, 30)}...`);
      
      // データの始まりを検証
      if (!base64Image.includes('base64')) {
        console.warn('警告: base64形式でない可能性があります。強制的に形式を設定します。');
        // 強制的に形式を設定
        base64Image = `data:image/jpeg;base64,${base64Image}`;
      }

      // システムプロンプトを設定
      const systemPrompt = `あなたは画像からテキストを抽出するOCRアシスタントです。画像内のテキストをすべて正確に抽出し、元のフォーマットをできるだけ保持してください。数式や表、リストなど特殊な形式も適切に処理してください。`;

      // GPT-4.1 mini モデルにリクエスト
      let imageUrl;
      
      // プレフィックスの重複を防止
      if (base64Image.startsWith('data:')) {
        // データ URIをそのまま使用
        imageUrl = base64Image;
      } else {
        // 純粋なBase64にプレフィックスを追加
        imageUrl = `data:image/jpeg;base64,${base64Image}`;
      }
      
      console.log(`画像 URLの先頭: ${imageUrl.substring(0, 30)}...`);
      
      const requestBody = {
        model: 'gpt-4.1-mini', // GPT-4.1 mini モデル
        messages: [
          { role: 'system', content: systemPrompt },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: '画像内のすべてのテキストを抽出してください。'
              },
              {
                type: 'image_url',
                image_url: {
                  url: imageUrl
                }
              }
            ]
          }
        ],
        max_tokens: 1000,
        temperature: 0.1
      };

      console.log('OpenAI APIにリクエスト送信開始');
      
      try {
        const response = await axios({
          method: 'post',
          url: 'https://api.openai.com/v1/chat/completions',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
          },
          data: requestBody,
          timeout: 45000, // 45秒タイムアウトに延長
          validateStatus: function (status) {
            // すべてのステータスコードを許可し、エラーを自分で処理
            return true;
          }
        });
        
        // ステータスコードの確認
        if (response.status !== 200) {
          console.error(`OpenAI APIエラー: ステータスコード ${response.status}`);
          console.error('APIレスポンス:', response.data);
          throw new Error(`OpenAI APIからエラーレスポンス: ${response.status}`);
        }

        console.log('OCR処理成功');
        
        // レスポンスデータのログを記録
        console.log('APIレスポンス構造:', JSON.stringify(response.data).substring(0, 100) + '...');
        
        // レスポンスからテキストを抽出（レスポンス形式のエラーが起きた場合は安全に処理）
        let completion = '';
        
        try {
          if (response.data && 
              response.data.choices && 
              response.data.choices.length > 0 && 
              response.data.choices[0].message && 
              response.data.choices[0].message.content) {
              
            completion = response.data.choices[0].message.content;
            console.log('抽出したテキストの長さ:', completion.length);
          } else {
            console.warn('APIレスポンスに期待される形式のデータがありません');
            if (response.data && response.data.error) {
              throw new Error(`OpenAI APIエラー: ${response.data.error.message || JSON.stringify(response.data.error)}`);
            }
          }
        } catch (parseError) {
          console.error('APIレスポンス処理エラー:', parseError);
          // エラーがあっても継続 - デバッグ用に可能な限り多くの情報を返す
        }
        
        return {
          success: true,
          text: completion,
          model: 'gpt-4.1-mini',
          responseStatus: response.status
        };
      } catch (apiError) {
        // APIリクエスト中のエラーを詳細にログ
        console.error('OpenAI APIリクエストエラー:', apiError);
        
        // エラーレスポンスがあればそれを記録
        if (apiError.response) {
          console.error('APIエラーステータス:', apiError.response.status);
          console.error('APIエラーレスポンス:', JSON.stringify(apiError.response.data).substring(0, 500));
          
          throw new functions.https.HttpsError(
            'internal',
            `OpenAI APIエラー: ${apiError.response.status}`,
            { message: JSON.stringify(apiError.response.data) }
          );
        } else {
          throw new functions.https.HttpsError(
            'internal',
            'OpenAI API接続エラー',
            { message: apiError.message }
          );
        }
      }
    } catch (error) {
      console.error('OCR処理メインエラー:', error);
      
      // エラー情報の詳細を記録
      let errorDetail = {};
      if (error.response) {
        console.error('APIレスポンスエラー:', error.response.status, error.response.data);
        errorDetail = {
          status: error.response.status,
          data: error.response.data
        };
      }
      
      throw new functions.https.HttpsError(
        'internal',
        `OCR処理中にエラーが発生しました: ${error.message}`,
        errorDetail
      );
    }
  });


