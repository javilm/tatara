; before
        irp     x,<>
        db      0aah
        endm
        irpc    c,<>
        db      0bbh
        endm
        ret
