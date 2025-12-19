import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class VinylDb {
  VinylDb._();
  static final instance = VinylDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, 'gabolp.db');

    return openDatabase(
      path,
      version: 5, // ✅ subimos versión por country
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE vinyls(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero INTEGER NOT NULL,
            artista TEXT NOT NULL,
            album TEXT NOT NULL,
            year TEXT,
            genre TEXT,
            country TEXT,
            artistBio TEXT,
            coverPath TEXT,
            mbid TEXT
          );
        ''');
        await d.execute('CREATE INDEX idx_artist ON vinyls(artista);');
        await d.execute('CREATE INDEX idx_album ON vinyls(album);');
      },
      onUpgrade: (d, oldV, newV) async {
        // migraciones sin perder datos
        if (oldV < 3) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN genre TEXT;');
        }
        if (oldV < 4) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN artistBio TEXT;');
        }
        if (oldV < 5) {
          await d.execute('ALTER TABLE vinyls ADD COLUMN country TEXT;');
        }
      },
    );
  }

  Future<int> getCount() async {
    final d = await db;
    final r = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM vinyls'));
    return r ?? 0;
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final d = await db;
    return d.query('vinyls', orderBy: 'numero ASC');
  }

  Future<List<Map<String, dynamic>>> search({
    required String artista,
    required String album,
  }) async {
    final d = await db;
    final a = artista.trim();
    final al = album.trim();

    if (a.isNotEmpty && al.isNotEmpty) {
      return d.query(
        'vinyls',
        where: 'LOWER(artista) LIKE ? AND LOWER(album) LIKE ?',
        whereArgs: ['%${a.toLowerCase()}%', '%${al.toLowerCase()}%'],
        orderBy: 'numero ASC',
      );
    }
    if (a.isNotEmpty) {
      return d.query(
        'vinyls',
        where: 'LOWER(artista) LIKE ?',
        whereArgs: ['%${a.toLowerCase()}%'],
        orderBy: 'numero ASC',
      );
    }
    return d.query(
      'vinyls',
      where: 'LOWER(album) LIKE ?',
      whereArgs: ['%${al.toLowerCase()}%'],
      orderBy: 'numero ASC',
    );
  }

  Future<bool> existsExact({required String artista, required String album}) async {
    final d = await db;
    final a = artista.trim().toLowerCase();
    final al = album.trim().toLowerCase();
    final rows = await d.query(
      'vinyls',
      columns: ['id'],
      where: 'LOWER(artista)=? AND LOWER(album)=?',
      whereArgs: [a, al],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> _nextNumero() async {
    final d = await db;
    final r = await d.rawQuery('SELECT MAX(numero) as m FROM vinyls');
    final m = (r.first['m'] as int?) ?? 0;
    return m + 1;
  }

  Future<void> insertVinyl({
    required String artista,
    required String album,
    String? year,
    String? genre,
    String? country,
    String? artistBio,
    String? coverPath,
    String? mbid,
  }) async {
    final d = await db;

    final exists = await existsExact(artista: artista, album: album);
    if (exists) throw Exception('Duplicado');

    final numero = await _nextNumero();

    await d.insert(
      'vinyls',
      {
        'numero': numero,
        'artista': artista.trim(),
        'album': album.trim(),
        'year': year?.trim(),
        'genre': genre?.trim(),
        'country': country?.trim(),
        'artistBio': artistBio?.trim(),
        'coverPath': coverPath?.trim(),
        'mbid': mbid?.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  

  /// Borra toda la tabla (para restaurar respaldos).
  Future<void> deleteAll() async {
    final d = await db;
    await d.delete('vinyls');
  }

  /// Inserta un vinilo usando un map (se usa para restaurar respaldos).
  Future<void> insertFromMap(Map<String, dynamic> v) async {
    final d = await db;
    await d.insert(
      'vinyls',
      {
        'numero': v['numero'],
        'artista': (v['artista'] ?? '').toString().trim(),
        'album': (v['album'] ?? '').toString().trim(),
        'year': v['year']?.toString().trim(),
        'genre': v['genre']?.toString().trim(),
        'country': v['country']?.toString().trim(),
        'artistBio': v['artistBio']?.toString().trim(),
        'coverPath': v['coverPath']?.toString().trim(),
        'mbid': v['mbid']?.toString().trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Reemplaza completamente la lista por la de un respaldo.
  Future<void> replaceAll(List<Map<String, dynamic>> vinyls) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('vinyls');
      for (final v in vinyls) {
        await txn.insert(
          'vinyls',
          {
            'numero': v['numero'],
            'artista': (v['artista'] ?? '').toString().trim(),
            'album': (v['album'] ?? '').toString().trim(),
            'year': v['year']?.toString().trim(),
            'genre': v['genre']?.toString().trim(),
            'country': v['country']?.toString().trim(),
            'artistBio': v['artistBio']?.toString().trim(),
            'coverPath': v['coverPath']?.toString().trim(),
            'mbid': v['mbid']?.toString().trim(),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }
Future<void> deleteById(int id) async {
    final d = await db;
    await d.delete('vinyls', where: 'id=?', whereArgs: [id]);
  }
}
