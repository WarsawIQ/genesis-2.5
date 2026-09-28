from neuron import h
h.load_file("stdrun.hoc")
h.cvode.cache_efficient(1)
h("mosinit=0")
h.load_file("init.hoc")
