import 'dart:async';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/vinyl_add_service.dart';
import 'album_tracks_screen.dart';

class DiscographyScreen extends StatefulWidget {
  const DiscographyScreen({super.key});

  @override
  State<DiscographyScreen> createState() => _DiscographyScreenState();
}

class _DiscographyScreenState extends State<DiscographyScreen> {
  final artistCtrl = TextEditingController();

  Timer? _debounce;
  bool searchingArtists = false;
  List<ArtistHit> artistResults = [];

  bool loadingAlbums = false;
  String? msg;

  ArtistHit? pickedArtist;
  ArtistInfo? artistInfo;
  List<AlbumItem> albums = [];

  @override
  void dispose() {
    _debounce?.cancel();
    artistCtrl.dispose();
    super.dispose();
  }

  void _onArtistTextChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        artistResults = [];
        searchingArtists = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => searchingArtists = true);
      final hits = await DiscographyService.searchArtists(q);
      if (!mounted) return;
      setState(() {
        artistResults = hits;
        searchingArtists = false;
      });
    });
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();

    setState(() {
      pickedArtist = a;
      artistCtrl.text = a.name;
      artistResults = [];
      albums = [];
      msg = null;
      artistInfo = null;
      loadingAlbums = true;
    });

    final info =
        await DiscographyService.getArtistInfoById(a.id, artistName: a.name);
    final list = await DiscographyService.getDiscographyByArtistId(a.id);

    if (!mounted) return;

    setState(() {
      artistInfo = info;
      albums = list;
      loadingAlbums = false;
      msg = list.isEmpty ? 'No encontré álbumes.' : null;
    });
  }

  Future<void> _addAlbumToCollection(AlbumItem al, {required bool favorite}) async {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();
    if (artistName.isEmpty) return;

    final prepared = await VinylAddService.prepare(
      artist: artistName,
      album: al.title,
      artistId: pickedArtist?.id,
    );

    final res = await VinylAddService.addPrepared(prepared, favorite: favorite);
    await BackupService.autoSaveIfEnabled();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    setState(() {});
  }

  Future<void> _toggleFavoriteExisting({required int id, required bool next}) async {
    await VinylDb.instance.setFavorite(id: id, favorite: next);
    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleWishlist({
    required String artistName,
    required AlbumItem al,
    required bool isInWishlist,
  }) async {
    if (!isInWishlist) {
      await VinylDb.instance.addToWishlist(
        artista: artistName,
        album: al.title,
        year: al.year,
        cover250: al.cover250,
        cover500: al.cover500,
        artistId: pickedArtist?.id,
      );
    } else {
      await VinylDb.instance.removeWishlistExact(
        artista: artistName,
        album: al.title,
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Discografías')),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: artistCtrl,
              onChanged: _onArtistTextChanged,
              decoration: const InputDecoration(
                labelText: 'Busca banda (escribe letras)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            if (searchingArtists) const LinearProgressIndicator(),

            if (artistResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: artistResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = artistResults[i];
                    return ListTile(
                      dense: true,
                      title: Text(a.name),
                      subtitle: Text((a.country ?? '').trim().isEmpty ? '' : 'País: ${a.country}'),
                      onTap: () => _pickArtist(a),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),

            Expanded(
              child: loadingAlbums
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: albums.length,
                      itemBuilder: (context, i) {
                        final al = albums[i];
                        final year = al.year ?? '—';

                        final f = Future.wait([
                          VinylDb.instance.findByExact(artista: artistName, album: al.title),
                          VinylDb.instance.findWishlistByExact(artista: artistName, album: al.title),
                        ]);

                        return Card(
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                al.cover250,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.album),
                              ),
                            ),
                            title: Text(al.title),
                            subtitle: Text('Año: $year'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AlbumTracksScreen(
                                    album: al,
                                    artistName: artistName,
                                  ),
                                ),
                              );
                            },

                            trailing: FutureBuilder<List<dynamic>>(
                              future: f,
                              builder: (context, snap) {
                                final list = snap.data;
                                final rowVinyl = (list != null && list.isNotEmpty)
                                    ? list[0] as Map<String, dynamic>?
                                    : null;
                                final rowWish = (list != null && list.length > 1)
                                    ? list[1] as Map<String, dynamic>?
                                    : null;

                                final exists = rowVinyl != null;
                                final fav = exists ? ((rowVinyl!['favorite'] ?? 0) == 1) : false;
                                final idVinyl = exists ? (rowVinyl!['id'] as int) : null;

                                final inWish = rowWish != null;

                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // ➕ Agregar LP (solo si NO existe)
                                    IconButton(
                                      tooltip: exists ? 'Ya está en tu lista' : 'Agregar LP',
                                      icon: Icon(
                                        Icons.add_circle_outline,
                                        color: exists ? Colors.black26 : null,
                                      ),
                                      onPressed: exists
                                          ? null
                                          : () => _addAlbumToCollection(al, favorite: false),
                                    ),

                                    // ⭐ Favorito (si no existe: agrega como favorito)
                                    IconButton(
                                      tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                                      icon: Icon(fav ? Icons.star : Icons.star_border),
                                      onPressed: () async {
                                        if (!exists) {
                                          await _addAlbumToCollection(al, favorite: true);
                                          return;
                                        }
                                        await _toggleFavoriteExisting(id: idVinyl!, next: !fav);
                                      },
                                    ),

                                    // 🛒 Wishlist: ✅ GRIS si ya está en deseos
                                    IconButton(
                                      tooltip: inWish ? 'Quitar de lista deseos' : 'Agregar a lista deseos',
                                      icon: Icon(
                                        inWish ? Icons.shopping_cart : Icons.shopping_cart_outlined,
                                        color: inWish ? Colors.grey : null, // ✅ gris
                                      ),
                                      onPressed: () => _toggleWishlist(
                                        artistName: artistName,
                                        al: al,
                                        isInWishlist: inWish,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
