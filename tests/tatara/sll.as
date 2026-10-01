; sll.as - SLL, the undocumented eighth row of the CB group: shift
; left, and set bit 0. CB 30 to CB 37, with the indexed forms through
; DD CB d 36 like every other member of the group.
;
; NEITHER ORACLE HAS IT. M80 does not know SLL, and SOLiD AS refuses
; sll, sl1 and slia alike - so openMSX's disassembler is the only
; authority on the name, and it says SLL. 101 has the runs.
;
; AND THE R800 DOES NOT DO IT. Measured in openMSX on 2026-10-02: CB 30
; with B = 81h leaves 03h on a Z80 and 02h on an R800, which is SLA.
; The carry is set either way, so only the low bit tells. Tatara
; assembles it on any machine - what the source says does not depend on
; what the assembler runs on - and the manual carries the warning.

t0:	sll	b
t1:	sll	c
t2:	sll	d
t3:	sll	e
t4:	sll	h
t5:	sll	l
t6:	sll	(hl)
t7:	sll	a
t8:	sll	(ix+5)
t9:	sll	(iy-1)
ta:	nop
	end
