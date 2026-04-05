'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { LibSerializeDeserialize, LibSerializeSerialize } = require('../lib/LibSerialize');

// Helper: hex string → Buffer
function h(hex) { return Buffer.from(hex.replace(/\s+/g, ''), 'hex'); }

// Helper: Buffer → hex string
function toHex(buf) {
  return Buffer.isBuffer(buf)
    ? [...buf].map(b => b.toString(16).padStart(2, '0')).join(' ')
    : [...buf].map(b => b.toString(16).padStart(2, '0')).join(' ');
}

// Reference wire bytes from Ruby (verified manually)
// Format: version byte 01 + encoded value
const FIXTURES = {
  nil:    '01 00',
  true_:  '01 60',
  false_: '01 68',
  int0:   '01 01',   // embedded: 0*2+1 = 1
  int1:   '01 03',   // embedded: 1*2+1 = 3
  int127: '01 ff',   // embedded: 127*2+1 = 255
  intN1:  '01 1c 00', // 2-byte small neg: -1
  intN100:'01 4c 06', // 2-byte small neg: -100
  int256: '01 08 01 00',        // NUM_16_POS = 1 → type byte 8
  int65535:'01 08 ff ff',       // NUM_16_POS
  int65536:'01 18 01 00 00',    // NUM_24_POS = 3 → type byte 24
  int1M:  '01 18 0f 42 40',     // NUM_24_POS: 1000000
  intN4096:'01 10 10 00',       // NUM_16_NEG = 2 → type byte 16
  float15:'01 50 03 31 2e 35',  // FLOATSTR_POS: "1.5"
  float3p14159: '01 48 40 09 21 f9 f0 1b 86 6e', // NUM_FLOAT
  strEmpty: '01 02',            // embedded STRING count=0
  strA:   '01 12 61',          // embedded STRING count=1, 'a'
  strAB:  '01 22 61 62',       // embedded STRING count=2
  strABC: '01 32 61 62 63',    // embedded STRING count=3
  strHello: '01 52 68 65 6c 6c 6f', // embedded STRING count=5
  arrEmpty: '01 0a',           // embedded ARRAY count=0
  arr123:  '01 3a 03 05 07',   // embedded ARRAY count=3: 1,2,3
  tblEmpty:'01 06',            // embedded TABLE count=0
  tblA1:  '01 16 12 61 03',    // embedded TABLE count=1: "a"→1
  tblA1B2:'01 26 12 61 03 12 62 05', // embedded TABLE count=2
};

// ── Deserialization ────────────────────────────────────────────────────────

describe('deserialize primitives', () => {
  test('nil', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.nil)), null));
  test('true', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.true_)), true));
  test('false', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.false_)), false));
  test('0', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int0)), 0));
  test('1', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int1)), 1));
  test('127 (max embedded)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int127)), 127));
  test('-1 (2-byte neg)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.intN1)), -1));
  test('-100 (2-byte neg)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.intN100)), -100));
  test('256 (NUM_16_POS)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int256)), 256));
  test('65535 (NUM_16_POS)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int65535)), 65535));
  test('65536 (NUM_24_POS)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int65536)), 65536));
  test('1000000 (NUM_24_POS)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.int1M)), 1000000));
  test('-4096 (NUM_16_NEG)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.intN4096)), -4096));
});

describe('deserialize floats', () => {
  test('1.5 (floatstr)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.float15)), 1.5));
  test('3.14159 (binary float)', () => {
    const val = LibSerializeDeserialize.deserialize(h(FIXTURES.float3p14159));
    assert.ok(Math.abs(val - 3.14159) < 1e-10, `Expected ~3.14159, got ${val}`);
  });
});

describe('deserialize strings', () => {
  test('empty string', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.strEmpty)), ''));
  test('"a"', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.strA)), 'a'));
  test('"ab"', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.strAB)), 'ab'));
  test('"abc"', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.strABC)), 'abc'));
  test('"hello" (embedded)', () => assert.strictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.strHello)), 'hello'));

  test('16-char string (STR_8 / length-prefixed)', () => {
    const wire = h('01 70 10' + ' 61'.repeat(16));
    assert.strictEqual(LibSerializeDeserialize.deserialize(wire), 'a'.repeat(16));
  });

  test('string ref (second occurrence returns same value)', () => {
    // 3-element array: ["hello", "world", "hello"] with correct string ref encoding
    // We build this with JS serializer and verify round-trip
    const input = ['hello', 'world', 'hello'];
    const wire = LibSerializeSerialize.serialize(input);
    const result = LibSerializeDeserialize.deserialize(wire);
    assert.deepStrictEqual(result, input);
  });
});

describe('deserialize arrays', () => {
  test('empty array', () => assert.deepStrictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.arrEmpty)), []));
  test('[1,2,3]', () => assert.deepStrictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.arr123)), [1, 2, 3]));

  test('nested array', () => {
    const wire = h('01 2a 2a 03 05 2a 07 09');
    assert.deepStrictEqual(LibSerializeDeserialize.deserialize(wire), [[1, 2], [3, 4]]);
  });
});

describe('deserialize tables', () => {
  test('empty table', () => assert.deepStrictEqual(LibSerializeDeserialize.deserialize(h(FIXTURES.tblEmpty)), {}));

  test('{a:1}', () => {
    const result = LibSerializeDeserialize.deserialize(h(FIXTURES.tblA1));
    assert.strictEqual(result['a'], 1);
  });

  test('{a:1, b:2}', () => {
    const result = LibSerializeDeserialize.deserialize(h(FIXTURES.tblA1B2));
    assert.strictEqual(result['a'], 1);
    assert.strictEqual(result['b'], 2);
  });
});

// ── Serialization ──────────────────────────────────────────────────────────

describe('serialize primitives', () => {
  test('null', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(null)), FIXTURES.nil));
  test('true', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(true)), FIXTURES.true_));
  test('false', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(false)), FIXTURES.false_));
  test('0', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(0)), FIXTURES.int0));
  test('1', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(1)), FIXTURES.int1));
  test('127', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(127)), FIXTURES.int127));
  test('-1', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(-1)), FIXTURES.intN1));
  test('-100', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(-100)), FIXTURES.intN100));
  test('256', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(256)), FIXTURES.int256));
  test('65535', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(65535)), FIXTURES.int65535));
  test('65536', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(65536)), FIXTURES.int65536));
  test('1000000', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(1000000)), FIXTURES.int1M));
  test('-4096', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(-4096)), FIXTURES.intN4096));
});

describe('serialize integers that crash Ruby (bugs fixed in JS)', () => {
  test('128 (1-byte value uses 2-byte encoding)', () => {
    const wire = LibSerializeSerialize.serialize(128);
    assert.strictEqual(LibSerializeDeserialize.deserialize(wire), 128);
  });
  test('255', () => {
    const wire = LibSerializeSerialize.serialize(255);
    assert.strictEqual(LibSerializeDeserialize.deserialize(wire), 255);
  });
});

describe('serialize floats', () => {
  test('1.5 (string-encoded)', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize(1.5)), FIXTURES.float15));
  test('3.14159 (binary float)', () => {
    const wire = LibSerializeSerialize.serialize(3.14159);
    assert.strictEqual(toHex(wire), FIXTURES.float3p14159);
  });
  test('-2.5 round-trip', () => {
    assert.strictEqual(LibSerializeDeserialize.deserialize(LibSerializeSerialize.serialize(-2.5)), -2.5);
  });
});

describe('serialize strings', () => {
  test('empty', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize('')), FIXTURES.strEmpty));
  test('"a"', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize('a')), FIXTURES.strA));
  test('"hello"', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize('hello')), FIXTURES.strHello));
});

describe('serialize arrays', () => {
  test('[]', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize([])), FIXTURES.arrEmpty));
  test('[1,2,3]', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize([1, 2, 3])), FIXTURES.arr123));
});

describe('serialize tables', () => {
  test('{}', () => assert.strictEqual(toHex(LibSerializeSerialize.serialize({})), FIXTURES.tblEmpty));
});

// ── Round-trip ─────────────────────────────────────────────────────────────

describe('round-trip', () => {
  const cases = [
    ['null', null],
    ['true', true],
    ['false', false],
    ['0', 0],
    ['127', 127],
    ['-1', -1],
    ['-4095', -4095],
    ['256', 256],
    ['1000000', 1000000],
    ['1.5', 1.5],
    ['0.001', 0.001],
    ['-2.5', -2.5],
    ['""', ''],
    ['"hello"', 'hello'],
    ['[]', []],
    ['[1,2,3]', [1, 2, 3]],
    ['[[1,2],[3,4]]', [[1, 2], [3, 4]]],
    ['{}', {}],
    ['{a:1}', { a: 1 }],
    ['nested {x:[1,2,3],y:null}', { x: [1, 2, 3], y: null }],
    ['string refs: [hello,world,hello]', ['hello', 'world', 'hello']],
  ];

  for (const [name, value] of cases) {
    test(name, () => {
      const wire = LibSerializeSerialize.serialize(value);
      const result = LibSerializeDeserialize.deserialize(wire);
      assert.deepStrictEqual(result, value);
    });
  }
});

// ── Cross-language fixtures (Ruby → JS) ───────────────────────────────────

describe('cross-language: Ruby-serialized bytes → JS deserialize', () => {
  // These bytes were generated by Ruby's LibSerializeSerialize (with nil+int bugs fixed)
  // Only values that Ruby can serialize correctly (no string/table refs)

  test('nil (Ruby wire)', () => {
    assert.strictEqual(LibSerializeDeserialize.deserialize(h('01 00')), null);
  });
  test('true (Ruby wire)', () => {
    assert.strictEqual(LibSerializeDeserialize.deserialize(h('01 60')), true);
  });
  test('[1,2,3] (Ruby wire)', () => {
    assert.deepStrictEqual(LibSerializeDeserialize.deserialize(h('01 3a 03 05 07')), [1, 2, 3]);
  });
  test('1000000 (Ruby wire)', () => {
    assert.strictEqual(LibSerializeDeserialize.deserialize(h('01 18 0f 42 40')), 1000000);
  });
  test('{a:1,b:2} (Ruby wire)', () => {
    const result = LibSerializeDeserialize.deserialize(h('01 26 12 61 03 12 62 05'));
    assert.strictEqual(result['a'], 1);
    assert.strictEqual(result['b'], 2);
  });
});
