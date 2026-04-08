# typed: strict

module CBOR
  sig { params(data: String).returns(T.untyped) }
  def self.decode(data); end
end

class Object
  sig { returns(String) }
  def to_cbor; end
end
