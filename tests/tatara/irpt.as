; before
        irp     r,<hl,de,bc>
        push    r
        endm
        irpc    n,123
        db      n
        endm
        irpc    n,<456>
        db      n
        endm
        irp     x,<1,,3>
        db      x+0
        endm
        irp     n,<4,5>
        local   l
l:      db      n
        djnz    l
        endm
        ret
