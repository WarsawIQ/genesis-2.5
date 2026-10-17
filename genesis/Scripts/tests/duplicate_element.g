// genesis
//
// Creating an element that already exists replaces it, with a warning, as in
// GENESIS 2.4. In 2.5 up to 2.6.1 an element made at start-up (/output) was not
// in the element hash table, so creating it again appended a second /output.
//
// Prints "DUPLICATE_ELEMENT: PASS" or "DUPLICATE_ELEMENT: FAIL (...)".
create neutral /output
create neutral /output
int n = 0
str e
foreach e ({el /#})
    if ({strcmp {getpath {e} -tail} "output"} == 0)
        n = n + 1
    end
end
if ({n} == 1)
    echo "DUPLICATE_ELEMENT: PASS"
else
    echo "DUPLICATE_ELEMENT: FAIL (" {n} " elements named /output)"
end
quit
