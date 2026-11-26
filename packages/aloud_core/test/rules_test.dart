import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

SpeechRule r(String id, RuleTrigger t, RuleAction a,
        {RuleScope scope = RuleScope.sentence, int priority = 0}) =>
    SpeechRule(id: id, name: id, trigger: t, action: a, scope: scope, priority: priority);

void main() {
  group('RuleEngine sentence', () {
    test('skip keeps original text but speaks nothing', () {
      final e = RuleEngine([r('a', const LiteralTrigger('patreon'), const SkipAction())]);
      final p = e.plan('Support me on Patreon!');
      expect(p.skip, isTrue);
      expect(p.original, 'Support me on Patreon!');
      expect(p.hasSpeech, isFalse);
    });
    test('replace literal, whole word', () {
      final e = RuleEngine([
        r('a', const LiteralTrigger('cat', wholeWord: true), const ReplaceAction('dog')),
      ]);
      expect(e.plan('The cat and the concatenate').spoken, 'The dog and the concatenate');
    });
    test('replace regex deletes → skip when empty', () {
      final e = RuleEngine([r('a', const RegexTrigger(r'^\[\d+\]$'), const ReplaceAction(''))]);
      expect(e.plan('[12]').skip, isTrue);
    });
    test('priority orders chained replacements', () {
      final e = RuleEngine([
        r('late', const LiteralTrigger('b'), const ReplaceAction('c'), priority: 5),
        r('early', const LiteralTrigger('a'), const ReplaceAction('b'), priority: 1),
      ]);
      expect(e.plan('a').spoken, 'c');
    });
    test('disabled rules are ignored', () {
      final off = r('a', const LiteralTrigger('x'), const SkipAction()).copyWith(enabled: false);
      expect(RuleEngine([off]).plan('x marks').skip, isFalse);
    });
    test('say before/after, pauses, speed', () {
      final e = RuleEngine([
        r('1', const StructureTrigger(StructureKind.quotedSpeech), const SayBeforeAction('Quote:')),
        r('2', const StructureTrigger(StructureKind.quotedSpeech), const PauseAfterAction(400)),
        r('3', const StructureTrigger(StructureKind.quotedSpeech), const SpeedShiftAction(0.2)),
      ]);
      final p = e.plan('"Hello there," she said.');
      expect(p.before, ['Quote:']);
      expect(p.pauseAfterMs, 400);
      expect(p.speedDelta, closeTo(0.2, 1e-9));
      expect(p.fullSpeech.startsWith('Quote: '), isTrue);
    });
    test('symbols-only is skipped but pause still reported', () {
      final e = RuleEngine([
        r('a', const StructureTrigger(StructureKind.sceneBreak), const PauseAfterAction(900)),
      ]);
      final p = e.plan('* * *');
      expect(p.skip, isTrue);
      expect(p.pauseAfterMs, 900);
    });
    test('stop and next-document flow', () {
      final e = RuleEngine([r('a', const LiteralTrigger('THE END'), const StopAction())]);
      expect(e.plan('THE END').flow, FlowDirective.stop);
    });
    test('font triggers need context', () {
      final e = RuleEngine([r('a', const FontTrigger(FontKind.italic), const SpeedShiftAction(-0.1))]);
      expect(e.plan('thought').speedDelta, 0);
      expect(e.plan('thought', context: const SentenceContext(italic: true)).speedDelta,
          closeTo(-0.1, 1e-9));
    });
    test('builder conditions with AND/OR/negation', () {
      final e = RuleEngine([
        r(
          'a',
          const ConditionsTrigger([
            RuleCondition(ConditionType.containsAny, value: 'sale, discount'),
            RuleCondition(ConditionType.containsNumber),
            RuleCondition(ConditionType.containsUrlOrEmail, or: true),
          ]),
          const SkipAction(),
        ),
      ]);
      expect(e.plan('Big sale 50 today').skip, isTrue);
      expect(e.plan('Big sale today').skip, isFalse);
      expect(e.plan('visit www.x.com').skip, isTrue);
    });
    test('invalid regex never matches and never throws', () {
      final e = RuleEngine([r('a', const RegexTrigger('(unclosed'), const SkipAction())]);
      expect(e.plan('anything').skip, isFalse);
      expect(RuleEngine.validateRegex('(unclosed'), isNotNull);
      expect(RuleEngine.validateRegex('ok+'), isNull);
    });
    test('normaliser runs after rules', () {
      final e = RuleEngine([r('a', const LiteralTrigger('X'), const ReplaceAction('3'))]);
      expect(e.plan('X cats').spoken, 'three cats');
    });
  });

  group('RuleEngine paragraph', () {
    test('skip, flow and pauses', () {
      final e = RuleEngine([
        r('a', const RegexTrigger(r"^a/?n:", caseSensitive: false), const SkipAction(),
            scope: RuleScope.paragraph),
        r('b', const LiteralTrigger('fin'), const NextDocumentAction(), scope: RuleScope.paragraph),
      ]);
      expect(e.checkParagraph('A/N: hi').skip, isTrue);
      expect(e.checkParagraph('fin').flow, FlowDirective.nextDocument);
      expect(e.checkParagraph('normal'), same(ParagraphVerdict.pass));
    });
  });

  group('fingerprint and json', () {
    test('changes when rules change, stable otherwise', () {
      final a = RuleEngine([r('a', const LiteralTrigger('x'), const SkipAction())]);
      final a2 = RuleEngine([r('a', const LiteralTrigger('x'), const SkipAction())]);
      final b = RuleEngine([r('a', const LiteralTrigger('y'), const SkipAction())]);
      expect(a.fingerprint, a2.fingerprint);
      expect(a.fingerprint == b.fingerprint, isFalse);
    });
    test('every template round-trips through json', () {
      for (final t in RuleTemplates.all) {
        final back = SpeechRule.fromJson(t.rule.toJson());
        expect(back.toJson(), t.rule.toJson());
      }
    });
    test('default templates behave', () {
      final e = RuleEngine(RuleTemplates.defaults());
      expect(e.checkParagraph("Author's Note: thanks all").skip, isTrue);
      expect(e.plan('He left[3].').spoken, 'He left.');
      expect(e.plan('See https://a.b/c').skip, isTrue);
      expect(e.plan('***').pauseAfterMs, 900);
    });
  });
}
