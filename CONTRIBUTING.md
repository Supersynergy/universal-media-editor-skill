# Contributing

Thanks! Most-wanted contributions:

1. **New recipe files** — share your pipelines (`recipes/yourstyle.recipe`)
2. **Benchmarks on your Mac** — how fast does `me_polish` run on M1/M2/Ultra/Intel?
3. **New primitives** — wrap a best-in-class tool we missed
4. **Easter eggs** — jokes, zen koans

## Before a PR

```bash
brew install shellcheck
shellcheck media-edit.sh install.sh uninstall.sh
source media-edit.sh && me_info && me_help
```

## Style

POSIX-ish bash. Quote everything. `find -print0 | xargs -0` for filenames. No mandatory deps without a benchmark.
