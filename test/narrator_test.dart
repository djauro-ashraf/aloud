import 'dart:async';

import 'package:aloud/features/listen/engines/fallback_backend.dart';
import 'package:aloud/features/listen/engines/speech_backend.dart';
import 'package:aloud/features/listen/narrator.dart';
import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable backend: records spoken text, completes after [speakFor].
class FakeBackend implements SpeechBackend {
  FakeBackend({this.inPlace = true, this.speakFor = const Duration(milliseconds: 5), this.kind = EngineKind.edge});

  final bool inPlace;
  final Duration speakFor;
  @override
  final EngineKind kind;
  final spoken = <String>[];
  final prefetched = <List<String>>[];
  final speeds = <double>[];
  Object? failWith;
  Completer<SpeakOutcome>? _c;
  bool _paused = false;
  int stops = 0;

  @override
  bool get pausesInPlace => inPlace;

  @override
  Future<void> prefetch(List<SpeechItem> upcoming) async => prefetched.add([for (final i in upcoming) i.text]);

  @override
  Future<void> renderAhead(List<SpeechItem> items, {void Function(int done)? onProgress, bool Function()? isCancelled}) async {}

  @override
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed}) async {
    final f = failWith;
    if (f != null) throw f;
    spoken.add(item.text);
    speeds.add(speed);
    final c = _c = Completer<SpeakOutcome>();
    Timer(speakFor, () => _tick(c));
    return c.future;
  }

  void _tick(Completer<SpeakOutcome> c) {
    if (c.isCompleted) return;
    if (_paused) {
      Timer(const Duration(milliseconds: 5), () => _tick(c));
    } else {
      c.complete(SpeakOutcome.completed);
    }
  }

  @override
  Future<void> pause() async => _paused = true;
  @override
  Future<void> resume() async => _paused = false;
  @override
  Future<void> stop() async {
    stops++;
    _paused = false;
    final c = _c;
    if (c != null && !c.isCompleted) c.complete(SpeakOutcome.cancelled);
  }

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);
  @override
  Future<void> dispose() async {}
}

/// A device-voice stand-in: announces the start of every word it speaks.
class WordReportingBackend extends FakeBackend implements SpokenOffsetSource {
  WordReportingBackend() : super(kind: EngineKind.system);

  final _offsets = StreamController<int>.broadcast();

  @override
  Stream<int> get spokenOffsets => _offsets.stream;

  @override
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed}) {
    final done = super.speak(item, speed: speed);
    scheduleMicrotask(() {
      for (final m in RegExp(r'\S+').allMatches(item.text)) {
        _offsets.add(m.start);
      }
    });
    return done;
  }
}

const _voice = VoiceInfo(engine: EngineKind.edge, id: 'v', name: 'V');

ReaderSection section(List<String> paras) => ReaderSection(
      title: 't',
      blocks: [for (final p in paras) ReaderBlock.paragraph(p)],
    );

Narrator make(FakeBackend b, ReaderSection s, {List<SpeechRule> rules = const [], int prefetch = 2}) {
  final n = Narrator(
    backend: () => b,
    rules: () => RuleEngine(rules),
    voice: () => _voice,
    settings: () => NarratorSettings(paragraphPauseMs: 0, sentencePauseMs: 0, prefetch: prefetch),
  );
  return n;
}

Future<void> until(bool Function() cond, {int ms = 2000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw StateError('timeout waiting for condition');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  group('Narrator word events', () {
    Future<List<WordEvent>> wordsFor(FakeBackend b, String text) async {
      final s = section([text]);
      final n = make(b, s, prefetch: 0);
      final words = <WordEvent>[];
      n.events.where((e) => e is WordEvent).cast<WordEvent>().listen(words.add);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      await n.dispose();
      return words;
    }

    test('device voice: one event per displayed word, in order', () async {
      final words = await wordsFor(WordReportingBackend(), 'Hello big world.');
      expect(words.map((w) => w.word).toList(), [0, 1, 2]);
      expect(words.every((w) => w.sentence == 0), isTrue);
    });

    test('a number spoken as a word still highlights the displayed digit', () async {
      final words = await wordsFor(WordReportingBackend(), 'I have 3 cats.');
      // spoken: "I have three cats." -> displayed words 0,1,2,3
      expect(words.map((w) => w.word).toList(), [0, 1, 2, 3]);
    });

    test('neural engine publishes no word events (sentence level only)', () async {
      final words = await wordsFor(FakeBackend(), 'Hello big world.');
      expect(words, isEmpty);
    });
  });
  group('Narrator', () {
    test('reads every sentence in order, emits cursor and end', () async {
      final b = FakeBackend();
      final s = section(['One. Two.', 'Three.']);
      final n = make(b, s);
      final events = <NarratorEvent>[];
      n.events.listen(events.add);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.spoken, ['One.', 'Two.', 'Three.']);
      expect(events.whereType<CursorEvent>().map((e) => e.index).toSet(), {0, 1, 2});
      expect(events.whereType<SectionEndEvent>().single.flow, FlowDirective.none);
      await n.dispose();
    });

    test('prefetches upcoming sentences without including the current one', () async {
      final b = FakeBackend();
      final s = section(['A one. B two. C three. D four.']);
      final n = make(b, s, prefetch: 2);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.prefetched.first, ['B two.', 'C three.']);
      await n.dispose();
    });

    test('rules: skipped paragraphs and sentences are never spoken; replacements apply', () async {
      final b = FakeBackend();
      final s = section(["Author's Note: hi.", 'Keep this. Visit www.x.com now.', 'Cats are 3.']);
      final n = make(b, s, rules: RuleTemplates.defaults());
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.spoken, ['Keep this.', 'Cats are three.']);
      await n.dispose();
    });

    test('pause/resume in place continues the same sentence', () async {
      final b = FakeBackend(speakFor: const Duration(milliseconds: 40));
      final s = section(['One. Two. Three.']);
      final n = make(b, s);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => b.spoken.length == 1);
      await n.pause();
      expect(n.status, NarratorStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(b.spoken.length, 1); // nothing advanced while paused
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.spoken, ['One.', 'Two.', 'Three.']);
      await n.dispose();
    });

    test('pause without in-place support re-speaks the sentence on resume', () async {
      final b = FakeBackend(inPlace: false, speakFor: const Duration(milliseconds: 40), kind: EngineKind.system);
      final s = section(['One. Two.']);
      final n = make(b, s);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => b.spoken.length == 1);
      await n.pause();
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.spoken, ['One.', 'One.', 'Two.']);
      await n.dispose();
    });

    test('jumpTo while playing restarts from the target', () async {
      final b = FakeBackend(speakFor: const Duration(milliseconds: 30));
      final s = section(['Alpha one. Bravo two. Charlie three. Delta four.']);
      final n = make(b, s);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => b.spoken.length == 1);
      await n.jumpTo(3);
      await until(() => n.status == NarratorStatus.ended);
      expect(b.spoken, ['Alpha one.', 'Delta four.']);
      await n.dispose();
    });

    test('paragraph navigation', () async {
      final b = FakeBackend();
      final s = section(['A1. A2.', 'B1. B2.', 'C1.']);
      final n = make(b, s);
      await n.load(s, SectionIndex.build(s));
      await n.nextParagraph();
      expect(n.cursor, 2);
      await n.nextParagraph();
      expect(n.cursor, 4);
      await n.previousParagraph(); // at first of block → previous block
      expect(n.cursor, 2);
      await n.jumpTo(3);
      await n.previousParagraph(); // mid block → restart block
      expect(n.cursor, 2);
      await n.dispose();
    });

    test('rule "stop" pauses at that point; next-document ends with flow', () async {
      final b = FakeBackend();
      final s = section(['Read me.', 'STOPHERE', 'Not read.']);
      final n = make(b, s, rules: [
        const SpeechRule(id: 's', name: 's', trigger: LiteralTrigger('STOPHERE'), action: StopAction()),
      ]);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.paused);
      expect(b.spoken, ['Read me.']);
      await n.dispose();

      final b2 = FakeBackend();
      final s2 = section(['Hello.', 'Thanks for reading!', 'Ghost.']);
      final n2 = make(b2, s2, rules: RuleTemplates.all.where((t) => t.rule.id == 'tpl.next_on_signoff').map((t) => t.rule).toList());
      final ev = <NarratorEvent>[];
      n2.events.listen(ev.add);
      await n2.load(s2, SectionIndex.build(s2));
      await n2.play();
      await until(() => n2.status == NarratorStatus.ended);
      expect(ev.whereType<SectionEndEvent>().single.flow, FlowDirective.nextDocument);
      expect(b2.spoken, ['Hello.']);
      await n2.dispose();
    });

    test('speech failure pauses and reports an error', () async {
      final b = FakeBackend()..failWith = const SpeechException('boom');
      final s = section(['One.']);
      final n = make(b, s);
      final ev = <NarratorEvent>[];
      n.events.listen(ev.add);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => ev.whereType<ErrorEvent>().isNotEmpty);
      expect(ev.whereType<ErrorEvent>().first.message, 'boom');
      expect(n.status, NarratorStatus.paused);
      await n.dispose();
    });

    test('speed shift rules change effective speed then restore', () async {
      final b = FakeBackend();
      final s = section(['Normal one.', '*Whispered thought.*', 'Normal two.']);
      final n = make(b, s, rules: [
        const SpeechRule(
            id: 'x', name: 'x', trigger: StructureTrigger(StructureKind.asteriskWrapped), action: SpeedShiftAction(-0.2)),
      ]);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      await until(() => n.status == NarratorStatus.ended);
      expect(b.speeds[0], closeTo(1.0, 1e-9));
      expect(b.speeds[1], closeTo(0.8, 1e-9));
      expect(b.speeds[2], closeTo(1.0, 1e-9));
      await n.dispose();
    });

    test('empty section ends immediately', () async {
      final b = FakeBackend();
      const s = ReaderSection(title: 't', blocks: []);
      final n = make(b, s);
      await n.load(s, SectionIndex.build(s));
      await n.play();
      expect(n.status, NarratorStatus.ended);
      await n.dispose();
    });
  });

  group('FallbackSpeechBackend', () {
    const sysVoice = VoiceInfo(engine: EngineKind.system, id: '', name: 'sys');
    SpeechItem item(String t) => SpeechItem(text: t, voice: _voice, key: t);

    test('falls back on failure, skips the broken primary during cooldown, then retries', () async {
      final primary = FakeBackend()..failWith = const SpeechException('offline');
      final fallback = FakeBackend(kind: EngineKind.system);
      var now = DateTime(2026, 1, 1);
      final reasons = <String>[];
      final fb = FallbackSpeechBackend(
        primary: primary,
        fallback: fallback,
        fallbackVoice: () => sysVoice,
        onFallback: reasons.add,
        clock: () => now,
      );
      await fb.speak(item('a'), speed: 1);
      await fb.speak(item('b'), speed: 1);
      expect(fallback.spoken, ['a', 'b']);
      expect(reasons.length, 2);

      // Unhealthy: primary isn't even tried.
      primary.failWith = null;
      await fb.speak(item('c'), speed: 1);
      expect(primary.spoken, isEmpty);
      expect(fallback.spoken.last, 'c');

      // After cooldown the primary is tried again.
      now = now.add(const Duration(minutes: 2));
      await fb.speak(item('d'), speed: 1);
      expect(primary.spoken, ['d']);
    });
  });
}
