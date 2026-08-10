# Withdrawn tests

Tests in here describe behaviour that was built, shipped, and then taken back
out. They are kept — rather than deleted — because the requirement usually
survives the implementation that failed it, and the next attempt should start
from what was already worked out rather than from a blank file.

Nothing here runs. `supabase test db` only globs `supabase/tests`.

| File | Withdrawn | Why |
|---|---|---|
| `coverage_valid_learning.sql` | 2026-08-10 | S3-C2 restricted learning to silences fully contained by valid coverage. It derived coverage from **activity signals**, so the system only counted itself as watching while the person was busy, and learned that normal quiet lasts fourteen minutes. One account was falsely escalated within a minute of deployment (`stage=self`, 0 notifications, 0 pushes). Reverted by `20260810040000_s3_revert_coverage_valid_learning.sql`. Its ten subjects never modelled sparse coverage — coverage always fully contained the gap — which is exactly why the suite stayed green over a fatal flaw. |

Before reviving `coverage_valid_learning.sql`, read ADR-0040 revision one in the
Brain. Coverage must come from a **watcher heartbeat** independent of user
activity, carrying four states (`app_foreground`, `app_background`,
`app_killed`, `device_off`), and the revived suite must cover sparse coverage
and background-quiet periods — the two cases the original never asked about.
