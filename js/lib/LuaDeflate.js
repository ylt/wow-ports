class LuaDeflate {
    constructor() {
        // Define a custom base64 character set.
        this.BYTE_TO_BIT = [...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()'];

        // Create a reverse lookup map from the custom base64 character set.
        this.BIT_TO_BYTE = new Map(this.BYTE_TO_BIT.map((val, idx) => [val, idx]));
    }

    decodeForPrint(encodedStr) {
        if (typeof encodedStr !== "string") {
            return;
        }

        // Strip leading and trailing whitespace.
        encodedStr = encodedStr.trim();
        if (encodedStr.length <= 1) {
            return;
        }

        const decodedBytes = [];
        for (let i = 0; i < encodedStr.length; i += 4) {
            const charGroup = encodedStr.slice(i, i + 4).split('');

            // Convert each character in the chunk to its corresponding base64 index.
            const indices = charGroup.map(char => this.BIT_TO_BYTE.get(char));
            if (indices.includes(undefined)) {
                return null;
            }

            // Calculate the 24-bit number represented by the chunk.
            const value = indices.reduce((acc, index, idx) => acc + index * (64 ** idx), 0);

            // Determine the number of bytes this chunk should produce.
            const bytesToTake = (charGroup.length === 4) ? 3 : charGroup.length - 1;

            // Extract bytes from the 24-bit number.
            for (let shift = 0; shift < bytesToTake; shift++) {
                const byte = String.fromCharCode((value >> (8 * shift)) & 0xFF);
                decodedBytes.push(byte);
            }
        }

        return decodedBytes.join('');
    }

    decodeForPrint2(encodedStr) {
        if (typeof encodedStr !== "string") {
            return;
        }

        encodedStr = encodedStr.trim();
        if (encodedStr.length <= 1) {
            return;
        }

        const byteCount = Math.ceil(encodedStr.length * 6 / 8);
        const buffer = new ArrayBuffer(byteCount);
        const view = new Uint8Array(buffer);

        let bufferIndex = 0;
        for (let i = 0; i < encodedStr.length; i += 4) {
            const charGroup = encodedStr.slice(i, i + 4).split('');

            const indices = charGroup.map(char => this.BIT_TO_BYTE.get(char));
            if (indices.includes(undefined)) {
                return null;
            }

            const value = indices.reduce((acc, index, idx) => acc + index * (64 ** idx), 0);

            const bytesToTake = (charGroup.length === 4) ? 3 : charGroup.length - 1;
            for (let shift = 0; shift < bytesToTake; shift++) {
                view[bufferIndex++] = (value >> (8 * shift)) & 0xFF;
            }
        }

        return new Uint8Array(buffer)
    }

    encodeForPrint(str) {
        if (typeof str !== "string") {
            throw new TypeError(`Expected 'str' to be a string, got ${typeof str}`);
        }

        const encodedChunks = [];
        for (let i = 0; i < str.length; i += 3) {
            const byteGroup = str.slice(i, i + 3).split('');

            // Convert characters to their ASCII byte values.
            const bytes = byteGroup.map(char => char.charCodeAt(0));

            // Calculate the 24-bit number represented by the 3 bytes.
            const value = bytes.reduce((acc, byte, idx) => acc + byte * (256 ** idx), 0);

            // Determine the number of chunks this group should produce.
            const chunksToTake = byteGroup.length + 1;

            // Extract 6-bit chunks from the 24-bit number and convert them to characters.
            for (let idx = 0; idx < chunksToTake; idx++) {
                const chunk = this.BYTE_TO_BIT[(value >> (6 * idx)) & 0x3F];
                encodedChunks.push(chunk);
            }
        }

        return encodedChunks.join('');
    }
}

// export default LuaDeflate;
module.exports = LuaDeflate;