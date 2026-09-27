; five digits: the longest a % argument can become
show    macro   n
    db  n
    endm
big defl 65535
    show    %big
    ret
