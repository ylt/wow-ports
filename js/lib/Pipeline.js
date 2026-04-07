'use strict';
const zlib = require('zlib');
const LuaDeflate = require('./LuaDeflateNative');
const WowAceDeserializer = require('./WowAceDeserializer');
const WowAceSerializer = require('./WowAceSerializer');
const LibCompress = require('./LibCompress');
const VuhDoSerializer = require('./VuhDoSerializer');

let LibSerializeDeserialize, LibSerializeSerialize;
try {
    ({ LibSerializeDeserialize, LibSerializeSerialize } = require('./LibSerialize'));
} catch (_) {}

let WowCbor;
try { WowCbor = require('./WowCbor'); } catch (_) {}

const luaDeflate = new LuaDeflate();

// ── Step registry ──────────────────────────────────────────────────────────

const STEPS = {
    prefix:          ['strip_prefix',              'prepend_prefix'],
    metadata:        ['extract_metadata',          'append_metadata'],
    encode_for_print: ['decode_for_print',         'do_encode_for_print'],
    base64:          ['base64_decode',             'base64_encode'],
    zlib:            ['decompress',                'compress'],
    lib_compress:    ['lib_compress_decode',       'lib_compress_encode'],
    ace_serializer:  ['deserialize_ace',           'serialize_ace'],
    lib_serialize:   ['deserialize_lib_serialize', 'serialize_lib_serialize'],
    cbor:            ['deserialize_cbor',          'serialize_cbor'],
    vuhdo:           ['deserialize_vuhdo',         'serialize_vuhdo'],
};

// ── Format definitions ─────────────────────────────────────────────────────

const AUTO_FORMATS = [
    { addon: 'plater',    version: 2, prefix: '!PLATER:2!',
      steps: [{ prefix: '!PLATER:2!' }, 'base64', 'zlib', 'cbor'] },
    { addon: 'weakauras', version: 2, prefix: '!WA:2!',
      steps: [{ prefix: '!WA:2!' }, 'encode_for_print', 'zlib', 'lib_serialize'] },
    { addon: 'elvui',     version: 1, prefix: '!E1!',
      steps: [{ prefix: '!E1!' }, 'encode_for_print', 'zlib', 'metadata', 'ace_serializer'] },
    { addon: 'weakauras', version: 1, prefix: '!',
      steps: [{ prefix: '!' }, 'encode_for_print', 'zlib', 'ace_serializer'] },
    { addon: 'weakauras', version: 0, prefix: '',
      steps: ['encode_for_print', 'zlib', 'ace_serializer'] },
];

const FORMATS = {
    plater:    AUTO_FORMATS[0].steps,
    weakauras: AUTO_FORMATS[1].steps,
    elvui:     AUTO_FORMATS[2].steps,
    cell:      [{ prefix: /^!CELL:\d+:\w+!/ }, 'encode_for_print', 'zlib', 'lib_serialize'],
    dbm:       ['encode_for_print', 'zlib', 'lib_serialize'],
    mdt:       ['encode_for_print', 'lib_compress', 'ace_serializer'],
    totalrp3:  [{ prefix: '!' }, 'encode_for_print', 'zlib', 'ace_serializer'],
    vuhdo:     ['base64', 'lib_compress', 'vuhdo'],
};

function resolve(step, direction) {
    const pair = STEPS[step];
    if (!pair) throw new Error(`Unknown step: ${step}`);
    return direction === 'decode' ? pair[0] : pair[1];
}

function findFormat(addon, version) {
    return AUTO_FORMATS.find(f => f.addon === addon && f.version === version);
}

function runSteps(pipeline, steps, direction) {
    for (const step of steps) {
        if (typeof step === 'object' && !Array.isArray(step) && !(step instanceof RegExp)) {
            const [name, arg] = Object.entries(step)[0];
            pipeline[resolve(name, direction)](arg);
        } else {
            pipeline[resolve(step, direction)]();
        }
    }
}

// ── Heuristic detection ────────────────────────────────────────────────────

function detectSteps(exportStr) {
    let raw = exportStr.trim();
    const steps = [];

    // Layer 1: prefix
    const bangMatch = raw.match(/^![A-Z][\w:]*!/);
    const colonMatch = raw.match(/^[A-Z]+\d*:/);
    if (bangMatch) {
        steps.push({ prefix: bangMatch[0] });
        raw = raw.slice(bangMatch[0].length);
    } else if (colonMatch) {
        steps.push({ prefix: colonMatch[0] });
        raw = raw.slice(colonMatch[0].length);
    } else if (raw.startsWith('!')) {
        steps.push({ prefix: '!' });
        raw = raw.slice(1);
    }

    // Layer 2: encoding (character set)
    const EFP = /^[a-zA-Z0-9()]+$/;
    const B64 = /^[A-Za-z0-9+/=]+$/;
    if (EFP.test(raw)) {
        steps.push('encode_for_print');
        raw = luaDeflate.decodeForPrint(raw);
    } else if (B64.test(raw)) {
        steps.push('base64');
        raw = Buffer.from(raw, 'base64').toString('binary');
    } else if (raw.startsWith('{') || raw.startsWith('[')) {
        return steps;
    } else {
        return steps;
    }

    if (!raw || raw.length === 0) return steps;

    // Layer 3: compression
    const firstByte = typeof raw === 'string' ? raw.charCodeAt(0) : raw[0];
    if (firstByte >= 1 && firstByte <= 3) {
        steps.push('lib_compress');
        const buf = Buffer.from(raw, 'binary');
        raw = LibCompress.decompress(buf).toString('binary');
    } else {
        try {
            raw = zlib.inflateRawSync(Buffer.from(raw, 'binary')).toString('binary');
            steps.push('zlib');
        } catch (_) {
            return steps;
        }
    }

    // Layer 4: serializer
    const first = raw.charCodeAt(0);
    if (raw.startsWith('^1')) {
        if (raw.includes('^^::')) steps.push('metadata');
        steps.push('ace_serializer');
    } else if (first === 1) {
        steps.push('lib_serialize');
    } else if ((first >> 5) === 5 || (first >> 5) === 4) {
        steps.push('cbor');
    }

    return steps;
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
        this._steps      = null;
    }

    static from_result(exportResult) {
        const p = new Pipeline(null);
        p.addon    = exportResult.addon;
        p.version  = exportResult.version;
        p.data     = exportResult.data;
        p.metadata = exportResult.metadata;
        return p;
    }

    // ── Public API ────────────────────────────────────────────────────────────

    static decode(exportStr, { addon, steps } = {}) {
        const p = new Pipeline(exportStr.trim());
        if (!steps) {
            if (addon) {
                steps = FORMATS[addon];
                if (!steps) throw new Error(`Unknown addon: ${addon}`);
                p.addon = addon;
            } else {
                steps = detectSteps(exportStr);
                if (!steps.length) throw new Error('Could not detect format');
                const pfxStep = steps.find(s => typeof s === 'object' && s.prefix);
                if (pfxStep) {
                    const match = AUTO_FORMATS.find(f => f.prefix === pfxStep.prefix);
                    if (match) { p.addon = match.addon; p.version = match.version; }
                } else {
                    p.addon = 'weakauras'; p.version = 0;
                }
            }
        }
        p._steps = steps;
        runSteps(p, steps, 'decode');
        return p.result();
    }

    static encode(exportResult, { addon, steps } = {}) {
        const p = Pipeline.from_result(exportResult);
        if (!steps) {
            if (addon) {
                steps = FORMATS[addon];
                if (!steps) throw new Error(`Unknown addon: ${addon}`);
            } else if (exportResult.steps) {
                steps = exportResult.steps;
            } else {
                const fmt = findFormat(exportResult.addon, exportResult.version);
                if (!fmt) throw new Error(`Unknown format: ${exportResult.addon} v${exportResult.version}`);
                steps = fmt.steps;
            }
        }
        runSteps(p, [...steps].reverse(), 'encode');
        return p.to_string();
    }

    // ── Format detection (legacy) ─────────────────────────────────────────────

    detect_format() {
        this.format = AUTO_FORMATS.find(f => f.prefix && this.raw.startsWith(f.prefix))
                   || AUTO_FORMATS[AUTO_FORMATS.length - 1];
        this.addon   = this.format.addon;
        this.version = this.format.version;
        this.prefix  = this.format.prefix;
        return this;
    }

    // ── Decode step implementations ───────────────────────────────────────────

    strip_prefix(pfx) {
        if (pfx instanceof RegExp) {
            const m = this.raw.match(pfx);
            if (!m) throw new Error(`Prefix pattern ${pfx} not found`);
            this.prefix = m[0];
            this.raw = this.raw.slice(this.prefix.length);
        } else {
            this.prefix = pfx;
            this.raw = this.raw.slice(pfx.length);
        }
        return this;
    }

    extract_metadata() {
        const text = this.serialized.toString('binary');
        const metaIdx = text.indexOf('^^::');
        if (metaIdx !== -1) {
            const metaPart = text.slice(metaIdx + 4);
            const [profileType = null, profileKey = null] = metaPart.split('::');
            this.metadata = { profileType, profileKey };
            this.serialized = Buffer.from(text.slice(0, metaIdx + 2), 'binary');
        }
        return this;
    }

    decode_for_print() {
        this.compressed = luaDeflate.decodeForPrint(this.raw);
        if (!this.compressed) throw new Error('LuaDeflate decode failed');
        return this;
    }

    base64_decode() {
        this.compressed = Buffer.from(this.raw, 'base64').toString('binary');
        return this;
    }

    decompress() {
        this.serialized = zlib.inflateRawSync(Buffer.from(this.compressed, 'binary'));
        return this;
    }

    lib_compress_decode() {
        this.serialized = LibCompress.decompress(Buffer.from(this.compressed, 'binary'));
        return this;
    }

    deserialize_cbor() {
        if (!WowCbor) throw new Error('WowCbor not available');
        this.data = WowCbor.decode(this.serialized);
        return this;
    }

    deserialize_lib_serialize() {
        if (!LibSerializeDeserialize) throw new Error('LibSerialize not available');
        this.data = LibSerializeDeserialize.deserialize(this.serialized);
        return this;
    }

    deserialize_ace() {
        this.data = new WowAceDeserializer(this.serialized.toString('binary')).deserialize();
        return this;
    }

    deserialize_vuhdo() {
        this.data = VuhDoSerializer.deserialize(this.serialized.toString('binary'));
        return this;
    }

    result() {
        return { addon: this.addon, version: this.version, data: this.data, metadata: this.metadata, steps: this._steps };
    }

    // ── Encode step implementations ───────────────────────────────────────────

    serialize_cbor() {
        if (!WowCbor) throw new Error('WowCbor not available');
        this.serialized = WowCbor.encode(this.data).toString('binary');
        return this;
    }

    serialize_lib_serialize() {
        if (!LibSerializeSerialize) throw new Error('LibSerialize not available');
        this.serialized = LibSerializeSerialize.serialize(this.data).toString('binary');
        return this;
    }

    serialize_ace() {
        this.serialized = WowAceSerializer.serialize(this.data);
        return this;
    }

    serialize_vuhdo() {
        this.serialized = VuhDoSerializer.serialize(this.data);
        return this;
    }

    compress() {
        const deflated = zlib.deflateRawSync(Buffer.from(this.serialized, 'binary'));
        this.compressed = deflated.toString('binary');
        return this;
    }

    lib_compress_encode() {
        throw new Error('LibCompress encode not implemented');
    }

    do_encode_for_print() {
        this.raw = luaDeflate.encodeForPrint(this.compressed);
        return this;
    }

    base64_encode() {
        this.raw = Buffer.from(this.compressed, 'binary').toString('base64');
        return this;
    }

    prepend_prefix(pfx) {
        if (pfx instanceof RegExp) {
            this.raw = this.prefix + this.raw;
        } else {
            this.raw = pfx + this.raw;
        }
        return this;
    }

    append_metadata() {
        if (this.metadata) {
            this.serialized += `::${this.metadata.profileType ?? ''}::${this.metadata.profileKey ?? ''}`;
        }
        return this;
    }

    to_string() {
        return this.raw;
    }
}

Pipeline.AUTO_FORMATS = AUTO_FORMATS;
Pipeline.FORMATS = FORMATS;
Pipeline.STEPS = STEPS;
Pipeline.detectSteps = detectSteps;
Pipeline.findFormat = findFormat;

module.exports = Pipeline;
