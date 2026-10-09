"""Une dos versiones de un .arb: el texto de HEAD tal cual, más las claves de
CHERRY_PICK_HEAD que HEAD no tiene, insertadas como texto antes del `}` final.
Nunca carga y vuelca el JSON (reformatearía todo).

Cuándo: al integrar con `git cherry-pick` el trabajo de un agente y chocan
`lib/l10n/app_es.arb` / `app_en.arb` (los dos lados agregaron claves al final y git
las alineó a medias, con varios bloques de choque entrelazados). Con el
cherry-pick detenido por el choque, desde la raíz del repo:

    python tool/arb_union.py lib/l10n/app_es.arb lib/l10n/app_en.arb
    git add lib/l10n/*.arb && GIT_EDITOR=true git cherry-pick --continue

Falla en voz alta si el resultado no es JSON válido o si falta alguna clave de
cualquiera de los dos lados."""
import io, json, re, subprocess, sys

def git_show(rev, path):
    return subprocess.run(['git', 'show', f'{rev}:{path}'], capture_output=True,
                          check=True).stdout.decode('utf-8')

def blocks(text):
    """Las entradas de primer nivel, en orden: (clave, texto sin la coma final)."""
    lines = text.split('\n')
    starts = [i for i, l in enumerate(lines) if re.match(r'^  "', l)]
    end = max(i for i, l in enumerate(lines) if l.rstrip() == '}')
    out = []
    for n, i in enumerate(starts):
        j = starts[n + 1] if n + 1 < len(starts) else end
        chunk = '\n'.join(lines[i:j]).rstrip()
        chunk = chunk[:-1] if chunk.endswith(',') else chunk
        key = re.match(r'^  "([^"]+)"', lines[i]).group(1)
        out.append((key, chunk))
    return out

for path in sys.argv[1:]:
    ours = git_show('HEAD', path)
    theirs = git_show('CHERRY_PICK_HEAD', path)
    have = {k for k, _ in blocks(ours)}
    extra = [(k, b) for k, b in blocks(theirs) if k not in have]
    # Una clave y su `@clave` viajan juntas: ninguna a medias.
    keys = {k for k, _ in extra}
    for k in keys:
        pair = k[1:] if k.startswith('@') else '@' + k
        assert pair in keys or pair in have or pair not in {x for x, _ in blocks(theirs)}, (path, k)
    body = ours.rstrip()
    assert body.endswith('}')
    body = body[:-1].rstrip()
    merged = body + (',\n' if extra else '') + ',\n'.join(b for _, b in extra) + '\n}\n'
    json.loads(merged)
    # Cada clave de las dos versiones tiene que estar.
    final = set(json.loads(merged)); both = set(json.loads(ours)) | set(json.loads(theirs))
    assert final == both, (path, sorted(both - final)[:5])
    io.open(path, 'w', encoding='utf-8', newline='').write(merged)
    print(path, 'ok:', len(extra), 'bloques agregados')
