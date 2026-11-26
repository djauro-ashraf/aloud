import 'package:aloud_core/aloud_core.dart';

/// Human-readable labels for the rules UI.
abstract final class RulesText {
  static const structureLabels = {
    StructureKind.quotedSpeech: 'Quoted speech ("…")',
    StructureKind.allCapsWord: 'Contains an ALL-CAPS word',
    StructureKind.headingLike: 'Looks like a heading',
    StructureKind.asteriskWrapped: 'Wrapped in *asterisks*',
    StructureKind.urlOrEmail: 'Contains a link or email',
    StructureKind.onlySymbols: 'Only symbols',
    StructureKind.sceneBreak: 'Scene break (***, ---)',
    StructureKind.startsWithMarker: 'Starts with a marker ([, (, *, -, #)',
  };

  static const fontLabels = {
    FontKind.italic: 'Italic text',
    FontKind.bold: 'Bold text',
    FontKind.larger: 'Larger text (headings)',
    FontKind.smaller: 'Smaller text (footnotes)',
    FontKind.different: 'Any different formatting',
  };

  static const conditionLabels = {
    ConditionType.containsWord: 'contains the word',
    ConditionType.containsAny: 'contains any of (comma list)',
    ConditionType.doesNotContain: 'does not contain',
    ConditionType.startsWith: 'starts with',
    ConditionType.endsWith: 'ends with',
    ConditionType.isAllCaps: 'is ALL CAPS',
    ConditionType.veryShort: 'is shorter than N words',
    ConditionType.veryLong: 'is longer than N words',
    ConditionType.containsNumber: 'contains a number',
    ConditionType.containsUrlOrEmail: 'contains a link or email',
    ConditionType.onlySymbols: 'is only symbols',
    ConditionType.startsWithMarker: 'starts with a marker',
  };

  /// Conditions that take a text/number value.
  static const needsValue = {
    ConditionType.containsWord,
    ConditionType.containsAny,
    ConditionType.doesNotContain,
    ConditionType.startsWith,
    ConditionType.endsWith,
    ConditionType.veryShort,
    ConditionType.veryLong,
  };

  static String trigger(RuleTrigger t) => switch (t) {
        LiteralTrigger(:final text, :final wholeWord) => 'contains ${wholeWord ? 'the word ' : ''}“$text”',
        RegexTrigger(:final pattern) => 'matches /$pattern/',
        StructureTrigger(:final structure) => structureLabels[structure]!.toLowerCase(),
        FontTrigger(:final font) => fontLabels[font]!.toLowerCase(),
        ConditionsTrigger(:final conditions) => '${conditions.length} condition${conditions.length == 1 ? '' : 's'}',
      };

  static String action(RuleAction a) => switch (a) {
        SkipAction() => 'skip',
        ReplaceAction(:final replacement) => replacement.isEmpty ? 'remove it' : 'say “$replacement”',
        SayBeforeAction(:final phrase) => 'say “$phrase” before',
        SayAfterAction(:final phrase) => 'say “$phrase” after',
        PauseBeforeAction(:final ms) => 'pause $ms ms before',
        PauseAfterAction(:final ms) => 'pause $ms ms after',
        SpeedShiftAction(:final delta) => '${delta >= 0 ? 'speed up' : 'slow down'} by ${(delta.abs() * 100).round()}%',
        StopAction() => 'stop playback',
        NextDocumentAction() => 'jump to the next chapter',
      };

  static String summary(SpeechRule r) =>
      '${r.scope == RuleScope.paragraph ? 'Paragraph' : 'Sentence'} ${trigger(r.trigger)} → ${action(r.action)}';
}
