# Cloud Notes pending-deletion counts

The repository's pendingCount includes dirty deleted rows, while count includes
only live notes. Subtracting the former from the latter mislabeled clean live
notes when deletions were queued. Cloud Notes now separates dirty live notes
from pending deletions; the live-note bar shows only live notes. Unchanged is
a local state description, with an explicit cloud-content verification limit.
Pending deletions appear separately and still count in the overall waiting
verdict. No dirty flag, note write, upload selection, API or economy changes.

Test-only baseline 07498cd on main 742d1e4: three regressions fail, including
one or two live notes alongside two dirty deleted rows. After: all three pass,
alongside 28 existing page/count controls. Listener refresh after a deletion
acknowledgement remains covered. The 375px widget case checks unchanged/edited
labels, a separate deletion count and absence of writes or automatic sync.
Strict local analysis and all 366 tests pass. CI must independently verify
analysis, tests and the debug APK.

R19 remains partial: these counters do not establish identical content across
devices, actual Drive state, or two-device convergence. Physical fonts, TalkBack
and native performance are unverified. Revert this PR to roll back display-only
count interpretation; local notes and pending deletion state remain intact.
