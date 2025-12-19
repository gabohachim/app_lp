import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/vinyl_db.dart';
import 'metadata_service.dart';
import 'discography_service.dart';

class AddVinylResult {
  final bool ok;
  final String message;

  AddVinylResult({required this.ok, required this.message});
}

class PreparedVinylAdd {
  final String artist;
  final String album;

  final String? year;
  final String? genre;
  final String? country;
  final String? bioShort;

  final String? releaseGroupId;

  final List<CoverCandidate> coverCandidates;

  CoverCandidate? selectedCover;

  PreparedVinylAdd({
    required this.artist,
    required this.album,
    required this.coverCandidates,
    this.selectedCover,
    this.year,
    this.genre,
    this.country,
    this.bioShort,
    this.releaseGroupId,
  });

  String? get selectedCover500 => selectedCover?.coverUrl500;
  String? get selectedCover250 => selectedCover?.coverUrl250;
}

class VinylAddService {
  static Future<PreparedVinylAdd> prepare({
    required String artist,
    required String album,
    String? artistId,
  }) async {
    final a = artist.trim();
    final al = album.trim();

    final candidatesAll =
        await MetadataService.fetchCoverCandidates(artist: a, album: al);
    final candidates = candidatesAll.take(5).toList();

    final meta = await MetadataService.fetchAutoMetadataWithCandidates(
      artist: a,
      album: al,
      candidates: candidates,
    );

    ArtistInfo info;
    if (artistId != null && artistId.trim().isNotEmpty) {
      info = await DiscographyService.getArtistInfoById(artistId.trim(),
          artistName: a);
    } else {
      info = await DiscographyService.getArtistInfo(a);
    }

    final country = (info.country ?? '').trim();
    final bio = (info.bio ?? '').trim();
    final bioShort =
        bio.isEmpty ? null : (bio.length > 220 ? '${bio.substring(0, 220)}…' : bio);

    return PreparedVinylAdd(
      artist: a,
      album: al,
      coverCandidates: candidates,
      selectedCover: candidates.isNotEmpty ? candidates.first : null,
      year: (meta.year ?? '').trim().isEmpty ? null : meta.year!.trim(),
      genre: (meta.genre ?? '').trim().isEmpty ? null : meta.genre!.trim(),
      country: country.isEmpty ? null : country,
      bioShort: bioShort,
      releaseGroupId: (meta.releaseGroupId ?? '').trim().isEmpty
          ? null
          : meta.releaseGroupId!.trim(),
    );
  }

  /// ✅ Ahora acepta favorite=true/false
  static Future<AddVinylResult> addPrepared(
    PreparedVinylAdd prepared, {
    String? overrideYear,
    bool favorite = false,
  }) async {
    final artist = prepared.artist.trim();
    final album = prepared.album.trim();
    if (artist.isEmpty || album.isEmpty) {
      return AddVinylResult(ok: false, message: 'Artista y Álbum son obligatorios.');
    }

    String? coverPath;
    final coverUrl = (prepared.selectedCover500 ?? '').trim();
    if (coverUrl.isNotEmpty) {
      coverPath = await _downloadCoverToLocal(coverUrl);
    }

    final y = (overrideYear ?? prepared.year ?? '').trim();
    try {
      await VinylDb.instance.insertVinyl(
        artista: artist,
        album: album,
        year: y.isEmpty ? null : y,
        genre: prepared.genre,
        country: prepared.country,
        artistBio: prepared.bioShort,
        coverPath: coverPath,
        mbid: prepared.releaseGroupId,
        favorite: favorite,
      );
      return AddVinylResult(ok: true, message: favorite ? 'Agregado a favoritos ⭐' : 'Vinilo agregado ✅');
    } catch (_) {
      return AddVinylResult(ok: false, message: 'Ese vinilo ya existe (Artista + Álbum).');
    }
  }

  static Future<String?> _downloadCoverToLocal(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return null;

      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      if (!await coversDir.exists()) await coversDir.create(recursive: true);

      final ct = res.headers['content-type'] ?? '';
      final ext = ct.contains('png') ? 'png' : 'jpg';
      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final file = File(p.join(coversDir.path, filename));
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
