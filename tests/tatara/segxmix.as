; a named segment and the classic CSEG are two different segments
c1: ds  1
    cseg    music
m1: ds  1
x   defl m1-c1
