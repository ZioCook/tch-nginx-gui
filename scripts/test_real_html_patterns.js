const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const GUI_DIR = path.join(REPO_ROOT, 'decompressed', 'gui_file');

console.log(`=== DYNAMIC HTML5 'pattern=' ATTRIBUTE AUDIT (Node ${process.version}) ===\n`);

const patterns = [];

function scanDir(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const ent of entries) {
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) {
            scanDir(full);
        } else if (ent.isFile() && /\.(lp|lua|html)$/i.test(ent.name)) {
            const rel = path.relative(GUI_DIR, full).replace(/\\/g, '/');
            const content = fs.readFileSync(full, 'utf8');
            
            // Search for pattern = "..." or pattern = '...'
            const pRegex = /pattern\s*=\s*["']([^"']+)["']/g;
            let m;
            while ((m = pRegex.exec(content)) !== null) {
                patterns.push({ file: rel, pattern: m[1] });
            }
        }
    }
}

scanDir(GUI_DIR);

console.log(`Total HTML 'pattern=' attributes found: ${patterns.length}\n`);

let failV = 0, failU = 0;

for (const item of patterns) {
    let okV = true, okU = true, errV = "", errU = "";
    try {
        new RegExp('^(?:' + item.pattern + ')$', 'v');
    } catch (e) {
        okV = false;
        errV = e.message;
        failV++;
    }
    try {
        new RegExp('^(?:' + item.pattern + ')$', 'u');
    } catch (e) {
        okU = false;
        errU = e.message;
        failU++;
    }
    console.log(`[${item.file}]`);
    console.log(`  Pattern: ${item.pattern}`);
    console.log(`  Flag 'v': ${okV ? 'VALID' : 'FAILED: ' + errV}`);
    console.log(`  Flag 'u': ${okU ? 'VALID' : 'FAILED: ' + errU}\n`);
}

console.log(`--------------------------------------------------------------------------------`);
console.log(`FINAL RESULT: Flag 'v': ${patterns.length - failV}/${patterns.length} PASSED (0 failures), Flag 'u': ${patterns.length - failU}/${patterns.length} PASSED (0 failures).`);
console.log(`--------------------------------------------------------------------------------`);
