import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import 'vinyl_detail_sheet.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = VinylDb.instance.getWishlist();
  }

  void _reload() {
    setState(() {
      _future = VinylDb.instance.getWishlist();
    });
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t)),
    );
  }

  Future<void> _removeItem(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    await VinylDb.instance.removeWishlistById(id);
    await BackupService.autoSaveIfEnabled();

    _snack('Eliminado de la lista de deseos');
    _reload();
  }

  Future<void> _openDetail(Map<String, dynamic> w) async {
    final artist = (w['artista'] ?? '').toString().trim();
    final album = (w['album'] ?? '').toString().trim();
    final year = (w['year'] ?? '').toString().trim();
    final cover = (w['cover500'] ?? w['cover250'] ?? '').toString().trim();
    final artistId = (w['artistId'] ?? '').toString().trim();

    String country = '';
    String genre = '';
    String bio = '';

    if (artistId.isNotEmpty) {
      try {
        final info = await DiscographyService.getArtistInfoById(
          artistId,
          artistName: artist,
        );
        country = info.country ?? '';
        genre = info.genres.join(', ');
        bio = info.bio ?? '';
      } catch (_) {}
    }

    final vinylLike = {
      'mbid': '',
      'coverPath': cover,
      'artista': artist,
      'album': album,
      'year': year,
      'genre': genre,
      'country': country,
      'artistBio': bio,
    };

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VinylDetailSheet(vinyl: vinylLike),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.library_music, color: Colors.black45),
    );
  }

  Widget _leadingCover(Map<String, dynamic> w) {
    final cover250 = (w['cover250'] ?? '').toString().trim();

    if (cover250.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          cover250,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    if (cover250.isNotEmpty && File(cover250).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(cover250),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    return _placeholder();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de deseos'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text('No hay vinilos en la lista de deseos.'),
            );
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final w = items[i];

              return Card(
                child: ListTile(
                  onTap: () => _openDetail(w),
                  leading: _leadingCover(w),
                  title: Text('${w['artista']} — ${w['album']}'),
                  subtitle: Text(
                    'Año: ${(w['year'] ?? '').toString().isEmpty ? '—' : w['year']}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 📋 AGREGAR A LISTA DE VINILOS
                      IconButton(
                        tooltip: 'Agregar a tu lista de vinilos',
                        icon: const Icon(Icons.format_list_bulleted),
                        onPressed: () async {
                          final artista = (w['artista'] ?? '').toString().trim();
                          final album = (w['album'] ?? '').toString().trim();

                          if (artista.isEmpty || album.isEmpty) return;

                          try {
                            await VinylDb.instance.insertVinyl(
                              artista: artista,
                              album: album,
                              year: (w['year'] ?? '').toString().trim().isEmpty
                                  ? null
                                  : w['year'].toString().trim(),
                              coverPath: (w['cover250'] ?? '').toString(),
                            );

                            await VinylDb.instance.removeWishlistById(w['id']);
                            await BackupService.autoSaveIfEnabled();

                            _snack('Agregado a tu lista de vinilos');
                            _reload();
                          } catch (_) {
                            _snack('No se pudo agregar');
                          }
                        },
                      ),

                      // 🗑️ ELIMINAR DE WISHLIST
                      IconButton(
                        tooltip: 'Eliminar de la lista de deseos',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeItem(w),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
