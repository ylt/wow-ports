class WowAceSerializer {
  static serialize(obj: unknown): string {
    return `^1${this._serializeInternal(obj)}^^`;
  }

  static _serializeInternal(obj: unknown): string {
    switch (typeof obj) {
      case "string":
        return this._serializeString(obj);
      case "number":
        return this._serializeNumber(obj);
      case "boolean":
        return obj ? "^B" : "^b";
      case "object":
        if (obj === null) {
          return "^Z";
        } else if (Array.isArray(obj)) {
          return this._serializeArray(obj);
        } else {
          return this._serializeTable(obj as Record<string, unknown>);
        }
      default:
        throw new Error(`Unsupported data type: ${typeof obj}`);
    }
  }

  // Serialization helpers
  static _serializeString(str: string): string {
    const escaped = str.replace(/[\x00-\x20\x5E\x7E\x7F]/g, (m) => {
      const byte = m.charCodeAt(0);
      if (byte === 0x1e) return "~z";
      if (byte === 0x5e) return "~}";
      if (byte === 0x7e) return "~|";
      if (byte === 0x7f) return "~{";
      return `~${String.fromCharCode(byte + 64)}`;
    });
    return `^S${escaped}`;
  }

  static _frexp(value: number): [number, number] {
    if (value === 0) return [0, 0];
    const data = new DataView(new ArrayBuffer(8));
    data.setFloat64(0, value);
    const bits = (data.getUint32(0) >>> 20) & 0x7ff;
    if (bits === 0) {
      data.setFloat64(0, value * Math.pow(2, 64));
      const bits2 = (data.getUint32(0) >>> 20) & 0x7ff;
      return [value * Math.pow(2, 64 - bits2 + 1022), bits2 - 1022 - 64];
    }
    return [value / Math.pow(2, bits - 1022), bits - 1022];
  }

  static _serializeNumber(num: number): string {
    if (!isFinite(num)) {
      return num > 0 ? "^N1.#INF" : "^N-1.#INF";
    }
    if (Number.isInteger(num)) {
      return `^N${num}`;
    }
    // Lua uses %.14g for tostring() — only use ^N if 14-digit precision roundtrips
    if (parseFloat(num.toPrecision(14)) === num) {
      return `^N${num}`;
    }
    const [m, e] = this._frexp(num);
    const int_mantissa = Math.floor(m * Math.pow(2, 53));
    const adj_exponent = e - 53;
    return `^F${int_mantissa}^f${adj_exponent}`;
  }

  static _serializeTable(table: Record<string, unknown>): string {
    const serialized = Object.entries(table)
      .map(([key, value]) => {
        // Object.entries always returns string keys; detect numeric keys
        // (e.g. array index 1 → "1") and serialize them as numbers.
        const numKey = key === "" ? NaN : Number(key);
        const serializedKey = Number.isFinite(numKey)
          ? this._serializeNumber(numKey)
          : this._serializeString(key);
        return `${serializedKey}${this._serializeInternal(value)}`;
      })
      .join("");
    return `^T${serialized}^t`;
  }

  static _serializeArray(array: unknown[]): string {
    const indexedTable: Record<number, unknown> = {};
    array.forEach((value, index) => {
      indexedTable[index + 1] = value;
    });
    return this._serializeTable(
      indexedTable as unknown as Record<string, unknown>,
    );
  }
}

export default WowAceSerializer;
