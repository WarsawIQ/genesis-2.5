#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd "$HOME/coreneuron_cmp/destexhe_benchmarks/NEURON/cobahh" || exit 1
rm -rf x86_64
nrnivmodl -coreneuron mechanisms > build2.log 2>&1
echo "nrnivmodl exit=$?"
grep -iE "error|Error|nahh|khh" build2.log | head -10
echo "--- libs ---"
ls -la x86_64/libcorenrnmech.so x86_64/libnrnmech.so 2>/dev/null
