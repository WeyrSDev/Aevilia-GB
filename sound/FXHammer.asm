
; Disassembly of Aleksi Eeben's FX Hammer SFX player

SECTION	"FX Hammer",ROMX,ALIGN[8]

FXHammerData::
INCBIN	"sound/SFXData.bin"
		
; thumbprint (this could be removed to save space)
	db	"FX HAMMER Version 1.0 (c)2000 Aleksi Eeben (email:aleksi@cncd.fi)"
	
FXHammer_Trig:
	ld	e,c
	ld	d,high(FXHammerData)
	ld	hl,FXHammer_RAM1
	ld	a,[de]
	cp	[hl]
	jr	z,.jmp_4055
	ret	c
.jmp_4055
	ld	[hl],a
	inc	d
	ld	a,[de]
	swap	a
	and	$f
	ld	l,low(FXHammer_SFXCH2)
	or	[hl]
	ld	[hl],a
	ld	a,[de]
	and	$f
	ld	l,low(FXHammer_SFXCH4)
	or	[hl]
	ld	[hl],a
	ld	l,low(FXHammer_cnt)
	ld	a,1
	ld	[hl+],a
	xor	a
	ld	[hl+],a
	ld	a,HIGH(FXHammerData) + 2
	add	e
	ld	[hl],a
	ret
	
FXHammer_Stop:
	ld	hl,FXHammer_SFXCH2
	bit	1,[hl]
	jr	z,.jmp_4084
	ld	a,$08
	ldh	[rNR22],a
	ld	a,$80
	ldh	[rNR24],a
	ld	[hl],1
.jmp_4084
	ld	l,low(FXHammer_SFXCH4)
	set	0,[hl]
	bit	1,[hl]
	jr	z,.jmp_4096
	ld	a,$08
	ldh	[rNR42],a
	ld	a,$80
	ldh	[rNR44],a
	ld	[hl],1
.jmp_4096
	ld	l,low(FXHammer_RAM1)
	xor	a
	ld	[hl+],a
	ld	[hl],a
	ret
	
FXHammer_Update:
	xor	a
	ld	hl,FXHammer_cnt
	or	[hl]
	ret	z
	dec	[hl]
	ret	nz
	inc	l
	ld	a,[hl+]
	ld	d,[hl]
	ld	e,a
	ld	a,[de]
	ld	l,low(FXHammer_cnt)
	ld	[hl-],a
	or	a
	jr	nz,.jmp_40b0
	ld	[hl],a
.jmp_40b0
	ld	l,low(FXHammer_SFXCH2)
	bit	1,[hl]
	jr	z,.jmp_40e5
	inc	e
	ld	a,[de]
	or	a
	jr	nz,.jmp_40c7
	ld	[hl],1
	ld	a,$08
	ldh	[rNR22],a
	ld	a,$80
	ldh	[rNR24],a
	jr	.jmp_40e6
.jmp_40c7
	ld	b,a
	ldh	a,[rNR51]
	and	$dd
	or	b
	ldh	[rNR51],a
	inc	e
	ld	a,[de]
	ldh	[rNR22],a
	inc	e
	ld	a,[de]
	ldh	[rNR21],a
	inc	e
	ld	a,[de]
	ld	b,high(FXHammerData)
	ld	c,a
	ld	a,[bc]
	ldh	[rNR23],a
	inc	c
	ld	a,[bc]
	ldh	[rNR24],a
	jr	.jmp_40e9
.jmp_40e5
	inc	e
.jmp_40e6
	inc	e
	inc	e
	inc	e
.jmp_40e9
	ld	l,low(FXHammer_SFXCH4)
	bit	1,[hl]
	jr	z,.jmp_4119
	inc	e
	ld	a,[de]
	or	a
	jr	nz,.jmp_4100
	ld	[hl],1
	ld	a,$08
	ldh	[rNR42],a
	ld	a,$80
	ldh	[rNR44],a
	jr	.jmp_4119
.jmp_4100
	ld	b,a
	ldh	a,[rNR51]
	and	$77
	or	b
	ldh	[rNR51],a
	inc	e
	ld	a,[de]
	ldh	[rNR42],a
	inc	e
	ld	a,[de]
	ldh	[rNR43],a
	ld	a,$80
	ldh	[rNR44],a
	inc	e
	ld	l,low(FXHammer_ptr)
	ld	[hl],e
	ret
.jmp_4119
	ld	l,low(FXHammer_ptr)
	ld	a,8
	add	[hl]
	ld	[hl],a
	ret
