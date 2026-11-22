const fs = require('fs');
const path = require('path');

const GUI_DIR = path.join(__dirname, '..', 'decompressed', 'gui_file');

const patterns = new Set();
const patternSources = new Map();

function addPattern(p, src) {
    if (!p || p.trim() === '') return;
    p = p.trim();
    // remove enclosing quotes or delimiters if any
    if ((p.startsWith('"') && p.endsWith('"')) || (p.startsWith("'") && p.endsWith("'"))) {
        p = p.slice(1, -1);
    }
    patterns.add(p);
    if (!patternSources.has(p)) {
        patternSources.set(p, []);
    }
    patternSources.get(p).push(src);
}

function scanDir(dir) {
    const files = fs.readdirSync(dir);
    for (const f of files) {
        const full = path.join(dir, f);
        const stat = fs.statSync(full);
        if (stat.isDirectory()) {
            scanDir(full);
        } else if (f.endsWith('.lp') || f.endsWith('.lua') || f.endsWith('.js') || f.endsWith('.html')) {
            const content = fs.readFileSync(full, 'utf8');
            const rel = path.relative(GUI_DIR, full).replace(/\\/g, '/');
            
            // 1. HTML pattern="..." attributes
            const htmlPatternRegex = /pattern\s*=\s*["']([^"']+)["']/g;
            let m;
            while ((m = htmlPatternRegex.exec(content)) !== null) {
                addPattern(m[1], `${rel} (HTML attribute)`);
            }
            
            // 2. Lua regex validations
            const luaPatternRegex = /getValidateRegularExpression\s*\(\s*["']([^"']+)["']/g;
            while ((m = luaPatternRegex.exec(content)) !== null) {
                addPattern(m[1], `${rel} (getValidateRegularExpression)`);
            }
            
            // 3. post_helper validation helpers
            const validateRegex = /validateRegEx\s*\([^,]+,\s*["']([^"']+)["']/g;
            while ((m = validateRegex.exec(content)) !== null) {
                addPattern(m[1], `${rel} (validateRegEx)`);
            }
        }
    }
}

// Add known IPv4, IPv6, MAC, Domain dynamic patterns
addPattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$', 'post_helper.validateIPv4');
addPattern('^((([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4})|(([0-9a-fA-F]{1,4}:){1,7}:)|(([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4})|(([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2})|(([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3})|(([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4})|(([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5})|([0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6}))|(:((:[0-9a-fA-F]{1,4}){1,7}|:)))$', 'post_helper.validateIPv6');
addPattern('^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$', 'post_helper.validateMac');
addPattern('^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,6}$', 'post_helper.validateFQDN');

scanDir(GUI_DIR);

console.log('='.repeat(90));
console.log(`=== ECMASCRIPT REGEXP FLAG 'v' COMPILATION AUDIT (${patterns.size} UNIQUE PATTERNS) ===`);
console.log('='.repeat(90));

let passed = 0;
let failed = 0;
const failures = [];

for (const p of patterns) {
    try {
        const regex = new RegExp('^(?:' + p + ')$', 'v');
        passed++;
    } catch (err) {
        failed++;
        failures.push({
            pattern: p,
            sources: patternSources.get(p),
            error: err.message
        });
    }
}

console.log(`Total Extracted Patterns: ${patterns.size}`);
console.log(`Successfully Compiled (flag 'v'): ${passed}`);
console.log(`Failed Compilations: ${failed}\n`);

if (failures.length > 0) {
    console.log('FAILED PATTERNS:');
    failures.forEach((f, idx) => {
        console.log(`[${idx+1}] Pattern: ${f.pattern}`);
        console.log(`    Sources: ${f.sources.join(', ')}`);
        console.log(`    Error:   ${f.error}`);
    });
} else {
    console.log('[+] 100% of patterns compiled successfully under ECMAScript RegExp flag \'v\' (zero failures).');
}

// Named pattern check table
console.log('\n--- NAMED SYSTEM PATTERNS AUDIT ---');
const namedPatterns = [
    { name: 'IPv4 Standard', pattern: '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$' },
    { name: 'IPv6 Full Mask', pattern: '^((([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4})|(([0-9a-fA-F]{1,4}:){1,7}:)|(([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4})|(([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2})|(([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3})|(([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4})|(([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5})|([0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6}))|(:((:[0-9a-fA-F]{1,4}){1,7}|:)))$' },
    { name: 'MAC Address', pattern: '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$' },
    { name: 'FQDN / Hostname', pattern: '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,6}$' },
    { name: 'Port Number', pattern: '^[0-9]{1,5}$' },
    { name: 'Printable ASCII', pattern: '^[!-~][ -~]{0,30}[!-~]$' }
];

namedPatterns.forEach(np => {
    let ok = false;
    try {
        new RegExp('^(?:' + np.pattern + ')$', 'v');
        ok = true;
    } catch(e) {}
    console.log(`  - ${np.name:<20}: ${ok ? 'PASSED (valid flag v)' : 'FAILED'}`);
});
