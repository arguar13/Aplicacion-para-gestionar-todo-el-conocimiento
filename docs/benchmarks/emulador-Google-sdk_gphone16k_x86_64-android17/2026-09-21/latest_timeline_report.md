# Línea de tiempo a escala

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- armar el árbol de intervalos de 10000 eventos: 5 ms
- mil ventanas de arrastre, consulta y carriles, sin dibujar: 83 ms (36179 eventos ubicados)
- abrir la pantalla con 10000 eventos, hasta verla: 371 ms
- barras en pantalla tras acercar: 100
- arrastre sostenido, doce pasadas de 1,5 s, 528 cuadros. Armado: promedio 6.0 ms, p90 10.7, p99 37.6, peor 43.6. Raster: promedio 11.7 ms, p90 23.1, p99 30.2, peor 35.1. Cuadros fuera del presupuesto: 38 de armado y 123 de raster. Recolecciones de memoria: 94 de la generación nueva y 8 de la vieja.
- memoria residente: 162 MB al empezar, 203 MB al terminar, 326 MB máxima
