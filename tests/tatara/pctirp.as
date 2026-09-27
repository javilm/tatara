; an IRP item list is built by the same routine, so % works there too
big defl 7
    irp x,<%big,2>
    db  x
    endm
    ret
