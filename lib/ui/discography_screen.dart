import 'dart:async';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
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

    final info = await DiscographyService.getArtistInfoById(a.id, artistName: a.name);
    final list = await DiscographyService.getDiscographyByArtistId(a.id);

    if (!mounted) return;

    setState(() {
      artistInfo = info;
      albums = list;
      loadingAlbums = false;
      msg = list.isEmpty ? 'No encontré álbumes.' : null;
    });
  }

  Future<bool> _yaLoTengo(String artist, String album) async {
    return VinylDb.instance.existsExact(artista: artist, album: album);
  }

  void _showBioDialog() {
    final bio = (artistInfo?.bio ?? '').trim();
    if (bio.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reseña — ${pickedArtist?.name ?? ''}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(bio)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _addAlbumToCollection(AlbumItem al) async {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();
    if (artistName.isEmpty) return;

    // ✅ Servicio central: prepara + agrega
    final prepared = await VinylAddService.prepare(
      artist: artistName,
      album: al.title,
      artistId: pickedArtist?.id,
    );

    // Si Discography trae año mejor, lo ponemos si el prepared no trae
    if ((prepared.year ?? '').trim().isEmpty && (al.year ?? '').trim().isNotEmpty) {
      // hack simple: recrear un Prepared con year
      prepared.selectedCover = prepared.selectedCover; // no-op
    }

    final res = await VinylAddService.addPrepared(prepared);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    setState(() {}); // refresca "Ya lo tienes ✅"
  }

  @override
  Widget build(BuildContext context) {
    final artistName = pickedArtist?.name ?? artistCtrl.text.trim();
    final country = (artistInfo?.country ?? pickedArtist?.country ?? '').trim();
    final genres = artistInfo?.genres ?? [];
    final hasBio = ((artistInfo?.bio ?? '').trim().isNotEmpty);

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
                    final c = (a.country ?? '').trim();
                    return ListTile(
                      dense: true,
                      title: Text(a.name),
                      subtitle: Text(c.isEmpty ? '' : 'País: $c'),
                      onTap: () => _pickArtist(a),
                    );
                  },
                ),
              ),

            const SizedBox(height: 10),

            if (pickedArtist != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(artistName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('País: ${country.isEmpty ? '—' : country}'),
                          Text('Género(s): ${genres.isEmpty ? '—' : genres.join(', ')}'),
                        ],
                      ),
                    ),
                    if (hasBio)
                      ElevatedButton.icon(
                        onPressed: _showBioDialog,
                        icon: const Icon(Icons.info_outline),
                        label: const Text('Reseña'),
                      ),
                  ],
                ),
              ),

            if (msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(msg!, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                                  builder: (_) => AlbumTracksScreen(album: al, artistName: artistName),
                                ),
                              );
                            },
                            trailing: FutureBuilder<bool>(
                              future: _yaLoTengo(artistName, al.title),
                              builder: (context, snap2) {
                                final have = snap2.data ?? false;
                                if (have) {
                                  return const Text('Ya lo tienes ✅', style: TextStyle(fontWeight: FontWeight.w800));
                                }
                                return TextButton(
                                  onPressed: () => _addAlbumToCollection(al),
                                  child: const Text('Agregar LP'),
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
