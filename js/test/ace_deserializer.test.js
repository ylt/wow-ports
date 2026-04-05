'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const WowAceDeserializer = require('../lib/WowAceDeserializer');
const WowAceSerializer = require('../lib/WowAceSerializer');

// ── Primitives ─────────────────────────────────────────────────────────────

describe('primitive deserialization', () => {
    test('string', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Shello^^').deserialize(), 'hello');
    });

    test('integer', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N42^^').deserialize(), 42);
    });

    test('negative integer', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N-7^^').deserialize(), -7);
    });

    test('boolean true', () => {
        assert.strictEqual(new WowAceDeserializer('^1^B^^').deserialize(), true);
    });

    test('boolean false', () => {
        assert.strictEqual(new WowAceDeserializer('^1^b^^').deserialize(), false);
    });

    test('null', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Z^^').deserialize(), null);
    });

    test('infinity', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N1.#INF^^').deserialize(), Infinity);
    });

    test('negative infinity', () => {
        assert.strictEqual(new WowAceDeserializer('^1^N-1.#INF^^').deserialize(), -Infinity);
    });
});

// ── Floats (stream mechanics) ──────────────────────────────────────────────

describe('float deserialization', () => {
    test('0.5 frexp wire format', () => {
        assert.strictEqual(new WowAceDeserializer('^1^F4503599627370496^f-53^^').deserialize(), 0.5);
    });

    test('round-trip 3.14', () => {
        const wire = WowAceSerializer.serialize(3.14);
        assert.strictEqual(new WowAceDeserializer(wire).deserialize(), 3.14);
    });

    test('round-trip negative float', () => {
        const wire = WowAceSerializer.serialize(-0.25);
        assert.strictEqual(new WowAceDeserializer(wire).deserialize(), -0.25);
    });
});

// ── Tables ─────────────────────────────────────────────────────────────────

describe('table deserialization', () => {
    test('empty table', () => {
        assert.deepStrictEqual(new WowAceDeserializer('^1^T^t^^').deserialize(), {});
    });

    test('single string key-value', () => {
        assert.deepStrictEqual(
            new WowAceDeserializer('^1^T^Sfoo^Sbar^t^^').deserialize(),
            { foo: 'bar' }
        );
    });

    test('multiple string pairs', () => {
        assert.deepStrictEqual(
            new WowAceDeserializer('^1^T^Sa^S1^Sb^S2^t^^').deserialize(),
            { a: '1', b: '2' }
        );
    });

    test('nested table with string keys', () => {
        assert.deepStrictEqual(
            new WowAceDeserializer('^1^T^Souter^T^Sinner^Sval^t^t^^').deserialize(),
            { outer: { inner: 'val' } }
        );
    });

    test('mixed value types in table', () => {
        const result = new WowAceDeserializer('^1^T^Sn^N5^Sb^B^Sz^Z^t^^').deserialize();
        assert.strictEqual(result.n, 5);
        assert.strictEqual(result.b, true);
        assert.strictEqual(result.z, null);
    });
});

// ── Escaped strings (stream mechanics) ────────────────────────────────────

describe('escaped string deserialization', () => {
    test('escaped caret', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Shello~}world^^').deserialize(), 'hello^world');
    });

    test('escaped tilde', () => {
        assert.strictEqual(new WowAceDeserializer('^1^Shello~|world^^').deserialize(), 'hello~world');
    });

    test('escaped DEL', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~{^^').deserialize(), '\x7F');
    });

    test('escaped byte 30', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~z^^').deserialize(), '\x1E');
    });

    test('full round-trip with all special chars', () => {
        const original = 'foo^bar~baz\x7F\x1E';
        const wire = WowAceSerializer.serialize(original);
        assert.strictEqual(new WowAceDeserializer(wire).deserialize(), original);
    });
});

// ── Array detection (Task 3.1) ─────────────────────────────────────────────

describe('array detection', () => {
    test('sequential 1-based int keys → array', () => {
        // {1: "a", 2: "b"} → ["a", "b"]
        const result = new WowAceDeserializer('^1^T^N1^Sa^N2^Sb^t^^').deserialize();
        assert.deepStrictEqual(result, ['a', 'b']);
    });

    test('non-sequential keys → object', () => {
        // {1: "a", 3: "c"} stays as object
        const result = new WowAceDeserializer('^1^T^N1^Sa^N3^Sc^t^^').deserialize();
        assert.strictEqual(Array.isArray(result), false);
        assert.strictEqual(result[1], 'a');
        assert.strictEqual(result[3], 'c');
    });

    test('string keys → object (not array)', () => {
        const result = new WowAceDeserializer('^1^T^Sfoo^Sbar^t^^').deserialize();
        assert.strictEqual(Array.isArray(result), false);
    });

    test('single element array', () => {
        const result = new WowAceDeserializer('^1^T^N1^Sonly^t^^').deserialize();
        assert.deepStrictEqual(result, ['only']);
    });

    test('nested array tables', () => {
        // {1: {1: "a"}} → [["a"]]
        const result = new WowAceDeserializer('^1^T^N1^T^N1^Sa^t^t^^').deserialize();
        assert.deepStrictEqual(result, [['a']]);
    });

    test('round-trip array through serializer', () => {
        const WowAceSerializer = require('../lib/WowAceSerializer');
        const original = ['x', 'y', 'z'];
        const wire = WowAceSerializer.serialize(original);
        assert.deepStrictEqual(new WowAceDeserializer(wire).deserialize(), original);
    });
});

// ── Malformed input ────────────────────────────────────────────────────────

describe('malformed input', () => {
    test('missing ^1 prefix throws', () => {
        assert.throws(() => new WowAceDeserializer('hello'));
    });

    test('empty string throws', () => {
        assert.throws(() => new WowAceDeserializer(''));
    });
});
