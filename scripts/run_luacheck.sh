#!/bin/bash
set -e
cd "$(dirname "$0")/.."
mapfile -t files < <(find decompressed/gui_file/www decompressed/gui_file/usr/lib/lua decompressed/gui_file/usr/share -type f \( -name "*.lp" -o -name "*.lua" \))
echo "Total files to check: ${#files[@]}"
luacheck --config .luacheckrc "$@" "${files[@]}"
