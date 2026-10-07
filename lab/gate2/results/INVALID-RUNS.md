# Invalid runs, kept as the record of the instrument defects they found

- **run1-invalid** (2026-10-06 23:26): the client never started in the
  container: `libopenmls_frb.so` not found, then GLIBC 2.38 missing on
  bookworm. And the canary scanner was handed the directory holding its own
  canary list, so it reported 40 hits of its own input. Both fixed in
  `bf62bd3`.
- **run2-invalid** (2026-10-06 23:28): P1 summarised 13 s before Bob
  finished (the wait probed a process name that never matched), so it counted
  14 delivered of a real 20, and the capture and store dump were cut early.
  Fixed in `1052eee`. Its P1 logs are complete and show 20/20.
