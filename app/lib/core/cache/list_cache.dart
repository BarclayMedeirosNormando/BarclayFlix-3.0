import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Guarda no aparelho o texto (JSON) das listas baixadas, para a próxima
/// abertura mostrar tudo na hora enquanto a atualização acontece ao fundo.
abstract interface class ListCache {
  /// Texto guardado em [key], ou null se não houver (ou estiver velho demais).
  Future<String?> read(String key);

  Future<void> write(String key, String text);
}

/// Implementação em arquivos dentro da pasta de dados do aplicativo.
///
/// Nunca lança exceção: qualquer falha de disco vira "sem cache".
class FileListCache implements ListCache {
  FileListCache({this.maxAge = const Duration(days: 14)});

  final Duration maxAge;
  Directory? _dir;

  Future<Directory?> _folder() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}list_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      return _dir = dir;
    } catch (_) {
      return null;
    }
  }

  File _file(Directory dir, String key) =>
      File('${dir.path}${Platform.pathSeparator}${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json');

  @override
  Future<String?> read(String key) async {
    try {
      final dir = await _folder();
      if (dir == null) return null;
      final file = _file(dir, key);
      if (!await file.exists()) return null;
      if (DateTime.now().difference(await file.lastModified()) > maxAge) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String text) async {
    try {
      final dir = await _folder();
      if (dir == null) return;
      final file = _file(dir, key);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Cache é opcional: sem disco, segue sem ele.
    }
  }
}
