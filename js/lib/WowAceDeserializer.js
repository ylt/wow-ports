const Streader = require('streader');

class WowAceDeserializer {
    constructor(serializedStr) {
        this.stream = new Streader(serializedStr.replace(/[\x00-\x20]/, ''));
        if (!this.stream.readPattern('^1')) {
            throw new Error('Invalid prefix');
        }
    }

    deserialize() {
        return this.deserializeInternal();
    }

    deserializeInternal() {
        if (this.stream.eof()) {
            throw new Error('Unexpected end of data');
        }

        const prefix = this.stream.read(2);
        switch (prefix[1]) {
            case 'S':
                return this.deserializeString();
            case 'N':
                return this.deserializeNumber();
            case 'F':
                return this.deserializeFloat();
            case 'T':
                return this.deserializeTable();
            case 'B':
                return true;
            case 'b':
                return false;
            case 'Z':
                return null;
            default:
                throw new Error(`Unsupported data type: ${prefix}`);
        }
    }

    deserializeString() {
        let stringData = this.stream.readPattern(/^[^^]*/);

        // Replace the escape sequences
        return stringData.replace(/~(.)/g, (match, char) => {
            switch (char) {
                case 'U': return '^';
                case 'T': return '~';
                case 'S': return '\x7F';
                default: return String.fromCharCode(char.charCodeAt(0) - 64);
            }
        });
    }

    deserializeNumber() {
        let numberStr = this.stream.readPattern(/^[^^]*/);
        if (numberStr === '1.#INF' || numberStr === 'inf') {
            return Infinity;
        } else if (numberStr === '-1.#INF' || numberStr === '-inf') {
            return -Infinity;
        } else if (/^-?\d+$/.test(numberStr)) {
            return parseInt(numberStr, 10);
        } else {
            return parseFloat(numberStr);
        }
    }

    deserializeFloat() {
        let mantissa = parseInt(this.stream.readPattern(/^-?\d+/), 10);
        this.stream.skipPattern(/\^f/);
        let exponent = parseInt(this.stream.readPattern(/^-?\d+/), 10);
        return mantissa * Math.pow(2, exponent - 53);
    }

    deserializeTable() {
        const table = {};
        this.stream.skipPattern('^T'); // Skip the '^T' prefix for the table

        while (!this.stream.peekPattern('^t')) {
            let key = this.deserializeInternal();
            let value = this.deserializeInternal();
            table[key] = value;
        }

        this.stream.skip(2); // skip the closing '^t' for the table
        return table;
    }
}

export default WowAceDeserializer;
