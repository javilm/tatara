; before
mkpoke  macro   sfx,reg
poke&sfx macro  addr
        ld      (addr),reg
        endm
        endm
        mkpoke  hl,hl
        mkpoke  de,de
        pokehl  4000h
        pokede  8000h
        ret
