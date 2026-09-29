rem TESTS.BAT - run every test in the program, hand the results back
rem and clean up. No M80.
rem
rem THE M80 LISTINGS ARE STILL HERE, in M80REF\, one per cross-checked
rem test. They are what M80 wrote, frozen: M80 never changes, so a
rem snapshot of its answer is as good an oracle as the binary, and
rem cmpm80.py compares the two listings out of RESULTS.TXT exactly as
rem it did before. What goes is the DEPENDENCY - Microsoft owns M80
rem and it cannot be distributed with this.
rem
rem Everything lands in RESULTS.TXT: run this, then send that one file.
rem
rem Redirection, not Tatara's own output file. Error messages go to the
rem screen through BDOS _STROUT, not into the file Tatara writes, and
rem half of these tests ARE error messages. Redirecting standard output
rem catches the expanded lines, the summary, the /M dump and the errors
rem in one place.

rem The previous run, kept: RESULTS.OLD is what tells one line of
rem difference from a rewritten test file. It used to be a hand copy,
rem and it had gone four phases stale.

if exist results.txt copy results.txt results.old

echo TATARA TEST RUN > results.txt

rem A TATARA.COM here would be run in preference to the one on the
rem PATH, because MSX-DOS looks in the current directory first. That
rem happened once and cost a whole run: a stale binary produced .TRO
rem files full of source text, and no errors where errors were
rem expected. The build had made the right one all along.

if exist tatara.com echo *** WARNING: a TATARA.COM in this directory shadows the real one >> results.txt

rem --- the conditional structure

echo === THE BANNER (no /Q, so it prints) >> results.txt
tatara objsmall.as objsmall.tro >> results.txt
echo === /V (expect the banner and nothing else) >> results.txt
tatara /v >> results.txt
echo === /Q /V (expect the banner: /V asked for it) >> results.txt
tatara /q /v >> results.txt
echo === /? (expect the usage screen, 22 lines) >> results.txt
tatara /? >> results.txt

echo === COND.AS (expect 6 lines, 22 total) >> results.txt
tatara /q /p cond.as >> results.txt

echo === NESTIF.AS (expect db 4 only) >> results.txt
tatara /q /p nestif.as >> results.txt

echo === CONDINC.AS (expect no error at all) >> results.txt
tatara /q /p condinc.as >> results.txt

echo === CONDMAC.AS (expect not a directive, a macro or an instruction, line 7) >> results.txt
tatara /q /p condmac.as >> results.txt

echo === CONDMAC.AS /M (expect the same error, and so NO macro dump) >> results.txt
tatara /q /p /m condmac.as >> results.txt

echo === NOENDIF.AS (expect the error ALONE - pass 1 emits nothing) >> results.txt
tatara /q /p noendif.as >> results.txt

echo === BADELSE.AS (expect ELSE or ENDIF without IF) >> results.txt
tatara /q /p badelse.as >> results.txt

echo === TWOELSE.AS (expect the error alone) >> results.txt
tatara /q /p twoelse.as >> results.txt

echo === DEEPIF.AS (expect nested too deeply) >> results.txt
tatara /q /p deepif.as >> results.txt

rem --- expressions

echo === EXPR.AS (expect db 1 to db 7) >> results.txt
tatara /q /p expr.as >> results.txt

echo === ASSOC.AS (expect db 1 to db 6, NO db 0ffh) >> results.txt
tatara /q /p assoc.as >> results.txt

echo === DEFLT.AS (expect 11h 22h 33h in that order) >> results.txt
tatara /q /p deflt.as >> results.txt

echo === UNDEF.AS (expect undefined symbol) >> results.txt
tatara /q /p undef.as >> results.txt

echo === BADEXPR.AS (expect bad expression) >> results.txt
tatara /q /p badexpr.as >> results.txt

echo === BADBASE.AS (expect bad expression) >> results.txt
tatara /q /p badbase.as >> results.txt

rem --- REPT

echo === REPTT.AS (expect 1,1,1 ??0000 ??0001 2x4 3x2) >> results.txt
tatara /q /p reptt.as >> results.txt

echo === REPTUND.AS (expect undefined symbol) >> results.txt
tatara /q /p reptund.as >> results.txt

echo === REPTNOE.AS (expect not closed by ENDM) >> results.txt
tatara /q /p reptnoe.as >> results.txt

echo === REPTLEAK.AS /M (expect the dump, no heap error) >> results.txt
tatara /q /p /m reptleak.as >> results.txt

echo === REPTMT.AS /M (expect db 1 x4, db 2, 3 macros dumped) >> results.txt
tatara /q /p /m reptmt.as >> results.txt

rem --- IRP and IRPC

echo === IRPT.AS (expect hl/de/bc, 1-6, 1+0//+0/3+0, 4/5) >> results.txt
tatara /q /p irpt.as >> results.txt

echo === IRPNULL.AS (expect db 0aah ONCE, no db 0bbh) >> results.txt
tatara /q /p irpnull.as >> results.txt

echo === IRPLONG.AS (expect db 1 to db 20, and a to t) >> results.txt
tatara /q /p irplong.as >> results.txt

echo === IRPMAC.AS (expect push hl/de then 1,2,1,2) >> results.txt
tatara /q /p irpmac.as >> results.txt

echo === IRPAMP.AS (expect db 'a' db 'b' db 'c') >> results.txt
tatara /q /p irpamp.as >> results.txt

echo === IRPBAD.AS (expect bad macro parameter list) >> results.txt
tatara /q /p irpbad.as >> results.txt

rem --- nested definitions and EXITM

echo === NESTED.AS (expect ld (4000h),hl and ld (8000h),de) >> results.txt
tatara /q /p nested.as >> results.txt

echo === NESTED.AS /M (expect mkpoke, pokehl, pokede) >> results.txt
tatara /q /p /m nested.as >> results.txt

echo === AMPAMP.AS (expect lbl7: db '7') >> results.txt
tatara /q /p ampamp.as >> results.txt

echo === EXITMT.AS (expect 0aah, 0bbh, ONE 0cch, no error) >> results.txt
tatara /q /p exitmt.as >> results.txt

echo === EXITMBAD.AS (expect EXITM outside a macro) >> results.txt
tatara /q /p exitmbad.as >> results.txt

rem --- lifetimes and leaks

echo === REDEF.AS (expect helper: nop / ret ONCE) >> results.txt
tatara /q /p redef.as >> results.txt

echo === REDEF.AS /M (expect grab twice: 6 lines then 1) >> results.txt
tatara /q /p /m redef.as >> results.txt

echo === HEAP1.AS /H (10 rounds - note the block count) >> results.txt
tatara /q /p /h heap1.as >> results.txt

echo === HEAP2.AS /H (200 rounds - MUST be the same count) >> results.txt
tatara /q /p /h heap2.as >> results.txt

rem --- diagnostics

echo === DIAG1.AS (expect 2 trail lines, INNER then OUTER) >> results.txt
tatara /q /p diag1.as >> results.txt

echo === DIAG2.AS (expect a repeat block, then WRAP) >> results.txt
tatara /q /p diag2.as >> results.txt

echo === DIAG3.AS (expect not closed, at line 6 not line 8) >> results.txt
tatara /q /p diag3.as >> results.txt

echo === DIAGINC.AS (expect DIAGSUB.INC(2) then DIAGINC.AS(3)) >> results.txt
tatara /q /p diaginc.as >> results.txt

echo === DIAGRDF.AS (expect: in a redefined macro) >> results.txt
tatara /q /p diagrdf.as >> results.txt

echo === INCTRL.AS (expect INCTRL1.INC then INCTRL.AS, both included from) >> results.txt
tatara /q /p inctrl.as >> results.txt

echo === INCTRLM.AS (expect called from, then ONE included from) >> results.txt
tatara /q /p inctrlm.as >> results.txt

echo === NESTMISS.AS (expect cannot open, then MIDMISS.INC and NESTMISS.AS) >> results.txt
tatara /q /p nestmiss.as >> results.txt

rem --- the symbol table

echo === SYMLONG.AS (expect db 1, 2, 31, 32, 33, 120, 240) >> results.txt
tatara /q /p symlong.as >> results.txt

echo === SYMREDEF.AS /H (expect db 10, and ONE block per symbol) >> results.txt
tatara /q /p /h symredef.as >> results.txt

echo === SYMCASE.AS (expect 0bbh, then 0cch from BAR) >> results.txt
tatara /q /p symcase.as >> results.txt

echo === SYMCASE.AS /C (expect 0aah, then BAR unknown - line 13) >> results.txt
tatara /q /p /c symcase.as >> results.txt

echo === SYMMANY.AS /H (2000 symbols - no /P, the defls would be 2000 lines) >> results.txt
tatara /q /h symmany.as symmany.prn >> results.txt

rem --- the expression parser stops copying

rem --- two passes, and the location counter

echo === PASSIF.AS (expect db 2 only - output comes from pass 2) >> results.txt
tatara /q /p passif.as >> results.txt

echo === LOCCTR.AS (expect db 1 and db 2) >> results.txt
tatara /q /p locctr.as >> results.txt

echo === MACPASS.AS (expect not a directive, a macro or an instruction, line 4) >> results.txt
tatara /q /p macpass.as >> results.txt

rem --- ASEG, CSEG, DSEG, and relocatable values

echo === SEGS.AS (expect db 1 to db 6, all six) >> results.txt
tatara /q /p segs.as >> results.txt

echo === RELMUL.AS (expect relocation error, line 3) >> results.txt
tatara /q /p relmul.as >> results.txt

echo === RELADD.AS (expect relocation error, line 4) >> results.txt
tatara /q /p reladd.as >> results.txt

echo === RELMIX.AS (expect relocation error, line 5) >> results.txt
tatara /q /p relmix.as >> results.txt

echo === RELHIGH.AS (expect relocation error, line 3) >> results.txt
tatara /q /p relhigh.as >> results.txt

echo === RELDS.AS (expect relocation error, line 3) >> results.txt
tatara /q /p relds.as >> results.txt

echo === RELORG.AS (expect relocation error, line 5) >> results.txt
tatara /q /p relorg.as >> results.txt

rem --- named segments, transient DSEGs and groups

echo === SEGNAME.AS (expect db 1, db 2 and db 3) >> results.txt
tatara /q /p segname.as >> results.txt

echo === TRANSNT.AS (expect db 1, db 2 and db 3) >> results.txt
tatara /q /p transnt.as >> results.txt

echo === SEGFLG.AS (expect declared differently, line 3) >> results.txt
tatara /q /p segflg.as >> results.txt

echo === SEGNGRP.AS (expect needs a GROUP first, line 3) >> results.txt
tatara /q /p segngrp.as >> results.txt

echo === SEGGRPX.AS (expect GROUP outside transient, line 3) >> results.txt
tatara /q /p seggrpx.as >> results.txt

echo === SEGTRAN.AS (expect bad segment line, line 2) >> results.txt
tatara /q /p segtran.as >> results.txt

echo === SEGASEG.AS (expect bad segment line, line 2) >> results.txt
tatara /q /p segaseg.as >> results.txt

echo === SEGXMIX.AS (expect relocation error, line 5) >> results.txt
tatara /q /p segxmix.as >> results.txt

echo === GRPMIX.AS (expect relocation error, line 7) >> results.txt
tatara /q /p grpmix.as >> results.txt

rem --- % - a macro call by value

echo === PCTVAL.AS (expect Error 1, Error 2, Error 3) >> results.txt
tatara /q /p pctval.as >> results.txt

echo === PCT5.AS (expect db 65535) >> results.txt
tatara /q /p pct5.as >> results.txt

echo === PCTZERO.AS (expect db 0) >> results.txt
tatara /q /p pctzero.as >> results.txt

echo === PCTMID.AS (expect db 100 percent 3 as text) >> results.txt
tatara /q /p pctmid.as >> results.txt

echo === PCTIRP.AS (expect db 7 then db 2) >> results.txt
tatara /q /p pctirp.as >> results.txt

echo === PCTREL.AS (expect relocation error, line 6) >> results.txt
tatara /q /p pctrel.as >> results.txt

echo === PCTUND.AS (expect undefined symbol, line 5) >> results.txt
tatara /q /p pctund.as >> results.txt

rem --- EQU, PUBLIC, EXTRN, END

echo === EQUT.AS (expect db 1 and db 2) >> results.txt
tatara /q /p equt.as >> results.txt

echo === EQUM.AS (expect already has a value, line 3) >> results.txt
tatara /q /p equm.as >> results.txt

echo === LABM.AS (expect already has a value, line 3) >> results.txt
tatara /q /p labm.as >> results.txt

echo === LABIND.AS /S (expect top 0, bare 2, mid 4, pub 6, only 8) >> results.txt
tatara /q /p /s labind.as >> results.txt

echo === LABIND.AS /F (expect mid, pub and only in the label field) >> results.txt
tatara /q /p /f labind.as >> results.txt

echo === EQUSET.AS (expect already has a value, line 3) >> results.txt
tatara /q /p equset.as >> results.txt

echo === PUBT.AS /S (expect FOO and BAR, both public) >> results.txt
tatara /q /p /s pubt.as >> results.txt

echo === PUBCC.AS /S (expect TWO and IND public, ONE not) >> results.txt
tatara /q /p /s pubcc.as >> results.txt

echo === COLNEQ.AS (expect a name, not a label, line 4) >> results.txt
tatara /q /p colneq.as >> results.txt

echo === COLNDF.AS (expect a name, not a label, line 3) >> results.txt
tatara /q /p colndf.as >> results.txt

echo === COLNMAC.AS (expect a name, not a label, line 4) >> results.txt
tatara /q /p colnmac.as >> results.txt

echo === EXTT.AS /S (expect E1 = 0 and E2 = 1, both external) >> results.txt
tatara /q /p /s extt.as >> results.txt

echo === EXTDEF.AS (expect already has a value, line 3) >> results.txt
tatara /q /p extdef.as >> results.txt

echo === EXTMUL.AS (expect external not allowed, line 3) >> results.txt
tatara /q /p extmul.as >> results.txt

echo === EXTEQU.AS (expect external not allowed, line 3) >> results.txt
tatara /q /p extequ.as >> results.txt

echo === ENDT.AS (expect db 1 only) >> results.txt
tatara /q /p endt.as >> results.txt

echo === ENDADDR.AS (expect no error and no db 2) >> results.txt
tatara /q /p endaddr.as >> results.txt

rem --- DB, DW and DC - the size of a line

echo === DBT.AS /S (expect A 0, B 3, C 4, D 7) >> results.txt
tatara /q /p /s dbt.as >> results.txt

echo === DBSTR.AS /S (expect A 0, B 2, C 5, D 6, E 6) >> results.txt
tatara /q /p /s dbstr.as >> results.txt

echo === DBMIX.AS /S (expect A 0, B 2, C 3, D 7, E 9) >> results.txt
tatara /q /p /s dbmix.as >> results.txt

echo === DBQUOT.AS /S (expect A 0, B 18, C 22) >> results.txt
tatara /q /p /s dbquot.as >> results.txt

echo === DBFWD.AS /S (expect A 0, B 1, LATER 3) >> results.txt
tatara /q /p /s dbfwd.as >> results.txt

echo === DWT.AS /S (expect A 0, B 4, C 6, D 8) >> results.txt
tatara /q /p /s dwt.as >> results.txt

echo === DWSTR.AS (expect bad DB, DW or DC operand, line 2) >> results.txt
tatara /q /p dwstr.as >> results.txt

echo === DCT.AS /S (expect A 0, B 3) >> results.txt
tatara /q /p /s dct.as >> results.txt

echo === DCBAD.AS (expect bad operand, line 2) >> results.txt
tatara /q /p dcbad.as >> results.txt

echo === DCEXP.AS (expect bad operand, line 2) >> results.txt
tatara /q /p dcexp.as >> results.txt

echo === DBBAD.AS (expect bad operand, line 2) >> results.txt
tatara /q /p dbbad.as >> results.txt

echo === DBOPEN.AS (expect bad operand, line 2) >> results.txt
tatara /q /p dbopen.as >> results.txt

echo === DBSEG.AS (expect needs a GROUP first, line 3) >> results.txt
tatara /q /p dbseg.as >> results.txt

rem --- the instruction table, and the classes with no operands

echo === INSN1.AS /S (expect A 0 to I 8, one byte each) >> results.txt
tatara /q /p /s insn1.as >> results.txt

echo === INSN2.AS /S (expect A 0, B 2, C 4, D 6, E 8, F 10) >> results.txt
tatara /q /p /s insn2.as >> results.txt

echo === INSNMIX.AS /S (expect A 0, B 1, C 3, D 4, E 6) >> results.txt
tatara /q /p /s insnmix.as >> results.txt

echo === INSNEXT.AS (expect not a form this instruction has, line 2) >> results.txt
tatara /q /p insnext.as >> results.txt

echo === INSNSEG.AS (expect needs a GROUP first, line 3) >> results.txt
tatara /q /p insnseg.as >> results.txt

echo === APOST.AS /F (expect the comment in its own bracket) >> results.txt
tatara /q /p /f apost.as >> results.txt

rem --- the operand parser, and the one-operand classes

echo === INSN3.AS /S (expect T0 0, T1 1, T2 2, T3 5, T4 7, T5 10) >> results.txt
tatara /q /p /s /l insn3.as >> results.txt

echo === INSN4.AS /S (expect T0 0, T1 1, T2 2, T3 4, T4 6, T5 8, T6 10, T7 13) >> results.txt
tatara /q /p /s /l insn4.as >> results.txt

echo === INSN5.AS /S (expect T0 0, T1 1, T2 2, T3 5, T4 6, T5 8, T6 9, T7 11, T8 12) >> results.txt
tatara /q /p /s /l insn5.as >> results.txt

echo === INSN6.AS /S (expect T0 0 to T4 4, T5 5) >> results.txt
tatara /q /p /s /l insn6.as >> results.txt

echo === INSNPAR.AS /S (expect T0 0, T1 2) >> results.txt
tatara /q /p /s /l insnpar.as >> results.txt

echo === INSNALU.AS (expect not a form, line 2 - "add b,c") >> results.txt
tatara /q /p insnalu.as >> results.txt

echo === INSNIX.AS (expect not a form, line 2) >> results.txt
tatara /q /p insnix.as >> results.txt

echo === INSNIXY.AS (expect not a form, line 2) >> results.txt
tatara /q /p insnixy.as >> results.txt

echo === INSNSP.AS (expect not a form, line 2) >> results.txt
tatara /q /p insnsp.as >> results.txt

echo === INSNRST.AS (expect not a form, line 2) >> results.txt
tatara /q /p insnrst.as >> results.txt

rem --- LD, and the operand parser that can see everything

echo === LDT1.AS /S (expect T0 0, T1 1, T2 2, T3 3, T4 5, T5 7) >> results.txt
tatara /q /p /s /l ldt1.as >> results.txt

echo === LDT2.AS /S (expect T0 0, T1 3, T2 6, T3 10) >> results.txt
tatara /q /p /s /l ldt2.as >> results.txt

echo === LDT3.AS /S (expect T0 0, T1 1, T2 2, T3 5, T4 8, T5 10, T6 12) >> results.txt
tatara /q /p /s /l ldt3.as >> results.txt

echo === LDT4.AS /S (expect T0 0, T1 3, T2 7, T3 10, T4 14, T5 17, T6 21, T7 22, T8 24) >> results.txt
tatara /q /p /s /l ldt4.as >> results.txt

echo === LDQUOTE.AS /S (expect T0 0, T1 3) >> results.txt
tatara /q /p /s /l ldquote.as >> results.txt

echo === LDCOMMA.AS (expect not a form, line 2 - "cp 1,2") >> results.txt
tatara /q /p ldcomma.as >> results.txt

echo === LDBAD1.AS (expect not a form, line 2) >> results.txt
tatara /q /p ldbad1.as >> results.txt

echo === LDBAD2.AS (expect not a form, line 2) >> results.txt
tatara /q /p ldbad2.as >> results.txt

echo === LDBAD3.AS (expect not a form, line 2) >> results.txt
tatara /q /p ldbad3.as >> results.txt

echo === LDBAD4.AS (expect not a form, line 2) >> results.txt
tatara /q /p ldbad4.as >> results.txt

echo === LDBAD5.AS (expect not a form, line 2) >> results.txt
tatara /q /p ldbad5.as >> results.txt

rem --- the jumps, the CB group, and the rest of the instruction set

echo === JPT.AS /S (expect T0 0, T1 3, T2 6, T3 9, T4 10, T5 12, T6 14) >> results.txt
tatara /q /p /s /l jpt.as >> results.txt

echo === JRT.AS /S (expect T0 0, T1 2, T2 4, T3 6, T4 8, T5 11, T6 14, T7 17) >> results.txt
tatara /q /p /s /l jrt.as >> results.txt

echo === CBT.AS /S (expect T0 0, T1 2, T2 4, T3 6, T4 10, T5 12, T6 14, T7 18) >> results.txt
tatara /q /p /s /l cbt.as >> results.txt

echo === SETBIT.AS /S (expect T0 0, T1 4, T2 6, FOO 7) >> results.txt
tatara /q /p /s /l setbit.as >> results.txt

echo === EXCHG.AS /S (expect T0 0, T1 1, T2 2, T3 3, T4 5, T5 7) >> results.txt
tatara /q /p /s /l exchg.as >> results.txt

echo === INOUT.AS /S (expect T0 0, T1 2, T2 4, T3 6, T4 8, T5 10) >> results.txt
tatara /q /p /s /l inout.as >> results.txt

echo === R800T.AS /S (expect T0 0, T1 2, T2 4, T3 6, T4 8) >> results.txt
tatara /q /p /s /l r800t.as >> results.txt

echo === CPAREN.AS /S (expect T0 0, T1 3, T2 5, C 5) >> results.txt
tatara /q /p /s /l cparen.as >> results.txt

echo === JPBAD.AS (expect not a form, line 2 - "jp (ix+5)") >> results.txt
tatara /q /p jpbad.as >> results.txt

echo === JPBAD2.AS (expect not a form, line 2) >> results.txt
tatara /q /p jpbad2.as >> results.txt

echo === JRBAD.AS (expect not a form, line 2 - "jr po,nn") >> results.txt
tatara /q /p jrbad.as >> results.txt

echo === CBBAD.AS (expect not a form, line 2) >> results.txt
tatara /q /p cbbad.as >> results.txt

echo === EXBAD1.AS (expect not a form, line 2) >> results.txt
tatara /q /p exbad1.as >> results.txt

echo === EXBAD2.AS (expect not a form, line 2) >> results.txt
tatara /q /p exbad2.as >> results.txt

echo === EXBAD3.AS (expect not a form, line 2) >> results.txt
tatara /q /p exbad3.as >> results.txt

echo === INBAD.AS (expect not a form, line 2) >> results.txt
tatara /q /p inbad.as >> results.txt

echo === OUTBAD.AS (expect not a form, line 2) >> results.txt
tatara /q /p outbad.as >> results.txt

echo === MULBAD1.AS (expect not a form, line 2) >> results.txt
tatara /q /p mulbad1.as >> results.txt

echo === MULBAD2.AS (expect not a form, line 2) >> results.txt
tatara /q /p mulbad2.as >> results.txt

echo === NOOP.AS (expect not a directive, a macro or an instruction, line 3) >> results.txt
tatara /q /p noop.as >> results.txt

rem --- the emitter, the listing, and the first bytes

echo === EMDB.AS /L (expect 01 02 03 / 61 62 63 / 42 / 34 12 / 42 41) >> results.txt
tatara /q /p /l emdb.as >> results.txt

echo === EMQUOTE.AS /L (expect 69 74 27 73, then 27) >> results.txt
tatara /q /p /l emquote.as >> results.txt

echo === EMDC.AS /L (expect 61 62 E3, then E1) >> results.txt
tatara /q /p /l emdc.as >> results.txt

echo === EMFWD.AS /L (expect 03 00 - LATER survived pass 1) >> results.txt
tatara /q /p /l emfwd.as >> results.txt

echo === EMREL.AS /L (expect 00 00, both addresses relocatable) >> results.txt
tatara /q /p /l emrel.as >> results.txt

echo === EMRELB.AS (expect a relocatable value where none is allowed) >> results.txt
tatara /q /p emrelb.as >> results.txt

echo === EMDB.AS (expect NO columns - /L is a switch) >> results.txt
tatara /q /p emdb.as >> results.txt

rem --- the simple classes, and the first instructions to encode

echo === SIMPLE1.AS /L (expect 00 76 D9 ED 44 ED B0 ED BB) >> results.txt
tatara /q /p /l simple1.as >> results.txt

echo === SIMPLE2.AS /L (expect A0 A6 DD A6 05 E6 07 BF FD AE FF) >> results.txt
tatara /q /p /l simple2.as >> results.txt

echo === SIMPLE3.AS /L (expect 80 19 ED 5A ED 72 DD 09 DD 29 DD 8E 00) >> results.txt
tatara /q /p /l simple3.as >> results.txt

echo === SIMPLE4.AS /L (expect 04 35 DD 34 01 03 FD 2B F5 DD E1) >> results.txt
tatara /q /p /l simple4.as >> results.txt

echo === SIMPLE5.AS /L (expect C9 C8 F8 FF ED 46 ED 56 ED 5E) >> results.txt
tatara /q /p /l simple5.as >> results.txt

echo === SIMPLE6.AS /L (expect ED C1 ED D9 ED C3 ED F3 - no oracle) >> results.txt
tatara /q /p /l simple6.as >> results.txt

echo === UPLUS.AS /L (expect 01 / 34 12 / DD A6 05 / DD A6 FB) >> results.txt
tatara /q /p /l uplus.as >> results.txt

echo === RSTBAD1.AS (expect RST takes 0, 8, 10h..., line 2) >> results.txt
tatara /q /p rstbad1.as >> results.txt

echo === RSTBAD2.AS (expect the same, line 2) >> results.txt
tatara /q /p rstbad2.as >> results.txt

echo === IMBAD.AS (expect IM takes 0, 1 or 2, line 2) >> results.txt
tatara /q /p imbad.as >> results.txt

echo === DISPBAD1.AS (expect displacement -128 to 127, line 2) >> results.txt
tatara /q /p dispbad1.as >> results.txt

echo === DISPBAD2.AS (expect the same, line 2) >> results.txt
tatara /q /p dispbad2.as >> results.txt

rem --- LD, and the eighteen forms

echo === LD1.AS /L (expect 41 46 70 06 05 36 05 0A 1A 02 12 00) >> results.txt
tatara /q /p /l ld1.as >> results.txt

echo === LD2.AS /L (expect DD 46 05 DD 70 05 DD 36 05 42) >> results.txt
echo ===   then FD 4E FF FD 71 FF DD 7E 00 00 >> results.txt
tatara /q /p /l ld2.as >> results.txt

echo === LD3.AS /L (expect 01 34 12 31 34 12 2A 34 12 ED 5B 34 12) >> results.txt
echo ===   then ED 7B 34 12 F9 DD F9 DD 21 34 12 FD 2A 34 12 00 >> results.txt
tatara /q /p /l ld3.as >> results.txt

echo === LD4.AS /L (expect 32 34 12 22 34 12 ED 43 34 12) >> results.txt
echo ===   then ED 73 34 12 DD 22 34 12 3A 34 12 00 >> results.txt
tatara /q /p /l ld4.as >> results.txt

echo === LD5.AS /L (expect ED 57 ED 5F ED 47 ED 4F 00) >> results.txt
tatara /q /p /l ld5.as >> results.txt

echo === LD6.AS /L (expect 21 06 00 32 06 00 00, addresses marked) >> results.txt
tatara /q /p /l ld6.as >> results.txt

rem --- the jumps, the CB group, and the last nine classes

echo === JRDISP.AS /L (expect 18 00 18 FC 10 FE 20 00 38 FC 00) >> results.txt
tatara /q /p /l jrdisp.as >> results.txt

echo === JRFAR.AS (expect a JR or DJNZ can only reach, line 6) >> results.txt
tatara /q /p jrfar.as >> results.txt

echo === BITBAD.AS (expect a bit number must be 0 to 7, line 5) >> results.txt
tatara /q /p bitbad.as >> results.txt

echo === JRSEG.AS (expect a relocation error, line 5 - M80 decides) >> results.txt
tatara /q /p jrseg.as >> results.txt

rem --- the file-name table

echo === MANYINC.AS /L (expect twenty 01s and a 00) >> results.txt
tatara /q /p /l manyinc.as >> results.txt

echo === MANYBAD.AS (expect too many different source files, line 36) >> results.txt
tatara /q /p manybad.as >> results.txt

rem --- character constants in either delimiter

echo === QUOTES.AS /L (expect FE 20 FE 41 FE 41 21 42 41 22 27 00) >> results.txt
tatara /q /p /l quotes.as >> results.txt

rem --- a line whose bytes do not fit the column

echo === WRAP.AS /L (expect 20 bytes on THREE lines, then 00) >> results.txt
tatara /q /p /l wrap.as >> results.txt

rem --- the object file exists

echo === OBJSMALL.AS to OBJSMALL.TRO (48 bytes: 047 gave it its nop) >> results.txt
tatara /q objsmall.as objsmall.tro >> results.txt

rem --- the records the linker's first pass reads

echo === OBJFULL.AS to OBJFULL.TRO (78 bytes: 048 added its RELOC) >> results.txt
tatara /q objfull.as objfull.tro >> results.txt

echo === OBJREL.AS to OBJREL.TRO (96 bytes, one fixup of each kind) >> results.txt
tatara /q objrel.as objrel.tro >> results.txt

rem --- the listing file

echo === OBJDATA.AS to a LISTING FILE (four bytes a line, source at 32) >> results.txt
tatara /q /l objdata.as objdata.tro objdata.prn
type objdata.prn >> results.txt

echo === MACPLUS.AS (expect a + on the two expanded lines) >> results.txt
tatara /q /p /l macplus.as >> results.txt

echo === M80 MACPLUS.AS - WHERE DOES M80 PUT THE +? >> results.txt
type m80ref\macplus.prn >> results.txt

echo === REPTLST.AS (expect the REPT, its body, ENDM, then 1 1) >> results.txt
tatara /q /p /l reptlst.as >> results.txt

echo === M80 REPTLST.AS - DOES M80 LIST A REPT BODY WHERE IT IS WRITTEN? >> results.txt
type m80ref\reptlst.prn >> results.txt

echo === LONGLST.AS to a LISTING FILE (055 reads this one) >> results.txt
tatara /q /l longlst.as longlst.tro longlst.prn
type longlst.prn >> results.txt

echo === M80 LONGLST.AS - THE SECOND PAGE, AND HOW LONG A PAGE IS >> results.txt
type m80ref\longlst.prn >> results.txt

echo === M80 TITLLST.AS - WHERE DO TITLE AND SUBTTL GO? (056 reads this) >> results.txt
type m80ref\titllst.prn >> results.txt

echo === TITLSH.AS - a three-character title >> results.txt
tatara /q /l titlsh.as titlsh.tro titlsh.prn
type titlsh.prn >> results.txt
echo === M80 TITLSH.AS - THE COLUMN IS M80S ANSWER >> results.txt
type m80ref\titlsh.prn >> results.txt

echo === TITLLG.AS - a twenty-character title >> results.txt
tatara /q /l titllg.as titllg.tro titllg.prn
type titllg.prn >> results.txt
echo === M80 TITLLG.AS - AND THE SAME QUESTION, WIDER >> results.txt
type m80ref\titllg.prn >> results.txt

echo === SUBTL2.AS - a subtitle and a second page >> results.txt
tatara /q /l subtl2.as subtl2.tro subtl2.prn
type subtl2.prn >> results.txt
echo === M80 SUBTL2.AS - IS THE SUBTITLE ON PAGE 1-1? >> results.txt
type m80ref\subtl2.prn >> results.txt

echo === PAGEDIR.AS - PAGE, and what PAGE 12 counts >> results.txt
tatara /q /l pagedir.as pagedir.tro pagedir.prn
type pagedir.prn >> results.txt
echo === M80 PAGEDIR.AS - IS THE NEXT PAGE 2 OR 1-1? >> results.txt
type m80ref\pagedir.prn >> results.txt

echo === PAGEBAD.AS (expect a PAGE length error, line 4) >> results.txt
tatara /q /p pagebad.as >> results.txt

echo === MACLIST.AS (expect .LALL all, .XALL the db only, .SALL none) >> results.txt
tatara /q /p /l maclist.as >> results.txt

echo === M80 MACLIST.AS - WHAT DOES M80 KEEP UNDER EACH? >> results.txt
type m80ref\maclist.prn >> results.txt

echo === XLIST.AS (expect the first db and nothing after .XLIST) >> results.txt
tatara /q /p /l xlist.as >> results.txt

echo === M80 XLIST.AS - DOES M80 LIST THE .XLIST LINE ITSELF? >> results.txt
type m80ref\xlist.prn >> results.txt

echo === EQULIST.AS (expect the VALUE beside EQU, no mark) >> results.txt
tatara /q /p /l equlist.as >> results.txt

echo === FCOND.AS (expect db 1 kept, db 2 gone) >> results.txt
tatara /q /p /l fcond.as >> results.txt

echo === M80 FCOND.AS >> results.txt
type m80ref\fcond.prn >> results.txt

echo === FCONDD.AS (a false branch with nothing said: the default) >> results.txt
tatara /q /p /l fcondd.as >> results.txt

echo === FCONDLAB.AS /S (expect no address on LAB or VAL, and only T0 defined) >> results.txt
tatara /q /p /l /s fcondlab.as >> results.txt

echo === P2LAB.AS (expect defined on pass 1 and not on pass 2, P2LAB.INC line 7) >> results.txt
tatara /q /p p2lab.as >> results.txt

echo === P2EQU.AS (expect a clean assembly, with 3E 05 at 0100h) >> results.txt
tatara /q /p /l p2equ.as >> results.txt

echo === P2IF1.AS (expect defined on pass 1 and not on pass 2, line 9) >> results.txt
tatara /q /p p2if1.as >> results.txt

echo === LABIF.AS (expect FIRST at 0000 and SECOND at 0001, and both dw) >> results.txt
tatara /q /p /l labif.as >> results.txt

echo === LABCND.AS /S (expect LIF1 LELS LIF0 LRPT LEND2 defined, LEND not) >> results.txt
tatara /q /p /l /s labcnd.as >> results.txt

echo === LABUND.AS (expect undefined symbol, line 11) >> results.txt
tatara /q /p labund.as >> results.txt

echo === LABIRP.AS (expect 0104 holding 0100 and 0106 holding 0102) >> results.txt
tatara /q /p /l labirp.as >> results.txt

echo === IFCASE.AS (expect 02 and 03 and no 01 - text is compared exactly) >> results.txt
tatara /q /p /l ifcase.as >> results.txt

echo === M80 IFCASE.AS - IS TEXT COMPARED EXACTLY? >> results.txt
type m80ref\ifcase.prn >> results.txt

echo === PAGENUM.AS (expect a page break at the form feed, PAGE 2, then 2-1) >> results.txt
rem THROUGH A LISTING FILE AND type, like PAGEDIR and LONGLST: MSX-DOS
rem renders a form feed as two characters on its way through type, and
rem cmpm80.py stops reading at a REAL one. Redirected straight to
rem RESULTS.TXT this listing keeps its 0Ch and the comparison stopped at
rem the first page break.
tatara /q /l pagenum.as pagenum.tro pagenum.prn
type pagenum.prn >> results.txt

echo === M80 PAGENUM.AS - DOES A FORM FEED MOVE THE MAIN NUMBER? >> results.txt
type m80ref\pagenum.prn >> results.txt

echo === PAGENUM.AS /S (expect an EMPTY symbol table - a form feed defines nothing) >> results.txt
tatara /q /p /s pagenum.as >> results.txt

echo === PUBDEFL.AS /S (expect a space between public var and the name) >> results.txt
tatara /q /p /s pubdefl.as >> results.txt

echo === FLDMAC.AS /F /P (expect field dumps and NO macro body, NO page heading) >> results.txt
tatara /q /p /f fldmac.as >> results.txt

echo === EXTT.AS /L to a file (expect E1 and E2 as 0000 and a star) >> results.txt
tatara /q /l extt.as extt.tro extt.prn
type extt.prn >> results.txt

echo === M80 FCONDD.AS - IS THE DEFAULT TO LIST THEM? >> results.txt
type m80ref\fcondd.prn >> results.txt

echo === M80 EQULIST.AS - COUNTER OR VALUE BESIDE AN EQU? >> results.txt
type m80ref\equlist.prn >> results.txt

echo === OBJDATA.AS to OBJDATA.TRO (71 bytes, four DATA runs) >> results.txt
tatara /q objdata.as objdata.tro >> results.txt

echo === PUBUNDF.AS (expect a PUBLIC name was never defined) >> results.txt
tatara /q pubundf.as pubundf.tro >> results.txt

echo === M80 PUBUNDF.AS - WHAT DOES M80 SAY ABOUT AN UNDEFINED PUBLIC? >> results.txt
type m80ref\pubundf.prn >> results.txt

rem --- the M80 cross-check
rem
rem M80 is the oracle. It writes a .PRN listing with an address and the
rem bytes for every line, so TYPEing those into RESULTS.TXT puts its
rem numbers and Tatara's in the same file and no .PRN has to be copied
rem anywhere. A listing that did not get written says File not found
rem right here, which is its own report.
rem
rem Only the instruction tests are worth cross-checking, and only the
rem ones M80 will accept: labels t0 upward - NEVER a register name, or
rem M80 resolves the symbol before the register - and an END line, or
rem M80 calls the file fatal. A new test joins this list only if it
rem obeys both rules.
rem
rem The leading comma is what stops M80 writing a .REL as well.

echo === M80 INSN3.AS >> results.txt
type m80ref\insn3.prn >> results.txt

echo === M80 INSN4.AS >> results.txt
type m80ref\insn4.prn >> results.txt

echo === M80 INSN5.AS >> results.txt
type m80ref\insn5.prn >> results.txt

echo === M80 INSN6.AS >> results.txt
type m80ref\insn6.prn >> results.txt

echo === M80 INSNPAR.AS >> results.txt
type m80ref\insnpar.prn >> results.txt

echo === M80 LDT1.AS >> results.txt
type m80ref\ldt1.prn >> results.txt

echo === M80 LDT2.AS >> results.txt
type m80ref\ldt2.prn >> results.txt

echo === M80 LDT3.AS >> results.txt
type m80ref\ldt3.prn >> results.txt

echo === M80 LDT4.AS >> results.txt
type m80ref\ldt4.prn >> results.txt

echo === M80 LDQUOTE.AS >> results.txt
type m80ref\ldquote.prn >> results.txt

echo === M80 JPT.AS >> results.txt
type m80ref\jpt.prn >> results.txt

echo === M80 JRT.AS >> results.txt
type m80ref\jrt.prn >> results.txt

echo === M80 CBT.AS >> results.txt
type m80ref\cbt.prn >> results.txt

echo === M80 SETBIT.AS >> results.txt
type m80ref\setbit.prn >> results.txt

echo === M80 EXCHG.AS >> results.txt
type m80ref\exchg.prn >> results.txt

echo === M80 INOUT.AS >> results.txt
type m80ref\inout.prn >> results.txt

echo === M80 CPAREN.AS >> results.txt
type m80ref\cparen.prn >> results.txt

echo === M80 EMDB.AS >> results.txt
type m80ref\emdb.prn >> results.txt

echo === M80 EMQUOTE.AS >> results.txt
type m80ref\emquote.prn >> results.txt

echo === M80 EMDC.AS >> results.txt
type m80ref\emdc.prn >> results.txt

echo === M80 SIMPLE1.AS >> results.txt
type m80ref\simple1.prn >> results.txt

echo === M80 SIMPLE2.AS >> results.txt
type m80ref\simple2.prn >> results.txt

echo === M80 SIMPLE3.AS >> results.txt
type m80ref\simple3.prn >> results.txt

echo === M80 SIMPLE4.AS >> results.txt
type m80ref\simple4.prn >> results.txt

echo === M80 SIMPLE5.AS >> results.txt
type m80ref\simple5.prn >> results.txt

echo === M80 UPLUS.AS >> results.txt
type m80ref\uplus.prn >> results.txt

echo === M80 LD1.AS >> results.txt
type m80ref\ld1.prn >> results.txt

echo === M80 LD2.AS >> results.txt
type m80ref\ld2.prn >> results.txt

echo === M80 LD3.AS >> results.txt
type m80ref\ld3.prn >> results.txt

echo === M80 LD4.AS >> results.txt
type m80ref\ld4.prn >> results.txt

echo === M80 LD5.AS >> results.txt
type m80ref\ld5.prn >> results.txt

echo === M80 LD6.AS >> results.txt
type m80ref\ld6.prn >> results.txt

echo === M80 JRDISP.AS >> results.txt
type m80ref\jrdisp.prn >> results.txt

echo === M80 JRSEG.AS - DOES M80 ALLOW A JR ACROSS SEGMENTS? >> results.txt
type m80ref\jrseg.prn >> results.txt

echo === M80 QUOTES.AS - DOES M80 TAKE A DOUBLE-QUOTED CONSTANT? >> results.txt
type m80ref\quotes.prn >> results.txt

echo === M80 WRAP.AS >> results.txt
type m80ref\wrap.prn >> results.txt

rem --- Tatara assembles itself, and the object file it makes is
rem     the one test big enough to get a segment size wrong in an
rem     interesting way: 1,569 bytes, two SEGDEFs with real sizes and
rem     an EXTDEF for every name tatara.as borrows from another module.
rem
rem     IT RUNS FROM THE SOURCE DIRECTORY. tatara.as includes twenty
rem     .inc files that sit beside it, and an include is looked for in
rem     the CURRENT directory - so this cds there, assembles, copies
rem     the object file back here, and cds back. The cd back is not
rem     optional: every line after it appends to RESULTS.TXT by a
rem     relative name.

echo === SYMDUMP.AS with /S (expect a section per segment) >> results.txt
tatara /q /p /s symdump.as >> results.txt

echo === INCSUB.AS (expect ISUB then SIBLING-RIGHT) >> results.txt
tatara /q /p incsub.as >> results.txt

echo === INCENV.AS with TATARA unset (expect: cannot open) >> results.txt
set TATARA=
tatara /q /p incenv.as >> results.txt

echo === INCENV.AS with TATARA set (expect FROM-TATARA-PATH) >> results.txt
set TATARA=lib
tatara /q /p incenv.as >> results.txt
set TATARA=

echo === TATARA.AS to TATARA.TRO (Tatara assembles itself) >> results.txt
rem NO CD, AND NO COPY. The source is named by a path, its
rem own includes are found beside it, and the shared ones come from
rem TATARA - which this line is now a test of. The
rem object lands here because that is where it was asked for.
set TATARA=..\..\shared
tatara /q ..\..\tatara\tatara.as tatara.tro >> results.txt
set TATARA=

echo === END OF RUN >> results.txt

rem --- tidy up, and leave RESULTS.TXT where it was written
rem
rem RESULTS.TXT STAYS HERE, and is fetched from the disk image with
rem openMSX's diskmanipulator.
rem
rem The .PRN listings do go: M80 writes one per cross-checked test,
rem every one of them is already TYPEd into RESULTS.TXT above, and the
rem emulator's disk has better uses for the room.
rem
rem TATARA.COM is not deleted here either - it lives in H:\UTILS on
rem the PATH now, there is only one of it, and MAKE deletes that one
rem before every build. A failed build leaves no binary at all rather
rem than a stale one.

del *.prn

echo Done. The results are in RESULTS.TXT, in this directory.
