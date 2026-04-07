# frozen_string_literal: true

require 'zlib'
require 'base64'
require 'set'
require_relative 'lua_deflate_native'
LuaDeflate = LuaDeflateNative
require_relative 'wowace'
require_relative 'lib_serialize'
require_relative 'lib_compress'
require_relative 'vuhdo_serializer'
require_relative 'wow_cbor'

ExportResult = Struct.new(:addon, :version, :data, :metadata, :steps)

class Pipeline
  attr_reader :raw, :addon, :version, :prefix, :metadata, :compressed, :serialized, :data

  # ── Step registry ─────────────────────────────────────────────────────────
  # Each step name maps to [decode_method, encode_method].

  STEPS = {
    prefix:          %i[strip_prefix         prepend_prefix],
    metadata:        %i[extract_metadata     append_metadata],
    encode_for_print: %i[decode_for_print   do_encode_for_print],
    base64:          %i[base64_decode        base64_encode],
    zlib:            %i[decompress           compress],
    lib_compress:    %i[lib_compress_decode  lib_compress_encode],
    ace_serializer:  %i[deserialize_ace      serialize_ace],
    lib_serialize:   %i[deserialize_lib_serialize serialize_lib_serialize],
    cbor:            %i[deserialize_cbor     serialize_cbor],
    vuhdo:           %i[deserialize_vuhdo   serialize_vuhdo],
  }.freeze

  # ── Format definitions ────────────────────────────────────────────────────
  # Steps can be a symbol (simple) or a hash (step with config).
  # e.g. { prefix: '!WA:2!' } passes '!WA:2!' to the prefix step.

  # Formats that can be auto-detected by prefix (ordered, longest prefix first)
  AUTO_FORMATS = [
    { addon: 'plater',    version: 2, prefix: '!PLATER:2!',
      steps: [{ prefix: '!PLATER:2!' }, :base64, :zlib, :cbor] },
    { addon: 'weakauras', version: 2, prefix: '!WA:2!',
      steps: [{ prefix: '!WA:2!' }, :encode_for_print, :zlib, :lib_serialize] },
    { addon: 'elvui',     version: 1, prefix: '!E1!',
      steps: [{ prefix: '!E1!' }, :encode_for_print, :zlib, :metadata, :ace_serializer] },
    { addon: 'weakauras', version: 1, prefix: '!',
      steps: [{ prefix: '!' }, :encode_for_print, :zlib, :ace_serializer] },
    { addon: 'weakauras', version: 0, prefix: '',
      steps: %i[encode_for_print zlib ace_serializer] },
  ].freeze

  # All known formats, keyed by addon name (for Pipeline.decode(str, addon: 'mdt'))
  FORMATS = {
    'plater'    => AUTO_FORMATS[0][:steps],
    'weakauras' => AUTO_FORMATS[1][:steps],  # v2 default
    'elvui'     => AUTO_FORMATS[2][:steps],
    'cell'      => [{ prefix: /^!CELL:\d+:\w+!/ }, :encode_for_print, :zlib, :lib_serialize],
    'dbm'       => %i[encode_for_print zlib lib_serialize],
    'mdt'       => %i[encode_for_print lib_compress ace_serializer],
    'totalrp3'  => [{ prefix: '!' }, :encode_for_print, :zlib, :ace_serializer],
    'vuhdo'     => %i[base64 lib_compress vuhdo],
  }.freeze

  # ── Constructor ───────────────────────────────────────────────────────────

  def initialize(export_str = nil)
    @raw        = export_str&.strip
    @addon      = nil
    @version    = nil
    @prefix     = nil
    @metadata   = nil
    @compressed = nil
    @serialized = nil
    @data       = nil
  end

  def self.from_result(export_result)
    p = new
    p.instance_variable_set(:@addon,    export_result.addon)
    p.instance_variable_set(:@version,  export_result.version)
    p.instance_variable_set(:@data,     export_result.data)
    p.instance_variable_set(:@metadata, export_result.metadata)
    p
  end

  # ── Public API ────────────────────────────────────────────────────────────

  def self.decode(export_str, addon: nil, steps: nil)
    p = new(export_str)
    unless steps
      if addon
        steps = FORMATS[addon]
        raise "Unknown addon: #{addon}" unless steps
        p.instance_variable_set(:@addon, addon)
      else
        steps = detect_steps(export_str)
        raise 'Could not detect format' if steps.empty?
        # Infer addon from prefix if possible
        pfx_step = steps.find { |s| s.is_a?(Hash) && s.key?(:prefix) }
        if pfx_step
          match = AUTO_FORMATS.find { |f| f[:prefix] == pfx_step[:prefix] }
          if match
            p.instance_variable_set(:@addon, match[:addon])
            p.instance_variable_set(:@version, match[:version])
          end
        else
          # No prefix — default to weakauras v0 (legacy)
          p.instance_variable_set(:@addon, 'weakauras')
          p.instance_variable_set(:@version, 0)
        end
      end
    end
    p.instance_variable_set(:@steps, steps)
    run_steps(p, steps, :decode)
    p.result
  end

  def self.encode(export_result, addon: nil, steps: nil)
    p = from_result(export_result)
    unless steps
      if addon
        steps = FORMATS[addon]
        raise "Unknown addon: #{addon}" unless steps
      elsif export_result.steps
        steps = export_result.steps
      else
        fmt = find_format(export_result.addon, export_result.version)
        raise "Unknown format: #{export_result.addon} v#{export_result.version}" unless fmt
        steps = fmt[:steps]
      end
    end
    run_steps(p, steps.reverse, :encode)
    p.to_string
  end

  # ── Heuristic detection ──────────────────────────────────────────────────
  # Probes each layer to auto-detect the pipeline without a prefix table.
  # Returns the detected steps array.

  KNOWN_PREFIXES = AUTO_FORMATS
    .reject { |f| f[:prefix].empty? }
    .map { |f| [f[:prefix], f[:addon]] }
    .freeze

  ENCODE_FOR_PRINT_CHARS = Set.new(('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['(', ')'])
  BASE64_CHARS = Set.new(('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + ['+', '/', '='])

  def self.detect_steps(export_str)
    raw = export_str.strip
    steps = []

    # Layer 1: prefix
    # Check specific !..! patterns first (longer match wins over bare !)
    if raw.match?(/^![A-Z][\w:]*!/)
      pfx = raw[/^![^!]+!/]
      steps << { prefix: pfx }
      raw = raw[pfx.length..]
    elsif raw.match?(/^[A-Z]+\d*:/)
      pfx = raw[/^[A-Z]+\d*:/]
      steps << { prefix: pfx }
      raw = raw[pfx.length..]
    elsif raw.start_with?('!')
      steps << { prefix: '!' }
      raw = raw[1..]
    end

    # Layer 2: encoding (character set analysis)
    chars = raw.chars.to_set
    if chars.subset?(ENCODE_FOR_PRINT_CHARS)
      steps << :encode_for_print
      raw = LuaDeflate.decode_for_print(raw)
    elsif chars.subset?(BASE64_CHARS)
      steps << :base64
      raw = Base64.decode64(raw)
    elsif raw.start_with?('{', '[')
      return steps # raw JSON, no further layers
    else
      return steps # plaintext or unknown
    end

    return steps unless raw && raw.length > 0

    # Layer 3: compression (probe first byte)
    first_byte = raw.getbyte(0)
    if [1, 2, 3].include?(first_byte)
      # LibCompress marker
      steps << :lib_compress
      raw = LibCompress.decompress(raw)
    else
      # Try zlib
      begin
        z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        raw = z.inflate(raw)
        z.close
        steps << :zlib
      rescue Zlib::DataError
        return steps # unknown compression
      end
    end

    # Layer 4: serializer (probe content)
    first = raw.getbyte(0)
    if raw.start_with?('^1')
      steps << :metadata if raw.include?('^^::')
      steps << :ace_serializer
    elsif first == 1
      steps << :lib_serialize
    elsif first && (first >> 5) == 5
      # CBOR map: major type 5 = 0xA0..0xBF
      steps << :cbor
    elsif first && (first >> 5) == 4
      # CBOR array: major type 4 = 0x80..0x9F
      steps << :cbor
    end

    steps
  end

  # ── Step runner ───────────────────────────────────────────────────────────

  def self.run_steps(pipeline, steps, direction)
    steps.each do |step|
      if step.is_a?(Hash)
        name, arg = step.first
        method = resolve(name, direction)
        pipeline.send(method, arg)
      else
        method = resolve(step, direction)
        pipeline.send(method)
      end
    end
  end

  def self.resolve(step, direction)
    pair = STEPS[step]
    raise "Unknown step: #{step}" unless pair
    direction == :decode ? pair[0] : pair[1]
  end

  # ── Format detection ──────────────────────────────────────────────────────

  def detect_format
    @format = AUTO_FORMATS.find { |f| !f[:prefix].empty? && @raw.start_with?(f[:prefix]) }
    @format ||= AUTO_FORMATS.last

    @addon   = @format[:addon]
    @version = @format[:version]
    @prefix  = @format[:prefix]
    self
  end

  def format
    @format
  end

  def self.find_format(addon, version)
    AUTO_FORMATS.find { |f| f[:addon] == addon && f[:version] == version }
  end

  # ── Decode step implementations ─────────────────────────────────────────────

  def strip_prefix(pfx)
    if pfx.is_a?(Regexp)
      m = @raw.match(pfx)
      raise "Prefix pattern #{pfx} not found" unless m
      @prefix = m[0]
      @raw = @raw[@prefix.length..]
    else
      @prefix = pfx
      @raw = @raw[pfx.length..]
    end
    self
  end

  def extract_metadata
    text = @serialized.force_encoding('UTF-8')
    meta_idx = text.index('^^::')
    if meta_idx
      meta_part = text[(meta_idx + 4)..]
      parts     = meta_part.split('::')
      @metadata = { profile_type: parts[0], profile_key: parts[1] }
      @serialized = text[0..meta_idx + 1] # keep the ^^ terminator
    end
    self
  end

  def decode_for_print
    @compressed = LuaDeflate.decode_for_print(@raw)
    raise 'LuaDeflate decode failed' unless @compressed
    self
  end

  def base64_decode
    @compressed = Base64.decode64(@raw)
    self
  end

  def decompress
    @serialized = inflate_raw(@compressed)
    self
  end

  def lib_compress_decode
    @serialized = LibCompress.decompress(@compressed)
    self
  end

  def deserialize_cbor
    @data = WowCbor.decode(@serialized)
    self
  end

  def deserialize_lib_serialize
    @data = LibSerializeDeserialize.deserialize(@serialized)
    self
  end

  def deserialize_ace
    @data = WowAceSerializer.new.deserialize(@serialized.force_encoding('UTF-8'))
    self
  end

  def deserialize_vuhdo
    @data = VuhDoSerializer.deserialize(@serialized.force_encoding('UTF-8'))
    self
  end

  def result
    ExportResult.new(@addon, @version, @data, @metadata, @steps)
  end

  # ── Encode step implementations ─────────────────────────────────────────────

  def serialize_cbor
    @serialized = WowCbor.encode(@data)
    self
  end

  def serialize_lib_serialize
    @serialized = LibSerializeSerialize.serialize(@data)
    self
  end

  def serialize_ace
    @serialized = WowAceSerializer.new.serialize(@data)
    self
  end

  def serialize_vuhdo
    @serialized = VuhDoSerializer.serialize(@data)
    self
  end

  def compress
    @compressed = deflate_raw(@serialized.b)
    self
  end

  def lib_compress_encode
    @compressed = LibCompress.compress(@serialized)
    self
  end

  def do_encode_for_print
    @raw = LuaDeflate.encode_for_print(@compressed)
    self
  end

  def base64_encode
    @raw = Base64.strict_encode64(@compressed)
    self
  end

  def prepend_prefix(pfx)
    @raw = pfx + @raw
    self
  end

  def append_metadata
    return self unless @metadata
    @serialized += "::#{@metadata[:profile_type]}::#{@metadata[:profile_key]}"
    self
  end

  def to_string
    @raw
  end

  private

  def inflate_raw(data)
    z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    z.inflate(data)
  ensure
    z&.close
  end

  def deflate_raw(data)
    z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    z.deflate(data, Zlib::FINISH)
  ensure
    z&.close
  end
end
