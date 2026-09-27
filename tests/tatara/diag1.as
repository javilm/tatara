; before
inner   macro   v
        if      v+nosuch
        endif
        endm
outer   macro
        inner   1
        endm
        outer
        ret
