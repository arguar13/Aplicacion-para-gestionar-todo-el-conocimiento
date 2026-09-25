# El mapa en pantalla

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- temas de la pantalla: 2164 temas, 10000 elementos, 25000 vínculos
- abrir la pantalla, hasta ver el tablero (mapa + lecturas de la base): 808 ms
- pasar al esquema, hasta verlo dibujado: 699 ms
- arrastre sostenido en el esquema, ocho pasadas de 1,5 s, 562 cuadros. Armado: promedio 0.7 ms, p90 0.8, p99 1.1, peor 1.4. Raster: promedio 8.5 ms, p90 10.4, p99 16.3, peor 19.2. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 7 de raster (1.2 %). Recolecciones de memoria: 54 de la generación nueva y 2 de la vieja.
- pasar al grafo, hasta ver el panorama (49 nodos): 672 ms
- arrastre sostenido en el panorama, doce pasadas de 1,5 s, 778 cuadros. Armado: promedio 0.7 ms, p90 0.8, p99 1.0, peor 1.3. Raster: promedio 8.3 ms, p90 9.7, p99 11.6, peor 12.8. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 0 de raster (0.0 %). Recolecciones de memoria: 40 de la generación nueva y 2 de la vieja.
- acercar y alejar con dos dedos en el panorama, ocho gestos, 494 cuadros. Armado: promedio 0.5 ms, p90 0.8, p99 5.4, peor 7.8. Raster: promedio 13.1 ms, p90 21.4, p99 25.1, peor 31.6. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 179 de raster (36.2 %). Recolecciones de memoria: 12 de la generación nueva y 0 de la vieja.
- bajar a los temas de la comunidad mayor (300 nodos), hasta verlos: 327 ms
- arrastre sostenido en el nivel de temas, ocho pasadas de 1,5 s, 390 cuadros. Armado: promedio 0.7 ms, p90 0.9, p99 1.2, peor 1.3. Raster: promedio 15.4 ms, p90 18.4, p99 21.3, peor 30.1. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 125 de raster (32.1 %). Recolecciones de memoria: 216 de la generación nueva y 2 de la vieja.
- temas a la vista: 300; con elementos en la base: 291 (de 2078 en toda la bóveda)
- bajar a los elementos de un tema (5 nodos, lectura de la base incluida), hasta verlos: 759 ms
- arrastre sostenido en el nivel de elementos, ocho pasadas de 1,5 s, 523 cuadros. Armado: promedio 0.7 ms, p90 0.9, p99 1.2, peor 2.3. Raster: promedio 3.6 ms, p90 3.8, p99 29.6, peor 101.4. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 11 de raster (2.1 %). Recolecciones de memoria: 12 de la generación nueva y 0 de la vieja.
- arrastre sostenido en el panorama con el mapa recalculándose de fondo (10 escrituras en 18 s), 773 cuadros. Armado: promedio 0.9 ms, p90 0.9, p99 6.7, peor 25.7. Raster: promedio 9.4 ms, p90 11.2, p99 20.0, peor 51.8. Cuadros fuera del presupuesto: 3 de armado (0.4 %) y 26 de raster (3.4 %). Recolecciones de memoria: 118 de la generación nueva y 48 de la vieja.
- F18, 18.1, agrupando por sub-rama (profundidad 2): la comunidad mayor tiene 300 nodos, hasta verlos: 281 ms
- arrastre sostenido en el nivel de temas con sub-rama, ocho pasadas de 1,5 s, 491 cuadros. Armado: promedio 0.7 ms, p90 0.9, p99 1.1, peor 1.5. Raster: promedio 12.8 ms, p90 15.9, p99 21.4, peor 25.4. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 48 de raster (9.8 %). Recolecciones de memoria: 100 de la generación nueva y 2 de la vieja.
- memoria residente: 238 MB al empezar, 272 MB al terminar, 470 MB máxima
