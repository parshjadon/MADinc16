import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:science_signal/quiz.dart';

Map<String, dynamic> sampleQuestion() => {
  'category': 'Science%20%26%20Nature',
  'difficulty': 'medium',
  'type': 'boolean',
  'question': 'Earth%27s%20sky%20is%20blue%2E',
  'correct_answer': 'True',
  'incorrect_answers': ['False'],
};

String body({int code = 0, int count = 5, Map<String, dynamic>? question}) =>
    jsonEncode({
      'response_code': code,
      'results': List.generate(count, (_) => question ?? sampleQuestion()),
    });

void main() {
  test('T02 percent decoding and exact Class B endpoint', () async {
    final source = OpenTriviaSource(
      client: MockClient((request) async {
        expect(request.url.toString(), questionUrl);
        return http.Response(body(), 200);
      }),
    );
    final results = await source.load();
    expect(results, hasLength(5));
    expect(results.first.prompt, "Earth's sky is blue.");
    expect(results.first.correct, isTrue);
  });

  test('T03 rejects nonzero code and four or six questions', () {
    for (final invalid in [
      body(code: 1),
      body(code: 5),
      body(count: 4),
      body(count: 6),
    ]) {
      expect(() => parseQuestions(invalid), throwsA(isA<QuizException>()));
    }
  });

  test('T03 rejects malformed percent escapes and malformed UTF8', () {
    for (final encoded in ['bad%ZZ', 'bad%', '%C0%AF', '%E2%82']) {
      expect(
        () => parseQuestions(
          body(question: {...sampleQuestion(), 'question': encoded}),
        ),
        throwsA(isA<QuizException>()),
      );
    }
  });

  test(
    'T03 rejects wrong category, metadata, empty prompt and invalid answers',
    () {
      for (final change in <Map<String, dynamic>>[
        {'category': 'General%20Knowledge'},
        {'difficulty': 'easy'},
        {'type': 'multiple'},
        {'question': '%20'},
        {'correct_answer': 'true'},
        {'correct_answer': 'False'},
        {'incorrect_answers': []},
        {
          'incorrect_answers': ['False', 'True'],
        },
        {
          'incorrect_answers': ['No'],
        },
        {'question': 5},
      ]) {
        expect(
          () =>
              parseQuestions(body(question: {...sampleQuestion(), ...change})),
          throwsA(isA<QuizException>()),
        );
      }
      expect(() => parseQuestions('<html>'), throwsA(isA<QuizException>()));
    },
  );

  test('HTTP 200 alone is not playable data', () async {
    final source = OpenTriviaSource(
      client: MockClient((_) async => http.Response(body(code: 2), 200)),
    );
    await expectLater(source.load(), throwsA(isA<QuizException>()));
  });

  test(
    'T03 manual retries cannot issue another HTTP request before five seconds',
    () async {
      var now = DateTime.utc(2026, 11, 17);
      var calls = 0;
      final source = OpenTriviaSource(
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response(body(), 200);
        }),
      );
      await source.load();
      await expectLater(source.load(), throwsA(isA<QuizException>()));
      now = now.add(const Duration(milliseconds: 4999));
      await expectLater(source.load(), throwsA(isA<QuizException>()));
      expect(calls, 1);
      now = now.add(const Duration(milliseconds: 1));
      await source.load();
      expect(calls, 2);
    },
  );

  test('HTTP failures have readable errors', () async {
    final source = OpenTriviaSource(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    await expectLater(
      source.load(),
      throwsA(
        isA<QuizException>().having(
          (e) => e.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });
}
