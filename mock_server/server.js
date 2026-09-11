// Mock backend local sobre json-server. json-server por sí solo solo sirve
// colecciones REST genéricas (no valida password ni protege rutas), así que
// esta capa fina de Express agrega:
//   - POST /login   -> valida contra db.json, devuelve { token, user }
//   - GET  /user    -> exige "Authorization: Bearer <token>" de un login
//                      previo; 401 si falta o no es válido
//
// Correr: npm install && npm start   (ver README.md de esta carpeta)
const jsonServer = require('json-server');

const server = jsonServer.create();
const router = jsonServer.router('db.json');
const middlewares = jsonServer.defaults();

const PORT = process.env.PORT || 3000;

// Tokens válidos solo mientras el proceso está vivo: reiniciar el server
// es la forma más simple de simular "el token expiró" para probar el
// interceptor de 401 sin tener que esperar una expiración real.
const sessions = new Map();

function publicUser(user) {
  const { password, ...rest } = user;
  return rest;
}

server.use(middlewares);
server.use(jsonServer.bodyParser);

server.post('/login', (req, res) => {
  const { email, password } = req.body || {};
  const user = router.db.get('users').find({ email, password }).value();

  if (!user) {
    res.status(401).json({ message: 'Correo o contraseña incorrectos.' });
    return;
  }

  const token = `mock-token-${user.id}-${Date.now()}`;
  sessions.set(token, user.id);
  res.json({ token, user: publicUser(user) });
});

server.get('/user', (req, res) => {
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  const userId = token ? sessions.get(token) : undefined;

  if (!userId) {
    res.status(401).json({ message: 'Tu sesión expiró. Inicia sesión de nuevo.' });
    return;
  }

  const user = router.db.get('users').find({ id: userId }).value();
  res.json(publicUser(user));
});

server.use(router);

server.listen(PORT, () => {
  console.log(`Mock server escuchando en http://localhost:${PORT}`);
  console.log('Usuario de prueba: ana@example.com / secret123');
});
