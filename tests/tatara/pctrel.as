; % needs a value the linker does not have to finish
show    macro   n
    db  n
    endm
lab:    ds  1
    show    %lab
    ret
