import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/card_set_service.dart';
import '../services/memory_service.dart';
import '../widgets/common_widgets.dart';
import 'home_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'commercial_transaction_screen.dart';
import 'how_to_use_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLogin = true; // ログインモードか登録モードか
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // アプリの特徴（カルーセル表示用）
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.lightbulb_outline,
      'title': 'サクっと暗記！',
      'description': '簡単に知識を頭に入れよう！'
    },
    {
      'icon': Icons.access_time,
      'title': '科学的な記憶サイクル',
      'description': '忘却曲線に基づいて、ちょうどいいタイミングで復習をお知らせ'
    },
    {
      'icon': Icons.emoji_events_outlined,
      'title': '楽しく継続！',
      'description': 'ゲーム感覚で暗記が続く！色々な覚え方を試そう！'
    },
  ];

  int _currentFeatureIndex = 0;

  @override
  void initState() {
    super.initState();
    // 特徴カルーセルの自動切り替え
    _startFeatureCarousel();
  }

  void _startFeatureCarousel() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _currentFeatureIndex = (_currentFeatureIndex + 1) % _features.length;
        });
        _startFeatureCarousel();
      }
    });
  }

  // このアプリについての情報を提供するモーダルを表示
  void _showLegalInfoModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'このアプリについて',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.help_outline, color: Colors.green.shade600),
                title: const Text('使い方'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const HowToUseScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.description_outlined,
                    color: Colors.blue.shade700),
                title: const Text('利用規約'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const TermsOfServiceScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined,
                    color: Colors.blue.shade700),
                title: const Text('プライバシーポリシー'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PrivacyPolicyScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.shopping_bag_outlined,
                    color: Colors.blue.shade700),
                title: const Text('特定商取引法に基づく表記'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const CommercialTransactionScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      if (_isLogin) {
        // ログイン処理
        await authService.signInWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        // 新規登録処理
        await authService.registerWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }

      // 認証成功後、全てのサービスのリスナーをクリーンアップしてから再初期化
      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);
      final memoryService = Provider.of<MemoryService>(context, listen: false);

      print('認証状態変更に伴い、全てのサービスリスナーをリセットします');

      // まずリスナーをクリーンアップ
      cardSetService.cleanupAllListeners();
      memoryService.cleanupAllListeners();

      // 次に再初期化
      try {
        await cardSetService.initialize();
        print('ログイン後のCardSetServiceの初期化が完了しました');
      } catch (e) {
        print('ログイン後のCardSetServiceの初期化に失敗しました: $e');
        // カードセットサービスの初期化失敗は致命的なエラーではないため継続
      }

      // 認証成功後、新しいHomeScreenに置き換える
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    // まずmountedをチェックしてから状態更新
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithGoogle();

      // 認証後のサービス初期化前に再度マウント状態をチェック
      if (!mounted) return;

      // Google認証成功後、カードセットサービスを初期化
      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);
      try {
        await cardSetService.initialize();

        print('Googleログイン後のCardSetServiceの初期化が完了しました');
      } catch (e) {
        print('Googleログイン後のCardSetServiceの初期化に失敗しました: $e');
        // カードセットサービスの初期化失敗は致命的なエラーではないため継続
      }

      // Google認証成功後、新しいHomeScreenに置き換える
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      // ポップアップが閉じられたエラーの場合は特別なメッセージを表示
      String errorMsg = e.toString();
      if (errorMsg.contains('popup-closed-by-user')) {
        errorMsg = 'サインインがキャンセルされました。もう一度お試しください。';
        print('Googleサインインキャンセル: $e');
      } else {
        print('Googleサインインエラー: $e');
      }
      
      // 状態更新前に必ずmountedをチェック
      if (mounted) {
        setState(() {
          _errorMessage = errorMsg;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Sign in with Apple
  Future<void> _signInWithApple() async {
    // mountedチェック
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('※ Apple Sign Inを開始します');
      final authService = Provider.of<AuthService>(context, listen: false);
      final credential = await authService.signInWithApple();
      
      // ログイン成功したか確認
      if (credential == null) {
        print('※ Apple Sign Inが失敗しました（NULL）');
        throw Exception('Appleサインインが完了しませんでした');
      }
      
      print('※ Apple Sign Inが成功しました: uid=${credential.user?.uid}');

      // 認証後のサービス初期化前に再度マウント状態をチェック
      if (!mounted) return;

      // Apple認証成功後、カードセットサービスを初期化
      final cardSetService = Provider.of<CardSetService>(context, listen: false);
      try {
        await cardSetService.initialize();
        print('Appleログイン後のCardSetServiceの初期化が完了しました');
      } catch (e) {
        print('Appleログイン後のCardSetServiceの初期化に失敗しました: $e');
      }

      // MemoryServiceの取得 (初期化は自動的に行われる)
      try {
        Provider.of<MemoryService>(context, listen: false);
        print('Appleログイン後のメモリーサービスを取得しました');
      } catch (e) {
        print('Appleログイン後のメモリーサービスの取得に失敗しました: $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      // ポップアップが閉じられたエラーの場合は特別なメッセージを表示
      String errorMsg = e.toString();
      if (errorMsg.contains('canceled')) {
        errorMsg = 'サインインがキャンセルされました。もう一度お試しください。';
        print('Appleサインインキャンセル: $e');
      } else {
        print('Appleサインインエラー: $e');
      }
      
      if (mounted) {
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInAnonymously();

      // 匿名認証成功後、カードセットサービスを初期化
      final cardSetService =
          Provider.of<CardSetService>(context, listen: false);
      try {
        await cardSetService.initialize();
        print('匿名ログイン後のCardSetServiceの初期化が完了しました');
      } catch (e) {
        print('匿名ログイン後のCardSetServiceの初期化に失敗しました: $e');
        // カードセットサービスの初期化失敗は致命的なエラーではないため継続
      }

      // 匿名認証成功後、新しいHomeScreenに置き換える
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // アプリロゴとタイトル
                  const PieLogo(),
                  const SizedBox(height: 8),
                  Text(
                    'サクッと覚える暗記パイ',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // アプリの特徴カルーセル
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: _buildFeatureCard(_features[_currentFeatureIndex]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _features.length,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentFeatureIndex == index
                              ? Colors.blue.shade600
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // フォーム
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: Colors.blue.shade200, width: 2),
                    ),
                    color: Colors.white.withOpacity(0.9),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isLogin ? Icons.login : Icons.person_add,
                                  color: Colors.blue.shade600,
                                  size: 28,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isLogin ? 'ログイン' : 'アカウント作成',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: _emailController,
                              icon: Icons.email,
                              label: 'メールアドレス',
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'メールアドレスを入力してください';
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                    .hasMatch(value)) {
                                  return '有効なメールアドレスを入力してください';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _passwordController,
                              icon: Icons.lock,
                              label: 'パスワード',
                              obscureText: _obscurePassword,
                              onToggleVisibility: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'パスワードを入力してください';
                                }
                                if (!_isLogin && value.length < 6) {
                                  return 'パスワードは6文字以上必要です';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.red.shade300),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            if (_errorMessage != null)
                              const SizedBox(height: 16),
                            _buildSubmitButton(),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: _isLoading ? null : _toggleAuthMode,
                                child: Text(
                                  _isLogin ? 'アカウント作成' : 'ログイン画面に戻る',
                                  style: TextStyle(
                                    color: Colors.blue.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'または',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ソーシャルログイン
                  _buildGoogleSignInButton(),
                  const SizedBox(height: 12),
                  _buildAppleSignInButton(),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading ? null : _signInAnonymously,
                    child: Text(
                      'ログインしない',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Column(
                    children: [
                      Text(
                        '登録することで、利用規約とプライバシーポリシーに同意したことになります',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        icon: Icon(Icons.info_outline,
                            size: 16, color: Colors.blue.shade600),
                        label: const Text('このアプリについて'),
                        onPressed: () => _showLegalInfoModal(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(Map<String, dynamic> feature) {
    return Card(
      key: ValueKey(feature['title']),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Colors.blue.shade300,
          width: 2,
        ),
      ),
      color: Colors.white.withOpacity(0.8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                feature['icon'],
                size: 40,
                color: Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              feature['title'],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              feature['description'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade900.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    required String? Function(String?) validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(color: Colors.blue.shade900),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.blue.shade600),
          prefixIcon: Icon(icon, color: Colors.blue.shade500),
          suffixIcon: onToggleVisibility != null
              ? IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                    color: Colors.blue.shade500,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade500, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                _isLogin ? 'ログイン' : '登録',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildGoogleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.login),
        label: const Text(
          'Googleでログイン',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.blue.shade400),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
      ),
    );
  }
  
  Widget _buildAppleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.apple),
        label: const Text(
          'Appleでログイン',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        onPressed: _isLoading ? null : _signInWithApple,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        ),
      ),
    );
  }
}
