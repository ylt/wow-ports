'use strict';
const { decode, encode } = require('cbor-x');

/**
 * Post-process a decoded CBOR value:
 * 1. CBOR byte strings (Uint8Array / Buffer) → UTF-8 text strings
 * 2. Sequential 1-based integer-keyed maps → arrays (Lua table convention)
 * 3. Maps returned as Map objects are also handled
 */
function postProcess(val) {
    if (val instanceof Uint8Array || Buffer.isBuffer(val)) {
        return Buffer.from(val).toString('utf8');
    }
    if (Array.isArray(val)) {
        return val.map(postProcess);
    }
    if (val instanceof Map) {
        // cbor-x may return Map for non-string-keyed CBOR maps
        const obj = {};
        for (const [k, v] of val) {
            obj[k] = postProcess(v);
        }
        return applyArrayDetection(obj);
    }
    if (val !== null && typeof val === 'object') {
        const result = {};
        for (const [k, v] of Object.entries(val)) {
            result[k] = postProcess(v);
        }
        return applyArrayDetection(result);
    }
    return val;
}

function applyArrayDetection(obj) {
    const keys = Object.keys(obj);
    if (keys.length === 0) return obj;
    const nums = keys.map(k => Number(k));
    if (!nums.every(n => Number.isInteger(n) && n > 0)) return obj;
    const sorted = [...nums].sort((a, b) => a - b);
    if (sorted.every((n, i) => n === i + 1)) {
        return sorted.map(n => obj[String(n)]);
    }
    return obj;
}

class WowCbor {
    /**
     * Decode CBOR bytes to a JS value, with WoW-specific post-processing.
     * @param {Buffer|Uint8Array} bytes
     * @returns {*}
     */
    static decode(bytes) {
        const raw = decode(Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes));
        return postProcess(raw);
    }

    /**
     * Encode a JS value to CBOR bytes.
     * @param {*} data
     * @returns {Buffer}
     */
    static encode(data) {
        const raw = encode(data);
        return Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
    }
}

module.exports = WowCbor;
