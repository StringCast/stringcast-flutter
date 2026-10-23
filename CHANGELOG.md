## 0.1.0

- First release: over-the-air strings, plurals (CLDR rules) and string arrays from StringCast releases.
- `StringCast.init` / `StringCast.instance` with `t`, `plural`, `array`; `StringCastScope` + `StringCast.of(context)`,
  `StringCastText`, `StringCastBuilder` and `StringCastLocalizationsDelegate` rebuild widgets on updates.
- Cached release loaded during `init`; background manifest checks with `If-None-Match`, SHA-256 bundle
  verification, atomic cache replacement, lazy languages, refresh on resume.
- Offline fallback from bundled `<lang>.json` or ARB assets (ICU plurals converted).
- Language resolution per the StringCast contract (§6.4), with override and app-locale support.
- Draft mode (debug builds): missing-key reports and a once-per-version upload of the bundled strings.
- Check-in headers (platform, app ID, app version, SDK version, language). No personal data.
