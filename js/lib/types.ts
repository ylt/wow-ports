export type StepName =
  | "prefix"
  | "metadata"
  | "encode_for_print"
  | "base64"
  | "zlib"
  | "lib_compress"
  | "ace_serializer"
  | "lib_serialize"
  | "cbor"
  | "vuhdo";

export type Step = StepName | { prefix: string | RegExp };

export interface FormatConfig {
  addon: string;
  version: number;
  prefix: string | RegExp;
  steps: Step[];
}

export interface ExportResult {
  addon: string | null;
  version: number | null;
  data: unknown;
  metadata: { profileType: string; profileKey: string } | null;
  steps: Step[];
}

export interface DecodeOptions {
  addon?: string;
  steps?: Step[];
}

export interface EncodeOptions {
  addon?: string;
  steps?: Step[];
}

export type DecodeStepMethodName =
  | "strip_prefix"
  | "extract_metadata"
  | "decode_for_print"
  | "base64_decode"
  | "decompress"
  | "lib_compress_decode"
  | "deserialize_ace"
  | "deserialize_lib_serialize"
  | "deserialize_cbor"
  | "deserialize_vuhdo";

export type EncodeStepMethodName =
  | "prepend_prefix"
  | "append_metadata"
  | "do_encode_for_print"
  | "base64_encode"
  | "compress"
  | "lib_compress_encode"
  | "serialize_ace"
  | "serialize_lib_serialize"
  | "serialize_cbor"
  | "serialize_vuhdo";

export type StepMethodName = DecodeStepMethodName | EncodeStepMethodName;

export type StepRegistry = Record<
  StepName,
  [DecodeStepMethodName, EncodeStepMethodName]
>;
