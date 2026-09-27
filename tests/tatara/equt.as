; EQU gives a name one value, and may say so twice
foo equ 7
bar equ foo+1
    if  bar eq 8
    db  1
    endif
foo equ 7
    db  2
    ret
