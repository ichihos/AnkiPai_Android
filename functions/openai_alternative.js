const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

/**
 * OpenAI API へのプロキシリクエスト（代替実装）
 * クライアントからのリクエストを OpenAI API に転送し、結果を返す
 * 元の実装と同じ機能だが、別名での実装
 */
exports.proxyOpenAIV2 = functions
  .region('asia-northeast1') // リージョンを明示的に指定し統一
  .runWith({
    memory: '1GB',  // メモリを増やす
    timeoutSeconds: 120  // タイムアウトも増やす
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
  console.log(`OpenAI代替API処理開始 (ユーザー: ${userId})`);

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
    
    // リクエストデータを取得
    const requestData = data.data || {};
    if (!requestData.model || !requestData.messages) {
      console.error('不正なリクエストデータ:', JSON.stringify(requestData).substring(0, 100));
      throw new functions.https.HttpsError(
        'invalid-argument',
        'リクエストデータが不正です',
        { received: requestData }
      );
    }
    
    console.log('OpenAI代替APIへリクエストを送信します:', {
      model: requestData.model,
      messagesCount: requestData.messages.length
    });

    // APIリクエストURLを構築
    const apiUrl = data.endpoint 
      ? `https://api.openai.com/v1/${data.endpoint}` 
      : 'https://api.openai.com/v1/chat/completions';
    
    console.log(`API URL: ${apiUrl}`);
    
    // API呼び出しを試みる
    try {
      console.log('OpenAI代替APIリクエスト実行開始');
      const response = await axios({
        method: 'post',
        url: apiUrl,
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        data: requestData,
        timeout: 90000  // 90秒のタイムアウト設定
      });
      
      console.log('OpenAI代替APIからレスポンス受信:', {
        status: response.status,
        dataSize: JSON.stringify(response.data).length
      });

      // レスポンスをそのまま返す
      return response.data;
    } catch (apiError) {
      console.error('OpenAI代替APIの呼び出しでエラー:', apiError.message);
      if (apiError.response) {
        console.error('エラーステータス:', apiError.response.status);
        console.error('エラーデータ:', JSON.stringify(apiError.response.data));
      }
      throw apiError;
    }
  } catch (error) {
    console.error('OpenAI代替API エラー:', error.message);
    
    if (error.response) {
      console.error('ステータスコード:', error.response.status);
      console.error('レスポンスデータ:', JSON.stringify(error.response.data));
    }
    
    throw new functions.https.HttpsError(
      'internal',
      'OpenAI代替API リクエストでエラーが発生しました: ' + error.message,
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
