from neuron import h, coreneuron
h.load_file("stdrun.hoc")
h.cvode.cache_efficient(1)
coreneuron.enable = True
coreneuron.gpu = False
h("mosinit=0")
h.load_file("init.hoc")
