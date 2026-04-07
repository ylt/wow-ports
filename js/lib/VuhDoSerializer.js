'use strict';

/**
 * VuhDo custom serializer — decode/encode VuhDo's type-length-value format.
 *
 * Wire format:
 *   Keys:   N<digits>=   (numeric key)
 *           S<string>=   (string key, may use abbreviations)
 *   Values: S<len>+<string>, N<len>+<number>, T<len>+<nested>, 1/0 booleans
 */

const ABBREV_TO_KEY = {
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
};

const KEY_TO_ABBREV = {};
for (const [k, v] of Object.entries(ABBREV_TO_KEY)) KEY_TO_ABBREV[v] = k;

function readLengthValue(str, pos) {
    const plus = str.indexOf('+', pos + 1);
    if (plus === -1) return [str.length, null];
    const len = parseInt(str.slice(pos + 1, plus), 10);
    const value = str.slice(plus + 1, plus + 1 + len);
    return [plus + 1 + len, value];
}

class VuhDoSerializer {
    static deserialize(str) {
        const table = {};
        let i = 0;

        while (i < str.length) {
            const eq = str.indexOf('=', i + 1);
            if (eq === -1) break;

            const keyType = str[i];
            const keyRaw = str.slice(i + 1, eq);
            const key = keyType === 'N'
                ? parseInt(keyRaw, 10)
                : (ABBREV_TO_KEY[keyRaw] || keyRaw);

            const vt = str[eq + 1];
            let value;

            switch (vt) {
                case 'S': {
                    const [next, v] = readLengthValue(str, eq + 1);
                    value = v;
                    i = next;
                    break;
                }
                case 'N': {
                    const [next, raw] = readLengthValue(str, eq + 1);
                    value = raw.includes('.') ? parseFloat(raw) : parseInt(raw, 10);
                    i = next;
                    break;
                }
                case 'T': {
                    const [next, raw] = readLengthValue(str, eq + 1);
                    value = VuhDoSerializer.deserialize(raw);
                    i = next;
                    break;
                }
                case '1':
                    value = true;
                    i = eq + 2;
                    break;
                case '0':
                    value = false;
                    i = eq + 2;
                    break;
                default:
                    return table;
            }

            if (key !== undefined && value !== undefined) {
                table[key] = value;
            }
        }

        return table;
    }

    static serialize(table) {
        let result = '';

        for (const [key, value] of Object.entries(table)) {
            const numKey = parseInt(key, 10);
            if (!isNaN(numKey) && String(numKey) === key) {
                result += `N${numKey}=`;
            } else {
                result += `S${KEY_TO_ABBREV[key] || key}=`;
            }

            if (typeof value === 'string') {
                result += `S${value.length}+${value}`;
            } else if (typeof value === 'number') {
                const s = value.toFixed(4);
                result += `N${s.length}+${s}`;
            } else if (value === true) {
                result += '1';
            } else if (value === false) {
                result += '0';
            } else if (typeof value === 'object' && value !== null) {
                const nested = VuhDoSerializer.serialize(value);
                result += `T${nested.length}+${nested}`;
            }
        }

        return result;
    }
}

module.exports = VuhDoSerializer;
