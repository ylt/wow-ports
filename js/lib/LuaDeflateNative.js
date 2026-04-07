const LUA_ALPHA = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()';
const B64_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

const luaToB64 = new Uint8Array(128);
const b64ToLua = new Uint8Array(128);
const validLua = new Uint8Array(128);

for (let i = 0; i < 64; i++) {
    luaToB64[LUA_ALPHA.charCodeAt(i)] = B64_ALPHA.charCodeAt(i);
    b64ToLua[B64_ALPHA.charCodeAt(i)] = LUA_ALPHA.charCodeAt(i);
    validLua[LUA_ALPHA.charCodeAt(i)] = 1;
}

class LuaDeflateNative {
    encodeForPrint(str) {
        if (typeof str !== 'string') {
            throw new TypeError(`Expected 'str' to be a string, got ${typeof str}`);
        }

        const originalLength = str.length;
        const padded = originalLength % 3 === 0 ? originalLength : originalLength + (3 - originalLength % 3);

        const input = Buffer.allocUnsafe(padded);
        for (let i = 0; i < originalLength; i++) input[i] = str.charCodeAt(i);
        for (let i = originalLength; i < padded; i++) input[i] = 0;

        for (let i = 0; i < padded; i += 3) {
            const tmp = input[i];
            input[i] = input[i + 2];
            input[i + 2] = tmp;
        }

        const b64 = input.toString('base64');

        const outLen = Math.ceil(originalLength * 4 / 3);
        const out = Buffer.allocUnsafe(outLen);

        for (let i = 0; i < outLen; i += 4) {
            const end = Math.min(i + 4, outLen);
            const groupEnd = i + 4;
            for (let j = i; j < end; j++) {
                out[j] = b64ToLua[b64.charCodeAt(groupEnd - 1 - (j - i))];
            }
        }

        return out.toString('latin1');
    }

    // Returns decoded Uint8Array with byteCount bytes, or null on invalid input.
    _decode(encodedStr) {
        const encodedLength = encodedStr.length;
        const r = encodedLength % 4;
        const fullGroups = r === 0 ? encodedLength : encodedLength - r;
        const b64Len = r === 0 ? encodedLength : encodedLength + (4 - r);

        const b64Chars = Buffer.allocUnsafe(b64Len);

        for (let i = 0; i < fullGroups; i += 4) {
            for (let k = 0; k < 4; k++) {
                const code = encodedStr.charCodeAt(i + k);
                if (code >= 128 || !validLua[code]) return null;
                b64Chars[i + (3 - k)] = luaToB64[code];
            }
        }

        if (r !== 0) {
            const base = fullGroups;
            const fill = 4 - r;
            for (let k = 0; k < fill; k++) b64Chars[base + k] = 0x41; // 'A'
            for (let k = 0; k < r; k++) {
                const code = encodedStr.charCodeAt(base + k);
                if (code >= 128 || !validLua[code]) return null;
                b64Chars[base + fill + (r - 1 - k)] = luaToB64[code];
            }
        }

        const b64str = b64Chars.toString('latin1') + (r === 0 ? '' : r === 2 ? '==' : '=');
        const decoded = Buffer.from(b64str, 'base64');

        for (let i = 0; i < decoded.length; i += 3) {
            const tmp = decoded[i];
            decoded[i] = decoded[i + 2];
            decoded[i + 2] = tmp;
        }

        return decoded;
    }

    decodeForPrint(encodedStr) {
        if (typeof encodedStr !== 'string') return null;
        const trimmed = encodedStr.trim();
        if (trimmed.length === 0) return '';
        if (trimmed.length === 1) return null;
        const decoded = this._decode(trimmed);
        if (decoded == null) return null;
        const byteCount = Math.floor(trimmed.length * 3 / 4);
        return decoded.toString('latin1', 0, byteCount);
    }

    decodeForPrint2(encodedStr) {
        if (typeof encodedStr !== 'string') return null;
        const trimmed = encodedStr.trim();
        if (trimmed.length === 0) return new Uint8Array(0);
        if (trimmed.length === 1) return null;
        const decoded = this._decode(trimmed);
        if (decoded == null) return null;
        const byteCount = Math.ceil(trimmed.length * 6 / 8);
        return new Uint8Array(decoded.buffer, decoded.byteOffset, byteCount);
    }
}

module.exports = LuaDeflateNative;
