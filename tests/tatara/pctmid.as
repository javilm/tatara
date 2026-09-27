; "%" is special only as an argument's FIRST character
show    macro   n
    db  n
    endm
    show    100%3
    ret
