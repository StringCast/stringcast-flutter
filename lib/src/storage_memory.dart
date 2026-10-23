import 'storage.dart';

/// Keeps the cache in memory only (nothing survives a restart). Handy for tests.
class MemoryStorage implements StringCastStorage {
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String name) async => entries[name];

  @override
  Future<void> write(String name, String data) async => entries[name] = data;

  @override
  Future<void> delete(String name) async => entries.remove(name);
}
