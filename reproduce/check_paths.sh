#!/bin/sh
# Fail if a measurement, toolchain or analysis script names a location outside
# the repository. Every such location belongs in cluster_bringup/env.sh, where
# it is defined once and can be overridden; anywhere else it ties a result to
# one machine, which is how several of the paper's results came to be
# reproducible only from one user's home directory.
#
#     sh reproduce/check_paths.sh
#
# A line that genuinely needs a literal path (a comment quoting an error
# message, a path inside a generated file) can say so with "# path-ok: why".
# The unchanged copies in cluster_bringup/toolchains/as-found/ and anything
# under cluster_bringup/logs/ are exempt:
# they are the record of what ran.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

PATTERN='(\$HOME|\$\{HOME\}|~/|/storage2?/|/datadisk/|/home/[a-z]|/tmp/|/opt/rh/)'   # path-ok: the pattern itself
hits=$(git ls-files -co --exclude-standard -- \
        'cluster_bringup/*.sh' 'cluster_bringup/**/*.sh' 'cluster_bringup/**/*.py' \
        'reproduce/*.sh' 'reproduce/**/*.sh' 'reproduce/*.py' \
        'paper/scripts/*' 'experiments/*.py' \
    | grep -v -e '^cluster_bringup/env.sh$' -e '^cluster_bringup/toolchains/as-found/' -e '^cluster_bringup/logs/' \
    | while read -r f; do
          grep -n -E "$PATTERN" "$f" | grep -v 'path-ok:' | sed "s#^#$f:#"
      done)

if [ -n "$hits" ]; then
    echo "$hits"
    echo
    echo "$(echo "$hits" | wc -l) literal paths outside cluster_bringup/env.sh."
    echo "Use the variables it defines, or mark a line '# path-ok: <reason>'."
    exit 1
fi
echo "no literal paths outside cluster_bringup/env.sh"
