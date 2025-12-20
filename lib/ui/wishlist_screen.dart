import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/vinyl_add_service.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  // cache local para deshabilitar "agregar a lista" si ya existe
  final Map<String, bool> _exists = {};
  final Map<String, bool> _busy = {};

  String _k(String artist, String album) => '$artist||$album';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _hydrateExistsIfNeeded(Map<String, dynamic> w) async {
    final artist = (w['artista'] as String?)?.trim() ?? '';
    final album = (w['album'] as String?)?.trim() ?? '';
    if (artist.isEmpty || album.isEmpty) return;

    final key = _k(artist, album);
    if (_exists.containsKey(key) || _busy[key] == true) return;

    _busy[key] = true;
    try {
      final row = await VinylDb.instance.findByExact(artista: artist, album: album);
      _exists[key] = row != null;
    } finally {
      _busy[key] = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeItem(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    await VinylDb.instance.removeWishlistById(id);
    await BackupService.autoSaveIfEnabled();

    _snack('Eliminado de la lista de deseos');
    _reload();
  }

  Future<void> _moveToCollection(Map<String, dynamic> w) async {
    final id = w['id'];
    if (id is! int) return;

    final artist = (w['artista'] as String?)?.trim() ?? '';
    final album = (w['album'] as String?)?.trim() ?? '';
    if (artist.isEmpty || album.isEmpty) {
      _snack('Faltan datos (artista/álbum).');
      return;
    }

    final key = _k(artist, album);
    if (_busy[key] == true) return;

    if (_exists[key] == true) {
      _snack('Ya está en tu lista de vinilos.');
      return;
    }

    setState(() => _busy[key] = true);

    try {
      final prepared = await VinylAddService.prepare(
        artist: artist,
        album: album,
        artistId: w['artistId'] as String?,
      );

      final res = await VinylAddService.addPrepared(prepared, favorite: false);
      if (!res.ok) {
        _snack(res.message);
        return;
      }

      await VinylDb.instance.removeWishlistById(id);
      await BackupService.autoSaveIfEnabled();

      _snack('Agregado a tu lista ✅');
      _reload();
    } catch (_) {
      _snack('Error agregando a tu lista.');
    } finally {
      if (!mounted) return;
      setState(() => _busy[key] = false);
    }
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
    final cover250 = (w['cover250'] as String?)?.trim() ?? '';

    if (cover250.startsWith('http://') || cover250.startsWith('https://')) {
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
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No hay vinilos en la lista de deseos.'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final w = items[i];

              final artist = (w['artista'] as String?)?.trim() ?? '';
              final album = (w['album'] as String?)?.trim() ?? '';
              final key = _k(artist, album);

              if (!_exists.containsKey(key) && _busy[key] != true) {
                _hydrateExistsIfNeeded(w);
              }

              final alreadyInList = _exists[key] == true;
              final busy = _busy[key] == true;

              return Card(
                child: ListTile(
                  leading: _leadingCover(w),
                  title: Text('${w['artista']} — ${w['album']}'),
                  subtitle: Text('Año: ${(w['year'] as String?)?.trim().isNotEmpty == true ? w['year'] : '—'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 📋 Icono agregar a lista (sin texto)
                      IconButton(
                        tooltip: alreadyInList ? 'Ya está en tu lista' : 'Agregar a tu lista de vinilos',
                        icon: Icon(
                          Icons.format_list_bulleted,
                          color: (alreadyInList || busy) ? Colors.grey : Colors.black,
                        ),
                        onPressed: (alreadyInList || busy) ? null : () => _moveToCollection(w),
                      ),

                      // 🗑️ Eliminar de wishlist
                      IconButton(
                        tooltip: 'Eliminar de la lista de deseos',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy ? null : () => _removeItem(w),
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
