# Minimal repro — snakemake-executor-plugin-slurm job-array identity collision (issue #447)

When a rule's distinct-wildcard jobs are submitted as a SLURM array
(`--slurm-array-jobs`), each array task runs the **correct** per-task command, but
every task's *outer* snakemake verifies the **first** job's output (`jobs[0]`)
instead of its own. So non-first tasks fail with `MissingOutputException` and their
correctly-produced outputs get deleted. It's timing-gated (passes when `jobs[0]`'s
output is visible in time, fails at scale / short `--latency-wait`), which is why it
looks intermittent.

**Root cause:** the array `--wrap` command is built once from `jobs[start_index-1]`
(`snakemake_executor_plugin_slurm/__init__.py` ~L889) and reused for every task; the
per-task command is only substituted lower down in the jobstep, so the outer
verification stays bound to `jobs[0]`.

This repo is one rule with 5 distinct-wildcard jobs in one small array (kept well
under `MAX_ARG_STRLEN` so it isn't confounded by the separate `/dev/stdin` E2BIG
fallback). Tested with **snakemake 9.19, executor-plugin-slurm 2.6.0, jobstep
0.6.0** (the array feature only exists from 2.6.0; the flags are absent before that).
Edit `profile/config.yaml` for your partition/account.

## Run

```bash
./run.sh                # succeeds (collision masked) + prints the per-task collision table
./run.sh --trigger      # forces the failure: MissingOutputException + deleted outputs
./run.sh --trigger 60   # same, with a 60s first-task sleep (default 45)
```

`run.sh` uses a venv with the 2.6.0 plugin (override `REPRO_VENV`). The raw command:

```bash
snakemake --executor slurm --workflow-profile profile/ \
          --slurm-array-jobs=all --slurm-array-limit=5 --jobs 5 --verbose
```

## What you see

`./run.sh` **succeeds** ("6 of 6 steps done", `out/s1..s5.txt` all correct) — the
collision is masked because `jobs[0]`'s output is visible before the siblings verify
it. The bug is therefore not in the main log, only in the per-task SLURM logs, which
the executor deletes on success — so `run.sh` passes `--slurm-keep-successful-logs`
and prints the collision from them:

```
array task       OUTER verifies (jobs[0])   actually executed
7915191_1        out/s4.txt                 out/s4.txt
7915191_2        out/s4.txt                 out/s1.txt
7915191_3        out/s4.txt                 out/s3.txt
7915191_4        out/s4.txt                 out/s5.txt
7915191_5        out/s4.txt                 out/s2.txt
```

- **Expected:** each array task verifies the output of the job it ran.
- **Observed (2.6.0):** every task's outer snakemake verifies the **same** job
  (`jobs[0]` = `out/s4.txt` here — whichever job is scheduled first, not always `s1`)
  while each task *executed* a different output. Non-first tasks verify the wrong one.

### How `--trigger` makes it fail deterministically
The array's first task is the one SLURM runs as `SLURM_ARRAY_TASK_MIN`, and it
executes `jobs[0]`. The Snakefile sleeps **only that task** (gated on `FIRST_SLEEP`),
so `jobs[0]`'s output is delayed; the siblings finish instantly, verify `jobs[0]`'s
still-missing output, and raise `MissingOutputException` — then their own correct
outputs are deleted as "corrupted". With `FIRST_SLEEP=0` (default) it's masked. The
*only* difference between pass and destructive-fail is the timing of one job's
output; the mis-attribution is identical either way.

## Possible directions (the maintainers will know best)
Give the outer layer per-task identity from `SLURM_ARRAY_TASK_ID`, or let each task
verify its own outputs rather than `jobs[0]`'s.
