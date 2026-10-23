import 'package:web/web.dart' as web;

import 'storage.dart';

/// `window.localStorage`, keys namespaced `stringcast:<projectId>:<name>` (same layout as the web SDK).
class LocalStorageStorage implements StringCastStorage {
  LocalStorageStorage(this.projectId);

  final String projectId;

  String _key(String name) => 'stringcast:$projectId:$name';

  @override
  Future<String?> read(String name) async => web.window.localStorage.getItem(_key(name));

  @override
  Future<void> write(String name, String data) async => web.window.localStorage.setItem(_key(name), data);

  @override
  Future<void> delete(String name) async => web.window.localStorage.removeItem(_key(name));
}

Future<StringCastStorage> createDefaultStorage(String projectId) async {
  // Throws in Safari private mode / when storage is disabled; the caller falls back to memory.
  const probe = 'stringcast:__probe__';
  web.window.localStorage.setItem(probe, '1');
  web.window.localStorage.removeItem(probe);
  return LocalStorageStorage(projectId);
}
