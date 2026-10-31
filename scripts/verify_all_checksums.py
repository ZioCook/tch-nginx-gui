import subprocess
import hashlib
import os

REPO_ROOT = os.environ.get("TCH_REPO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUI_DIR = os.path.join(REPO_ROOT, "decompressed", "gui_file")
if not os.path.isdir(GUI_DIR):
    raise SystemExit("[FATAL] GUI_DIR not found: " + GUI_DIR)
ROUTERS = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

local_hashes = {}
for root, dirs, files in os.walk(GUI_DIR):
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, GUI_DIR).replace("\\", "/")
        with open(full, "rb") as fh:
            local_hashes[rel] = hashlib.sha256(fh.read()).hexdigest()

manifest = "\n".join([f"{h}  /{p}" for p, h in local_hashes.items()]).replace("\r", "") + "\n"

for name, ip in ROUTERS:
    # Upload manifest and verify with sha256sum
    proc = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "tr -d '\\r' > /tmp/manifest.txt && sha256sum -c /tmp/manifest.txt 2>&1 | grep -v ': OK' ; rm -f /tmp/manifest.txt"],
                          input=manifest.encode('utf-8'), capture_output=True)
    mismatches = proc.stdout.decode('utf-8', errors='ignore').strip().splitlines()
    err_lines = [l for l in mismatches if l.strip() and not "OK" in l]
    print(f"[{name}] ({ip}): {len(local_hashes)} files checked, {len(err_lines)} mismatches.")
    if err_lines:
        print("  Mismatches:", err_lines[:5])
