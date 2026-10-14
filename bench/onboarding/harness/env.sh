# Sourced by every harness script. Paths, so nothing is tied to one machine:
#   H           this directory (prompts, graders, scripts)
#   BENCH_HOME  bench/onboarding (cases/, results/)
#   B           BENCH_ROOT, the work directory: runs/, ref/, replay/, oldid/. Tens of GB
#               once clones and downloads pile up, so it lives outside the repository.
#   DUO_REPO    the duo-updater checkout the cases' parent commits are fetched from
#   PYSHIM      a directory whose `python3` is Python >= 3.10 (old bases' Makefiles call a
#               bare python3, which is 3.9 on macOS)
H=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BENCH_HOME=$(dirname "$H")
B=${BENCH_ROOT:-$HOME/duo-updater-bench}
DUO_REPO=${DUO_REPO:-$(git -C "$BENCH_HOME" rev-parse --show-toplevel)}
PYSHIM=$B/pyshim
mkdir -p "$B" "$PYSHIM"
[ -x "$PYSHIM/python3" ] || ln -sf "$(command -v "${BENCH_PYTHON:-python3.14}")" "$PYSHIM/python3"
