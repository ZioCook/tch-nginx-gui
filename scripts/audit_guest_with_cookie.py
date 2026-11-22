import subprocess
import re
import requests
import json

ROUTERS = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

def audit_router(name, ip):
    print(f"\n=======================================================")
    print(f"[*] AUDITING GUEST-ACCESSIBLE RULES WITH REAL GUEST SESSION: {name} ({ip})")
    print(f"=======================================================")
    
    # Get all rules admitting guest
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

    # Step 1: Acquire real guest session cookie via GET /login.lp
    session = requests.Session()
    r_login = session.get(f"http://{ip}/login.lp", timeout=5)
    guest_cookies = session.cookies.get_dict()
    print(f"Acquired Guest Session Cookies from /login.lp: {guest_cookies}")

    print(f"\n{'Rule Name':<20} | {'Target':<28} | {'HTTP':<5} | {'Size':<8} | {'JSON Keys / Content Summary'}")
    print("-" * 105)

    for rname, info in sorted(guest_rules.items()):
        target = info.get("target", "N/A")
        url = f"http://{ip}{target}"
        try:
            r = session.get(url, timeout=5)
            content_type = r.headers.get("Content-Type", "")
            size = len(r.content)
            
            # Check if JSON
            summary = ""
            try:
                data = r.json()
                if isinstance(data, dict):
                    keys = list(data.keys())
                    summary = f"JSON keys ({len(keys)}): {keys[:6]}"
                elif isinstance(data, list):
                    summary = f"JSON array of {len(data)} items"
                else:
                    summary = f"JSON: {str(data)[:50]}"
            except Exception:
                # HTML or text
                text_clean = r.text.replace("\n", " ").replace("\r", "")[:60].strip()
                if "sign-me-in" in r.text or "srp_username" in r.text:
                    summary = "HTML Login Page"
                else:
                    summary = f"HTML/Text: {text_clean}"

            print(f"{rname:<20} | {target:<28} | {r.status_code:<5} | {size:<6}B | {summary}")
        except Exception as e:
            print(f"{rname:<20} | {target:<28} | ERROR | {e}")

def main():
    for name, ip in ROUTERS:
        audit_router(name, ip)

if __name__ == "__main__":
    main()
