import subprocess
import os

ROUTERS = [
    {"name": "DGA4331 (TIM HUB+)", "ip": "192.0.2.6"},
    {"name": "DGA4132 (TIM HUB)",  "ip": "192.0.2.3"},
    {"name": "TG789vac v2",        "ip": "192.0.2.7"},
]

REPO_ROOT = os.environ.get("TCH_REPO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 1. Read files to upload
with open(os.path.join(REPO_ROOT, "scripts", "check_tags_hardware.sh"), "rb") as f:
    sh_bytes = f.read().replace(b"\r\n", b"\n")

with open(os.path.join(REPO_ROOT, "scripts", "test_agent_populated_hardware.lua"), "rb") as f:
    lua_bytes = f.read().replace(b"\r\n", b"\n")

f2g_1f = subprocess.check_output(["git", "show", "1f1cedfd:decompressed/gui_file/www/docroot/modals/agent-list-2g.lp"], cwd=REPO_ROOT)
f5g_1f = subprocess.check_output(["git", "show", "1f1cedfd:decompressed/gui_file/www/docroot/modals/agent-list-5g.lp"], cwd=REPO_ROOT)

def upload(ip, remote_path, data):
    p = subprocess.Popen(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", f"root@{ip}", f"cat > '{remote_path}'"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p.communicate(data)
    return p.returncode == 0

def run(ip, cmd):
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", f"root@{ip}", cmd],
                         capture_output=True, text=True, timeout=30)
    return res.stdout.strip()

for r in ROUTERS:
    ip = r["ip"]
    name = r["name"]
    print("=" * 90)
    print(f">>> RUNNING POPULATED BRANCH TEST ON HARDWARE: {name} [{ip}] <<<")
    print("=" * 90)
    upload(ip, "/tmp/check_tags.sh", sh_bytes)
    run(ip, "chmod +x /tmp/check_tags.sh")
    upload(ip, "/tmp/test_agent_populated.lua", lua_bytes)
    upload(ip, "/tmp/agent-list-2g-1f1cedfd.lp", f2g_1f)
    upload(ip, "/tmp/agent-list-5g-1f1cedfd.lp", f5g_1f)
    out = run(ip, "lua /tmp/test_agent_populated.lua")
    print(out)
    print()
