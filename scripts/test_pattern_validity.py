#!/usr/bin/env python3
import re

# HTML5 pattern compiled as ^(?:pattern)$ in browser DOM
pattern_str = r"^([a-zA-Z]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$"
pat = re.compile(pattern_str)

test_cases = [
    ("my-dect-base.home.arpa", "Valid FQDN with hyphen in label"),
    ("sipxtimxit", "Invalid name with no dots"),
    ("my-dect-base-.home.arpa", "Invalid FQDN with trailing hyphen in label"),
    ("-my-dect-base.home.arpa", "Invalid FQDN with leading hyphen in label"),
    ("192.168.1.1", "IP address format (does not match FQDN alpha start)"),
    ("BaseStation.local", "Valid standard alphanumeric hostname with TLD"),
]

print("=== HTML5 PATTERN VALIDITY TEST (input.validity.patternMismatch) ===")
for val, desc in test_cases:
    matches = bool(pat.match(val))
    pattern_mismatch = not matches
    validity_str = "VALID (Can submit)" if not pattern_mismatch else "INVALID (Blocked by HTML5)"
    print(f"Value: {val:<28} | patternMismatch: {str(pattern_mismatch):<5} | Status: {validity_str:<23} | {desc}")
