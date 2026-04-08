.PHONY: test install typecheck lint

test:
	uv run --extra test pytest tests/ -v

install:
	uv sync --extra test

typecheck:
	uvx pyrefly check

lint:
	uvx ruff check azerite/
	uvx ruff format --check azerite/
