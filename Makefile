build:
	./Scripts/build-app.sh

run: build
	open build/UmamiBar.app

preview: build
	open -n build/UmamiBar.app --args --demo

test:
	env CLANG_MODULE_CACHE_PATH="$(CURDIR)/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/.build/ModuleCache" swift test --disable-sandbox --cache-path "$(CURDIR)/.build/PackageCache"

clean:
	rm -rf .build build

.PHONY: build run preview test clean
