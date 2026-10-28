import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/playlist_service.dart';

class AddToPlaylistDialog extends StatefulWidget {
  final Track track;

  const AddToPlaylistDialog({super.key, required this.track});

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreatingNew = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistService = Provider.of<PlaylistService>(context);
    final playlists = playlistService.playlists;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        _isCreatingNew ? 'Criar Nova Coletânea' : 'Adicionar à Coletânea',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 400,
        child: _isCreatingNew
            ? TextField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nome da coletânea (ex: Rock 80s)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2B2B3D),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              )
            : playlists.isEmpty
                ? const Text(
                    'Você ainda não possui nenhuma coletânea criada.',
                    style: TextStyle(color: Colors.white70),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      final alreadyContains =
                          pl.tracks.any((t) => t.id == widget.track.id);

                      return ListTile(
                        leading: const Icon(Icons.queue_music, color: Color(0xFF9D4EDD)),
                        title: Text(
                          pl.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${pl.tracks.length} músicas',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: alreadyContains
                            ? const Icon(Icons.check_circle, color: Colors.greenAccent)
                            : const Icon(Icons.add, color: Colors.white60),
                        onTap: alreadyContains
                            ? null
                            : () async {
                                await playlistService.addTrackToPlaylist(
                                    pl.id, widget.track);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Adicionado em "${pl.name}"!'),
                                      backgroundColor: const Color(0xFF7B2CBF),
                                    ),
                                  );
                                }
                              },
                      );
                    },
                  ),
      ),
      actions: [
        if (_isCreatingNew)
          TextButton(
            onPressed: () => setState(() => _isCreatingNew = false),
            child: const Text('Voltar', style: TextStyle(color: Colors.white60)),
          )
        else
          TextButton.icon(
            onPressed: () => setState(() => _isCreatingNew = true),
            icon: const Icon(Icons.add, color: Color(0xFF9D4EDD)),
            label: const Text('Nova Coletânea',
                style: TextStyle(color: Color(0xFF9D4EDD))),
          ),
        if (_isCreatingNew)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B2CBF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              if (_nameController.text.trim().isNotEmpty) {
                final newPl = await playlistService.createPlaylist(
                  _nameController.text.trim(),
                );
                await playlistService.addTrackToPlaylist(newPl.id, widget.track);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Coletânea "${newPl.name}" criada com a música!'),
                      backgroundColor: const Color(0xFF7B2CBF),
                    ),
                  );
                }
              }
            },
            child: const Text('Salvar e Adicionar',
                style: TextStyle(color: Colors.white)),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.white60)),
          ),
      ],
    );
  }
}
