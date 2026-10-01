; inoutu.as - the two undocumented rows of the IN/OUT group. ED 70 is
; IN F,(C) and ED 71 is OUT (C),0: register code 6, the slot (HL)
; fills in every other instruction with a register field, and the one
; code in the ED group that names no register.
;
; NEITHER ORACLE HAS THEM. M80 knows neither, and SOLiD AS refuses
; in f,(c), in (c) and out (c),0 alike - 101 has the runs. openMSX
; disassembles the two bytes as the two names, and z80-documented
; v0.91 lists them.
;
; WHAT THEY DO, measured in openMSX on 2026-10-02 with a sentinel in
; PSG register 0, read back through port 0A2h:
;
;   IN F,(C) leaves A alone and sets the flags exactly as the IN r,(C)
;   beside it does - Z80 F=A8 for a value of A8h, R800 F=80. The
;   documented IN A,(C) answers the same two on the same machines, so
;   ED 70 is not a special case: the R800 does not maintain the
;   undocumented bits for any IN r,(C).
;
;   OUT (C),0 WROTE FFh, not 0, on both cores. The document says 0;
;   the published split is NMOS 0 and CMOS FFh. A program may not rely
;   on the value.
;
; The operand of OUT (C),0 is the literal digit and not an expression:
; 00h is a word that matches no row and is refused. IN (C) is not
; accepted either - one spelling per byte.

t0:	in	f,(c)
t1:	out	(c),0
t2:	in	a,(c)
t3:	out	(c),a
t4:	nop
	end
