#!/bin/bash
# Run the minimal #447 repro.
#
#   ./run.sh                 normal run; SUCCEEDS (collision masked) and prints the
#                            per-task collision table proving the mis-attribution.
#   ./run.sh --trigger [N]   delay ONLY the array's first task by N sec (default 45)
#                            so jobs[0]'s output is missing when the siblings verify
#                            it. Usually surfaces the MissingOutputException +
#                            deletion -- but it is timing-gated (if the cluster
#                            staggers task start so jobs[0] finishes first, it can
#                            still pass; the collision table is the reliable proof).
#   ./run.sh --dirs          use Snakefile.dirs (faithful to the original report:
#                            two wildcards, output in a per-combo subdirectory).
#                            Combine, e.g.  ./run.sh --dirs --trigger
#
# Needs snakemake-executor-plugin-slurm >= 2.6.0 (array flags don't exist before
# that; this machine's default `snakemake` is 2.5.4). Override venv with
# REPRO_VENV=/path. Edit profile/config.yaml for your cluster.
set -uo pipefail
cd "$(dirname "$0")"
VENV="${REPRO_VENV:-/lab/ops_analysis_ssd/test_andy/brieflow-analysis-202512-storage-perf/brieflow/.venv}"
PY="$VENV/bin/python"

SNAKEFILE=Snakefile
export FIRST_SLEEP=0
args=("$@")
for i in "${!args[@]}"; do
    case "${args[$i]}" in
        --dirs)    SNAKEFILE=Snakefile.dirs ;;
        --trigger) next="${args[$((i+1))]:-}"
                   if [[ "$next" =~ ^[0-9]+$ ]]; then export FIRST_SLEEP="$next"; else export FIRST_SLEEP=45; fi ;;
    esac
done
[ "$FIRST_SLEEP" != 0 ] && echo ">>> TRIGGER: first task sleeps ${FIRST_SLEEP}s (--latency-wait 10)"

rm -rf out finished .snakemake 2>/dev/null
"$PY" -m snakemake --unlock --snakefile "$SNAKEFILE" --workflow-profile profile/ >/dev/null 2>&1 || true
"$PY" -m snakemake --snakefile "$SNAKEFILE" \
    --executor slurm --workflow-profile profile/ \
    --slurm-array-jobs=all --slurm-array-limit=5 --jobs 5 \
    --slurm-keep-successful-logs --keep-going \
    --latency-wait 10 --envvars FIRST_SLEEP
rc=$?

echo
echo "================ COLLISION (from per-task logs) ================"
LOGDIR=$(ls -d .snakemake/slurm_logs/rule_* 2>/dev/null | head -1)
printf "%-16s %-30s %s\n" "array task" "OUTER verifies (jobs[0])" "actually executed"
for f in $(ls "$LOGDIR"/*_*.log 2>/dev/null | sort -t_ -k2 -n); do
    t=$(basename "$f" .log)
    outer=$(awk '/^rule /{f=1} f&&/^[[:space:]]*output:/{sub(/.*output:[[:space:]]*/,"");print $1;exit}' "$f")
    ex=$(awk '/^localrule /{f=1} f&&/^[[:space:]]*output:/{sub(/.*output:[[:space:]]*/,"");print $1;exit}' "$f")
    printf "%-16s %-30s %s\n" "$t" "${outer:-?}" "${ex:-(failed before localrule)}"
done
echo
echo "Every array task's OUTER snakemake verifies the SAME job (jobs[0]); each task"
echo "EXECUTED a different one. Non-first tasks verify the WRONG output."
exit $rc
