// genesis
//
// A compartment's coordinates and the element tree must not overlap.
// GENESIS 2.5 up to 2.6.1 added a field (childtail) to the generic element
// layout but not to the one compartments use, so setting x0/y0 of a
// compartment overwrote its link to the next sibling: the coordinates came back
// as garbage after another sibling was created, and listing the parent crashed.
//
//   nxgenesis -nosimrc -notty -batch element_layout.g
//
// Prints "ELEMENT_LAYOUT: PASS" or "ELEMENT_LAYOUT: FAIL (...)".
int bad = 0
create neutral /cell
create compartment /cell/a
create compartment /cell/b
setfield /cell/b x0 1.5 y0 2.5 z0 3.5
create compartment /cell/c
setfield /cell/c x0 4.5 y0 5.5
if ({getfield /cell/b x0} != 1.5 || {getfield /cell/b y0} != 2.5 || {getfield /cell/b z0} != 3.5)
    echo "b's coordinates changed: " {getfield /cell/b x0} {getfield /cell/b y0} {getfield /cell/b z0}
    bad = bad + 1
end
create neutral /cell/d
str names = ""
str e
foreach e ({el /cell/#})
    names = {names} @ " " @ {getpath {e} -tail}
end
if ({strcmp {names} " a b c d"} != 0)
    echo "children of /cell: " {names}
    bad = bad + 1
end
if ({bad} == 0)
    echo "ELEMENT_LAYOUT: PASS"
else
    echo "ELEMENT_LAYOUT: FAIL (" {bad} " checks)"
end
quit
