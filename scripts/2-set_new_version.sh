#!/bin/bash

version="$(cat $HOME/gui_build/data/version)"
short_commit_hash="$(cat $HOME/gui_build/data/short_commit_hash 2>/dev/null || echo "")"
build_type="$(cat $HOME/gui_build/data/type 2>/dev/null || echo "")"
rootdevice_file="$HOME/gui_build/decompressed/base/etc/init.d/rootdevice"
cd $HOME/gui_build/

if [ "$build_type" = "STABLE" ]; then
	stamp_ver="$version"
else
	if [ -n "$short_commit_hash" ]; then
		stamp_ver="$version-$short_commit_hash"
	else
		stamp_ver="$version"
	fi
fi

echo "Setting version $stamp_ver to rootdevice"
sed -i "s#version_gui=.*#version_gui=$stamp_ver#" "$rootdevice_file"
	