import 'dart:convert';
import 'package:http/http.dart' as http;

class AlbumSuggest {
  final String title;
  final String? year;

  AlbumSuggest({required this.title, this.year});

  factory AlbumSuggest.fromMap(Map<String, dynamic> m) {
    return AlbumSuggest(
      title: (m['title'] ?? '').toString(),
      year: (m['year'] ?? '').toString().trim().isEmpty ? null : (m['year'] ?? '').toString(),
    );
  }
}

class MetadataService {
  static const _musicbrainzBase = 'https://musicbrainz.org/ws/2';

  static Map<String, String> get _headers => {
        'User-Agent': 'GaboLP/1.0 ( https://example.com )',
        'Accept': 'application/json',
      };

  static String _q(String s) => Uri.encodeQueryComponent(s);

  /// Busca sugerencias de álbum dentro del contexto de un artista.
  /// (Este método se usa desde HomeScreen -> buscador)
  ///
  /// ✅ Firma POSICIONAL para que calce con:
  ///   MetadataService.searchAlbumsForArtist(artistName, q);
  static Future<List<Map<String, dynamic>>> searchAlbumsForArtist(String artistName, String albumQuery) async {
    final artist = artistName.trim();
    final q = albumQuery.trim();
    if (artist.isEmpty || q.isEmpty) return [];

    // MusicBrainz: buscar release-group con artista + parte del título
    // Ej: release-group?query=artist:"Metallica" AND releasegroup:"Master"
    final url =
        '$_musicbrainzBase/release-group/?query=artist:"${_q(artist)}"%20AND%20releasegroup:"${_q(q)}"&fmt=json&limit=15';

    final res = await http.get(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final groups = (data['release-groups'] as List?) ?? [];

    final out = <Map<String, dynamic>>[];
    for (final g in groups) {
      if (g is! Map<String, dynamic>) continue;
      final title = (g['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;

      // first-release-date -> año
      String? year;
      final frd = (g['first-release-date'] ?? '').toString().trim();
      if (frd.length >= 4) {
        year = frd.substring(0, 4);
      }

      out.add({
        'title': title,
        'year': year ?? '',
      });
    }

    return out;
  }

  /// Si alguna parte de la app usa AlbumSuggest, lo dejamos disponible.
  /// (No es requerido por el fix, solo compatibilidad)
  static Future<List<AlbumSuggest>> searchAlbumsForArtistSuggest({
    required String artistName,
    required String albumQuery,
  }) async {
    final raw = await searchAlbumsForArtist(artistName, albumQuery);
    return raw.map((m) => AlbumSuggest.fromMap(m)).toList();
  }
}
