class LuaDeflate {
  BYTE_TO_BIT: string[];
  BIT_TO_BYTE: Map<string, number>;

  constructor() {
    this.BYTE_TO_BIT = [
      ..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()",
    ];
    this.BIT_TO_BYTE = new Map(this.BYTE_TO_BIT.map((val, idx) => [val, idx]));
  }

  decodeForPrint(encodedStr: string): string | null {
    if (typeof encodedStr !== "string") {
      return null;
    }

    encodedStr = encodedStr.trim();
    if (encodedStr.length === 0) {
      return "";
    }
    if (encodedStr.length === 1) {
      return null;
    }

    const decodedBytes: string[] = [];
    for (let i = 0; i < encodedStr.length; i += 4) {
      const charGroup = encodedStr.slice(i, i + 4).split("");

      const indices = charGroup.map((char) => this.BIT_TO_BYTE.get(char));
      if (indices.includes(undefined)) {
        return null;
      }

      const value = (indices as number[]).reduce(
        (acc, index, idx) => acc + index * 64 ** idx,
        0,
      );

      const bytesToTake = charGroup.length === 4 ? 3 : charGroup.length - 1;

      for (let shift = 0; shift < bytesToTake; shift++) {
        const byte = String.fromCharCode((value >> (8 * shift)) & 0xff);
        decodedBytes.push(byte);
      }
    }

    return decodedBytes.join("");
  }

  decodeForPrint2(encodedStr: string): Uint8Array | null | undefined {
    if (typeof encodedStr !== "string") {
      return;
    }

    encodedStr = encodedStr.trim();
    if (encodedStr.length === 0) {
      return new Uint8Array(0);
    }
    if (encodedStr.length === 1) {
      return null;
    }

    const byteCount = Math.ceil((encodedStr.length * 6) / 8);
    const buffer = new ArrayBuffer(byteCount);
    const view = new Uint8Array(buffer);

    let bufferIndex = 0;
    for (let i = 0; i < encodedStr.length; i += 4) {
      const charGroup = encodedStr.slice(i, i + 4).split("");

      const indices = charGroup.map((char) => this.BIT_TO_BYTE.get(char));
      if (indices.includes(undefined)) {
        return null;
      }

      const value = (indices as number[]).reduce(
        (acc, index, idx) => acc + index * 64 ** idx,
        0,
      );

      const bytesToTake = charGroup.length === 4 ? 3 : charGroup.length - 1;
      for (let shift = 0; shift < bytesToTake; shift++) {
        view[bufferIndex++] = (value >> (8 * shift)) & 0xff;
      }
    }

    return new Uint8Array(buffer);
  }

  encodeForPrint(str: string): string {
    if (typeof str !== "string") {
      throw new TypeError(`Expected 'str' to be a string, got ${typeof str}`);
    }

    const encodedChunks: string[] = [];
    for (let i = 0; i < str.length; i += 3) {
      const byteGroup = str.slice(i, i + 3).split("");

      const bytes = byteGroup.map((char) => char.charCodeAt(0));

      const value = bytes.reduce(
        (acc, byte, idx) => acc + byte * 256 ** idx,
        0,
      );

      const chunksToTake = byteGroup.length + 1;

      for (let idx = 0; idx < chunksToTake; idx++) {
        const chunk = this.BYTE_TO_BIT[(value >> (6 * idx)) & 0x3f]!;
        encodedChunks.push(chunk);
      }
    }

    return encodedChunks.join("");
  }
}

export default LuaDeflate;
