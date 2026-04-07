PYTHON := uv run

.PHONY: test test-js test-ruby test-python test-lua install install-js install-ruby install-python install-lua generate-tests

test: test-js test-ruby test-python test-lua

test-js:
	node --test 'js/test/**/*.test.js'

test-ruby:
	cd ruby && bundle exec rspec spec/

test-python:
	cd python && uv run --extra test pytest tests/ -v

test-lua:
	cd lua && busted test/ --verbose

install: install-js install-ruby install-python install-lua

install-js:
	cd js && npm install

install-ruby:
	cd ruby && bundle install

install-python:
	cd python && uv sync --extra test

install-lua:
	./lua/fetch-deps.sh

generate-tests:
	cd testing && uv run generate-tests.py
