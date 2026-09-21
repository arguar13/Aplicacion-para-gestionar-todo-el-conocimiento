# Línea de tiempo a escala

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- armar el árbol de intervalos de 10000 eventos: 8 ms
- mil ventanas de arrastre, consulta y carriles, sin dibujar: 115 ms (36179 eventos ubicados)
- abrir la pantalla con 10000 eventos, hasta verla: 483 ms
- barras en pantalla tras acercar: 100
- arrastre sostenido, doce pasadas de 1,5 s, 268 cuadros. Armado: promedio 17.3 ms, p90 38.3, p99 69.6, peor 117.7. Raster: promedio 30.8 ms, p90 58.9, p99 80.5, peor 136.6. Cuadros fuera del presupuesto: 108 de armado y 210 de raster. Recolecciones de memoria: 62 de la generación nueva y 4 de la vieja.
- memoria residente: 174 MB al empezar, 215 MB al terminar, 331 MB máxima
