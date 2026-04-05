-- LibDeflate EncodeForPrint/DecodeForPrint test suite — busted spec
-- CWD is lua/ when run via busted.

local LibDeflate = dofile("deps/LibDeflate.lua")

local alphabet = {}
for b = string.byte('a'), string.byte('z') do alphabet[string.char(b)] = true end
for b = string.byte('A'), string.byte('Z') do alphabet[string.char(b)] = true end
for b = string.byte('0'), string.byte('9') do alphabet[string.char(b)] = true end
alphabet['('] = true
alphabet[')'] = true

local function only_alphabet(s)
  for i = 1, #s do
    local c = string.sub(s, i, i)
    if not alphabet[c] then
      error(string.format("char '%s' (byte %d) at pos %d not in alphabet", c, string.byte(c), i), 2)
    end
  end
  return true
end

local function enc(s) return LibDeflate:EncodeForPrint(s) end
local function dec(s) return LibDeflate:DecodeForPrint(s) end

------------------------------------------------------------------------
describe("LibDeflate", function()
------------------------------------------------------------------------

  describe("M. Encode", function()
    it("74. 3-byte input → 4 chars (full group)", function()
      local r = enc("abc")
      assert.are.equal(#r, 4)
      assert.truthy(only_alphabet(r))
    end)

    it("75. 1-byte input → 2 chars (tail)", function()
      local r = enc("a")
      assert.are.equal(#r, 2)
      assert.truthy(only_alphabet(r))
    end)

    it("76. 2-byte input → 3 chars (tail)", function()
      local r = enc("ab")
      assert.are.equal(#r, 3)
      assert.truthy(only_alphabet(r))
    end)

    it("77. 6-byte input → 8 chars (two full groups)", function()
      local r = enc("abcdef")
      assert.are.equal(#r, 8)
      assert.truthy(only_alphabet(r))
    end)

    it("78. Empty input → empty string", function()
      assert.are.equal(enc(""), "")
    end)

    it("79. Output uses only alphabet chars: a-zA-Z0-9()", function()
      local bin = ""
      for i = 0, 255 do bin = bin .. string.char(i) end
      assert.truthy(only_alphabet(enc(bin)))
    end)
  end)

  describe("N. Decode", function()
    it("80. 4-char input → 3 bytes (full group)", function()
      local encoded = enc("abc")
      assert.are.equal(#encoded, 4)
      assert.are.equal(dec(encoded), "abc")
    end)

    it("81. 2-char input → 1 byte (tail)", function()
      local encoded = enc("a")
      assert.are.equal(#encoded, 2)
      assert.are.equal(dec(encoded), "a")
    end)

    it("82. 3-char input → 2 bytes (tail)", function()
      local encoded = enc("ab")
      assert.are.equal(#encoded, 3)
      assert.are.equal(dec(encoded), "ab")
    end)

    it("83. Whitespace stripped from start/end before decode", function()
      local encoded = enc("hello")
      assert.are.equal(dec("  \t" .. encoded .. "\n  "), "hello")
    end)

    it("84. Length-1 input → nil", function()
      assert.is_nil(dec("a"))
    end)

    it("85. Single invalid char → nil", function()
      assert.is_nil(dec("!"))
    end)

    it("86. Invalid character in sequence → nil", function()
      assert.is_nil(dec("abc!"))
      assert.is_nil(dec("!@#$"))
    end)
  end)

  describe("O. Round-trips", function()
    it("87. Simple ASCII string", function()
      local s = "Hello, World!"
      assert.are.equal(dec(enc(s)), s)
    end)

    it("88. Binary data: all 256 byte values", function()
      local bin = ""
      for i = 0, 255 do bin = bin .. string.char(i) end
      assert.are.equal(dec(enc(bin)), bin)
    end)

    it("89. Large payload (1000+ bytes)", function()
      local large = string.rep("The quick brown fox jumps over the lazy dog. ", 25)
      assert.are.equal(dec(enc(large)), large)
    end)

    it("90. Single byte", function()
      assert.are.equal(dec(enc("\x42")), "\x42")
    end)

    it("91. Two bytes", function()
      assert.are.equal(dec(enc("\x01\x02")), "\x01\x02")
    end)

    it("92. Three bytes (boundary)", function()
      assert.are.equal(dec(enc("\xAA\xBB\xCC")), "\xAA\xBB\xCC")
    end)

    it("93. Null bytes round-trip correctly", function()
      assert.are.equal(dec(enc("\x00\x00\x00")), "\x00\x00\x00")
      assert.are.equal(dec(enc("a\x00b\x00c")), "a\x00b\x00c")
    end)
  end)

  describe("P. Native Variant", function()
    it("94. Encode output is deterministic", function()
      local s = "deterministic test"
      assert.are.equal(enc(s), enc(s))
    end)

    it("95. Decode is inverse of encode", function()
      local s = "inverse test \x00\xFF"
      assert.are.equal(dec(enc(s)), s)
    end)

    it("96. Round-trip preserves all byte values in structured payload", function()
      local payload = ""
      for i = 0, 255 do payload = payload .. string.char(i) end
      payload = payload .. payload
      assert.are.equal(dec(enc(payload)), payload)
    end)
  end)

  describe("WIRE FORMAT REFERENCE", function()
    it("prints cross-language fixtures", function()
      local function wire(label, input)
        print(string.format("  %-30s → %s", label, enc(input)))
      end
      print("\n  -- LibDeflate EncodeForPrint wire format --")
      wire('""', "")
      wire('"a"', "a")
      wire('"ab"', "ab")
      wire('"abc"', "abc")
      wire('"Hello, World!"', "Hello, World!")
      wire("NUL byte (\\x00)", "\x00")
      wire("bytes 0x00-0x02", "\x00\x01\x02")
      wire("bytes 0xFF 0xFE 0xFD", "\xFF\xFE\xFD")
      wire('"hello world"', "hello world")
      assert.truthy(true)
    end)
  end)

end)
