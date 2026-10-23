import 'format.dart';

/// One language entry of a [Manifest].
class ManifestLanguage {
  const ManifestLanguage({required this.code, required this.url, this.hash, this.keyCount});

  final String code;

  /// Absolute bundle URL (CDN in production).
  final String url;

  /// SRI-style `sha256-<base64>` over the exact bundle bytes.
  final String? hash;
  final int? keyCount;

  Map<String, Object?> toJson() => {'code': code, 'url': url, 'hash': hash, 'keyCount': keyCount};
}

/// `GET /v1/sdk/{projectId}/manifest` (contract §4.2).
class Manifest {
  const Manifest({
    required this.projectId,
    required this.version,
    required this.baseLanguage,
    required this.languages,
    this.publishedAt,
  });

  final String projectId;

  /// Release version; 0 = nothing published yet.
  final int version;
  final String? publishedAt;
  final String baseLanguage;
  final List<ManifestLanguage> languages;

  List<String> get codes => [for (final l in languages) l.code];

  ManifestLanguage? entry(String code) {
    for (final l in languages) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Parses a decoded manifest; throws [FormatException] when it is malformed.
  factory Manifest.fromJson(Object? json) {
    if (json is! Map || json['version'] is! int || json['languages'] is! List || json['baseLanguage'] is! String) {
      throw const FormatException('manifest is malformed');
    }
    return Manifest(
      projectId: '${json['projectId'] ?? ''}',
      version: json['version'] as int,
      publishedAt: json['publishedAt'] as String?,
      baseLanguage: json['baseLanguage'] as String,
      languages: [
        for (final l in json['languages'] as List)
          if (l is Map && l['code'] is String && l['url'] is String)
            ManifestLanguage(
              code: l['code'] as String,
              url: l['url'] as String,
              hash: l['hash'] is String ? l['hash'] as String : null,
              keyCount: l['keyCount'] is int ? l['keyCount'] as int : null,
            ),
      ],
    );
  }

  Map<String, Object?> toJson() => {
        'projectId': projectId,
        'version': version,
        'publishedAt': publishedAt,
        'baseLanguage': baseLanguage,
        'languages': [for (final l in languages) l.toJson()],
      };
}

/// A release bundle (contract §3): every published value of one language.
class StringBundle {
  const StringBundle({required this.version, required this.language, required this.strings, this.publishedAt});

  final int version;
  final String language;
  final String? publishedAt;
  final Map<String, Value> strings;

  /// Keeps only valid §2 values. Throws [FormatException] when `strings` is missing.
  factory StringBundle.fromJson(Object? json, {required int version, required String language}) {
    if (json is! Map || json['strings'] is! Map) throw const FormatException('bundle is malformed');
    return StringBundle(
      version: version,
      language: language,
      publishedAt: json['publishedAt'] is String ? json['publishedAt'] as String : null,
      strings: parseStrings(json['strings'] as Map),
    );
  }

  Map<String, Object?> toJson() => {'version': version, 'language': language, 'publishedAt': publishedAt, 'strings': strings};
}

/// Valid §2 values of a decoded `{key: value}` object; anything else is dropped.
Map<String, Value> parseStrings(Map<Object?, Object?> raw) {
  final out = <String, Value>{};
  raw.forEach((k, v) {
    final value = parseValue(v);
    if (k is String && value != null) out[k] = value;
  });
  return out;
}
