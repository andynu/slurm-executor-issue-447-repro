#!/bin/bash
# Run the minimal #447 repro.
#
#   ./run.sh              normal run: SUCCEEDS (collision masked), then prints the
#                         per-task collision table proving the mis-attribution.
#   ./run.sh --trigger    forces the failure: ONLY the array's first task sleeps,
#                         so jobs[0]'s output is missing when the sibling tasks
#                         verify it -> MissingOutputException + deletion of the
#                         siblings' (correct) outputs. Optional seconds arg:
#                         ./run.sh --trigger 60   (default 45).
#
# Needs snakemake-executor-plugin-slurm >= 2.6.0 (array flags don't exist before
# that; this machine's default `snakemake` is 2.5.4). Override venv with
# REPRO_VENV=/path. Edit profile/config.yaml for your cluster.
set -uo pipefail
cd "$(dirname "$0")"
VENV="${REPRO_VENV:-/lab/ops_analysis_ssd/test_andy/brieflow-analysis-202512-storage-perf/brieflow/.venv}"
PY="$VENV/bin/python"

export FIRST_SLEEP=0
LATENCY=10
if [ "${1:-}" = "--trigger" ]; then
    export FIRST_SLEEP="${2:-45}"
    LATENCY=10
    echo ">>> TRIGGER mode: first array task sleeps ${FIRST_SLEEP}s, --latency-wait ${LATENCY}s"
    echo ">>> expect MissingOutputException + 'Removing output files' for the sibling tasks."
fi

rm -rf out .snakemake 2>/dev/null
"$PY" -m snakemake --unlock --workflow-profile profile/ >/dev/null 2>&1 || true
"$PY" -m snakemake \
    --executor slurm --workflow-profile profile/ \
    --slurm-array-jobs=all --slurm-array-limit=5 --jobs 5 \
    --slurm-keep-successful-logs --keep-going \
    --latency-wait "$LATENCY" --envvars FIRST_SLEEP
rc=$?

echo
echo "================ COLLISION (from per-task logs) ================"
printf "%-16s %-26s %s\n" "array task" "OUTER verifies (jobs[0])" "actually executed"
for f in $(ls .snakemake/slurm_logs/rule_make/*_*.log 2>/dev/null | sort -t_ -k2 -n); do
    t=$(basename "$f" .log)
    outer=$(awk '/^rule make:/{f=1} f&&/output:/{print;exit}' "$f" | grep -oE "out/s[0-9]\.txt")
    ex=$(awk '/^localrule make:/{f=1} f&&/output:/{print;exit}' "$f" | grep -oE "out/s[0-9]\.txt")
    printf "%-16s %-26s %s\n" "$t" "${outer:-?}" "${ex:-(failed before localrule)}"
done
echo
echo "Every array task's OUTER snakemake verifies the SAME job (jobs[0]); each task"
echo "EXECUTED a different one. Non-first tasks verify the WRONG output."
exit $rc
