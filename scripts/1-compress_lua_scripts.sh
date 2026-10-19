#!/bin/bash
set -eo pipefail

TYPE="$(cat type)"
if [ "$TYPE" != "STABLE" ] && [ "$TYPE" != "PREVIEW" ]; then
	exit 0
fi

pretranslated_string="--pretranslated: do not change this file"
FAIL_FLAG="/tmp/luasrcdiet_failed_$$"
rm -f "$FAIL_FLAG"

MAX_JOBS="$(nproc 2>/dev/null || echo 4)"
case "$MAX_JOBS" in ''|*[!0-9]*|0) MAX_JOBS=4 ;; esac
[ "$MAX_JOBS" -gt 8 ] && MAX_JOBS=8

minify_lua() {
	local file="$1"
	local compressed=0
	local append_pretranslate=0
	if grep -q "$file" -e "$pretranslated_string" 2>/dev/null; then
		append_pretranslate=1
	fi
	echo "Minifying $file | Pretranslated: $append_pretranslate"
	
	if ! luasrcdiet --maximum --quiet "$file" -o "$file.min"; then 
		echo "Minify error for $file" >&2
		touch "$FAIL_FLAG"
		return 1
	fi

	if [ "$append_pretranslate" = 1 ]; then
		sed -i '1s/^/'"$pretranslated_string"'\n/' "$file.min"
	fi
	# Remove any comments in the form "code // comment" or "^//" (line start + comment all line)
	perl -i -pe 's/(^[\s\t]*|[\s\t]+)\/\/.*\n//g' "$file.min"
	# Remove any new line escaped and reduce html code to one line
	perl -i -pe 's/\\\n[\s\t]*//g' "$file.min"
	chmod "$(stat -c "%a" "$file")" "$file.min"
	compressed=$(( $(stat --printf="%s" "$file") - $(stat --printf="%s" "$file.min") ))
	echo "File $file minified for $compressed byte"

	if [ -f "$file.min" ]; then
		echo "Moving $( echo "$file.min" | sed 's|.*/||' ) to $( echo "$file" | sed 's|.*/||' )"
		rm -f "$file"
		mv -f "$file.min" "$file"
	else
		echo "Missing minified file for $file" >&2
		touch "$FAIL_FLAG"
		return 1
	fi
}

run_job() {
	while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
		wait -n 2>/dev/null || sleep 0.05
	done
	minify_lua "$1" &
}

parse_files() {
	find "$1"_files ! -name "$(printf "*\n*")" -name "*.$1" -type f > "$1"_files_list
	while IFS= read -r file; do
		run_job "$file"
	done < "$1"_files_list
	rm -f "$1"_files_list
}

parse_files lua
parse_files lp
parse_files map

wait

if [ -f "$FAIL_FLAG" ]; then
	rm -f "$FAIL_FLAG"
	echo "ERROR: Lua minification failed for one or more files." >&2
	exit 1
fi

rm -f "$FAIL_FLAG"
exit 0
