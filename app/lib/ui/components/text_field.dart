import 'package:flutter/material.dart';

class MessieTextField extends StatelessWidget {
  final String? label;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  const MessieTextField({super.key, this.label, this.obscureText = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

