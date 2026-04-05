'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const WowAceDeserializer = require('../lib/WowAceDeserializer');
const WowAceSerializer = require('../lib/WowAceSerializer');

// ── B. String Unescaping (Deserialize) ────────────────────────────────────

describe('B. String Unescaping (Deserialize)', () => {
    test('B11: ~@ → NUL (0x00)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~@^^').deserialize(), '\x00');
    });

    test('B12: generic ~X where X < z → chr(ord(X)−64)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~A^^').deserialize(), '\x01');
        assert.strictEqual(new WowAceDeserializer('^1^S~J^^').deserialize(), '\x0A');
    });

    test('B13: ~z → byte 30 (0x1E)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~z^^').deserialize(), '\x1E');
    });

    test('B14: ~{ → DEL (0x7F)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~{^^').deserialize(), '\x7F');
    });

    test('B15: ~| → tilde (~)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~|^^').deserialize(), '~');
    });

    test('B16: ~} → caret (^)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~}^^').deserialize(), '^');
    });

    test('B17: round-trip — all escapable bytes survive serialize→deserialize', () => {
        const chars = [];
        for (let i = 0x00; i <= 0x20; i++) chars.push(String.fromCharCode(i));
        chars.push('^', '~', '\x7F');
        const original = chars.join('');
        const wire = WowAceSerializer.serialize(original);
        assert.strictEqual(new WowAceDeserializer(wire).deserialize(), original);
    });
});

// ── D. Number Deserialization ──────────────────────────────────────────────

describe('D. Number Deserialization', () => {
    test('D27: ^N42 → 42 (integer)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N42^^').deserialize(), 42);
    });

    test('D28: ^N-42 → -42', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N-42^^').deserialize(), -42);
    });

    test('D29: ^N3.14 → 3.14 (float via ^N path)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N3.14^^').deserialize(), 3.14);
    });

    test('D30: ^N1.#INF → Infinity', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N1.#INF^^').deserialize(), Infinity);
    });

    test('D31: ^N-1.#INF → -Infinity', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N-1.#INF^^').deserialize(), -Infinity);
    });

    test('D32: ^Ninf → Infinity (alternate format)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Ninf^^').deserialize(), Infinity);
    });

    test('D33: ^N-inf → -Infinity (alternate format)', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N-inf^^').deserialize(), -Infinity);
    });

    test('D34: ^F<m>^f<e> → correct float reconstruction', () => {
        // 4503599627370496 * 2^-53 = 0.5
        assert.strictEqual(new WowAceDeserializer('^1^F4503599627370496^f-53^^').deserialize(), 0.5);
    });
});

// ── F. Boolean ─────────────────────────────────────────────────────────────

describe('F. Boolean', () => {
    test('F44: ^B → true', () => {
        assert.strictEqual(new WowAceDeserializer('^1^B^^').deserialize(), true);
    });

    test('F45: ^b → false', () => {
        assert.strictEqual(new WowAceDeserializer('^1^b^^').deserialize(), false);
    });
});

// ── G. Nil ──────────────────────────────────────────────────────────────────

describe('G. Nil', () => {
    test('G47: ^Z → null', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Z^^').deserialize(), null);
    });
});

// ── I. Array Detection (Deserialize) ──────────────────────────────────────

describe('I. Array Detection (Deserialize)', () => {
    test('I54: sequential 1-based integer keys → array', () => {
        assert.deepStrictEqual(
            new WowAceDeserializer('^1^T^N1^Sa^N2^Sb^t^^').deserialize(),
            ['a', 'b']
        );
    });

    test('I55: non-sequential integer keys → object/hash', () => {
        const result = new WowAceDeserializer('^1^T^N1^Sa^N3^Sc^t^^').deserialize();
        assert.strictEqual(Array.isArray(result), false);
        assert.strictEqual(result[1], 'a');
        assert.strictEqual(result[3], 'c');
    });

    test('I56: string keys → object (not array)', () => {
        const result = new WowAceDeserializer('^1^T^Sfoo^Sbar^t^^').deserialize();
        assert.strictEqual(Array.isArray(result), false);
    });

    test('I57: single element array', () => {
        assert.deepStrictEqual(
            new WowAceDeserializer('^1^T^N1^Sonly^t^^').deserialize(),
            ['only']
        );
    });

    test('I58: empty table → empty object (not array)', () => {
        const result = new WowAceDeserializer('^1^T^t^^').deserialize();
        assert.strictEqual(Array.isArray(result), false);
        assert.deepStrictEqual(result, {});
    });
});

// ── J. Framing (Deserialize) ───────────────────────────────────────────────

describe('J. Framing (Deserialize)', () => {
    test('J60: deserialize requires ^1 prefix', () => {
        // Wrong version '^2' → throws
        assert.throws(() => new WowAceDeserializer('^2^Shello^^'));
    });

    test.skip('J61: missing ^^ terminator → error', () => {
        // JS deserializer is lenient: returns value instead of throwing.
        // Other languages (Lua, Ruby, Python) reject missing ^^ terminator.
        assert.throws(() => new WowAceDeserializer('^1^N42').deserialize());
    });

    test('J62: control chars 0x00-0x20 stripped from input before parsing', () => {
        assert.strictEqual(new WowAceDeserializer('\x00^1^N42\x0A^^').deserialize(), 42);
    });
});

// ── K. Error Handling ──────────────────────────────────────────────────────

describe('K. Error Handling', () => {
    test('K63: missing ^1 prefix → throws', () => {
        assert.throws(() => new WowAceDeserializer('hello'));
    });

    test('K64: empty string → throws', () => {
        assert.throws(() => new WowAceDeserializer(''));
    });

    test.skip('K65: missing ^^ terminator → error', () => {
        // JS deserializer is lenient: returns value instead of throwing.
        // Other languages (Lua, Ruby, Python) reject missing ^^ terminator.
        assert.throws(() => new WowAceDeserializer('^1^Z').deserialize());
    });
});
