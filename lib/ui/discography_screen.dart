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

  // Cache local: estado inmediato de iconos
  final Map<String, bool> _exists = {};
  final Map<String, bool> _fav = {};
  final Map<String, int?> _vinylId = {};
  final Map<String, bool> _wish = {};
  final Map<String, bool> _busy = {};

  String _k(String artist, String album) => '$artist||$album';

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

      // limpia caches al cambiar artista
      _exists.clear();
      _fav.clear();
      _vinylId.clear();
      _wish.clear();
      _busy.clear();
    });

    final list = await DiscographyService.getDiscographyByArtistId(a.id);

    if (!mounted) return;

    setState(() {
      albums = list;
      loadingAlbums = false;
    });
  }

  Future<void> _hydrateIfNeeded(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_exists.containsKey(key) || _busy[key] == true) return;

    _busy[key] = true;
    try {
      final r = await Future.wait([
        VinylDb.instance.findByExact(artista: artistName, album: al.title),
        VinylDb.instance.findWishlistByExact(artista: artistName, album: al.title),
      ]);

      final vinyl = r[0] as Map<String, dynamic>?;
      final wish = r[1] as Map<String, dynamic>?;

      _exists[key] = vinyl != null;
      _vinylId[key] = vinyl?['id'] as int?;
      _fav[key] = vinyl != null ? ((vinyl['favorite'] ?? 0) == 1) : false;
      _wish[key] = wish != null;
    } finally {
      _busy[key] = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _addToListOptimistic(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    // ✅ Optimista
    setState(() {
      _busy[key] = true;
      _exists[key] = true;
      _fav[key] = _fav[key] == true;
      _wish[key] = false; // si lo agrego a lista, sale de wishlist
    });

    try {
      await VinylDb.instance.removeWishlistExact(artista: artistName, album: al.title);

      final prepared = await VinylAddService.prepare(
        artist: artistName,
        album: al.title,
        artistId: pickedArtist?.id,
      );

      final res = await VinylAddService.addPrepared(prepared, favorite: false);
      await BackupService.autoSaveIfEnabled();

      if (!mounted) return;

      if (!res.ok) {
        setState(() {
          _exists.remove(key);
          _vinylId.remove(key);
        });
      } else {
        final row = await VinylDb.instance.findByExact(artista: artistName, album: al.title);
        if (!mounted) return;
        setState(() {
          _vinylId[key] = row?['id'] as int?;
          _exists[key] = row != null;
          _fav[key] = row != null ? ((row['favorite'] ?? 0) == 1) : (_fav[key] == true);
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exists.remove(key);
        _vinylId.remove(key);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error guardando. Intenta de nuevo.')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _toggleFavoriteOptimistic(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    if (!exists) {
      // ✅ Regla: solo se puede favorito si ya está agregado
      return;
    }

    final id = _vinylId[key];
    if (id == null) {
      await _hydrateIfNeeded(artistName, al);
      return;
    }

    final currentFav = _fav[key] == true;

    setState(() {
      _busy[key] = true;
      _fav[key] = !currentFav;
    });

    try {
      await VinylDb.instance.setFavorite(id: id, favorite: !currentFav);
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      setState(() => _fav[key] = currentFav);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error actualizando favorito.')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  Future<void> _addWishlistOptimistic(String artistName, AlbumItem al) async {
    final key = _k(artistName, al.title);
    if (_busy[key] == true) return;

    final exists = _exists[key] == true;
    final inWish = _wish[key] == true;

    if (exists || inWish) return;

    setState(() {
      _busy[key] = true;
      _wish[key] = true;
    });

    try {
      await VinylDb.instance.addToWishlist(
        artista: artistName,
        album: al.title,
        year: al.year,
        cover250: al.cover250,
        cover500: al.cover500,
        artistId: pickedArtist?.id,
      );
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      setState(() => _wish[key] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error actualizando lista deseos.')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
  }

  IconButton _miniBtn({
    required IconData icon,
    required bool active,
    required bool disabled,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: (active || disabled) ? Colors.grey : Colors.black),
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      splashRadius: 18,
      onPressed: disabled ? null : onPressed,
    );
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
                  final c = (a.country ?? '').trim();
                  return ListTile(
                    title: Text(a.name),
                    subtitle: c.isEmpty ? null : Text('País: $c'),
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
                        final key = _k(artistName, al.title);

                        if (!_exists.containsKey(key) && _busy[key] != true && artistName.isNotEmpty) {
                          _hydrateIfNeeded(artistName, al);
                        }

                        final exists = _exists[key] == true;
                        final fav = _fav[key] == true;
                        final inWish = _wish[key] == true;
                        final busy = _busy[key] == true;

                        final addDisabled = exists;
                        final favDisabled = !exists; // ⭐ solo si ya está agregado
                        final wishDisabled = exists || inWish;

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
                            subtitle: Row(
                              children: [
                                Expanded(child: Text('Año: $year')),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _miniBtn(
                                      icon: exists ? Icons.check_circle : Icons.format_list_bulleted,
                                      active: exists,
                                      disabled: busy || addDisabled,
                                      tooltip: addDisabled ? 'Ya está en tu lista' : 'Agregar a tu lista',
                                      onPressed: () => _addToListOptimistic(artistName, al),
                                    ),
                                    _miniBtn(
                                      icon: fav ? Icons.star : Icons.star_border,
                                      active: fav,
                                      disabled: busy || favDisabled,
                                      tooltip: favDisabled
                                          ? 'Primero agrégalo a tu lista'
                                          : (fav ? 'Quitar de favoritos' : 'Agregar a favoritos'),
                                      onPressed: () => _toggleFavoriteOptimistic(artistName, al),
                                    ),
                                    _miniBtn(
                                      icon: Icons.shopping_cart,
                                      active: inWish,
                                      disabled: busy || wishDisabled,
                                      tooltip: exists
                                          ? 'Ya lo tienes en tu lista'
                                          : (inWish ? 'Ya está en lista de deseos' : 'Agregar a lista deseos'),
                                      onPressed: () => _addWishlistOptimistic(artistName, al),
                                    ),
                                  ],
                                ),
                              ],
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
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
