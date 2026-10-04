; limg.inc - public interface of limg.as: the image being built.
;
; THE IMAGE IS NEVER IN THE TPA. [R11] asks for a 64 KB .ROM to be
; possible, and 64 KB of image cannot live in a 64 KB address space
; that already holds MSX-DOS, TANREN and its tables. So the image is
; sixteen blocks of 4 KB in mapper RAM, indexed by WHICH 4 KB OF THE
; ADDRESS SPACE they hold, and a block is created the first time
; something is written into it.
;
; NOTHING HERE SAYS WHERE THE OUTPUT STARTS. Bytes are written at the
; addresses they will load at - 0100h for a .COM, 4000h for a
; cartridge driver, 8000h for a block that will be banked - and image_low
; and image_high are MEASURED afterwards. That is decision 8's answer:
; absolute content is written where it says.

		ifndef	LIMG_INCLUDED

		extrn image_init		; an empty image: every block
					; unallocated, nothing written
		extrn image_write_run		; a run of content
					; in:  HL = the address it loads
					;      at
					;      DE -> the bytes, in
					;      ordinary RAM
					;      BC = how many
					; (error_image_too_big,
					; error_out_of_memory do not
					; return)
		extrn image_read_byte		; one byte out of the image
					; in:  HL = its address
					; out: A  = the byte, or 0 where
					;      nothing was ever written
		extrn image_write_byte		; one byte into it
					; in:  A  = the byte
					;      HL = its address
		extrn image_save		; the image, to a file
					; in:  DE -> the ASCIIZ name
					;      A  = 0 for raw bytes,
					;      anything else for a
					;      seven-byte BLOAD header
					;      HL = the execution address
					;      that header carries
					; out: CY set = there was nothing
					;      to write
					; (error_cannot_create,
					; error_cannot_write do not
					; return)
		extrn image_low		; the lowest address written,
		extrn image_high		;   the highest, and
		extrn image_any		;   0 = nothing was written at
					;   all
		endif

					; bytes in one block. NOT 16384:
					; halloc's
IMAGE_BLOCK_SIZE		equ	4096
				; largest payload is 16372 (alloc.inc),
				; four bytes short of a mapper segment, so
				; a 16 KB block cannot be asked for - and
				; two 8 KB blocks do not fit in one segment
				; either, so a full 64 KB image would cost
				; eight segments. Three 4 KB blocks fit in
				; one, so the same image costs six. 4096 is
				; also a shift and not a division: the
				; block is the address's top nibble
					; 16 * 4096 = the whole address space
IMAGE_BLOCK_COUNT		equ	16
					; the high byte's low nibble is the
IMAGE_OFFSET_MASK		equ	00fh
				; offset within a block; its high nibble
				; is which block
IMAGE_CHUNK_SIZE equ	256	; how much goes to disk per _WRITE.
				;   It is also exactly
				;   OBJFILE_STRING_SIZE, which is what
				;   lets image_save borrow
				;   objfile_string_buffer
