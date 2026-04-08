PYTHON := uv run

.PHONY: test test-js test-ruby test-python test-lua install install-js install-ruby install-python install-lua generate-tests typecheck typecheck-ts typecheck-ruby typecheck-python

test: test-js test-ruby test-python test-lua

test-js:
	cd js && bun test

test-ruby:
	cd ruby && bundle exec rspec spec/

test-python:
	cd python && uv run --extra test pytest tests/ -v

test-lua:
	cd lua && busted test/ --verbose

install: install-js install-ruby install-python install-lua

install-js:
	cd js && bun install

install-ruby:
	cd ruby && bundle install

install-python:
	cd python && uv sync --extra test

install-lua:
	./lua/fetch-deps.sh

generate-tests:
	cd testing && uv run generate-tests.py

typecheck: typecheck-ts typecheck-ruby typecheck-python

typecheck-ts:
	cd js && bunx tsc --noEmit

typecheck-ruby:
	cd ruby && bundle exec srb tc

typecheck-python:
	cd python && uvx pyrefly check
