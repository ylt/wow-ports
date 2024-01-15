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
        const escaped = str.replace(/[\x00-\x20]/g, m => `~${String.fromCharCode(m.charCodeAt(0) + 64)}`)
            .replace('^', '~U')
            .replace('~', '~T')
            .replace("\x7F", '~S');
        return `^S${escaped}`;
    }

    static _serializeNumber(num) {
        if (!isFinite(num)) {
            return num > 0 ? '^N1.#INF' : '^N-1.#INF';
        }
        // Handle integer and float differentiation
        if (Number.isInteger(num)) {
            return `^N${num}`;
        } else {
            const data = new Float64Array(1);
            data[0] = num;
            const [mantissa, exponent] = [data[0] * Math.pow(2, 53), 53]; // Using ES6 destructuring
            return `^F${mantissa}^f${exponent}`;
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
