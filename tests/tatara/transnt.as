; a transient DSEG: its groups overlay, so both frames start at 0
    dseg    scratch,transient
    group   halloc
a1: ds  2
a2: ds  2
    group   hfree
b1: ds  4
b2: ds  2
    group   halloc
a3: ds  4
    cseg
    if  a2-a1 eq 2
    db  1
    endif
    if  b2-b1 eq 4
    db  2
    endif
    if  a3-a1 eq 4
    db  3
    endif
    ret
