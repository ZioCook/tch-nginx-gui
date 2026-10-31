#!/usr/bin/env python3
import subprocess

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

probe_injection = """
if ngx.req.get_uri_args().action == "checktypes" then
  ngx.header.content_type = "text/plain"
  ngx.say("type(ui_helper)=" .. tostring(type(ui_helper)))
  ngx.say("type(post_helper)=" .. tostring(type(post_helper)))
  ngx.say("type(content_helper)=" .. tostring(type(content_helper)))
  ngx.say("type(proxy)=" .. tostring(type(proxy)))
  ngx.say("type(session)=" .. tostring(type(session)))
  ngx.say("type(T)=" .. tostring(type(T)))
  ngx.say("type(N)=" .. tostring(type(N)))
  ngx.say("type(gettext)=" .. tostring(type(gettext)))
  ngx.say("type(ngx)=" .. tostring(type(ngx)))
  ngx.exit(ngx.HTTP_OK)
end
"""

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Testing in login.lp on {name} ({ip})")
    print(f"=======================================================")
    
    # Backup login.lp
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cp /www/docroot/login.lp /tmp/login.lp.bak"], check=True)
    
    try:
        # Insert probe right after gettext.textdomain('webui-core')
        script = f"""
        python -c '
with open("/tmp/login.lp.bak") as f:
    c = f.read()
target = "gettext.textdomain(\\'webui-core\\')"
replacement = target + "\\n{probe_injection.strip()}"
new_c = c.replace(target, replacement, 1)
with open("/www/docroot/login.lp", "w") as f:
    f.write(new_c)
'
        """
        # Alternatively using sed or awk on router
        awk_cmd = """awk '/gettext.textdomain/{print; print "if ngx.req.get_uri_args().action == \\"checktypes\\" then ngx.header.content_type = \\"text/plain\\"; ngx.say(\\"type(ui_helper)=\\" .. tostring(type(ui_helper))); ngx.say(\\"type(post_helper)=\\" .. tostring(type(post_helper))); ngx.say(\\"type(content_helper)=\\" .. tostring(type(content_helper))); ngx.say(\\"type(proxy)=\\" .. tostring(type(proxy))); ngx.say(\\"type(session)=\\" .. tostring(type(session))); ngx.say(\\"type(T)=\\" .. tostring(type(T))); ngx.say(\\"type(N)=\\" .. tostring(type(N))); ngx.say(\\"type(gettext)=\\" .. tostring(type(gettext))); ngx.say(\\"type(ngx)=\\" .. tostring(type(ngx))); ngx.exit(ngx.HTTP_OK) end"; next}1\' /tmp/login.lp.bak > /www/docroot/login.lp'"""
        subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f"awk '/gettext.textdomain/{{print; print \"if ngx.req.get_uri_args().action == \\\"checktypes\\\" then ngx.header.content_type = \\\"text/plain\\\"; ngx.say(\\\"type(ui_helper)=\\\" .. tostring(type(ui_helper))); ngx.say(\\\"type(post_helper)=\\\" .. tostring(type(post_helper))); ngx.say(\\\"type(content_helper)=\\\" .. tostring(type(content_helper))); ngx.say(\\\"type(proxy)=\\\" .. tostring(type(proxy))); ngx.say(\\\"type(session)=\\\" .. tostring(type(session))); ngx.say(\\\"type(T)=\\\" .. tostring(type(T))); ngx.say(\\\"type(N)=\\\" .. tostring(type(N))); ngx.say(\\\"type(gettext)=\\\" .. tostring(type(gettext))); ngx.say(\\\"type(ngx)=\\\" .. tostring(type(ngx))); ngx.exit(ngx.HTTP_OK) end\"; next}}1' /tmp/login.lp.bak > /www/docroot/login.lp"], check=True)
        
        # 1. Anonymous request
        out_unauth = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "curl -k -s https://127.0.0.1/login.lp?action=checktypes"], capture_output=True, text=True).stdout
        print("--- RESPONSE WITHOUT SESSION ---")
        print(out_unauth.strip())
        
        # 2. Authenticated request
        get_cookie = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
        c_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", get_cookie], capture_output=True, text=True)
        cookie = c_res.stdout.strip()
        
        out_auth = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f'curl -k -s -H "Cookie: sessionid={cookie}" https://127.0.0.1/login.lp?action=checktypes'], capture_output=True, text=True).stdout
        print("\n--- RESPONSE WITH SESSION ---")
        print(out_auth.strip())
    finally:
        # Restore login.lp
        subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cp /tmp/login.lp.bak /www/docroot/login.lp && rm -f /tmp/login.lp.bak"], check=True)
