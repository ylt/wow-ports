'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const WowCbor = require('../lib/WowCbor');
const Pipeline = require('../lib/Pipeline');

// ── WowCbor.decode / encode round-trip ────────────────────────────────────

describe('WowCbor encode→decode round-trip', () => {
    test('string value', () => {
        const data = 'hello world';
        assert.strictEqual(WowCbor.decode(WowCbor.encode(data)), data);
    });

    test('integer value', () => {
        assert.strictEqual(WowCbor.decode(WowCbor.encode(42)), 42);
    });

    test('boolean true', () => {
        assert.strictEqual(WowCbor.decode(WowCbor.encode(true)), true);
    });

    test('null value', () => {
        assert.strictEqual(WowCbor.decode(WowCbor.encode(null)), null);
    });

    test('string-keyed object', () => {
        const data = { key: 'value', num: 7 };
        const result = WowCbor.decode(WowCbor.encode(data));
        assert.strictEqual(result.key, 'value');
        assert.strictEqual(result.num, 7);
    });

    test('array', () => {
        const data = ['a', 'b', 'c'];
        assert.deepStrictEqual(WowCbor.decode(WowCbor.encode(data)), data);
    });
});

// ── Byte string conversion ─────────────────────────────────────────────────

describe('WowCbor byte string → UTF-8 conversion', () => {
    test('Uint8Array is converted to UTF-8 string', () => {
        const bytes = Buffer.from('hello', 'utf8');
        // Build CBOR byte string manually: type 2, length 5, then bytes
        // CBOR: 0x45 = type 2 (byte string), len 5, followed by "hello"
        const cbor = Buffer.concat([Buffer.from([0x45]), bytes]);
        const result = WowCbor.decode(cbor);
        assert.strictEqual(result, 'hello');
    });

    test('nested byte string in object is converted', () => {
        const { encode } = require('cbor-x');
        // Encode an object containing a byte string using cbor-x
        const raw = encode({ key: Buffer.from('world', 'utf8') });
        const result = WowCbor.decode(raw);
        assert.strictEqual(result.key, 'world');
    });
});

// ── Array detection ────────────────────────────────────────────────────────

describe('WowCbor array detection', () => {
    test('sequential 1-based int keys → array', () => {
        const { encode } = require('cbor-x');
        // cbor-x encodes JS objects with string keys; use a Map to force int keys
        const m = new Map([[1, 'a'], [2, 'b'], [3, 'c']]);
        const raw = encode(m);
        const result = WowCbor.decode(raw);
        assert.deepStrictEqual(result, ['a', 'b', 'c']);
    });

    test('non-sequential int keys stay as object', () => {
        const { encode } = require('cbor-x');
        const m = new Map([[1, 'a'], [3, 'c']]);
        const raw = encode(m);
        const result = WowCbor.decode(raw);
        // Should NOT be converted to array
        assert.ok(!Array.isArray(result));
    });

    test('string-keyed object stays as object', () => {
        const data = { a: 1, b: 2 };
        const result = WowCbor.decode(WowCbor.encode(data));
        assert.ok(!Array.isArray(result));
        assert.strictEqual(result.a, 1);
    });
});

// ── Pipeline Plater v2 routing ─────────────────────────────────────────────

describe('Pipeline Plater v2 prefix', () => {
    test('encodes with !PLATER:2! prefix', () => {
        const enc = Pipeline.encode({ addon: 'plater', version: 2, data: { x: 1 }, metadata: null });
        assert.ok(enc.startsWith('!PLATER:2!'));
    });

    test('decodes !PLATER:2! → plater v2', () => {
        const enc = Pipeline.encode({ addon: 'plater', version: 2, data: { x: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'plater');
        assert.strictEqual(dec.version, 2);
    });

    test('Plater v2 round-trip preserves data', () => {
        const data = { profile: 'Default', enabled: true, level: 5 };
        const enc = Pipeline.encode({ addon: 'plater', version: 2, data, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.data.profile, 'Default');
        assert.strictEqual(dec.data.enabled, true);
        assert.strictEqual(dec.data.level, 5);
    });

    test('!PLATER:2! is detected before ! catch-all', () => {
        const enc = Pipeline.encode({ addon: 'plater', version: 2, data: 'test', metadata: null });
        assert.ok(enc.startsWith('!PLATER:2!'));
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'plater');
        assert.strictEqual(dec.version, 2);
    });
});
