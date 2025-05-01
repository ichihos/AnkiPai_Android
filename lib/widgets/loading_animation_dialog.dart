import 'package:flutter/material.dart';
import 'dart:math' as math;

/// アニメーションタイプの列挙型
enum AnimationType {
  memory, // 記憶法生成用のアニメーション
  flashcard, // フラッシュカード生成用のアニメーション
}

/// ローディング中に表示する、アニメーション付きのダイアログ
class LoadingAnimationDialog extends StatefulWidget {
  final String message;
  final AnimationType animationType;
  final int? itemCount; // 複数項目検出時の項目数
  final bool showItemCount; // 項目数を表示するかどうか

  const LoadingAnimationDialog({
    super.key,
    this.message = '暗記法を生成中...',
    this.animationType = AnimationType.memory,
    this.itemCount,
    this.showItemCount = false,
  });

  /// ダイアログを表示するスタティックメソッド
  static Future<void> show(
    BuildContext context, {
    String message = '暗記法を生成中...',
    AnimationType animationType = AnimationType.memory,
    int? itemCount,
    bool showItemCount = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return LoadingAnimationDialog(
          message: message,
          animationType: animationType,
          itemCount: itemCount,
          showItemCount: showItemCount,
        );
      },
    );
  }

  @override
  _LoadingAnimationDialogState createState() => _LoadingAnimationDialogState();
}

class _LoadingAnimationDialogState extends State<LoadingAnimationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // 記憶法生成用の色
  final List<Color> _memoryColors = [
    Colors.orange.shade300,
    Colors.purple.shade400,
    Colors.green.shade500,
    Colors.blue.shade400,
  ];

  // フラッシュカード生成用の色
  final List<Color> _flashcardColors = [
    Colors.amber.shade300,
    Colors.orange.shade400,
    Colors.deepOrange.shade500,
    Colors.red.shade400,
  ];

  List<Color> get _colors => widget.animationType == AnimationType.memory
      ? _memoryColors
      : _flashcardColors;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.animationType == AnimationType.memory
                ? _buildAnimatedBrain()
                : _buildAnimatedCards(),
            const SizedBox(height: 24),
            Column(
              children: [
                Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: widget.animationType == AnimationType.memory
                        ? Colors.blue.shade800
                        : Colors.deepOrange.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
                // 項目数表示が有効な場合に表示
                if (widget.showItemCount && widget.itemCount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '検出された項目数: ${widget.itemCount}個',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDots(),
          ],
        ),
      ),
    );
  }

  /// アイデアと電球のかわいいアニメーション（記憶法生成用）
  Widget _buildAnimatedBrain() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // 光る背景エフェクト
            _buildPulsatingCircle(1.0, 0.3, _memoryColors[0]),
            _buildPulsatingCircle(0.9, 0.4, _memoryColors[1]),
            _buildPulsatingCircle(0.8, 0.5, _memoryColors[2]),

            // アイデアを表す星エフェクト
            ..._buildStars(value),

            // 中央の電球アイコン
            Transform.translate(
              offset: Offset(0, math.sin(value * math.pi * 2) * 3),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.yellow.shade100,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.yellow.shade600.withOpacity(0.5),
                      blurRadius: 10 + math.sin(value * math.pi) * 10,
                      spreadRadius: 2 + math.sin(value * math.pi) * 3,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.lightbulb,
                    size: 40,
                    color: Colors.yellow.shade600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// アイデアを表す星を生成
  List<Widget> _buildStars(double animationValue) {
    final stars = <Widget>[];

    // 複数の星を異なる位置、角度、大きさで追加
    for (var i = 0; i < 5; i++) {
      final angle = (i / 5) * 2 * math.pi + animationValue * math.pi * 2;
      final distance =
          40.0 + math.sin((animationValue + i * 0.2) * math.pi) * 20;
      final x = math.cos(angle) * distance;
      final y = math.sin(angle) * distance;
      final size = 10.0 + math.sin((animationValue + i * 0.1) * math.pi) * 5;
      final calculatedOpacity =
          0.4 + math.sin((animationValue + i * 0.1) * math.pi) * 0.5;
      final safeOpacity = math.max(0.0, math.min(1.0, calculatedOpacity));

      stars.add(
        Positioned(
          left: x + 30,
          top: y + 30,
          child: Transform.rotate(
            angle: angle,
            child: Icon(
              i % 2 == 0 ? Icons.auto_awesome : Icons.star,
              size: size,
              color: _memoryColors[i % _memoryColors.length]
                  .withOpacity(safeOpacity),
            ),
          ),
        ),
      );
    }

    return stars;
  }

  /// 浮かび上がるカードのアニメーション（フラッシュカード生成用）
  Widget _buildAnimatedCards() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // 複数のカードが浮かび上がるアニメーション
            Transform.translate(
              offset: Offset(0, math.sin(value * math.pi * 2) * 10),
              child: Transform.scale(
                scale: 0.7 + math.sin(value * math.pi) * 0.2,
                child: _buildCard(0, -10.0, 0.8),
              ),
            ),
            Transform.translate(
              offset: Offset(math.sin((value + 0.2) * math.pi * 2) * 15, 0),
              child: Transform.scale(
                scale: 0.8 + math.sin((value + 0.3) * math.pi) * 0.15,
                child: _buildCard(1, 0.0, 0.9),
              ),
            ),
            Transform.translate(
              offset: Offset(math.sin((value + 0.4) * math.pi * 2) * 10, -5),
              child: Transform.scale(
                scale: 0.9 + math.sin((value + 0.6) * math.pi) * 0.1,
                child: _buildCard(2, 10.0, 1.0),
              ),
            ),

            // 中央の閃光エフェクト
            if (value > 0.7 && value < 0.9)
              Container(
                width: 20 + (value - 0.7) * 100,
                height: 20 + (value - 0.7) * 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(1.0 - (value - 0.7) * 5),
                ),
              ),
          ],
        );
      },
    );
  }

  /// フラッシュカードを表現するウィジェット
  Widget _buildCard(int colorIndex, double rotation, double opacity) {
    return Transform.rotate(
      angle: rotation * (math.pi / 180),
      child: Container(
        width: 70,
        height: 50,
        decoration: BoxDecoration(
          color: _flashcardColors[colorIndex % _flashcardColors.length],
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2 * opacity),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.question_mark,
            color: Colors.white.withOpacity(opacity),
            size: 22,
          ),
        ),
      ),
    );
  }

  /// パルスエフェクトの円を作成
  Widget _buildPulsatingCircle(double scale, double opacity, Color color) {
    final size = 100.0 * scale;
    final pulseAnimation = Tween<double>(
      begin: size * 0.8,
      end: size * 1.2,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          0.2 * scale,
          0.8 * scale,
          curve: Curves.easeInOut,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Container(
          width: pulseAnimation.value,
          height: pulseAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(opacity * (1 - _controller.value)),
          ),
        );
      },
    );
  }

  /// 点滅するドットのアニメーション
  Widget _buildDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delayedValue = (_controller.value + (index * 0.2)) % 1.0;
            final scale = 0.5 + math.sin(delayedValue * math.pi) * 0.5;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _colors[index % _colors.length].withOpacity(scale),
              ),
            );
          },
        );
      }),
    );
  }
}
