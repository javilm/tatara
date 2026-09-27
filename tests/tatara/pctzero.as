; zero is a digit, not an empty argument
show    macro   n
    db  n
    endm
    show    %0
    ret
