; named segments: each keeps its own counter across contributions
    cseg    music
m1: ds  3
    dseg    strings
s1: ds  4
    cseg    music
m2: ds  1
    cseg
c1: ds  2
c2: ds  1
    dseg    strings
s2: ds  1
    if  m2-m1 eq 3
    db  1
    endif
    if  s2-s1 eq 4
    db  2
    endif
    if  c2-c1 eq 2
    db  3
    endif
    ret
