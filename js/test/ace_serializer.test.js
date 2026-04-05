'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const WowAceSerializer = require('../lib/WowAceSerializer');
const WowAceDeserializer = require('../lib/WowAceDeserializer');

// ── Escape character serialization (Task 1.2) ──────────────────────────────

describe('escape character serialization', () => {
    test('^ serializes to ~}', () => {
        assert.strictEqual(WowAceSerializer.serialize('^'), '^1^S~}^^');
    });

    test('~ serializes to ~|', () => {
        assert.strictEqual(WowAceSerializer.serialize('~'), '^1^S~|^^');
    });

    test('DEL (0x7F) serializes to ~{', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x7F'), '^1^S~{^^');
    });

    test('byte 30 (0x1E) serializes to ~z', () => {
        assert.strictEqual(WowAceSerializer.serialize('\x1E'), '^1^S~z^^');
    });

    test('space (0x20) serializes to ~`', () => {
        assert.strictEqual(WowAceSerializer.serialize(' '), '^1^S~`^^');
    });

    test('multi-special-char: single-pass, no double-escaping', () => {
        assert.strictEqual(WowAceSerializer.serialize('^~\x7F'), '^1^S~}~|~{^^');
    });
});

// ── Escape character deserialization (Task 1.2) ────────────────────────────

describe('escape character deserialization', () => {
    test('~} decodes to ^', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~}^^').deserialize(), '^');
    });

    test('~| decodes to ~', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~|^^').deserialize(), '~');
    });

    test('~{ decodes to DEL', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~{^^').deserialize(), '\x7F');
    });

    test('~z decodes to byte 30', () => {
        assert.strictEqual(new WowAceDeserializer('^1^S~z^^').deserialize(), '\x1E');
    });

    test('round-trip: string with all special chars', () => {
        const original = 'hello^world~test\x7F\x1E end';
        const serialized = WowAceSerializer.serialize(original);
        assert.strictEqual(new WowAceDeserializer(serialized).deserialize(), original);
    });
});

// ── Float serialization (Task 1.4) ─────────────────────────────────────────

describe('float serialization', () => {
    test('3.14 produces correct frexp wire format', () => {
        // frexp(3.14): m≈0.785, e=2 → int_mantissa=floor(m*2^53), adj_exp=e-53
        // Actual JS double: floor(0.785... * 2^53) = 7070651414971679
        const result = WowAceSerializer.serialize(3.14);
        assert.strictEqual(result, '^1^F7070651414971679^f-51^^');
    });

    test('3.0 uses integer path (^N), not float path', () => {
        assert.strictEqual(WowAceSerializer.serialize(3.0), '^1^N3^^');
    });

    test('round-trip 0.1', () => {
        const s = WowAceSerializer.serialize(0.1);
        const [, mantStr, expStr] = s.match(/\^F(-?\d+)\^f(-?\d+)/) || [];
        assert.ok(mantStr, `Expected ^F...^f... format, got: ${s}`);
        const val = parseInt(mantStr, 10) * Math.pow(2, parseInt(expStr, 10));
        assert.ok(Math.abs(val - 0.1) < Number.EPSILON * 2, `Round-trip failed: ${val}`);
    });

    test('round-trip 123.456', () => {
        const s = WowAceSerializer.serialize(123.456);
        const [, mantStr, expStr] = s.match(/\^F(-?\d+)\^f(-?\d+)/) || [];
        const val = parseInt(mantStr, 10) * Math.pow(2, parseInt(expStr, 10));
        assert.ok(Math.abs(val - 123.456) < Number.EPSILON * 256, `Round-trip failed: ${val}`);
    });

    test('round-trip -99.99', () => {
        const s = WowAceSerializer.serialize(-99.99);
        const [, mantStr, expStr] = s.match(/\^F(-?\d+)\^f(-?\d+)/) || [];
        const val = parseInt(mantStr, 10) * Math.pow(2, parseInt(expStr, 10));
        assert.ok(Math.abs(val - (-99.99)) < Number.EPSILON * 256, `Round-trip failed: ${val}`);
    });

    test('round-trip 1e-10', () => {
        const s = WowAceSerializer.serialize(1e-10);
        const [, mantStr, expStr] = s.match(/\^F(-?\d+)\^f(-?\d+)/) || [];
        const val = parseInt(mantStr, 10) * Math.pow(2, parseInt(expStr, 10));
        assert.ok(Math.abs(val - 1e-10) < Number.EPSILON * 1e-10 * 2, `Round-trip failed: ${val}`);
    });

    test('1e+10 is integer in JS, uses ^N path', () => {
        // Number.isInteger(1e10) === true, so it takes the integer path
        assert.strictEqual(WowAceSerializer.serialize(1e+10), '^1^N10000000000^^');
    });
});

// ── Float deserialization (Task 1.5) ──────────────────────────────────────

describe('float deserialization', () => {
    test('deserialize 3.14 wire format (exact round-trip)', () => {
        const wire = '^1^F7070651414971679^f-51^^';
        const val = new WowAceDeserializer(wire).deserialize();
        assert.strictEqual(val, 3.14);
    });

    test('deserialize 0.5 = 4503599627370496 * 2^-53', () => {
        // frexp(0.5): m=0.5, e=0 → int_m=2^52, adj_e=-53
        const d = new WowAceDeserializer('^1^F4503599627370496^f-53^^');
        assert.strictEqual(d.deserialize(), 0.5);
    });
});
