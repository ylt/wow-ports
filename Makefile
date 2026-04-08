.PHONY: test test-js test-ruby test-python test-lua \
       install install-js install-ruby install-python install-lua \
       typecheck typecheck-ts typecheck-ruby typecheck-python \
       lint lint-ts lint-ruby lint-python \
       generate-tests

test: test-js test-ruby test-python test-lua
install: install-js install-ruby install-python install-lua
typecheck: typecheck-ts typecheck-ruby typecheck-python
lint: lint-ts lint-ruby lint-python

test-js:
	$(MAKE) -C js test

test-ruby:
	$(MAKE) -C ruby test

test-python:
	$(MAKE) -C python test

test-lua:
	cd lua && busted test/ --verbose

install-js:
	$(MAKE) -C js install

install-ruby:
	$(MAKE) -C ruby install

install-python:
	$(MAKE) -C python install

install-lua:
	./lua/fetch-deps.sh

typecheck-ts:
	$(MAKE) -C js typecheck

typecheck-ruby:
	$(MAKE) -C ruby typecheck

typecheck-python:
	$(MAKE) -C python typecheck

lint-ts:
	$(MAKE) -C js lint

lint-ruby:
	$(MAKE) -C ruby lint

lint-python:
	$(MAKE) -C python lint

generate-tests:
	cd testing && uv run generate-tests.py
