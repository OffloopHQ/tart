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

## 2026-09-04 macOS guest benchmark

The exact fork commit `6023c21789ef49836745e66eda8b04e837fccb7b` was built
and ad-hoc signed on a `Mac16,11` host running macOS `26.6.2` (`25G83`) with
64 GiB RAM. `MemoryBalloonTests` passed 7/7. The guest was the production-pinned
Tahoe/Xcode OCI digest
`sha256:61f6e857a3d65dd2f8daf9c51c7b837fa458bcc9181ae8556e645b534dab6bf6`,
configured for 4 vCPU and 8 GiB RAM.

| Case | Guest result after 45 seconds | Host Tart RSS |
| --- | --- | --- |
| control, no balloon | SSH healthy; `hw.memsize=8589934592`; memory free 86% | 47,024 KiB |
| fixed target 6,144 MiB | SSH initially healthy, then SSH banner timeout | 46,928 KiB |
| fixed target 4,096 MiB | SSH initially healthy, then SSH banner timeout | 47,024 KiB |

Both target runs logged the requested target, but neither produced measurable
host RSS reduction and both made the macOS guest unavailable. Every benchmark
VM was stopped and deleted; the host retained only its production OCI source
image. The dynamic controller is therefore **not approved for release**: a host
warning or critical pressure event would apply the same unsafe target. Revisit
only after a newer macOS guest or Virtualization.framework release provides a
measurable reclaim receipt without guest availability loss.
