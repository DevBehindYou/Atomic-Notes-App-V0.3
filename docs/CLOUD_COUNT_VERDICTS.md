# R19 Cloud Notes count verdicts

Cloud Notes checks only the live-note count, not note identities, versions or
contents. Equal counts must not claim "In sync", and unequal counts cannot prove
that one side is ahead or behind. A failed count also cannot establish that the
device is offline; server/auth failures can produce the same missing count.

Use "Counts match", "Fewer in cloud", "More in cloud" and "Check failed". The
successful count details explicitly say this check does not compare contents;
the failed check offers Check cloud again and confirms local notes remain.
This changes status copy only, with no requests, merges, writes or sync behavior.

Test-only baseline `dcdaad57d47aec8666d1d0bd4040cfcf84f5a95d` on main
`3a26c2cd19ef59356815bda686e12f057cf1f8db`: four widget regressions fail and the
sync-off control passes. After: all five pass, strict Flutter analysis passes
and all 357 tests pass locally. Fixtures verify opening the page does not sync
or mark notes for upload and retains the local note identity. CI is recorded in
the PR and aggregate verification report.

R19 remains partial: automatic failure feedback is not addressed here. The
existing synced/waiting calculation, pending tombstone terminology and Cloud
Notes billing copy also remain separate concerns. No physical/two-device
comparison or content equality is claimed. Rollback: revert this copy/test PR.
