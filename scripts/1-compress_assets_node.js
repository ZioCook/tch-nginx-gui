#!/usr/bin/env node
/**
 * Asset Minification Tool for tch-nginx-gui
 * Uses Terser for advanced JS optimization and Clean-CSS for CSS optimization.
 */

const fs = require('fs');
const path = require('path');

let Terser;
let CleanCSS;

try {
  Terser = require('terser');
} catch (e) {
  console.error('Error: "terser" package is missing. Run "npm install".');
  process.exit(1);
}

try {
  CleanCSS = require('clean-css');
} catch (e) {
  console.error('Error: "clean-css" package is missing. Run "npm install".');
  process.exit(1);
}

function findFiles(dir, ext, fileList = []) {
  if (!fs.existsSync(dir)) return fileList;
  const items = fs.readdirSync(dir);
  for (const item of items) {
    const fullPath = path.join(dir, item);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      findFiles(fullPath, ext, fileList);
    } else if (item.endsWith(ext)) {
      fileList.push(fullPath);
    }
  }
  return fileList;
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B';
  return (bytes / 1024).toFixed(1) + ' KB';
}

async function minifyJS(files) {
  console.log(`\n=== Minifying ${files.length} JavaScript files with Terser ===`);
  let totalOrig = 0;
  let totalMini = 0;

  for (const file of files) {
    const origCode = fs.readFileSync(file, 'utf8');
    const origSize = Buffer.byteLength(origCode, 'utf8');
    totalOrig += origSize;

    try {
      const result = await Terser.minify(origCode, {
        compress: {
          passes: 2,
          drop_debugger: true,
          dead_code: true,
        },
        mangle: {
          toplevel: false, // preserve top-level symbols needed across multiple scripts/templates
        },
        format: {
          comments: false,
        },
      });

      if (result.error) {
        console.error(`[FAIL] ${file}: ${result.error}`);
        continue;
      }

      const miniCode = result.code || origCode;
      const miniSize = Buffer.byteLength(miniCode, 'utf8');
      totalMini += miniSize;
      const saved = origSize - miniSize;
      const pct = origSize > 0 ? ((saved / origSize) * 100).toFixed(1) : 0;

      fs.writeFileSync(file, miniCode, 'utf8');
      console.log(`[OK] ${path.basename(file)}: ${formatBytes(origSize)} -> ${formatBytes(miniSize)} (-${pct}%)`);
    } catch (err) {
      console.error(`[ERROR] Processing ${file}:`, err.message);
    }
  }

  const savedTotal = totalOrig - totalMini;
  const pctTotal = totalOrig > 0 ? ((savedTotal / totalOrig) * 100).toFixed(1) : 0;
  console.log(`JavaScript Summary: ${formatBytes(totalOrig)} -> ${formatBytes(totalMini)} (Saved ${formatBytes(savedTotal)}, -${pctTotal}%)`);
}

function minifyCSS(files) {
  console.log(`\n=== Minifying ${files.length} CSS files with Clean-CSS ===`);
  let totalOrig = 0;
  let totalMini = 0;

  const cleanCss = new CleanCSS({
    level: 2,
    rebase: false,
    returnPromise: false,
  });

  for (const file of files) {
    const origCode = fs.readFileSync(file, 'utf8');
    const origSize = Buffer.byteLength(origCode, 'utf8');
    totalOrig += origSize;

    try {
      const output = cleanCss.minify(origCode);

      if (output.errors && output.errors.length > 0) {
        console.error(`[FAIL] ${file}:`, output.errors.join(', '));
        continue;
      }

      if (output.warnings && output.warnings.length > 0) {
        // Log warnings as debug only
      }

      const miniCode = output.styles || origCode;
      const miniSize = Buffer.byteLength(miniCode, 'utf8');
      totalMini += miniSize;
      const saved = origSize - miniSize;
      const pct = origSize > 0 ? ((saved / origSize) * 100).toFixed(1) : 0;

      fs.writeFileSync(file, miniCode, 'utf8');
      console.log(`[OK] ${path.basename(file)}: ${formatBytes(origSize)} -> ${formatBytes(miniSize)} (-${pct}%)`);
    } catch (err) {
      console.error(`[ERROR] Processing ${file}:`, err.message);
    }
  }

  const savedTotal = totalOrig - totalMini;
  const pctTotal = totalOrig > 0 ? ((savedTotal / totalOrig) * 100).toFixed(1) : 0;
  console.log(`CSS Summary: ${formatBytes(totalOrig)} -> ${formatBytes(totalMini)} (Saved ${formatBytes(savedTotal)}, -${pctTotal}%)`);
}

async function main() {
  const cwd = process.cwd();
  // Determine if running inside data/ or repo root
  let jsDir = path.resolve(cwd, 'js_files');
  let cssDir = path.resolve(cwd, 'css_files');

  if (!fs.existsSync(jsDir) && fs.existsSync(path.resolve(cwd, 'data', 'js_files'))) {
    jsDir = path.resolve(cwd, 'data', 'js_files');
    cssDir = path.resolve(cwd, 'data', 'css_files');
  }

  const jsFiles = findFiles(jsDir, '.js');
  const cssFiles = findFiles(cssDir, '.css');

  if (jsFiles.length === 0 && cssFiles.length === 0) {
    console.log(`No JS or CSS files found to minify in ${cwd} or data/`);
    return;
  }

  if (jsFiles.length > 0) {
    await minifyJS(jsFiles);
  }

  if (cssFiles.length > 0) {
    minifyCSS(cssFiles);
  }

  console.log('\nAsset minification complete.');
}

main().catch((err) => {
  console.error('Fatal minification error:', err);
  process.exit(1);
});
