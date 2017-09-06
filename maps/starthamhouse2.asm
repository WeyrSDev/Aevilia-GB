
SECTION "Player house map", ROMX
StarthamHouse2::
	db $80 ; Interior map
	
	db MUSIC_SAFE_PLACE ; Music ID
	
	db TILESET_INTERIOR
	dw NO_SCRIPT ; No map script
	map_size 10, 10
	dw NO_SCRIPT ; No loading script
	
StarthamHouse2Interactions::
	db 1
	
	db WALK_LOADZONE
	interact_box $0087, $002E, 10, $15
	db MAP_STARTHAM
	db 4
	
StarthamHouse2NPCs::
	db 0
	
StarthamHouse2WarpToPoints::
	db 1 ; Number of warp-to points
	
	dw $0086 ; Y pos
	dw $0038 ; X pos
	db DIR_UP ; Direction
	db NO_WALKING ; Flags
	db 0
	dw NO_SCRIPT ; Loading script (none)
	ds 7
	
StarthamHouse2Blocks::
INCBIN "maps/starthamhouse2.blk"
