'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const WowAceSerializer = require('../lib/WowAceSerializer');
const WowAceDeserializer = require('../lib/WowAceDeserializer');
const LuaDeflate = require('../lib/LuaDeflate');

const FIXTURES_PATH = path.join(__dirname, '../../testdata/fixtures.json');
const fixtures = JSON.parse(fs.readFileSync(FIXTURES_PATH, 'utf8'));
const ld = new LuaDeflate();

// Convert a fixture input (which may contain __type__ wrappers) to a native JS value.
function toNativeValue(input) {
    if (input === null || input === undefined) return null;
    if (Array.isArray(input)) return input.map(toNativeValue);
    if (typeof input === 'object') {
        switch (input.__type__) {
            case 'infinity':     return Infinity;
            case 'neg_infinity': return -Infinity;
            case 'float':        return input.value;
            case 'bytes':        return Buffer.from(input.hex, 'hex').toString('binary');
        }
        return Object.fromEntries(
            Object.entries(input).map(([k, v]) => [k, toNativeValue(v)])
        );
    }
    return input; // boolean, number, string pass through
}

function hexToBytes(hex) {
    return Buffer.from(hex, 'hex').toString('binary');
}

function bytesToHex(str) {
    return Buffer.from(str, 'binary').toString('hex');
}

// ── AceSerializer: deserialize ─────────────────────────────────────────────
// For each fixture: deserialize ace_serialized and assert it equals input.

describe('AceSerializer fixtures — deserialize', () => {
    for (const fixture of fixtures.ace_serializer) {
        test(fixture.name, () => {
            const result = new WowAceDeserializer(fixture.ace_serialized).deserialize();
            assert.deepStrictEqual(result, toNativeValue(fixture.input));
        });
    }
});

// ── AceSerializer: serialize ───────────────────────────────────────────────
// For each deterministic fixture: serialize input and assert it equals ace_serialized.
// Fixtures with serialize_deterministic: false are skipped (non-deterministic key order).

describe('AceSerializer fixtures — serialize', () => {
    for (const fixture of fixtures.ace_serializer) {
        if (fixture.serialize_deterministic === false) continue;
        test(fixture.name, () => {
            const result = WowAceSerializer.serialize(toNativeValue(fixture.input));
            assert.strictEqual(result, fixture.ace_serialized);
        });
    }
});

// ── AceSerializer: round-trip ──────────────────────────────────────────────
// deserialize(ace_serialized) -> value1 -> serialize(value1) -> deserialize -> value2
// Assert value2 deeply equals value1 (internal consistency).

describe('AceSerializer fixtures — round-trip', () => {
    for (const fixture of fixtures.ace_serializer) {
        test(fixture.name, () => {
            const value1 = new WowAceDeserializer(fixture.ace_serialized).deserialize();
            const wire2 = WowAceSerializer.serialize(value1);
            const value2 = new WowAceDeserializer(wire2).deserialize();
            assert.deepStrictEqual(value2, value1);
        });
    }
});

// ── LuaDeflate: encode ─────────────────────────────────────────────────────

describe('LuaDeflate fixtures — encode', () => {
    for (const fixture of fixtures.lua_deflate) {
        test(fixture.name, () => {
            const input = hexToBytes(fixture.input_hex);
            assert.strictEqual(ld.encodeForPrint(input), fixture.encoded);
        });
    }
});

// ── LuaDeflate: decode ─────────────────────────────────────────────────────

describe('LuaDeflate fixtures — decode', () => {
    for (const fixture of fixtures.lua_deflate) {
        test(fixture.name, () => {
            const decoded = ld.decodeForPrint(fixture.encoded);
            assert.strictEqual(bytesToHex(decoded), fixture.input_hex);
        });
    }
});
