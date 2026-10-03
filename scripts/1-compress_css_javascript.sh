#! /bin/sh

TYPE="$(cat type)"
if [ "$TYPE" != "STABLE" ] && [ "$TYPE" != "PREVIEW" ]; then
	exit 0
fi

if command -v node >/dev/null 2>&1 && [ -f "../scripts/1-compress_assets_node.js" ]; then
	echo "Running Node.js asset optimizer (Terser + Clean-CSS)..."
	node ../scripts/1-compress_assets_node.js
else
	echo "Falling back to standard minify..."
	minify --recursive --verbose --match=\.*.js$ --type=js --output js_files/ js_files/
	minify --recursive --verbose --match=\.*.css$ --type=css --output css_files/ css_files/
fi

echo "Finished"