import 'package:flutter/material.dart';

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // パイのアイコン
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.amber.shade300,
              shape: BoxShape.circle,
            ),
            child: Stack(
              children: [
                // パイの基本形
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
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
                    size: const Size(40, 40),
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
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Text(
                _showFullName ? '暗記 Planner ai' : '暗記Pai',
                key: ValueKey<bool>(_showFullName),
                style: TextStyle(
                  fontSize: _showFullName ? 28 : 32,
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
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.amber.shade300,
          shape: BoxShape.circle,
        ),
        child: Stack(
          children: [
            // パイの基本形
            Center(
              child: Container(
                width: 24,
                height: 24,
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
                size: const Size(24, 24),
                painter: PieSlicePainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// タイトルテキストを切り替えて表示するウィジェット
class AppTitleText extends StatelessWidget {
  const AppTitleText({super.key});

  @override
  Widget build(BuildContext context) {
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
              showFullName ? '暗記 Planner ai' : '暗記Pai',
              key: ValueKey<bool>(showFullName),
              style: TextStyle(
                fontSize: showFullName ? 18 : 18, // 同じサイズで統一
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

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

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
    this.color = const Color(0xFF2196F3), // デフォルトは青
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hasBorder
            ? BorderSide(color: Colors.blue.shade200)
            : BorderSide.none,
      ),
      color: Colors.white.withOpacity(0.9),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

// 習得度バッジ
class MasteryBadge extends StatelessWidget {
  final int mastery;

  const MasteryBadge({super.key, required this.mastery});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    if (mastery < 30) {
      color = Colors.red.shade400;
      label = '初級';
    } else if (mastery < 70) {
      color = Colors.orange.shade400;
      label = '中級';
    } else {
      color = Colors.green.shade500;
      label = '上級';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        '$label ($mastery%)',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
