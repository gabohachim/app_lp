import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../db/vinyl_db.dart';
import '../services/backup_service.dart';
import '../services/discography_service.dart';
import '../services/metadata_service.dart';
import '../services/view_mode_service.dart';
import '../services/vinyl_add_service.dart';
import 'discography_screen.dart';
import 'settings_screen.dart';
import 'vinyl_detail_sheet.dart';

enum Vista { inicio, buscar, lista, favoritos, deseos, borrar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Vista vista = Vista.inicio;

  bool _gridView = false;

  final artistaCtrl = TextEditingController();
  final albumCtrl = TextEditingController();
  final yearCtrl = TextEditingController();

  Timer? _debounceArtist;
  bool buscandoArtistas = false;
  List<ArtistHit> sugerenciasArtistas = [];
  ArtistHit? artistaElegido;

  Timer? _debounceAlbum;
  bool buscandoAlbums = false;
  List<AlbumSuggest> sugerenciasAlbums = [];
  AlbumSuggest? albumElegido;

  List<Map<String, dynamic>> resultados = [];
  bool mostrarAgregar = false;

  bool autocompletando = false;
  PreparedVinylAdd? prepared;

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

  // ----------------- FAVORITOS (colección) -----------------

  Future<void> _toggleFavorite(Map<String, dynamic> v) async {
    final id = v['id'];
    if (id is! int) return;

    final current = (v['favorite'] ?? 0) == 1;
    final next = !current;

    await VinylDb.instance.setFavorite(id: id, favorite: next);
    await BackupService.autoSaveIfEnabled();

    v['favorite'] = next ? 1 : 0;

    if (!mounted) return;
    setState(() {});
  }

  // ----------------- WISHLIST (lista deseos) -----------------

  Future<void> _removeWishlistItem(int id) async {
    await VinylDb.instance.removeWishlistById(id);
    if (!mounted) return;
    setState(() {});
  }

  // ----------------- DETALLE -----------------

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
      setState(() {});
    });
  }

  // ----------------- UI helpers -----------------

  Widget _numeroBadge(dynamic numero) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
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
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.album, size: 48),
    );
  }

  // ----------------- HOME widgets -----------------

  Widget encabezadoInicio() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        contadorLp(),
        const Spacer(),
        nubeEstado(),
      ],
    );
  }

  Widget nubeEstado() {
    return FutureBuilder<bool>(
      future: BackupService.isAutoEnabled(),
      builder: (context, snap) {
        final auto = snap.data ?? false;
        return Container(
          width: 90,
          height: 70,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            auto ? Icons.cloud_done : Icons.cloud_off,
            color: auto ? Colors.greenAccent : Colors.white54,
            size: 30,
          ),
        );
      },
    );
  }

  // ✅ Contador centrado dentro del cuadro (tu arreglo pedido)
  Widget contadorLp() {
    return FutureBuilder<int>(
      future: VinylDb.instance.getCount(),
      builder: (context, snap) {
        final total = snap.data ?? 0;
        return Container(
          width: 90,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center, // ✅ CENTRADO
          child: Text(
            '$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }

  Widget gabolpMarca() {
    return const Positioned(
      right: 10,
      bottom: 8,
      child: IgnorePointer(
        child: Text(
          'GaBoLP',
          style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700),
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
              Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
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
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscographyScreen()))
              .then((_) => setState(() {}));
        }),
        const SizedBox(height: 10),

        btn(Icons.list, 'Lista de vinilos', () => setState(() => vista = Vista.lista)),
        const SizedBox(height: 10),

        btn(Icons.star, 'Vinilos favoritos', () => setState(() => vista = Vista.favoritos)),
        const SizedBox(height: 10),

        btn(Icons.shopping_cart_outlined, 'Lista deseos', () => setState(() => vista = Vista.deseos)),
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

  // ----------------- BUSCAR (autocompletado + auto metadata) -----------------

  void _onArtistChanged(String v) {
    _debounceArtist?.cancel();
    final q = v.trim();

    setState(() {
      artistaElegido = null;
      albumElegido = null;
      sugerenciasAlbums = [];
      buscandoAlbums = false;
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
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
      albumCtrl.clear();
      albumElegido = null;
      sugerenciasAlbums = [];
    });
  }

  void _onAlbumChanged(String v) {
    _debounceAlbum?.cancel();
    final q = v.trim();
    final artistName = artistaCtrl.text.trim();

    setState(() {
      albumElegido = null;
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
    });

    if (artistName.isEmpty || q.isEmpty) {
      setState(() {
        sugerenciasAlbums = [];
        buscandoAlbums = false;
      });
      return;
    }

    _debounceAlbum = Timer(const Duration(milliseconds: 220), () async {
      setState(() => buscandoAlbums = true);
      final hits = await MetadataService.searchAlbumsForArtist(
        artistName: artistName,
        albumQuery: q,
      );
      if (!mounted) return;
      setState(() {
        sugerenciasAlbums = hits;
        buscandoAlbums = false;
      });
    });
  }

  Future<void> _pickAlbum(AlbumSuggest a) async {
    FocusScope.of(context).unfocus();
    setState(() {
      albumElegido = a;
      albumCtrl.text = a.title;
      sugerenciasAlbums = [];
    });
  }

  Future<void> buscar() async {
    final artista = artistaCtrl.text.trim();
    final album = albumCtrl.text.trim();

    if (artista.isEmpty || album.isEmpty) {
      snack('Escribe Artista y Álbum');
      return;
    }

    final res = await VinylDb.instance.search(artista: artista, album: album);

    setState(() {
      resultados = res;
      prepared = null;
      mostrarAgregar = res.isEmpty;
      yearCtrl.clear();
    });

    snack(res.isEmpty ? 'No lo tienes' : 'Ya lo tienes');

    if (mostrarAgregar) {
      setState(() => autocompletando = true);

      final p = await VinylAddService.prepare(
        artist: artista,
        album: album,
        artistId: artistaElegido?.id,
      );

      if (!mounted) return;

      setState(() {
        prepared = p;
        yearCtrl.text = p.year ?? '';
        autocompletando = false;
      });
    }
  }

  Future<void> elegirCaratula() async {
    final p = prepared;
    if (p == null || p.coverCandidates.isEmpty) {
      snack('No encontré carátulas para elegir.');
      return;
    }

    final picked = await showDialog<CoverCandidate>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Elegir carátula (máx 5)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: p.coverCandidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = p.coverCandidates[i];
              final y = (c.year ?? '').trim();
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    c.coverUrl250,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.album),
                  ),
                ),
                title: Text('Opción ${i + 1}${y.isEmpty ? '' : ' — $y'}'),
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );

    if (picked == null) return;

    setState(() {
      prepared!.selectedCover = picked;
      if ((picked.year ?? '').trim().isNotEmpty) yearCtrl.text = picked.year!.trim();
    });
  }

  Future<void> agregar() async {
    final p = prepared;
    if (p == null) return;

    final res = await VinylAddService.addPrepared(
      p,
      overrideYear: yearCtrl.text.trim().isEmpty ? null : yearCtrl.text.trim(),
      favorite: false,
    );

    snack(res.message);

    if (!res.ok) return;

    await BackupService.autoSaveIfEnabled();

    setState(() {
      prepared = null;
      mostrarAgregar = false;
      resultados = [];
      yearCtrl.clear();
    });
  }

  Widget vistaBuscar() {
    final p = prepared;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: artistaCtrl,
          onChanged: _onArtistChanged,
          decoration: InputDecoration(
            labelText: 'Artista',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 6),
        if (buscandoArtistas) const LinearProgressIndicator(),
        if (sugerenciasArtistas.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sugerenciasArtistas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = sugerenciasArtistas[i];
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

        TextField(
          controller: albumCtrl,
          onChanged: _onAlbumChanged,
          decoration: InputDecoration(
            labelText: 'Álbum',
            filled: true,
            fillColor: Colors.white.withOpacity(0.85),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 6),
        if (buscandoAlbums) const LinearProgressIndicator(),
        if (sugerenciasAlbums.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sugerenciasAlbums.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final al = sugerenciasAlbums[i];
                final y = (al.year ?? '').trim();
                return ListTile(
                  dense: true,
                  title: Text(al.title),
                  subtitle: Text(y.isEmpty ? '' : 'Año: $y'),
                  onTap: () => _pickAlbum(al),
                );
              },
            ),
          ),

        const SizedBox(height: 10),
        ElevatedButton(onPressed: buscar, child: const Text('Buscar')),

        const SizedBox(height: 12),

        if (resultados.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ya lo tienes:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...resultados.map((v) {
                  final y = (v['year'] as String?)?.trim() ?? '';
                  final yTxt = y.isEmpty ? '' : ' ($y)';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _leadingCover(v),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${v['numero']} — ${v['artista']} — ${v['album']}$yTxt',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

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
                const Text('Agregar este vinilo:', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (autocompletando) const LinearProgressIndicator(),
                if (!autocompletando && p != null) ...[
                  Text('Año: ${p.year ?? '—'}'),
                  Text('Género: ${p.genre ?? '—'}'),
                  Text('País: ${p.country ?? '—'}'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (!autocompletando && p != null && (p.selectedCover500 ?? '').trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      p.selectedCover500!,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 70,
                        height: 70,
                        child: Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.coverCandidates.length > 1
                          ? 'Carátula (hay ${p.coverCandidates.length} opciones)'
                          : 'Carátula automática ✅',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),

          if (!autocompletando && p != null && p.coverCandidates.length > 1) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: elegirCaratula,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir carátula'),
            ),
          ],

          const SizedBox(height: 10),

          TextField(
            controller: yearCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Año (editable)',
              filled: true,
              fillColor: Colors.white.withOpacity(0.85),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: autocompletando ? null : agregar,
            child: const Text('Agregar vinilo'),
          ),
        ],
      ],
    );
  }

  // ----------------- LISTA/GRID (colección) -----------------

  Widget _gridVinylCard(Map<String, dynamic> v, {required bool conBorrar}) {
    final year = (v['year'] as String?)?.trim() ?? '';
    final artista = (v['artista'] as String?)?.trim() ?? '';
    final album = (v['album'] as String?)?.trim() ?? '';
    final fav = (v['favorite'] ?? 0) == 1;

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

            // ✅ número arriba derecha
            Positioned(
              right: 8,
              top: 8,
              child: _numeroBadge(v['numero']),
            ),

            // ⭐ a la izquierda (no choca con el número)
            if (!conBorrar)
              Positioned(
                left: 6,
                top: 6,
                child: IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                  icon: Icon(fav ? Icons.star : Icons.star_border),
                  onPressed: () => _toggleFavorite(v),
                ),
              ),

            if (conBorrar)
              Positioned(
                left: 6,
                top: 6,
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
  }

  Widget listaColeccion({required bool conBorrar, required bool onlyFavorites}) {
    final fut = onlyFavorites ? VinylDb.instance.getFavorites() : VinylDb.instance.getAll();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fut,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
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
            itemBuilder: (context, i) => _gridVinylCard(items[i], conBorrar: conBorrar),
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
            final fav = (v['favorite'] ?? 0) == 1;

            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: _leadingCover(v),

                // ✅ badge arriba derecha (sin LP)
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
                    Positioned(
                      right: 0,
                      top: 0,
                      child: _numeroBadge(v['numero']),
                    ),
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

  // ----------------- WISHLIST UI -----------------

  Widget listaDeseos() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VinylDb.instance.getWishlist(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return const Text('No tienes deseos todavía.', style: TextStyle(color: Colors.white));
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final w = items[i];
            final year = (w['year'] ?? '').toString().trim();
            final cover = (w['cover250'] ?? '').toString().trim();

            return Card(
              color: Colors.white.withOpacity(0.88),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cover.isEmpty
                      ? const SizedBox(width: 48, height: 48, child: Icon(Icons.album))
                      : Image.network(
                          cover,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.album),
                          ),
                        ),
                ),
                title: Text('${w['artista']} — ${w['album']}'),
                subtitle: Text('Año: ${year.isEmpty ? '—' : year}'),
                trailing: IconButton(
                  tooltip: 'Quitar de lista deseos',
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () => _removeWishlistItem(w['id'] as int),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ----------------- APP BAR/FAB -----------------

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
      case Vista.deseos:
        title = 'Lista deseos';
        break;
      case Vista.borrar:
        title = 'Borrar vinilos';
        break;
      default:
        title = 'GaBoLP';
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
    if (vista == Vista.lista || vista == Vista.favoritos || vista == Vista.deseos || vista == Vista.borrar) {
      return FloatingActionButton.extended(
        onPressed: () => setState(() => vista = Vista.inicio),
        icon: const Icon(Icons.home),
        label: const Text('Inicio'),
      );
    }
    return null;
  }

  // ----------------- BUILD -----------------

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
                    if (vista == Vista.lista) listaColeccion(conBorrar: false, onlyFavorites: false),
                    if (vista == Vista.favoritos) listaColeccion(conBorrar: false, onlyFavorites: true),
                    if (vista == Vista.deseos) listaDeseos(),
                    if (vista == Vista.borrar) listaColeccion(conBorrar: true, onlyFavorites: false),
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
