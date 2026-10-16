"""Ejecutor de mutaciones: python mutar.py <mutaciones.json>

El JSON es una lista de {"archivo", "viejo", "nuevo", "pruebas", "nombre"}.
Por cada una: comprueba que `viejo` aparece EXACTAMENTE una vez (si no, la
mutación está mal armada y se informa sin correr nada), la aplica, corre
`flutter test <pruebas>`, cuenta las pruebas que fallan y restaura el archivo
siempre (también si algo se corta). Una mutación que no hace fallar ninguna
prueba se informa como SOBREVIVIÓ."""
import io
import json
import re
import subprocess
import sys

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace('\', '/')

mutations = json.load(io.open(sys.argv[1], encoding='utf-8'))
results = []
for m in mutations:
    path = ROOT + '/' + m['archivo']
    original = io.open(path, encoding='utf-8', newline='').read()
    old = m['viejo'].replace('\n', '\r\n') if '\r\n' in original else m['viejo']
    new = m['nuevo'].replace('\n', '\r\n') if '\r\n' in original else m['nuevo']
    count = original.count(old)
    if count != 1:
        results.append((m['nombre'], f'MAL ARMADA: aparece {count} veces'))
        continue
    try:
        io.open(path, 'w', encoding='utf-8', newline='').write(original.replace(old, new))
        applied = io.open(path, encoding='utf-8', newline='').read()
        assert applied != original and new in applied, 'no se aplicó'
        proc = subprocess.run(
            ['flutter', 'test', *m['pruebas'], '--timeout', '60s'],
            cwd=ROOT, capture_output=True, text=True, encoding='utf-8',
            errors='replace', timeout=900, shell=True)
        out = proc.stdout + proc.stderr
        failed = len(set(re.findall(r'^\d\d:\d\d \+\d+(?: ~\d+)? -\d+: (.*) \[E\]$', out, re.M)))
        compile_error = 'Error: ' in out and failed == 0 and proc.returncode != 0
        if compile_error:
            results.append((m['nombre'], 'NO COMPILA (mutación inválida)'))
        elif failed == 0:
            results.append((m['nombre'], 'SOBREVIVIÓ'))
        else:
            results.append((m['nombre'], f'muerta ({failed} pruebas fallan)'))
    finally:
        io.open(path, 'w', encoding='utf-8', newline='').write(original)
        assert io.open(path, encoding='utf-8', newline='').read() == original

for name, verdict in results:
    print(f'{verdict:40}  {name}')
