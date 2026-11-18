import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const questionUrl =
    'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium&type=boolean&encode=url3986';

class QuizException implements Exception {
  const QuizException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ScienceQuestion {
  const ScienceQuestion({
    required this.prompt,
    required this.correct,
    required this.encodedPrompt,
  });
  final String prompt;
  final bool correct;
  final String encodedPrompt;

  static String decode(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const QuizException(
        'Response contains an empty or invalid string.',
      );
    }
    try {
      final decoded = Uri.decodeComponent(value);
      if (decoded.trim().isEmpty) throw const FormatException();
      return decoded;
    } on FormatException {
      throw const QuizException(
        'Response contains malformed percent encoding.',
      );
    } on ArgumentError {
      throw const QuizException(
        'Response contains malformed percent encoding.',
      );
    }
  }

  factory ScienceQuestion.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const QuizException('A question is not a valid object.');
    }
    final category = decode(raw['category']);
    final prompt = decode(raw['question']);
    final correct = decode(raw['correct_answer']);
    final wrong = raw['incorrect_answers'];
    if (category != 'Science & Nature' ||
        raw['difficulty'] != 'medium' ||
        raw['type'] != 'boolean' ||
        wrong is! List ||
        wrong.length != 1) {
      throw const QuizException(
        'Expected five medium Science & Nature true/false questions.',
      );
    }
    final incorrect = decode(wrong.single);
    if (!((correct == 'True' && incorrect == 'False') ||
        (correct == 'False' && incorrect == 'True'))) {
      throw const QuizException(
        'Answer values must be exactly True and False.',
      );
    }
    return ScienceQuestion(
      prompt: prompt,
      correct: correct == 'True',
      encodedPrompt: raw['question'] as String,
    );
  }
}

List<ScienceQuestion> parseQuestions(String body) {
  try {
    final raw = jsonDecode(body);
    if (raw is! Map<String, dynamic> || raw['response_code'] != 0) {
      throw const QuizException(
        'Trivia service returned an unsuccessful API code. Retry after five seconds.',
      );
    }
    final results = raw['results'];
    if (results is! List || results.length != 5) {
      throw const QuizException(
        'Trivia service must return exactly five questions.',
      );
    }
    return List.unmodifiable(results.map(ScienceQuestion.fromJson));
  } on FormatException {
    throw const QuizException('Trivia service returned invalid JSON.');
  }
}

abstract interface class QuestionSource {
  Future<List<ScienceQuestion>> load();
  Duration get retryAfter;
}

class OpenTriviaSource implements QuestionSource {
  OpenTriviaSource({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  DateTime? _lastRequest;

  @override
  Duration get retryAfter {
    if (_lastRequest == null) return Duration.zero;
    final remaining =
        const Duration(seconds: 5) - _now().difference(_lastRequest!);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Future<List<ScienceQuestion>> load() async {
    if (retryAfter > Duration.zero) {
      throw const QuizException(
        'Wait at least five seconds between trivia requests.',
      );
    }
    _lastRequest = _now();
    try {
      final response = await _client
          .get(Uri.parse(questionUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw QuizException(
          'Trivia HTTP ${response.statusCode}. Please retry.',
        );
      }
      return parseQuestions(response.body);
    } on TimeoutException {
      throw const QuizException(
        'Trivia request timed out after 10 seconds. Please retry.',
      );
    } on http.ClientException {
      throw const QuizException(
        'Trivia service is unreachable. Check your connection and retry.',
      );
    }
  }
}
