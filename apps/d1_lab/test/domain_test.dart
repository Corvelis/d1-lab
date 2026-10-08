import 'package:flutter_test/flutter_test.dart';
import 'package:d1_lab/domain.dart';

void main() {
  test('media-only input still requires a valid decision question', () {
    final q = Question(
      id: '1',
      type: 'noul',
      instructions: 'Is this a command?',
    );
    expect(() => snapshot('', [q], true), throwsFormatException);
    expect(snapshot('', [q], true, allowEmptyState: true)['state'], '');
    expect(
      () => snapshot('', [], true, allowEmptyState: true),
      throwsFormatException,
    );
    q.instructions = '';
    expect(
      () => snapshot('', [q], true, allowEmptyState: true),
      throwsFormatException,
    );
  });
  test('comparison input keeps the question order and freezes the draft', () {
    final q = Question(
      id: '1',
      instructions: 'Pick one.',
      criteria: 'A|First\nB|Second',
    );
    final input = snapshot('state', [q], true);
    q.instructions = 'Changed';
    q.criteria = 'C\nD';
    expect(input['questions'][0]['instructions'], 'Pick one.');
    expect(input['questions'][0]['options'][1]['name'], 'B');
  });
  test('ambiguous candidate names and invalid score scales are rejected', () {
    expect(
      () => Question(
        id: '1',
        instructions: 'Pick.',
        criteria: 'A|one\nA|two',
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => Question(
        id: '2',
        type: 'score',
        instructions: 'Rate.',
        criteria: 'one',
      ).toJson(),
      throwsFormatException,
    );
    expect(
      Question(
        id: '3',
        type: 'score',
        instructions: 'Rate.',
        criteria: 'low\nmedium\nhigh',
      ).toJson()['levels'],
      ['low', 'medium', 'high'],
    );
  });
}
