const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const cors = require('cors')({origin: true});
const { GoogleAuth } = require('google-auth-library');

/**
 * OpenAI API へのプロキシリクエスト
 * クライアントからのリクエストを OpenAI API に転送し、結果を返す
 * メモリとタイムアウト設定を増やしてエラーを回避
 */
exports.proxyOpenAI = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .runWith({
    memory: '1GB',  // メモリを増やす（デフォルトは256MB）
    timeoutSeconds: 120  // タイムアウトも増やす（デフォルトは60秒）
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
    // OpenAI APIキーを取得
    let apiKey = functions.config().openai.apikey;
    
    // APIキーの形式をチェック
    if (apiKey && apiKey.startsWith('sk-proj-')) {
      console.warn('OpenAI プロジェクトAPIキーが検出されました。代替キーを使用します。');
      // 代替キーがあれば使用
      apiKey = functions.config().openai.alternative_key || functions.config().openai.standardkey;
    }
    
    if (!apiKey) {
      console.error('OpenAI APIキーが設定されていません');
      throw new functions.https.HttpsError(
        'failed-precondition',
        'OpenAI APIキーが設定されていません'
      );
    }
    
    // APIキーの形式を記録する(実際のキーは記録しない)
    console.log('APIキー形式: ' + (apiKey.startsWith('sk-') ? 'Standard Key' : 'Unknown Format'));
    
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
    
    console.log('OpenAI APIへリクエストを送信します:', {
      model: requestData.model,
      messagesCount: requestData.messages.length
    });

    // リクエストの詳細情報をログ出力
    console.log('OpenAI APIへのリクエスト開始:', new Date().toISOString());
    console.log('モデル:', requestData.model);
    console.log('メッセージ数:', requestData.messages.length);
    console.log('メッセージの形式を確認:', JSON.stringify(requestData.messages[0].role));
    
    // 画像データがある場合はサイズを出力
    if (requestData.messages.some(msg => Array.isArray(msg.content) && msg.content.some(item => item.type === 'image_url'))) {
      console.log('画像データサイズを含むメッセージをチェックしています...');
      try {
        // 内容が配列の場合
        for (const msg of requestData.messages) {
          if (Array.isArray(msg.content)) {
            for (const item of msg.content) {
              if (item.type === 'image_url' && item.image_url && item.image_url.url) {
                const url = item.image_url.url;
                if (url.startsWith('data:image')) {
                  // Base64画像の場合はサイズを測定
                  const commaIdx = url.indexOf(',');
                  const base64Length = url.length - commaIdx - 1;
                  console.log('リクエスト内のBase64画像サイズ:', (base64Length / 1024).toFixed(2), 'KB');
                  
                  // 画像サイズが大きすぎる場合は警告
                  if (base64Length > 1024 * 1024 * 10) { // 10MB以上
                    console.warn('警告: 画像サイズが非常に大きいです (' + (base64Length / 1024 / 1024).toFixed(2) + ' MB)');
                  }
                }
              }
            }
          }
        }
      } catch (imgError) {
        console.warn('画像サイズ計算中にエラー:', imgError.message);
      }
    }
    
    console.log('APIキー先頭文字:', apiKey.substring(0, 7) + '...');
    
    // API呼び出しを試みる
    try {
      console.log('OpenAI APIリクエスト実行開始');
      const response = await axios({
        method: 'post',
        url: 'https://api.openai.com/v1/chat/completions',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        data: requestData,
        timeout: 90000  // 90秒のタイムアウト設定（Functionsのタイムアウトより短く）
      });
      
      console.log('OpenAI APIからレスポンス受信:', new Date().toISOString());
      console.log('レスポンスステータス:', response.status);
      console.log('レスポンスデータ型:', typeof response.data);

      // レスポンスデータの構造チェック
      if (typeof response.data === 'object') {
        console.log('レスポンススキーマ:', Object.keys(response.data).join(', '));
        if (response.data.choices && Array.isArray(response.data.choices)) {
          console.log('受信した選択肢数:', response.data.choices.length);
        }
      }
  
      console.log('OpenAI APIからレスポンス受信完了');
      
      // レスポンスをそのまま返す
      return response.data;
    } catch (apiError) {
      console.error('OpenAI APIの直接呼び出しでエラーが発生しました:', apiError.message);
      if (apiError.response) {
        console.error('エラーステータス:', apiError.response.status);
        console.error('エラーデータ:', JSON.stringify(apiError.response.data));
      }
      // 外部のcatchブロックにエラーを導く
      throw apiError;
    }
  } catch (error) {
    // エラーログの詳細化
    console.error('OpenAI API エラー:', error.message);
    
    if (error.response) {
      // サーバーからのレスポンスでエラーが返された場合
      console.error('ステータスコード:', error.response.status);
      console.error('レスポンスデータ:', JSON.stringify(error.response.data));
    } else if (error.request) {
      // リクエストは行われたがレスポンスが返ってこなかった場合
      console.error('リクエストタイムアウトまたは接続エラー:', error.code);
    }
    
    // エラー情報を追加してクライアントに送信
    throw new functions.https.HttpsError(
      'internal',
      'OpenAI API リクエストでエラーが発生しました: ' + error.message,
      {
        error: error.message,
        status: error.response?.status,
        data: error.response?.data,
        code: error.code,
        timestamp: new Date().toISOString()
      }
    );
  }
});

/**
 * Google Vision API へのプロキシリクエスト
 * 画像解析を行う Google Vision API へのリクエストを転送
 */
exports.proxyVision = functions.https.onCall(async (data, context) => {
  // 認証チェック
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'ユーザー認証が必要です'
    );
  }

  try {
    // Google Vision APIキーを取得
    const apiKey = functions.config().google.vision_key;
    if (!apiKey) {
      console.error('Google Vision APIキーが設定されていません');
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Google Vision APIキーが設定されていません'
      );
    }

    // リクエストデータを取得
    const requestData = data.data || {};
    if (!requestData.requests) {
      console.error('不正なリクエストデータ:', requestData);
      throw new functions.https.HttpsError(
        'invalid-argument',
        'リクエストデータが不正です',
        { received: requestData }
      );
    }

    // APIエンドポイント設定
    const baseURL = 'https://vision.googleapis.com/v1';
    const endpoint = data.endpoint || 'images:annotate';

    console.log('Google Vision APIへリクエストを送信します:', {
      endpoint: endpoint,
      requestsCount: requestData.requests?.length || 0,
      features: requestData.requests?.[0]?.features || []
    });

    // Google Vision API にリクエスト
    const response = await axios({
      method: 'post',
      url: `${baseURL}/${endpoint}`,
      params: {
        key: apiKey
      },
      headers: {
        'Content-Type': 'application/json'
      },
      data: requestData
    });

    console.log('Google Vision APIからレスポンスを受信しました');

    // レスポンスをそのまま返す
    return response.data;
  } catch (error) {
    console.error('Google Vision API エラー:', error.response?.data || error.message);
    if (error.response) {
      console.error('レスポンスステータス:', error.response.status);
      console.error('レスポンスヘッダー:', error.response.headers);
      console.error('レスポンスデータ:', error.response.data);
    }
    throw new functions.https.HttpsError(
      'internal',
      'Google Vision API リクエストでエラーが発生しました',
      error.response?.data || {message: error.message}
    );
  }
});

/**
 * DeepSeek API へのプロキシリクエスト
 * バックアップ AI として使用される DeepSeek API へのリクエストを転送
 */
// exports.proxyDeepSeek = functions
//   .region('asia-northeast1') // リージョンを明示的に指定し統一
//   .runWith({
//     memory: '1GB',  // メモリを増やす
//     timeoutSeconds: 60  // タイムアウトも増やす
//   })
//   .https.onCall(async (data, context) => {
//   // 認証チェック
//   if (!context.auth) {
//     throw new functions.https.HttpsError(
//       'unauthenticated',
//       'ユーザー認証が必要です'
//     );
//   }

//   try {
//     // DeepSeek APIキーを取得 - 新機能では新しいキー名のみ使用
//     const apiKey = functions.config().deepseek.newkey;
//     if (!apiKey) {
//       console.error('DeepSeek APIキーが設定されていません');
//       throw new functions.https.HttpsError(
//         'failed-precondition',
//         'DeepSeek APIキーが設定されていません'
//       );
//     }
    
//     // APIキーが正しい形式か確認
//     if (!apiKey.startsWith('sk-')) {
//       console.error('DeepSeek APIキーの形式が不正です: キーは"sk-"で始まる必要があります');
//       throw new functions.https.HttpsError(
//         'invalid-argument',
//         'DeepSeek APIキーの形式が不正です'
//       );
//     }
    
//     // リクエストデータを取得
//     const requestData = data.data || {};
//     if (!requestData.model || !requestData.messages) {
//       console.error('不正なリクエストデータ:', requestData);
//       throw new functions.https.HttpsError(
//         'invalid-argument',
//         'リクエストデータが不正です',
//         { received: requestData }
//       );
//     }

//     console.log('DeepSeek APIへリクエストを送信します:', {
//       model: requestData.model,
//       messagesCount: requestData.messages.length,
//       temperature: requestData.temperature || 0.7,
//       max_tokens: requestData.max_tokens || 2000
//     });

//     // リクエストパラメータのクリーンアップと適正化
//     try {
//       // モデル名を確認、デフォルト値を設定
//       const validModels = ['deepseek-chat', 'deepseek-coder', 'deepseek-lite'];
//       if (!validModels.includes(requestData.model)) {
//         console.warn(`指定されたモデル ${requestData.model} が未知です。deepseek-chatを使用します`);
//         requestData.model = 'deepseek-chat';
//       }
      
//       // トークン数のチェック、最大値を制限
//       if (!requestData.max_tokens || typeof requestData.max_tokens !== 'number') {
//         console.warn(`トークン数が無効です: ${requestData.max_tokens}。2000を使用します`); 
//         requestData.max_tokens = 2000;
//       } else if (requestData.max_tokens > 4000) {
//         console.warn(`トークン数${requestData.max_tokens}が上限を超えています。4000に制限します`);
//         requestData.max_tokens = 4000;
//       } else if (requestData.max_tokens < 100) {
//         console.warn(`トークン数${requestData.max_tokens}が小さすぎます。100に修正します`);
//         requestData.max_tokens = 100;
//       }

//       // temperatureパラメータの確認
//       if (typeof requestData.temperature !== 'number' || 
//           requestData.temperature < 0 || 
//           requestData.temperature > 1) {
//         console.warn(`temperature値が無効です: ${requestData.temperature}。デフォルトの0.7を使用します`);
//         requestData.temperature = 0.7;
//       }
      
//       // メッセージが有効か確認
//       if (!requestData.messages || !Array.isArray(requestData.messages) || requestData.messages.length === 0) {
//         throw new Error('有効なメッセージが存在しません');
//       }
      
//       // 各メッセージが適切な形式かチェック
//       requestData.messages = requestData.messages.map(msg => {
//         // 必須フィールドの確認
//         if (!msg.role || !msg.content) {
//           console.warn('不正なメッセージ形式を修正します:', msg);
//           return {
//             role: msg.role || 'user',
//             content: msg.content || ''
//           };
//         }
//         return msg;
//       });
    
//       // 最終的なリクエストデータをコンソールに記録
//       console.log('最終リクエストデータ:', {
//         model: requestData.model,
//         temperature: requestData.temperature,
//         max_tokens: requestData.max_tokens,
//         stream: requestData.stream || false,
//         messages_count: requestData.messages.length
//       });
//     } catch (validationError) {
//       console.error('リクエストデータの検証エラー:', validationError);
//       throw new functions.https.HttpsError(
//         'invalid-argument',
//         'リクエストデータの形式が不正です',
//         { message: validationError.message }
//       );
//     }

//     try {
//       // DeepSeek APIにリクエスト
//       console.log('DeepSeek APIにリクエストを送信します...', new Date().toISOString());
//       const requestStartTime = Date.now();
      
//       // APIキーのログ出力（実際では安全のために削除すること）
//       // APIキーの最初と5文字、安全のため完全なキーは表示しない
//       console.log(`DeepSeek APIキーの長さ: ${apiKey ? apiKey.length : 0}文字, 先頭5文字: ${apiKey ? apiKey.substring(0, 5) : 'null'}`);
//       console.log(`キー更新日時: ${new Date().toISOString()}`); // 強制的にデプロイを促すための変更

//       // モデルを確実に指定
//       if (requestData.model === 'deepseek-chat') {
//         // DeepSeekの最大最新モデルを使用
//         requestData.model = 'deepseek-chat';
//       }

//       // リクエスト内容のログ
//       console.log('レスポンス待機中...', new Date().toISOString());
      
//       // API呼び出しのデバッグ情報を出力
//       console.log(`APIリクエストを開始: ${new Date().toISOString()}`);
//       console.log(`エンドポイントURL: https://api.deepseek.com/v1/chat/completions`);
//       console.log(`リクエストのメッセージ数: ${requestData.messages.length}`);
      
//       let response;
//       try {
//         response = await axios({
//           method: 'post',
//           url: 'https://api.deepseek.com/v1/chat/completions',
//           headers: {
//             'Authorization': `Bearer ${apiKey}`,
//             'Content-Type': 'application/json'
//           },
//           data: requestData,
//           timeout: 30000,  // 30秒に短縮
//           validateStatus: (status) => true // どのステータスコードも許可してエラーとして投げない
//         });
        
//         // レスポンスステータスチェック
//         if (response.status !== 200) {
//           console.error(`エラーステータス: ${response.status}`);
//           console.error('DeepSeek APIレスポンス:', response.data);
//           throw new Error(`APIリクエスト失敗: ステータスコード ${response.status}`);
//         }
        
//         const elapsedTime = Date.now() - requestStartTime;
//         console.log(`DeepSeek APIレスポンス受信時間: ${elapsedTime}ms`);
//         console.log(`レスポンス満了: ${new Date().toISOString()}`);
//         console.log(`レスポンスステータス: ${response.status}`);
//         console.log(`レスポンスフィールド: ${Object.keys(response.data).join(', ')}`);
//       } catch (requestError) {
//         console.error('APIリクエストエラー:', requestError.message);
//         throw requestError;
//       }
      
//       // レスポンス内容の要約をログ記録
//       const hasChoices = response.data && response.data.choices && response.data.choices.length > 0;
//       console.log('レスポンス形式確認:', { 
//         hasChoices, 
//         fields: response.data ? Object.keys(response.data).join(', ') : 'none' 
//       });
      
//       // レスポンスをそのまま返す
//       return response.data;
//     } catch (error) {
//       // 詳細なエラー情報をログに記録
//       console.error('DeepSeek API呼び出し中のエラー:', error.message);
//       console.error('DeepSeek API エラー詳細:', error.response?.data || 'no response data');
//       console.error('エラースタック:', error.stack);
      
//       let errorMessage = 'DeepSeek API リクエストでエラーが発生しました';
//       let errorCode = 'internal';
//       let errorDetails = { message: error.message };
      
//       if (error.response) {
//         const status = error.response.status;
//         console.error('レスポンスステータス:', status);
//         console.error('レスポンスヘッダー:', error.response.headers);
//         console.error('レスポンスデータ:', error.response.data);
        
//         // ステータスコードに基づくエラーメッセージ
//         if (status === 401) {
//           errorMessage = 'DeepSeek API認証エラー: APIキーが無効または期限切れ';
//           errorCode = 'unauthenticated';
//         } else if (status === 400) {
//           errorMessage = 'DeepSeek APIリクエストエラー: 不正なリクエストパラメータ';
//           errorCode = 'invalid-argument';
//         } else if (status === 429) {
//           errorMessage = 'DeepSeek APIレート制限エラー: リクエスト数が多すぎます';
//           errorCode = 'resource-exhausted';
//         } else if (status >= 500) {
//           errorMessage = 'DeepSeek APIサーバーエラー: サービスが一時的に利用できません';
//           errorCode = 'unavailable';
//         }
        
//         errorDetails = error.response.data || errorDetails;
//       } else if (error.code === 'ECONNABORTED') {
//         errorMessage = 'DeepSeek APIタイムアウト: リクエストが時間切れになりました';
//         errorCode = 'deadline-exceeded';
//       }
    
//       // フォールバックレスポンスの生成
//       try {
//         // シンプルな暗記法オブジェクトを返す
//         return {
//           choices: [{
//             message: {
//               content: JSON.stringify({
//                 name: 'シンプル暗記法',
//                 description: '重要ポイントに焦点を当てて、イメージ化で覚えよう',
//                 type: 'concept',
//                 tags: ['学習'],
//                 contentKeywords: ['キーワード'],
//                 flashcards: [{
//                   question: '質問',
//                   answer: '回答'
//                 }]
//               })
//             }
//           }],
//           error_info: errorMessage
//         };
//       } catch (fallbackError) {
//         console.error('フォールバック生成失敗:', fallbackError);
//         throw new functions.https.HttpsError(errorCode, errorMessage, errorDetails);
//       }
//     }
//   } catch (error) {
//     console.error('DeepSeek API全体のエラー処理:', error);
//     throw new functions.https.HttpsError('internal', 'DeepSeek API呼び出しで予期しないエラーが発生しました', { message: error.message });
//   }
// });

/**
 * Base64データURIから純粋なBase64文字列を抽出する
 * @param {string} dataUri - Base64データURI (例: "data:image/jpeg;base64,/9j/...") または純粋なBase64文字列
 * @returns {string} - 純粋なBase64文字列
 */
function extractBase64FromDataUri(dataUri) {
  if (!dataUri) {
    console.error('データURIが提供されていません');
    return '';
  }

  console.log(`データ文字列処理: 長さ ${dataUri.length}文字, 先頭: ${dataUri.substring(0, 20)}...`);

  try {
    // すでに純粋なBase64であるか確認
    if (!dataUri.startsWith('data:')) {
      console.log('純粋なBase64文字列と判断しました (data:プレフィックスなし)');
      return dataUri;
    }

    // Base64部分を抽出
    const matches = dataUri.match(/^data:[^;]+;base64,(.+)$/);
    if (matches && matches.length > 1) {
      console.log('データURIからBase64を正常に抽出しました');
      return matches[1];
    } else {
      // カンマで区切られた部分を探す (データURIフォーマットは一定しない場合があるため)
      const commaIndex = dataUri.indexOf(',');
      if (commaIndex !== -1) {
        console.log('カンマ区切りでBase64を抽出しました');
        return dataUri.substring(commaIndex + 1);
      }
    }

    console.warn('Base64抽出が失敗、元の文字列を使用します');
    return dataUri;
  } catch (error) {
    console.error('Base64抽出エラー:', error);
    return dataUri; // エラー時は元の文字列を返す
  }
}

/**
 * Google Vision API へのプロキシリクエスト
 * OCR およびイメージ分析のリクエストを転送
 */
exports.proxyVision = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .runWith({
    memory: '1GB',  // メモリを増やす
    timeoutSeconds: 120  // タイムアウトを増やす
  })
  .https.onCall(async (data, context) => {
  // 認証チェック
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'ユーザー認証が必要です'
    );
  }

  const userId = context.auth.uid;
  console.log(`Vision APIリクエスト処理開始 (ユーザー: ${userId})`);

  try {
    // APIキーを取得
    let apiKey = functions.config().google?.vision?.apikey || functions.config().google?.vision_key;
    
    if (!apiKey) {
      console.error('Google Vision APIキーが設定されていません');
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Google Vision APIキーが設定されていません'
      );
    }

    // リクエストデータを取得
    const requestData = data.data || {};
    
    // データチェック
    if (!requestData.requests && !requestData.imageContent) {
      console.error('不正なリクエストデータ:', JSON.stringify(requestData).substring(0, 100));
      throw new functions.https.HttpsError(
        'invalid-argument',
        'リクエストデータが不正です (イメージデータがありません)'
      );
    }

    // リクエストデータ構造を標準化
    let visionRequest;
    
    if (requestData.requests) {
      // すでに適切な形式の場合
      console.log('既存のrequests形式を使用します');
      visionRequest = requestData;
    } else {
      // イメージコンテンツから構築
      let imageContent = requestData.imageContent;
      const feature = data.feature || requestData.feature || 'TEXT_DETECTION';
      
      // Base64データURIから純粋なBase64を抽出
      let base64Image = extractBase64FromDataUri(imageContent);
      
      if (!base64Image) {
        console.error('有効な画像データがありません');
        throw new functions.https.HttpsError(
          'invalid-argument',
          '有効な画像データがありません'
        );
      }
      
      console.log(`処理後の画像データ: ${base64Image.length}文字`);
      
      // リクエストを構築
      visionRequest = {
        requests: [{
          image: {
            content: base64Image
          },
          features: [{
            type: feature,
            maxResults: 50
          }]
        }]
      };
    }

    console.log('Vision APIへリクエスト送信準備完了');
    
    // Vision API にリクエスト
    const response = await axios({
      method: 'post',
      url: `https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`,
      headers: {
        'Content-Type': 'application/json'
      },
      data: visionRequest,
      timeout: 30000 // 30秒タイムアウト
    });

    console.log('Vision APIからレスポンスを受信しました:', {
      status: response.status,
      dataSize: JSON.stringify(response.data).length
    });

    // レスポンスをそのまま返す
    return response.data;
  } catch (error) {
    console.error('Vision API 呼び出しエラー:', error);
    
    if (error.response) {
      console.error('エラーステータス:', error.response.status);
      console.error('エラーデータ:', JSON.stringify(error.response.data));
    } else if (error.request) {
      console.error('リクエストエラー:', error.code || 'unknown');
    }
    
    throw new functions.https.HttpsError(
      'internal',
      'Vision API リクエストでエラーが発生しました: ' + (error.message || 'Unknown error'),
      {
        error: error.message,
        status: error.response?.status,
        data: error.response?.data,
        code: error.code,
        timestamp: new Date().toISOString()
      }
    );
  }
});

/**
 * レート制限を回避するため、Firebase Functions 内のメモリにAPIキャッシュを実装
 * 各ユーザーの API 使用回数を管理
 */
const rateLimit = {
  userQuota: {}, // ユーザーごとのクォータ
  resetTime: Date.now(), // リセット時間
  
  // クォータチェック
  async checkUserQuota(userId, apiType) {
    const now = Date.now();
    const timeWindow = 24 * 60 * 60 * 1000; // 24時間
    
    // 24時間経過したらリセット
    if (now - this.resetTime > timeWindow) {
      this.userQuota = {};
      this.resetTime = now;
    }
    
    // ユーザーのクォータ初期化
    if (!this.userQuota[userId]) {
      this.userQuota[userId] = {
        openai: 0,
        deepseek: 0, 
        vision: 0,
        mistral: 0,
        lastReset: now
      };
    }
    
    // ユーザー個別のリセット
    if (now - this.userQuota[userId].lastReset > timeWindow) {
      this.userQuota[userId] = {
        openai: 0,
        deepseek: 0,
        vision: 0,
        mistral: 0,
        lastReset: now
      };
    }
    
    // 使用回数増加
    this.userQuota[userId][apiType]++;
    
    // サブスクリプション状態を確認
    const userSubscription = await admin.firestore()
      .collection('subscriptions')
      .doc(userId)
      .get();
    
    // サブスクリプション情報に基づいて制限を設定
    let limits = {
      openai: 10,   // 無料ユーザーの1日の上限
      deepseek: 10,
      vision: 5,
      mistral: 5
    };
    
    // プレミアムユーザーの場合、制限を緩和
    if (userSubscription.exists && 
        (userSubscription.data().type === 'premium_monthly' || 
         userSubscription.data().type === 'premium_yearly')) {
      limits = {
        openai: 100,
        deepseek: 100,
        vision: 50,
        mistral: 50
      };
    }
    
    // 制限をチェック
    if (this.userQuota[userId][apiType] > limits[apiType]) {
      return false; // 制限超過
    }
    
    return true; // 制限内
  }
};
