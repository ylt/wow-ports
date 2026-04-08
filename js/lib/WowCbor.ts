import { decode, encode } from "cbor-x";

/**
 * Post-process a decoded CBOR value:
 * 1. CBOR byte strings (Uint8Array / Buffer) → UTF-8 text strings
 * 2. Sequential 1-based integer-keyed maps → arrays (Lua table convention)
 * 3. Maps returned as Map objects are also handled
 */
function postProcess(val: unknown): unknown {
  if (val instanceof Uint8Array || Buffer.isBuffer(val)) {
    return Buffer.from(val).toString("utf8");
  }
  if (Array.isArray(val)) {
    return val.map(postProcess);
  }
  if (val instanceof Map) {
    // cbor-x may return Map for non-string-keyed CBOR maps
    const obj: Record<string, unknown> = {};
    for (const [k, v] of val) {
      obj[k as string] = postProcess(v);
    }
    return applyArrayDetection(obj);
  }
  if (val !== null && typeof val === "object") {
    const result: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(val as Record<string, unknown>)) {
      result[k] = postProcess(v);
    }
    return applyArrayDetection(result);
  }
  return val;
}

function applyArrayDetection(
  obj: Record<string, unknown>,
): unknown[] | Record<string, unknown> {
  const keys = Object.keys(obj);
  if (keys.length === 0) return obj;
  const nums = keys.map((k) => Number(k));
  if (!nums.every((n) => Number.isInteger(n) && n > 0)) return obj;
  const sorted = [...nums].sort((a, b) => a - b);
  if (sorted.every((n, i) => n === i + 1)) {
    return sorted.map((n) => obj[String(n)]);
  }
  return obj;
}

class WowCbor {
  static decode(bytes: Buffer | Uint8Array | string): unknown {
    const raw = decode(
      Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes as string),
    );
    return postProcess(raw);
  }

  static encode(data: unknown): Buffer {
    const raw = encode(data);
    return Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
  }
}

export default WowCbor;
