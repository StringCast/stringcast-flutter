# StringCast Flutter example

A small app that shows over-the-air strings, plurals, arrays, a language picker and a refresh button.

By default it talks to the local backend (`cd backend && npm run seed && npm run dev`) with the demo project
`p_demo` / `pk_demo_local`. The Android emulator reaches it at `http://10.0.2.2:8787`, everything else at
`http://localhost:8787`.

```sh
flutter run                       # local backend
flutter run -d chrome             # web
flutter run \
  --dart-define=STRINGCAST_PROJECT_ID=p_… \
  --dart-define=STRINGCAST_SDK_KEY=pk_… \
  --dart-define=STRINGCAST_BASE_URL=https://console.stringcast.app
```

Change a value in the portal, publish, and tap **Refresh translations**: the screen updates without a restart.
`assets/stringcast/` holds the offline fallback used before the first release is downloaded.
