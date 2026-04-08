# typed: strict
# frozen_string_literal: true

require 'zlib'
require 'base64'
require 'set'
require 'sorbet-runtime'
require_relative 'lua_deflate_native'
require_relative 'wowace'
require_relative 'lib_serialize'
require_relative 'lib_compress'
require_relative 'vuhdo_serializer'
require_relative 'wow_cbor'

module Azerite
  T.unsafe(self).const_set(:LuaDeflate, LuaDeflateNative) unless defined?(LuaDeflate)

  class ExportResult < T::Struct
    prop :addon, T.nilable(String)
    prop :version, T.nilable(Integer)
    prop :data, T.untyped
    prop :metadata, T.nilable(T::Hash[Symbol, String])
    prop :steps, T::Array[T.untyped], default: []
  end

  class Pipeline
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :raw

    sig { returns(T.nilable(String)) }
    attr_reader :addon

    sig { returns(T.nilable(Integer)) }
    attr_reader :version

    sig { returns(T.nilable(String)) }
    attr_reader :prefix

    sig { returns(T.nilable(T::Hash[Symbol, String])) }
    attr_reader :metadata

    sig { returns(T.nilable(String)) }
    attr_reader :compressed

    sig { returns(T.nilable(String)) }
    attr_reader :serialized

    sig { returns(T.untyped) }
    attr_reader :data

    # -- Step registry -----------------------------------------------------------
    # Each step name maps to [decode_method, encode_method].

    STEPS = T.let({
      prefix: %i[strip_prefix prepend_prefix],
      metadata: %i[extract_metadata append_metadata],
      encode_for_print: %i[decode_for_print do_encode_for_print],
      base64: %i[base64_decode base64_encode],
      zlib: %i[decompress compress],
      lib_compress: %i[lib_compress_decode lib_compress_encode],
      ace_serializer: %i[deserialize_ace serialize_ace],
      lib_serialize: %i[deserialize_lib_serialize serialize_lib_serialize],
      cbor: %i[deserialize_cbor serialize_cbor],
      vuhdo: %i[deserialize_vuhdo serialize_vuhdo]
    }.freeze, T::Hash[Symbol, T::Array[Symbol]])

    # -- Format definitions ------------------------------------------------------
    # Steps can be a symbol (simple) or a hash (step with config).
    # e.g. { prefix: '!WA:2!' } passes '!WA:2!' to the prefix step.

    # Formats that can be auto-detected by prefix (ordered, longest prefix first)
    AUTO_FORMATS = T.let([
      { addon: 'plater',    version: 2, prefix: '!PLATER:2!',
        steps: [{ prefix: '!PLATER:2!' }, :base64, :zlib, :cbor] },
      { addon: 'weakauras', version: 2, prefix: '!WA:2!',
        steps: [{ prefix: '!WA:2!' }, :encode_for_print, :zlib, :lib_serialize] },
      { addon: 'elvui',     version: 1, prefix: '!E1!',
        steps: [{ prefix: '!E1!' }, :encode_for_print, :zlib, :metadata, :ace_serializer] },
      { addon: 'weakauras', version: 1, prefix: '!',
        steps: [{ prefix: '!' }, :encode_for_print, :zlib, :ace_serializer] },
      { addon: 'weakauras', version: 0, prefix: '',
        steps: %i[encode_for_print zlib ace_serializer] }
    ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

    # All known formats, keyed by addon name (for Pipeline.decode(str, addon: 'mdt'))
    FORMATS = T.let({
      'plater' => T.must(AUTO_FORMATS[0])[:steps],
      'weakauras' => T.must(AUTO_FORMATS[1])[:steps], # v2 default
      'elvui' => T.must(AUTO_FORMATS[2])[:steps],
      'cell' => [{ prefix: /^!CELL:\d+:\w+!/ }, :encode_for_print, :zlib, :lib_serialize],
      'dbm' => %i[encode_for_print zlib lib_serialize],
      'mdt' => %i[encode_for_print lib_compress ace_serializer],
      'totalrp3' => [{ prefix: '!' }, :encode_for_print, :zlib, :ace_serializer],
      'vuhdo' => %i[base64 lib_compress vuhdo]
    }.freeze, T::Hash[String, T.untyped])

    # -- Constructor -------------------------------------------------------------

    sig { params(export_str: T.nilable(String)).void }
    def initialize(export_str = nil)
      @raw        = T.let(export_str&.strip, T.nilable(String))
      @addon      = T.let(nil, T.nilable(String))
      @version    = T.let(nil, T.nilable(Integer))
      @prefix     = T.let(nil, T.nilable(String))
      @metadata   = T.let(nil, T.nilable(T::Hash[Symbol, String]))
      @compressed = T.let(nil, T.nilable(String))
      @serialized = T.let(nil, T.nilable(String))
      @data       = T.let(nil, T.untyped)
      @format     = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
      @steps      = T.let(nil, T.nilable(T::Array[T.untyped]))
    end

    sig { params(export_result: ExportResult).returns(Pipeline) }
    def self.from_result(export_result)
      p = new
      p.instance_variable_set(:@addon,    export_result.addon)
      p.instance_variable_set(:@version,  export_result.version)
      p.instance_variable_set(:@data,     export_result.data)
      p.instance_variable_set(:@metadata, export_result.metadata)
      p
    end

    # -- Public API --------------------------------------------------------------

    sig { params(export_str: String, addon: T.nilable(String), steps: T.nilable(T::Array[T.untyped])).returns(ExportResult) }
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
            # No prefix -- default to weakauras v0 (legacy)
            p.instance_variable_set(:@addon, 'weakauras')
            p.instance_variable_set(:@version, 0)
          end
        end
      end
      p.instance_variable_set(:@steps, steps)
      run_steps(p, steps, :decode)
      p.result
    end

    sig { params(export_result: ExportResult, addon: T.nilable(String), steps: T.nilable(T::Array[T.untyped])).returns(String) }
    def self.encode(export_result, addon: nil, steps: nil)
      p = from_result(export_result)
      unless steps
        if addon
          steps = FORMATS[addon]
          raise "Unknown addon: #{addon}" unless steps
        elsif !export_result.steps.empty?
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

    # -- Heuristic detection -----------------------------------------------------
    # Probes each layer to auto-detect the pipeline without a prefix table.
    # Returns the detected steps array.

    KNOWN_PREFIXES = T.let(AUTO_FORMATS
      .reject { |f| f[:prefix].empty? }
      .map { |f| [f[:prefix], f[:addon]] }
      .freeze, T::Array[T::Array[String]])

    ENCODE_FOR_PRINT_CHARS = T.let(Set.new(('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['(', ')']), T::Set[String])
    BASE64_CHARS = T.let(Set.new(('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + ['+', '/', '=']), T::Set[String])

    sig { params(export_str: String).returns(T::Array[T.untyped]) }
    def self.detect_steps(export_str)
      raw = export_str.strip
      steps = T.let([], T::Array[T.untyped])

      # Layer 1: prefix
      # Check specific !..! patterns first (longer match wins over bare !)
      if raw.match?(/^![A-Z][\w:]*!/)
        pfx = T.must(raw[/^![^!]+!/])
        steps << { prefix: pfx }
        raw = T.must(raw[pfx.length..])
      elsif raw.match?(/^[A-Z]+\d*:/)
        pfx = T.must(raw[/^[A-Z]+\d*:/])
        steps << { prefix: pfx }
        raw = T.must(raw[pfx.length..])
      elsif raw.start_with?('!')
        steps << { prefix: '!' }
        raw = T.must(raw[1..])
      end

      # Layer 2: encoding (character set analysis)
      chars = raw.chars.to_set
      if chars.subset?(ENCODE_FOR_PRINT_CHARS)
        steps << :encode_for_print
        raw = T.must(LuaDeflate.decode_for_print(raw))
      elsif chars.subset?(BASE64_CHARS)
        steps << :base64
        raw = Base64.decode64(raw)
      elsif raw.start_with?('{', '[')
        return steps # raw JSON, no further layers
      else
        return steps # plaintext or unknown
      end

      return steps unless raw.length.positive?

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

    # -- Step runner -------------------------------------------------------------

    sig { params(pipeline: Pipeline, steps: T::Array[T.untyped], direction: Symbol).void }
    def self.run_steps(pipeline, steps, direction)
      steps.each do |step|
        if step.is_a?(Hash)
          name, arg = step.first
          method = resolve(T.cast(name, Symbol), direction)
          T.unsafe(pipeline).send(method, arg)
        else
          method = resolve(step, direction)
          T.unsafe(pipeline).send(method)
        end
      end
    end

    sig { params(step: Symbol, direction: Symbol).returns(Symbol) }
    def self.resolve(step, direction)
      pair = STEPS[step]
      raise "Unknown step: #{step}" unless pair

      direction == :decode ? T.must(pair[0]) : T.must(pair[1])
    end

    # -- Format detection --------------------------------------------------------

    sig { returns(Pipeline) }
    def detect_format
      @format = AUTO_FORMATS.find { |f| !f[:prefix].empty? && T.must(@raw).start_with?(f[:prefix]) }
      @format ||= AUTO_FORMATS.last

      @addon   = T.must(@format)[:addon]
      @version = T.must(@format)[:version]
      @prefix  = T.must(@format)[:prefix]
      self
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    attr_reader :format

    sig { params(addon: T.nilable(String), version: T.nilable(Integer)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.find_format(addon, version)
      AUTO_FORMATS.find { |f| f[:addon] == addon && f[:version] == version }
    end

    # -- Decode step implementations -----------------------------------------------

    sig { params(pfx: T.any(String, Regexp)).returns(Pipeline) }
    def strip_prefix(pfx)
      if pfx.is_a?(Regexp)
        m = T.must(@raw).match(pfx)
        raise "Prefix pattern #{pfx} not found" unless m

        @prefix = m[0]
        @raw = T.must(@raw)[T.must(@prefix).length..]
      else
        @prefix = pfx
        @raw = T.must(@raw)[pfx.length..]
      end
      self
    end

    sig { returns(Pipeline) }
    def extract_metadata
      text = T.must(@serialized).force_encoding('UTF-8')
      meta_idx = text.index('^^::')
      if meta_idx
        meta_part = T.must(text[(meta_idx + 4)..])
        parts     = meta_part.split('::')
        @metadata = { profile_type: T.must(parts[0]), profile_key: T.must(parts[1]) }
        @serialized = text[0..(meta_idx + 1)] # keep the ^^ terminator
      end
      self
    end

    sig { returns(Pipeline) }
    def decode_for_print
      @compressed = LuaDeflate.decode_for_print(T.must(@raw))
      raise 'LuaDeflate decode failed' unless @compressed

      self
    end

    sig { returns(Pipeline) }
    def base64_decode
      @compressed = Base64.decode64(T.must(@raw))
      self
    end

    sig { returns(Pipeline) }
    def decompress
      @serialized = inflate_raw(T.must(@compressed))
      self
    end

    sig { returns(Pipeline) }
    def lib_compress_decode
      @serialized = LibCompress.decompress(T.must(@compressed))
      self
    end

    sig { returns(Pipeline) }
    def deserialize_cbor
      @data = WowCbor.decode(T.must(@serialized))
      self
    end

    sig { returns(Pipeline) }
    def deserialize_lib_serialize
      @data = LibSerializeDeserialize.deserialize(T.must(@serialized))
      self
    end

    sig { returns(Pipeline) }
    def deserialize_ace
      @data = WowAceSerializer.new.deserialize(T.must(@serialized).force_encoding('UTF-8'))
      self
    end

    sig { returns(Pipeline) }
    def deserialize_vuhdo
      @data = VuhDoSerializer.deserialize(T.must(@serialized).force_encoding('UTF-8'))
      self
    end

    sig { returns(ExportResult) }
    def result
      ExportResult.new(addon: @addon, version: @version, data: @data, metadata: @metadata, steps: @steps || [])
    end

    # -- Encode step implementations -----------------------------------------------

    sig { returns(Pipeline) }
    def serialize_cbor
      @serialized = WowCbor.encode(@data)
      self
    end

    sig { returns(Pipeline) }
    def serialize_lib_serialize
      @serialized = LibSerializeSerialize.serialize(@data)
      self
    end

    sig { returns(Pipeline) }
    def serialize_ace
      @serialized = WowAceSerializer.new.serialize(@data)
      self
    end

    sig { returns(Pipeline) }
    def serialize_vuhdo
      @serialized = VuhDoSerializer.serialize(@data)
      self
    end

    sig { returns(Pipeline) }
    def compress
      @compressed = deflate_raw(T.must(@serialized).b)
      self
    end

    sig { returns(Pipeline) }
    def lib_compress_encode
      @compressed = T.unsafe(LibCompress).compress(T.must(@serialized))
      self
    end

    sig { returns(Pipeline) }
    def do_encode_for_print
      @raw = LuaDeflate.encode_for_print(T.must(@compressed))
      self
    end

    sig { returns(Pipeline) }
    def base64_encode
      @raw = Base64.strict_encode64(T.must(@compressed))
      self
    end

    sig { params(pfx: T.any(String, Regexp)).returns(Pipeline) }
    def prepend_prefix(pfx)
      @raw = pfx.to_s + T.must(@raw)
      self
    end

    sig { returns(Pipeline) }
    def append_metadata
      return self unless @metadata

      @serialized = T.must(@serialized) + "::#{@metadata[:profile_type]}::#{@metadata[:profile_key]}"
      self
    end

    sig { returns(String) }
    def to_string
      T.must(@raw)
    end

    private

    sig { params(data: String).returns(String) }
    def inflate_raw(data)
      z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      z.inflate(data)
    ensure
      z&.close
    end

    sig { params(data: String).returns(String) }
    def deflate_raw(data)
      z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
      z.deflate(data, Zlib::FINISH)
    ensure
      z&.close
    end
  end
end
