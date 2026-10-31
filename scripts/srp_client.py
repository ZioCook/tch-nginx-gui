import hashlib
import requests
import os
import time
import sys

N_hex = "ac6bdb41324a9a9bf166de5e1389582faf72b6651987ee07fc3192943db56050a37329cbb4a099ed8193e0757767a13dd52312ab4b03310dcd7f48a9da04fd50e8083969edb767b0cf6095179a163ab3661a05fbd5faaae82918a9962f0b93b855f97993ec975eeaa80d740adbf4ff747359d041d5c33ea71d281e446b14773bca97b43a23fb801676bd207a436c6481f1d2b9078717461a5b9d32e688f87748544523b524b0d57d5ea77a2775d2ecfa032cfbdbf52fb3786160279004e57ae6af874e7303ce53299ccc041c7bc308d82a5698f3a8d0c38271ae35f8e9dbfbb694b5c803d89f7ae435de236d525f54759b65e372fcd68ef20fa7111f9e4aff73"
N = int(N_hex, 16)
g = 2
k_hex = "05b9e8ef059c6b32ea59fc1d322d37f04aa30bae5aa9003b8321e21ddb04e300"
k = int(k_hex, 16)
u_hash = "4a76a9a2402bdd18123389b72ebbda50a30f65aedb90d7273130edea4b29cc4c"

def sha256_hex(data_bytes):
    return hashlib.sha256(data_bytes).hexdigest()

def pad_hex(val_hex, byte_len=256):
    val_hex = val_hex.lstrip("0")
    if len(val_hex) % 2 == 1:
        val_hex = "0" + val_hex
    raw = bytes.fromhex(val_hex)
    if len(raw) < byte_len:
        raw = b"\x00" * (byte_len - len(raw)) + raw
    elif len(raw) > byte_len:
        raw = raw[-byte_len:]
    return raw

def srp_login(ip, username=None, password=None, session=None):
    if username is None:
        username = os.environ.get("ROUTER_USER")
        if not username:
            sys.stderr.write("Error: Missing required environment variable ROUTER_USER\n")
            sys.exit(1)
    if password is None:
        password = os.environ.get("ROUTER_PASS")
        if not password:
            sys.stderr.write("Error: Missing required environment variable ROUTER_PASS\n")
            sys.exit(1)
    if session is None:
        session = requests.Session()
    
    # 1. GET /login.lp to get session cookie & CSRF token
    r = session.get(f"http://{ip}/login.lp", timeout=10)
    csrf_token = ""
    for line in r.text.splitlines():
        if 'name="CSRFtoken"' in line:
            import re
            m = re.search(r'content="([^"]+)"', line)
            if m:
                csrf_token = m.group(1)
                break
    
    # Generate client ephemeral 'a'
    a_bytes = os.urandom(32)
    a = int.from_bytes(a_bytes, 'big')
    A = pow(g, a, N)
    A_hex = f"{A:x}"
    if len(A_hex) % 2 == 1:
        A_hex = "0" + A_hex
        
    # 2. Step 1: POST /authenticate with I and A
    post_data_1 = {
        "CSRFtoken": csrf_token,
        "I": username,
        "A": A_hex
    }
    r1 = session.post(f"http://{ip}/authenticate", data=post_data_1, timeout=10)
    res1 = r1.json()
    if "error" in res1:
        return False, f"Step 1 error: {res1['error']}", session
    
    salt_hex = res1["s"]
    B_hex = res1["B"]
    B = int(B_hex, 16)
    
    # 3. Calculate u = H(PAD(A) || PAD(B))
    raw_A = pad_hex(A_hex, 256)
    raw_B = pad_hex(B_hex, 256)
    u_bytes = hashlib.sha256(raw_A + raw_B).digest()
    u = int.from_bytes(u_bytes, 'big')
    if u == 0:
        return False, "u == 0", session
    
    # Calculate x = H(salt || H(username:password))
    inner = hashlib.sha256(f"{username}:{password}".encode('utf-8')).hexdigest()
    x_bytes = hashlib.sha256(bytes.fromhex(salt_hex) + bytes.fromhex(inner)).digest()
    x = int.from_bytes(x_bytes, 'big')
    
    # Calculate S = (B - k * (g^x mod N)) ^ (a + u * x) mod N
    gx = pow(g, x, N)
    base = (B - (k * gx)) % N
    exp = (a + (u * x))
    S = pow(base, exp, N)
    S_hex = f"{S:x}"
    if len(S_hex) % 2 == 1:
        S_hex = "0" + S_hex
    
    K = hashlib.sha256(bytes.fromhex(S_hex)).hexdigest()
    
    # Calculate M = H(u_hash || H(I) || salt || A_hex || B_hex || K)
    I_hash = hashlib.sha256(username.encode('utf-8')).hexdigest()
    m_input = u_hash + I_hash + salt_hex + A_hex + B_hex + K
    M = hashlib.sha256(bytes.fromhex(m_input)).hexdigest()
    
    # 4. Step 2: POST /authenticate with M
    post_data_2 = {
        "CSRFtoken": csrf_token,
        "M": M
    }
    r2 = session.post(f"http://{ip}/authenticate", data=post_data_2, timeout=10)
    res2 = r2.json()
    if "error" in res2:
        return False, f"Step 2 error: {res2['error']}", session
    
    server_M = res2.get("M", "")
    # Calculate expected server M2 = H(A_hex || M || K)
    m2_input = A_hex + M + K
    expected_M2 = hashlib.sha256(bytes.fromhex(m2_input)).hexdigest()
    
    if server_M.lower() == expected_M2.lower():
        return True, "Authenticated successfully", session
    else:
        return False, f"M2 mismatch: server={server_M}, expected={expected_M2}", session

if __name__ == "__main__":
    router_host = os.environ.get("ROUTER_HOST")
    if not router_host:
        router_host = "192.0.2.6"
    router_user = os.environ.get("ROUTER_USER")
    router_pass = os.environ.get("ROUTER_PASS")
    if not router_user:
        sys.stderr.write("Error: Missing required environment variable ROUTER_USER\n")
        sys.exit(1)
    if not router_pass:
        sys.stderr.write("Error: Missing required environment variable ROUTER_PASS\n")
        sys.exit(1)
    ok, msg, sess = srp_login(router_host, router_user, router_pass)
    print(f"Login result: {ok}, {msg}")
    if ok:
        r = sess.get(f"http://{router_host}/cards.lp")
        print("cards.lp status:", r.status_code, "len:", len(r.content), "md5:", hashlib.md5(r.content).hexdigest())
