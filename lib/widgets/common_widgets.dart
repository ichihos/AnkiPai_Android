import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:math' as math;

// パイロゴ（大）
class PieLogo extends StatefulWidget {
  const PieLogo({super.key});

  @override
  State<PieLogo> createState() => _PieLogoState();
}

class _PieLogoState extends State<PieLogo> {
  bool _showFullName = false;

  // ロゴテキストの切り替え
  void _toggleLogoText() {
    setState(() {
      _showFullName = !_showFullName;
    });

    // 3秒後に元のテキストに戻す
    if (_showFullName) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showFullName = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // デバイスのサイズを取得
    final Size screenSize = MediaQuery.of(context).size;
    // 画面の短い方の寸法に基づいてサイズを計算
    final double minDimension = math.min(screenSize.width, screenSize.height);
    final double logoSize = minDimension * 0.12; // 画面の12%をロゴサイズに
    final double innerLogoSize = logoSize * 0.8; // 外側の80%を内側のサイズに

    return LayoutBuilder(
      builder: (context, constraints) {
        // レイアウト制約に基づいた調整
        final double paddingSize = constraints.maxWidth < 300 ? 8.0 : 16.0;

        return Container(
          padding: EdgeInsets.all(paddingSize),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // パイのアイコン - レスポンシブに
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: Colors.amber.shade300,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  children: [
                    // パイの基本形
                    Center(
                      child: Container(
                        width: innerLogoSize,
                        height: innerLogoSize,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade200,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // パイカット
                    Align(
                      alignment: Alignment.center,
                      child: CustomPaint(
                        size: Size(innerLogoSize, innerLogoSize),
                        painter: PieSlicePainter(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _toggleLogoText,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _showFullName
                        ? AppLocalizations.of(context)!.logoFullName
                        : AppLocalizations.of(context)!.logoShortName,
                    key: ValueKey<bool>(_showFullName),
                    style: TextStyle(
                      // 画面サイズに基づいてフォントサイズを調整
                      fontSize: _showFullName
                          ? math.max(18, minDimension * 0.06)
                          : math.max(22, minDimension * 0.07),
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                      fontFamily: 'Rounded', // 丸みのあるフォント
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

// アプリタイトルの表示状態を管理するグローバルなValueNotifier
final ValueNotifier<bool> appTitleFullNameNotifier = ValueNotifier<bool>(false);

// パイロゴ（小）- タップ機能付き
class PieLogoSmall extends StatefulWidget {
  const PieLogoSmall({super.key});

  @override
  State<PieLogoSmall> createState() => _PieLogoSmallState();
}

class _PieLogoSmallState extends State<PieLogoSmall> {
  @override
  Widget build(BuildContext context) {
    // デバイスのサイズを取得
    final Size screenSize = MediaQuery.of(context).size;
    // 画面の短い方の寸法に基づいてサイズを計算
    final double minDimension = math.min(screenSize.width, screenSize.height);
    // 小さいロゴは画面の5-8%のサイズに
    final double logoSize = math.max(24, math.min(36, minDimension * 0.04));
    final double innerLogoSize = logoSize * 0.8;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: () {
            // 全アプリに対して完全名称表示を通知
            appTitleFullNameNotifier.value = true;

            // 3秒後に元に戻す
            Future.delayed(const Duration(seconds: 3), () {
              appTitleFullNameNotifier.value = false;
            });
          },
          child: Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(
              color: Colors.amber.shade300,
              shape: BoxShape.circle,
            ),
            child: Stack(
              children: [
                // パイの基本形
                Center(
                  child: Container(
                    width: innerLogoSize,
                    height: innerLogoSize,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade200,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // パイカット
                Align(
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: Size(innerLogoSize, innerLogoSize),
                    painter: PieSlicePainter(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// タイトルテキストを切り替えて表示するウィジェット
class AppTitleText extends StatelessWidget {
  const AppTitleText({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ValueListenableBuilder<bool>(
      valueListenable: appTitleFullNameNotifier,
      builder: (context, showFullName, child) {
        return GestureDetector(
          onTap: () {
            // タップ時に切り替え
            appTitleFullNameNotifier.value = !appTitleFullNameNotifier.value;

            // 完全名称表示モードに切り替わった場合は3秒後に元に戻す
            if (appTitleFullNameNotifier.value) {
              Future.delayed(const Duration(seconds: 4), () {
                appTitleFullNameNotifier.value = false;
              });
            }
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final inAnimation =
                  Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
              ));

              return FadeTransition(
                opacity: inAnimation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.95,
                    end: 1.0,
                  ).animate(inAnimation),
                  child: child,
                ),
              );
            },
            layoutBuilder:
                (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: Text(
              showFullName ? l10n.appLogoFull : l10n.appLogoShort,
              key: ValueKey<bool>(showFullName),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        );
      },
    );
  }
}

// パイの一部が切り取られた形を描画するためのカスタムペインター
class PieSlicePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // キャンバスのサイズチェック
    if (size.width <= 0 || size.height <= 0) {
      return; // 無効なサイズの場合は描画しない
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 < size.height / 2
        ? size.width / 2
        : size.height / 2; // 最小値を使用して範囲エラーを防ぐ

    // 60度の角度でパイの一部をカット
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -0.5, // 開始角度
      1.0, // 終了角度（ラジアン）
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

// 共通の見出し
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  const SectionHeader({super.key, required this.title, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.blue.shade600),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }
}

// ボタンコンテナ
class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final bool isLoading;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = Colors.blue,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// 標準カード
class StandardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hasBorder;

  const StandardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: hasBorder ? Border.all(color: Colors.grey.shade300) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

// 習得度バッジ
class MasteryBadge extends StatelessWidget {
  final int mastery;

  const MasteryBadge({
    super.key,
    required this.mastery,
  });

  @override
  Widget build(BuildContext context) {
    // 習得度に基づいて色を決定
    final Color badgeColor = mastery < 1
        ? Colors.grey.shade400
        : mastery < 3
            ? Colors.blue.shade400
            : mastery < 5
                ? Colors.green.shade500
                : Colors.amber.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withOpacity(0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            mastery < 1
                ? Icons.star_border
                : mastery < 3
                    ? Icons.star_half
                    : Icons.star,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$mastery',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
