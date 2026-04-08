// ── Type indices (reader_table dispatch) ───────────────────────────────────
const NIL = 0;
const NUM_16_POS = 1,
  NUM_16_NEG = 2;
const NUM_24_POS = 3,
  NUM_24_NEG = 4;
const NUM_32_POS = 5,
  NUM_32_NEG = 6;
const NUM_64_POS = 7,
  NUM_64_NEG = 8;
const NUM_FLOAT = 9;
const NUM_FLOATSTR_POS = 10,
  NUM_FLOATSTR_NEG = 11;
const BOOL_T = 12,
  BOOL_F = 13;
const STR_8 = 14,
  STR_16 = 15,
  STR_24 = 16;
const TABLE_8 = 17,
  TABLE_16 = 18,
  TABLE_24 = 19;
const ARRAY_8 = 20,
  ARRAY_16 = 21,
  ARRAY_24 = 22;
const MIXED_8 = 23,
  MIXED_16 = 24,
  MIXED_24 = 25;
const STRINGREF_8 = 26,
  STRINGREF_16 = 27,
  STRINGREF_24 = 28;
const TABLEREF_8 = 29,
  TABLEREF_16 = 30,
  TABLEREF_24 = 31;

// ── Embedded type indices ──────────────────────────────────────────────────
const EMB_STRING = 0,
  EMB_TABLE = 1,
  EMB_ARRAY = 2,
  EMB_MIXED = 3;
const EMBEDDED_INDEX_SHIFT = 2,
  EMBEDDED_COUNT_SHIFT = 4;

// byte_count → type index for large positive integers (Lua uses keys 2,3,4,7)
const NUMBER_INDICES: (number | null)[] = [
  null,
  null,
  NUM_16_POS,
  NUM_24_POS,
  NUM_32_POS,
  null,
  null,
  NUM_64_POS,
];

const STRING_TYPE: (number | null)[] = [null, STR_8, STR_16, STR_24];
const TABLE_TYPE: (number | null)[] = [null, TABLE_8, TABLE_16, TABLE_24];
const ARRAY_TYPE: (number | null)[] = [null, ARRAY_8, ARRAY_16, ARRAY_24];
const STRING_REF_TYPE: (number | null)[] = [
  null,
  STRINGREF_8,
  STRINGREF_16,
  STRINGREF_24,
];
const TABLE_REF_TYPE: (number | null)[] = [
  null,
  TABLEREF_8,
  TABLEREF_16,
  TABLEREF_24,
];

// ── Shared utilities ───────────────────────────────────────────────────────
function getRequiredBytes(value: number): number {
  if (value < 256) return 1;
  if (value < 65536) return 2;
  if (value < 16777216) return 3;
  throw new Error("Object limit exceeded");
}

function getRequiredBytesNumber(value: number): number {
  if (value < 256) return 1;
  if (value < 65536) return 2;
  if (value < 16777216) return 3;
  if (value < 4294967296) return 4;
  return 7;
}

// ── Deserializer ───────────────────────────────────────────────────────────
class LibSerializeDeserialize {
  data: Buffer;
  pos: number;
  string_refs: string[];
  table_refs: Record<string | number, unknown>[];

  constructor(data: Buffer | Uint8Array | string) {
    this.data = Buffer.isBuffer(data)
      ? data
      : typeof data === "string"
        ? Buffer.from(data, "binary")
        : Buffer.from(data);
    this.pos = 0;
    this.string_refs = [];
    this.table_refs = [];
  }

  static deserialize(data: Buffer | Uint8Array | string): unknown {
    return new LibSerializeDeserialize(data).deserialize();
  }

  deserialize(): unknown {
    this.readByte(); // version byte
    return this.readObject();
  }

  readByte(): number {
    return this.data[this.pos++]!;
  }

  readInt(n: number): number {
    let v = 0;
    for (let i = 0; i < n; i++) v = v * 256 + this.data[this.pos++]!;
    return v;
  }

  readBytes(n: number): Buffer {
    const slice = this.data.slice(this.pos, this.pos + n);
    this.pos += n;
    return slice;
  }

  readString(len: number): string {
    const str = this.readBytes(len).toString("binary");
    if (len > 2) this.string_refs.push(str);
    return str;
  }

  readObject(): unknown {
    const byte = this.readByte();

    // Embedded small positive integer 0-127: odd byte
    if (byte % 2 === 1) return (byte - 1) / 2;

    // Embedded type + count: byte % 4 === 2
    if (byte % 4 === 2) {
      const combined = (byte - 2) / 4;
      const count = Math.floor(combined / 4);
      const typ = combined % 4;
      return this.embeddedReader(typ, count);
    }

    // 2-byte small integer: byte % 8 === 4
    if (byte % 8 === 4) {
      const hi = this.readByte();
      const packed = hi * 256 + byte;
      return byte % 16 === 12 ? -(packed - 12) / 16 : (packed - 4) / 16;
    }

    // Named type
    return this.readerTable(byte / 8);
  }

  embeddedReader(type: number, count: number): unknown {
    switch (type) {
      case EMB_STRING:
        return this.readString(count);
      case EMB_TABLE:
        return this.readTable(count);
      case EMB_ARRAY:
        return this.readArray(count);
      case EMB_MIXED:
        return this.readMixed((count % 4) + 1, Math.floor(count / 4) + 1);
      default:
        throw new Error(`Unknown embedded type: ${type}`);
    }
  }

  readerTable(type: number): unknown {
    switch (type) {
      case NIL:
        return null;
      case NUM_16_POS:
        return this.readInt(2);
      case NUM_16_NEG:
        return -this.readInt(2);
      case NUM_24_POS:
        return this.readInt(3);
      case NUM_24_NEG:
        return -this.readInt(3);
      case NUM_32_POS:
        return this.readInt(4);
      case NUM_32_NEG:
        return -this.readInt(4);
      case NUM_64_POS:
        return this.readInt(7);
      case NUM_64_NEG:
        return -this.readInt(7);
      case NUM_FLOAT: {
        const buf = this.readBytes(8);
        const dv = new DataView(buf.buffer, buf.byteOffset, 8);
        return dv.getFloat64(0, false);
      }
      case NUM_FLOATSTR_POS:
        return parseFloat(this.readBytes(this.readByte()).toString("binary"));
      case NUM_FLOATSTR_NEG:
        return -parseFloat(this.readBytes(this.readByte()).toString("binary"));
      case BOOL_T:
        return true;
      case BOOL_F:
        return false;
      case STR_8:
        return this.readString(this.readByte());
      case STR_16:
        return this.readString(this.readInt(2));
      case STR_24:
        return this.readString(this.readInt(3));
      case TABLE_8:
        return this.readTable(this.readByte());
      case TABLE_16:
        return this.readTable(this.readInt(2));
      case TABLE_24:
        return this.readTable(this.readInt(3));
      case ARRAY_8:
        return this.readArray(this.readByte());
      case ARRAY_16:
        return this.readArray(this.readInt(2));
      case ARRAY_24:
        return this.readArray(this.readInt(3));
      case MIXED_8:
        return this.readMixed(this.readByte(), this.readByte());
      case MIXED_16:
        return this.readMixed(this.readInt(2), this.readInt(2));
      case MIXED_24:
        return this.readMixed(this.readInt(3), this.readInt(3));
      case STRINGREF_8:
        return this.string_refs[this.readByte() - 1];
      case STRINGREF_16:
        return this.string_refs[this.readInt(2) - 1];
      case STRINGREF_24:
        return this.string_refs[this.readInt(3) - 1];
      case TABLEREF_8:
        return this.table_refs[this.readByte() - 1];
      case TABLEREF_16:
        return this.table_refs[this.readInt(2) - 1];
      case TABLEREF_24:
        return this.table_refs[this.readInt(3) - 1];
      default:
        throw new Error(`Unknown type in reader table: ${type}`);
    }
  }

  // readTable: if existingObj supplied, populates it (no new ref added)
  readTable(
    count: number,
    existingObj: Record<string | number, unknown> | null = null,
  ): Record<string | number, unknown> {
    const table = existingObj || {};
    if (!existingObj) this.table_refs.push(table);
    for (let i = 0; i < count; i++) {
      const k = this.readObject() as string | number;
      table[k] = this.readObject();
    }
    return table;
  }

  readArray(count: number): Record<number, unknown> {
    const obj: Record<number, unknown> = {};
    this.table_refs.push(obj);
    for (let i = 0; i < count; i++) obj[i + 1] = this.readObject();
    return obj;
  }

  // readMixed: 1-based integer keys for array portion (bug fix vs Ruby 0-based)
  readMixed(
    arrayCount: number,
    mapCount: number,
  ): Record<string | number, unknown> {
    const value: Record<string | number, unknown> = {};
    this.table_refs.push(value);
    for (let i = 0; i < arrayCount; i++) value[i + 1] = this.readObject();
    this.readTable(mapCount, value); // populates value, no extra ref
    return value;
  }
}

// ── Serializer ─────────────────────────────────────────────────────────────
class LibSerializeSerialize {
  data: unknown;
  buf: number[];
  string_refs: Record<string, number>;
  object_refs: Map<object, number>;

  constructor(data: unknown) {
    this.data = data;
    this.buf = []; // byte accumulator
    this.string_refs = {}; // string → 1-based wire index
    this.object_refs = new Map(); // object identity → 1-based wire index
  }

  static serialize(data: unknown): Buffer {
    return new LibSerializeSerialize(data).serialize();
  }

  writeByte(b: number): void {
    this.buf.push(b & 0xff);
  }
  writeBytes(bs: Buffer | number[]): void {
    for (const b of bs) this.buf.push(b);
  }

  writeInt(n: number, required: number): void {
    switch (required) {
      case 1:
        this.writeByte(n);
        break;
      case 2:
        this.writeByte((n >> 8) & 0xff);
        this.writeByte(n & 0xff);
        break;
      case 3:
        this.writeByte((n >> 16) & 0xff);
        this.writeByte((n >> 8) & 0xff);
        this.writeByte(n & 0xff);
        break;
      case 4:
        this.writeByte((n >>> 24) & 0xff);
        this.writeByte((n >> 16) & 0xff);
        this.writeByte((n >> 8) & 0xff);
        this.writeByte(n & 0xff);
        break;
      case 7: {
        const hi = Math.floor(n / 0x100000000);
        this.writeByte((hi >> 16) & 0xff);
        this.writeByte((hi >> 8) & 0xff);
        this.writeByte(hi & 0xff);
        this.writeByte((n >>> 24) & 0xff);
        this.writeByte((n >> 16) & 0xff);
        this.writeByte((n >> 8) & 0xff);
        this.writeByte(n & 0xff);
        break;
      }
      default:
        throw new Error(`Invalid required bytes: ${required}`);
    }
  }

  floatToBytes(n: number): Buffer {
    const buf = Buffer.alloc(8);
    new DataView(buf.buffer).setFloat64(0, n, false);
    return buf;
  }

  serialize(): Buffer {
    this.writeInt(1, 1); // version byte
    this.writeObject(this.data);
    return Buffer.from(this.buf);
  }

  writeObject(obj: unknown): void {
    if (obj === null || obj === undefined) return this.serializeNil();
    if (typeof obj === "boolean") return this.serializeBoolean(obj);
    if (typeof obj === "number") return this.serializeNumber(obj);
    if (typeof obj === "string") return this.serializeString(obj);
    if (Array.isArray(obj)) return this.serializeArray(obj);
    if (typeof obj === "object")
      return this.serializeTable(obj as Record<string, unknown>);
    throw new Error(`Unsupported type: ${typeof obj}`);
  }

  serializeNil(): void {
    this.writeByte(NIL << 3);
  }

  serializeBoolean(b: boolean): void {
    this.writeByte((b ? BOOL_T : BOOL_F) << 3);
  }

  serializeNumber(n: number): void {
    if (!Number.isInteger(n)) return this.serializeFloat(n);
    if (n >= 0 && n < 128) {
      this.writeByte(n * 2 + 1); // embedded small int
    } else if (n > -4096 && n < 0) {
      const packed = Math.abs(n) * 16 + 8 + 4; // 2-byte small neg
      this.writeByte(packed % 256);
      this.writeByte(Math.floor(packed / 256));
    } else {
      this.serializeLargeInteger(n);
    }
  }

  serializeFloat(n: number): void {
    const absN = Math.abs(n);
    const asStr = String(absN);
    if (asStr.length < 7 && parseFloat(asStr) === absN && isFinite(absN)) {
      const sign = n < 0 ? 1 : 0;
      this.writeByte((sign + NUM_FLOATSTR_POS) << 3);
      this.writeByte(asStr.length);
      this.writeBytes(Buffer.from(asStr, "binary"));
    } else {
      this.writeByte(NUM_FLOAT << 3);
      this.writeBytes(this.floatToBytes(n));
    }
  }

  serializeLargeInteger(n: number): void {
    const sign = n < 0 ? 1 : 0;
    const abs = Math.abs(n);
    let required = getRequiredBytesNumber(abs);
    if (required === 1) required = 2; // no 1-byte type; use NUM_16 with padding
    this.writeByte((sign + NUMBER_INDICES[required]!) << 3);
    this.writeInt(abs, required);
  }

  serializeString(str: string): void {
    const ref = this.string_refs[str];
    if (ref !== undefined) {
      const reqBytes = getRequiredBytes(ref);
      this.writeByte(STRING_REF_TYPE[reqBytes]! << 3);
      this.writeInt(ref, reqBytes);
    } else {
      const bytes = Buffer.from(str, "binary");
      const len = bytes.length;
      this.writeTypeWithCount(EMB_STRING, STRING_TYPE, len);
      this.writeBytes(bytes);
      if (len > 2) {
        // 1-based index: first string stored = 1
        this.string_refs[str] = Object.keys(this.string_refs).length + 1;
      }
    }
  }

  serializeArray(arr: unknown[]): void {
    const ref = this.object_refs.get(arr);
    if (ref !== undefined) {
      const reqBytes = getRequiredBytes(ref);
      this.writeByte(TABLE_REF_TYPE[reqBytes]! << 3);
      this.writeInt(ref, reqBytes);
    } else {
      const len = arr.length;
      this.writeTypeWithCount(EMB_ARRAY, ARRAY_TYPE, len);
      for (const item of arr) this.writeObject(item);
      if (len > 2) this.object_refs.set(arr, this.object_refs.size + 1);
    }
  }

  serializeTable(obj: Record<string, unknown>): void {
    const ref = this.object_refs.get(obj);
    if (ref !== undefined) {
      const reqBytes = getRequiredBytes(ref);
      this.writeByte(TABLE_REF_TYPE[reqBytes]! << 3);
      this.writeInt(ref, reqBytes);
    } else {
      const keys = Object.keys(obj);
      const len = keys.length;
      // Detect Lua-style array: sequential 1-based integer keys
      if (len > 0 && keys.every((k, i) => k === String(i + 1))) {
        this.writeTypeWithCount(EMB_ARRAY, ARRAY_TYPE, len);
        for (const k of keys) this.writeObject(obj[k]);
      } else {
        this.writeTypeWithCount(EMB_TABLE, TABLE_TYPE, len);
        for (const [k, v] of Object.entries(obj)) {
          this.writeObject(k);
          this.writeObject(v);
        }
      }
      if (len > 2) this.object_refs.set(obj, this.object_refs.size + 1);
    }
  }

  writeTypeWithCount(
    embeddedIndex: number,
    typeIndices: (number | null)[],
    count: number,
  ): void {
    if (count < 16) {
      this.writeByte(
        (embeddedIndex << EMBEDDED_INDEX_SHIFT) |
          (count << EMBEDDED_COUNT_SHIFT) |
          2,
      );
    } else {
      const required = getRequiredBytes(count);
      this.writeByte(typeIndices[required]! << 3);
      this.writeInt(count, required);
    }
  }
}

export { LibSerializeDeserialize, LibSerializeSerialize };
