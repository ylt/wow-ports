'use strict';

/**
 * Clean-room implementation of LibCompress decompression.
 *
 * Written from the wire format specification only — NOT derived from
 * the GPL-licensed LibCompress.lua source code.
 *
 * Method markers: 0x01 = uncompressed, 0x02 = LZW, 0x03 = Huffman
 */

class LibCompress {
  static decompress(data) {
    if (!data || data.length === 0) throw new Error('Cannot decompress empty data');
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data, 'binary');
    const method = buf[0];
    switch (method) {
      case 1: return buf.slice(1);
      case 2: return LibCompress.decompressLZW(buf);
      case 3: return LibCompress.decompressHuffman(buf);
      default: throw new Error(`Unknown compression method (${method})`);
    }
  }

  // ── LZW ──────────────────────────────────────────────────────────────────

  static decompressLZW(buf) {
    let pos = 1; // skip method byte
    const dict = new Array(256);
    for (let i = 0; i < 256; i++) dict[i] = String.fromCharCode(i);
    let dictSize = 256;

    let [code, delta] = readCode(buf, pos);
    pos += delta;
    let w = dict[code];
    const result = [w];

    while (pos < buf.length) {
      [code, delta] = readCode(buf, pos);
      pos += delta;
      const entry = code < dictSize ? dict[code] : w + w[0];
      result.push(entry);
      dict[dictSize] = w + entry[0];
      dictSize++;
      w = entry;
    }

    return Buffer.from(result.join(''), 'binary');
  }

  // ── Huffman ──────────────────────────────────────────────────────────────

  static decompressHuffman(buf) {
    const bufSize = buf.length;

    // Header
    const numSymbols = buf[1] + 1;
    const origSize = buf[2] | (buf[3] << 8) | (buf[4] << 16);
    if (origSize === 0) return Buffer.alloc(0);

    // Read symbol→code map from bitstream
    let bitfield = 0;
    let bitfieldLen = 0;
    let bytePos = 5;

    const map = {}; // map[codeLen][code] = symbolChar
    let minCodeLen = Infinity;
    let maxCodeLen = 0;
    let symbolsRead = 0;
    let state = 'symbol';
    let symbol = 0;

    while (symbolsRead < numSymbols) {
      if (bytePos >= bufSize) throw new Error('Truncated Huffman map');
      bitfield |= (buf[bytePos] << bitfieldLen);
      bitfieldLen += 8;

      if (state === 'symbol') {
        symbol = bitfield & 0xFF;
        bitfield >>>= 8;
        bitfieldLen -= 8;
        state = 'code';
      } else {
        const codeResult = extractEscapedCode(bitfield, bitfieldLen);
        if (codeResult) {
          const [code, codeLen, newBf, newBfLen] = codeResult;
          bitfield = newBf;
          bitfieldLen = newBfLen;
          const [unescaped, ul] = unescape(code, codeLen);
          if (!map[ul]) map[ul] = {};
          map[ul][unescaped] = String.fromCharCode(symbol);
          if (ul < minCodeLen) minCodeLen = ul;
          if (ul > maxCodeLen) maxCodeLen = ul;
          symbolsRead++;
          state = 'symbol';
        }
      }
      bytePos++;
    }

    // Decode compressed data
    const result = [];
    let decSize = 0;
    let testLen = minCodeLen;

    while (true) {
      if (testLen <= bitfieldLen) {
        const testCode = bitfield & ((1 << testLen) - 1);
        const sym = map[testLen] && map[testLen][testCode];
        if (sym !== undefined) {
          result.push(sym);
          decSize++;
          if (decSize >= origSize) break;
          bitfield >>>= testLen;
          bitfieldLen -= testLen;
          testLen = minCodeLen;
        } else {
          testLen++;
          if (testLen > maxCodeLen) throw new Error('Huffman decode error: code too long');
        }
      } else {
        const c = bytePos < bufSize ? buf[bytePos] : 0;
        bitfield |= (c << bitfieldLen);
        bitfieldLen += 8;
        if (bytePos > bufSize) break;
        bytePos++;
      }
    }

    return Buffer.from(result.join(''), 'binary');
  }
}

// Variable-length LZW code reader
function readCode(buf, pos) {
  const a = buf[pos];
  if (a < 250) return [a, 1];
  const count = 256 - a;
  let r = 0;
  for (let n = pos + count; n >= pos + 1; n--) {
    r = r * 255 + buf[n] - 1;
  }
  return [r, count + 1];
}

// Find escaped Huffman code terminated by two consecutive set bits
function extractEscapedCode(bitfield, fieldLen) {
  if (fieldLen < 2) return null;
  let prev = 0;
  for (let i = 0; i < fieldLen; i++) {
    const bit = bitfield & (1 << i);
    if (prev !== 0 && bit !== 0) {
      const code = bitfield & ((1 << (i - 1)) - 1);
      const remaining = bitfield >>> (i + 1);
      const remainingLen = fieldLen - i - 1;
      return [code, i - 1, remaining, remainingLen];
    }
    prev = bit;
  }
  return null;
}

// Unescape Huffman code: 1-bit encoded as "11", 0-bit as "0"
function unescape(code, codeLen) {
  let unescaped = 0;
  let outPos = 0;
  let i = 0;
  while (i < codeLen) {
    const bit = code & (1 << i);
    if (bit !== 0) {
      unescaped |= (1 << outPos);
      i++; // skip paired 1-bit
    }
    i++;
    outPos++;
  }
  return [unescaped, outPos];
}

module.exports = LibCompress;
