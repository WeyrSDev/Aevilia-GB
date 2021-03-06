

SECTION "Map loader", ROM0
	
	
LoadMap_FatalError::
	ld [wSaveA], a
	ld a, ERR_BAD_MAP
	jp FatalError
	
LoadMap_Hook::
	ld a, c
	
; If applicable, performs music fade-out
; Performs gfx fade-out,
; Loads map (meta-)data,
; Applies warp-to #[wTargetWarpID] (except if that's $FF),
; Performs gfx fade-in,
; Loads map blocks,
; and returns.
LoadMap::
	ld [wLoadedMap], a ; Write the current map's ID to WRAM
	ld d, a ; Save the ID
	
IF !DEF(GlitchMaps)
	cp NB_OF_MAPS ; Check for validity
	jr nc, LoadMap_FatalError ; Is not. ¯\_(ツ)_/¯
ENDC
	
	xor a
	ld [wChangeMusics], a ; By default, don't change musics
	inc a ; a = 1
	call SwitchRAMBanks
	
	ld a, BANK(MapROMBanks)
	rst bankswitch
	ld h, HIGH(MapROMBanks)
	ld l, d ; MapROMBanks is 256-byte aligned
	ld a, [hl] ; Get map ROM bank
	ld b, a ; Store for bankswitch just after
	ld [wLoadedMapROMBank], a ; Store it
	
	ld a, d
	add a, a ; 2 bytes per pointer
	
	add a, LOW(MapPointers)
	ld l, a
	adc a, HIGH(MapPointers) ; a = Hi + Lo + Carry
	sub l ; a = Hi + Carry, OK!
	ld h, a
	ld a, [hli] ; Set hl to map header's pointer
	ld h, [hl]
	ld l, a
	ld a, b ; We got all info we needed from MapROMBanks/MapPointers
	rst bankswitch ; Switch to map's ROM bank
	
	ld a, [hli] ; Read map's properties byte
	and $80 ; Filter map type (interior vs exterior)
	ld b, a
	ld a, [wFadeSpeed] ; Use fade speed previously set, so it can be customized
	and $7F
	or b ; If map is interior, set fadeout to black, otherwise it will be white
	ld [wFadeSpeed], a
	
	push hl ; Save read pointer, it will be destroyed by later operations
	ld a, [wCurrentMusicID] ; We will determine whether we have to fade the music out
	cp $FF ; Is there any music?
	jr z, .forceMutedMusic ; If not, we have to start the new music
	cp [hl] ; Compare to map's music ID
	jr z, .sameMusic ; If we have the same music, do nothing
.forceMutedMusic
	ld a, [hl]
	ld [wCurrentMusicID], a ; Store intended music ID
	ld a, 2
	ld [wChangeMusics], a ; Schedule music changing
	call DS_Fade ; Fade out and kill music once it's done (fade type 2)
.sameMusic
	
	callacross Fadeout
	ldh a, [hGFXFlags]
	set 6, a
	ldh [hGFXFlags], a
	
	xor a
	ldh [hThread2ID], a ; Avoid race conditions while loading the map
	
	; Clear OAM 'cause NPC code doesn't clear attribs, etc.
	; Has to be done AFTER fadeout to avoid graphical errors
	ld [wNumOfSprites], a
	ld hl, wVirtualOAM
	ld c, OAM_SIZE
	rst fill
	inc a
	ld [wTransferSprites], a
	
	pop hl ; Get back read ptr
	inc hl
	
	; Tileset
	ld a, [hli] ; Check if tileset is fixed
	and a
	jr z, .fixedTileset
	ld a, [hli] ; If the tileset is dependent, call a function to determine the tileset to use
	push hl
	ld h, [hl]
	ld l, a
	rst callHL ; This function must return the ID in a (all registers can be destroyed)
	pop hl
	inc hl
	db $0E ; ld c, $22, and c is about to be overwritten
.fixedTileset
	ld a, [hli]
	ld c, a
	ld a, [wLoadedTileset] ; Lets "movable" tilesets modify c...
	cp c
	ld a, c ; ...at the cost of one instruction.
	call nz, LoadTileset
	
	ld de, wMapScriptPtr ; Copy this data
	ld c, 4
	rst copy
	
	ld c, [hl] ; Get loading script
	inc hl
	ld b, [hl]
	inc hl
	push bc
	
	ld a, [hli]
	and a
	jr z, .noInteractions
	ld b, a
	ld a, [wTargetWarpID] ; Warp $FF will already have the interactions loaded
	inc a
	jr nz, .loadInteractions
.skipInteractions
	ld a, INTERACTION_STRUCT_SIZE + 1
	bit 7, [hl] ; Check if the interaction is tied to a flag
	jr z, .skipInteraction
	inc a ; If yes, skip it
	inc a
.skipInteraction
	add a, l
	ld l, a
	adc a, h
	sub l
	ld h, a
	dec b
	jr nz, .skipInteractions
	jr .noInteractions
.loadInteractions
	xor a
	ld de, wWalkInterCount
	ld c, 4
.clearInteractionsLoop
	ld [de], a
	inc de
	dec c
	jr nz, .clearInteractionsLoop
.copyInteractions
	ld e, [hl]
	bit 7, e
	jr z, .notTiedToFlag
	res 7, e ; Reset that bit
	ld c, e ; Store the type for later
	push bc ; Save count and type
	inc hl
	ld a, [hli] ; Read flag ID
	ld e, a
	ld d, [hl]
	push hl ; Save read ptr
	call GetFlag
	pop hl
	pop bc
	ld a, [hld] ; Get back high byte
	dec hl
	bit 7, a ; Check if bit was supposed to be reset
	jr z, .checkIfFlagReset
	ccf ; If the flag is supposed to be set, invert the check
.checkIfFlagReset
	ld e, c ; Get back interaction type
	jr nc, .notTiedToFlag ; The bit was supposed to be reset, and it is !
	ld de, INTERACTION_STRUCT_SIZE + 3 ; 1 byte of type plus two of flag ID
	add hl, de
	jr .nextInteraction
.notTiedToFlag
	ld d, HIGH(wWalkInterCount)
	ld a, [de]
	inc a
	ld [de], a
	dec a
	swap a
	ld e, a
	dec d ; de points to wButtonLoadZones + struct offset
	ld a, [hli]
	bit 7, a ; If the interaction was tied to a certain flag,
	jr z, .noFlag
	inc hl ; Skip over it
	inc hl
.noFlag
	rra
	jr c, .buttonThingy
	dec d
.buttonThingy
	and $3F ; Don't count flag-tied flag
	jr nz, .loadZone
	dec d
	dec d
.loadZone
	ld c, INTERACTION_STRUCT_SIZE
	rst copy
.nextInteraction
	dec b
	jr nz, .copyInteractions
.noInteractions
	
LoadNPCs:
	ld a, [wTargetWarpID]
	inc a
	ld a, [hli] ; Get NPC count
	jr nz, .loadNPCs
	; Warp $FF overrides NPC loading
	; The number of NPCs mustn't be reloaded either
	add a, a ; *2
	jp z, .noNPCs ; If there are no NPCs, the rest of the data doesn't exist, so skip it
	ld b, a
	add a, a ; *4
	add a, a ; *8
	add a, a ; *16
	sub a, b ; *14 (size of ROM NPC)
	add a, 3 ; Skip script loading (1 count & 1 ptr)
	add a, l
	ld l, a
	jr nc, .skipLoadingNPCs
	inc h
	jr .skipLoadingNPCs
.loadNPCs
	ld [wNumOfNPCs], a
	and a
	jp z, .noNPCs
	ld de, wNPC1_ypos
	ld b, a
.NPCLoadingLoop
	; Check for flag dependency
	ld a, [hli]
	ld c, a
	or [hl] ; Check if there is a flag dependency (ie. this is non-zero)
	jr z, .noFlagDependency
	push hl ; Save read ptr
	push bc ; Save counter
	push de ; Save write ptr
	ld e, c
	ld d, [hl]
	call GetFlag
	pop de
	pop bc
	pop hl
	bit 7, [hl]
	jr z, .checkFlagReset
	ccf
.checkFlagReset
	jr nc, .dependencyMet
	ld a, [wNumOfNPCs] ; The NPC won't be loaded
	dec a
	ld [wNumOfNPCs], a
	ld a, 13 ; Skip over NPC + 1 flag byte
	add a, l
	ld l, a
	jr nc, .skipNPC
	inc h
	jr .skipNPC
.dependencyMet
.noFlagDependency
	inc hl
	ld c, 10
	rst copy ; Copy position and hitbox and interaction ID and sprite ID and palettes
	xor a
	ld [de], a
	inc de
	ld c, 2
	rst copy ; Copy movement flags and speed
	ld a, $20
	ld [de], a ; Init vertical displacement
	inc de
	xor a
	ld [de], a ; Init unused byte
	inc de
	ld a, $20
	ld [de], a ; Init horizontal displacement
	inc de
.skipNPC
	dec b
	jr nz, .NPCLoadingLoop
	ld a, [wNumOfNPCs]
	and $F8
	jr z, .correctNumOfNPCs
	; Do something
	jp FatalError
.correctNumOfNPCs
	ld de, wNumOfNPCScripts
	ld c, 3
	rst copy ; Copy nb & ptr
.skipLoadingNPCs
	ld a, [hli] ; Get number of NPC tiles
	and $0F
	jr z, .noNPCTiles
	ld de, $80C0
.NPCTilesLoop
	push af
	ld a, [hli]
	and a
	jr z, .loadOppositeGender
	ld b, a
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	jr .notOppositeGender
.loadOppositeGender
	dec hl
	push hl
	ld b, BANK(EvieTiles)
	ld hl, EvieTiles
	ld a, [wPlayerGender]
	and a
	jr nz, .notOppositeGender
	ld hl, TomTiles
.notOppositeGender
	push bc
	ld a, b
	ld bc, $C0
	call CopyAcrossToVRAM
	ld a, 1
	ld [rVBK], a
	ld a, e
	sub $C0
	ld e, a
	jr nc, .noCarry0
	dec d
.noCarry0
	pop af
	ld bc, $C0
	call CopyAcrossToVRAM
	xor a
	ld [rVBK], a
	pop hl
	inc hl
	pop af
	dec a
	jr nz, .NPCTilesLoop
.noNPCTiles
	
.noNPCs	
	push hl
	ld a, [hli] ; Get number of warp-to points
	ld c, a
	ld a, [wTargetWarpID]
	cp c
IF !DEF(GlitchMaps)
	jr nc, .checkWarpFF
ELSE
	jr nc, .doneWarping
ENDC
	
	add a, a
	add a, a
	add a, a
	add a, a
	jr nc, .noCarry1
	inc h
.noCarry1
	add a, l
	ld l, a
	jr nc, .noCarry2
	inc h
.noCarry2
	ld a, $FF ; For saving, make sure to preserve player position
	ld [wTargetWarpID], a ; UNLESS THIS IS EXPLICITELY OVERRIDDEN
	ld de, wYPos
	ld c, 4
	rst copy
	
	ld a, [hli]
	ld b, a
	cp DIR_RIGHT + 1
	jr nc, .dontForcePlayerDir
	ld a, b
	ld [de], a ; Player direction
.dontForcePlayerDir
	ld a, [hli] ; Flags byte
	rrca
	ld b, a
	jr c, .dontResetPlayerAnim
	xor a
	ld [wNPC0_steps], a
.dontResetPlayerAnim
	
	; Now we're going to move the camera to the cameraman...
	ld a, [hli]
	ld [wCameramanID], a
	push hl
	call MoveNPC0ToPlayer ; If camera is set to target player (ie. NPC0), move NPC0 to avoid camera moving incorrectly
	pop hl
	ld a, [wCameramanID]
	ld de, wYPos
	and $0F ; Somewhat of a failsafe, and also updates flags
	ld de, wNPC0_ypos
	swap a ; Mult by 16
	add a, e
	ld e, a
	ld bc, wCameraYPos
	ld a, [de]
	sub a, SCREEN_HEIGHT * 4 - 8
	ld [bc], a ; Camera Y pos, low
	inc de
	inc bc
	ld a, [de]
	sbc a, 0 ; Add carry
	ld [bc], a ; Camera Y pos, high
	inc de
	inc bc
	ld a, [de]
	sub a, SCREEN_WIDTH * 4 - 8
	ld [bc], a ; Camera X pos, low
	inc de
	inc bc
	ld a, [de]
	sbc a, 0
	ld [bc], a ; Camera X pos, high
	
	ld a, [hli] ; Thread 2 ID
	ldh [hThread2ID], a
	
	ld a, [hli] ; Loading script...
	ld h, [hl]
	ld l, a
	; Now, call "MoveCamera" to snap the camera at the map's boundaries
	; Otherwise redrawing gets screwed up
	push hl ; Save loading script ptr
	call MoveCamera
	pop hl ; get it back
	ld a, l
	or h
	jr nz, @+1 ; Call loading script if it's not NULL
	jr .doneWarping
.checkWarpFF
	inc a ; Check for warp $FF, which stands for "don't do any warp-related operation"
	jr z, .doneWarping
	dec a
	ld [wSaveA], a
	ld a, ERR_WRONG_WARP
	jp FatalError
.doneWarping
	
	pop hl
	ld a, [hli] ; Get back number of warps
	add a, a
	add a, a
	add a, a
	add a, a
	jr nc, .noCarry3
	inc h
.noCarry3
	add a, l
	ld l, a
	jr nc, .noCarry4
	inc h
.noCarry4 ; Skipped over all warp entries
	
	push hl
	ld a, [wMapWidth]
	ld e, a
	ld d, 0
	ld a, [wMapHeight]
	call MultiplyDEByA
	ld b, h
	ld c, l
	ld a, BANK(wBlockData)
	call SwitchRAMBanks
	pop hl
	ld de, wBlockData
	call Copy
	ld a, BANK(wChangeMusics)
	call SwitchRAMBanks
	
	pop hl
	ld a, l
	or h
	; Hack : this compiles as 20 FF
	; If the jump occurs, it will land on the $FF byte, which will execute a "rst callHL".
	; tl;dr : this is "rst nz, callHL" ^^
	jr nz, @+1
	
	ld a, [wCameraYPos]
	ldh [hSCY], a
	ld a, [wCameraXPos]
	ldh [hSCX], a
	call RedrawMap
	call MoveNPC0ToPlayer
	call ProcessNPCs
	call ExtendOAM
	
	ld a, [wChangeMusics]
	and a
	jr z, .stillSameMusic
.waitMusicIsDown
	rst waitVBlank
	ld a, [SoundEnabled]
	and a
	jr nz, .waitMusicIsDown
	ld a, [wCurrentMusicID]
	inc a
	jr z, .stillSameMusic ; Music $FF = no music
	ld e, a
	ld a, 1
	call DS_Fade
	ld a, e
	dec a
	call DS_Init
.stillSameMusic
	
	ldh a, [hGFXFlags]
	res 6, a
	ldh [hGFXFlags], a
	callacross Fadein
	xor a
	ld [wFadeSpeed], a
	inc a
	ldh [hIgnorePlayerActions], a ; Let all triggers happen at the player's target warping position
	ldh [hAbortFrame], a ; The current overworld frame must NOT keep going, since a new map has been loaded
	ret
	
	
LoadTileset::
	push hl
	ld [wLoadedTileset], a
	ld l, a
	ld h, HIGH(TilesetROMBanks)
	save_rom_bank
	ld a, BANK(TilesetROMBanks)
	rst bankswitch
	ld b, [hl] ; Save tileset's ROM bank
	
	ld a, l
	add a, a
	add a, LOW(TilesetPointers)
	ld l, a
	adc a, HIGH(TilesetPointers)
	sub l
	ld h, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, BANK(wNumOfTileAnims)
	call SwitchRAMBanks
	xor a
	ld [wNumOfTileAnims], a ; Make sure no tile gets overwritten during init
.copyOneBank
	ld de, v0Tiles1
.copyTiles
	ld a, b
	rst bankswitch ; Switch to the tileset's ROM bank
	ld a, [hli] ; Get the number of tiles
	and a
	jr nz, .copyMoreTiles ; 0 indicates the bank's tiles are all copied
	ld a, [rVBK] ; Get bank | $FE
	inc a ; If bank 1, we read $FF, so this will overflow to 0
	ld [rVBK], a ; Note that this also flipped the significant bit, which we'll write back (0->1, 1->0)
	jr z, .doneCopyingTiles ; If so, we're done
	jr .copyOneBank ; So, we're not done ! Let's copy the Bank 1 tiles.
	
.copyMoreTiles
	ld c, a ; Save the number of tiles
	push bc ; Save the tileset's ROM bank
	ld a, [hli] ; Get the source ROM bank
	ld b, a ; Save it
	ld a, [hli] ; Get the source pointer
	push hl
	ld h, [hl]
	ld l, a
	call TransferTilesAcross
	pop hl
	inc hl
	pop bc
	jr .copyTiles
	
.doneCopyingTiles
	ld a, BANK(wBlockMetadata)
	call SwitchRAMBanks
	ld de, wBlockMetadata
	ld bc, (wTileAttributesEnd - wBlockMetadata)
	call Copy ; Copy block metadata
	
	ld a, [hli] ; Read number of tile animators
	and $0F ; Cap that
	jr z, .noAnimators
	ld de, wNumOfTileAnims
	ld b, a
	ld c, b
.copyAnimators ; This loop is a bit of an oddball : de points to the byte *just before* the target
	; It's no problem by any means, just not what you'd be used to.
	xor a
	inc de
	ld [de], a ; Write frame count
	ld a, [hli]
	inc de
	ld [de], a ; Write max frame
	xor a
	inc de
	ld [de], a ; Write current animation frame
	ld a, [hli]
	inc de
	ld [de], a ; Write max anim frame
	ld a, [hli]
	inc de
	ld [de], a ; Write tile ID
	ld a, [hli]
	inc de
	ld [de], a ; Write temporary pointer (real one will be computed after copies)
	ld a, [hli]
	inc de
	ld [de], a
	inc de ; Skip over unused byte
	dec c
	jr nz, .copyAnimators
	
	ld c, b ; Re-copy the number of animators
	; Now, copy all animation frames to WRAM bank 3
	push hl
	ld hl, wTileAnim0_framesPtr + 1
	ld de, wTileFrames
.copyAnimationFrames
	push bc
	
	; Now, a slightly tricky part : we need to write the pointer before the copy (since that's where the base pointer is)
	; but at the same time we need to retrieve the pointer that's the source of the copy!
	ld b, [hl]
	ld [hl], e ; Write pointer to anim frames (which is big-endian)
	dec hl
	ld c, [hl]
	ld [hl], d
	; So, the source pointer is in bc.
	
	dec hl
	dec hl
	ld a, [hli] ; Get num of frames
	; Note : using hli when not necessary? Yup, but if it happened to overflow, we skip a "noCarry", so it's good.
	
	push hl ; Save the read pointer for later
	ld h, b ; Get the source pointer into hl,
	ld l, c ; which also frees bc.
	
	swap a ; Compute length of copy
	ld c, a ; Save this because we can't read it again!
	and $0F
	ld b, a
	ld a, c ; Get back unmasked low byte
	and $F0
	ld c, a ; Done calculating.
	
	ld a, BANK(wTileFrames)
	call SwitchRAMBanks
	call Copy ; Copy anim frames from ROM to WRAM
	; This advances de, which is then set up for the next animator
	
	ld a, BANK(wTileAnimations)
	call SwitchRAMBanks
	
	pop hl ; Get back read ptr
	; Move to next tile
	ld a, l
	add a, (wTileAnim1_framesPtr + 1) - (wTileAnim0_numOfFrames + 1)
	ld l, a
	jr nc, .noCarryAnim
	inc h
.noCarryAnim
	
	pop bc
	dec b
	jr nz, .copyAnimationFrames
	pop hl
	ld a, c
.noAnimators
	ld [wNumOfTileAnims], a
	
	ld de, wOBJPalette6_color2
	ld c, 14
	rst copy
	push hl
	save_rom_bank
	ld a, BANK(DefaultPalette)
	rst bankswitch
	
	ld hl, wOBJPalette6_color2
	ld de, wBGPalette1_color0
.loadTilesetBGPalettes
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	ld c, BG_PALETTE_STRUCT_SIZE
	rst copy
	pop hl
	inc hl
	ld a, e
	cp LOW(wOBJPalettes)
	jr nz, .loadTilesetBGPalettes
	
	restore_rom_bank
	pop hl
	ld de, wOBJPalette6_color2
	ld c, 14
	rst copy
;	push hl
;	save_rom_bank
	ld a, BANK(DefaultPalette)
	rst bankswitch
	
	ld hl, wOBJPalette6_color2
	ld de, wOBJPalette1_color0
.loadTilesetOBJPalettes
	inc de
	inc de
	inc de
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	or h
	ld c, OBJ_PALETTE_STRUCT_SIZE
	jr nz, .normalPalette
	; Load opposite gender's palette
	save_rom_bank
	ld a, BANK(EvieDefaultPalette)
	rst bankswitch
	ld a, [wPlayerGender]
	and a
	ld hl, EvieDefaultPalette
	jr nz, .loadOppositeGenderPalette
	ld hl, TomDefaultPalette
.loadOppositeGenderPalette
	rst copy
	restore_rom_bank
	jr .paletteLoaded
.normalPalette
	rst copy
.paletteLoaded
	pop hl
	inc hl
	ld a, e
	cp LOW(wPalettesEnd)
	jr nz, .loadTilesetOBJPalettes
	
;	restore_rom_bank
;	pop hl
	
	; Insert more code here
	; (If so, uncomment the above block of code and the corresponding one above)
	
	ld hl, wEmoteGfxID
	res 7, [hl]
	
	restore_rom_bank
	pop hl
	ret
	
	
GetCameraTopLeftPtr::
	ld d, HIGH(vTileMap0)
	ld a, [wCameraYPos]
	and $F0
	add a, a
	jr nc, .noCarry2
	inc d
	inc d
.noCarry2
	add a, a
	jr nc, .noCarry3
	inc d
.noCarry3
	ld b, a
	ld a, [wCameraXPos]
	and $F0
	rra
	rra
	rra
	add a, b ; Cannot overflow
	ld e, a
	ret
	
RedrawMap::
	ld hl, wCameraYPos
	ld a, [hli]
	and $F0
	ld e, a
	ld a, [hl]
	and $0F
	or e
	swap a
	ld e, a ; Divided by 16 : OK!
	ld a, [hli]
	and $F0
	swap a
	ld d, a ; Divided by 16 : OK!
	; de now contains the vertical block position
	
	ld a, [hli]
	and $F0
	ld c, a
	ld a, [hl]
	and $0F
	or c
	swap a
	ld c, a ; Divided by 16 : OK!
	ld a, [hli]
	and $F0
	swap a
	ld b, a ; Divided by 16 : OK!
	; bc now contains the horizontal position
	
	ld a, [wMapWidth]
	call MultiplyDEByA
	add hl, bc
	ld d, h
	ld e, l
	ld hl, wBlockData
	add hl, de
	
	
	call GetCameraTopLeftPtr
	; Got VRAM destination
	ld b, 0
.redrawRow
	push hl
	ld c, 0
.redrawBlock
	ld a, [wMapWidth]
	dec a
	cp c
	jr c, .mapIsntWideEnough
	ld a, [wMapHeight]
	dec a
	cp b
	ld a, BANK(wBlockData)
	call SwitchRAMBanks
	ld a, [hli] ; Get block ID
	jr nc, .mapIsTallEnough
.mapIsntWideEnough
	xor a ; If drawing to the right or the bottom of the map, draw block 0 instead
.mapIsTallEnough
	push hl
	ld l, a
	ld a, BANK(wBlockMetadata)
	call SwitchRAMBanks
	ld a, l
	call DrawBlock
	pop hl
	ld a, e
	sub a, VRAM_ROW_SIZE - 1
	ld e, a
	and (VRAM_ROW_SIZE - 1)
	jr nz, .noWrap1
	ld a, e
	sub VRAM_ROW_SIZE
	ld e, a
.noWrap1
	inc c
	ld a, c
	cp SCREEN_WIDTH / 2 + 1
	jr nz, .redrawBlock
	ld a, e
	add a, (VRAM_ROW_SIZE - 1) * 2 - SCREEN_WIDTH
	ld e, a
	jr nc, .noCarry4
	inc d
	ld a, d
	cp HIGH(vTileMap1)
	jr nz, .noCarry4
	ld d, HIGH(vTileMap0)
.noCarry4
	ld a, e
	and (VRAM_ROW_SIZE - 1)
	cp $0A
	jr c, .noWrap2
	ld a, e
	add a, VRAM_ROW_SIZE
	ld e, a
	jr nc, .noWrap2
	inc d
	ld a, d
	cp HIGH(vTileMap1)
	jr nz, .noWrap2
	ld d, HIGH(vTileMap0)
.noWrap2
	pop hl ; Get back pointer from last line
	ld a, [wMapWidth]
	add a, l
	ld l, a
	jr nc, .noCarry5
	inc h
.noCarry5
	inc b
	ld a, b
	cp SCREEN_HEIGHT / 2 + 1
	jr nz, .redrawRow
	ret
	
; Draw block with ID a at VRAM dest de.
; hl points to end of the block's metadata
; de points to last written tile, a equals zero
DrawBlock::
	ld h, HIGH(wBlockMetadata)
	add a, a
	add a, a
	add a, a
	jr nc, .noCarry
	inc h
.noCarry
	ld l, a ; 256-byte aligned : all's gewd here!
	
	xor a
	ld [rVBK], a
.waitVRAM1
	rst isVRAMOpen
	jr nz, .waitVRAM1
	ld a, [hli] ; Load tile 0
	ld [de], a
	ld a, 1
	ld [rVBK], a
.waitVRAM2
	rst isVRAMOpen
	jr nz, .waitVRAM2
	ld a, [hli]
	ld [de], a
	
	ld a, e
	add a, VRAM_ROW_SIZE
	ld e, a
	
	xor a
	ld [rVBK], a
.waitVRAM3
	rst isVRAMOpen
	jr nz, .waitVRAM3
	ld a, [hli] ; Load tile 1
	ld [de], a
	ld a, 1
	ld [rVBK], a
.waitVRAM4
	rst isVRAMOpen
	jr nz, .waitVRAM4
	ld a, [hli]
	ld [de], a
	
	ld a, e
	sub a, VRAM_ROW_SIZE - 1
	ld e, a
	
	xor a
	ld [rVBK], a
.waitVRAM5
	rst isVRAMOpen
	jr nz, .waitVRAM5
	ld a, [hli] ; Load tile 2
	ld [de], a
	ld a, 1
	ld [rVBK], a
.waitVRAM6
	rst isVRAMOpen
	jr nz, .waitVRAM6
	ld a, [hli]
	ld [de], a
	
	ld a, e
	add a, VRAM_ROW_SIZE
	ld e, a
	
	xor a
	ld [rVBK], a
.waitVRAM7
	rst isVRAMOpen
	jr nz, .waitVRAM7
	ld a, [hli] ; Load tile 3
	ld [de], a
	ld a, 1
	ld [rVBK], a
.waitVRAM8
	rst isVRAMOpen
	jr nz, .waitVRAM8
	ld a, [hli]
	ld [de], a
	
	xor a
	ld [rVBK], a
	
	ret
	
	
MoveNPC0ToPlayer::
	ld de, wNPCArray
	ld hl, wYPos
	ld c, 4
	rst copy
	
	ld de, wNPC0_sprite
	ld a, [hl]
	and $03
	ld [de], a
	ret
	
MoveCamera::
	ld a, [wCameramanID]
	cp 9
	ret nc ; If the cameraman ID is too high, this means "don't move the camera an inch"
	call GetNPCOffsetFromCam
	
	ld hl, wTempBuf
	ld a, [hli]
	ld h, [hl]
	ld l, a ; Get vertical offset
	; Sub "SCREEN_HEIGHT * 8 / 2 - 8" to get intended position, plus MAX_CAM_SPEED for possible values to be 0 - MAX_CAM_SPEED * 2
	; (Simpler to process this way)
	ld bc, -(SCREEN_HEIGHT * 4) + 8 + MAX_CAM_SPEED
	add hl, bc ; hl = NPC's displacement from standard position + MAX_CAM_SPEED
	
	ld a, h
	add a, a
	jr c, .capSpeedVertNeg ; Actually, a displacement in range [32768-MAX_CAM_SPEED; 32767] will move the camera in the wrong direction
	jr nz, .capSpeedVert
	
	ld a, l
	cp MAX_CAM_SPEED * 2
	jr nc, .capSpeedVert
	
	; hl is valid, so we will give it the proper value and proceed
	sub MAX_CAM_SPEED
	ld l, a
	sbc a ; 0 if no carry, $FF if carry
	ld h, a
	jr .moveVertically
	
.capSpeedVertNeg
	ld hl, -MAX_CAM_SPEED
	jr .moveVertically
.capSpeedVert
	ld hl, MAX_CAM_SPEED
	
.moveVertically
	ld de, wCameraYPos
	ld a, [de]
	ld c, a
	inc de
	ld a, [de]
	ld b, a ; Get camera's position in bc
	push hl ; Save movement vector ; if redraw needed, MSB will determine whether to redraw left or right row
	add hl, bc ; Add movement vector
	bit 7, h ; If hl > 0, don't count carry
	jr z, .dontLockCamUp
	jr nc, .lockCamUp ; If moving up AND there's no carry (ie. camera crossed sign), lock camera at top
.dontLockCamUp
	; Check if camera's bottom is past the map's boundary
	ld a, [wMapHeight]
	sub a, SCREEN_HEIGHT / 2 ; Subtract the camera's height
	jr c, .lockCamUp
	jr z, .lockCamUp ; If the map is too small, no movement.
	swap a ; Multiply the size by 16
	ld b, a
	and $F0
	ld c, a
	ld a, b
	and $0F
	ld b, a
	ld a, h
	; bc contains the camera's max position (camera must be <= this)
	; Lock cam if hl > bc
	; ie bc - hl < 0
	cp b
	jr c, .dontLockCamVert ; if h < b, hl < bc
	jr nz, .lockCamDown ; if h > b, hl > bc
	ld a, c
	cp l
	jr nc, .dontLockCamVert
.lockCamDown
	; Lock camera to bottom
	ld h, b
	ld l, c
	jr .cameraLockedVert
.lockCamUp
	ld hl, 0 ; Lock camera at position 0
.cameraLockedVert ; Force no OoB redrawing if camera is locked
	ld a, h
	ld [de], a
	dec de
	ld a, l
	ld [de], a
	pop bc
	jp .dontRedrawRow
.dontLockCamVert
	ld a, h ; Write back (in reverse order!)
	ld [de], a
	dec de
	ld a, [de]
	ld c, a ; Get back current position to decide whether to redraw row or not
	ld a, l
	ld [de], a
	
	ld a, c
	and $F0
	ld c, a
	ld a, l
	and $F0
	cp c
	pop bc ; Get movement vector back, LSByte will be trashed but what counts is MSByte
	jr z, .dontRedrawRow
	ld hl, wTempBuf + 2
	ld de, wLargerBuf
	ld c, 2
	rst copy
	ld hl, wCameraYPos
	ld de, wTempBuf
	ld a, b
	add a, a ; Get MSB of movement vector in carry
	ld a, [hli]
	jr nc, .drawBottomRow ; No carry = moved right -> redraw bottom!
	ld [de], a
	inc de
	ld a, [hli]
	jr .rowTargetAcquired
.drawBottomRow
	add a, SCREEN_HEIGHT * 8
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
.rowTargetAcquired
	ld [de], a
	inc de
	ld c, 2
	rst copy
	
	ld d, HIGH(vTileMap0)
	ld a, [wTempBuf]
	and $F0
	add a, a
	jr nc, .noCarry1
	inc d
	inc d
.noCarry1
	add a, a
	jr nc, .noCarry2
	inc d
.noCarry2
	ld e, a
	ld a, [wTempBuf + 2]
	and $F0
	rrca
	rrca
	rrca
	add a, e
	ld e, a
	push de
	call GetPointerFromCoords
	pop de
	ld c, SCREEN_WIDTH / 2 + 1
.drawRowLoop
	ld a, BANK(wBlockData)
	call SwitchRAMBanks
	ld a, [hli]
	push hl
	push de
	ld l, a
	ld a, BANK(wBlockMetadata)
	call SwitchRAMBanks
	ld a, l
	call DrawBlock
	pop de
	inc e
	inc e
	ld a, e
	and (VRAM_ROW_SIZE - 1)
	jr nz, .rowNoWrap
	ld a, e
	sub a, $20
	ld e, a
.rowNoWrap
	pop hl
	dec c
	jr nz, .drawRowLoop
	ld hl, wLargerBuf
	ld de, wTempBuf + 2
	ld c, 2
	rst copy
	ld de, wCameraYPos
.dontRedrawRow
	
	
	ld hl, wTempBuf + 2
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld bc, -(SCREEN_WIDTH * 4) + 8 + MAX_CAM_SPEED
	add hl, bc
	
	ld a, h
	add a, a
	jr c, .capSpeedHorizNeg
	jr nz, .capSpeedHoriz
	
	ld a, l
	cp MAX_CAM_SPEED * 2
	jr nc, .capSpeedHoriz
	
	sub MAX_CAM_SPEED
	ld l, a
	sbc a
	ld h, a
	jr .moveHorizontally
	
.capSpeedHorizNeg
	ld hl, -MAX_CAM_SPEED
	jr .moveHorizontally
.capSpeedHoriz
	ld hl, MAX_CAM_SPEED
	
.moveHorizontally
	inc de
	inc de
	ld a, [de]
	ld c, a
	inc de
	ld a, [de]
	ld b, a
	push hl ; Push for later redraw
	add hl, bc
	bit 7, h ; If hl > 0, don't count carry
	jr z, .dontLockCamLeft
	jr nc, .lockCamLeft ; If moving up AND there's no carry (ie. camera crossed sign), lock camera at top
.dontLockCamLeft
	; Check if camera's right is past the map's boundary
	ld a, [wMapWidth]
	sub a, SCREEN_WIDTH / 2 ; Subtract the camera's width
	jr c, .lockCamLeft
	jr z, .lockCamLeft ; If the map is too small, no movement.
	swap a ; Multiply the size by 16
	ld b, a
	and $F0
	ld c, a
	ld a, b
	and $0F
	ld b, a
	ld a, h
	; bc contains the camera's max position (camera must be <= this)
	; Lock cam if hl > bc
	; ie bc - hl < 0
	cp b
	jr c, .dontLockCamHoriz ; if h < b, hl < bc
	jr nz, .lockCamRight ; if h > b, hl > bc
	ld a, c
	cp l
	jr nc, .dontLockCamHoriz
.lockCamRight
	; Lock camera to right
	ld h, b
	ld l, c
	jr .dontLockCamHoriz
.lockCamLeft
	ld hl, 0 ; Lock camera at position 0
.dontLockCamHoriz
	ld a, h
	ld [de], a
	dec de
	ld a, [de]
	ld c, a ; Get back current position to decide whether to redraw row or not
	ld a, l
	ld [de], a
	
	ld a, c
	and $F0
	ld c, a
	ld a, l
	and $F0
	cp c
	pop bc ; Get back h in b. l doesn't matter
	ret z ; End all operations if we stay on same row
	
	ld hl, wCameraYPos
	ld de, wTempBuf
	ld c, 2
	rst copy
	ld a, b
	add a, a
	ld a, [hli]
	jr nc, .drawRightColumn
	ld [de], a
	inc de
	ld a, [hli]
	jr .columnTargetAcquired
.drawRightColumn
	add a, SCREEN_WIDTH * 8
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
.columnTargetAcquired
	ld [de], a
	
	ld d, HIGH(vTileMap0)
	ld a, [wTempBuf]
	and $F0
	add a, a
	jr nc, .noCarry3
	inc d
	inc d
.noCarry3
	add a, a
	jr nc, .noCarry4
	inc d
.noCarry4
	ld e, a
	ld a, [wTempBuf + 2]
	and $F0
	rrca
	rrca
	rrca
	add a, e
	ld e, a
	push de
	call GetPointerFromCoords
	pop de
	ld c, SCREEN_HEIGHT / 2 + 1
.drawColumnLoop
	ld a, BANK(wBlockData)
	call SwitchRAMBanks
	ld a, [hl]
	push hl
	ld l, a
	ld a, BANK(wBlockMetadata)
	call SwitchRAMBanks
	ld a, l
	call DrawBlock
	ld a, VRAM_ROW_SIZE - 1
	add a, e
	ld e, a
	jr nc, .noCarry5
	inc d
	ld a, d
	cp HIGH(vTileMap1)
	jr nz, .noCarry5
	; Wrap
	ld d, HIGH(vTileMap0)
.noCarry5
	pop hl
	ld a, [wMapWidth]
	add a, l
	ld l, a
	jr nc, .noCarry6
	inc h
.noCarry6
	dec c
	jr nz, .drawColumnLoop
	ret
	
	
StopPlayerMovement::
	xor a
	ld [wNPC0_steps], a
	; Slide through to refresh sprites
	
	
; Aside from "THIS FUNCTION IS FUCKING HUUUUUGE", there's not much to say
; In fact, it's so huge there are a couple JRs in here that died because their target was too far away
ProcessNPCs::
	ld a, BANK(wNPCArray)
	call SwitchRAMBanks
	
	ld hl, wNPCArray
	ld de, wVirtualOAM + 4 * OAM_SPRITE_SIZE
	ld a, [wNumOfNPCs]
	inc a ; Add player to the count, also makes sure this is not 0
	ld c, a
	
	ld b, 0
.processNPC
	push bc
	push hl
	push de
	ld a, b
	call GetNPCOffsetFromCam
	
	ld bc, wTempBuf
	ld a, [bc]
	ld e, a
	inc bc
	ld a, [bc]
	ld d, a ; Get offset from wTempBuf
	inc bc
	ld hl, TILE_SIZE * 2
	add hl, de
	pop de ; Get back write ptr
	ld a, h
	and a ; Check if NPC has a pixel on-screen
	jp nz, .skipThisNPC ; Too far for a jr
	ld a, l
	cp SCREEN_HEIGHT * TILE_SIZE + TILE_SIZE * 2
	jp nc, .skipThisNPC
	
	ld a, [bc]
	add a, TILE_SIZE * 2
	ld h, a
	inc bc
	ld a, [bc]
	adc a, 0
	jp nz, .skipThisNPC ; Too far, too
	ld a, h
	cp SCREEN_WIDTH * TILE_SIZE + TILE_SIZE * 2
	jp nc, .skipThisNPC
	
	; Write sprite coords
	ld a, l
	ld [de], a ; Place offset
REPT 4
	inc de
ENDR
	add a, TILE_SIZE
	ld [de], a
REPT 4
	inc de
ENDR
	sub TILE_SIZE
	ld [de], a
REPT 4
	inc de
ENDR
	add a, TILE_SIZE
	ld [de], a
	inc de
	
	ld a, h
	ld [de], a
REPT 4
	dec de
ENDR
	ld [de], a
REPT 4
	dec de
ENDR
	sub a, TILE_SIZE
	ld [de], a
REPT 4
	dec de
ENDR
	ld [de], a
	inc de
	
	; Calculate sprite ID, direction etc.
	pop hl ; Get read pointer back
	push hl
	ld bc,  2 + 2 + 1 + 1 + 1 ; Y pos, X pos, Y hitbox, X hitbox, interact ID
	add hl, bc
	ld a, [hli] ; Get sprite ID & direction
	ld b, a ; Save this for ID extraction
	add a, a ; Mult by 2
	and 3 << 1 ; Get direction
	ld c, a
	
	ld a, b ; Extract ID
	and $7C ; Get sprite ID * 4
	ld b, a
	add a, a ; Mult by 3
	add a, b ; a = ID * 12
	ld b, a
	
	ld a, [hli] ; Get palette ID
	and $77
	
	inc hl
	inc hl
	bit 3, [hl] ; [hl]'s bit 3 contains if the NPC is walking or "frozen"
	dec hl
	ld d, 0 ; We will use the step counter to perform walking animations. d is known, so we can use it for storage.
	jr nz, .forceNoWalkingAnim ; If bit 3 is set, the NPC isn't walking so no anim
	ld d, [hl]
.forceNoWalkingAnim
	dec hl
	
	ld h, [hl] ; Store right palettes in h
	ld l, a ; Store left palettes in l
	ld a, h
	and $77
	ld h, a
	
	bit 3, d ; On some parts of a walk, change to a "walking" stance to play a "walking" animation
	jr z, .noWalkingAnim
	or $88 ; Change VRAM banks
	ld h, a
	ld a, l
	or $88
	ld l, a
	bit 2, c
	jr nz, .noWalkingAnim ; If facing up or down,
	bit 4, d ; (set this to 1 bit left of the "walking stance" bit)
	jr z, .noWalkingAnim ; half of the walking frames will be of the opposite direction (to create arms balancing)
	inc c ; Set bit 0 of c to mirror the bottom half
.noWalkingAnim
	ld d, HIGH(wVirtualOAM) ; Restore
	
	ld a, c ; Get direction
	and 6
	cp DIR_RIGHT * 2
	jr nz, .notRight
	dec a
	dec a
	ld c, %1001 ; Set bits 0 and 3 of c to mirror both halves of sprite
.notRight
	add a, a ; Double the index (top is always on even IDs)
	add a, b ; Add the base index
	ld b, a
	bit 3, c
	jr z, .dontFlip1
	or 2
.dontFlip1
	ld [de], a
	inc de
	ld a, l
	swap a
	and %1111 ; Get palette ID and VRAM bank bit
	bit 3, c
	jr z, .dontFlip2
	set 5, a ; Set flip
.dontFlip2
	ld [de], a
REPT 3
	inc de
ENDR
	ld a, b
	bit 0, c
	jr z, .dontFlip3
	or 2
.dontFlip3
	inc a
	ld [de], a
	inc de
	ld a, l
	and %1111 ; Get palette ID and VRAM bank
	bit 0, c
	jr z, .dontFlip4
	set 5, a ; Set flip
.dontFlip4
	ld [de], a
REPT 3
	inc de
ENDR
	ld a, b
	or 2
	ld b, a
	bit 3, c
	jr z, .dontFlip5
	and 2 ^ $FF
.dontFlip5
	ld [de], a
	inc de
	ld a, h
	swap a
	and %1111 ; Get palette ID and VRAM bank
	bit 3, c
	jr z, .dontFlip6
	set 5, a ; Set flip
.dontFlip6
	ld [de], a
REPT 3
	inc de
ENDR
	ld a, b
	inc a
	bit 0, c
	jr z, .dontFlip7
	and 2 ^ $FF
.dontFlip7
	ld [de], a
	inc de
	ld a, h
	and %1111 ; Get palette ID and VRAM bank
	bit 0, c
	jr z, .dontFlip8
	set 5, a ; Set flip
.dontFlip8
	ld [de], a
	inc de
	
.skipThisNPC
	ld a, e
	and -OAM_SPRITE_SIZE ; Get on sprite boundary
	ld e, a
	pop hl
	ld a, l
	and -NPC_STRUCT_SIZE
	add a, NPC_STRUCT_SIZE
	ld l, a
	
	pop bc
	inc b
	ld a, b
	sub c
	jp nz, .processNPC ; Too far to jr...
	
	; Now, we set the number of sprites...
	ld a, e
	rra
	and a
	rra
	ld [wNumOfSprites], a
	
	ld hl, wEmoteGfxID
	ld a, [hli]
	inc a
	jr z, .unloadEmote
	dec a
	add a, a
	jr c, .emoteGfxLoaded
	cp $FE
	jp z, .emoteNotPresent
	
	add a, a
	add a, LOW(.emoteTilesPtrs)
	ld l, a
	adc a, HIGH(.emoteTilesPtrs)
	sub l
	ld h, a
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	ld de, vEmoteTiles
	ld bc, BANK(EmoteTiles) << 8 | 4
	ld a, BANK(vEmoteTiles)
	ld [rVBK], a
	call TransferTilesAcross
	xor a
	ld [rVBK], a
	pop hl
	inc hl
	ld a, [hli]
	ld e, a
	ld d, [hl]
	ld c, 7
	callacross LoadOBJPalette_Hook
	
	ld hl, wEmoteGfxID
	; Mark emote gfx as loaded
	ld a, [hl]
	set 7, a
	ld [hli], a
.emoteGfxLoaded
	ld a, [hl] ; Get emote position
	ld hl, wTempBuf
	bit 7, a
	jr nz, .atScreenBottom
	; Attached to a NPC
	and $0F
	call GetNPCOffsetFromCam
	ld bc, TILE_SIZE * 2
	ld a, [de]
	ld h, a
	dec de
	ld a, [de]
	ld l, a
	add hl, bc
	ld a, h
	and a
	jr nz, .noEmote
	ld a, l
	cp (SCREEN_WIDTH + 2) * TILE_SIZE
	jr nc, .noEmote
	sub TILE_SIZE
	ld c, a
	
	dec de
	ld a, [de]
	and a
	jr nz, .noEmote
	dec de
	ld a, [de]
	cp SCREEN_HEIGHT * TILE_SIZE
	jr c, .gotCoords
	ld a, [wEmotePosition]
	; If bit 6 is set, the emote should stick to the bottom of the screen
	; even if the NPC is below the screen (except if it's further away than 256 pixels)
	bit 6, a
	jr nz, .stickyBottom
	ld a, [de]
	cp (SCREEN_HEIGHT + 2) * TILE_SIZE
	jr c, .gotCoords
	jr .noEmote
	
.unloadEmote
	dec hl
	ld [hl], $7F
	jr .noEmote
	
.atScreenBottom
	and $7F
	add a, TILE_SIZE * 2
	ld c, a
.stickyBottom
	ld a, SCREEN_HEIGHT * TILE_SIZE
	
.gotCoords
	ld b, a
	ld hl, wVirtualOAM
	ld de, $7C << 8 | LOW(TILE_SIZE)
.drawEmote
	ld a, b
	ld [hli], a
	ld a, c
	ld [hli], a
	ld a, d
	ld [hli], a
	ld a, $0F
	ld [hli], a
	
	ld a, b
	add a, e
	ld b, a
	jr nc, .dontMoveHoriz
	ld a, c
	add a, TILE_SIZE
	ld c, a
.dontMoveHoriz
	ld a, e
	cpl
	inc a
	ld e, a
	inc d
	ld a, d
	cp $80
	jr nz, .drawEmote
	jr .emoteNotPresent
	
.noEmote
	xor a
	ld hl, wVirtualOAM
	ld c, 4 * OAM_SPRITE_SIZE
	rst fill
.emoteNotPresent
	ld a, 1
	ld [wTransferSprites], a
	ret
	
	
.emoteTilesPtrs
	dw BlankEmoteTiles
	dw EmotePalette
	
	dw HappyEmoteTiles
	dw EmotePalette
	
	dw NeutralEmoteTiles
	dw EmotePalette
	
	dw SadEmoteTiles
	dw EmotePalette
	
	dw SadderEmoteTiles
	dw EmotePalette
	
	dw SurprisedEmoteTiles
	dw EmotePalette
	
	
; Get NPC #a's offset from the camera
; Returns with de = wTempBuf + 3 and bc = wCameraXPos + 1
; Destroys all registers
GetNPCOffsetFromCam::
	add a, a
	add a, a
	add a, a
	add a, a
	add a, LOW(wNPC0_ypos)
	ld l, a
	ld h, HIGH(wNPC0_ypos)
	; hl = Pointer to NPC's Y coord
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	; hl = NPC's Y coord
	
	ld bc, wCameraYPos
	ld a, [bc]
	cpl
	ld e, a
	inc bc
	ld a, [bc]
	cpl
	ld d, a
	inc bc
	inc de
	; de = - Camera's Y coord
	
	add hl, de ; Get NPC's Y offset
	ld de, wTempBuf
	ld a, l
	ld [de], a
	inc de
	ld a, h
	ld [de], a ; Store it
	
	pop hl
	inc hl ; hl = Pointer to NPC's X coord
	ld a, [hli]
	ld h, [hl]
	ld l, a
	
	ld a, [bc]
	cpl
	ld e, a
	inc bc
	ld a, [bc]
	cpl
	ld d, a
	inc de
	; de = - Camera's X coord
	
	add hl, de ; Get offset
	ld de, wTempBuf + 2
	ld a, l
	ld [de], a
	inc de
	ld a, h
	ld [de], a ; Store it
	ret
	
	
; Move all NPCs according to their structs
MoveNPCs::
	ld de, NPC_STRUCT_SIZE
	ld a, [wNumOfNPCs]
	call MultiplyDEByA
	ld de, wNPC0_steps
	add hl, de
.moveNPC
	ld a, [hli]
	bit 2, [hl]
	jr z, .gotoNextNPC
	and a
	jr z, .NPCAtRest
	
	bit 3, [hl]
	jr z, .NPCIsMoving
	
	dec hl
	dec a ; Decrement waiting counter
	ld [hli], a ; Store
	jr nz, .gotoNextNPC
	res 3, [hl] ; Unfreeze NPC if waiting is done
	jr .gotoNextNPC
	
.NPCIsMoving
	ld b, a ; Store number of steps
	ld e, [hl] ; Store direction
	inc hl
	
	ld d, [hl] ; Store speed in d
	; a = number of steps
	sub d ; Subtract speed from number of steps
	jr nc, .dontStopMovement
	; If there's a carry we need to not walk full speed on the last step
	ld d, b ; Set "speed" to equal remaining steps
	xor a ; Set number of steps to zero
	
.dontStopMovement
	dec hl
	dec hl
	ld [hl], a ; Write number of steps back
	
	and a
	jr nz, .movementContinues
.stopMovement
	; Oddity : If this triggers on the same frame an NPC "bonks", RNG will be rolled twice
	; (This roll will be overwritten by the "bonk" one)
	push hl
	call RandInt
	pop hl
	ld [hli], a ; Set random freezing time
	set 3, [hl] ; Mark NPC as "frozen"
.movementContinues
	
	ld a, l
	and -NPC_STRUCT_SIZE
	ld l, a
	; hl points to NPC's y pos
	ld bc, wTempBuf
.copyToTemp
	ld a, [hli]
	ld [bc], a
	inc bc
	ld a, c
	cp LOW(wTempBuf + 4)
	jr nz, .copyToTemp
	dec bc
	dec bc
	bit 1, e ; Check if moving horizontally
	jr nz, .movingHorizontally
	dec bc
	dec bc
	dec hl
	dec hl
.movingHorizontally
	; bc points to corresponding coordinate
	bit 0, e
	ld a, [bc]
	jr nz, .movingPositively
	sub a, d
	jr nc, .noCarry
	ld [bc], a
	inc bc
	ld a, [bc]
	dec a
	jr .noCarry
.movingPositively
	add a, d
	jr nc, .noCarry
	ld [bc], a
	inc bc
	ld a, [bc]
	inc a
.noCarry
	ld [bc], a
	; Perform collision check
	push hl
	push de
	call GetNPCCollision
	pop de
	pop hl
	jr z, .stopNPC
	
	; Update displacement
	ld a, l
	add a, (wNPC0_ydispl - wNPC0_xpos)
	ld l, a
	ld a, [hl]
	bit 0, e
	jr nz, .updateDisplacementPositively
	sub a, d
	sub a, d ; Compensate for next
.updateDisplacementPositively
	add a, d
	ld d, a ; Store this (next check destroys a)
	and $C0
	jr nz, .stopNPC ; Prevent NPCs going too far from their "anchor point" (box of 64x64 px)
	ld [hl], d
	
	ld a, l
	and -NPC_STRUCT_SIZE
	ld e, a
	ld d, h ; de = NPC's ypos
	ld hl, wTempBuf
	ld c, 4
	rst copy ; Apply movement
	ld h, d
	ld l, e
.gotoNextNPC ; "Relay" to avoid turning some "jr"s above into "jp"s (Saves size and wastes 1 CPU cycle)
	jr .nextNPC
	
.NPCAtRest
	; Have NPC generate movement
	ld a, [hl] ; Store flags
	and $F4 ; Get only permissions & "enable" bit (which should be set by this point)
	ld [hl], a ; Correct invalid states
	ld d, a
	and $C0 ; Get turning permissions
	jr z, .nextNPC
	
	push hl
	call RandInt
	ld b, l ; Save the random int's low byte
	pop hl
	and $3F ; a contains the high byte
	jr nz, .nextNPC ; Some chance the NPC doesn't do anything, but eventually it should
	
	ld a, d ; Get back flags
	and $C0
	rlca
	rlca
	cp 3 ; If NPC is able to move on both axes, choose one at random
	jr nz, .axisSelected
	rra
	bit 1, b
	jr z, .axisSelected
	add a, a
.axisSelected
	ld c, a ; Store the axis to choose movement (later)
	and 2
	bit 2, b
	jr z, .directionSelected
	inc a
.directionSelected
	ld e, a ; Store direction in common format
	or d
	ld [hld], a ; Write flags with new direction
	dec hl
	dec hl
	dec hl
	ld a, [hl] ; Get sprite ID minus direction
	and $FC
	or e ; Turn NPC
	ld [hli], a
	inc hl
	inc hl ; hl points to step counter
	bit 0, b
	jr z, .dontMove ; NPC may choose not to move :p
	ld a, d
	swap a ; Get perms in the low byte
	and c ; Mask the axis chosen
	jr z, .dontMove ; NPC isn't allowed to move on that axis
	
	; Do NPC's movement
	push hl
	call RandInt
	pop hl
	ld [hli], a
	; Process one frame of movement (if NPC bonks immediately, avoids a "stutter frame") ; also "hli" coincidentally placed hl just right! :D
	jp .NPCIsMoving ; Too far to jr, tho :/
	
.stopNPC ; This block of code is off in the distance to avoid turning a jr into a jp
	ld a, l
	and -NPC_STRUCT_SIZE
	ld l, a
	ld bc, (wNPC0_steps - wNPC0_ypos)
	add hl, bc
	push hl
	call RandInt
	pop hl
	ld [hli], a ; Make NPC enter "frozen" state
	set 3, [hl]
	jr .nextNPC
	
.dontMove
	; Stall NPC for some frames, to avoid spamming turning around
	ld a, b
	and $F8
	rrca
	ld [hli], a
	set 3, [hl] ; Mark NPC as "waiting"
	
.nextNPC
	ld a, l
	and -NPC_STRUCT_SIZE ; Get on struct edge
	sub	(wNPC1_ypos - wNPC0_steps) ; Go to previous struct
	ld l, a
	cp LOW(wNPC0_steps - 16) ; Check if we reached the end
	jp nz, .moveNPC
	ret
	
; Get collision for the NPC pointed to by hl (can be anywhere within the NPC's struct) at coordinates given by wTempBuf
; Doesn't alter wTempBuf, but otherwise trashes all other registers
GetNPCCollision::
	ld a, l ; Make sure we are on struct's edge (transfers some code from above function, lets a jr be a jr)
	and -NPC_STRUCT_SIZE
	ld l, a
	ld bc, (wNPC0_movtFlags - wNPC0_ypos)
	add hl, bc
	ld a, [hl]
	and 3
	ld b, a ; Get movement direction, will be used for optimization (otherwise, laaaaag)
	ld a, l
	and -NPC_STRUCT_SIZE
	add a, (wNPC0_ybox - wNPC0_ypos)
	ld l, a
	ld e, b ; Transfer direction (it was preserved across the copy here)
	ld a, [hli] ; Store Y hitbox size
	ld c, a
	ld b, [hl] ; Store X hitbox size
	push hl
	ld a, c ; If hitbox is 0 wide/large, NPC can't collide
	dec c ; Decrement hitbox size by 1 to obtain offset
	and a
	jr z, .dontCollide
	ld a, b
	dec b
	and a
	jr z, .dontCollide
	
	ld [hl], 0 ; Zero hitbox size to avoid NPC colliding with itself
	
	bit 0, e ; Down and Right have this bit set
	jr nz, .dontSampleTopLeft
	push de
	push bc
	call GetNPCCollisionAt
	pop bc
	pop de
	jr z, .collide
	
.dontSampleTopLeft
	ld a, c
	and a
	jr z, .dontSampleBottomLeft ; A hitbox of 1 (thus offset of 0) will yield the same result as above, ie. PASS
	
	ld hl, wTempBuf
	ld a, [hl]
	add a, c
	ld [hli], a
	jr nc, .noCarry1
	inc [hl]
.noCarry1
	ld a, e ; Get direction
	and a ; Clear carry
	rra
	jr nc, .bit0Reset1
	dec a ; Toggle bit 1 (rotated right)
.bit0Reset1
	and a ; Left and Down have differing bits 0 and 1, thus they will set Z here (and we want only those)
	jr z, .dontSampleBottomLeft
	push de
	push bc
	call GetNPCCollisionAt
	pop bc
	pop de
	jr z, .collide
	
.dontSampleBottomLeft
	ld a, b
	and a
	jr z, .dontSampleBottomRight
	
	ld hl, wTempBuf + 2
	ld a, [hl]
	add a, b
	ld [hli], a
	jr nc, .noCarry2
	inc [hl]
.noCarry2
	bit 0, e ; Up and Left have the bit reset
	jr z, .dontSampleBottomRight
	push de
	push bc
	call GetNPCCollisionAt
	pop bc
	pop de
	jr z, .collide
	
.dontSampleBottomRight
	ld a, c
	and a
	jr z, .dontCollide
	
	ld hl, wTempBuf
	ld a, [hl]
	sub a, c
	ld [hli], a
	jr nc, .noCarry3
	inc [hl]
.noCarry3
	
	ld a, e
	and a
	rra
	jr nc, .bit0Reset2
	dec a
.bit0Reset2
	and a
	jr nz, .dontCollide
	push bc
	call GetNPCCollisionAt
	pop bc
	db $11 ; Will absorb the next two as "ld de, $XXXX"
	
.dontCollide
	xor a
	inc a
.collide
	pop hl
	push af
	inc c ; Make sure to restore true hitbox size
	ld [hl], c ; Restore hitbox size
	ld hl, wTempBuf + 2
	ld a, [hl]
	sub b
	ld [hli], a
	jr nc, .noCarry4
	dec [hl]
.noCarry4
	pop af ; Restore Z flag
	ret
	
	
StopWalkingAnimation:
	; xor a ; No need, it's already zero when called
	ld [wNPC0_steps], a
	ret
	
MovePlayer::
	ldh a, [hOverworldHeldButtons]
	and DPAD_DOWN | DPAD_LEFT | DPAD_RIGHT | DPAD_UP
	jr z, StopWalkingAnimation
	ld b, a
	ld [wTempBuf + 4], a
	
	ld a, [wNPC0_steps]
	and a
	jr nz, .dontRestartWalkingAnimation
	ld a, $20
.dontRestartWalkingAnimation
	dec a
	ld [wNPC0_steps], a
	
	ld a, [wPlayerSpeed]
	ld c, a
	and $F0 ; Valid speed range : $00-$0F
	jr z, .speedIsValid
	xor a
	ld c, a
	ld [wPlayerSpeed], a
.speedIsValid
	ld a, c
	and a
	jp z, .cantMove ; Too far to jr
	
.movementLoop
	push bc
	ld hl, wYPos
	ld de, wTempBuf
	ld a, b
	add a, a
	jr nc, .notDown
	add a, a ; Skip Up.
	ld b, a
	ld a, [hli]
	add a, 1
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
	jr .movedVertically
.notDown
	add a, a
	ld b, a
	jr c, .moveUp
	ld c, 2
	rst copy
	jr .noVerticalMovement
.moveUp
	ld a, [hli]
	sub a, 1
	ld [de], a
	inc de
	ld a, [hli]
	sbc a, 0
.movedVertically
	ld [de], a
	
	inc de
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	
	push bc
	ld hl, wTempBuf
	ld de, wLargerBuf
	ld c, 2
	rst copy
	
	call DetectPlayerCollision
	jr z, .verticalCollision
	ld hl, wLargerBuf
	ld de, wYPos
	ld c, 2
	rst copy
	jr .noVerticalCollision
	
.verticalCollision
	ld a, [wTempBuf + 4]
	and $30
	ld [wTempBuf + 4], a
	
.noVerticalCollision
	ld hl, wYPos
	ld de, wTempBuf
	ld c, 2
	rst copy
	
	pop bc
	ld hl, wXPos
	ld de, wTempBuf + 2
.noVerticalMovement
	ld a, b
	add a, a
	jr nc, .notLeft
	ld a, [hli]
	sub a, 1 ; This can generate a carry, "dec" wouldn't
	ld [de], a
	inc de
	ld a, [hli]
	sbc a, 0
	jr .movedHorizontally
.notLeft
	add a, a
	jr nc, .noHorizontalMovement
.moveRight
	ld a, [hli]
	add a, 1 ; This may generate a carry, "inc" wouldn't
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
.movedHorizontally
	ld [de], a
	inc de
	
	ld hl, wTempBuf + 2
	ld de, wLargerBuf
	ld c, 2
	rst copy
	
	; Check for collision at target coordinates
	call DetectPlayerCollision
	jr z, .horizontalCollision ; Don't move if collision occurs
	
	ld hl, wLargerBuf
	ld de, wXPos
	ld c, 2
	rst copy
	jr .noHorizontalCollision
	
.horizontalCollision
	ld a, [wTempBuf + 4]
	and $C0
	ld [wTempBuf + 4], a
	
.noHorizontalCollision
.noHorizontalMovement
	pop bc
	dec c
	jp nz, .movementLoop ; Too far to jr!
	
.cantMove
	ld a, [wTempBuf + 4]
	ld c, a
	and a
	jr nz, .changeDirection
	; Reset animation for the same reasons as below
	xor a
	ld [wNPC0_steps], a
	
	ld a, b ; Player didn't move, so use direction keys instead. Will look weird in some cases, but just returning would cause even weirder things
	; Example : Look left against a wall below you, stop and tap Down. You wouldn't turn with `ret`urning.
	; Also not retrieving keys from memory, since it's slower
	; Note : loop softlocks if no key is held (but that's normally impossible here)
.changeDirection
	ld e, -1
.turnPlayer
	inc e
	add a, a
	jr nc, .turnPlayer
	
	and a ; Check if a diagonal is being held (no other key than first one)
	jr z, .doTurn
	ld a, c
	and a ; If we're trying to turn but we didn't move, don't turn (otherwise it looks weird)
	ret z
	
.doTurn
	and a ; Clear carry
	ld a, e
	rra
	xor e
	xor 1
	ld [wPlayerDir], a
	ret
	
	
PLAYER_HITBOX_Y_OFFSET	equ 8
PLAYER_HITBOX_X_OFFSET	equ 2
PLAYER_HITBOX_Y_SIZE	equ 7
PLAYER_HITBOX_X_SIZE	equ 11 ; Collision is per-tile, so we need one extra collision point (since this > 8)
	
; Detect player collision at coordinates given by wTempBuf
; Sets Z if can't go through
DetectPlayerCollision::
	ld hl, wTempBuf
	ld a, [hl]
	add a, PLAYER_HITBOX_Y_OFFSET
	ld [hli], a
	jr nc, .noCarry1
	inc [hl]
.noCarry1
	inc hl
	ld a, [hl]
	add a, PLAYER_HITBOX_X_OFFSET
	ld [hli], a
	jr nc, .noCarry2
	inc [hl]
.noCarry2
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_UP | DPAD_LEFT
	jr z, .dontSampleTopLeft ; Don't sample top-left if not going up or left
	call GetCollisionAt
	ret z
.dontSampleTopLeft
	
	ld hl, wTempBuf
	ld a, [hl]
	add a, PLAYER_HITBOX_Y_SIZE
	ld [hli], a
	jr nc, .noCarry3
	inc [hl]
.noCarry3
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_DOWN | DPAD_LEFT
	jr z, .dontSampleBottomLeft ; Don't sample if...
	call GetCollisionAt
	ret z
.dontSampleBottomLeft
	
	ld hl, wTempBuf + 2
	ld a, [hl]
	; NOTE : due to integer rounding, LEAVE THIS instead of "add a, PLAYER_HITBOX_X_SIZE / 2"
	add a, PLAYER_HITBOX_X_SIZE - PLAYER_HITBOX_X_SIZE / 2
	ld [hli], a
	jr nc, .noCarry4
	inc [hl]
.noCarry4
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_DOWN
	jr z, .dontSampleBottom
	call GetCollisionAt
	ret z
.dontSampleBottom
	
	ld hl, wTempBuf + 2
	ld a, [hl]
	add a, PLAYER_HITBOX_X_SIZE / 2
	ld [hli], a
	jr nc, .noCarry5
	inc [hl]
.noCarry5
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_DOWN | DPAD_RIGHT
	jr z, .dontSampleBottomRight
	call GetCollisionAt
	ret z
.dontSampleBottomRight
	
	ld hl, wTempBuf
	ld a, [hl]
	sub a, PLAYER_HITBOX_Y_SIZE
	ld [hli], a
	jr nc, .noCarry6
	dec [hl]
.noCarry6
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_UP | DPAD_RIGHT
	jr z, .dontSampleTopRight
	call GetCollisionAt
	ret z
.dontSampleTopRight
	
	ldh a, [hOverworldHeldButtons]
	and DPAD_UP
	jr nz, .sampleTop ; Skip all calculations if this point isn't sampled
	inc a ; A was zero, so we need to return with NZ
	ret
.sampleTop
	
	ld hl, wTempBuf + 2
	ld a, [hl]
	sub a, PLAYER_HITBOX_X_SIZE / 2
	ld [hli], a
	jr nc, .noCarry7
	dec [hl]
.noCarry7
	call GetCollisionAt
	ret
	
	
GetNPCCollisionAt::
	; Check for collision with the player (only relevant for NPCs, since the player will NEVER trigger this)
	ld hl, wTempBuf
	ld a, [wYPos + 1]
	ld b, a
	ld a, [wYPos]
	ld c, a
	ld a, [hli]
	sub c
	ld c, a
	ld a, [hli]
	sbc b
	jr nz, .noPlayerCollision
	ld a, c
	cp $10
	jr nc, .noPlayerCollision
	
	ld a, [wYPos + 3]
	ld b, a
	ld a, [wYPos + 2]
	ld c, a
	ld a, [hli]
	sub c
	ld c, a
	ld a, [hl]
	sbc b
	jr nz, .noPlayerCollision
	ld a, c
	cp $10
	jr c, CollideWithOOB
.noPlayerCollision
	
	; Prevent NPCs from moving inside walking loading zones as to not get in the player's way
	ld a, [wWalkLoadZoneCount]
	and a
	jr z, .dontScanLoadZones
	ld hl, wWalkingLoadZones
	ld e, wWalkingLoadZone1_ypos - wWalkingLoadZone0_ypos
	call ScanForInteraction
	ccf ; C reset if detection occured
	sbc a, a ; Will set a to zero if...
	ret z ; Return if interaction has been found
.dontScanLoadZones
	; Share rest of collision detection with player
	
; Detect collision at pixel whose coordinates are given by wTempBuf
; Sets Z if collision occurs
GetCollisionAt::
	ld a, [wNumOfNPCs]
	and a
	jr z, .dontScanNPCs
	ld hl, wNPC1_ypos
	ld e, NPC_STRUCT_SIZE
	call ScanForInteraction
	ccf ; C set = NPC NOT collided with
	sbc a, a ; If a NPC is collided with, this will set a to $00. Otherwise, $FF.
	ret z
.dontScanNPCs
	
	call GetPointerFromCoords
	
	ld a, b
	and a
	jr nz, CollideWithOOB
	ld a, [wMapWidth]
	dec a
	cp c ; Will set carry if width - 1 < block offset, ie block offset >= width
	jr c, CollideWithOOB
	
	ld hl, wTempBuf + 1
	ld a, [hl]
	and $F0
	jr nz, CollideWithOOB
	ld a, [wMapHeight]
	ld c, a
	ld a, [hld]
	and $0F
	ld b, a
	ld a, [hl]
	and $F0
	or b
	swap a
	cp c
	jr c, NoOOB
CollideWithOOB:
	xor a
	ret
	
NoOOB:
	ld a, [wNoClipActive]
	and a
	ret nz
	
	ld a, BANK(wBlockData)
	call SwitchRAMBanks
	ld a, [de]
	ld d, HIGH(wBlockMetadata)
	add a, a
	add a, a
	add a, a
	jr nc, .noCarry1
	inc d
.noCarry1
	ld e, a
	ld a, BANK(wBlockMetadata)
	call SwitchRAMBanks
	bit 3, [hl] ; Check if on bottom row of tile of current block
	jr z, .notBottomRow
	inc de
	inc de
.notBottomRow
	inc hl
	inc hl
	bit 3, [hl] ; Check if on right column of tile of current block
	jr z, .notRightRow
	inc de
	inc de
	inc de
	inc de
.notRightRow
	ld h, d
	ld l, e
	ld a, [hli]
	bit 7, a ; Check if tile is a tileset one
	ret z ; Always collide with tiles not originating from tileset
	bit 3, [hl]
	jr nz, .tileIsBank1
	res 7, a ; Bank 0's tiles have attributes 0-127, bank 1's have 128-255
.tileIsBank1
	ld l, a
	ld h, HIGH(wTileAttributes)
	bit 7, [hl]
	ret ; Return with colliding with block status
	
	
; Get the pointer to the block targeted by the coords in wTempBuf
GetPointerFromCoords::
	ld hl, wTempBuf
	ld a, [hli]
	and $F0
	ld e, a
	ld a, [hl]
	and $0F
	or e
	swap a
	ld e, a ; Divided by 16 : OK!
	ld a, [hli]
	and $F0
	swap a
	ld d, a ; Divided by 16 : OK!
	; de now contains the vertical block position
	
	ld a, [hli]
	and $F0
	ld c, a
	ld a, [hl]
	and $0F
	or c
	swap a
	ld c, a ; Divided by 16 : OK!
	ld a, [hli]
	and $F0
	swap a
	ld b, a ; Divided by 16 : OK!
	; bc now contains the horizontal position
	
	ld a, [wMapWidth]
	call MultiplyDEByA
	add hl, bc ; hl now contains map offset
	ld d, h
	ld e, l
	
	ld hl, wBlockData
	add hl, de
	ld d, h
	ld e, l
	ret
	
	
GetCoordsInFrontOfPlayer::
	ld a, [wPlayerDir]
	add a, a
	ld hl, CoordVectors
	add a, l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld c, [hl]
	inc hl
	ld b, [hl]
	
	ld hl, wYPos
	ld de, wTempBuf
	ld a, [hli]
	add a, c
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
	ld [de], a
	inc de
	ld a, [hli]
	add a, b
	ld [de], a
	inc de
	ld a, [hli]
	adc a, 0
	ld [de], a
	ret
	
CoordVectors::
	db 7,  7
	db 16, 7
	db 9,  1
	db 9, 14
	
	
DoButtonInteractions::
	call GetCoordsInFrontOfPlayer
	
	ld a, [wNumOfNPCs]
	and a
	jr z, .noNPCs
	ld hl, wNPC1_ypos
	
	ld e, NPC_STRUCT_SIZE
	call ScanForInteraction
	jr nc, .noNPCs ; Didn't find anything
	inc hl
	ld a, [hli] ; Get NPC's interaction ID
	ld b, a ; Save it
	ld a, [wNPC0_sprite] ; Get out direction (& sprite)
	and 3 ; Filter only direction bits
	xor 1 ; Toggle facing so NPC faces us
	ld c, a ; Save new direction
	ld a, [hl] ; Get NPC's sprite & direction
	and $FC ; Get sprite only
	or c ; Set direction
	ld [hli], a ; Push changes
	inc hl
	inc hl
	xor a
	ld [hli], a ; Stop NPC's movement
	push bc
	call ProcessNPCs
	call ExtendOAM
	ld a, [wLoadedMapROMBank]
	rst bankswitch
	pop af ; NPC script ID goes in a
	add a, a
	ld hl, wNPCScriptsPointer
	add a, [hl] ; Add offset to base ptr
	inc hl
	ld h, [hl]
	ld l, a
	jr nc, ProcessInteraction + 1 ; Skip 1st "inc hl"
	inc h
	jr ProcessInteraction + 1
	
.noNPCs
	ld e, INTERACTION_STRUCT_SIZE
	ld a, [wBtnInterCount]
	and a
	jr z, .noButtonInteraction
	ld hl, wButtonInteractions
	call ScanForInteraction
	jr c, ProcessInteraction
.noButtonInteraction
	ld a, [wBtnLoadZoneCount]
	and a
	ret z
	ld hl, wButtonLoadZones
	call ScanForInteraction
	ret nc
	jr ProcessLoadZone
	
DoWalkingInteractions::
	ld hl, wYPos
	ld de, wTempBuf
	ld c, 4
	rst copy
	ld e, INTERACTION_STRUCT_SIZE
	ld a, [wWalkInterCount]
	and a
	jr z, .noWalkingInteraction
	ld hl, wWalkingInteractions
	call ScanForInteraction
	jr c, ProcessInteraction
.noWalkingInteraction
	ld a, [wWalkLoadZoneCount]
	and a
	ret z
	ld hl, wWalkingLoadZones
	call ScanForInteraction
	ret nc
	; Slide
	
ProcessLoadZone:
	inc hl
	ld a, [hli]
	ldh [hThread2ID], a
	ld a, [hli]
	ld [wTargetWarpID], a
	ld a, [hli]
	push af
	ld a, [hl]
	ld c, a
	inc a
	callacross nz, FXHammer_Trig
	pop af
	jp LoadMap
	
ProcessInteraction:
	inc hl
	ld e, [hl]
	inc hl
	ld d, [hl] ; Get interaction pointer
	push de ; Save it 'cause it's gonna be destroyed
	call StopPlayerMovement
	pop de ; Retrieve interaction pointer
	ld a, [wLoadedMapROMBank]
	ld c, a ; Get interaction bank
	jpacross ProcessText_Hook
	
; Formerly "LookForAThingToInteractWith"
; The olde name shall forever remain in memory
; Scans for an interaction in a table
; First 6 bytes of an element must be :
; - Y pos,			2 bytes
; - X pos,			2 bytes
; - Y hitbox size,	1 byte
; - X hitbox size,	1 byte
; Parameters :
; hl = pointer to table (ELEMENTS MUST BE ALIGNED TO THEIR SIZE!!) (Otherwise  v )
; a = number of elements
; e = length of one element (MUST BE A POWER OF 2!!!) (Otherwise          rewrite code so it pushes base ptr, operates, pops it, and adds the size)
; wTempBuf = coords of scanned point
; Destroys all registers, preserves wTempBuf
; If an element can be interacted with, will return with C flag set and hl pointing to corresponding X hitbox size
ScanForInteraction::
	ld b, a
.lookForInteraction
	ld a, [hli]
	ld c, a
	ld a, [wTempBuf]
	sub c
	ld d, a
	ld a, [hli]
	ld c, a
	ld a, [wTempBuf + 1]
	sbc c
	jr nz, .notThisOne
	ld a, d
	inc hl
	inc hl
	cp [hl]
	jr nc, .notThisOne
	dec hl
	dec hl
	ld a, [hli]
	ld c, a
	ld a, [wTempBuf + 2]
	sub c
	ld d, a
	ld a, [hli]
	ld c, a
	ld a, [wTempBuf + 3]
	sbc c
	jr nz, .notThisOne
	ld a, d
	inc hl
	cp [hl]
	ret c
	
.notThisOne
	xor a
	sub e ; Get alignment mask (this only works with powers of 2!!!)
	and l ; Align read ptr
	add a, e ; Advance 1 element
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	dec b
	jr nz, .lookForInteraction
	and a ; Clear carry
	ret
	
	
GetPlayerTopLeftPtr::
	ld d, HIGH(vTileMap0)
	ld a, [wYPos]
	and $F0
	add a, a
	jr nc, .noCarry2
	inc d
	inc d
.noCarry2
	add a, a
	jr nc, .noCarry3
	inc d
.noCarry3
	ld b, a
	ld a, [wXPos]
	and $F0
	rra
	rra
	rra
	add a, b ; Cannot overflow
	ld e, a
	ret
