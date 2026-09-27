; hash.inc - public interface of hash.as (hash table library).
; IX = table descriptor for every routine; IX is always preserved.
;
; hash.as includes this file too, for the shared equates: it defines
; HASHLIB first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	HASHLIB
		extrn htinit
		extrn hthash
		extrn htadd
		extrn htfind
		extrn htdel
		extrn htclear
		extrn htnext
		extrn htrepl
		endif

HTCASES		equ	0	; case mode: sensitive
HTCASEI		equ	1	; case mode: fold a-z to A-Z

; descriptor layout (the caller only sizes the descriptor; the fields
; are the library's):
HT_CASE		equ	0	; +0 case mode
HT_MASK		equ	1	; +1 bucket mask (count-1)
HT_TAB		equ	2	; +2 the bucket index (count farptrs)

; record layout (parse htnext results with these):
HT_NEXT		equ	0	; +0 next far pointer (4)
HT_KLEN		equ	4	; +4 key length (1)
HT_KEY		equ	5	; +5 key bytes
HTHDR		equ	5	; payload starts at HTHDR + klen
