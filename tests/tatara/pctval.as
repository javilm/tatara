; the manual's own example: %expr is a macro call BY VALUE
maklab  macro   y
err&y:  db  'Error &y',0
    endm
makerr  macro   x
lb  defl 0
    rept    x
lb  defl lb+1
    maklab  %lb
    endm
    endm
    makerr  3
    ret
