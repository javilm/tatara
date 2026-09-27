; before
inner   macro   a,b
        rept    2
        db      a,b
        endm
        endm
        rept    10
        inner   1,2
        endm
        ret
