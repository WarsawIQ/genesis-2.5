# Not used: this profile took the wrong path

host_kernel_profile.sh at df937af did not set GENESIS_OCL_TREE_MAX_NCOMPTS=0,
which the campaign harness sets in cuda_env. Above 20 000 compartments the
batched tree solver then declines the model, and these two runs took the
per-step path (the logs say "the Hines solve runs on the CPU (per-step mode)"
and print no CUDA MULTILOOP line). The script was fixed in 61b77b1; the
profile of the tree loop is host_kernel_inf03_20261009_232805.
