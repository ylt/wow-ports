PYTHON := uv run

.PHONY: test test-js test-ruby test-python install install-js install-ruby install-python

test: test-js test-ruby test-python test-lua

test-js:
	node --test 'js/test/**/*.test.js'

test-ruby:
	cd ruby && bundle exec rspec spec/

test-python:
	cd python && uv run --extra test pytest tests/ -v

test-lua:
	lua lua/test_ace_serializer.lua && lua lua/test_lua_deflate.lua && lua lua/test_lib_serialize.lua

install: install-js install-ruby install-python install-lua

install-js:
	cd js && npm install

install-ruby:
	cd ruby && bundle install

install-python:
	cd python && uv sync --extra test

install-lua:
	./lua/fetch-deps.sh
