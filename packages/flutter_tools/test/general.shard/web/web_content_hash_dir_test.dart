// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/web/web_content_hash_dir.dart';

import '../../src/common.dart';

/// Faithful port of how the runtime resolves the deferred-part URL: flutter.js
/// builds the entrypoint `<script src>` from `mainJsPath`, and dart2js then
/// resolves a (bare) part name relative to that script's directory
/// (`js_helper.dart` `_thisScriptBaseUrl`). Proves a moved entrypoint pulls its
/// parts from the same `<hash>/` with no compiler change.
String resolveDeferredPartUrl({
  required String documentBaseUri,
  required String mainJsPath,
  required String bareHunkName,
}) {
  final entrypointUrl = Uri.parse(documentBaseUri).resolve(mainJsPath).toString();
  final String base = entrypointUrl.substring(0, entrypointUrl.lastIndexOf('/') + 1);
  return base + Uri.encodeComponent(bareHunkName);
}

void main() {
  late FileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  List<File> writeProgramFiles(Directory dir, {String mainJs = '// app v1'}) {
    final File main = dir.childFile('main.dart.js')..writeAsStringSync(mainJs);
    final File part1 = dir.childFile('main.dart.js_1.part.js')..writeAsStringSync('// part 1');
    final File part2 = dir.childFile('main.dart.js_2.part.js')..writeAsStringSync('// part 2');
    return <File>[main, part1, part2];
  }

  group('computeWebBundleHash', () {
    test('is deterministic and independent of input ordering', () {
      final Directory dir = fileSystem.directory('/build')..createSync();
      final List<File> files = writeProgramFiles(dir);

      final String a = computeWebBundleHash(files);
      final String b = computeWebBundleHash(files.reversed);

      expect(a, hasLength(16));
      expect(a, b, reason: 'the per-file digests are sorted, so input order is irrelevant');
    });

    test('is order-independent when basenames collide (resolution variants)', () {
      // Resolution variants live in sibling directories but share a basename
      // (e.g. 2.0x/foo.png and 3.0x/foo.png both have basename foo.png). The
      // directory listing that surfaces them is unordered, so the hash must not
      // depend on which order they arrive in.
      final File lo = (fileSystem.directory('/2.0x')..createSync()).childFile('foo.png')
        ..writeAsStringSync('2x bytes');
      final File hi = (fileSystem.directory('/3.0x')..createSync()).childFile('foo.png')
        ..writeAsStringSync('3x bytes');

      expect(
        computeWebBundleHash(<File>[lo, hi]),
        computeWebBundleHash(<File>[hi, lo]),
        reason: 'same (basename, content) set must hash the same regardless of order',
      );
    });

    test('changes when any program byte changes', () {
      final Directory d1 = fileSystem.directory('/b1')..createSync();
      final Directory d2 = fileSystem.directory('/b2')..createSync();

      final String h1 = computeWebBundleHash(writeProgramFiles(d1));
      final String h2 = computeWebBundleHash(writeProgramFiles(d2, mainJs: '// app v2'));

      expect(h1, isNot(h2));
    });

    test('changes when a file is renamed but content is identical', () {
      final Directory d1 = fileSystem.directory('/c1')..createSync();
      final Directory d2 = fileSystem.directory('/c2')..createSync();
      final File a = d1.childFile('main.dart.js')..writeAsStringSync('same');
      final File b = d2.childFile('main.dart.js_1.part.js')..writeAsStringSync('same');

      expect(
        computeWebBundleHash(<File>[a]),
        isNot(computeWebBundleHash(<File>[b])),
        reason: 'the file name is mixed into the hash',
      );
    });
  });

  group('prefixEntrypointPaths', () {
    test('prefixes dart2js entrypoint path', () {
      final Map<String, Object?> result = prefixEntrypointPaths(<String, Object?>{
        'compileTarget': 'dart2js',
        'renderer': 'canvaskit',
        'mainJsPath': 'main.dart.js',
      }, 'abc123', const <String>['mainJsPath']);

      expect(result['mainJsPath'], 'abc123/main.dart.js');
      expect(result['renderer'], 'canvaskit', reason: 'unrelated keys are untouched');
    });

    test('prefixes all dart2wasm entrypoint paths', () {
      final Map<String, Object?> result = prefixEntrypointPaths(<String, Object?>{
        'compileTarget': 'dart2wasm',
        'mainWasmPath': 'main.dart.wasm',
        'jsSupportRuntimePath': 'main.dart.mjs',
      }, 'deadbeef', const <String>['mainWasmPath', 'jsSupportRuntimePath']);

      expect(result['mainWasmPath'], 'deadbeef/main.dart.wasm');
      expect(result['jsSupportRuntimePath'], 'deadbeef/main.dart.mjs');
    });

    test('does not mutate the input map', () {
      final input = <String, Object?>{'mainJsPath': 'main.dart.js'};
      prefixEntrypointPaths(input, 'xyz', const <String>['mainJsPath']);
      expect(input['mainJsPath'], 'main.dart.js');
    });

    test('ignores entries without a hashed key', () {
      final Map<String, Object?> result = prefixEntrypointPaths(<String, Object?>{
        'compileTarget': 'dart2js',
      }, 'abc', const <String>['mainJsPath']);
      expect(result.containsKey('mainJsPath'), isFalse);
    });
  });

  test('deferred part resolves under the hashed directory the entrypoint moved to', () {
    // mainJsPath as written by prefixEntrypointPaths.
    const hash = 'abc123def4567890';
    final mainJsPath = prefixEntrypointPaths(<String, Object?>{
      'mainJsPath': 'main.dart.js',
    }, hash, const <String>['mainJsPath'])['mainJsPath']! as String;

    final String partUrl = resolveDeferredPartUrl(
      documentBaseUri: 'https://example.com/',
      mainJsPath: mainJsPath,
      bareHunkName: 'main.dart.js_1.part.js',
    );

    expect(partUrl, 'https://example.com/$hash/main.dart.js_1.part.js');
  });
}
