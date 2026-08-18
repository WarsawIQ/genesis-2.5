# Spiking-network acceleration — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one `hsolve` hold many spike generators, so a synaptically coupled spiking network is built as a single solver and reaches the GPU through the per-step dispatch path that already works.

**Architecture:** `hsolve->spikegen` (one `Element *`) becomes `hsolve->spikegens` (one per compartment). The interpreter derives the compartment index from the `vm` pointer it already advances, so nothing is added to the hot loop and **the opcode stream layout does not change**. The CUDA host glue stops counting crossings and starts walking the per-compartment flag array it already downloads. No kernel changes.

**Tech stack:** C (K&R-style function definitions, as the surrounding files use), CUDA C++ for the backend glue, GENESIS SLI for the model script, POSIX sh for harnesses.

## Global Constraints

- **The opcode stream layout must not change.** No opcode may gain or lose operands. A previous attempt changed it and moved VAnet2's CPU output md5 from `1440eb86` to `0b663c0c`; it was reverted.
- **Gate 1 is unconditional.** After every task that touches solver code, `sh cluster_bringup/80_accel_regression.sh check` must pass. If it fails, revert the task rather than explain the difference.
- **CUDA only.** The OpenCL kernel does not implement `SPIKE_OP` or the synaptic opcodes; `ocl_hsolve.c` marks such compartments `cpu_only` and disables acceleration for the whole solver. That behaviour stays as it is. Do not touch `opencl/`.
- **Existing scripts must keep working.** The per-cell `call solver DUPLICATE` idiom stays valid; `genesis/Scripts/VAnet2/VAnet2-batch.g` is not to be modified — it produced the published 46.9 s.
- **Follow the file's own style.** `hines_*.c` use K&R definitions (`void f(a) int a; {`). Match the file you are editing, do not modernise it.
- Build CPU: `cd genesis/src && make` → `nxgenesis_nocl`. Build CUDA: `make USE_CUDA=1` → `nxgenesis`.

---

### Task 1: Record the golden file before touching anything

**Files:**
- Run only: `cluster_bringup/80_accel_regression.sh`
- Create: `cluster_bringup/accel_regression_golden.txt` (or refresh it)

**Interfaces:**
- Consumes: nothing.
- Produces: a golden file that every later task checks against. Without it, gate 1 cannot be evaluated and the rest of the plan is unsafe.

- [ ] **Step 1: Confirm the tree is clean and build both binaries**

```bash
cd /datadisk/od-kchlasta/1.Ac/0.Nauka/61.GENESIS/genesis-2.4
git status --short          # must be empty
cd genesis/src && make && make USE_CUDA=1 && cd ../..
ls -la genesis/src/nxgenesis genesis/src/nxgenesis_nocl
```

Expected: both binaries exist and are newer than the last source edit.

- [ ] **Step 2: Record the golden file on the device you will validate on**

```bash
sh cluster_bringup/80_accel_regression.sh record
```

Expected: `recorded N values on <device> -> cluster_bringup/accel_regression_golden.txt`

- [ ] **Step 3: Confirm the golden contains the VAnet2 anchor**

```bash
grep vanet2 cluster_bringup/accel_regression_golden.txt
```

Expected: a line `vanet2_cpu|vm_md5=1440eb86...`. If the md5 differs from `1440eb86`, **stop** — the tree is not in the state this plan assumes; report before continuing.

- [ ] **Step 4: Confirm check passes against the file just recorded**

```bash
sh cluster_bringup/80_accel_regression.sh check
```

Expected: `PASS: N values unchanged on <device>`

- [ ] **Step 5: Commit**

```bash
git add cluster_bringup/accel_regression_golden.txt
git commit -m "Record the accelerator golden file before the spikegen change

Gate 1 of the spiking-network work is that models with one spike generator
per solver stay byte-identical. That is only checkable against a baseline
recorded first, on the device the checks will run on -- the fp32 kernels are
not bit-identical between the A40 and the A100."
```

---

### Task 2: A failing test for the thing that is currently refused

**Files:**
- Create: `genesis/Scripts/benchmark/two_spikegen_setup.g`
- Create: `cluster_bringup/81_two_spikegen_test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `cluster_bringup/81_two_spikegen_test.sh`, which exits 0 when one solver accepts two spike generators and non-zero otherwise. Tasks 3–5 use it as their pass condition.

This is the test that must fail first. Two cells, each with a soma carrying a `spikegen`, under one `hsolve`. Today GENESIS refuses at SETUP.

- [ ] **Step 1: Write the model script**

Create `genesis/Scripts/benchmark/two_spikegen_setup.g`:

```
// genesis
// Two cells, one hsolve, one spikegen each.
//
// GENESIS has always refused a second spikegen in a solver
// (hines_child.c). That refusal is what forces a spiking network to be
// built as one solver per cell, which is why the accelerator cannot pay
// for itself there. This is the smallest model that provokes it.
//
// Prints SETUP_OK on success. On the unmodified tree it never gets that
// far -- SETUP raises "second spikegen ... not allowed" and the script
// exits non-zero.

float EREST = -0.070
float DT    = 10e-6

include genesis/src/startup/schedule.g

create neutral /library
pushe /library
create compartment soma
setfield soma Em {EREST} initVm {EREST} Rm 1e8 Cm 1e-10 Ra 1e6 \
    dia 20e-6 len 20e-6
create spikegen spike
setfield spike thresh -0.020 abs_refract 0.002 output_amp 1
pope
disable /library

create neutral /net
int i
str cell
for (i = 0; i < 2; i = i + 1)
    cell = "/net/cell" @ {i}
    create neutral {cell}
    copy /library/soma {cell}/soma
    copy /library/spike {cell}/spike
    addmsg {cell}/soma {cell}/spike INPUT Vm
end

setclock 0 {DT}
useclock /net/##[] 0

create hsolve /net/solver
setfield /net/solver path "/net/##[][TYPE=compartment]" chanmode 1 calcmode 1
call /net/solver SETUP
useclock /net/solver 0

echo "SETUP_OK ncompts=" {getfield /net/solver ncompts}
reset
step 10
echo "STEP_OK"
quit
```

- [ ] **Step 2: Write the test harness**

Create `cluster_bringup/81_two_spikegen_test.sh`:

```sh
#!/bin/sh
# One hsolve, two spike generators.
#
# GENESIS refuses this at SETUP, which is the constraint that forces a
# spiking network into one solver per cell. This script is the pass
# condition for lifting that refusal: it exits 0 only when SETUP accepts
# the model and ten steps run.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT" || exit 1
BIN=${BIN:-./genesis/src/nxgenesis_nocl}
OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT

"$BIN" -nosimrc -notty -batch \
    genesis/Scripts/benchmark/two_spikegen_setup.g > "$OUT" 2>&1

if grep -q "second spikegen" "$OUT"; then
    echo "FAIL: SETUP still refuses a second spikegen"
    grep "second spikegen" "$OUT" | head -1
    exit 1
fi
if ! grep -q "^SETUP_OK" "$OUT"; then
    echo "FAIL: SETUP did not complete"; tail -5 "$OUT"; exit 1
fi
if ! grep -q "^STEP_OK" "$OUT"; then
    echo "FAIL: SETUP completed but stepping did not"; tail -5 "$OUT"; exit 1
fi
echo "PASS: $(grep '^SETUP_OK' "$OUT")"
exit 0
```

- [ ] **Step 3: Run it and verify it fails for the expected reason**

```bash
chmod +x cluster_bringup/81_two_spikegen_test.sh
sh cluster_bringup/81_two_spikegen_test.sh
```

Expected: exit 1, printing `FAIL: SETUP still refuses a second spikegen` followed by the GENESIS error line. If it fails any other way, the model script is wrong — fix it before proceeding, because a test that fails for the wrong reason proves nothing.

- [ ] **Step 4: Commit**

```bash
git add genesis/Scripts/benchmark/two_spikegen_setup.g cluster_bringup/81_two_spikegen_test.sh
git commit -m "Add a failing test for two spike generators in one solver

Two cells under one hsolve, one spikegen each. SETUP refuses it today with
'second spikegen not allowed', which is the constraint that forces a spiking
network to be built as one solver per cell. The script exits 0 only once
SETUP accepts the model and ten steps run."
```

---

### Task 3: Per-compartment spikegen table

**Files:**
- Modify: `genesis/src/hines/hines_struct.h:311`
- Modify: `genesis/src/hines/hines_child.c:246-248` and `:958-965`
- Modify: `genesis/src/hines/hines_conn.c:43-55`
- Modify: `genesis/src/hines/hines_chip.c:266-276`

**Interfaces:**
- Consumes: `cluster_bringup/81_two_spikegen_test.sh` from Task 2.
- Produces: `hsolve->spikegens` (`Element **`, length `hsolve->ncompts`, `NULL` where a compartment has no generator) and `hsolve->nspikegens` (`int`). `h_dospike_event(hsolve, comp)` replaces `h_dospike_event(hsolve)`; Task 4 calls the new signature.

- [ ] **Step 1: Add the fields**

In `genesis/src/hines/hines_struct.h`, replace line 311:

```c
	Element *spikegen;	/* pointer to Spikegen element */
```

with:

```c
	Element *spikegen;	/* first Spikegen element; kept so existing
				** field access and hines_d@.c stay valid */
	Element **spikegens;	/* [ncompts], NULL where the compartment has
				** none. One solver may now hold many, which is
				** what lets a spiking network be built as a
				** single hsolve. */
	int	nspikegens;
```

`spikegen` is deliberately kept: `hines_d@.c` registers it as a named field of the object, and removing it would change the SLI-visible interface.

- [ ] **Step 2: Allocate and populate the table at SETUP**

In `genesis/src/hines/hines_child.c`, the branch at line 246 currently reads:

```c
		} else if (strcmp(oname,"spikegen")==0) {
			ct=SPIKEGEN_T;
			hsolve->spikegen=child;
```

Replace with:

```c
		} else if (strcmp(oname,"spikegen")==0) {
			ct=SPIKEGEN_T;
			/* Keep the first one in the legacy field, and record
			** every one against the compartment it hangs off, so
			** SPIKE_OP can emit from the right generator. The
			** table is allocated on first use: models without
			** spike elements pay nothing. */
			if (hsolve->spikegen==NULL) hsolve->spikegen=child;
			if (hsolve->spikegens==NULL) {
				hsolve->spikegens=(Element **)calloc(
					hsolve->ncompts,sizeof(Element *));
				if (hsolve->spikegens==NULL) {
					Error();
					printf(" during SETUP of %s: out of memory for spikegen table.\n",Pathname(hsolve));
					return(ERR);
				}
			}
			if (i>=0 && i<hsolve->ncompts) {
				hsolve->spikegens[i]=child;
				hsolve->nspikegens++;
			}
```

`i` is the compartment index here: this branch sits inside `for (i=0; i<ncompts; i++)` which opens at `hines_child.c:187`, and `ncompts` is `hsolve->ncompts`, taken at `hines_child.c:85`. Both are in scope; no other index needs finding.

- [ ] **Step 3: Drop the refusal**

In the same file, the `case SPIKEGEN_T:` block near line 958 currently reads:

```c
			if (firstSPIKE) {
			    firstSPIKE=0;
			} else {
			    Error();
			    printf(" during SETUP of %s: second spikegen %s not allowed.\n",Pathname(hsolve),Pathname(child));
			    return(ERR);
			}
			break;
```

Replace with:

```c
			/* Many generators per solver are supported: each is
			** recorded against its compartment above, and SPIKE_OP
			** emits from hsolve->spikegens[comp]. The refusal that
			** stood here is why a spiking network had to be built
			** as one solver per cell. */
			firstSPIKE=0;
			break;
```

Leave `firstSPIKE` declared and assigned — removing it would touch unrelated lines in this function.

- [ ] **Step 4: Make the emitter take a compartment**

In `genesis/src/hines/hines_conn.c`, replace lines 43–55:

```c
/* execute Spikegen event */
void h_dospike_event(hsolve)
	Hsolve  *hsolve;
{
	struct Spikegen_type *spike;
	MsgOut  *mo;

	spike = (struct Spikegen_type *) hsolve->spikegen;
	MSGOUTLOOP(spike,mo) {
		CallEventAction(spike, mo);
	}
        spike->lastevent = SimulationTime();
}
```

with:

```c
/* execute Spikegen event for the generator on compartment `comp' */
void h_dospike_event(hsolve,comp)
	Hsolve  *hsolve;
	int	comp;
{
	struct Spikegen_type *spike;
	MsgOut  *mo;
	Element *elm;

	/* spikegens[] is per compartment so that a solver holding many cells
	** emits from the generator that actually crossed threshold. Solvers
	** built before the table existed, and any caller that cannot name a
	** compartment, fall back to the single legacy pointer. */
	if (hsolve->spikegens != NULL && comp >= 0 && comp < hsolve->ncompts)
		elm = hsolve->spikegens[comp];
	else
		elm = hsolve->spikegen;
	if (elm == NULL) return;

	spike = (struct Spikegen_type *) elm;
	MSGOUTLOOP(spike,mo) {
		CallEventAction(spike, mo);
	}
        spike->lastevent = SimulationTime();
}
```

- [ ] **Step 5: Pass the compartment from the interpreter**

In `genesis/src/hines/hines_chip.c`, the `SPIKE_OP` case at line 266 currently reads:

```c
		    case SPIKE_OP:
		    /* check for spike triggering */
			*op-=1;		/* decrement refractory period */
			if (Vm>*chip++) {  /* chip[n]=thresh */
			    if (*op<=0) {        /* check refractory period */
				h_dospike_event(hsolve);
				*op=*(op+1);    /* reset refractory period */
			    }
			}
			op+=2;
			continue;	/* go back to this switch statement */
```

Replace the `h_dospike_event(hsolve);` line with:

```c
				/* vm has already been advanced past this
				** compartment at the top of the loop, so the
				** index is one behind it. Derived rather than
				** counted: nothing is added to the hot path and
				** there is no counter to fall out of step. */
				h_dospike_event(hsolve,(int)(vm-hsolve->vm)-1);
```

- [ ] **Step 6: Build the CPU binary**

```bash
cd genesis/src && make 2>&1 | tail -20 && cd ../..
```

Expected: build completes. Any warning naming `spikegen`, `spikegens` or `h_dospike_event` is a real problem — read it, do not ignore it.

- [ ] **Step 7: Run the Task 2 test and verify it now passes**

```bash
sh cluster_bringup/81_two_spikegen_test.sh
```

Expected: `PASS: SETUP_OK ncompts= 2`

- [ ] **Step 8: Gate 1 — the change must be a no-op on existing models**

```bash
sh cluster_bringup/80_accel_regression.sh check
```

Expected: `PASS: N values unchanged on <device>`.

If this fails, **revert the task**:

```bash
git checkout -- genesis/src/hines/
```

and report which values moved. Do not proceed with a failing gate 1 and do not adjust the golden file to make it pass.

- [ ] **Step 9: Commit**

```bash
git add genesis/src/hines/hines_struct.h genesis/src/hines/hines_child.c \
        genesis/src/hines/hines_conn.c genesis/src/hines/hines_chip.c
git commit -m "Let one hsolve hold many spike generators

hsolve->spikegen was a single Element pointer and SETUP refused a second
generator, so any spiking model had to be built as one solver per cell.
Spike generators are now recorded per compartment and h_dospike_event()
takes the compartment that crossed threshold.

The opcode stream is untouched. The compartment index is derived from the
vm pointer the interpreter already advances, so SPIKE_OP keeps its three
slots and every downstream ops[] and chip[] offset stays where it was --
which is what a previous attempt at this got wrong.

The legacy spikegen field stays: hines_d@.c registers it as an SLI-visible
field of the object.

Existing models are byte-identical (80_accel_regression.sh check)."
```

---

### Task 4: CUDA glue emits from the right generator

**Files:**
- Modify: `genesis/src/hines/cuda/cuda_backend.cu:296-308`
- Modify: `genesis/src/hines/cuda/cuda_hsolve.c:59` and `:135-143`

**Interfaces:**
- Consumes: `h_dospike_event(hsolve, comp)` from Task 3.
- Produces: `int cuda_backend_spike_flag(void *sth, int i)` — returns non-zero when compartment `i` crossed threshold in the last dispatch. `cuda_backend_spikes_this_step()` stays, so nothing else breaks.

Today the backend counts crossings and the caller emits that many events from the one generator. With many generators that misroutes every spike.

- [ ] **Step 1: Expose the flag array**

In `genesis/src/hines/cuda/cuda_backend.cu`, next to the existing `cuda_backend_has_spikes()` (near line 552), add:

```c
/* Which compartment crossed, not just how many. With one generator per solver
   the count was enough; a solver holding many cells has to emit from the
   generator belonging to the compartment that actually fired. */
int cuda_backend_spike_flag(void *sth, int i)
{
    CudaState *st = (CudaState *)sth;
    if (!st || !st->h_spike_flag || i < 0 || i >= st->ncompts) return 0;
    return st->h_spike_flag[i];
}
```

Add it inside the existing `extern "C" {` block, which opens at `cuda_backend.cu:114` and closes at `:585` — the neighbouring accessors carry no `extern "C"` of their own because of it. `st->ncompts` and `st->h_spike_flag` are both `CudaState` fields already (`:63`, `:193`).

- [ ] **Step 2: Declare it on the caller side**

In `genesis/src/hines/cuda/cuda_hsolve.c`, beside the other `extern` declarations near line 37, add:

```c
extern int  cuda_backend_spike_flag(void *sth, int i);
```

and change the declaration at line 59 from:

```c
extern void h_dospike_event(Hsolve *hsolve);
```

to:

```c
extern void h_dospike_event(Hsolve *hsolve, int comp);
```

- [ ] **Step 3: Walk the flags instead of counting**

Replace lines 135–143 of `cuda_hsolve.c`:

```c
    if (cuda_backend_has_spikes(hsolve->accel_state)) {
        int k = cuda_backend_spikes_this_step(hsolve->accel_state);
        while (k-- > 0) h_dospike_event(hsolve);
    }
```

with:

```c
    if (cuda_backend_has_spikes(hsolve->accel_state)) {
        /* Emit from the generator on each compartment that crossed. Counting
           crossings and calling the emitter that many times was only ever
           correct while a solver held one generator. */
        int i;
        for (i = 0; i < hsolve->ncompts; i++)
            if (cuda_backend_spike_flag(hsolve->accel_state, i))
                h_dospike_event(hsolve, i);
    }
```

- [ ] **Step 4: Build the CUDA binary**

```bash
cd genesis/src && make USE_CUDA=1 2>&1 | tail -20 && cd ../..
```

Expected: build completes with no warning mentioning `h_dospike_event` or `spike_flag`.

- [ ] **Step 5: Gate 1 again, both arms**

```bash
sh cluster_bringup/80_accel_regression.sh check
```

Expected: `PASS`. Revert the task on failure, as in Task 3 Step 8.

- [ ] **Step 6: Commit**

```bash
git add genesis/src/hines/cuda/cuda_backend.cu genesis/src/hines/cuda/cuda_hsolve.c
git commit -m "Emit GPU spikes from the generator that crossed

The backend downloaded a per-compartment flag array and then reduced it to a
count, and the caller emitted that many events from the solver's single
generator. Correct while a solver held one cell; with many it would send
every spike from the wrong place. The caller now walks the flags.

No kernel change: the device already recorded crossings per compartment."
```

---

### Task 5: VAnet2 as a single solver

**Files:**
- Create: `genesis/Scripts/VAnet2/VAnet2-batch-1solver.g`
- Create: `cluster_bringup/82_vanet2_1solver.sh`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces: `cluster_bringup/82_vanet2_1solver.sh`, which prints spike count and mean firing rate for the one-solver variant on CPU or GPU, for the gate-2 and gate-3 comparisons.

`VAnet2-batch.g` is not to be edited. Copy it and change only how solvers are made.

- [ ] **Step 1: Create the variant from the original**

```bash
cd genesis/Scripts/VAnet2
cp VAnet2-batch.g VAnet2-batch-1solver.g
grep -n "create hsolve solver\|DUPLICATE\|call solver SETUP" VAnet2-batch-1solver.g
```

Read the block those lines sit in before editing — the per-cell solver is created inside a loop over cells, and the whole loop is what gets replaced.

- [ ] **Step 2: Replace the per-cell solvers with one**

The block to replace is `VAnet2-batch.g:433-464`, the whole `if(hflag) … end`. It creates a solver inside cell 0 of each layer and then `DUPLICATE`s it into every other cell, copying each soma's `x/y/z` onto that cell's solver.

Two things about it matter. `setmethod solver 11` selects Crank-Nicholson and **must be carried over** — dropping it changes the integration method and invalidates any comparison. The two layers use different paths: the excitatory one is `"../soma"`, the inhibitory one `"../[][TYPE=compartment]"`.

The per-solver `x/y/z` can go. Connectivity is built afterwards by `connect_cells`, and `planarconnect` addresses `/Ex_layer/Ex_cell[]/soma/spike` and the synchans under the somas (`VAnet2-batch.g:200-234`) — element positions, not solver positions. Nothing reads the coordinates this block writes onto solvers.

Replace the block with:

```
/* One hsolve per layer instead of one per cell.
**
** The original idiom -- create a solver in cell 0, then DUPLICATE it into
** every other cell -- exists because GENESIS refused a second spikegen in
** one solver. With that lifted, a layer is a single solver and the
** accelerator is dispatched once per step rather than once per cell per
** step.
**
** setmethod 11 (Crank-Nicholson) is carried over unchanged: it is the
** integration method the published run used.
**
** The per-solver x/y/z the original set are dropped. connect_cells runs
** after this and addresses soma/spike and synchan elements, not solvers,
** so nothing reads them.
**
** VAnet2-batch.g keeps the original idiom -- it produced the published
** 46.9 s and has to stay reproducible.
*/
if(hflag)
    create hsolve /Ex_layer/solver
    setmethod /Ex_layer/solver 11
    setfield /Ex_layer/solver chanmode {hsolve_chanmode} \
        path "/Ex_layer/Ex_cell[]/soma"
    call /Ex_layer/solver SETUP
    echo "Ex solver ncompts: " {getfield /Ex_layer/solver ncompts}

    create hsolve /Inh_layer/solver
    setmethod /Inh_layer/solver 11
    setfield /Inh_layer/solver chanmode {hsolve_chanmode} \
        path "/Inh_layer/Inh_cell[]/##[][TYPE=compartment]"
    call /Inh_layer/solver SETUP
    echo "Inh solver ncompts: " {getfield /Inh_layer/solver ncompts}
end
```

The two `echo` lines are the check for Step 3: the excitatory count must equal `Ex_NX*Ex_NY` (3200) and the inhibitory one `Inh_NX*Inh_NY` (800). A smaller number means the path wildcard is not matching every cell.

The `SAVE`/`findsolvefield` messages near `VAnet2-batch.g:332-345` address `/Ex_layer/Ex_cell[{middlecell}]/solver`, which no longer exists. Repoint them at `/Ex_layer/solver` or delete them from this variant — it exists for timing and spike counts, and `spikecount.g` supplies the rate.

- [ ] **Step 3: Verify it builds one solver and runs**

```bash
cd /datadisk/od-kchlasta/1.Ac/0.Nauka/61.GENESIS/genesis-2.4
mkdir -p /tmp/va1 && cp genesis/Scripts/VAnet2/*.g genesis/Scripts/VAnet2/*.p /tmp/va1/
cd /tmp/va1
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nschedule\n' "$OLDPWD" "$OLDPWD" "$OLDPWD" > .simrc
"$OLDPWD/genesis/src/nxgenesis_nocl" -notty -batch VAnet2-batch-1solver.g 2>&1 | tail -20
```

Expected: no `second spikegen` error, no `not allowed`, the run completes. If SETUP reports far fewer compartments than 3200, the `path` wildcard is not matching every cell — fix the path before going on.

- [ ] **Step 4: Write the measurement harness**

Create `cluster_bringup/82_vanet2_1solver.sh`:

```sh
#!/bin/sh
# VAnet2 built as one solver per layer instead of one per cell.
#
# Gate 2 compares this against the stock script on CPU: different solver
# grouping changes the arithmetic order, so the two are not bit-identical
# and the criterion is agreement of firing rate. Gate 3 compares this
# script's CPU and GPU arms against each other.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SCRIPT=${SCRIPT:-VAnet2-batch-1solver.g}
BIN=${BIN:-$ROOT/genesis/src/nxgenesis_nocl}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

cp "$ROOT"/genesis/Scripts/VAnet2/*.g "$ROOT"/genesis/Scripts/VAnet2/*.p "$W"/ 2>/dev/null
cd "$W" || exit 1
printf 'setenv SIMPATH . %s/genesis/startup %s/genesis/Scripts/neurokit %s/genesis/Scripts/neurokit/prototypes\nschedule\n' \
    "$ROOT" "$ROOT" "$ROOT" > .simrc

S=$(date +%s%N)
timeout 1800 "$BIN" -notty -batch "$SCRIPT" > out.log 2>&1
RC=$?
E=$(date +%s%N)
awk "BEGIN{printf \"script=$SCRIPT rc=$RC wall=%.2f s\n\", ($E-$S)/1e9}"
grep -c "second spikegen" out.log >/dev/null 2>&1 && \
    { echo "ERROR: solver refused the model"; exit 1; }
tail -3 out.log
```

- [ ] **Step 5: Commit**

```bash
cd /datadisk/od-kchlasta/1.Ac/0.Nauka/61.GENESIS/genesis-2.4
chmod +x cluster_bringup/82_vanet2_1solver.sh
git add genesis/Scripts/VAnet2/VAnet2-batch-1solver.g cluster_bringup/82_vanet2_1solver.sh
git commit -m "Add a VAnet2 variant built as one solver per layer

The stock script creates a solver per cell because GENESIS refused a second
spike generator in one. With that lifted, a layer is one solver and the
accelerator is dispatched once per step rather than once per cell per step.

VAnet2-batch.g is untouched: it produced the published 46.9 s and that has
to stay reproducible."
```

---

### Task 6: Gates 2 and 3, then timing

**Files:**
- Run only. No source changes.
- Create: `cluster_bringup/logs/vanet2_1solver_<node>_<date>.csv`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: the measurement that decides whether this work paid, in a form the paper can cite.

- [ ] **Step 1: Gate 2 — one solver against many, on CPU**

```bash
sh cluster_bringup/82_vanet2_1solver.sh                       # one-solver variant
SCRIPT=VAnet2-batch.g sh cluster_bringup/82_vanet2_1solver.sh # stock, same harness
```

Then take the firing rate of each with the existing instrument:

```bash
sh cluster_bringup/coreneuron/run_spikecount.sh
```

Expected: the two rates agree within 4% — the tolerance already accepted in the paper between GENESIS and NEURON. They will not be bit-identical; different solver grouping changes the order of arithmetic. A rate gap larger than 4% means spikes are being emitted from the wrong generators — go back to Task 3 Step 5 and check the compartment index.

- [ ] **Step 2: Gate 3 — GPU against CPU on the one-solver variant**

```bash
export GENESIS_OCL_TREE_MAX_NCOMPTS=0
BIN=$PWD/genesis/src/nxgenesis sh cluster_bringup/82_vanet2_1solver.sh
```

Expected: completes without the accelerator refusing the model, and the spike count matches the CPU arm's to the same standard the paper already applies to spiking runs — equal counts, phase drift only.

Confirm the GPU was actually used; a silent CPU fallback looks exactly like success:

```bash
grep -i "cuda\|accel" /tmp/*/out.log | head
```

- [ ] **Step 3: Time it on an idle node**

Check the card is free first — a foreign job inflated a whole sweep once before:

```bash
nvidia-smi --query-gpu=memory.used --format=csv,noheader
```

Expected: under 500 MiB. Then three replicates of each arm, recording to CSV:

```bash
for arm in cpu gpu; do
  BIN=$PWD/genesis/src/nxgenesis_nocl
  [ $arm = gpu ] && BIN=$PWD/genesis/src/nxgenesis
  for r in 1 2 3; do
    BIN=$BIN sh cluster_bringup/82_vanet2_1solver.sh
  done
done
```

- [ ] **Step 4: Compare against the baselines**

The numbers this has to be read against: GENESIS stock CPU **46.9 s**, CoreNEURON on the A100 **27.0 s**, and the profile's floor of **19.3 s** with a ceiling of 2.43×.

Record all three arms — stock CPU, one-solver CPU, one-solver GPU — because the one-solver CPU arm is what separates "the accelerator helped" from "removing 4000 solvers helped".

- [ ] **Step 5: Commit the measurements**

```bash
git add cluster_bringup/logs/
git commit -m "Measure VAnet2 as a single solver, CPU and GPU

Three arms so the two effects can be told apart: the stock per-cell script,
the one-solver variant on CPU, and the one-solver variant on GPU. Without
the middle arm there is no way to say how much came from the accelerator
and how much from no longer building 4000 solvers."
```

---

### Task 7: Report what was measured

**Files:**
- Modify: `genesis/src/hines/SPIKING_NETWORK_ACCEL_DESIGN.md` (status line and a results section)
- Modify: `paper/manuscript_softwarex_draft.tex` — only if the result changes a claim

**Interfaces:**
- Consumes: Task 6.
- Produces: the record of what happened, including if it did not work.

- [ ] **Step 1: Write the outcome into the design document**

Change the status line from `design, 2026-08-19. Not implemented.` to the date and outcome, and add a short results section giving the three wall times, the firing rates from gate 2, and the spike counts from gate 3.

State a negative outcome as plainly as a positive one. If the GPU arm lands above 27.0 s, the honest reading is that per-step dispatch overhead over 100,000 steps eats the gain, and the design document should say so — the profile predicted a floor of 19.3 s and a prediction that missed is worth recording.

- [ ] **Step 2: Update the paper only if a claim changed**

The abstract says a spiking network is one GENESIS cannot yet accelerate, and Table 5 reports CoreNEURON's GPU arm as 1.74× ahead. Both change only if gate 3 passed **and** the timing beat 27.0 s. If it did not, the Future work paragraph corrected earlier already describes the situation accurately and the paper needs no edit.

Check the word budget before adding anything — the body was at 3999 of 4000 words:

```bash
cd paper && tectonic -X compile manuscript_softwarex_draft.tex --keep-logs
```

- [ ] **Step 3: Commit**

```bash
git add genesis/src/hines/SPIKING_NETWORK_ACCEL_DESIGN.md paper/
git commit -m "Record what lifting the spikegen limit actually bought"
```
