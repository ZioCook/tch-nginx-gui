import requests
import sys
import os

router_user = os.environ.get("ROUTER_USER")
router_pass = os.environ.get("ROUTER_PASS")
if not router_user:
    sys.stderr.write("Error: Missing required environment variable ROUTER_USER\n")
    sys.exit(1)
if not router_pass:
    sys.stderr.write("Error: Missing required environment variable ROUTER_PASS\n")
    sys.exit(1)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from srp_client import srp_login

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac v2", "192.0.2.7")
]

if len(sys.argv) > 1:
    target = sys.argv[1]
    filtered = [r for r in routers if target in (r[0], r[1])]
    if not filtered:
        sys.stderr.write(f"Error: Router '{target}' not found in router list\n")
        sys.exit(2)
    routers = filtered

login_failed = False
for name, ip in routers:
    s = requests.Session()
    ok, msg, session = srp_login(ip, router_user, router_pass, session=s)
    if not ok:
        sys.stderr.write(f"Error: Login failed for {name} ({ip}): {msg}\n")
        login_failed = True
        continue
    for ep in ["/modals/agent-list-2g.lp", "/modals/agent-list-5g.lp"]:
        r = s.get(f"http://{ip}{ep}", timeout=10)
        c = r.text.count("No extenders are connected")
        print(f"{name:<12} {ep:<26} -> HTTP {r.status_code}, count('No extenders are connected') = {c}")

if login_failed:
    sys.exit(1)
