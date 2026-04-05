'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const LuaDeflate = require('../lib/LuaDeflate');
const LuaDeflateNative = require('../lib/LuaDeflateNative');

const ld = new LuaDeflate();
const ldn = new LuaDeflateNative();

// ── M. Encode ──────────────────────────────────────────────────────────────

describe('M. Encode', () => {
    test('M74: 3-byte input → 4 chars (full group)', () => {
        assert.strictEqual(ld.encodeForPrint('\x41\x42\x43').length, 4);
    });

    test('M75: 1-byte input → 2 chars (tail)', () => {
        assert.strictEqual(ld.encodeForPrint('\x41').length, 2);
    });

    test('M76: 2-byte input → 3 chars (tail)', () => {
        assert.strictEqual(ld.encodeForPrint('\x41\x42').length, 3);
    });

    test('M77: 6-byte input → 8 chars (two full groups)', () => {
        assert.strictEqual(ld.encodeForPrint('\x41\x42\x43\x44\x45\x46').length, 8);
    });

    test('M78: empty input → empty string', () => {
        assert.strictEqual(ld.encodeForPrint(''), '');
    });

    test('M79: output uses only alphabet chars a-zA-Z0-9()', () => {
        assert.match(ld.encodeForPrint('hello world test data here!!'), /^[a-zA-Z0-9()]+$/);
    });
});

// ── N. Decode ──────────────────────────────────────────────────────────────

describe('N. Decode', () => {
    test('N80: 4-char input → 3 bytes (full group)', () => {
        const decoded = ld.decodeForPrint(ld.encodeForPrint('\x41\x42\x43'));
        assert.strictEqual(decoded.length, 3);
    });

    test('N81: 2-char input → 1 byte (tail)', () => {
        const decoded = ld.decodeForPrint(ld.encodeForPrint('\x41'));
        assert.strictEqual(decoded.length, 1);
    });

    test('N82: 3-char input → 2 bytes (tail)', () => {
        const decoded = ld.decodeForPrint(ld.encodeForPrint('\x41\x42'));
        assert.strictEqual(decoded.length, 2);
    });

    test('N83: whitespace stripped from start/end before decode', () => {
        const encoded = ld.encodeForPrint('hi');
        assert.strictEqual(ld.decodeForPrint('  ' + encoded + '\n'), 'hi');
    });

    test('N84: length-1 input → undefined', () => {
        assert.strictEqual(ld.decodeForPrint('a'), undefined);
    });

    test('N85: empty string → undefined', () => {
        assert.strictEqual(ld.decodeForPrint(''), undefined);
    });

    test('N86: invalid character → null', () => {
        assert.strictEqual(ld.decodeForPrint('ab+c'), null);
    });
});

// ── O. Round-trips ─────────────────────────────────────────────────────────

describe('O. Round-trips', () => {
    test('O87: simple ASCII string', () => {
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint('hello')), 'hello');
    });

    test('O88: binary data — all 256 byte values', () => {
        const bytes = Array.from({ length: 256 }, (_, i) => String.fromCharCode(i)).join('');
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(bytes)), bytes);
    });

    test('O89: large payload (1000+ bytes)', () => {
        const input = 'abcdefghij'.repeat(120);
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(input)), input);
    });

    test('O90: single byte', () => {
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint('\x41')), '\x41');
    });

    test('O91: two bytes', () => {
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint('\x41\x42')), '\x41\x42');
    });

    test('O92: three bytes (boundary)', () => {
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint('\x41\x42\x43')), '\x41\x42\x43');
    });

    test('O93: null bytes (0x00) round-trip correctly', () => {
        const nullStr = '\x00\x00\x00';
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(nullStr)), nullStr);
    });
});

// ── P. Native Variant ──────────────────────────────────────────────────────

describe('P. Native Variant', () => {
    test('P94: native encode output byte-identical to reference encode', () => {
        const inputs = ['hello', 'abc', 'The quick brown fox', 'x'.repeat(99)];
        for (const input of inputs) {
            assert.strictEqual(
                ldn.encodeForPrint(input),
                ld.encodeForPrint(input),
                `Mismatch for input: ${input.slice(0, 20)}`
            );
        }
    });

    test('P95: native decode output byte-identical to reference decode', () => {
        const input = 'round trip test string 123';
        const encoded = ld.encodeForPrint(input);
        assert.strictEqual(ldn.decodeForPrint(encoded), ld.decodeForPrint(encoded));
    });

    test('P96: native round-trip', () => {
        const input = 'The quick brown fox jumps over the lazy dog';
        assert.strictEqual(ldn.decodeForPrint(ldn.encodeForPrint(input)), input);
    });
});
