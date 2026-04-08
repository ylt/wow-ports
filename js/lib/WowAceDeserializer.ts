class StringCursor {
  private _s: string;
  private _pos: number;

  constructor(str: string) {
    this._s = str;
    this._pos = 0;
  }

  eof(): boolean {
    return this._pos >= this._s.length;
  }

  read(n: number): string {
    const chunk = this._s.substr(this._pos, n);
    this._pos += n;
    return chunk;
  }

  readPattern(pattern: string | RegExp): string | null {
    if (this.eof()) return null;
    const trail = this._s.slice(this._pos);
    if (typeof pattern === "string") {
      if (!trail.startsWith(pattern)) return null;
      this._pos += pattern.length;
      return pattern;
    }
    const m = trail.match(pattern);
    if (!m || m.index !== 0) return null;
    this._pos += m[0].length;
    return m[0];
  }

  peekPattern(str: string): string | null {
    return this._s.startsWith(str, this._pos) ? str : null;
  }

  skip(n: number): void {
    this._pos += n;
  }

  skipPattern(pattern: string | RegExp): number {
    if (typeof pattern === "string") {
      if (this._s.startsWith(pattern, this._pos)) {
        this._pos += pattern.length;
        return pattern.length;
      }
      return 0;
    }
    const trail = this._s.slice(this._pos);
    const m = trail.match(pattern);
    if (m && m.index === 0) {
      this._pos += m[0].length;
      return m[0].length;
    }
    return 0;
  }
}

class WowAceDeserializer {
  stream: StringCursor;

  constructor(serializedStr: string) {
    this.stream = new StringCursor(serializedStr.replace(/[\x00-\x20]/g, ""));
    if (!this.stream.readPattern("^1")) {
      throw new Error("Invalid prefix");
    }
  }

  deserialize(): unknown {
    const result = this.deserializeInternal();
    if (!this.stream.readPattern("^^")) {
      throw new Error("Missing '^^' terminator");
    }
    return result;
  }

  deserializeInternal(): unknown {
    if (this.stream.eof()) {
      throw new Error("Unexpected end of data");
    }

    const prefix = this.stream.read(2);
    switch (prefix[1]) {
      case "S":
        return this.deserializeString();
      case "N":
        return this.deserializeNumber();
      case "F":
        return this.deserializeFloat();
      case "T":
        return this.deserializeTable();
      case "B":
        return true;
      case "b":
        return false;
      case "Z":
        return null;
      default:
        throw new Error(`Unsupported data type: ${prefix}`);
    }
  }

  deserializeString(): string {
    const stringData = this.stream.readPattern(/^[^^]*/);
    return stringData!.replace(/~(.)/g, (_match: string, char: string) => {
      const code = char.charCodeAt(0);
      if (code < 122) {
        const byte = code - 64;
        if (byte < 0) throw new Error(`Invalid escape sequence: ~${char}`);
        return String.fromCharCode(byte);
      }
      switch (char) {
        case "z":
          return "\x1E";
        case "{":
          return "\x7F";
        case "|":
          return "~";
        case "}":
          return "^";
        default:
          return `~${char}`;
      }
    });
  }

  deserializeNumber(): number {
    const numberStr = this.stream.readPattern(/^[^^]*/);
    if (numberStr === "1.#INF" || numberStr === "inf") return Infinity;
    if (numberStr === "-1.#INF" || numberStr === "-inf") return -Infinity;
    if (/^-?\d+$/.test(numberStr!)) return parseInt(numberStr!, 10);
    return parseFloat(numberStr!);
  }

  deserializeFloat(): number {
    const mantissa = parseInt(this.stream.readPattern(/^-?\d+/)!, 10);
    this.stream.skipPattern("^f");
    const exponent = parseInt(this.stream.readPattern(/^-?\d+/)!, 10);
    return mantissa * Math.pow(2, exponent);
  }

  deserializeTable(): Record<string | number, unknown> {
    const table: Record<string | number, unknown> = {};
    while (!this.stream.peekPattern("^t")) {
      const key = this.deserializeInternal() as string | number;
      const value = this.deserializeInternal();
      table[key] = value;
    }
    this.stream.skip(2);

    return table;
  }
}

export default WowAceDeserializer;
