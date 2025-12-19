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
  ArtistHit? pickedArtist;
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

    _debounce = Timer(const Duration(milliseconds: 400), () async {
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
      loadingAlbums = true;
    });

    final list = await DiscographyService.getDiscographyByArtistId(a.id);

    if (!mounted) return;

    setState(() {
      albums = list;
      loadingAlbums = false;
    });
  }

  Future<void> _addAlbum(AlbumItem al, {required bool favorite}) async {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();
    final prepared = await VinylAddService.prepare(
      artist: artistName,
      album: al.title,
      artistId: pickedArtist?.id,
    );

    final res = await VinylAddService.addPrepared(prepared, favorite: favorite);
    await BackupService.autoSaveIfEnabled();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(res.message)));
    setState(() {});
  }

  Future<void> _toggleFavorite(int id, bool next) async {
    await VinylDb.instance.setFavorite(id: id, favorite: next);
    await BackupService.autoSaveIfEnabled();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleWishlist(
    String artist,
    AlbumItem al,
    bool isInWishlist,
  ) async {
    if (!isInWishlist) {
      await VinylDb.instance.addToWishlist(
        artista: artist,
        album: al.title,
        year: al.year,
        cover250: al.cover250,
        cover500: al.cover500,
        artistId: pickedArtist?.id,
      );
    } else {
      await VinylDb.instance.removeWishlistExact(
        artista: artist,
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
                labelText: 'Buscar artista',
                border: OutlineInputBorder(),
              ),
            ),

            if (searchingArtists) const LinearProgressIndicator(),

            if (artistResults.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                itemCount: artistResults.length,
                itemBuilder: (_, i) {
                  final a = artistResults[i];
                  return ListTile(
                    title: Text(a.name),
                    onTap: () => _pickArtist(a),
                  );
                },
              ),

            const SizedBox(height: 10),

            Expanded(
              child: loadingAlbums
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: albums.length,
                      itemBuilder: (_, i) {
                        final al = albums[i];
                        final year = al.year ?? '—';

                        return FutureBuilder<List<dynamic>>(
                          future: Future.wait([
                            VinylDb.instance.findByExact(
                              artista: artistName,
                              album: al.title,
                            ),
                            VinylDb.instance.findWishlistByExact(
                              artista: artistName,
                              album: al.title,
                            ),
                          ]),
                          builder: (_, snap) {
                            final vinyl = snap.data?[0] as Map<String, dynamic>?;
                            final wish = snap.data?[1] as Map<String, dynamic>?;

                            final exists = vinyl != null;
                            final fav = exists && (vinyl['favorite'] ?? 0) == 1;
                            final id = exists ? vinyl['id'] as int : null;
                            final inWish = wish != null;

                            return Card(
                              child: ListTile(
                                leading: Image.network(
                                  al.cover250,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.album),
                                ),

                                title: Text(al.title),
                                subtitle: Text('Año: $year'),

                                // 👇 ICONOS EN COLUMNA AL BORDE DERECHO
                                trailing: SizedBox(
                                  width: 44,
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // ➕ AGREGAR
                                      IconButton(
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: exists
                                              ? Colors.black26
                                              : null,
                                        ),
                                        tooltip: 'Agregar LP',
                                        onPressed: exists
                                            ? null
                                            : () =>
                                                _addAlbum(al, favorite: false),
                                      ),

                                      // ⭐ FAVORITOS
                                      IconButton(
                                        icon: Icon(
                                          fav
                                              ? Icons.star
                                              : Icons.star_border,
                                        ),
                                        tooltip: 'Favorito',
                                        onPressed: () {
                                          if (!exists) {
                                            _addAlbum(al, favorite: true);
                                          } else {
                                            _toggleFavorite(id!, !fav);
                                          }
                                        },
                                      ),

                                      // 🛒 LISTA DE DESEOS
                                      IconButton(
                                        icon: Icon(
                                          inWish
                                              ? Icons.shopping_cart
                                              : Icons.shopping_cart_outlined,
                                          color:
                                              inWish ? Colors.grey : null,
                                        ),
                                        tooltip: 'Lista deseos',
                                        onPressed: () => _toggleWishlist(
                                          artistName,
                                          al,
                                          inWish,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

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
                              ),
                            );
                          },
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
