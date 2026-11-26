import 'dart:async';
import 'dart:math';

final _rng = Random.secure();

/// Random 16-hex-character identifier (collision-safe for local data).
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 8; i++) {
    b.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Collapses bursts of calls into one trailing call.
final class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Runs [action] now and cancels any pending call.
  void flush(void Function() action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  void dispose() => _timer?.cancel();
}
