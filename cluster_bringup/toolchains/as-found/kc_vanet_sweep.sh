#!/bin/sh
# CPU scaling sweep of the bundled Vogels-Abbott model. Network size is set by
# the createmap dimensions in VAnet2-batch.g -- a parameter of the model, not a
# change to it (the 4:1 excitatory:inhibitory ratio is preserved). Everything
# else, including tmax, is left as published.
R=$HOME/genesis-2.5
BIN=$R/genesis/src/nxgenesis_nocl
CSV=$HOME/vanet2_cpu_scaling.csv
echo "ex_nx,ex_ny,inh_nx,inh_ny,n_cells,wall_s,vm_lines" > $CSV
for dims in "64 50 32 25" "90 70 45 35" "128 100 64 50" "160 125 80 62"; do
  set -- $dims
  EX=$1; EY=$2; IX=$3; IY=$4
  N=$(( EX*EY + IX*IY ))
  D=$HOME/vanet_sweep_$N
  rm -rf $D; mkdir -p $D
  cp $R/genesis/Scripts/VAnet2/*.g $R/genesis/Scripts/VAnet2/*.p $D/
  printf "setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n" "$R" "$R" "$R" "$HOME" "$R" > $D/.simrc
  sed -i "s/^int Ex_NX = .*/int Ex_NX = $EX; int Ex_NY = $EY/" $D/VAnet2-batch.g
  sed -i "s/^int Inh_NX = .*/int Inh_NX = $IX; int Inh_NY = $IY/" $D/VAnet2-batch.g
  echo "== N=$N (${EX}x${EY} exc + ${IX}x${IY} inh) == $(date +%T)"
  S=$(date +%s.%N)
  ( cd $D && timeout 5400 $BIN -notty -batch VAnet2-batch.g > out.log 2>&1 )
  RC=$?; E=$(date +%s.%N)
  W=$(echo "$E - $S" | bc)
  L=$(wc -l < $D/Vm_out_1000.txt 2>/dev/null || echo 0)
  echo "$EX,$EY,$IX,$IY,$N,$W,$L" >> $CSV
  echo "   exit=$RC wall=${W}s lines=$L"
done
echo "== KONIEC $(date +%T) =="
cat $CSV
