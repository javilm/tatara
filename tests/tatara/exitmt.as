; before
maybe   macro   x
        ifb     <x>
        db      0aah
        exitm
        endif
        db      0bbh
        endm
        maybe
        maybe   1
        rept    3
        db      0cch
        exitm
        endm
        ret
