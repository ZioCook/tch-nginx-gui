#!/bin/sh
#
# Lua Syntax Linter for tch-nginx-gui
# Validates syntax of all .lua and pretranslated .lp files before build/release.
#

TARGET_DIR="${1:-decompressed}"

echo "=========================================="
echo "    Lua Syntax Linter (tch-nginx-gui)     "
echo "=========================================="

LUAC_BIN=""

if command -v luac5.1 >/dev/null 2>&1; then
    LUAC_BIN="luac5.1"
    echo "Found compiler: $(luac5.1 -v 2>&1)"
elif command -v luac >/dev/null 2>&1; then
    LUAC_BIN="luac"
    echo "Found compiler: $(luac -v 2>&1)"
elif command -v lua5.1 >/dev/null 2>&1; then
    LUAC_BIN="lua5.1"
    echo "Using Lua interpreter: $(lua5.1 -v 2>&1)"
elif command -v lua >/dev/null 2>&1; then
    LUAC_BIN="lua"
    echo "Using Lua interpreter: $(lua -v 2>&1)"
else
    echo "ERROR: Neither luac5.1, luac, lua5.1 nor lua was found." >&2
    echo "Please install lua5.1 (e.g. 'sudo apt-get install -y lua5.1')." >&2
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: Target directory '$TARGET_DIR' does not exist." >&2
    exit 1
fi

failed=0
count=0

lint_file() {
    target="$1"
    count=$((count + 1))
    
    if [ "$LUAC_BIN" = "luac5.1" ] || [ "$LUAC_BIN" = "luac" ]; then
        if ! err=$("$LUAC_BIN" -p "$target" 2>&1); then
            failed=$((failed + 1))
            echo "[SYNTAX ERROR] $target"
            echo "    $err"
            if [ -n "$GITHUB_ACTIONS" ]; then
                echo "::error file=$target,title=Lua Syntax Error::$err"
            fi
        fi
    else
        if ! err=$(LUA_FILE="$target" "$LUAC_BIN" -e 'local f, e = loadfile(os.getenv("LUA_FILE")); if not f then io.stderr:write(e .. "\n"); os.exit(1) end' 2>&1); then
            failed=$((failed + 1))
            echo "[SYNTAX ERROR] $target"
            echo "    $err"
            if [ -n "$GITHUB_ACTIONS" ]; then
                echo "::error file=$target,title=Lua Syntax Error::$err"
            fi
        fi
    fi
}

# Lint all .lua files
for file in $(find "$TARGET_DIR" -name "*.lua" -type f); do
    lint_file "$file"
done

# Lint pretranslated .lp files
for file in $(find "$TARGET_DIR" -name "*.lp" -type f); do
    if head -n 1 "$file" | grep -q "pretranslated"; then
        lint_file "$file"
    fi
done

echo "------------------------------------------"
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed / $count files contained syntax errors!" >&2
    exit 1
fi

echo "SUCCESS: All $count Lua/LP files passed syntax validation!"
exit 0
