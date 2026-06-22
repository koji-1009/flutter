// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../base/file_system.dart';

/// Reserved directory under `build/web/`. Wiped and recreated on every build, so
/// it must not hold any user content.
const String kContentHashDirRoot = '_flutter';

/// Build-dir handoff: the release bundle records the content-hash directories
/// here for the templated-files target to point entrypoints and `assetBase` at.
const String kWebContentHashFile = 'web_content_hash.json';

/// A deterministic, order-independent content hash over [programFiles] (their
/// base names and contents); the first 16 hex characters of a SHA-256 digest.
String computeWebBundleHash(Iterable<File> programFiles) {
  // Sorting by basename alone is not enough: resolution variants (2.0x/foo.png,
  // 3.0x/foo.png) share a basename and the directory listing is unordered, so a
  // basename-only sort would hash the same bundle differently across machines.
  final entries = <Uint8List>[];
  for (final file in programFiles) {
    final builder = BytesBuilder(copy: false);
    builder
      // NUL delimits name from bytes (a basename can't contain NUL).
      ..add(utf8.encode(file.basename))
      ..addByte(0)
      ..add(crypto.sha256.convert(file.readAsBytesSync()).bytes);
    entries.add(builder.takeBytes());
  }
  // Lexicographic byte order over the per-file digests gives a total order.
  entries.sort((a, b) {
    final int shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      if (a[i] != b[i]) {
        return a[i] - b[i];
      }
    }
    return a.length - b.length;
  });

  final concatenated = <int>[for (final Uint8List entry in entries) ...entry];
  return crypto.sha256.convert(concatenated).toString().substring(0, 16);
}

/// Returns a copy of a `buildConfig` `builds` entry with each [pathKeys] value
/// prefixed with `$dir/`. [pathKeys] is the owning target's document-relative
/// path keys.
Map<String, Object?> prefixEntrypointPaths(
  Map<String, Object?> build,
  String dir,
  Iterable<String> pathKeys,
) {
  final copy = Map<String, Object?>.of(build);
  for (final key in pathKeys) {
    final Object? value = copy[key];
    if (value is String) {
      copy[key] = '$dir/$value';
    }
  }
  return copy;
}
