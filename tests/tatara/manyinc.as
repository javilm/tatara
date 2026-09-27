; the file-name table counts OPENINGS, not distinct files, so
; twenty includes of one file fill twenty-one entries and cost two
; files on the disk
	aseg
	org	0
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
	include	oneline.inc
t0:	nop
	end
