; before
regs    macro   which
        irp     r,which
        push    r
        endm
        endm
        regs    <hl,de>
        rept    2
        irpc    n,12
        db      n
        endm
        endm
        ret
