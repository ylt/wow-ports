'use strict';
const zlib = require('zlib');
const LuaDeflate = require('./LuaDeflate');
const WowAceDeserializer = require('./WowAceDeserializer');
const WowAceSerializer = require('./WowAceSerializer');

// LibSerialize is ported as part of task #10; load if available
let LibSerializeDeserialize, LibSerializeSerialize;
try {
    ({ LibSerializeDeserialize, LibSerializeSerialize } = require('./LibSerialize'));
} catch (_) {}

const luaDeflate = new LuaDeflate();

function detectAddon(str) {
    if (str.startsWith('!WA:2!')) return { addon: 'weakauras', version: 2, prefix: '!WA:2!' };
    if (str.startsWith('!E1!'))   return { addon: 'elvui',     version: 1, prefix: '!E1!' };
    if (str.startsWith('!'))      return { addon: 'weakauras', version: 1, prefix: '!' };
    return { addon: 'weakauras', version: 0, prefix: '' };
}

function prefixFor(addon, version) {
    if (version === 2)          return '!WA:2!';
    if (addon === 'elvui')      return '!E1!';
    if (version >= 1)           return '!';
    return '';
}

class Pipeline {
    /**
     * Decode a WoW addon export string.
     * Returns { addon, version, data, metadata }
     */
    static decode(exportStr) {
        exportStr = exportStr.trim();
        const { addon, version, prefix } = detectAddon(exportStr);
        let encoded = exportStr.slice(prefix.length);

        // ElvUI: strip ^^:: metadata trailer before LuaDeflate decode
        let metadata = null;
        if (addon === 'elvui') {
            const metaIdx = encoded.indexOf('^^::');
            if (metaIdx !== -1) {
                const metaPart = encoded.slice(metaIdx + 4);
                const [profileType = null, profileKey = null] = metaPart.split('::');
                metadata = { profileType, profileKey };
                encoded = encoded.slice(0, metaIdx);
            }
        }

        // LuaDeflate decode → binary string
        const compressed = luaDeflate.decodeForPrint(encoded);
        if (!compressed) throw new Error('LuaDeflate decode failed');

        // zlib raw inflate
        const inflated = zlib.inflateRawSync(Buffer.from(compressed, 'binary'));

        // Deserialize
        let data;
        if (version === 2) {
            if (!LibSerializeDeserialize) throw new Error('LibSerialize not available for WA v2 decode');
            data = LibSerializeDeserialize.deserialize(inflated);
        } else {
            data = new WowAceDeserializer(inflated.toString('binary')).deserialize();
        }

        return { addon, version, data, metadata };
    }

    /**
     * Encode an ExportResult back to a WoW addon export string.
     * exportResult: { addon, version, data, metadata }
     */
    static encode(exportResult) {
        const { addon, version, data, metadata } = exportResult;

        // Serialize
        let serialized;
        if (version === 2) {
            if (!LibSerializeSerialize) throw new Error('LibSerialize not available for WA v2 encode');
            serialized = LibSerializeSerialize.serialize(data).toString('binary');
        } else {
            serialized = WowAceSerializer.serialize(data);
        }

        // zlib raw deflate
        const deflated = zlib.deflateRawSync(Buffer.from(serialized, 'binary'));

        // LuaDeflate encode
        let encoded = luaDeflate.encodeForPrint(deflated.toString('binary'));

        // ElvUI: append metadata trailer
        if (addon === 'elvui' && metadata) {
            encoded += `^^::${metadata.profileType ?? ''}::${metadata.profileKey ?? ''}`;
        }

        return prefixFor(addon, version) + encoded;
    }
}

module.exports = Pipeline;
