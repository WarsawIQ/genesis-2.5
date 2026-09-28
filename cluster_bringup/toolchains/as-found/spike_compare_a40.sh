#!/bin/sh
set -u
R=$HOME/genesis-2.5
for arm in cpu gpu; do
    bin=$R/genesis/src/nxgenesis_nocl
    [ "$arm" = gpu ] && bin=$R/genesis/src/nxgenesis.sm86
    D=$HOME/spikecmp40-$arm; rm -rf $D; mkdir -p $D
    cp $R/genesis/Scripts/VAnet2/*.g $R/genesis/Scripts/VAnet2/*.p $D/
    printf "setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nsetenv SIMNOTES %s/.notes\nsetenv GENESIS_HELP %s/genesis/Doc\nschedule\n" $R $R $R $D $R > $D/.simrc
    ( cd $D && GENESIS_VANET2_SPIKEFILE=$D/spikes.txt timeout 3600 $bin -notty -batch VAnet2-batch-1solver.g > out.log 2>&1 )
    echo "$arm spikes=$(wc -l < $D/spikes.txt)"
done
