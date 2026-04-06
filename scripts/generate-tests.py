#!/usr/bin/env python3
"""Generate native test files for JS, Ruby, Python, and Lua from testdata/tests.yaml."""

import re
import sys
from itertools import groupby
from pathlib import Path

import jinja2
import yaml

ROOT = Path(__file__).resolve().parent.parent
YAML_PATH = ROOT / "testdata" / "tests.yaml"
TEMPLATE_DIR = ROOT / "templates"

OUTPUT_MAP = {
    "ace_serializer": {
        "js": ROOT / "js" / "test" / "ace_serializer.test.js",
        "ruby": ROOT / "ruby" / "spec" / "wowace_spec.rb",
        "python": ROOT / "python" / "tests" / "test_ace_serializer.py",
        "lua": ROOT / "lua" / "test" / "ace_serializer_spec.lua",
    },
    "lua_deflate": {
        "js": ROOT / "js" / "test" / "lua_deflate.test.js",
        "ruby": ROOT / "ruby" / "spec" / "lua_deflate_spec.rb",
        "python": ROOT / "python" / "tests" / "test_lua_deflate.py",
        "lua": ROOT / "lua" / "test" / "lua_deflate_spec.lua",
    },
    "lib_serialize": {
        "js": ROOT / "js" / "test" / "lib_serialize.test.js",
        "ruby": ROOT / "ruby" / "spec" / "lib_serialize_spec.rb",
        "python": ROOT / "python" / "tests" / "test_lib_serialize.py",
        "lua": ROOT / "lua" / "test" / "lib_serialize_spec.lua",
    },
    "cbor": {
        "js": ROOT / "js" / "test" / "cbor.test.js",
        "ruby": ROOT / "ruby" / "spec" / "cbor_spec.rb",
        "python": ROOT / "python" / "tests" / "test_cbor.py",
    },
    "pipeline": {
        "js": ROOT / "js" / "test" / "pipeline.test.js",
        "ruby": ROOT / "ruby" / "spec" / "pipeline_spec.rb",
        "python": ROOT / "python" / "tests" / "test_pipeline.py",
    },
}


def snake_case(s: str) -> str:
    """Convert a description string to a valid Python/Ruby snake_case identifier."""
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    s = s.strip("_")
    return s


def group_by_section(tests: list[dict]) -> list[tuple[str, list[dict]]]:
    """Group tests by their section field, preserving order."""
    groups = []
    for key, group in groupby(tests, key=lambda t: t["section"]):
        groups.append((key, list(group)))
    return groups


def render_value(val, lang: str, module: str = "ace_serializer") -> str:
    """Render a plain YAML value (string, number, bool, None) as language code."""
    if val is None:
        return {"js": "null", "ruby": "nil", "python": "None", "lua": "nil"}[lang]
    if isinstance(val, bool):
        return {
            "js": "true" if val else "false",
            "ruby": "true" if val else "false",
            "python": "True" if val else "False",
            "lua": "true" if val else "false",
        }[lang]
    if isinstance(val, float):
        # Ensure proper float representation
        s = repr(val)
        return s
    if isinstance(val, int):
        return str(val)
    if isinstance(val, str):
        return render_string(val, lang)
    if isinstance(val, dict):
        if "type" in val:
            return render_typed_input(val, lang)
        return render_table(val, lang, module)
    if isinstance(val, list):
        return render_array(val, lang, module)
    raise ValueError(f"Unsupported value type: {type(val)}: {val!r}")


def render_array(val: list, lang: str, module: str = "ace_serializer") -> str:
    """Render a list/array literal for a given language."""
    items = [render_input(v, lang, module) for v in val]
    joined = ", ".join(items)
    if lang == "js":
        return f"[{joined}]"
    if lang == "ruby":
        return f"[{joined}]"
    if lang == "python":
        return f"[{joined}]"
    if lang == "lua":
        return "{ " + joined + " }"
    raise ValueError(f"Unknown lang: {lang}")


def render_string(s: str, lang: str) -> str:
    """Render a string literal with proper escaping per language."""
    # Check for bytes that need special handling
    needs_escape = any(ord(c) < 32 or ord(c) == 127 or ord(c) > 127 for c in s)
    if not needs_escape:
        # Simple string with safe escaping
        escaped = s.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')
        if lang == "js":
            return f"'{escaped}'"
        if lang == "ruby":
            return f"'{escaped}'"
        if lang == "python":
            return f"'{escaped}'"
        if lang == "lua":
            return f'"{escaped}"'
    # Has special characters - use language-specific byte escaping
    return _render_string_with_escapes(s, lang)


def _render_string_with_escapes(s: str, lang: str) -> str:
    """Render a string that contains control chars or high bytes."""
    if lang == "js":
        parts = []
        for c in s:
            o = ord(c)
            if o < 32 or o == 127 or o > 127:
                parts.append(f"\\x{o:02x}")
            elif c == "'":
                parts.append("\\'")
            elif c == "\\":
                parts.append("\\\\")
            else:
                parts.append(c)
        return "'" + "".join(parts) + "'"
    if lang == "ruby":
        parts = []
        for c in s:
            o = ord(c)
            if o < 32 or o == 127 or o > 127:
                parts.append(f"\\x{o:02X}")
            elif c == '"':
                parts.append('\\"')
            elif c == "\\":
                parts.append("\\\\")
            else:
                parts.append(c)
        return '"' + "".join(parts) + '"'
    if lang == "python":
        parts = []
        for c in s:
            o = ord(c)
            if o < 32 or o == 127 or o > 127:
                parts.append(f"\\x{o:02x}")
            elif c == '"':
                parts.append('\\"')
            elif c == "\\":
                parts.append("\\\\")
            else:
                parts.append(c)
        return '"' + "".join(parts) + '"'
    if lang == "lua":
        parts = []
        for c in s:
            o = ord(c)
            if o < 32 or o == 127 or o > 127:
                parts.append(f"\\{o}")
            elif c == '"':
                parts.append('\\"')
            elif c == "\\":
                parts.append("\\\\")
            else:
                parts.append(c)
        return '"' + "".join(parts) + '"'
    raise ValueError(f"Unknown lang: {lang}")


def _lua_byte_range(fr: int, to: int) -> str:
    """Build a Lua string from a byte range, chunked to avoid register limits."""
    count = to - fr + 1
    if count <= 200:
        args = ", ".join(str(i) for i in range(fr, to + 1))
        return f"string.char({args})"
    # Build in chunks of 200
    chunks = []
    for start in range(fr, to + 1, 200):
        end = min(start + 199, to)
        args = ", ".join(str(i) for i in range(start, end + 1))
        chunks.append(f"string.char({args})")
    return " .. ".join(chunks)


def _lua_bytes_list(vals: list[int]) -> str:
    """Build a Lua string from a byte list, chunked to avoid register limits."""
    if len(vals) <= 200:
        args = ", ".join(str(v) for v in vals)
        return f"string.char({args})"
    chunks = []
    for i in range(0, len(vals), 200):
        chunk = vals[i:i+200]
        args = ", ".join(str(v) for v in chunk)
        chunks.append(f"string.char({args})")
    return " .. ".join(chunks)


def render_typed_input(val: dict, lang: str) -> str:
    """Render a typed input object like {type: byte, value: N}."""
    t = val["type"]

    if t == "byte":
        n = val["value"]
        if lang == "js":
            return f"String.fromCharCode({n})"
        if lang == "ruby":
            return f"{n}.chr"
        if lang == "python":
            return f"chr({n})"
        if lang == "lua":
            return f"string.char({n})"

    if t == "bytes":
        vals = val["values"]
        if lang == "js":
            args = ", ".join(str(v) for v in vals)
            return f"[{args}].map(b => String.fromCharCode(b)).join('')"
        if lang == "ruby":
            args = ", ".join(str(v) for v in vals)
            return f"[{args}].pack('C*')"
        if lang == "python":
            # For ace_serializer, bytes are strings (chr). For lib_serialize, they're bytes.
            args = ", ".join(str(v) for v in vals)
            return f"''.join(chr(b) for b in [{args}])"
        if lang == "lua":
            return _lua_bytes_list(vals)

    if t == "byte_range":
        fr, to = val["from"], val["to"]
        if lang == "js":
            return f"Array.from({{ length: {to - fr + 1} }}, (_, i) => String.fromCharCode(i + {fr})).join('')"
        if lang == "ruby":
            return f"({fr}..{to}).map(&:chr).join"
        if lang == "python":
            return f"''.join(chr(i) for i in range({fr}, {to + 1}))"
        if lang == "lua":
            return _lua_byte_range(fr, to)

    if t == "infinity":
        return {"js": "Infinity", "ruby": "Float::INFINITY", "python": "math.inf", "lua": "math.huge"}[lang]

    if t == "neg_infinity":
        return {"js": "-Infinity", "ruby": "-Float::INFINITY", "python": "-math.inf", "lua": "-math.huge"}[lang]

    if t == "repeated":
        value = val["value"]
        count = val["count"]
        s_val = render_string(value, lang)
        if lang == "js":
            return f"{s_val}.repeat({count})"
        if lang == "ruby":
            return f"{s_val} * {count}"
        if lang == "python":
            return f"{s_val} * {count}"
        if lang == "lua":
            return f"string.rep({s_val}, {count})"

    raise ValueError(f"Unknown typed input: {t}")


def render_typed_input_bytes(val: dict, lang: str) -> str:
    """Render typed input as bytes (for lua_deflate and lib_serialize which use byte APIs)."""
    t = val["type"]

    if t == "byte":
        n = val["value"]
        if lang == "js":
            return f"String.fromCharCode({n})"
        if lang == "ruby":
            return f"{n}.chr.force_encoding('BINARY')"
        if lang == "python":
            return f"bytes([{n}])"
        if lang == "lua":
            return f"string.char({n})"

    if t == "bytes":
        vals = val["values"]
        if lang == "js":
            args = ", ".join(str(v) for v in vals)
            return f"[{args}].map(b => String.fromCharCode(b)).join('')"
        if lang == "ruby":
            args = ", ".join(str(v) for v in vals)
            return f"[{args}].pack('C*')"
        if lang == "python":
            args = ", ".join(str(v) for v in vals)
            return f"bytes([{args}])"
        if lang == "lua":
            return _lua_bytes_list(vals)

    if t == "byte_range":
        fr, to = val["from"], val["to"]
        if lang == "js":
            return f"Array.from({{ length: {to - fr + 1} }}, (_, i) => String.fromCharCode(i + {fr})).join('')"
        if lang == "ruby":
            return f"({fr}..{to}).map(&:chr).join.force_encoding('BINARY')"
        if lang == "python":
            return f"bytes(range({fr}, {to + 1}))"
        if lang == "lua":
            return _lua_byte_range(fr, to)

    if t == "repeated":
        value = val["value"]
        count = val["count"]
        if lang == "js":
            return f"{render_string(value, lang)}.repeat({count})"
        if lang == "ruby":
            return f"({render_string(value, lang)} * {count}).force_encoding('BINARY')"
        if lang == "python":
            return f"({render_string(value, lang)} * {count}).encode('latin-1')" if any(ord(c) > 127 for c in value) else f"{render_string(value, lang)}.encode() * {count}"
        if lang == "lua":
            return f"string.rep({render_string(value, lang)}, {count})"

    if t == "infinity":
        return {"js": "Infinity", "ruby": "Float::INFINITY", "python": "math.inf", "lua": "math.huge"}[lang]

    if t == "neg_infinity":
        return {"js": "-Infinity", "ruby": "-Float::INFINITY", "python": "-math.inf", "lua": "-math.huge"}[lang]

    raise ValueError(f"Unknown typed input for bytes: {t}")


def render_input(val, lang: str, module: str = "ace_serializer") -> str:
    """Render any input value for a specific language and module context."""
    if isinstance(val, dict) and "type" in val:
        if module in ("lua_deflate", "lib_serialize"):
            return render_typed_input_bytes(val, lang)
        return render_typed_input(val, lang)
    if isinstance(val, dict):
        return render_table(val, lang, module)
    if isinstance(val, list):
        return render_array(val, lang, module)
    if isinstance(val, str) and module in ("lua_deflate",):
        # lua_deflate inputs are byte strings
        if lang == "python":
            return f"b{render_string(val, lang)}"
        return render_string(val, lang)
    return render_value(val, lang, module)


def render_expected(val, lang: str, module: str = "ace_serializer") -> str:
    """Render expected value, same as render_input but for expected context."""
    if isinstance(val, str) and module in ("lua_deflate",):
        if lang == "python":
            return f"b{render_string(val, lang)}"
        return render_string(val, lang)
    return render_input(val, lang, module)


def render_wire(val: str, lang: str) -> str:
    """Render a wire string, preserving actual control characters."""
    return _render_string_with_escapes(val, lang) if any(ord(c) < 32 or ord(c) > 126 for c in val) else render_string(val, lang)


def render_table(val: dict, lang: str, module: str = "ace_serializer") -> str:
    """Render a dict/table literal for a given language."""
    if lang == "js":
        pairs = []
        for k, v in val.items():
            rk = _render_js_key(k, module)
            rv = render_input(v, lang, module) if not isinstance(v, dict) or "type" in v else render_table(v, lang, module)
            pairs.append(f"{rk}: {rv}")
        return "{ " + ", ".join(pairs) + " }"
    if lang == "ruby":
        pairs = []
        for k, v in val.items():
            rk = render_ruby_key(k, module)
            rv = render_input(v, lang, module) if not isinstance(v, dict) or "type" in v else render_table(v, lang, module)
            pairs.append(f"{rk} => {rv}")
        return "{ " + ", ".join(pairs) + " }"
    if lang == "python":
        pairs = []
        for k, v in val.items():
            rk = render_python_key(k)
            rv = render_input(v, lang, module) if not isinstance(v, dict) or "type" in v else render_table(v, lang, module)
            pairs.append(f"{rk}: {rv}")
        return "{ " + ", ".join(pairs) + " }"
    if lang == "lua":
        pairs = []
        for k, v in val.items():
            rk = render_lua_key(k)
            rv = render_input(v, lang, module) if not isinstance(v, dict) or "type" in v else render_table(v, lang, module)
            pairs.append(f"[{rk}] = {rv}")
        return "{ " + ", ".join(pairs) + " }"
    raise ValueError(f"Unknown lang: {lang}")


def _render_js_key(k: str, module: str = "ace_serializer") -> str:
    """Render a JS object key, using numeric keys for integer strings."""
    try:
        n = int(k)
        return str(n)
    except ValueError:
        if module == "lib_serialize":
            try:
                f = float(k)
                return str(f)
            except ValueError:
                pass
        if re.match(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$', k):
            return k
        return f"'{k}'"


def render_ruby_key(k: str, module: str = "ace_serializer") -> str:
    try:
        n = int(k)
        return str(n)
    except ValueError:
        if k in ("true", "false"):
            return k
        if module == "lib_serialize":
            try:
                f = float(k)
                return str(f)
            except ValueError:
                pass
        return f"'{k}'"


def render_python_key(k: str) -> str:
    try:
        n = int(k)
        return str(n)
    except ValueError:
        if k == "true":
            return "True"
        if k == "false":
            return "False"
        try:
            f = float(k)
            return str(f)
        except ValueError:
            return f"'{k}'"


def render_lua_key(k: str) -> str:
    try:
        n = int(k)
        return str(n)
    except ValueError:
        if k in ("true", "false"):
            return k
        try:
            f = float(k)
            return str(f)
        except ValueError:
            return f'"{k}"'


def render_check_key_access(obj_var: str, key: str, lang: str) -> str:
    """Render access to a check_key on a result object."""
    try:
        n = int(key)
        if lang == "js":
            return f"{obj_var}[{n}]"
        if lang == "ruby":
            return f"{obj_var}[{n}]"
        if lang == "python":
            return f"{obj_var}[{n}]"
        if lang == "lua":
            return f"{obj_var}[{n}]"
    except ValueError:
        pass
    if key in ("true", "false"):
        if lang == "lua":
            return f"{obj_var}[{key}]"
        if lang == "python":
            return f"{obj_var}[{key.capitalize()}]"
        return f"{obj_var}[{key}]"
    try:
        f = float(key)
        if lang == "js":
            return f"{obj_var}[{f}]"
        if lang == "ruby":
            return f"{obj_var}[{f}]"
        if lang == "python":
            return f"{obj_var}[{f}]"
        if lang == "lua":
            return f"{obj_var}[{f}]"
    except ValueError:
        pass
    if lang == "js":
        return f"{obj_var}['{key}']"
    if lang == "ruby":
        return f"{obj_var}['{key}']"
    if lang == "python":
        return f"{obj_var}['{key}']"
    if lang == "lua":
        return f'{obj_var}["{key}"]'


def _is_sequential_int_keys(val: dict) -> bool:
    """Check if dict has sequential 1-based integer keys."""
    if not isinstance(val, dict):
        return False
    try:
        keys = sorted(int(k) for k in val.keys())
    except (ValueError, TypeError):
        return False
    return len(keys) > 0 and keys == list(range(1, len(keys) + 1))


def _convert_to_js_array(val, module: str = "ace_serializer") -> any:
    """Recursively convert sequential 1-based int-keyed dicts to lists for JS."""
    if isinstance(val, dict) and "type" not in val:
        # Recurse into values first
        converted = {k: _convert_to_js_array(v, module) for k, v in val.items()}
        if _is_sequential_int_keys(converted):
            keys = sorted(converted.keys(), key=lambda k: int(k))
            return [converted[k] for k in keys]
        return converted
    if isinstance(val, list):
        return [_convert_to_js_array(v, module) for v in val]
    return val


def render_js_expected(val, module: str = "ace_serializer") -> str:
    """Render expected value for JS, converting int-keyed dicts to arrays."""
    converted = _convert_to_js_array(val, module)
    return render_input(converted, "js", module)


def make_python_name(test_id: str, desc: str) -> str:
    """Create a valid Python function name from test ID and description."""
    return f"it_{test_id}_{snake_case(desc)}"


def main():
    with open(YAML_PATH) as f:
        data = yaml.safe_load(f)

    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(TEMPLATE_DIR)),
        keep_trailing_newline=True,
        trim_blocks=True,
        lstrip_blocks=True,
    )

    # Register custom tests
    env.tests["real_float"] = lambda val: isinstance(val, float) and not isinstance(val, bool)

    # Register filters and globals
    env.filters["snake_case"] = snake_case
    env.filters["js_escape"] = lambda s: s.replace("\\", "\\\\").replace("'", "\\'")
    env.filters["lua_escape"] = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    env.globals["render_input"] = render_input
    env.globals["render_expected"] = render_expected
    env.globals["render_wire"] = render_wire
    env.globals["render_value"] = render_value
    env.globals["render_table"] = render_table
    env.globals["render_check_key_access"] = render_check_key_access
    env.globals["render_typed_input"] = render_typed_input
    env.globals["render_typed_input_bytes"] = render_typed_input_bytes
    env.globals["render_string"] = render_string
    env.globals["group_by_section"] = group_by_section
    env.globals["make_python_name"] = make_python_name
    env.globals["render_lua_key"] = render_lua_key
    env.globals["render_ruby_key"] = render_ruby_key
    env.globals["render_python_key"] = render_python_key
    env.globals["render_js_expected"] = render_js_expected

    modules = ["ace_serializer", "lua_deflate", "lib_serialize", "cbor", "pipeline"]
    langs = ["js", "ruby", "python", "lua"]

    for module in modules:
        tests = data.get(module, [])
        if not tests:
            print(f"  SKIP {module}: no tests found in YAML", file=sys.stderr)
            continue

        sections = group_by_section(tests)

        for lang in langs:
            template_path = f"{module}.{lang}.j2"
            try:
                tmpl = env.get_template(template_path)
            except jinja2.TemplateNotFound:
                print(f"  SKIP {module}.{lang}: template not found", file=sys.stderr)
                continue

            output = tmpl.render(
                tests=tests,
                sections=sections,
                module=module,
                lang=lang,
            )

            out_path = OUTPUT_MAP[module].get(lang)
            if out_path is None:
                continue
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(output)
            print(f"  wrote {out_path.relative_to(ROOT)}")

    print("Done.")


if __name__ == "__main__":
    main()
