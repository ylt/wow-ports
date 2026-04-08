.PHONY: test install typecheck lint build

test:
	bun test

install:
	bun install

typecheck:
	bunx tsc --noEmit

lint:
	bunx eslint lib/ test/ index.ts
	bunx prettier --check 'lib/**/*.ts' 'test/**/*.ts' 'index.ts'

build:
	bunx tsc
