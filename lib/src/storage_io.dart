import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Files under `<Application Support>/StringCast/<projectId>/`. Writes go to a temp file that is then
/// renamed over the target, so a crash never leaves a half-written bundle.
class FileStorage implements StringCastStorage {
  FileStorage(this.directory);

  final Directory directory;

  File _file(String name) => File('${directory.path}/$name');

  @override
  Future<String?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String name, String data) async {
    await directory.create(recursive: true);
    final tmp = _file('$name.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }
}

Future<StringCastStorage> createDefaultStorage(String projectId) async {
  final support = await getApplicationSupportDirectory();
  final safe = projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return FileStorage(Directory('${support.path}/StringCast/$safe'));
}
