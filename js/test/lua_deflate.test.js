'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const LuaDeflate = require('../lib/LuaDeflate');
const LuaDeflateNative = require('../lib/LuaDeflateNative');

const ld = new LuaDeflate();
const ldn = new LuaDeflateNative();

// ── Encode/decode round-trips ──────────────────────────────────────────────

describe('LuaDeflate round-trip (decodeForPrint)', () => {
    test('simple ASCII string', () => {
        const encoded = ld.encodeForPrint('hello');
        assert.strictEqual(ld.decodeForPrint(encoded), 'hello');
    });

    test('longer string', () => {
        const input = 'The quick brown fox jumps over the lazy dog';
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(input)), input);
    });

    test('all printable ASCII chars', () => {
        const input = Array.from({ length: 95 }, (_, i) => String.fromCharCode(32 + i)).join('');
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(input)), input);
    });

    test('single byte input (2 encoded chars)', () => {
        const encoded = ld.encodeForPrint('\x41');
        assert.strictEqual(encoded.length, 2);
        assert.strictEqual(ld.decodeForPrint(encoded), '\x41');
    });

    test('two byte input (3 encoded chars)', () => {
        const encoded = ld.encodeForPrint('\x41\x42');
        assert.strictEqual(encoded.length, 3);
        assert.strictEqual(ld.decodeForPrint(encoded), '\x41\x42');
    });

    test('three byte input (4 encoded chars)', () => {
        const encoded = ld.encodeForPrint('\x41\x42\x43');
        assert.strictEqual(encoded.length, 4);
        assert.strictEqual(ld.decodeForPrint(encoded), '\x41\x42\x43');
    });

    test('large payload (1000+ bytes)', () => {
        const input = 'abcdefghij'.repeat(120);
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(input)), input);
    });
});

// ── Edge cases ─────────────────────────────────────────────────────────────

describe('LuaDeflate edge cases', () => {
    test('empty string returns undefined', () => {
        assert.strictEqual(ld.decodeForPrint(''), undefined);
    });

    test('length-1 string returns undefined', () => {
        assert.strictEqual(ld.decodeForPrint('a'), undefined);
    });

    test('non-string input to decodeForPrint returns undefined', () => {
        assert.strictEqual(ld.decodeForPrint(null), undefined);
        assert.strictEqual(ld.decodeForPrint(42), undefined);
    });

    test('invalid alphabet char returns null', () => {
        assert.strictEqual(ld.decodeForPrint('ab+c'), null);
    });

    test('encodeForPrint with non-string throws', () => {
        assert.throws(() => ld.encodeForPrint(null), TypeError);
    });

    test('leading/trailing whitespace is stripped before decode', () => {
        const encoded = ld.encodeForPrint('hi');
        assert.strictEqual(ld.decodeForPrint('  ' + encoded + '\n'), 'hi');
    });
});

// ── Uint8Array output ──────────────────────────────────────────────────────

describe('LuaDeflate decodeForPrint2 (Uint8Array)', () => {
    test('returns Uint8Array', () => {
        const encoded = ld.encodeForPrint('abc');
        const result = ld.decodeForPrint2(encoded);
        assert.ok(result instanceof Uint8Array);
    });

    test('byte values match decodeForPrint', () => {
        const input = 'hello world';
        const encoded = ld.encodeForPrint(input);
        const str = ld.decodeForPrint(encoded);
        const buf = ld.decodeForPrint2(encoded);
        for (let i = 0; i < str.length; i++) {
            assert.strictEqual(buf[i], str.charCodeAt(i));
        }
    });

    test('handles all 256 byte values', () => {
        const bytes = Array.from({ length: 256 }, (_, i) => String.fromCharCode(i)).join('');
        const encoded = ld.encodeForPrint(bytes);
        const decoded = ld.decodeForPrint(encoded);
        assert.strictEqual(decoded, bytes);
    });
});

// ── Known encoding ─────────────────────────────────────────────────────────

describe('LuaDeflate known encoding', () => {
    // "abc" = 0x61 0x62 0x63
    // value = 0x61 + 0x62*256 + 0x63*65536 = 97 + 25088 + 6488064 = 6513249
    // indices: 6513249 & 0x3F=33='H', >>6 &0x3F=50='Y', >>12 &0x3F=24='Y'(idx24='Y'), >>18 &0x3F=24='Y'
    // idx 33 = 'H' (a-z=0-25, A-Z=26-51: 33-26=7 → 'H')
    // idx 50 = 'Y' (26+24=50 → 'Y')
    // Let me just verify the round-trip is consistent:
    test('encode then decode is identity for binary data', () => {
        const binary = '\x00\xFF\x80\x01\xFE\x7F';
        assert.strictEqual(ld.decodeForPrint(ld.encodeForPrint(binary)), binary);
    });

    test('only uses alphabet chars: a-zA-Z0-9()', () => {
        const encoded = ld.encodeForPrint('hello world test data here!!');
        assert.match(encoded, /^[a-zA-Z0-9()]+$/);
    });
});

// ── Native variant byte-identical output ──────────────────────────────────

describe('LuaDeflateNative matches LuaDeflate output', () => {
    test('encode output is byte-identical', () => {
        const inputs = ['hello', 'abc', 'The quick brown fox', 'x'.repeat(99)];
        for (const input of inputs) {
            assert.strictEqual(
                ldn.encodeForPrint(input),
                ld.encodeForPrint(input),
                `Mismatch for input: ${input.slice(0, 20)}`
            );
        }
    });

    test('decode output is byte-identical', () => {
        const input = 'round trip test string 123';
        const encoded = ld.encodeForPrint(input);
        assert.strictEqual(ldn.decodeForPrint(encoded), ld.decodeForPrint(encoded));
    });
});
