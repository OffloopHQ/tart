# Offloop fork policy

`main` follows `openai/tart`. Offloop production patches live on versioned
`offloop/*` branches and remain pinned to an exact upstream release and commit.

`offloop/2.36-macos-memory-balloon` evaluates Virtualization.framework memory
ballooning for managed macOS CI guests. The configured guest memory remains the
upper bound. `--dynamic-memory` requests the full allocation at normal host
pressure, 75% at warning pressure, and the restore-image minimum at critical
pressure. The target is re-applied after guest device resets.

This branch is experimental until a real macOS guest benchmark proves guest
cooperation and a measurable reduction in host physical footprint without CI
failure. It must not replace a production Tart binary based only on unit tests
or a successful Linux guest result.
