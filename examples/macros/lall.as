; LALL.AS - the same program, listed in full.
;
; .LALL asks for every line of every macro expansion, including the
; ones that produce no bytes. The default is .XALL, which keeps only
; the lines that emitted something. Nothing else here differs from
; MACROS.AS, so the two listings differ only in what they show.

		.lall
		include	macros.as
