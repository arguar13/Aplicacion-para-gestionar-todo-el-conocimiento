# Flavors de iOS — estado y pasos pendientes

## Qué hay acá

Los tres `.xcconfig` de esta carpeta definen, para cada flavor, las dos
cosas que lo distinguen:

| Flavor    | `FLAVOR_BUNDLE_ID_SUFFIX` | `APP_DISPLAY_NAME`  | Bundle id resultante |
|-----------|---------------------------|---------------------|----------------------|
| `dev`     | `.dev`                    | `Sinapsis Dev`      | `app.sinapsis.dev`     |
| `staging` | `.staging`                | `Sinapsis Staging`  | `app.sinapsis.staging` |
| `prod`    | *(ninguno)*               | `Sinapsis`          | `app.sinapsis`         |

Son los mismos valores que `android/app/build.gradle.kts` define en sus
`productFlavors` y que los entry points de Dart (`lib/main_dev.dart`,
`main_staging.dart`, `main_prod.dart`) eligen vía `AppFlavor`. Las tres
definiciones tienen que contar la misma historia; si cambia una, cambian
las tres.

## Qué falta, y por qué

Estos archivos por sí solos no hacen nada todavía: Xcode no los lee hasta
que existan *build configurations* que los incluyan y *schemes* que
seleccionen esas configuraciones. Y ese cableado vive dentro de
`Runner.xcodeproj/project.pbxproj`.

Ese archivo **no se editó a mano y a propósito**. `project.pbxproj` es un
grafo de objetos con referencias cruzadas por UUID; escribirlo sin Xcode y
sin poder abrir el proyecto para comprobar que sigue siendo válido es la
forma habitual de romper el build de iOS de un modo que no se nota hasta
que alguien intenta compilar en un Mac. El entorno donde se preparó esta
configuración es Linux, sin Xcode.

Android sí quedó completo y verificado: el workflow de CI compila los tres
flavors en cada push (job `build-android`).

## Pasos para terminarlo (requiere un Mac con Xcode)

1. Abrir `ios/Runner.xcworkspace` (el *workspace*, no el `.xcodeproj`).

2. **Build configurations.** Seleccionar el proyecto `Runner` → pestaña
   *Info* → sección *Configurations*. Duplicar las tres existentes
   (`Debug`, `Release`, `Profile`) una vez por flavor, hasta tener nueve:

   ```
   Debug-dev      Release-dev      Profile-dev
   Debug-staging  Release-staging  Profile-staging
   Debug-prod     Release-prod     Profile-prod
   ```

3. **Archivos de configuración.** Crear, al lado de `Debug.xcconfig`, un
   archivo por cada configuración nueva. Cada uno son dos líneas — el
   `Generated.xcconfig` que escribe la herramienta de Flutter, más el
   flavor:

   ```
   // ios/Flutter/Debug-dev.xcconfig
   #include "Generated.xcconfig"
   #include "flavors/dev.xcconfig"
   ```

   Y asignarlo a su configuración en la columna del target `Runner`.

4. **Bundle identifier por flavor.** En *Build Settings* del target
   `Runner`, reemplazar el valor fijo de `PRODUCT_BUNDLE_IDENTIFIER` por:

   ```
   app.sinapsis$(FLAVOR_BUNDLE_ID_SUFFIX)
   ```

   Con el sufijo vacío en `prod`, eso da `app.sinapsis` — el identificador
   de publicación, que no puede cambiar nunca.

5. **Nombre visible.** En `ios/Runner/Info.plist`, cambiar el valor de
   `CFBundleDisplayName` de `Sinapsis` a:

   ```xml
   <string>$(APP_DISPLAY_NAME)</string>
   ```

6. **Schemes.** *Product → Scheme → Manage Schemes…*: crear un scheme por
   flavor (`dev`, `staging`, `prod`), y en cada uno asignar las
   configuraciones que le corresponden (Run → `Debug-<flavor>`, Profile →
   `Profile-<flavor>`, Archive → `Release-<flavor>`). Marcarlos como
   *shared* para que queden versionados en
   `xcshareddata/xcschemes/` y no solo en la máquina de quien los creó.

## Verificación

```bash
flutter run   --flavor dev  -t lib/main_dev.dart
flutter build ipa --flavor prod -t lib/main_prod.dart
```

Con los tres schemes instalados, las tres apps conviven en el mismo
dispositivo con nombres e íconos distintos. Ese es el punto de todo esto:
poder tener dev y producción en el mismo teléfono sin que una pise a la
otra.

Conviene además agregar el build de iOS al CI (`macos-latest`), igual que
ya está el de Android, para que la configuración quede verificada de forma
automática y no dependa de que alguien se acuerde de probarla.
