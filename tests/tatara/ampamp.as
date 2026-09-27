; before
mkerr   macro   sfx
err&sfx macro   y
lbl&&y: db      '&&y'
        endm
        endm
        mkerr   a
        erra    7
        ret
