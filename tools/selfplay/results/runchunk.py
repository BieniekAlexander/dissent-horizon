#!/usr/bin/env python3
"""Run the next K undone matches from a batch file, synchronously.
The device shell is killed after ~180s, so work is sliced to fit one window
and --resume-style id skipping makes the slicing free."""
import json, os, subprocess, sys, time

batch, results, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
cfgs = json.load(open(batch))
done = set()
if os.path.exists(results):
    for line in open(results):
        line = line.strip()
        if line:
            done.add(json.loads(line).get("id"))
todo = [c for c in cfgs if c["id"] not in done][:k]
print("total=%d done=%d running=%d" % (len(cfgs), len(done), len(todo)))
if not todo:
    print("BATCH COMPLETE"); sys.exit(0)
tmp = results + ".chunk.json"
json.dump(todo, open(tmp, "w"))
t0 = time.time()
subprocess.run([sys.executable, os.path.expanduser("~/mnt/dissent-horizon/tools/selfplay/run_batch.py"),
                tmp, "--out", results, "--jobs", "2",
                "--godot", os.path.expanduser("~/godot/Godot_v4.7.2-stable_linux.arm64"),
                "--project", os.path.expanduser("~/mnt/dissent-horizon"),
                "--timeout", "600"])
print("chunk wall: %.1fs" % (time.time() - t0))
