# Faithful to the original report: the per-subdirectory ("directory") shape

The original #447 report used a rule with **two** wildcards whose output lives in a
**per-combination subdirectory**, and titled the issue *"Job arrays across different
wildcards may not create output directories"*:

```python
rule ruleA:
    input:  bam="{sample}.bam"
    output: vcf="finished/{sample}_{N}/test.vcf"
```

Our primary repro (`Snakefile`) is deliberately simpler — one wildcard, a flat
output directory, no input — to isolate the mechanism. This note records that we
also reproduced it in the **reporter's shape**, and what we learned.

## What we ran

`Snakefile.dirs` matches that shape: two wildcards (`{sample}`, `{N}`) and output
`finished/{sample}_{N}/test.txt` (input omitted as non-essential). Run it with:

```bash
./run.sh --dirs            # masked success + collision table
./run.sh --dirs --trigger  # delay only jobs[0] (timing-gated failure)
```

## What we saw

**Same collision, identical mechanism.** Every array task's outer snakemake verifies
`jobs[0]`'s output while each task executes its own:

```
array task     OUTER verifies (jobs[0])         actually executed
7915216_1      finished/s5_a/test.txt           finished/s5_a/test.txt
7915216_2      finished/s5_a/test.txt           finished/s2_a/test.txt   <- verifies s5, ran s2
7915216_3      finished/s5_a/test.txt           finished/s4_a/test.txt
7915216_4      finished/s5_a/test.txt           finished/s1_a/test.txt
7915216_5      finished/s5_a/test.txt           finished/s3_a/test.txt
```

(`jobs[0]` is whichever job the scheduler orders first — `s5` in that run.)

**Two clarifications this shape gave us:**

1. **The output *directories* are created fine.** Each task's per-combo directory
   (`finished/s1_1/`, `finished/s2_1/`, …) exists and holds the right file. The
   report's title (*"may not create output directories"*) was an explicit
   hypothesis — the reporter wrote *"I haven't had the chance to check if any
   directories are created"* — and it is **not** the mechanism. The reporter's
   *observed* symptom, *"all jobs fail at the end because of missing output,"* is the
   verification collision, and that is what reproduces.

2. **The failure is timing-gated, not deterministic.** Even with the first-task
   sleep, this run *passed* (exit 0) because the siblings happened to check
   `jobs[0]`'s output after it had landed (task start can be staggered by node
   availability). The flat-shape run with the same trigger *failed* with deletions.
   So `--trigger` *usually* surfaces the failure but cannot guarantee it; the
   deterministic, always-true evidence is the collision table above (outer verifies
   one job, each task executed a different one) — independent of pass/fail.

## Takeaway

The bug is the per-task identity mis-attribution in the outer wrapper
(`jobs[start_index-1]` reused for every task); it manifests identically regardless
of wildcard count or whether the output sits in a per-combo subdirectory. The flat
`Snakefile` is the cleanest demonstration; `Snakefile.dirs` confirms it in the
reporter's exact shape.
