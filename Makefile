.PHONY: test build clean patch-build build-original

test:
	@bash httpstat_test.sh

clean:
	rm -rf build dist *.egg-info

build: patch-build

patch-build:
	@echo "Creating temporary patched version..."
	@mkdir -p patch-build
	@cp httpstat.py patch-build/
	@cp setup.py patch-build/
	@cp README.md patch-build/
	@cp LICENSE patch-build/
	@cd patch-build && patch -p1 < ../httpstat-append-json.patch
	@echo "Building from patched version..."
	@cd patch-build && python setup.py build
	@echo "Build complete, original files unchanged"

build-original:
	python setup.py build

build-dist:
	python setup.py sdist bdist_wheel

build-dist-patched:
	@echo "Creating patched distribution..."
	@mkdir -p patch-build
	@cp httpstat.py patch-build/
	@cp setup.py patch-build/
	@cp README.md patch-build/
	@cp LICENSE patch-build/
	@cd patch-build && patch -p1 < ../httpstat-append-json.patch
	@cd patch-build && python setup.py sdist bdist_wheel
	@cp patch-build/dist/* dist/ 2>/dev/null || mkdir -p dist && cp build/dist/* dist/
	@echo "Patched distribution ready in dist/"

publish: clean build-dist-patched
	python -m twine upload dist/*
