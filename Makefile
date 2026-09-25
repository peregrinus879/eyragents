# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.
# Stow runs without directory folding so every managed parent under $HOME stays
# a real directory and only leaf files are links.

SHELL := /bin/bash
PACKAGES := agents claude-code opencode
STOW := stow --no-folding --ignore='__pycache__' -t ~
TOOL_PACKAGES := claude-code opencode
# Each skill deploys as one directory link under ~/.agents/skills and
# ~/.claude/skills, so files added to a skill need no restow; Stow leaves those
# directories to scripts/prepare-stow.sh --link-skills.
AGENTS_STOW := $(STOW) --ignore='\.agents/skills'
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  $(filter-out %.py,$(wildcard agents/.agents/skills/*/scripts/*)) \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow require-clone check-skills lint test check verify-deploy verify canary clean refs workspace-guide

# Deployment goals and their guards must never race, including `make -j clean restow`.
.NOTPARALLEL:

help:
	@echo "Targets:"
	@echo "  stow           Clean dangling links, stow packages, link skill directories"
	@echo "  unstow         Remove all package links and the skill directory links"
	@echo "  dry-run        Preview Stow actions"
	@echo "  restow         Guard, preflight skills, clean, refresh links"
	@echo "  check-skills   Read-only preflight of every managed skill directory"
	@echo "  lint           ShellCheck and Python syntax checks over managed scripts"
	@echo "  test           Fast tests: configuration boundaries, bridges, statusline, preparation, canary fixtures"
	@echo "  check          Repository checks: links, JSON/TOML and fixture tests (runs in CI)"
	@echo "  verify-deploy  Check every package file resolves to its deployed target"
	@echo "  verify         lint, check, and verify-deploy"
	@echo "  canary         Up to six live calls per tool; behavioral smoke (not a gate)"
	@echo "  refs           Refresh existing clones declared by this repository (preview with scripts/update-references.sh --dry-run)"
	@echo "  workspace-guide Rebuild the full offline workspace and AI-client guide for both hosts"
	@echo "  clean          Remove dangling links that point into this repository's packages"

stow: clean
	$(STOW) -v $(TOOL_PACKAGES)
	$(AGENTS_STOW) -v agents
	bash scripts/prepare-stow.sh --link-skills

unstow: require-clone check-skills
	$(STOW) -D -v $(TOOL_PACKAGES)
	$(AGENTS_STOW) -D -v agents
	bash scripts/prepare-stow.sh --unlink-skills

dry-run:
	$(STOW) -n -v $(TOOL_PACKAGES)
	$(AGENTS_STOW) -n -v agents

restow: clean
	$(STOW) -R -v $(TOOL_PACKAGES)
	$(AGENTS_STOW) -R -v agents
	bash scripts/prepare-stow.sh --link-skills

# A managed endpoint that is a link must resolve into this clone; a reference
# clone of the same repository must never redeploy the packages from itself.
require-clone:
	@bash scripts/prepare-stow.sh --require-clone

check-skills: require-clone
	@bash scripts/prepare-stow.sh --check-skills

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	python3 -I -c 'import sys; [compile(open(p, "rb").read(), p, "exec") for p in sys.argv[1:]]' \
	  scripts/update-references.py tests/reference-migration.py tests/config-contracts.py docs/workspace-guide-src/build.py \
	  agents/.agents/skills/spar/scripts/spar-supervise.py
	@echo "ok:   lint"

test:
	python3 tests/config-contracts.py
	bash tests/mise-env.sh
	bash tests/update-references.sh
	python3 tests/reference-migration.py
	bash tests/statusline.sh
	bash tests/prepare-stow.sh
	bash tests/spar-bridges.sh
	bash tests/canary.sh
	@echo "ok:   test"

check:
	python3 docs/workspace-guide-src/build.py --check
	@fail=0; \
	while IFS= read -r -d '' link; do \
	  echo "FAIL: package symlink does not resolve: $$link"; fail=1; \
	done < <(find $(PACKAGES) .agents .claude -type l -xtype l -print0); \
	[[ $$fail -eq 0 ]] && echo "ok:   package and project symlinks resolve"; \
	while IFS= read -r -d '' f; do \
	  if [[ ! -e $$f ]]; then \
	    deleted=$$(git ls-files --deleted -- "$$f") || exit 1; \
	    [[ $$deleted == "$$f" ]] && continue; \
	  fi; \
	  case $$f in \
	    *.toml) python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$$f" ;; \
	    *) python3 -c 'import sys, json; json.load(open(sys.argv[1], encoding="utf-8"))' "$$f" ;; \
	  esac && echo "ok:   $$f parses" || { echo "FAIL: $$f does not parse"; fail=1; }; \
	done < <(git ls-files -z --cached --others --exclude-standard -- '*.json' '*.toml'); \
	exit $$fail
	@$(MAKE) --no-print-directory test
	@echo "ok:   check"

# Every non-ignored package file must resolve to the same inode as its
# deployed target, every package directory must be a real directory in $HOME,
# and a retired source must leave no link behind. GNU Stow ignores .gitignore
# files, so they are skipped.
verify-deploy:
	@fail=0; \
	while IFS= read -r -d '' src; do \
	  [[ "$$src" == */.gitignore ]] && continue; \
	  target="$$HOME/$${src#*/}"; \
	  if [[ ! -e $$src && ! -L $$src ]]; then \
	    if git diff --quiet -- "$$src"; then \
	      echo "FAIL: tracked package source is missing without a pending deletion: $$src"; fail=1; \
	    elif [[ -L $$target ]]; then \
	      echo "FAIL: retired package endpoint remains linked: $$target"; fail=1; \
	    elif [[ ! -e $$target ]]; then \
	      echo "ok:   retired package endpoint absent: $$target"; \
	    elif [[ -f $$target && -O $$target ]]; then \
	      echo "ok:   retired package endpoint is owner-controlled: $$target"; \
	    else \
	      echo "FAIL: retired package endpoint has an unsupported replacement: $$target"; fail=1; \
	    fi; \
	    continue; \
	  fi; \
	  if [[ $$(readlink -f -- "$$target") == "$$(readlink -f -- "$$src")" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done < <(git ls-files -z --cached --others --exclude-standard -- $(PACKAGES)); \
	while IFS= read -r dir; do \
	  target="$$HOME/$${dir#*/}"; \
	  case $$dir in \
	    agents/.agents/skills/*/*) continue ;; \
	    agents/.agents/skills/*) \
	      for link in "$$target" "$$HOME/.claude/skills/$${dir##*/}"; do \
	        if [[ -L $$link && $$(readlink -f -- "$$link") == "$(CURDIR)/$$dir" ]]; then echo "ok:   skill directory link resolves into the repo: $$link"; \
	        else echo "FAIL: skill directory is not one link into the repo (run make restow): $$link"; fail=1; fi; \
	      done ;; \
	    *) if [[ -d $$target && ! -L $$target ]]; then :; \
	       else echo "FAIL: managed directory is folded or missing: $$target"; fail=1; fi ;; \
	  esac; \
	done < <(git ls-files --cached --others --exclude-standard -- $(PACKAGES) | \
	  while IFS= read -r src; do [[ -e $$src || -L $$src ]] || continue; dir=$${src%/*}; \
	  while [[ $$dir == */* ]]; do echo "$$dir"; dir=$${dir%/*}; done; done | sort -u); \
	for path in package.json package-lock.json bun.lock bun.lockb node_modules; do \
	  target="opencode/.config/opencode/$$path"; \
	  if [[ ! -e $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: generated OpenCode state reached the package source: $$target"; fail=1; fi; \
	done; \
	for b in spar-claude spar-opencode spar-supervise.py; do \
	  if [[ -x "$$HOME/.agents/skills/spar/scripts/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	exit $$fail

verify: lint check verify-deploy
	@echo "ok:   verify"

# Live behavior of the deployed tools: up to six model calls per tool from a
# throwaway repository. Run after make restow.
canary:
	bash scripts/canary.sh

refs:
	bash scripts/update-references.sh

workspace-guide:
	python3 docs/workspace-guide-src/build.py

clean: check-skills
	bash scripts/prepare-stow.sh
