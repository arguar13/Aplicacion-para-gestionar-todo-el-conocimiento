# Reglas de R8 para la versión release. El plugin de Flutter para Gradle
# incluye este archivo solo, por su nombre.

# `google_mlkit_text_recognition` puede crear reconocedores de chino,
# devanagari, japonés y coreano, pero cada uno viene en su propia
# dependencia, y la app usa solo el latino (MlKitImageTextExtractor): esas
# clases no están, a propósito. Sin esto R8 frena la versión release por
# "clases que faltan" que nunca se usan. Es la regla que el propio plugin
# indica.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
