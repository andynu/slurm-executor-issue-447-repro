SAMPLES = ["s1", "s2", "s3", "s4", "s5"]


rule all:
    input:
        expand("out/{s}.txt", s=SAMPLES),


rule make:
    output:
        "out/{s}.txt",
    shell:
        # Normally just `echo {wildcards.s} > {output}`.
        #
        # Optional failure trigger: if FIRST_SLEEP > 0, ONLY the array's first
        # task sleeps (it is the one SLURM runs as SLURM_ARRAY_TASK_MIN, which
        # executes jobs[0]). That delays jobs[0]'s output; the sibling tasks
        # finish instantly and then verify jobs[0]'s output (the collision) ->
        # it isn't there yet -> MissingOutputException -> their correct outputs
        # are deleted. With FIRST_SLEEP unset/0 the workflow succeeds (the bug is
        # masked). Enable via `./run.sh --trigger`.
        'if [ "$SLURM_ARRAY_TASK_ID" = "$SLURM_ARRAY_TASK_MIN" ]; then '
        'sleep "${{FIRST_SLEEP:-0}}"; fi; '
        'echo {wildcards.s} > {output}'
