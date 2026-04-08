import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strict,
  {
    files: ["lib/**/*.ts", "test/**/*.ts", "index.ts"],
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_" },
      ],
      // Static-only classes are the pattern for serializers (WowAceSerializer, WowCbor, etc.)
      "@typescript-eslint/no-extraneous-class": "off",
      // Non-null assertions are used deliberately in typed serialization code
      "@typescript-eslint/no-non-null-assertion": "off",
      // Control characters in regex are intentional (NUL byte handling in AceSerializer)
      "no-control-regex": "off",
    },
  },
  {
    ignores: ["dist/"],
  },
);
