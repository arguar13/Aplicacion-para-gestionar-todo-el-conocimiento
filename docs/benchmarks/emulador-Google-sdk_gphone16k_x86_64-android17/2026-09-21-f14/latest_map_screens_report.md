# El mapa en pantalla

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- temas de la pantalla: 2164 temas, 10000 elementos, 25000 vínculos
- abrir la pantalla, hasta ver el tablero (mapa + lecturas de la base): 1019 ms
- pasar al esquema, hasta verlo dibujado: 784 ms
- arrastre sostenido en el esquema, ocho pasadas de 1,5 s, 438 cuadros. Armado: promedio 0.8 ms, p90 1.3, p99 3.5, peor 4.5. Raster: promedio 11.2 ms, p90 18.0, p99 41.4, peor 45.5. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 57 de raster (13.0 %). Recolecciones de memoria: 42 de la generación nueva y 2 de la vieja.
- pasar al grafo, hasta ver el panorama (49 nodos): 671 ms
- arrastre sostenido en el panorama, doce pasadas de 1,5 s, 683 cuadros. Armado: promedio 1.0 ms, p90 1.9, p99 4.2, peor 6.8. Raster: promedio 12.0 ms, p90 19.5, p99 43.2, peor 50.9. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 114 de raster (16.7 %). Recolecciones de memoria: 34 de la generación nueva y 2 de la vieja.
- acercar y alejar con dos dedos en el panorama, ocho gestos, 494 cuadros. Armado: promedio 0.6 ms, p90 0.9, p99 6.0, peor 8.2. Raster: promedio 16.1 ms, p90 24.1, p99 47.6, peor 70.9. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 212 de raster (42.9 %). Recolecciones de memoria: 12 de la generación nueva y 2 de la vieja.
- bajar a los temas de la comunidad mayor (300 nodos), hasta verlos: 329 ms
- arrastre sostenido en el nivel de temas, ocho pasadas de 1,5 s, 297 cuadros. Armado: promedio 1.5 ms, p90 3.5, p99 6.7, peor 8.2. Raster: promedio 22.2 ms, p90 38.9, p99 60.9, peor 78.1. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 182 de raster (61.3 %). Recolecciones de memoria: 178 de la generación nueva y 2 de la vieja.
- temas a la vista: 300; con elementos en la base: 291 (de 2078 en toda la bóveda)
- bajar a los elementos de un tema (5 nodos, lectura de la base incluida), hasta verlos: 810 ms
- arrastre sostenido en el nivel de elementos, ocho pasadas de 1,5 s, 468 cuadros. Armado: promedio 1.1 ms, p90 1.9, p99 4.2, peor 9.9. Raster: promedio 5.3 ms, p90 9.0, p99 26.3, peor 48.6. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 22 de raster (4.7 %). Recolecciones de memoria: 10 de la generación nueva y 0 de la vieja.
- arrastre sostenido en el panorama con el mapa recalculándose de fondo (10 escrituras en 18 s), 662 cuadros. Armado: promedio 1.2 ms, p90 2.1, p99 9.8, peor 24.6. Raster: promedio 12.3 ms, p90 18.5, p99 44.6, peor 51.2. Cuadros fuera del presupuesto: 4 de armado (0.6 %) y 102 de raster (15.4 %). Recolecciones de memoria: 116 de la generación nueva y 44 de la vieja.
- memoria residente: 191 MB al empezar, 230 MB al terminar, 418 MB máxima
