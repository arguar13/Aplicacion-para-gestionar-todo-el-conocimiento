"""Inserta claves nuevas en un .arb como TEXTO antes del `}` final, sin cargar y
volcar el JSON (reformatearía todo). Uso: python arb_agregar.py <archivo.arb>
<archivo_de_bloques.txt>. Valida que el resultado sea JSON y que las claves no
existan ya."""
import io
import json
import sys

arb, bloques = sys.argv[1], sys.argv[2]
s = io.open(arb, encoding='utf-8').read()
nuevo = io.open(bloques, encoding='utf-8').read().strip('\n')
existentes = set(json.loads(s))
agregadas = set(json.loads('{' + nuevo + '}'))
repetidas = existentes & agregadas
assert not repetidas, f'ya existen: {sorted(repetidas)}'
cuerpo = s.rstrip()
assert cuerpo.endswith('}')
cuerpo = cuerpo[:-1].rstrip()
resultado = cuerpo + ',\n' + nuevo + '\n}\n'
json.loads(resultado)
io.open(arb, 'w', encoding='utf-8', newline='').write(resultado)
print(arb, 'ok:', len(agregadas), 'claves')
