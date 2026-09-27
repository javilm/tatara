; before
        rept    3
        endm
empty   macro
        endm
        empty
        empty
hollow  macro
        rept    4
        endm
        db      1
        endm
        hollow
        hollow
        hollow
        hollow
later   macro
        db      2
        endm
        later
        ret
