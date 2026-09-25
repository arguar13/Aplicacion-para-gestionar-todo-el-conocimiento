# El mapa en pantalla

Equipo: EMULADOR Google sdk_gphone16k_x86_64, Android 17 (API 37), ranchu, 3.8 GB de RAM

- temas de la pantalla: 2164 temas, 10000 elementos, 25000 vínculos
- abrir la pantalla, hasta ver el tablero (mapa + lecturas de la base): 810 ms
- pasar al esquema, hasta verlo dibujado: 717 ms
- arrastre sostenido en el esquema, ocho pasadas de 1,5 s, 567 cuadros. Armado: promedio 0.7 ms, p90 0.8, p99 1.1, peor 4.8. Raster: promedio 9.3 ms, p90 11.2, p99 16.3, peor 23.6. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 7 de raster (1.2 %). Recolecciones de memoria: 54 de la generación nueva y 0 de la vieja.
- pasar al grafo, hasta ver el panorama (49 nodos): 685 ms
- arrastre sostenido en el panorama, doce pasadas de 1,5 s, 890 cuadros. Armado: promedio 0.8 ms, p90 0.9, p99 5.0, peor 8.3. Raster: promedio 4.8 ms, p90 15.1, p99 35.7, peor 81.2. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 71 de raster (8.0 %). Recolecciones de memoria: 22 de la generación nueva y 6 de la vieja.
- acercar y alejar con dos dedos en el panorama, ocho gestos, 490 cuadros. Armado: promedio 0.6 ms, p90 0.8, p99 7.7, peor 9.7. Raster: promedio 5.5 ms, p90 10.5, p99 41.6, peor 89.4. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 32 de raster (6.5 %). Recolecciones de memoria: 10 de la generación nueva y 4 de la vieja.
- bajar a los temas de la comunidad mayor (300 nodos), hasta verlos: 343 ms
- arrastre sostenido en el nivel de temas, ocho pasadas de 1,5 s, 520 cuadros. Armado: promedio 1.2 ms, p90 1.0, p99 29.0, peor 41.1. Raster: promedio 7.3 ms, p90 17.0, p99 56.3, peor 161.8. Cuadros fuera del presupuesto: 7 de armado (1.3 %) y 94 de raster (18.1 %). Recolecciones de memoria: 40 de la generación nueva y 16 de la vieja.
- temas a la vista: 300; con elementos en la base: 291 (de 2078 en toda la bóveda)
- bajar a los elementos de un tema (5 nodos, lectura de la base incluida), hasta verlos: 742 ms
- arrastre sostenido en el nivel de elementos, ocho pasadas de 1,5 s, 572 cuadros. Armado: promedio 0.8 ms, p90 0.9, p99 1.7, peor 3.5. Raster: promedio 3.3 ms, p90 3.6, p99 25.6, peor 45.3. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 11 de raster (1.9 %). Recolecciones de memoria: 10 de la generación nueva y 0 de la vieja.
- arrastre sostenido en el panorama con el mapa recalculándose de fondo (10 escrituras en 18 s), 823 cuadros. Armado: promedio 1.0 ms, p90 1.0, p99 6.9, peor 34.6. Raster: promedio 4.6 ms, p90 10.4, p99 30.6, peor 110.8. Cuadros fuera del presupuesto: 2 de armado (0.2 %) y 57 de raster (6.9 %). Recolecciones de memoria: 92 de la generación nueva y 46 de la vieja.
- F18, 18.1, agrupando por sub-rama (profundidad 2): la comunidad mayor tiene 300 nodos, hasta verlos: 321 ms
- arrastre sostenido en el nivel de temas con sub-rama, ocho pasadas de 1,5 s, 553 cuadros. Armado: promedio 1.1 ms, p90 0.9, p99 25.7, peor 37.6. Raster: promedio 4.9 ms, p90 14.7, p99 43.0, peor 94.1. Cuadros fuera del presupuesto: 7 de armado (1.3 %) y 39 de raster (7.1 %). Recolecciones de memoria: 34 de la generación nueva y 16 de la vieja.
- memoria residente: 238 MB al empezar, 273 MB al terminar, 469 MB máxima
