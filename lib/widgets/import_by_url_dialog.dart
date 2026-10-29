import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/youtube_service.dart';
import '../services/playlist_service.dart';

class ImportByUrlDialog extends StatefulWidget {
  final String? initialPlaylistId; // Se fornecido, pré-seleciona para adicionar música
  final String? initialUrl; // Se fornecido, preenche o campo de link automaticamente

  const ImportByUrlDialog({super.key, this.initialPlaylistId, this.initialUrl});

  @override
  State<ImportByUrlDialog> createState() => _ImportByUrlDialogState();
}

class _ImportByUrlDialogState extends State<ImportByUrlDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _playlistUrlController = TextEditingController();
  final TextEditingController _videoUrlController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();

  bool _isLoading = false;
  String? _statusMessage;
  String? _selectedPlaylistId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      final url = widget.initialUrl!;
      if (YouTubeService.extractPlaylistId(url) != null) {
        _playlistUrlController.text = url;
        _tabController.index = 0;
      } else {
        _videoUrlController.text = url;
        _tabController.index = 1;
      }
    } else if (widget.initialPlaylistId != null) {
      _selectedPlaylistId = widget.initialPlaylistId;
      _tabController.index = 1; // Vai direto para "Adicionar Música"
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _playlistUrlController.dispose();
    _videoUrlController.dispose();
    _ytService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistService = Provider.of<PlaylistService>(context);
    final playlists = playlistService.playlists;

    if (_selectedPlaylistId == null && playlists.isNotEmpty) {
      _selectedPlaylistId = playlists.first.id;
    }

    return Dialog(
      backgroundColor: const Color(0xFF161622),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B2CBF), Color(0xFFF72585)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.link, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Montar Playlist por Link',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Sem login: use qualquer link público ou não-listado',
                      style: TextStyle(color: Color(0xFF00F5D4), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Abas
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF222232),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: const Color(0xFF7B2CBF),
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Playlist do YouTube'),
                  Tab(text: 'Música Individual'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Conteúdo
            SizedBox(
              height: 230,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildImportPlaylistTab(playlistService),
                  _buildAddSingleVideoTab(playlistService, playlists),
                ],
              ),
            ),

            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ),

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  // Aba 1: Importar Playlist inteira por URL
  Widget _buildImportPlaylistTab(PlaylistService playlistService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Cole o link de uma playlist do YouTube para importar todas as faixas automaticamente:',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _playlistUrlController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'https://www.youtube.com/playlist?list=PL...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.playlist_play, color: Color(0xFF9D4EDD)),
            filled: true,
            fillColor: const Color(0xFF1E1E2C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B2CBF),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isLoading ? null : () => _importPlaylist(playlistService),
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download, color: Colors.white),
          label: Text(
            _isLoading ? 'Importando faixas da playlist...' : 'Importar Coletânea Completa',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // Aba 2: Adicionar Música individual por URL a uma playlist existente
  Widget _buildAddSingleVideoTab(PlaylistService playlistService, List<dynamic> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _videoUrlController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Link do vídeo (ex: https://youtu.be/... ou watch?v=...)',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.music_note, color: Color(0xFF9D4EDD)),
            filled: true,
            fillColor: const Color(0xFF1E1E2C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Adicionar à coletânea:',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (playlists.isEmpty)
          const Text(
            'Crie uma coletânea antes de adicionar faixas.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPlaylistId,
                dropdownColor: const Color(0xFF1E1E2C),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                isExpanded: true,
                items: playlists.map<DropdownMenuItem<String>>((pl) {
                  return DropdownMenuItem<String>(
                    value: pl.id as String,
                    child: Text('${pl.name} (${pl.tracks.length} músicas)'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPlaylistId = val);
                },
              ),
            ),
          ),
        const Spacer(),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B2CBF),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isLoading ? null : () => _addSingleVideo(playlistService),
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.add_circle, color: Colors.white),
          label: Text(
            _isLoading ? 'Buscando metadados...' : 'Adicionar à Coletânea',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Future<void> _importPlaylist(PlaylistService playlistService) async {
    final url = _playlistUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _statusMessage = 'Cole um link de playlist do YouTube.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final importedPlaylist = await _ytService.importPlaylistFromUrl(url);
      if (importedPlaylist == null || importedPlaylist.tracks.isEmpty) {
        setState(() {
          _statusMessage = 'Não foi possível ler as faixas. Verifique se o link da playlist é válido e público.';
        });
      } else {
        await playlistService.addPlaylist(importedPlaylist);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Coletânea "${importedPlaylist.name}" importada com ${importedPlaylist.tracks.length} músicas!'),
              backgroundColor: const Color(0xFF7B2CBF),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _statusMessage = 'Erro ao importar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addSingleVideo(PlaylistService playlistService) async {
    final url = _videoUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _statusMessage = 'Cole um link de vídeo do YouTube.');
      return;
    }

    if (_selectedPlaylistId == null) {
      setState(() => _statusMessage = 'Selecione uma coletânea de destino.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final track = await _ytService.getTrackFromUrl(url);
      if (track == null) {
        setState(() => _statusMessage = 'Não foi possível carregar a música deste link.');
      } else {
        await playlistService.addTrackToPlaylist(_selectedPlaylistId!, track);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${track.title}" adicionada com sucesso!'),
              backgroundColor: const Color(0xFF7B2CBF),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _statusMessage = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
