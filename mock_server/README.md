# Mock server (json-server)

Backend local para el flavor `dev`. Simula `/login` y `/user` contra
`db.json`.

```bash
cd mock_server
npm install
npm start
```

Sirve en `http://localhost:3000`. La app (flavor `dev`) ya apunta ahí por
defecto (ver `lib/core/config/platform_base_url.dart`):
Android emulator usa `http://10.0.2.2:3000`, iOS/Web/desktop usan
`http://localhost:3000`.

Usuarios de prueba (`db.json`):

| email               | password  |
|---------------------|-----------|
| ana@example.com     | secret123 |
| carlos@example.com  | hunter2   |

- `POST /login` con `{ "email", "password" }` → `200 { token, user }` o
  `401` si no coinciden.
- `GET /user` con header `Authorization: Bearer <token>` → `200 <user>` o
  `401` si el token falta o no viene de un login reciente (reiniciar el
  server invalida todos los tokens — es la forma más simple de simular una
  sesión expirada).

Para probar en un dispositivo físico (no emulador/simulador), el mock
server debe escuchar en la IP LAN de la máquina y la app debe apuntar ahí
con `--dart-define=API_BASE_URL=http://<tu-ip-lan>:3000`.
