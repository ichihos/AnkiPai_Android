import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ProfileEditScreen extends StatefulWidget {
  final String initialDisplayName;
  final String? profilePhotoUrl;

  const ProfileEditScreen({
    super.key,
    required this.initialDisplayName,
    this.profilePhotoUrl,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late TextEditingController _displayNameController;
  bool _isLoading = false;
  bool _isUpdatingPhoto = false;
  String? _profilePhotoUrl;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.initialDisplayName);
    _profilePhotoUrl = widget.profilePhotoUrl;

    // 変更を監視
    _displayNameController.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  // 変更があるかチェック
  void _checkChanges() {
    final hasNameChange =
        _displayNameController.text != widget.initialDisplayName;
    final hasPhotoChange = _profilePhotoUrl != widget.profilePhotoUrl;

    setState(() {
      _hasChanges = hasNameChange || hasPhotoChange;
    });
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
              title: Text(AppLocalizations.of(context)!.takePhoto),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(AppLocalizations.of(context)!.chooseFromGallery),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(AppLocalizations.of(context)!.removeProfileImage,
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
        _checkChanges();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profileImageUpdated),
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
            content: Text(
                AppLocalizations.of(context)!.imageUpdateFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // プロフィール画像の削除
  Future<void> _removeProfilePhoto() async {
    setState(() {
      _profilePhotoUrl = null;
      _isUpdatingPhoto = false;
    });
    _checkChanges();
  }

  // 変更を保存
  Future<void> _saveChanges() async {
    if (!_hasChanges) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // 表示名の更新
      if (_displayNameController.text != widget.initialDisplayName) {
        await authService.updateDisplayName(_displayNameController.text);
      }

      // プロフィール画像の更新
      if (_profilePhotoUrl != widget.profilePhotoUrl) {
        if (_profilePhotoUrl == null) {
          await authService.updateProfilePhotoURL('');
        } else if (_profilePhotoUrl!.isNotEmpty) {
          // 既にアップロード済みなので、URLの更新のみ
          await authService.updateProfilePhotoURL(_profilePhotoUrl!);
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profileUpdated),
            backgroundColor: Colors.green,
          ),
        );

        // 前の画面に戻る（更新された情報を渡す）
        Navigator.pop(context, {
          'displayName': _displayNameController.text,
          'profilePhotoUrl': _profilePhotoUrl,
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .profileUpdateFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 変更を破棄する前に確認
  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmation),
        content: Text(AppLocalizations.of(context)!.discardChangesConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)!.discard),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmDiscard,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.profileEdit),
          elevation: 0,
          foregroundColor: Colors.white,
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
          actions: [
            // 保存ボタン
            TextButton(
              onPressed: _hasChanges && !_isLoading ? _saveChanges : null,
              child: Text(
                AppLocalizations.of(context)!.save,
                style: TextStyle(
                  color: _hasChanges && !_isLoading
                      ? Colors.white
                      : Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),

                    // プロフィール画像エリア
                    Center(
                      child: Stack(
                        children: [
                          // プロフィール画像またはデフォルトアイコン
                          GestureDetector(
                            onTap: () =>
                                _isUpdatingPhoto ? null : _showPhotoOptions(),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade200,
                              foregroundColor: Colors.transparent,
                              child: _isUpdatingPhoto
                                  ? const CircularProgressIndicator()
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(60),
                                      child: _profilePhotoUrl != null &&
                                              _profilePhotoUrl!.isNotEmpty
                                          ? Image.network(
                                              _profilePhotoUrl!,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color: Colors.blue.shade700,
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
                                              Icons.person,
                                              size: 60,
                                              color: Colors.blue.shade700,
                                            ),
                                    ),
                            ),
                          ),

                          // 編集ボタン
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () =>
                                  _isUpdatingPhoto ? null : _showPhotoOptions(),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 53, 152, 71),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 表示名編集フォーム
                    Container(
                      padding: const EdgeInsets.all(16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.displayNameLabel,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _displayNameController,
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context)!.displayNameHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color.fromARGB(255, 53, 152, 71),
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            onChanged: (value) {
                              _checkChanges();
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)!
                                .displayNameDescription,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 保存ボタン（下部）
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _hasChanges && !_isLoading ? _saveChanges : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color.fromARGB(255, 53, 152, 71),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                AppLocalizations.of(context)!.saveChanges,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // キャンセルボタン
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () async {
                          if (await _confirmDiscard()) {
                            Navigator.pop(context);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.cancel,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
