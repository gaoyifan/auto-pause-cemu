.PHONY: build test install uninstall clean

build:
	swift build -c release

test:
	swift test

install: build
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

clean:
	swift package clean
