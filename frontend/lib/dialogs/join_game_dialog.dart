import 'package:flutter/material.dart';

class JoinGameDialog extends StatefulWidget {
  final String gameCode;
  final String? preFilledName;
  final Function(String) onJoin;

  const JoinGameDialog({
    super.key,
    required this.gameCode,
    this.preFilledName,
    required this.onJoin,
  });

  @override
  State<JoinGameDialog> createState() => _JoinGameDialogState();
}

class _JoinGameDialogState extends State<JoinGameDialog> {
  late TextEditingController _nameController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preFilledName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _handleJoin() {
    if (_nameController.text.trim().isNotEmpty && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
      widget.onJoin(_nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('You\'re joining game: ${widget.gameCode}'),
          const SizedBox(height: 8),
          Text(
            'This will join you as a new player. If you were playing this game before and got disconnected, use the "Rejoin Game" option instead.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              border: OutlineInputBorder(),
              hintText: 'Enter your name to join',
            ),
            autofocus: true,
            textInputAction: TextInputAction.done,
            enabled: !_isLoading,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty && !_isLoading) {
                _handleJoin();
              }
            },
          ),
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Joining game...'),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (!_isLoading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _handleJoin,
            child: const Text('Join Game'),
          ),
        ],
      ],
    );
  }
}
