import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    required this.label,
    required this.controller,
    required this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      // Solo `labelText`: todo lo demás (bordes, radio, relleno, colores de
      // foco y de error) sale del `inputDecorationTheme` de AppTheme. Un
      // `border:` explícito acá —aunque sea un `OutlineInputBorder()` a
      // secas— gana sobre el tema y se lleva puesta la configuración
      // completa: InputDecoration.applyDefaults solo rellena los campos que
      // están en null, así que fijar uno lo saca de la jerarquía del tema.
      // Eso devolvía el radio por defecto de Material (4) en vez del de la
      // app (12) y un borde negro en vez de colorScheme.outline.
      decoration: InputDecoration(labelText: label),
    );
  }
}
