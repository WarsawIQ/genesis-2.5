#!/bin/bash
# Where does VAnet2's 46.9 s actually go?
#
# Before touching the solver to lift the one-spikegen-per-hsolve limit, this
# establishes what lifting it could possibly buy. The accelerator would take
# over the channel-update and Hines-solve path; the synaptic event machinery
# (h_dosynchan, h_dospike_event and the GENESIS messaging underneath them)
# stays on the host either way. If that machinery already dominates, the
# restructuring cannot pay for itself and we should know before writing it.
#
# Flat profile, no call graph: GENESIS is built without frame pointers, so a
# -g profile would be mostly unwound garbage. Symbol-level totals answer the
# question on their own.
set -u
R="$HOME/genesis-2.5"
W="$HOME/vanet2_profile"
rm -rf "$W"; mkdir -p "$W"
cp "$R"/genesis/Scripts/VAnet2/*.g "$R"/genesis/Scripts/VAnet2/*.p "$W"/ 2>/dev/null
cd "$W" || exit 1
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n' \
    "$R" "$R" "$R" "$HOME" "$R" > .simrc

echo "node=$(hostname)  binary=nxgenesis_nocl (CPU, no accelerator)"
S=$(date +%s%N)
perf record -F 499 -o perf.data --  \
    timeout 1800 "$R/genesis/src/nxgenesis_nocl" -notty -batch VAnet2-batch.g \
    > run.log 2>&1
RC=$?
E=$(date +%s%N)
awk "BEGIN{printf \"wall=%.2f s rc=$RC\n\", ($E-$S)/1e9}"

echo
echo "== top 30 symbols =="
perf report -i perf.data --stdio --sort symbol --percent-limit 0.3 2>/dev/null \
    | grep -E "^ +[0-9]" | head -30

echo
echo "== grouped =="
perf report -i perf.data --stdio --sort symbol 2>/dev/null \
  | grep -E "^ +[0-9]" \
  | awk '{
      pct=$1+0; sym="";
      for (i=2;i<=NF;i++) if ($i ~ /^\[/) { sym=$(i+1); break }
      if (sym=="") sym=$NF;
      # bucket by what the symbol belongs to
      if (sym ~ /dosynchan|dospike|EventAction|SynChan|synchan|Synaptic|CallElement|CallActionFunc|CallAction|MsgOut|Msg/) b="synaptic + messaging";
      else if (sym ~ /hsolve|hines|chip|h_calc|do_fast|hh_update|compt/) b="hsolve interpreter (channels + solve)";
      else if (sym ~ /Simulate|Step|clock|Clock|Sched/) b="scheduler";
      else b="other";
      t[b]+=pct; tot+=pct
    } END {for (k in t) printf "  %-38s %6.1f%%\n", k, t[k]}' | sort -k2 -rn
