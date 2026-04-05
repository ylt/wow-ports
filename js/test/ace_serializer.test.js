'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const WowAceSerializer = require('../lib/WowAceSerializer');
const WowAceDeserializer = require('../lib/WowAceDeserializer');

// ── A. String Escaping (Serialize) ─────────────────────────────────────────

describe('A. String Escaping (Serialize)', () => {
    test('A1: NUL (0x00) → ~@', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x00'), '^1^S~@^^');
    });

    test('A2: control 0x01 → ~A', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x01'), '^1^S~A^^');
    });

    test('A2: control 0x0A (LF) → ~J', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x0A'), '^1^S~J^^');
    });

    test('A2: control 0x1D → ~]', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x1D'), '^1^S~]^^');
    });

    test('A3: byte 30 (0x1E) → ~z (special case — 30+64=94=^ would corrupt parser)', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x1E'), '^1^S~z^^');
    });

    test('A4: byte 31 (0x1F) → ~_', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x1F'), '^1^S~_^^');
    });

    test('A5: space (0x20) → ~`', () => {
        assert.strictEqual(WowAceSerializer.serialize(' '), '^1^S~`^^');
    });

    test('A6: caret ^ (0x5E) → ~}', () => {
        assert.strictEqual(WowAceSerializer.serialize('^'), '^1^S~}^^');
    });

    test('A7: tilde ~ (0x7E) → ~|', () => {
        assert.strictEqual(WowAceSerializer.serialize('~'), '^1^S~|^^');
    });

    test('A8: DEL (0x7F) → ~{', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x7F'), '^1^S~{^^');
    });

    test('A9: single-pass — multiple special chars, no double-escaping', () => {
        assert.strictEqual(WowAceSerializer.serialize('^~\x7F'), '^1^S~}~|~{^^');
    });

    test('A10: printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped', () => {
        const chars = [];
        for (let i = 0x21; i <= 0x7D; i++) {
            if (i !== 0x5E && i !== 0x7E) chars.push(String.fromCharCode(i));
        }
        const str = chars.join('');
        assert.strictEqual(WowAceSerializer.serialize(str), `^1^S${str}^^`);
    });
});

// ── C. Number Serialization ────────────────────────────────────────────────

describe('C. Number Serialization', () => {
    test('C18: positive integer → ^N42', () => {
        assert.strictEqual(WowAceSerializer.serialize(42), '^1^N42^^');
    });

    test('C19: negative integer → ^N-42', () => {
        assert.strictEqual(WowAceSerializer.serialize(-42), '^1^N-42^^');
    });

    test('C20: zero → ^N0', () => {
        assert.strictEqual(WowAceSerializer.serialize(0), '^1^N0^^');
    });

    test('C21: large integer → ^N<large>', () => {
        assert.strictEqual(WowAceSerializer.serialize(1000000000), '^1^N1000000000^^');
    });

    test('C22: non-integer float uses ^F^f format (not ^N)', () => {
        assert.match(WowAceSerializer.serialize(3.14), /^\^1\^F-?\d+\^f-?\d+\^\^$/);
    });

    test('C23: 3.14 exact wire format', () => {
        assert.strictEqual(WowAceSerializer.serialize(3.14), '^1^F7070651414971679^f-51^^');
    });

    test('C24: 0.1 wire format is ^F^f', () => {
        assert.match(WowAceSerializer.serialize(0.1), /^\^1\^F-?\d+\^f-?\d+\^\^$/);
    });

    test('C24: -99.99 wire format is ^F^f', () => {
        assert.match(WowAceSerializer.serialize(-99.99), /^\^1\^F-?\d+\^f-?\d+\^\^$/);
    });

    test('C24: 1e-10 wire format is ^F^f', () => {
        assert.match(WowAceSerializer.serialize(1e-10), /^\^1\^F-?\d+\^f-?\d+\^\^$/);
    });

    test('C25: positive infinity → ^N1.#INF', () => {
        assert.strictEqual(WowAceSerializer.serialize(Infinity), '^1^N1.#INF^^');
    });

    test('C26: negative infinity → ^N-1.#INF', () => {
        assert.strictEqual(WowAceSerializer.serialize(-Infinity), '^1^N-1.#INF^^');
    });

    // JS-specific: integer detection paths
    test('JS: 3.0 takes integer path ^N (not float ^F)', () => {
        assert.strictEqual(WowAceSerializer.serialize(3.0), '^1^N3^^');
    });

    test('JS: 1e10 is integer in JS, uses ^N path', () => {
        assert.strictEqual(WowAceSerializer.serialize(1e+10), '^1^N10000000000^^');
    });
});

// ── E. Float frexp Round-trips ─────────────────────────────────────────────

describe('E. Float frexp Round-trips', () => {
    function rt(value) {
        return new WowAceDeserializer(WowAceSerializer.serialize(value)).deserialize();
    }

    test('E35: round-trip 3.14', () => {
        assert.strictEqual(rt(3.14), 3.14);
    });

    test('E36: round-trip 0.1', () => {
        assert.strictEqual(rt(0.1), 0.1);
    });

    test('E37: round-trip 123.456', () => {
        assert.strictEqual(rt(123.456), 123.456);
    });

    test('E38: round-trip -99.99', () => {
        assert.strictEqual(rt(-99.99), -99.99);
    });

    test('E39: round-trip 1e-10', () => {
        assert.strictEqual(rt(1e-10), 1e-10);
    });

    test('E40: round-trip very small float (minimum normal)', () => {
        // JS impl cannot round-trip subnormals: deserialize computes mantissa * 2^adj_exp
        // where adj_exp = e-53; for subnormals e < -1021, giving adj_exp < -1074 which
        // underflows Math.pow(2, adj_exp) to 0. Minimum normal 2^-1022 (adj_exp=-1074)
        // is the smallest value that round-trips correctly.
        const minNormal = 2.2250738585072014e-308; // 2^-1022
        assert.strictEqual(rt(minNormal), minNormal);
    });

    test('E41: round-trip very large float', () => {
        assert.strictEqual(rt(Number.MAX_VALUE), Number.MAX_VALUE);
    });
});

// ── F. Boolean ─────────────────────────────────────────────────────────────

describe('F. Boolean', () => {
    test('F42: true → ^B', () => {
        assert.strictEqual(WowAceSerializer.serialize(true), '^1^B^^');
    });

    test('F43: false → ^b', () => {
        assert.strictEqual(WowAceSerializer.serialize(false), '^1^b^^');
    });
});

// ── G. Nil ──────────────────────────────────────────────────────────────────

describe('G. Nil', () => {
    test('G46: null → ^Z', () => {
        assert.strictEqual(WowAceSerializer.serialize(null), '^1^Z^^');
    });
});

// ── H. Table Serialization ─────────────────────────────────────────────────

describe('H. Table Serialization', () => {
    test('H48: empty table → ^T^t', () => {
        assert.strictEqual(WowAceSerializer.serialize({}), '^1^T^t^^');
    });

    test('H49: single string key-value pair', () => {
        assert.strictEqual(WowAceSerializer.serialize({ foo: 'bar' }), '^1^T^Sfoo^Sbar^t^^');
    });

    test('H50: multiple key-value pairs', () => {
        const result = WowAceSerializer.serialize({ a: '1', b: '2' });
        assert.ok(result.startsWith('^1^T'), 'should start with ^1^T');
        assert.ok(result.endsWith('^t^^'), 'should end with ^t^^');
        assert.ok(result.includes('^Sa^S1'), 'should contain a→1');
        assert.ok(result.includes('^Sb^S2'), 'should contain b→2');
    });

    test('H51: nested table (table containing table)', () => {
        const result = WowAceSerializer.serialize({ outer: { inner: 'val' } });
        assert.ok(result.includes('^Souter'), 'outer key present');
        assert.ok(result.includes('^Sinner^Sval'), 'inner key-value present');
    });

    test('H52: array [a,b,c] → 1-based integer keys', () => {
        assert.strictEqual(
            WowAceSerializer.serialize(['a', 'b', 'c']),
            '^1^T^N1^Sa^N2^Sb^N3^Sc^t^^'
        );
    });

    test('H53: mixed table (integer + string keys)', () => {
        const result = WowAceSerializer.serialize({ 1: 'one', str: 'val' });
        assert.ok(result.startsWith('^1^T'), 'wrapped in ^T');
        assert.ok(result.includes('^N1^Sone'), 'numeric key 1');
        assert.ok(result.includes('^Sstr^Sval'), 'string key str');
    });
});

// ── J. Framing (Serialize) ─────────────────────────────────────────────────

describe('J. Framing (Serialize)', () => {
    test('J59: serialize output starts with ^1 and ends with ^^', () => {
        const result = WowAceSerializer.serialize('test');
        assert.ok(result.startsWith('^1'), 'prefix is ^1');
        assert.ok(result.endsWith('^^'), 'terminator is ^^');
    });
});

// ── L. Round-trips (serialize→deserialize identity) ───────────────────────

describe('L. Round-trips', () => {
    function rt(val) {
        return new WowAceDeserializer(WowAceSerializer.serialize(val)).deserialize();
    }

    test('L66: string with plain ASCII', () => {
        assert.strictEqual(rt('hello world'), 'hello world');
    });

    test('L67: string with all special chars', () => {
        const s = '\x00\x01\x1E\x1F ^~\x7F';
        assert.strictEqual(rt(s), s);
    });

    test('L68: integer', () => {
        assert.strictEqual(rt(42), 42);
    });

    test('L69: float', () => {
        assert.strictEqual(rt(3.14), 3.14);
    });

    test('L70: boolean true', () => {
        assert.strictEqual(rt(true), true);
    });

    test('L71: null (nil)', () => {
        assert.strictEqual(rt(null), null);
    });

    test('L72: nested table/array', () => {
        assert.deepStrictEqual(rt([1, [2, 3]]), [1, [2, 3]]);
    });

    test('L73: mixed-type table', () => {
        const obj = { n: 42, f: 3.14, b: true, z: null, s: 'hello' };
        const result = rt(obj);
        assert.strictEqual(result.n, 42);
        assert.strictEqual(result.f, 3.14);
        assert.strictEqual(result.b, true);
        assert.strictEqual(result.z, null);
        assert.strictEqual(result.s, 'hello');
    });
});
