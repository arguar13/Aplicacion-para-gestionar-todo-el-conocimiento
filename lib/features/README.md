# Convención de features

Cada carpeta dentro de `features/` es un módulo autocontenido con tres capas.
La regla de dependencia es siempre hacia adentro: `presentation` → `domain` ←
`data`. `domain` no importa nada de `data` ni de `presentation`.

```
features/<nombre_feature>/
├── data/
│   ├── datasources/     # Fuentes concretas: REST (dio), local (secure storage)...
│   ├── dtos/             # Modelos freezed + json_serializable, mapean JSON <-> dominio
│   └── repositories/     # Implementa la interfaz definida en domain/repositories
├── domain/
│   ├── entities/          # Objetos de negocio puros (freezed), sin dependencias de Flutter
│   ├── repositories/      # Interfaces (contratos) que data/ implementa
│   └── usecases/          # Un caso de uso = una acción de negocio (implementa UseCase)
└── presentation/
    ├── providers/         # Riverpod: exponen estado y casos de uso a la UI
    ├── screens/            # Páginas registradas en app/router/app_router.dart
    └── widgets/            # Widgets reutilizables dentro del feature
```

Al crear un feature nuevo:

1. Definir las `entities` y el contrato de `repositories` en `domain/`.
2. Implementar el `repository` en `data/`, devolviendo `Either<Failure, T>`
   (ver `core/usecase/usecase.dart` y `core/error/failures.dart`).
3. Exponer los `usecases` vía un provider en `presentation/providers/`.
4. Registrar las rutas del feature en `app/router/app_router.dart`.
