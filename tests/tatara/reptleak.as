; before
        rept    3
        db      1
        endm
        rept    3
        db      2
        endm
later   macro
        db      3
        endm
        later
        ret
