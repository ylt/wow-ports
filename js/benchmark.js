'use strict';

const LuaDeflate = require('./lib/LuaDeflate');
const LuaDeflateNative = require('./lib/LuaDeflateNative');

const orig = new LuaDeflate();
const native = new LuaDeflateNative();

// Generate random printable ASCII string (0x20-0x7E)
function randomString(len) {
    let s = '';
    for (let i = 0; i < len; i++) {
        s += String.fromCharCode(0x20 + Math.floor(Math.random() * 95));
    }
    return s;
}

const SIZES = [
    { label: 'Small  (32B)', bytes: 32,     encIter: 5000, decIter: 5000 },
    { label: 'Medium (1KB)', bytes: 1024,   encIter: 1000, decIter: 1000 },
    { label: 'Large  (64KB)', bytes: 65536,  encIter: 20,   decIter: 20   },
    { label: 'XL   (256KB)', bytes: 262144, encIter: 5,    decIter: 5    },
];

// --- Correctness check ---
console.log('=== Correctness ===\n');

let allPass = true;
for (const { label, bytes } of SIZES) {
    const input = randomString(bytes);

    const encOrig   = orig.encodeForPrint(input);
    const encNative = native.encodeForPrint(input);

    const encMatch = encOrig === encNative;

    const decOrig   = orig.decodeForPrint(encOrig);
    const decNative = native.decodeForPrint(encNative);

    const decOrigMatch   = decOrig   === input;
    const decNativeMatch = decNative === input;

    const pass = encMatch && decOrigMatch && decNativeMatch;
    if (!pass) allPass = false;

    const status = pass ? 'PASS' : 'FAIL';
    console.log(`${label}: encode-match=${encMatch} dec-orig=${decOrigMatch} dec-native=${decNativeMatch} => ${status}`);
    if (!encMatch) {
        console.log(`  enc orig   len=${encOrig   ? encOrig.length   : 'null'}`);
        console.log(`  enc native len=${encNative ? encNative.length : 'null'}`);
    }
}
console.log(`\nOverall correctness: ${allPass ? 'PASS' : 'FAIL'}\n`);

// --- Benchmark helper ---
function bench(fn, iterations) {
    // Warm up
    fn();
    fn();

    const start = process.hrtime.bigint();
    for (let i = 0; i < iterations; i++) {
        fn();
    }
    const end = process.hrtime.bigint();
    const elapsedNs = Number(end - start);
    const opsPerSec = Math.round(iterations / (elapsedNs / 1e9));
    return opsPerSec;
}

// --- Benchmark ---
console.log('=== Benchmark ===\n');

const COL = {
    label:   22,
    op:      8,
    orig:    14,
    native:  14,
    speedup: 10,
};

function pad(str, width) {
    return String(str).padStart(width);
}

function fmt(n) {
    return n.toLocaleString('en-US');
}

const header = [
    'Size'.padEnd(COL.label),
    'Op'.padEnd(COL.op),
    pad('Original', COL.orig),
    pad('Native', COL.native),
    pad('Speedup', COL.speedup),
].join('  ');

const divider = '-'.repeat(header.length);

console.log(header);
console.log(divider);

for (const { label, bytes, encIter, decIter } of SIZES) {
    const input    = randomString(bytes);
    const encoded  = orig.encodeForPrint(input);

    const encOrig   = bench(() => orig.encodeForPrint(input),     encIter);
    const encNative = bench(() => native.encodeForPrint(input),   encIter);
    const decOrig   = bench(() => orig.decodeForPrint(encoded),   decIter);
    const decNative = bench(() => native.decodeForPrint(encoded), decIter);

    const encSpeedup = (encNative / encOrig).toFixed(2);
    const decSpeedup = (decNative / decOrig).toFixed(2);

    console.log([
        label.padEnd(COL.label),
        'encode'.padEnd(COL.op),
        pad(fmt(encOrig),   COL.orig),
        pad(fmt(encNative), COL.native),
        pad(`${encSpeedup}x`, COL.speedup),
    ].join('  '));

    console.log([
        ''.padEnd(COL.label),
        'decode'.padEnd(COL.op),
        pad(fmt(decOrig),   COL.orig),
        pad(fmt(decNative), COL.native),
        pad(`${decSpeedup}x`, COL.speedup),
    ].join('  '));

    console.log(divider);
}

console.log('\nops/sec: higher is better. Speedup = native / original.\n');
