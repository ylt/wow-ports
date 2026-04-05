'use strict';
const zlib = require('zlib');
const LuaDeflate = require('./LuaDeflate');
const WowAceDeserializer = require('./WowAceDeserializer');
const WowAceSerializer = require('./WowAceSerializer');

// LibSerialize — ported as part of task #10
let LibSerializeDeserialize, LibSerializeSerialize;
try {
    ({ LibSerializeDeserialize, LibSerializeSerialize } = require('./LibSerialize'));
} catch (_) {}

// WowCbor — Plater v2 CBOR support (task #14)
let WowCbor;
try { WowCbor = require('./WowCbor'); } catch (_) {}

const luaDeflate = new LuaDeflate();

function detectAddon(str) {
    if (str.startsWith('!PLATER:2!')) return { addon: 'plater',    version: 2, prefix: '!PLATER:2!' };
    if (str.startsWith('!WA:2!'))    return { addon: 'weakauras', version: 2, prefix: '!WA:2!' };
    if (str.startsWith('!E1!'))      return { addon: 'elvui',     version: 1, prefix: '!E1!' };
    if (str.startsWith('!'))         return { addon: 'weakauras', version: 1, prefix: '!' };
    return { addon: 'weakauras', version: 0, prefix: '' };
}

function prefixFor(addon, version) {
    if (addon === 'plater' && version === 2) return '!PLATER:2!';
    if (version === 2)                       return '!WA:2!';
    if (addon === 'elvui')                   return '!E1!';
    if (version >= 1)                        return '!';
    return '';
}

class Pipeline {
    constructor(raw) {
        this.raw      = raw;
        this.addon    = null;
        this.version  = null;
        this.prefix   = null;
        this.metadata = null;
        this.compressed  = null;
        this.serialized  = null;
        this.data        = null;
        this.encoded     = null;
    }

    static from_result(exportResult) {
        const p = new Pipeline(null);
        p.addon    = exportResult.addon;
        p.version  = exportResult.version;
        p.data     = exportResult.data;
        p.metadata = exportResult.metadata;
        return p;
    }

    // ── Decode steps ──────────────────────────────────────────────────────────

    detect_format() {
        const { addon, version, prefix } = detectAddon(this.raw);
        this.addon   = addon;
        this.version = version;
        this.prefix  = prefix;
        return this;
    }

    strip_prefix() {
        this.raw = this.raw.slice(this.prefix.length);
        return this;
    }

    extract_metadata() {
        if (this.addon === 'elvui') {
            const metaIdx = this.raw.indexOf('^^::');
            if (metaIdx !== -1) {
                const metaPart = this.raw.slice(metaIdx + 4);
                const [profileType = null, profileKey = null] = metaPart.split('::');
                this.metadata = { profileType, profileKey };
                this.raw = this.raw.slice(0, metaIdx);
            }
        }
        return this;
    }

    base64_decode() {
        this.compressed = luaDeflate.decodeForPrint(this.raw);
        if (!this.compressed) throw new Error('LuaDeflate decode failed');
        return this;
    }

    decompress() {
        this.serialized = zlib.inflateRawSync(Buffer.from(this.compressed, 'binary'));
        return this;
    }

    deserialize() {
        if (this.addon === 'plater' && this.version === 2) {
            if (!WowCbor) throw new Error('WowCbor not available for Plater v2 decode');
            this.data = WowCbor.decode(this.serialized);
        } else if (this.version === 2) {
            if (!LibSerializeDeserialize) throw new Error('LibSerialize not available for WA v2 decode');
            this.data = LibSerializeDeserialize.deserialize(this.serialized);
        } else {
            this.data = new WowAceDeserializer(this.serialized.toString('binary')).deserialize();
        }
        return this;
    }

    result() {
        return { addon: this.addon, version: this.version, data: this.data, metadata: this.metadata };
    }

    // ── Encode steps ──────────────────────────────────────────────────────────

    serialize() {
        if (this.addon === 'plater' && this.version === 2) {
            if (!WowCbor) throw new Error('WowCbor not available for Plater v2 encode');
            this.serialized = WowCbor.encode(this.data).toString('binary');
        } else if (this.version === 2) {
            if (!LibSerializeSerialize) throw new Error('LibSerialize not available for WA v2 encode');
            this.serialized = LibSerializeSerialize.serialize(this.data).toString('binary');
        } else {
            this.serialized = WowAceSerializer.serialize(this.data);
        }
        return this;
    }

    compress() {
        const deflated = zlib.deflateRawSync(Buffer.from(this.serialized, 'binary'));
        this.compressed = deflated.toString('binary');
        return this;
    }

    base64_encode() {
        this.encoded = luaDeflate.encodeForPrint(this.compressed);
        return this;
    }

    prepend_prefix() {
        this.raw = prefixFor(this.addon, this.version) + this.encoded;
        return this;
    }

    append_metadata() {
        if (this.addon === 'elvui' && this.metadata) {
            this.raw += `^^::${this.metadata.profileType ?? ''}::${this.metadata.profileKey ?? ''}`;
        }
        return this;
    }

    to_string() {
        return this.raw;
    }

    // ── Convenience wrappers (static) ─────────────────────────────────────────

    /**
     * Decode a WoW addon export string.
     * Returns { addon, version, data, metadata }
     */
    static decode(exportStr) {
        const p = new Pipeline(exportStr.trim());
        p.detect_format();
        p.strip_prefix();
        p.extract_metadata();
        p.base64_decode();
        p.decompress();
        p.deserialize();
        return p.result();
    }

    /**
     * Encode an ExportResult back to a WoW addon export string.
     * exportResult: { addon, version, data, metadata }
     */
    static encode(exportResult) {
        const p = Pipeline.from_result(exportResult);
        p.serialize();
        p.compress();
        p.base64_encode();
        p.prepend_prefix();
        p.append_metadata();
        return p.to_string();
    }
}

module.exports = Pipeline;
