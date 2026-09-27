; before
        rept    3
        db      1
        endm
        rept    2
        local   l
l:      nop
        endm
count   defl    4
        rept    count
        db      2
        endm
        rept    0
        db      0ffh
        endm
inner   macro   n
        rept    n
        db      3
        endm
        endm
        inner   2
        ret
