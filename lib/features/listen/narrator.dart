import 'dart:async';

import 'package:aloud_core/aloud_core.dart';

import 'engines/speech_backend.dart';

enum NarratorStatus { idle, playing, paused, ended }

/// Events the narrator publishes.
sealed class NarratorEvent {
  const NarratorEvent();
}

final class CursorEvent extends NarratorEvent {
  const CursorEvent(this.index);
  final int index;
}

final class StatusEvent extends NarratorEvent {
  const StatusEvent(this.status);
  final NarratorStatus status;
}

/// The section's sentences are exhausted ([FlowDirective.none]) or a rule
/// asked to jump to the next document.
final class SectionEndEvent extends NarratorEvent {
  const SectionEndEvent(this.flow);
  final FlowDirective flow;
}

final class ErrorEvent extends NarratorEvent {
  const ErrorEvent(this.message);
  final String message;
}

/// Live-tunable parameters, read fresh for every sentence so settings
/// changes apply immediately without restarting playback.
final class NarratorSettings {
  const NarratorSettings({
    this.speed = 1.0,
    this.paragraphPauseMs = 350,
    this.sentencePauseMs = 80,
    this.prefetch = 3,
  });

  final double speed;
  final int paragraphPauseMs;
  final int sentencePauseMs;
  final int prefetch;
}

/// Reads one section aloud, sentence by sentence.
///
/// Responsibilities: apply rules, build speech items, drive the
/// [SpeechBackend], insert natural pauses, prefetch upcoming audio, and
/// publish the cursor so the UI can highlight and scroll.
///
/// It owns no UI and no persistence. The reading controller feeds it a
/// section and reacts to its events.
final class Narrator {
  Narrator({
    required this._backend,
    required this._rules,
    required this._voice,
    required this._settings,
  });

  final SpeechBackend Function() _backend;
  final RuleEngine Function() _rules;
  final VoiceInfo Function() _voice;
  final NarratorSettings Function() _settings;

  final _events = StreamController<NarratorEvent>.broadcast();
  Stream<NarratorEvent> get events => _events.stream;

  ReaderSection _section = const ReaderSection(title: '', blocks: []);
  SectionIndex _index = SectionIndex.build(const ReaderSection(title: '', blocks: []));

  NarratorStatus _status = NarratorStatus.idle;
  int _cursor = 0;
  int _token = 0;
  bool _inPlacePaused = false;
  Completer<void>? _gate;
  double _stickySpeed = 0;
  final _blockVerdicts = <int, ParagraphVerdict>{};

  NarratorStatus get status => _status;
  int get cursor => _cursor;
  SectionIndex get index => _index;
  bool get isPlaying => _status == NarratorStatus.playing;

  // ── Loading ────────────────────────────────────────────────────────────

  /// Replaces the section being read. Stops any current speech.
  Future<void> load(ReaderSection section, SectionIndex index, {int startAt = 0}) async {
    await _halt();
    _section = section;
    _index = index;
    _cursor = index.isEmpty ? 0 : startAt.clamp(0, index.length - 1);
    _blockVerdicts.clear();
    _stickySpeed = 0;
    _setStatus(NarratorStatus.idle);
    _events.add(CursorEvent(_cursor));
  }

  // ── Transport ──────────────────────────────────────────────────────────

  Future<void> play() async {
    if (_status == NarratorStatus.playing) return;
    if (_index.isEmpty) {
      _setStatus(NarratorStatus.ended);
      _events.add(const SectionEndEvent(FlowDirective.none));
      return;
    }
    if (_status == NarratorStatus.ended) _cursor = 0;

    if (_status == NarratorStatus.paused && _inPlacePaused) {
      _inPlacePaused = false;
      _setStatus(NarratorStatus.playing);
      _releaseGate();
      await _backend().resume();
      return;
    }
    _startRun();
  }

  void _startRun() {
    _setStatus(NarratorStatus.playing);
    final token = ++_token;
    unawaited(_run(token));
  }

  Future<void> pause() async {
    if (_status != NarratorStatus.playing) return;
    final backend = _backend();
    if (backend.pausesInPlace) {
      _inPlacePaused = true;
      _gate = Completer<void>();
      _setStatus(NarratorStatus.paused);
      await backend.pause();
    } else {
      // Can't freeze the voice: cancel and re-speak this sentence on resume.
      _token++;
      _inPlacePaused = false;
      _setStatus(NarratorStatus.paused);
      await backend.stop();
    }
  }

  Future<void> togglePlay() => isPlaying ? pause() : play();

  Future<void> stop() async {
    await _halt();
    _setStatus(NarratorStatus.idle);
  }

  /// Moves to [sentence]; keeps playing if it was playing.
  Future<void> jumpTo(int sentence) async {
    if (_index.isEmpty) return;
    final wasPlaying = _status == NarratorStatus.playing;
    await _halt();
    _cursor = sentence.clamp(0, _index.length - 1);
    _events.add(CursorEvent(_cursor));
    if (wasPlaying) {
      _startRun();
    } else if (_status == NarratorStatus.ended) {
      _setStatus(NarratorStatus.idle);
    }
  }

  Future<void> nextSentence() => jumpTo(_cursor + 1 >= _index.length ? _index.length - 1 : _cursor + 1);

  Future<void> previousSentence() => jumpTo(_cursor - 1);

  /// First sentence of the next/previous paragraph.
  Future<void> nextParagraph() async {
    if (_index.isEmpty) return;
    final block = _index.sentences[_cursor].block;
    final target = _index.firstSentenceAtOrAfterBlock(block + 1);
    if (target != null) await jumpTo(target);
  }

  Future<void> previousParagraph() async {
    if (_index.isEmpty) return;
    final s = _index.sentences[_cursor];
    // Restart the current paragraph first; a second press goes further back.
    final firstOfBlock = _index.firstSentenceAtOrAfterBlock(s.block) ?? 0;
    if (_cursor > firstOfBlock) return jumpTo(firstOfBlock);
    for (var b = s.block - 1; b >= 0; b--) {
      final first = _index.firstSentenceAtOrAfterBlock(b);
      if (first != null && _index.sentences[first].block == b) return jumpTo(first);
    }
    return jumpTo(0);
  }

  /// Applies a changed speed setting to the sentence being spoken.
  Future<void> speedChanged() async {
    if (_status == NarratorStatus.idle || _status == NarratorStatus.ended) return;
    await _backend().setSpeed(_effectiveSpeed(0));
  }

  Future<void> dispose() async {
    await _halt();
    await _events.close();
  }

  // ── Loop ───────────────────────────────────────────────────────────────

  bool _alive(int token) => token == _token && _status != NarratorStatus.idle;

  Future<void> _halt() async {
    _token++;
    _inPlacePaused = false;
    _releaseGate();
    await _backend().stop();
  }

  void _releaseGate() {
    final g = _gate;
    _gate = null;
    if (g != null && !g.isCompleted) g.complete();
  }

  Future<void> _checkpoint(int token) async {
    final g = _gate;
    if (g != null) await g.future;
    // Pause cancelled this run, or a jump started another one.
    if (token != _token) return;
  }

  Future<void> _run(int token) async {
    var lastBlock = -1;
    while (_alive(token)) {
      await _checkpoint(token);
      if (!_alive(token)) return;

      if (_cursor >= _index.length) {
        _setStatus(NarratorStatus.ended);
        _events.add(const SectionEndEvent(FlowDirective.none));
        return;
      }

      final sentence = _index.sentences[_cursor];
      final block = _section.blocks[sentence.block];
      final verdict = _blockVerdicts[sentence.block] ??= _rules().checkParagraph(block.text, context: block.context);
      final enteringBlock = sentence.block != lastBlock;
      lastBlock = sentence.block;

      // Whole paragraph skipped by a rule: hop over it silently.
      if (verdict.skip) {
        _cursor = _firstSentenceAfterBlock(sentence.block);
        continue;
      }
      if (enteringBlock && sentence.inBlock == 0) {
        if (verdict.flow == FlowDirective.stop) {
          await _stopFromRule(token);
          return;
        }
        if (verdict.flow == FlowDirective.nextDocument) {
          _setStatus(NarratorStatus.ended);
          _events.add(const SectionEndEvent(FlowDirective.nextDocument));
          return;
        }
        if (verdict.pauseBeforeMs > 0) await _wait(verdict.pauseBeforeMs, token);
        if (!_alive(token)) return;
      }

      _events.add(CursorEvent(_cursor));
      final plan = _rules().plan(sentence.text, context: block.context);

      if (plan.flow == FlowDirective.stop) {
        await _stopFromRule(token);
        return;
      }
      if (plan.flow == FlowDirective.nextDocument) {
        _setStatus(NarratorStatus.ended);
        _events.add(const SectionEndEvent(FlowDirective.nextDocument));
        return;
      }

      if (plan.pauseBeforeMs > 0) await _wait(plan.pauseBeforeMs, token);
      if (!_alive(token)) return;

      if (plan.hasSpeech) {
        final ok = await _speak(plan, token);
        if (!ok) return;
      }
      if (!plan.restoreSpeed) _stickySpeed = (_stickySpeed + plan.speedDelta).clamp(-1.0, 1.5);

      final pauseAfter = plan.pauseAfterMs + _gapAfter(sentence, verdict);
      if (pauseAfter > 0) await _wait(pauseAfter, token);
      if (!_alive(token)) return;

      _cursor++;
    }
  }

  Future<void> _stopFromRule(int token) async {
    if (!_alive(token)) return;
    _token++;
    _setStatus(NarratorStatus.paused);
    await _backend().stop();
  }

  /// Natural gap after a sentence: longer at paragraph ends.
  int _gapAfter(SentenceRef s, ParagraphVerdict verdict) {
    final next = s.index + 1;
    final settings = _settings();
    final lastInBlock = next >= _index.length || _index.sentences[next].block != s.block;
    return (lastInBlock ? settings.paragraphPauseMs : settings.sentencePauseMs) +
        (lastInBlock ? verdict.pauseAfterMs : 0);
  }

  int _firstSentenceAfterBlock(int block) => _index.firstSentenceAtOrAfterBlock(block + 1) ?? _index.length;

  double _effectiveSpeed(double delta) => (_settings().speed + _stickySpeed + delta).clamp(0.5, 3.0);

  Future<bool> _speak(SpeechPlan plan, int token) async {
    final backend = _backend();
    final voice = _voice();
    final fingerprint = _rules().fingerprint;
    final item = SpeechItem(
      text: plan.fullSpeech,
      voice: voice,
      key: SpeechItem.keyFor(voice, plan.fullSpeech, fingerprint),
    );

    // Speak first so the current sentence is first in any synthesis queue,
    // then hint what comes next.
    final speaking = backend.speak(item, speed: _effectiveSpeed(plan.restoreSpeed ? plan.speedDelta : 0));
    unawaited(backend.prefetch(_upcoming(voice, fingerprint)));
    try {
      final outcome = await speaking;
      return outcome == SpeakOutcome.completed && _alive(token);
    } on SpeechException catch (e) {
      if (_alive(token)) {
        _token++;
        _setStatus(NarratorStatus.paused);
        _events.add(ErrorEvent(e.message));
        await backend.stop();
      }
      return false;
    }
  }

  List<SpeechItem> _upcoming(VoiceInfo voice, String fingerprint) =>
      _itemsFrom(_cursor + 1, _settings().prefetch, voice, fingerprint);

  /// Speech items for up to [count] speakable sentences starting at [start].
  /// Used for prefetching and for offline preparation of a whole section.
  List<SpeechItem> itemsFrom(int start, {required int count}) =>
      _itemsFrom(start, count, _voice(), _rules().fingerprint);

  List<SpeechItem> _itemsFrom(int start, int count, VoiceInfo voice, String fingerprint) {
    final out = <SpeechItem>[];
    for (var i = start; i < _index.length && out.length < count; i++) {
      final s = _index.sentences[i];
      final block = _section.blocks[s.block];
      final verdict = _blockVerdicts[s.block] ??= _rules().checkParagraph(block.text, context: block.context);
      if (verdict.skip) continue;
      final plan = _rules().plan(s.text, context: block.context);
      if (!plan.hasSpeech) continue;
      out.add(SpeechItem(
        text: plan.fullSpeech,
        voice: voice,
        key: SpeechItem.keyFor(voice, plan.fullSpeech, fingerprint),
      ));
    }
    return out;
  }

  Future<void> _wait(int ms, int token) async {
    var left = ms;
    // Sleep in slices so a jump/stop doesn't have to wait out a long pause.
    while (left > 0 && _alive(token)) {
      final slice = left > 100 ? 100 : left;
      await Future<void>.delayed(Duration(milliseconds: slice));
      left -= slice;
    }
    await _checkpoint(token);
  }

  void _setStatus(NarratorStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_events.isClosed) _events.add(StatusEvent(s));
  }
}
