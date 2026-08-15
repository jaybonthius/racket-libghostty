SHELL := /bin/bash

.PHONY: native link test lint fmt docs clean

PACKAGE_NAMES := libghostty-x86_64-linux libghostty libghostty-browser-terminal
RKT_FILES := $(shell find libghostty examples/browser-terminal -name '*.rkt' -not -path '*/compiled/*' 2>/dev/null)

native:
	bin/build-linux-x86-64.sh

link:
	raco pkg install --auto --link --skip-installed --name libghostty-x86_64-linux $(CURDIR)/libghostty-x86_64-linux
	raco pkg install --auto --link --skip-installed --name libghostty $(CURDIR)/libghostty
	raco pkg install --auto --link --skip-installed --name libghostty-browser-terminal $(CURDIR)/examples/browser-terminal
	raco setup --no-docs --pkgs $(PACKAGE_NAMES)

test:
	raco test libghostty/tests/ examples/browser-terminal/tests/

lint:
	@for f in $(RKT_FILES); do raco review $$f; done

fmt:
	@for f in $(RKT_FILES); do raco fmt -i $$f; done

docs:
	mkdir -p .build/docs
	scribble --htmls ++xref-in setup/xref load-collections-xref --dest .build/docs libghostty/scribblings/libghostty.scrbl

clean:
	rm -rf .build/docs
