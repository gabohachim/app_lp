import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/metadata_service.dart';
import '../services/vinyl_add_service.dart';
import '../services/view_mode_service.dart';
import 'discography_screen.dart';
import 'settings_screen.dart';
import 'vinyl_detail_sheet.dart';
import 'wishlist_screen.dart';

enum Vista { inicio, buscar, lista, favoritos, borrar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Vista vista = Vista.inicio;

  // visual
  bool _gridView = false;

  // buscar
  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  // autocompletado artistas
  Timer? _debounceArtist;
  bool buscandoArtistas = false;
  List<ArtistHit> sugerenciasArtistas = [];
  ArtistHit? artistaElegido;

  // autocompletado álbumes
  Timer? _debounceAlbum;
  bool buscandoAlbums = false;
  List<Map<String, dynamic>> sugerenciasAlbums = [];
  Map<String, dynamic>? albumElegido;

  // resultados
  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  // agregar
  PreparedVinylAdd? prepared;
  bool autocompletando = false;

  // cache local para favorito instantáneo (lista/grid)
  final Map<int, bool> _favCache = {};
  int _reloadTick = 0;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final g = await ViewModeService.isGridEnabled();
    if (!mounted) return;
    setState(() => _gridView = g);
  }

  @override
  void dispose() {
    _debounceArtist?.cancel();
    _debounceAlbum?.cancel();
    artistaCtrl.dispose();
    albumCtrl.dispose();
    yearCtrl.dispose();
    super.dispose();
  }

  void snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  bool _isFav(Map<String, dynamic> v) {
    final id = v['id'];
    final dbFav = (v['favorite'] ?? 0) == 1;
    if (id is int) return _favCache[id] ?? dbFav;
    return dbFav;
  }

  Future<void> _toggleFavorite(Map<String, dynamic> v) async {
    final id = v['id'];
    if (id is! int) return;

    final current = (v['favorite'] ?? 0) == 1;
    final next = !current;

    // ✅ UI inmediata
    setState(() {
      _favCache[id] = next;
      v['favorite'] = next ? 1 : 0;
      _reloadTick++;
    });

    try {
      await VinylDb.instance.setFavorite(id: id, favorite: next);
      await BackupService.autoSaveIfEnabled();
    } catch (_) {
      if (!mounted) return;
      // revert
      setState(() {
        _favCache[id] = current;
        v['favorite'] = current ? 1 : 0;
        _reloadTick++;
      });
      snack('Error actualizando favorito.');
    }
  }

  void _openDetail(Map<String, dynamic> v) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: VinylDetailSheet(vinyl: v),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {}); // por si cambiaste favorito en el detalle
    });
  }

  Widget _numeroBadge(dynamic numero) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$numero',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _leadingCover(Map<String, dynamic> v) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(f, width: 48, height: 48, fit: BoxFit.cover),
        );
      }
    }
    return const Icon(Icons.album);
  }

  Widget _gridCover(Map<String, dynamic> v) {
    final cp = (v['coverPath'] as String?)?.trim() ?? '';
    if (cp.isNotEmpty) {
      final f = File(cp);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.album, size: 48),
    );
  }

  // ---------------- BUSCADOR (autocompletado artista) ----------------
  void _onArtistChanged(String v) {
    _debounceArtist?.cancel();
    final q = v.trim();

    setState(() {
      artistaElegido = null;

      // reset album al cambiar artista
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;

      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });

    if (q.isEmpty) {
      setState(() {
        sugerenciasArtistas = [];
        buscandoArtistas = false;
      });
      return;
    }

    _debounceArtist = Timer(const Duration(milliseconds: 350), () async {
      setState(() => buscandoArtistas = true);
      final hits = await DiscographyService.searchArtists(q);
      if (!mounted) return;
      setState(() {
        sugerenciasArtistas = hits;
        buscandoArtistas = false;
      });
    });
  }

  Future<void> _pickArtist(ArtistHit a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      artistaElegido = a;
      artistaCtrl.text = a.name;
      sugerenciasArtistas = [];

      // reset album
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;

      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });
  }

  // ---------------- BUSCADOR (autocompletado album) ----------------
  void _onAlbumChanged(String v) {
    _debounceAlbum?.cancel();
    final q = v.trim();
    final artistName = artistaCtrl.text.trim();

    setState(() {
      albumElegido = null;
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });

    if (q.isEmpty || artistName.isEmpty) {
      setState(() {
        sugerenciasAlbums = [];
        buscandoAlbums = false;
      });
      return;
    }

    _debounceAlbum = Timer(const Duration(milliseconds: 250), () async {
      setState(() => buscandoAlbums = true);
      final hits = await MetadataService.searchAlbumsForArtist(artistName, q);
      if (!mounted) return;
      setState(() {
        sugerenciasAlbums = hits;
        buscandoAlbums = false;
      });
    });
  }

  Future<void> _pickAlbum(Map<String, dynamic> al) async {
    FocusScope.of(context).unfocus();
    setState(() {
      albumElegido = al;
      albumCtrl.text = (al['title'] ?? '').toString();
      sugerenciasAlbums = [];
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });
  }

  // ---------------- BUSCAR EN DB ----------------
  Future<void> buscar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();

    if (artista.isEmpty && album.isEmpty) {
      snack('Escribe al menos Artista o Álbum');
      return;
    }

    final res = await VinylDb.instance.search(artista: artista, album: album);

    setState(() {
      resultados = res;
      prepared = null;
      mostrarAgregar = res.isEmpty && artista.isNotEmpty && album.isNotEmpty;
      yearCtrl.clear();
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    if (mostrarAgregar) {
      setState(() => autocompletando = true);
      try {
        final p = await VinylAddService.prepare(
          artist: artista,
          album: album,
          artistId: artistaElegido?.id,
        );

        if (!mounted) return;

        setState(() {
          prepared = p;
          yearCtrl.text = (p.year ?? '').trim();
          autocompletando = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => autocompletando = false);
      }
    }
  }

  Future<void> agregar() async {
    final p = prepared;
    if (p == null) return;

    final overrideYear = yearCtrl.text.trim().isEmpty ? null : yearCtrl.text.trim();
    final res = await VinylAddService.addPrepared(p, overrideYear: overrideYear);

    await BackupService.autoSaveIfEnabled();
    snack(res.message);

    if (res.ok) {
      setState(() {
        prepared = null;
        mostrarAgregar = false;
        resultados = [];
        yearCtrl.clear();
        _reloadTick++;
      });
    }
  }

  // ---------------- UI: encabezado/home ----------------
  Widget encabezadoInicio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'GaboLP',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        Text('Colección de vinilos', style: TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget gabolpMarca() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'GaboLP',
          style: TextStyle(color: Colors.white.withOpacity(0.75)),
        ),
      ),
    );
  }

  Widget botonesInicio() {
    Widget btn(IconData icon, String text, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        btn(Icons.search, 'Buscar vinilos', () => setState(() => vista = Vista.buscar)),
        const SizedBox(height: 10),

        btn(Icons.library_music, 'Discografías', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscographyScreen()));
        }),
        const SizedBox(height: 10),

        btn(Icons.list, 'Lista de vinilos', () => setState(() => vista = Vista.lista)),
        const SizedBox(height: 10),

        btn(Icons.star, 'Vinilos favoritos', () => setState(() => vista = Vista.favoritos)),
        const SizedBox(height: 10),

        // ✅ NUEVO: Lista de deseos (debajo de favoritos) -> ICONO CARRITO
        btn(Icons.shopping_cart, 'Lista de deseos', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => WishlistScreen())).then((_) {
            if (!mounted) return;
            setState(() {});
          });
        }),
        const SizedBox(height: 10),

        btn(Icons.settings, 'Ajustes', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) async {
            await _loadViewMode();
            if (!mounted) return;
            setState(() {});
          });
        }),
        const SizedBox(height: 10),

        btn(Icons.delete_outline, 'Borrar vinilos', () => setState(() => vista = Vista.borrar)),
      ],
    );
  }

  // ---------------- UI: vista buscar ----------------
  Widget vistaBuscar() {
    final p = prepared;
    final showXArtist = artistaCtrl.text.trim().isNotEmpty;
    final showXAlbum = albumCtrl.text.trim().isNotEmpty;

    Widget suggestionBox<T>({
      required List<T> items,
      required Widget Function(T) tile,
    }) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: items.map(tile).toList(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: artistaCtrl,
                decoration: InputDecoration(
                  labelText: 'Artista',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.85),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: showXArtist
                      ? IconButton(
                          tooltip: 'Limpiar artista',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            _debounceArtist?.cancel();
                            _debounceAlbum?.cancel();
                            setState(() {
                              artistaCtrl.clear();
                              albumCtrl.clear();
                              yearCtrl.clear();
                              buscandoArtistas = false;
                              buscandoAlbums = false;
                              sugerenciasArtistas = [];
                              sugerenciasAlbums = [];
                              artistaElegido = null;
                              albumElegido = null;
                              resultados = [];
                              prepared = null;
                              mostrarAgregar = false;
                              autocompletando = false;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: _onArtistChanged,
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Limpiar todo',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                FocusScope.of(context).unfocus();
                _debounceArtist?.cancel();
                _debounceAlbum?.cancel();
                setState(() {
                  artistaCtrl.clear();
                  albumCtrl.clear();
                  yearCtrl.clear();
                  buscandoArtistas = false;
                  buscandoAlbums = false;
                  sugerenciasArtistas = [];
                  sugerenciasAlbums = [];
                  artistaElegido = null;
                  albumElegido = null;
                  resultados = [];
                  prepared = null;
                  mostrarAgregar = false;
                  autocompletando = false;
                });
              },
            ),
          ],
        ),
        if (buscandoArtistas) const LinearProgressIndicator(),
        if (sugerenciasArtistas.isNotEmpty)
          suggestionBox<ArtistHit>(
            items: sugerenciasArtistas,
            tile: (a) {
              final c = (a.country ?? '').trim();
              return ListTile(
                title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: c.isEmpty ? null : Text('País: $c'),
                onTap: () => _pickArtist(a),
              );
            },
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: albumCtrl,
                decoration: InputDecoration(
                  labelText: 'Álbum',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.85),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: showXAlbum
                      ? IconButton(
                          tooltip: 'Limpiar álbum',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            _debounceAlbum?.cancel();
                            setState(() {
                              albumCtrl.clear();
                              yearCtrl.clear();
                              buscandoAlbums = false;
                              sugerenciasAlbums = [];
                              albumElegido = null;
                              resultados = [];
                              prepared = null;
                              mostrarAgregar = false;
                              autocompletando = false;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: _onAlbumChanged,
              ),
            ),
          ],
        ),
        if (buscandoAlbums) const LinearProgressIndicator(),
        if (sugerenciasAlbums.isNotEmpty)
          suggestionBox<Map<String, dynamic>>(
            items: sugerenciasAlbums,
            tile: (al) {
              final t = (al['title'] ?? '').toString();
              final y = (al['year'] ?? '').toString().trim();
              return ListTile(
                title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Año: ${y.isEmpty ? '—' : y}'),
                onTap: () => _pickAlbum(al),
              );
            },
          ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: buscar,
          icon: const Icon(Icons.search),
          label: const Text('Buscar'),
        ),
        const SizedBox(height: 10),

        if (resultados.isNotEmpty) ...[
          const Text('Resultados:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...resultados.map((v) {
            final fav = _isFav(v);
            final year = (v['year'] as String?)?.trim();
            final genre = (v['genre'] as String?)?.trim();
            final country = (v['country'] as String?)?.trim();
            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: _leadingCover(v),
                title: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: Text('${v['artista']} — ${v['album']}'),
                    ),
                    Positioned(right: 0, top: 0, child: _numeroBadge(v['numero'])),
                  ],
                ),
                subtitle: Text(
                  'Año: ${(year?.isEmpty ?? true) ? '—' : year}  •  Género: ${(genre?.isEmpty ?? true) ? '—' : genre}  •  País: ${(country?.isEmpty ?? true) ? '—' : country}',
                ),
                onTap: () => _openDetail(v),
                trailing: IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                  icon: Icon(fav ? Icons.star : Icons.star_border),
                  onPressed: () => _toggleFavorite(v),
                ),
              ),
            );
          }).toList(),
        ],

        if (mostrarAgregar) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Agregar este vinilo', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (autocompletando) const LinearProgressIndicator(),
                if (!autocompletando && p != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: (p.selectedCover500 ?? '').trim().isEmpty
                            ? Container(
                                width: 90,
                                height: 90,
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: const Icon(Icons.album, size: 40),
                              )
                            : Image.network(
                                p.selectedCover500!,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 90,
                                  height: 90,
                                  color: Colors.black12,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Artista: ${p.artist}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('Álbum: ${p.album}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('Año: ${p.year ?? '—'}'),
                            Text('Género: ${p.genre ?? '—'}'),
                            Text('País: ${p.country ?? '—'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: yearCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Año (opcional: corregir)',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.85),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: agregar,
                    child: const Text('Agregar vinilo'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------- UI: lista completa / favoritos / borrar ----------------
  Widget listaCompleta({required bool conBorrar, required bool onlyFavorites}) {
    final fut = VinylDb.instance.getAll();

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('listaCompleta_${onlyFavorites}_${conBorrar}_${_reloadTick.toString()}'),
      future: fut,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rawItems = snap.data!;
        final items = onlyFavorites ? rawItems.where((v) => _isFav(v)).toList() : rawItems;

        if (items.isEmpty) {
          return Text(
            onlyFavorites ? 'No tienes favoritos todavía.' : 'No tienes vinilos todavía.',
            style: const TextStyle(color: Colors.white),
          );
        }

        if (_gridView) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 6),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, i) {
              final v = items[i];
              final year = (v['year'] as String?)?.trim() ?? '';
              final artista = (v['artista'] as String?)?.trim() ?? '';
              final album = (v['album'] as String?)?.trim() ?? '';
              final fav = _isFav(v);

              return InkWell(
                onTap: () => _openDetail(v),
                borderRadius: BorderRadius.circular(14),
                child: Card(
                  color: Colors.white.withOpacity(0.88),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _gridCover(v),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              artista,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(year.isEmpty ? '—' : year),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _numeroBadge(v['numero']),
                      ),
                      if (!conBorrar)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: IconButton(
                            tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                            icon: Icon(fav ? Icons.star : Icons.star_border),
                            onPressed: () => _toggleFavorite(v),
                          ),
                        ),
                      if (conBorrar)
                        Positioned(
                          left: 2,
                          bottom: 2,
                          child: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              await VinylDb.instance.deleteById(v['id'] as int);
                              await BackupService.autoSaveIfEnabled();
                              snack('Borrado');
                              setState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final v = items[i];
            final year = (v['year'] as String?)?.trim() ?? '—';
            final genre = (v['genre'] as String?)?.trim();
            final country = (v['country'] as String?)?.trim();
            final fav = _isFav(v);

            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: _leadingCover(v),
                title: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: Text(
                        '${v['artista']} — ${v['album']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Positioned(right: 0, top: 0, child: _numeroBadge(v['numero'])),
                  ],
                ),
                subtitle: Text(
                  'Año: $year  •  Género: ${genre?.isEmpty ?? true ? '—' : genre}  •  País: ${country?.isEmpty ?? true ? '—' : country}',
                ),
                onTap: () => _openDetail(v),
                trailing: conBorrar
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await VinylDb.instance.deleteById(v['id'] as int);
                          await BackupService.autoSaveIfEnabled();
                          snack('Borrado');
                          setState(() {});
                        },
                      )
                    : IconButton(
                        tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                        icon: Icon(fav ? Icons.star : Icons.star_border),
                        onPressed: () => _toggleFavorite(v),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (vista == Vista.inicio) return null;

    String title;
    switch (vista) {
      case Vista.buscar:
        title = 'Buscar vinilos';
        break;
      case Vista.lista:
        title = 'Lista de vinilos';
        break;
      case Vista.favoritos:
        title = 'Vinilos favoritos';
        break;
      case Vista.borrar:
        title = 'Borrar vinilos';
        break;
      default:
        title = 'GaboLP';
    }

    return AppBar(
      title: Text(title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => vista = Vista.inicio),
      ),
    );
  }

  Widget? _buildFab() {
    if (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.borrar) {
      return FloatingActionButton.extended(
        onPressed: () => setState(() => vista = Vista.inicio),
        icon: const Icon(Icons.home),
        label: const Text('Inicio'),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.grey.shade300)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vista == Vista.inicio) ...[
                      encabezadoInicio(),
                      const SizedBox(height: 14),
                      botonesInicio(),
                    ],
                    if (vista == Vista.buscar) vistaBuscar(),
                    if (vista == Vista.lista) listaCompleta(conBorrar: false, onlyFavorites: false),
                    if (vista == Vista.favoritos) listaCompleta(conBorrar: false, onlyFavorites: true),
                    if (vista == Vista.borrar) listaCompleta(conBorrar: true, onlyFavorites: false),
                  ],
                ),
              ),
            ),
          ),
          gabolpMarca(),
        ],
      ),
    );
  }
}
