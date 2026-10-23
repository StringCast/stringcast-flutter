import 'storage_memory.dart';
import 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart' as platform;

/// Where the SDK persists the last-known release. Every method may throw; the SDK treats failures
/// as "no cache".
///
/// The default is files under `Application Support/StringCast/<projectId>/` on Android, iOS and
/// desktop, and `localStorage` (`stringcast:<projectId>:…`) on the web. Pass [MemoryStorage] to
/// disable persistence, or your own implementation.
abstract class StringCastStorage {
  Future<String?> read(String name);

  /// Must replace [name] atomically (readers never see a half-written value).
  Future<void> write(String name, String data);
  Future<void> delete(String name);
}

/// The platform default storage for [projectId], or an in-memory one when that is unavailable.
Future<StringCastStorage> defaultStorage(String projectId) async {
  try {
    return await platform.createDefaultStorage(projectId);
  } catch (_) {
    return MemoryStorage();
  }
}
