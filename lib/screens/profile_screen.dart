import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../models/subscription_model.dart';
import '../providers/language_provider.dart';
import 'login_screen.dart';
import 'subscription_info_screen.dart';
import 'notification_settings_screen.dart';
import 'profile_edit_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'contact_screen.dart';
import 'commercial_transaction_screen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isUpdatingPhoto = false;
  SubscriptionModel? _subscription;
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadProfilePhoto();
  }

  // プロフィール画像のURLを読み込む
  Future<void> _loadProfilePhoto() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final photoUrl = await authService.getProfilePhotoURL();

    if (mounted) {
      setState(() {
        _profilePhotoUrl = photoUrl;
      });
    }
  }

  Future<void> _loadUserInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final subscriptionService =
          Provider.of<SubscriptionService>(context, listen: false);
      final subscription = await subscriptionService.getUserSubscription();

      setState(() {
        _subscription = subscription;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.failedToLoadInfo(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // プレミアムへのアップグレードボタン
  Widget _buildUpgradeButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionInfoScreen(),
          ),
        );
      },
      icon: const Icon(Icons.workspace_premium),
      label: Text(AppLocalizations.of(context)!.upgradeYourPlan),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // サインアウト確認ダイアログ
  Future<void> _showSignOutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.logout),
        content: Text(AppLocalizations.of(context)!.logoutConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.logout),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // アカウント削除確認ダイアログ
  Future<void> _showDeleteAccountConfirmation() async {
    // 最初の確認ダイアログ
    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteAccount),
        content: Text(AppLocalizations.of(context)!.deleteAccountConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (firstConfirmed != true) return;

    // 最終確認ダイアログ
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.finalConfirmation),
        content:
            Text(AppLocalizations.of(context)!.finalDeleteConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (finalConfirmed == true) {
      // ローディングダイアログを表示
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context)!.deletingAccount)
            ],
          ),
        ),
      );

      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.deleteAccount();

        // 成功時の下処理が実行される前に新しい画面に遷移するため、ダイアログを手動で閉じる必要があります
        if (mounted) {
          Navigator.of(context).pop(); // ローディングダイアログ閉じる

          // ログイン画面に遷移
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );

          // 完了メッセージを表示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.accountDeleted),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        // エラーが発生した場合はローディングダイアログを閉じてエラーメッセージを表示
        if (mounted) {
          Navigator.of(context).pop(); // ローディングダイアログ閉じる
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .failedToDeleteAccount(e.toString())),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  // プロフィール画像の選択オプションを表示
  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(AppLocalizations.of(context)!.camera),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(AppLocalizations.of(context)!.gallery),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(AppLocalizations.of(context)!.deleteProfilePicture,
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  // 画像の選択とアップロードプロセス
  Future<void> _pickImage(ImageSource source) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      // 画像選択中のローディング状態に変更
      setState(() {
        _isUpdatingPhoto = true;
      });

      // 画像の選択
      final pickedFile = await authService.pickProfileImage(source: source);

      if (pickedFile == null) {
        setState(() {
          _isUpdatingPhoto = false;
        });
        return;
      }

      // 画像のアップロード
      final photoUrl =
          await authService.uploadProfileImage(imageFile: pickedFile);

      // 結果を表示
      if (mounted) {
        setState(() {
          _profilePhotoUrl = photoUrl;
          _isUpdatingPhoto = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profilePictureUpdated),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // エラー処理
      if (mounted) {
        setState(() {
          _isUpdatingPhoto = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .failedToUpdateImage(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // プロフィール画像の削除
  Future<void> _removeProfilePhoto() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      setState(() {
        _isUpdatingPhoto = true;
      });

      // 空のURLでプロフィール画像を更新
      await authService.updateProfilePhotoURL('');

      if (mounted) {
        setState(() {
          _profilePhotoUrl = null;
          _isUpdatingPhoto = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profilePictureDeleted),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdatingPhoto = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .failedToDeleteProfilePicture(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 設定項目ウィジェット
  // 言語選択ダイアログを表示
  void _showLanguageSelectionDialog(BuildContext context) {
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
    final currentLocale = languageProvider.currentLocale.languageCode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.selectLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 日本語選択
            ListTile(
              leading: Radio<String>(
                value: 'ja',
                groupValue: currentLocale,
                onChanged: (value) {
                  if (value != null) {
                    languageProvider.changeLocale(const Locale('ja'));
                    Navigator.pop(context);
                    // 言語切替メッセージを表示
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .languageSwitchedJapanese),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
              title: Text(AppLocalizations.of(context)!.japanese),
              onTap: () {
                languageProvider.changeLocale(const Locale('ja'));
                Navigator.pop(context);
                // 言語切替メッセージを表示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.languageSwitchedJapanese),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            // 英語選択
            ListTile(
              leading: Radio<String>(
                value: 'en',
                groupValue: currentLocale,
                onChanged: (value) {
                  if (value != null) {
                    languageProvider.changeLocale(const Locale('en'));
                    Navigator.pop(context);
                    // 言語切替メッセージを表示
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .languageSwitchedEnglish),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
              title: Text(AppLocalizations.of(context)!.english),
              onTap: () {
                languageProvider.changeLocale(const Locale('en'));
                Navigator.pop(context);
                // 言語切替メッセージを表示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.languageSwitchedEnglish),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            // 中国語選択
            ListTile(
              leading: Radio<String>(
                value: 'zh',
                groupValue: currentLocale,
                onChanged: (value) {
                  if (value != null) {
                    languageProvider.changeLocale(const Locale('zh'));
                    Navigator.pop(context);
                    // 言語切替メッセージを表示
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!
                            .languageSwitchedChinese),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
              title: Text(AppLocalizations.of(context)!.chinese),
              onTap: () {
                languageProvider.changeLocale(const Locale('zh'));
                Navigator.pop(context);
                // 言語切替メッセージを表示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!.languageSwitchedChinese),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.blue.shade700),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final bool isAnonymous = user?.isAnonymous ?? true;
    final String userEmail = user?.email ?? l10n.anonymousUser;
    final String displayName = user?.displayName ?? userEmail;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 53, 152, 71),
                Color.fromARGB(255, 40, 130, 60),
              ],
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.profile,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        foregroundColor: Colors.white,
        actions: [
          // プレミアムバッジ（プレミアム会員のみ表示）
          if (_subscription?.isPremium ?? false)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium,
                      size: 16, color: Colors.amber.shade300),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context)!.premium,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade300,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: AppLocalizations.of(context)!.refreshUserInfo,
            onPressed: _loadUserInfo,
          ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ユーザー情報セクション
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // プロフィールアイコン
                        Stack(
                          children: [
                            // プロフィール画像（もしくはデフォルトアイコン）
                            GestureDetector(
                              onTap: () =>
                                  _isUpdatingPhoto ? null : _showPhotoOptions(),
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.transparent,
                                child: _isUpdatingPhoto
                                    ? const CircularProgressIndicator()
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(45),
                                        child: _profilePhotoUrl != null &&
                                                _profilePhotoUrl!.isNotEmpty
                                            ? Image.network(
                                                _profilePhotoUrl!,
                                                width: 90,
                                                height: 90,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Icon(
                                                    isAnonymous
                                                        ? Icons.person_outline
                                                        : Icons.person,
                                                    size: 40,
                                                    color: isAnonymous
                                                        ? Colors.grey.shade500
                                                        : Colors.blue.shade700,
                                                  );
                                                },
                                                loadingBuilder: (context, child,
                                                    loadingProgress) {
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  }
                                                  return const Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  );
                                                },
                                              )
                                            : Icon(
                                                isAnonymous
                                                    ? Icons.person_outline
                                                    : Icons.person,
                                                size: 40,
                                                color: isAnonymous
                                                    ? Colors.grey.shade500
                                                    : Colors.blue.shade700,
                                              ),
                                      ),
                              ),
                            ),
                            // 編集ボタン（匿名ユーザー以外に表示）
                            if (!isAnonymous)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _isUpdatingPhoto
                                      ? null
                                      : _showPhotoOptions(),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(
                                          255, 53, 152, 71),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ユーザー名
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // メールアドレス（匿名ユーザーの場合は表示しない）
                        if (!isAnonymous)
                          Text(
                            userEmail,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        const SizedBox(height: 16),

                        // サブスクリプションステータス
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_subscription?.isPremium ?? false)
                                ? Colors.amber.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_subscription?.isPremium ?? false)
                                  ? Colors.amber
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_subscription?.isPremium ?? false)
                                    ? Icons.workspace_premium
                                    : Icons.star_border,
                                size: 16,
                                color: (_subscription?.isPremium ?? false)
                                    ? Colors.amber.shade800
                                    : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _subscription != null
                                    ? _getLocalizedSubscriptionName(
                                        _subscription!.type, context)
                                    : AppLocalizations.of(context)!.freePlan,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: (_subscription?.isPremium ?? false)
                                      ? Colors.amber.shade800
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // プランの価格表示
                        if (_subscription != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _subscription!.subscriptionPrice, // 新しい価格ゲッターを使用
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),

                        // アップグレードボタン（無料プランの場合のみ）
                        if (!(_subscription?.isPremium ?? false))
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _buildUpgradeButton(),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // プラン情報カード（特別枠）
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: (_subscription?.isPremium ?? false)
                          ? Colors.amber.shade50
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_subscription?.isPremium ?? false)
                            ? Colors.amber.shade300
                            : Colors.grey.shade200,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SubscriptionInfoScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              // アイコン
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (_subscription?.isPremium ?? false)
                                      ? Colors.amber.shade100
                                      : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.workspace_premium,
                                  color: (_subscription?.isPremium ?? false)
                                      ? Colors.amber.shade700
                                      : Colors.grey.shade700,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // テキスト情報
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.planAndPricing,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _subscription != null
                                          ? _getLocalizedSubscriptionName(
                                              _subscription!.type, context)
                                          : AppLocalizations.of(context)!
                                              .freePlan,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            (_subscription?.isPremium ?? false)
                                                ? Colors.amber.shade800
                                                : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 矢印
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 設定セクション
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppLocalizations.of(context)!.settings,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 通知設定
                        // 言語設定
                        _buildSettingItem(
                          icon: Icons.language_outlined,
                          title: AppLocalizations.of(context)!.languageSettings,
                          onTap: () {
                            _showLanguageSelectionDialog(context);
                          },
                        ),

                        // 通知設定
                        _buildSettingItem(
                          icon: Icons.notifications_outlined,
                          title: AppLocalizations.of(context)!
                              .notificationSettings,
                          iconColor: Colors.orange,
                          onTap: () {
                            // 通知設定画面へ移動
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationSettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // アカウントセクション
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.accountSectionTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // プロフィール編集
                        _buildSettingItem(
                          icon: Icons.edit,
                          title: AppLocalizations.of(context)!.editProfile,
                          onTap: () async {
                            // プロフィール編集画面へ遷移
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfileEditScreen(
                                  initialDisplayName:
                                      user?.displayName ?? userEmail,
                                  profilePhotoUrl: _profilePhotoUrl,
                                ),
                              ),
                            );

                            // 編集画面から戻ってきたらリロード
                            if (result != null && mounted) {
                              // 情報を再読み込み
                              _loadUserInfo();
                              _loadProfilePhoto();
                            }
                          },
                        ),
                        const Divider(height: 1),

                        // アカウント削除
                        _buildSettingItem(
                          icon: Icons.delete_forever,
                          title: l10n.deleteAccount,
                          iconColor: Colors.red.shade700,
                          onTap: _showDeleteAccountConfirmation,
                        ),
                        const Divider(height: 1),

                        // ログアウト
                        _buildSettingItem(
                          icon: Icons.logout,
                          title: AppLocalizations.of(context)!.logout,
                          iconColor: Colors.red,
                          onTap: _showSignOutConfirmation,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // アプリ情報セクション
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.aboutAppSectionTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // プライバシーポリシー
                        _buildSettingItem(
                          icon: Icons.privacy_tip_outlined,
                          title: l10n.privacyPolicy,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PrivacyPolicyScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),

                        // 利用規約
                        _buildSettingItem(
                          icon: Icons.description_outlined,
                          title: l10n.termsOfService,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const TermsOfServiceScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),

                        // お問い合わせ
                        _buildSettingItem(
                          icon: Icons.help_outline,
                          title: l10n.contactUs,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ContactScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),

                        // 特定商取引法に基づく表記
                        _buildSettingItem(
                          icon: Icons.shopping_bag_outlined,
                          title: l10n.commercialTransactionAct,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CommercialTransactionScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),

                        // バージョン情報
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.grey.shade600),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  l10n.versionInfo,
                                  style: const TextStyle(
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                '1.0.0',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  String _getLocalizedSubscriptionName(
      SubscriptionType type, BuildContext context) {
    switch (type) {
      case SubscriptionType.premium_monthly:
        return AppLocalizations.of(context)!.monthlyPremiumPlan;
      case SubscriptionType.premium_yearly:
        return AppLocalizations.of(context)!.yearlyPremiumPlan;
      default:
        return AppLocalizations.of(context)!.freePlan;
    }
  }
}
