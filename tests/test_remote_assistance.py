"""Unit tests for remote assistance boot persistence and scripts."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'decompressed/gui_file'
SH = shutil.which('bash') or shutil.which('sh')


@unittest.skipUnless(SH, 'POSIX shell required')
class RemoteAssistanceTests(unittest.TestCase):
    def run_sh(self, script):
        result = subprocess.run([SH, '-c', script], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, f"Script failed: {result.stderr}\nStdout: {result.stdout}")
        return result.stdout.strip()

    def test_shell_syntax(self):
        scripts = [
            ROOT / 'etc/init.d/ra',
            ROOT / 'etc/hotplug.d/iface/99-ra',
            ROOT / 'etc/fwdassist.sh',
            ROOT / 'etc/modgui_scripts/03_various.sh',
        ]
        for script_path in scripts:
            with self.subTest(script=script_path.name):
                result = subprocess.run([SH, '-n', str(script_path)], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, f"Syntax error in {script_path}: {result.stderr}")

    def test_is_ra_enabled_logic(self):
        ra_script = (ROOT / 'etc/init.d/ra').read_text()
        func_body = ra_script[ra_script.index('is_ra_enabled() {'):ra_script.index('\ntrigger_ra()')]

        test_harness = f"""
{func_body}

# Case 1: web.state_remote.enabled='1' (standard UCI show with single quotes)
uci() {{
    if [ "$1" = "show" ]; then
        echo "web.state_remote=assist_state"
        echo "web.state_remote.enabled='1'"
        echo "web.state_remote.port='55432'"
    else
        return 1
    fi
}}
is_ra_enabled || exit 1

# Case 2: web.state_remote.enabled=1 (unquoted)
uci() {{
    if [ "$1" = "show" ]; then
        echo "web.state_remote=assist_state"
        echo "web.state_remote.enabled=1"
    else
        return 1
    fi
}}
is_ra_enabled || exit 2

# Case 3: uci get web.state_remote.enabled returns 1
uci() {{
    if [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "web.state_remote.enabled" ]; then
        echo "1"
    else
        return 1
    fi
}}
is_ra_enabled || exit 3

# Case 4: web.remote.active=1
uci() {{
    if [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "web.remote.active" ]; then
        echo "1"
    else
        return 1
    fi
}}
is_ra_enabled || exit 4

# Case 5: anonymous section web.@assist_state[0].enabled='1'
uci() {{
    if [ "$1" = "show" ]; then
        echo "web.@assist_state[0]=assist_state"
        echo "web.@assist_state[0].enabled='1'"
    else
        return 1
    fi
}}
is_ra_enabled || exit 5

# Case 6: disabled - should return 1 (false)
uci() {{
    if [ "$1" = "show" ]; then
        echo "web.state_remote=assist_state"
        echo "web.state_remote.enabled='0'"
    else
        return 1
    fi
}}
if is_ra_enabled; then
    exit 6
fi

echo "ALL_CASES_PASSED"
"""
        out = self.run_sh(test_harness)
        self.assertEqual(out, "ALL_CASES_PASSED")

    def test_fwdassist_load_value(self):
        fwdassist = (ROOT / 'etc/fwdassist.sh').read_text()
        func_body = fwdassist[fwdassist.index('load_value()'):fwdassist.index('\nget_state_value()')]

        test_harness = f"""
{func_body}

TMPFILE=$(mktemp)
cat << 'EOF' > "$TMPFILE"
enabled=1
ifname=wan
wanport=55432
lanport=8443
EOF

val_en=$(load_value "$TMPFILE" enabled)
val_if=$(load_value "$TMPFILE" ifname)
val_wp=$(load_value "$TMPFILE" wanport)
val_none=$(load_value "$TMPFILE" nonexistent)

rm -f "$TMPFILE"

[ "$val_en" = "1" ] || exit 1
[ "$val_if" = "wan" ] || exit 2
[ "$val_wp" = "55432" ] || exit 3
[ -z "$val_none" ] || exit 4

echo "LOAD_VALUE_PASSED"
"""
        out = self.run_sh(test_harness)
        self.assertEqual(out, "LOAD_VALUE_PASSED")


if __name__ == '__main__':
    unittest.main()
