import 'package:flutter_test/flutter_test.dart';

import '../tool/setup_android.dart';

const kts = '''
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.aloud.aloud"
    defaultConfig {
        applicationId = "dev.aloud.aloud"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }
}

flutter {
    source = "../.."
}
''';

const groovy = '''
android {
    defaultConfig {
        applicationId "dev.aloud.aloud"
        minSdkVersion flutter.minSdkVersion
    }
}
dependencies {
    implementation 'androidx.core:core:1.0.0'
}
''';

void main() {
  test('kotlin dsl: minSdk raised, dependency appended, idempotent', () {
    final once = patchGradle(kts, kotlinDsl: true);
    expect(once.contains('minSdk = maxOf(24, flutter.minSdkVersion)'), isTrue);
    expect(once.contains('implementation("org.apache.commons:commons-compress:1.27.1")'), isTrue);
    expect(patchGradle(once, kotlinDsl: true), once);
  });
  test('explicit low minSdk is raised', () {
    expect(patchGradle('android { defaultConfig { minSdk = 21 } }', kotlinDsl: true).contains('minSdk = 24'), isTrue);
    expect(patchGradle('android { defaultConfig { minSdk = 30 } }', kotlinDsl: true).contains('minSdk = 30'), isTrue);
  });
  test('groovy dsl inserts into an existing dependencies block', () {
    final out = patchGradle(groovy, kotlinDsl: false);
    expect(out.contains('Math.max(24, flutter.minSdkVersion)'), isTrue);
    expect(out.indexOf('commons-compress') < out.indexOf('androidx.core'), isTrue);
  });
  test('application id and template rendering', () {
    expect(readApplicationId(kts), 'dev.aloud.aloud');
    expect(readApplicationId(groovy), 'dev.aloud.aloud');
    expect(renderMainActivity('package {{PACKAGE}}\nclass X', 'a.b'), 'package a.b\nclass X');
  });
}
