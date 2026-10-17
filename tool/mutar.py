"""Ejecutor de mutaciones: python mutar.py <mutaciones.json>

El JSON es una lista de {"archivo", "viejo", "nuevo", "pruebas", "nombre"}
(y opcional "minutos": cuánto puede tardar, 10 si no está).
Por cada una: comprueba que `viejo` aparece EXACTAMENTE una vez (si no, la
mutación está mal armada y se informa sin correr nada), la aplica, corre
`flutter test <pruebas>`, cuenta las pruebas que fallan y restaura el archivo
siempre (también si algo se corta). Una mutación que no hace fallar ninguna
prueba se informa como SOBREVIVIÓ.

Una mutación puede colgar las pruebas —un bucle que no suelta nunca el hilo
no deja vencer ni el `--timeout` de `flutter test`—: pasado su tiempo se mata
el árbol entero de procesos (con `shell=True`, matar solo el primero deja
vivos a `dart` y `flutter_tester`, que retienen la salida y traban la espera
para siempre) y cuenta como muerta: con ella las pruebas no pasan.

Cada resultado se imprime apenas está, para poder seguir el avance."""
import io
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(os.sep, '/')


def kill_tree(proc):
    """Mata [proc] y todo lo que lanzó."""
    if os.name == 'nt':
        subprocess.run(['taskkill', '/T', '/F', '/PID', str(proc.pid)],
                       capture_output=True)
    else:
        os.killpg(proc.pid, 9)
    proc.wait()


def run_tests(tests, minutes):
    """Corre [tests]; devuelve (salida, código, si se colgó)."""
    with tempfile.TemporaryFile(mode='w+', encoding='utf-8', errors='replace') as log:
        proc = subprocess.Popen(
            ['flutter', 'test', *tests, '--timeout', '60s'],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, shell=True,
            start_new_session=os.name != 'nt')
        hung = False
        try:
            proc.wait(timeout=minutes * 60)
        except subprocess.TimeoutExpired:
            hung = True
            kill_tree(proc)
        log.seek(0)
        return log.read(), proc.returncode, hung


mutations = json.load(io.open(sys.argv[1], encoding='utf-8'))
for m in mutations:
    path = ROOT + '/' + m['archivo']
    original = io.open(path, encoding='utf-8', newline='').read()
    old = m['viejo'].replace('\n', '\r\n') if '\r\n' in original else m['viejo']
    new = m['nuevo'].replace('\n', '\r\n') if '\r\n' in original else m['nuevo']
    count = original.count(old)
    if count != 1:
        print(f'{"MAL ARMADA: aparece " + str(count) + " veces":40}  {m["nombre"]}', flush=True)
        continue
    try:
        io.open(path, 'w', encoding='utf-8', newline='').write(original.replace(old, new))
        applied = io.open(path, encoding='utf-8', newline='').read()
        assert applied != original and new in applied, 'no se aplicó'
        out, code, hung = run_tests(m['pruebas'], m.get('minutos', 10))
        failed = len(set(re.findall(r'^\d\d:\d\d \+\d+(?: ~\d+)? -\d+: (.*) \[E\]$', out, re.M)))
        compile_error = 'Error: ' in out and failed == 0 and code != 0 and not hung
        if hung:
            verdict = 'muerta (las pruebas se colgaron)'
        elif compile_error:
            verdict = 'NO COMPILA (mutación inválida)'
        elif failed == 0:
            verdict = 'SOBREVIVIÓ'
        else:
            verdict = f'muerta ({failed} pruebas fallan)'
    finally:
        io.open(path, 'w', encoding='utf-8', newline='').write(original)
        assert io.open(path, encoding='utf-8', newline='').read() == original
    print(f'{verdict:40}  {m["nombre"]}', flush=True)
