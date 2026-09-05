# Offloop fork policy

`main` follows `openai/tart`. Offloop production patches live on versioned
`offloop/*` branches and remain pinned to an exact upstream release and commit.

`offloop/2.36-macos-memory-balloon` evaluates Virtualization.framework memory
ballooning for managed macOS CI guests. The configured guest memory remains the
upper bound. `--dynamic-memory` requests the full allocation at normal host
pressure, 75% at warning pressure, and the restore-image minimum at critical
pressure. The target is re-applied after guest device resets.

`--balloon-target-memory-sequence` with
`--balloon-target-interval-seconds` is a validation-only control. It changes
targets on one running VM so a benchmark can measure shrink and expansion
without creating system-wide host memory pressure.

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

## 2026-09-05 16 GiB shrink-and-restore benchmark

The validation sequence in commit `a9b0162adf2b4c66fb95c7057ff864fdfad989b1`
was exercised on the same `Mac16,11` host and pinned Tahoe/Xcode guest, now
configured for 4 vCPU and 16 GiB RAM. `MemoryBalloonTests` passed 8/8. The VM
remained running while Tart applied `16384 -> 12288 -> 8192 -> 16384` MiB at
60-second intervals.

| Requested target | Guest result | Host Tart RSS / footprint |
| --- | --- | --- |
| 16,384 MiB baseline | SSH healthy; `hw.memsize=17179869184`; memory free 94% | 47,280 KiB / 14.0 MiB |
| 12,288 MiB | SSH banner timed out | 47,312 KiB / 14.0 MiB |
| 8,192 MiB | SSH connection timed out | 47,328 KiB / 14.0 MiB |
| 16,384 MiB restored | SSH still timed out after the target change and a further 32-second settle | 47,296-47,344 KiB / 14.0 MiB |

Host memory pressure reported 96% free before and after the run. Tart process
RSS is not a complete accounting of Virtualization.framework guest memory, but
neither it nor the available host-wide pressure sample provides a reclaim
receipt for either shrink target. More importantly, the first 4 GiB shrink made
the guest unavailable and restoring the configured upper bound did not recover
it. The benchmark VM was then stopped and deleted, leaving only the pinned OCI
source image.

The 16 GiB maximum therefore does not make this controller safe. Do not deploy
this branch to managed macOS CI runners. A future experiment needs a guest or
framework version that both cooperates with the balloon device and exposes
host-side reclaim evidence while continuous guest health probes remain green.

## 2026-09-05 root cause and replacement

The Tahoe guest does load one active `AppleVirtIOBalloon` from
`com.apple.driver.AppleVirtIO`. The failure is a page-accounting mismatch:
Virtio balloon PFNs use fixed 4 KiB units, while the arm64 macOS guest uses 16
KiB VM pages. With a 16 GiB guest, a 15 GiB framework target increased guest
wired pages from 60,893 to 339,403, about 4.25 GiB. Repeating the same target
was idempotent, confirming that the four-times inflation is not caused by
Tart's 15-second reapplication.

A delayed one-shot 12 GiB target still made the guest unreachable within 15
seconds after two minutes of stable uptime. Restoring the framework target to
16 GiB did not deflate the balloon. Guest memory pressure produced compression
and swap while balloon wired pages stayed allocated. Calibrating a desired 4
GiB guest reclaim to a 1 GiB framework request therefore costs the guest about
4 GiB while returning only about the requested 1 GiB to the host. The current
Apple driver cannot provide efficient, reversible macOS overcommit.

The validated replacement keeps the checksum-pinned upstream Tart 2.35.0
binary. On the 64 GiB McIntosh host, two concurrent official Tart guests were
configured with 16 GiB each while a bounded allocator touched another 24 GiB.
macOS host compression absorbed the overlap without increasing swap. Both
guests retained authenticated SSH and independently completed the repository
Xcode canary by booting an iPhone 17 Pro Simulator. Cleanup left only the
pinned OCI source image.

Do not compensate or release this balloon branch. Use host-owned compression
and paging with two ephemeral 16 GiB guests on hosts with at least 64 GiB;
smaller hosts retain the 8 GiB baseline.

## 2026-09-05 aggregate overcommit validation

Virtualization.framework on the same 64 GiB host exposes the private selectors
`_memoryOvercommitmentAllowed`, `_terminationUnderMemoryPressureEnabled`, and
`_maximumAllowedOvercommittedMemorySize`. The public per-VM maximum was 64 GiB
and the private reported maximum was 1,030,400 MiB. A fork experiment could set
and read back both private booleans, and a 66 GiB configuration then passed
validation instead of being rejected by `maximumAllowedMemorySize`. It still
failed to start with `VZErrorDomain Code=1`. A 40 GiB VM also failed to start
when the same private settings were enabled. Passing configuration validation
is therefore not a runtime overcommit receipt, and the private settings are not
part of the Offloop fork.

The useful behavior is already present without either private setting or a
balloon. Checksum-pinned upstream Tart 2.35.0 started two ordinary Tahoe/Xcode
guests configured for 40 GiB each on the 64 GiB host, for an 80 GiB aggregate
configured maximum. Both guests reported the full 40 GiB through `hw.memsize`,
retained authenticated SSH, and concurrently booted and deleted an iPhone 17
Pro Simulator with Xcode 26.5.

At idle, the two Apple Virtualization helper processes had physical footprints
of 21,772,305,408 and 21,976,024,376 bytes, well below their configured maxima.
After both Simulator canaries completed, their physical footprints had grown
to 35,941,505,648 and 36,076,984,992 bytes while resident memory was only
14,504,951,808 and 14,468,464,640 bytes. The host compressor held 1,536,040
16-KiB pages, about 23.44 GiB. Swap remained 12.19 MiB and the host's cumulative
swapout count remained 3,339. Both guests still reported 94% free memory. Every
test VM was stopped and deleted, leaving only the pinned OCI source image.

This is the supported overcommit boundary for Offloop: multiple fixed-maximum
VMs may have aggregate configured memory above host physical memory while
macOS accounts, compresses, and pages their actual resident working sets. It
does not provide a hard per-VM current-memory value or a host-triggered page
reclaim receipt. Keep the 16 GiB per-job maximum and the two-job concurrency
limit on 64 GiB production hosts; measured working-set overlap, host pressure,
and workload health remain the admission evidence.
