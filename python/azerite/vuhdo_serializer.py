"""
VuhDo custom serializer — decode/encode VuhDo's type-length-value format.

Wire format:
  Keys:   N<digits>=   (numeric key)
          S<string>=   (string key, may use abbreviations)
  Values: S<len>+<string>, N<len>+<number>, T<len>+<nested>, 1/0 booleans
"""

ABBREV_TO_KEY = {
    '*a': 'isFullDuration',
    '*b': 'useBackground',
    '*c': 'color',
    '*d': 'isStacks',
    '*e': 'isIcon',
    '*f': 'isColor',
    '*g': 'bright',
    '*h': 'others',
    '*i': 'icon',
    '*j': 'timer',
    '*k': 'animate',
    '*l': 'isClock',
    '*m': 'mine',
    '*n': 'name',
    '*o': 'useOpacity',
    '*p': 'countdownMode',
    '*r': 'radio',
    '*s': 'isManuallySet',
    '*t': 'useText',
    '*u': 'custom',
}

KEY_TO_ABBREV = {v: k for k, v in ABBREV_TO_KEY.items()}


def _read_length_value(s: str, pos: int) -> tuple[int, str | None]:
    plus = s.find('+', pos + 1)
    if plus == -1:
        return (len(s), None)
    length = int(s[pos + 1:plus])
    value = s[plus + 1:plus + 1 + length]
    return (plus + 1 + length, value)


def deserialize(s: str) -> dict:
    table: dict = {}
    i = 0

    while i < len(s):
        eq = s.find('=', i + 1)
        if eq == -1:
            break

        key_type = s[i]
        key_raw = s[i + 1:eq]
        key: int | str = int(key_raw) if key_type == 'N' else (ABBREV_TO_KEY.get(key_raw, key_raw))

        vt = s[eq + 1] if eq + 1 < len(s) else None

        if vt == 'S':
            i, value = _read_length_value(s, eq + 1)
        elif vt == 'N':
            i, raw = _read_length_value(s, eq + 1)
            if raw is None:
                break
            value = float(raw) if '.' in raw else int(raw)
        elif vt == 'T':
            i, raw = _read_length_value(s, eq + 1)
            if raw is None:
                break
            value = deserialize(raw)
        elif vt == '1':
            value = True
            i = eq + 2
        elif vt == '0':
            value = False
            i = eq + 2
        else:
            break

        if value is not None:
            table[key] = value

    return table


def serialize(table: dict) -> str:
    result = []

    for key, value in table.items():
        if isinstance(key, int):
            result.append(f'N{key}=')
        else:
            result.append(f'S{KEY_TO_ABBREV.get(key, key)}=')

        if isinstance(value, str):
            result.append(f'S{len(value)}+{value}')
        elif isinstance(value, bool):
            result.append('1' if value else '0')
        elif isinstance(value, (int, float)):
            s = f'{value:.4f}'
            result.append(f'N{len(s)}+{s}')
        elif isinstance(value, dict):
            nested = serialize(value)
            result.append(f'T{len(nested)}+{nested}')

    return ''.join(result)
