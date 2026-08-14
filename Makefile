.PHONY: link lint fmt resyntax

PACKAGE_NAMES := libghostty
PACKAGE_DIRS := \
	$(CURDIR)/libghostty

RKT_FILES := $(shell find . -name '*.rkt' -not -path './.git/*' 2>/dev/null)

link:
	raco pkg update --link --no-setup $(PACKAGE_DIRS)
	raco setup --no-zo --no-docs --pkgs $(PACKAGE_NAMES)

lint:
	@for f in $(RKT_FILES); do raco review $$f; done

fmt:
	@for f in $(RKT_FILES); do raco fmt -i $$f; done

resyntax:
	@for f in $(RKT_FILES); do resyntax fix --file $$f; done
