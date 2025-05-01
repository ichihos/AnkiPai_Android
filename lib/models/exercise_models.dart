/// クイズの質問モデル
class QuizExercise {
  final String question;
  final List<String> options;
  final int correctAnswerIndex;
  final String? explanation;
  
  QuizExercise({
    required this.question,
    required this.options,
    required this.correctAnswerIndex,
    this.explanation,
  });
}

/// 穴埋め問題モデル
class FillBlankExercise {
  final String question;
  final String answer;
  final String sentence;
  final bool isOpenEnded;
  
  FillBlankExercise({
    required this.question,
    required this.answer,
    required this.sentence,
    this.isOpenEnded = false,
  });
}

/// フラッシュカードモデル
class FlashcardExercise {
  final String question;
  final String answer;
  
  FlashcardExercise({
    required this.question,
    required this.answer,
  });
}
