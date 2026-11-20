# Contributing

Thanks for helping improve `roc-elm-tui`.

For local work, use any recent `roc` on `PATH`, or download the latest archive for your operating system from the [`roc-lang/nightlies` releases](https://github.com/roc-lang/nightlies/releases/latest).

## Building the platform host

Build for the native target:

```sh
./scripts/build.py
```

Cross-compile for a specific target:

```sh
./scripts/build.py --target x64musl
```

Build all Unix targets at once:

```sh
./scripts/build.py --all
```

The Windows host (`x64win`) must be built on Windows. For Linux musl targets, [Zig](https://ziglang.org/) must be on `PATH`; `scripts/build.py` uses `ci/zig-cc.sh` and `ci/zig-ar.sh` as C-compiler and archiver shims.

After building, run an example to verify:

```sh
roc run examples/elm-example.roc
```

## Updating Roc glue

The Rust host ABI is generated from `platform/main.roc` using Roc's `RustGlue.roc` generator.

Regenerate:

```sh
./ci/regenerate_glue.sh
```

Check that the committed glue matches what would be generated:

```sh
./ci/regenerate_glue.sh --check
```

The script defaults to a sibling `../roc` checkout. Override when needed:

```sh
ROC=../roc/zig-out/bin/roc ROC_SRC=../roc ./ci/regenerate_glue.sh
```

Commit `src/roc_platform_abi.rs` with any platform API change and the matching `src/lib.rs` updates. Do not edit generated glue by hand.

After regenerating, run `cargo check` to verify the Rust host still compiles.
