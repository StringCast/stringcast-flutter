/// StringCast over-the-air localization for Flutter.
///
/// See https://console.stringcast.app/docs/flutter
library;

export 'src/config.dart' show StringCastConfig, defaultBaseUrl, sdkVersion;
export 'src/format.dart' show interpolate;
export 'src/language.dart' show matchLanguage, normalizeTag, resolveLanguage;
export 'src/plural_rules.dart' show pluralCategory, selectPlural;
export 'src/storage.dart' show StringCastStorage;
export 'src/storage_memory.dart' show MemoryStorage;
export 'src/stringcast.dart'
    show ClientInfo, StringCast, StringCastInherited, StringCastUpdate, StringCastUpdateReason, UploadResult, localeFromTag;
export 'src/widgets.dart' show StringCastBuilder, StringCastLocalizationsDelegate, StringCastScope, StringCastText;
