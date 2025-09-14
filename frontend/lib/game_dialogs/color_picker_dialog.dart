import 'package:flutter/material.dart';

class ColorPickerDialog extends StatelessWidget {
  const ColorPickerDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ColorPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a Color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            title: const Text('Red'),
            onTap: () => Navigator.of(context).pop('red'),
          ),
          ListTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            title: const Text('Blue'),
            onTap: () => Navigator.of(context).pop('blue'),
          ),
          ListTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            title: const Text('Green'),
            onTap: () => Navigator.of(context).pop('green'),
          ),
          ListTile(
            leading: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            title: const Text('Yellow'),
            onTap: () => Navigator.of(context).pop('yellow'),
          ),
        ],
      ),
    );
  }
}
