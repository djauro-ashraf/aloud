/// Small, dependency-free, web-safe string hashing used for cache keys and
/// content fingerprints. Not cryptographic.
abstract final class Hashing {
  /// 32-bit FNV-1a with an optional [seed] offset.
  static int fnv1a32(String input, {int seed = 0x811C9DC5}) {
    var h = seed & 0xFFFFFFFF;
    for (final unit in input.codeUnits) {
      h ^= unit & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= (unit >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// 64-bit-wide (two 32-bit lanes) hex digest: 16 lowercase hex characters.
  static String hex64(String input) {
    final a = fnv1a32(input);
    final b = fnv1a32(input, seed: 0x9747B28C);
    return a.toRadixString(16).padLeft(8, '0') + b.toRadixString(16).padLeft(8, '0');
  }
}
