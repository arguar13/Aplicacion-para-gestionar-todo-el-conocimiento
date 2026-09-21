# El mapa en pantalla

Equipo: escritorio Windows i5-10300H, enchufada

- temas de la pantalla: 2164 temas, 10000 elementos, 25000 vínculos
- abrir la pantalla, hasta ver el tablero (mapa + lecturas de la base): 694 ms
- pasar al esquema, hasta verlo dibujado: 435 ms
- arrastre sostenido en el esquema, ocho pasadas de 1,5 s, 585 cuadros. Armado: promedio 0.6 ms, p90 1.2, p99 1.5, peor 1.7. Raster: promedio 12.9 ms, p90 21.9, p99 30.5, peor 38.1. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 88 de raster (15.0 %). Recolecciones de memoria: 68 de la generación nueva y 0 de la vieja.
- pasar al grafo, hasta ver el panorama (49 nodos): 411 ms
- arrastre sostenido en el panorama, doce pasadas de 1,5 s, 908 cuadros. Armado: promedio 0.5 ms, p90 1.1, p99 1.5, peor 2.0. Raster: promedio 10.9 ms, p90 17.5, p99 27.7, peor 30.7. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 103 de raster (11.3 %). Recolecciones de memoria: 52 de la generación nueva y 2 de la vieja.
- acercar y alejar con dos dedos en el panorama, ocho gestos, 496 cuadros. Armado: promedio 0.4 ms, p90 0.5, p99 3.8, peor 15.6. Raster: promedio 11.4 ms, p90 19.9, p99 29.2, peor 29.7. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 60 de raster (12.1 %). Recolecciones de memoria: 14 de la generación nueva y 0 de la vieja.
- bajar a los temas de la comunidad mayor (300 nodos), hasta verlos: 307 ms
- arrastre sostenido en el nivel de temas, ocho pasadas de 1,5 s, 547 cuadros. Armado: promedio 0.2 ms, p90 0.2, p99 0.5, peor 0.6. Raster: promedio 20.9 ms, p90 21.9, p99 33.2, peor 41.3. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 547 de raster (100.0 %). Recolecciones de memoria: 10 de la generación nueva y 0 de la vieja.
- temas a la vista: 300; con elementos en la base: 291 (de 2078 en toda la bóveda)
- bajar a los elementos de un tema (18 nodos, lectura de la base incluida), hasta verlos: 711 ms
- arrastre sostenido en el nivel de elementos, ocho pasadas de 1,5 s, 588 cuadros. Armado: promedio 0.7 ms, p90 1.3, p99 1.7, peor 2.2. Raster: promedio 5.6 ms, p90 10.4, p99 15.6, peor 17.0. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 2 de raster (0.3 %). Recolecciones de memoria: 26 de la generación nueva y 4 de la vieja.
- arrastre sostenido en el panorama con el mapa recalculándose de fondo (10 escrituras en 18 s), 872 cuadros. Armado: promedio 0.7 ms, p90 1.2, p99 8.4, peor 11.3. Raster: promedio 11.1 ms, p90 17.7, p99 27.4, peor 30.4. Cuadros fuera del presupuesto: 0 de armado (0.0 %) y 103 de raster (11.8 %). Recolecciones de memoria: 146 de la generación nueva y 86 de la vieja.
- memoria residente: 267 MB al empezar, 319 MB al terminar, 428 MB máxima
