; ASEG, CSEG and DSEG: a counter each, and labels relative to them
c1: ds  2
    dseg
d1: ds  5
    cseg
c2: ds  1
    dseg
d2: ds  1
    org 20
d3: ds  1
    aseg
    org 8000h
a1: ds  1
    if  $ eq 8001h
    db  1
    endif
    cseg
    if  c2-c1 eq 2
    db  2
    endif
    if  d2-d1 eq 5
    db  3
    endif
    if  d3-d1 eq 20
    db  4
    endif
here    defl $
    ife c1+6-here
    db  5
    endif
    if  a1 eq 8000h
    db  6
    endif
    ret
