; the /S dump: one of every kind of symbol, and TWO LABELS AT ONE
; ADDRESS - which is the tie-break, and what loops forever without one
    extrn   deref
    public  sdpub
    public  sdnodef
two equ 2
five    equ 5
sdvar   defl 7
    cseg
sdpub:  db  1
same1:
same2:  db  2
    db  3
    dseg
sddata: db  0
    dseg    scratch,transient
    group   work
scr1:   ds  4
    cseg    empty
    ds  2
    end
