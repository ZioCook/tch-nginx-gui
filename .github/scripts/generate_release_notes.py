#!/usr/bin/env python3
import os
import re

def main():
    version = os.environ.get("VERSION", "9.7.9")
    full_ver = os.environ.get("FULL_VER", version)
    commit = os.environ.get("SHORT_HASH", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "ZioCook/tch-nginx-gui")

    changelog_notes = []
    changelog_file = "CHANGELOG.md"

    if os.path.exists(changelog_file):
        try:
            with open(changelog_file, "r", encoding="utf-8") as f:
                lines = f.readlines()

            in_ver = False
            for line in lines:
                s = line.strip()
                if s == version or s.startswith(version):
                    in_ver = True
                    continue
                if in_ver:
                    # Stop when encountering next version header (e.g. 9.7.8) or mainline header
                    if (re.match(r"^[0-9]+\.[0-9]+", s) and not s.startswith(version)) or s.startswith("# Mainline"):
                        if len(changelog_notes) > 1:
                            break
                    if not s.startswith("---") and s:
                        changelog_notes.append(s)
        except Exception as e:
            changelog_notes = [f"- Modifiche e correzioni da commit {commit}"]

    if not changelog_notes:
        changelog_notes = [f"- Aggiornamenti e miglioramenti da commit {commit}"]

    changelog_text = "\n".join(changelog_notes)

    body = f"""## 🚀 Technicolor Nginx GUI - Release {full_ver}

### 📝 Changelog per {version}
{changelog_text}

---

### 📦 Installazione Rapida (via SSH sul modem)
```bash
curl -k -L https://raw.githubusercontent.com/{repo}/master/compressed/GUI_dev.tar.bz2 --output /tmp/GUI.tar.bz2
bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
/etc/init.d/rootdevice force
```

### 📁 File Disponibili nel Rilascio
- **`GUI_dev.zip`** & **`GUI_dev.tar.bz2`**: Pacchetto di sviluppo con tutte le ultime funzionalità e fix.
- **`GUI.zip`** & **`GUI.tar.bz2`**: Pacchetto stabile.
- **`MD5SUMS`** & **`SHA256SUMS`**: Checksum di integrità crittografica per la verifica dei download.
"""

    with open("release_notes.md", "w", encoding="utf-8") as out:
        out.write(body)

    print("=== RELEASE NOTES GENERATED ===")
    print(body)

if __name__ == "__main__":
    main()
