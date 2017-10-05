
SECTION "Player house map", ROMX
PlayerHouse::
	db $80 ; Interior map
	
	db MUSIC_SAFE_PLACE ; Music ID
	
	db TILESET_INTERIOR
	dw NO_SCRIPT ; No map script
	map_size 10, 9
	dw NO_SCRIPT ; No loading script
	
PlayerHouseInteractions::
	db 3
	
	db WALK_LOADZONE
	interact_box $0077, $003E, 10, $15
	db THREAD2_LOADINGWALKDOWN
	db 3
	db MAP_STARTHAM
	ds 7
	
	db WALK_LOADZONE
	interact_box $0008, $FFFE, 16, 16
	db THREAD2_LOADINGSTAIRSUP_LEFT
	db 0
	db MAP_PLAYER_HOUSE_2F
	ds 7
	
	db BTN_INTERACT
	interact_box $0008, $0080, 16, 16
	dw PlayerHouseTVScript
	ds 8
	
PlayerHouseNPCs::
	db 1
	
	dw 0 ; No flag dependency
	interact_box $0060, $0000, 0, 0
	db 0 ; Interaction ID
	db $0A << 2 | DIR_LEFT ; Sprite ID & direction
	dn 1, 1, 1, 1 ; Palette IDs
	db $00 ; Movement permissions
	db $00 ; Movement speed
	
	db 0 ; Number of NPC scripts
	dw 0 ; Obligatory no matter the above value
	
	db 1 ; Number of NPC tile sets
	db 0 ; Special trigger : load opposite gender's tiles (if Evie, load Tom, etc.)
	
PlayerHouseWarpToPoints::
	db 2 ; Number of warp-to points
	
	dw $0076 ; Y pos
	dw $0048 ; X pos
	db DIR_UP ; Direction
	db NO_WALKING ; Flags
	db 0
	db THREAD2_AFTERLOADINGWALKUP
	dw NO_SCRIPT ; Loading script (none)
	ds 6
	
	dw $0010
	dw $000F
	db DIR_RIGHT
	db NO_WALKING
	db 0
	db THREAD2_DISABLED
	dw NO_SCRIPT
	ds 6
	
PlayerHouseBlocks::
INCBIN "maps/playerhouse.blk"
	
	
	set_text_prefix PlayerHouseTV
PlayerHouseTVScript::
	disp_box
	print_line_id 0
	print_line_id 1
.source1
	choose YesNoChoice, .branch1 - .source1
	close_box
	make_player_walk_to VERTICAL_AXIS, $30, 1
	make_player_walk_to HORIZONTAL_AXIS, $0080, 1
	turn_player DIR_UP
	wait_user
	make_player_walk DIR_UP, 32, 1
	delay 30
	turn_player DIR_DOWN
	done
	
.branch1
	print_line_id 2
	wait_user
	done
