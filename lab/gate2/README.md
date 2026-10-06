# Gate 2 lab: text across the network profiles

`run.py` builds the client bundle and two images, then for each profile runs
one fhirant and two clients in Docker with `tc netem` shaping, exactly as the
Gate 1 lab did. Raw logs, the server's own dump of every stored blob, the
store file and the packet capture land in `results/<label>/<profile>/`; the
canary scanner proves none of them holds a message in the clear. One summary
line per profile goes to `results/<label>.jsonl`.

`dry_run.sh` does the same on the laptop with no Docker and no shaping: one
fhirant started by `dart run`, the two client bundles, the canary scan.

A run creates two Docker networks. Do not start one without Grey's go.
