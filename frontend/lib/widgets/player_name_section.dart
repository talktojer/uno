import 'package:flutter/material.dart';

class PlayerNameSection extends StatelessWidget {
  final TextEditingController controller;
  final bool hasSavedName;
  final VoidCallback onClearName;
  final Function(String) onNameChanged;

  const PlayerNameSection({
    super.key,
    required this.controller,
    required this.hasSavedName,
    required this.onClearName,
    required this.onNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'Your Name',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Enter your name to start',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: const Icon(Icons.edit, color: Colors.blue),
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: onNameChanged,
                ),
              ),
              if (controller.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClearName,
                  icon: Icon(Icons.clear, color: Colors.grey[600]),
                  tooltip: 'Clear saved name',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Help text about names and rejoining
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasSavedName
                  ? Colors.green.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: hasSavedName
                      ? Colors.green.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                    hasSavedName ? Icons.check_circle : Icons.lightbulb_outline,
                    color: hasSavedName ? Colors.green : Colors.blue,
                    size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasSavedName
                        ? 'Your name "${controller.text}" is saved and will be remembered when you rejoin games'
                        : 'Tip: Your name is automatically saved and will be remembered when you rejoin games',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          hasSavedName ? Colors.green[700] : Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
