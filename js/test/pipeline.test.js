'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const Pipeline = require('../lib/Pipeline');

// Check if LibSerialize serialize+deserialize are available (task #10)
let libSerializeAvailable = false;
try {
    const { LibSerializeSerialize, LibSerializeDeserialize } = require('../lib/LibSerialize');
    libSerializeAvailable = typeof LibSerializeSerialize.serialize === 'function' &&
                            typeof LibSerializeDeserialize.deserialize === 'function';
} catch (_) {}

// ── Prefix encoding ────────────────────────────────────────────────────────

describe('Pipeline prefix encoding', () => {
    test('WA v1 uses ! prefix', () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 1, data: 'x', metadata: null });
        assert.ok(enc.startsWith('!'), `Expected ! prefix, got: ${enc.slice(0, 10)}`);
        assert.ok(!enc.startsWith('!WA:2!'));
        assert.ok(!enc.startsWith('!E1!'));
    });

    test('ElvUI uses !E1! prefix', () => {
        const enc = Pipeline.encode({ addon: 'elvui', version: 1, data: 'x', metadata: null });
        assert.ok(enc.startsWith('!E1!'));
    });

    test('legacy (v0) uses no prefix', () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 0, data: 'x', metadata: null });
        assert.ok(!enc.startsWith('!'));
    });

    test('WA v2 uses !WA:2! prefix', { skip: !libSerializeAvailable }, () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 2, data: { a: 1 }, metadata: null });
        assert.ok(enc.startsWith('!WA:2!'));
    });
});

// ── Prefix detection (via decode) ──────────────────────────────────────────

describe('Pipeline.decode prefix detection', () => {
    test('!E1! → elvui v1', () => {
        const enc = Pipeline.encode({ addon: 'elvui', version: 1, data: { a: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'elvui');
        assert.strictEqual(dec.version, 1);
    });

    test('! → weakauras v1', () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 1, data: { a: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'weakauras');
        assert.strictEqual(dec.version, 1);
    });

    test('no prefix → weakauras v0 (legacy)', () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 0, data: { a: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'weakauras');
        assert.strictEqual(dec.version, 0);
    });

    test('!WA:2! → weakauras v2', { skip: !libSerializeAvailable }, () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 2, data: { a: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.strictEqual(dec.addon, 'weakauras');
        assert.strictEqual(dec.version, 2);
    });
});

// ── ExportResult wrapper shape ─────────────────────────────────────────────

describe('Pipeline ExportResult structure', () => {
    test('decode returns all four fields', () => {
        const enc = Pipeline.encode({ addon: 'weakauras', version: 1, data: { x: 1 }, metadata: null });
        const dec = Pipeline.decode(enc);
        assert.ok('addon'    in dec, 'missing addon');
        assert.ok('version'  in dec, 'missing version');
        assert.ok('data'     in dec, 'missing data');
        assert.ok('metadata' in dec, 'missing metadata');
    });
});

// ── Encode→decode round-trips ──────────────────────────────────────────────

describe('Pipeline encode→decode round-trip', () => {
    test('WA v1 — string', () => {
        const orig = { addon: 'weakauras', version: 1, data: 'hello', metadata: null };
        const dec = Pipeline.decode(Pipeline.encode(orig));
        assert.strictEqual(dec.data, 'hello');
        assert.strictEqual(dec.addon, 'weakauras');
        assert.strictEqual(dec.version, 1);
        assert.strictEqual(dec.metadata, null);
    });

    test('WA v1 — table', () => {
        const data = { key: 'value', num: 42 };
        const dec = Pipeline.decode(Pipeline.encode({ addon: 'weakauras', version: 1, data, metadata: null }));
        assert.strictEqual(dec.data.key, 'value');
        assert.strictEqual(dec.data.num, 42);
    });

    test('WA v1 — array', () => {
        const data = ['a', 'b', 'c'];
        const dec = Pipeline.decode(Pipeline.encode({ addon: 'weakauras', version: 1, data, metadata: null }));
        assert.deepStrictEqual(dec.data, data);
    });

    test('WA v1 — nested table', () => {
        const data = { outer: { inner: 99 }, list: [1, 2] };
        const dec = Pipeline.decode(Pipeline.encode({ addon: 'weakauras', version: 1, data, metadata: null }));
        assert.strictEqual(dec.data.outer.inner, 99);
        assert.deepStrictEqual(dec.data.list, [1, 2]);
    });

    test('legacy v0 — round-trip', () => {
        const data = { flag: true, n: -5 };
        const dec = Pipeline.decode(Pipeline.encode({ addon: 'weakauras', version: 0, data, metadata: null }));
        assert.strictEqual(dec.data.flag, true);
        assert.strictEqual(dec.data.n, -5);
    });

    test('WA v2 — round-trip', { skip: !libSerializeAvailable }, () => {
        const data = { key: 'v2data', num: 7 };
        const dec = Pipeline.decode(Pipeline.encode({ addon: 'weakauras', version: 2, data, metadata: null }));
        assert.strictEqual(dec.data.key, 'v2data');
        assert.strictEqual(dec.data.num, 7);
    });
});

// ── ElvUI metadata ─────────────────────────────────────────────────────────

describe('Pipeline ElvUI metadata', () => {
    test('round-trip preserves metadata profileType and profileKey', () => {
        const metadata = { profileType: 'profile', profileKey: 'Default' };
        const orig = { addon: 'elvui', version: 1, data: { setting: 1 }, metadata };
        const dec = Pipeline.decode(Pipeline.encode(orig));
        assert.strictEqual(dec.addon, 'elvui');
        assert.deepStrictEqual(dec.metadata, metadata);
        assert.strictEqual(dec.data.setting, 1);
    });

    test('ElvUI without metadata → null metadata after decode', () => {
        const orig = { addon: 'elvui', version: 1, data: { a: 1 }, metadata: null };
        const dec = Pipeline.decode(Pipeline.encode(orig));
        assert.strictEqual(dec.metadata, null);
    });
});
