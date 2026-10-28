import 'package:flutter/material.dart';
import '../app_ui.dart';

Widget sourceField(
  BuildContext context,
  String label,
  TextEditingController controller, {
  int lines = 1,
  bool readOnly = false,
  bool autofocus = false,
  bool obscure = false,
  Iterable<String>? autofillHints,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  TextInputAction? textInputAction,
  String? hint,
  String? error,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LiquidGlass(
        radius: 16,
        elevated: false,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          readOnly: readOnly,
          obscureText: obscure,
          maxLines: obscure ? 1 : lines,
          minLines: obscure ? 1 : lines,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.all(14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    ],
  ),
);
