'use strict';
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const LibCompress = require('../lib/LibCompress');

describe('LibCompress', () => {
  describe('method 0x01 (uncompressed)', () => {
    it('passes through raw bytes', () => {
      const wire = Buffer.from([0x01, 0x68, 0x65, 0x6c, 0x6c, 0x6f]);
      assert.equal(LibCompress.decompress(wire).toString('binary'), 'hello');
    });

    it('handles empty payload', () => {
      const wire = Buffer.from([0x01]);
      assert.equal(LibCompress.decompress(wire).length, 0);
    });
  });

  describe('method 0x02 (LZW)', () => {
    it('decompresses single-byte codes', () => {
      const wire = Buffer.from([0x02, 104, 101, 108, 108, 111]);
      assert.equal(LibCompress.decompress(wire).toString('binary'), 'hello');
    });

    it('decompresses with dictionary hits', () => {
      // Codes: 65,66,256,258,66 → "ABABABAB"
      const wire = Buffer.from([0x02, 65, 66, 0xFE, 2, 2, 0xFE, 4, 2, 66]);
      assert.equal(LibCompress.decompress(wire).toString('binary'), 'ABABABAB');
    });

    it('decompresses single char', () => {
      const wire = Buffer.from([0x02, 65]);
      assert.equal(LibCompress.decompress(wire).toString('binary'), 'A');
    });
  });

  describe('method 0x03 (Huffman)', () => {
    it('decompresses a minimal Huffman stream', () => {
      // 1 symbol ('A'=65), orig_size=3, code=0 (1-bit)
      const wire = Buffer.from([0x03, 0x00, 0x03, 0x00, 0x00, 0x41, 0x06]);
      assert.equal(LibCompress.decompress(wire).toString('binary'), 'AAA');
    });
  });

  describe('error handling', () => {
    it('throws on empty input', () => {
      assert.throws(() => LibCompress.decompress(Buffer.alloc(0)), /empty/);
    });

    it('throws on unknown method', () => {
      assert.throws(() => LibCompress.decompress(Buffer.from([0x05, 0x00])), /Unknown compression method/);
    });
  });
});
