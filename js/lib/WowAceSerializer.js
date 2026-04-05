class WowAceSerializer {
    static serialize(obj) {
        return `^1${this._serializeInternal(obj)}^^`;
    }

    static _serializeInternal(obj) {
        switch (typeof obj) {
            case 'string':
                return this._serializeString(obj);
            case 'number':
                return this._serializeNumber(obj);
            case 'boolean':
                return obj ? '^B' : '^b';
            case 'object':
                if (obj === null) {
                    return '^Z';
                } else if (Array.isArray(obj)) {
                    return this._serializeArray(obj);
                } else {
                    return this._serializeTable(obj);
                }
            default:
                throw new Error(`Unsupported data type: ${typeof obj}`);
        }
    }

    // Serialization helpers
    static _serializeString(str) {
        const escaped = str.replace(/[\x00-\x20\x5E\x7E\x7F]/g, m => {
            const byte = m.charCodeAt(0);
            if (byte === 0x1E) return '~z';
            if (byte === 0x5E) return '~}';
            if (byte === 0x7E) return '~|';
            if (byte === 0x7F) return '~{';
            return `~${String.fromCharCode(byte + 64)}`;
        });
        return `^S${escaped}`;
    }

    static _frexp(value) {
        if (value === 0) return [0, 0];
        const data = new DataView(new ArrayBuffer(8));
        data.setFloat64(0, value);
        const bits = (data.getUint32(0) >>> 20) & 0x7FF;
        if (bits === 0) {
            data.setFloat64(0, value * Math.pow(2, 64));
            const bits2 = (data.getUint32(0) >>> 20) & 0x7FF;
            return [value * Math.pow(2, 64 - bits2 + 1022), bits2 - 1022 - 64];
        }
        return [value / Math.pow(2, bits - 1022), bits - 1022];
    }

    static _serializeNumber(num) {
        if (!isFinite(num)) {
            return num > 0 ? '^N1.#INF' : '^N-1.#INF';
        }
        if (Number.isInteger(num)) {
            return `^N${num}`;
        } else {
            const [m, e] = this._frexp(num);
            const int_mantissa = Math.floor(m * Math.pow(2, 53));
            const adj_exponent = e - 53;
            return `^F${int_mantissa}^f${adj_exponent}`;
        }
    }

    static _serializeTable(table) {
        const serialized = Object.entries(table)
            .map(([key, value]) => `${this._serializeInternal(key)}${this._serializeInternal(value)}`)
            .join('');
        return `^T${serialized}^t`;
    }

    static _serializeArray(array) {
        const indexedTable = {};
        array.forEach((value, index) => {
            indexedTable[index + 1] = value;
        });
        return this._serializeTable(indexedTable);
    }
}

module.exports = WowAceSerializer;

// export default WowAceSerializer;
