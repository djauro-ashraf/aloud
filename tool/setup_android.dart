// Applies Aloud's Android customisations to the project that
// `flutter create` generated.
//
//   flutter create --org dev.aloud --project-name aloud --platforms=android .
//   dart tool/setup_android.dart
//
// It is idempotent: running it again changes nothing. It never touches your
// Gradle/AGP/Kotlin versions; it only
//   * raises minSdk to 24 (ML Kit, ONNX runtime),
//   * adds the commons-compress dependency (voice-model extraction),
//   * installs the manifest, MainActivity.kt and the notification icon.
import 'dart:io';

const minSdk = 24;
const _dependency = 'org.apache.commons:commons-compress:1.27.1';

/// Returns [source] with minSdk raised and the extraction dependency added.
String patchGradle(String source, {required bool kotlinDsl}) {
  var s = source;

  // minSdk
  final alreadyMax = s.contains('maxOf($minSdk') || s.contains('Math.max($minSdk');
  if (!alreadyMax) {
    if (kotlinDsl) {
      s = s.replaceFirstMapped(
        RegExp(r'minSdk\s*=\s*flutter\.minSdkVersion'),
        (_) => 'minSdk = maxOf($minSdk, flutter.minSdkVersion)',
      );
      s = s.replaceFirstMapped(RegExp(r'minSdk\s*=\s*(\d+)'), (m) {
        final v = int.parse(m[1]!);
        return 'minSdk = ${v < minSdk ? minSdk : v}';
      });
    } else {
      s = s.replaceFirstMapped(
        RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'),
        (_) => 'minSdkVersion Math.max($minSdk, flutter.minSdkVersion)',
      );
    }
  }

  // dependency
  if (!s.contains('commons-compress')) {
    final line = kotlinDsl ? '    implementation("$_dependency")' : "    implementation '$_dependency'";
    final block = RegExp(r'^dependencies\s*\{', multiLine: true);
    if (block.hasMatch(s)) {
      s = s.replaceFirstMapped(block, (m) => '${m[0]}\n$line');
    } else {
      s = '${s.trimRight()}\n\ndependencies {\n$line\n}\n';
    }
  }
  return s;
}

/// Reads `applicationId` from a Gradle file (Kotlin or Groovy DSL).
String? readApplicationId(String gradle) {
  final m = RegExp(r'''applicationId\s*=?\s*["']([^"']+)["']''').firstMatch(gradle);
  return m?.group(1);
}

String renderMainActivity(String template, String packageName) => template.replaceAll('{{PACKAGE}}', packageName);

void main(List<String> args) {
  final app = Directory('android/app');
  if (!app.existsSync()) {
    stderr.writeln('No android/app folder here. From the project root run:\n'
        '  flutter create --org dev.aloud --project-name aloud --platforms=android .');
    exit(1);
  }
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final gradleFile = kts.existsSync() ? kts : (groovy.existsSync() ? groovy : null);
  if (gradleFile == null) {
    stderr.writeln('Could not find android/app/build.gradle(.kts).');
    exit(1);
  }
  final gradle = gradleFile.readAsStringSync();
  final pkg = readApplicationId(gradle);
  if (pkg == null) {
    stderr.writeln('Could not read applicationId from ${gradleFile.path}.');
    exit(1);
  }

  gradleFile.writeAsStringSync(patchGradle(gradle, kotlinDsl: gradleFile.path.endsWith('.kts')));
  stdout.writeln('✓ ${gradleFile.path}: minSdk ≥ $minSdk, commons-compress added');

  // Replace the generated MainActivity with ours (in the applicationId package).
  final srcMain = Directory('android/app/src/main');
  for (final e in srcMain.listSync(recursive: true)) {
    if (e is File && RegExp(r'MainActivity\.(kt|java)$').hasMatch(e.path)) e.deleteSync();
  }
  final activityDir = Directory('android/app/src/main/kotlin/${pkg.replaceAll('.', '/')}')..createSync(recursive: true);
  final template = File('android_overrides/MainActivity.kt.template').readAsStringSync();
  File('${activityDir.path}/MainActivity.kt').writeAsStringSync(renderMainActivity(template, pkg));
  stdout.writeln('✓ MainActivity.kt ($pkg)');

  File('android_overrides/AndroidManifest.xml').copySync('android/app/src/main/AndroidManifest.xml');
  stdout.writeln('✓ AndroidManifest.xml');

  Directory('android/app/src/main/res/drawable').createSync(recursive: true);
  File('android_overrides/res/drawable/ic_stat_aloud.xml').copySync('android/app/src/main/res/drawable/ic_stat_aloud.xml');
  stdout.writeln('✓ notification icon');

  stdout.writeln('\nDone. Next: flutter pub get && flutter run');
}
