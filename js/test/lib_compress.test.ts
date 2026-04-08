import { describe, it, expect } from "bun:test";
import LibCompress from "../lib/LibCompress.js";

describe("LibCompress", () => {
  describe("method 0x01 (uncompressed)", () => {
    it("passes through raw bytes", () => {
      const wire = Buffer.from([0x01, 0x68, 0x65, 0x6c, 0x6c, 0x6f]);
      expect(LibCompress.decompress(wire).toString("binary")).toBe("hello");
    });

    it("handles empty payload", () => {
      const wire = Buffer.from([0x01]);
      expect(LibCompress.decompress(wire).length).toBe(0);
    });
  });

  describe("method 0x02 (LZW)", () => {
    it("decompresses single-byte codes", () => {
      const wire = Buffer.from([0x02, 104, 101, 108, 108, 111]);
      expect(LibCompress.decompress(wire).toString("binary")).toBe("hello");
    });

    it("decompresses with dictionary hits", () => {
      // Codes: 65,66,256,258,66 → "ABABABAB"
      const wire = Buffer.from([0x02, 65, 66, 0xfe, 2, 2, 0xfe, 4, 2, 66]);
      expect(LibCompress.decompress(wire).toString("binary")).toBe("ABABABAB");
    });

    it("decompresses single char", () => {
      const wire = Buffer.from([0x02, 65]);
      expect(LibCompress.decompress(wire).toString("binary")).toBe("A");
    });
  });

  describe("method 0x03 (Huffman)", () => {
    it("decompresses a minimal Huffman stream", () => {
      // 1 symbol ('A'=65), orig_size=3, code=0 (1-bit)
      const wire = Buffer.from([0x03, 0x00, 0x03, 0x00, 0x00, 0x41, 0x06]);
      expect(LibCompress.decompress(wire).toString("binary")).toBe("AAA");
    });
  });

  describe("error handling", () => {
    it("throws on empty input", () => {
      expect(() => LibCompress.decompress(Buffer.alloc(0))).toThrow(/empty/);
    });

    it("throws on unknown method", () => {
      expect(() => LibCompress.decompress(Buffer.from([0x05, 0x00]))).toThrow(
        /Unknown compression method/,
      );
    });
  });
});
