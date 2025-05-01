import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class ProfileAvatarWidget extends StatefulWidget {
  // パラメータ
  final double size;
  final Color? defaultBackgroundColor;
  final Color? defaultIconColor;
  final Color? premiumIndicatorColor;
  final bool showPremiumIndicator;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  const ProfileAvatarWidget({
    super.key,
    this.size = 40.0,
    this.defaultBackgroundColor,
    this.defaultIconColor,
    this.premiumIndicatorColor,
    this.showPremiumIndicator = false,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2.0,
  });

  @override
  State<ProfileAvatarWidget> createState() => _ProfileAvatarWidgetState();
}

class _ProfileAvatarWidgetState extends State<ProfileAvatarWidget> {
  String? _photoUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  // プロフィール画像を読み込む
  Future<void> _loadProfilePhoto() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final photoUrl = await authService.getProfilePhotoURL();

      if (mounted) {
        setState(() {
          _photoUrl = photoUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final bool isAnonymous = user?.isAnonymous ?? true;

        // タップ可能なウィジェット
        return GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            children: [
              // プロフィール画像または代替アイコン
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.defaultBackgroundColor ?? 
                      (isAnonymous ? Colors.grey.shade200 : Colors.blue.shade100),
                  border: widget.showBorder ? Border.all(
                    color: widget.borderColor ?? Theme.of(context).primaryColor,
                    width: widget.borderWidth,
                  ) : null,
                ),
                child: _isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(widget.size / 2),
                        child: _photoUrl != null && _photoUrl!.isNotEmpty
                            ? Image.network(
                                _photoUrl!,
                                width: widget.size,
                                height: widget.size,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    isAnonymous ? Icons.person_outline : Icons.person,
                                    size: widget.size * 0.6,
                                    color: widget.defaultIconColor ??
                                        (isAnonymous
                                            ? Colors.grey.shade500
                                            : Colors.blue.shade700),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Icon(
                                isAnonymous ? Icons.person_outline : Icons.person,
                                size: widget.size * 0.6,
                                color: widget.defaultIconColor ??
                                    (isAnonymous
                                        ? Colors.grey.shade500
                                        : Colors.blue.shade700),
                              ),
                      ),
              ),
              
              // プレミアムインジケーター（オプション）
              if (widget.showPremiumIndicator)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: widget.size * 0.35,
                    height: widget.size * 0.35,
                    decoration: BoxDecoration(
                      color: widget.premiumIndicatorColor ?? Colors.amber,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.workspace_premium,
                        color: Colors.white,
                        size: widget.size * 0.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
