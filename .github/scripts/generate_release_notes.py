#!/usr/bin/env python3
import os, re


def extract_section(changelog_file, version):
    if not os.path.exists(changelog_file):
        return []
    with open(changelog_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    notes = []
    in_sec = False
    for line in lines:
        s = line.rstrip()
        if re.match(r'^\d+\.\d+(\.\d+)?$', s.strip()):
            if s.strip() == version or s.strip().startswith(version + '.'):
                in_sec = True; continue
            elif in_sec:
                break
        if not in_sec: continue
        if re.match(r'^--{5,}$', s.strip()): continue
        if not s.strip() and not notes: continue
        if s.strip():
            c = s.strip()
            if not c.startswith('-'): c = '- ' + c
            notes.append(c)
    return notes


def main():
    version  = os.environ.get('VERSION',  '9.7.9')
    full_ver = os.environ.get('FULL_VER', version)
    commit   = os.environ.get('SHORT_HASH', '')
    repo     = os.environ.get('GITHUB_REPOSITORY', 'ZioCook/tch-nginx-gui')

    notes = extract_section('CHANGELOG.md', version)
    if not notes:
        notes = ['- Aggiornamenti e miglioramenti']
    changelog_text = '\n'.join(notes)

    ls = [
        '## Technicolor Nginx GUI ' + full_ver,
        '',
        '> Fork personale di [Ansuel/tch-nginx-gui](https://github.com/Ansuel/tch-nginx-gui) ottimizzato per il TIM HUB (DGA4132) in modalita Bridge/AP.',
        '> Progetto ad uso personale - non vengono forniti supporto o feature su richiesta.',
        '',
        '---',
        '',
        '### Novita in ' + version,
        '',
        changelog_text,
        '',
        '---',
        '',
        '### Installazione rapida (via SSH sul modem)',
        '',
        '```bash',
        'curl -k -L https://github.com/' + repo + '/releases/latest/download/GUI_dev.tar.bz2 -o /tmp/GUI.tar.bz2',
        'bunzip2 -c /tmp/GUI.tar.bz2 | tar -x -C /',
        '/etc/init.d/nginx restart',
        '```',
       '',
        '---',
        '',
        '### File allegati',
        '',
        '| File | Descrizione |',
        '|------|-------------|',
        '| `GUI_dev.tar.bz2` | Pacchetto sviluppo (tar+bzip2) - consigliato per installazione su modem |',
        '| `GUI_dev.zip` | Pacchetto sviluppo (zip) - per ispezione su PC |',
        '| `GUI.tar.bz2` | Pacchetto stabile (tar+bzip2) |',
        '| `GUI.zip` | Pacchetto stabile (zip) |',
        '| `MD5SUMS` | Checksum MD5 |',
        '| `SHA256SUMS` | Checksum SHA-256 |',
        '',
        '---',
        '',
        'Commit: [' + commit + '](https://github.com/' + repo + '/commit/' + commit + ')  ',
        'Changelog: [CHANGELOG.md](https://github.com/' + repo + '/blob/master/CHANGELOG.md)',
    ]

    body = '\n'.join(ls) + '\n'
    with open('release_notes.md', 'w', encoding='utf-8') as out:
        out.write(body)
    print('=== RELEASE NOTES GENERATED ===')
    print(body)


if __name__ == '__main__':
    main()
