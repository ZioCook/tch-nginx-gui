import subprocess
import re
import requests
import json

ROUTERS = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

def main():
    for name, ip in ROUTERS:
        print(f"\n=======================================================")
        print(f"[*] AUDITING ALL GUEST-ACCESSIBLE RULES ON {name} ({ip})")
        print(f"=======================================================")
        
        res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "uci show web"],
                             capture_output=True, text=True)
        lines = res.stdout.splitlines()
        
        rules = {}
        for line in lines:
            m_target = re.match(r"web\.(\w+)\.target='(.*)'", line)
            if m_target:
                rname, target = m_target.groups()
                rules.setdefault(rname, {})["target"] = target
            m_roles = re.match(r"web\.(\w+)\.roles=(.*)", line)
            if m_roles:
                rname, roles_str = m_roles.groups()
                roles = roles_str.replace("'", "").split()
                rules.setdefault(rname, {})["roles"] = roles

        guest_rules = {k: v for k, v in rules.items() if "roles" in v and "guest" in v["roles"]}
        print(f"Total rules admitting 'guest': {len(guest_rules)}\n")
        print(f"{'Rule Name':<24} | {'Target Endpoint':<30} | {'Status':<8} | {'Size':<8} | {'Content Sample'}")
        print("-" * 105)
        
        for rname, info in sorted(guest_rules.items()):
            target = info.get("target", "N/A")
            url = f"http://{ip}{target}"
            try:
                r = requests.get(url, timeout=4)
                content_sample = r.text.replace("\n", " ").replace("\r", "")[:50].strip()
                print(f"{rname:<24} | {target:<30} | HTTP {r.status_code:<3} | {len(r.content):<6}B | {content_sample}")
            except Exception as e:
                print(f"{rname:<24} | {target:<30} | ERROR    | {e}")

if __name__ == "__main__":
    main()
