%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'boards.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_CHAR 'O'

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40

; the player starting position.
; top left is considered (0,0)
%define STARTX 1
%define STARTY 1

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'

 ;these are for adding  coins
        %define coin_char 'C'
        %define empty_char ' '
        %define coin_count 5
        %define teleport_x 36
        %define teleport_y 17
segment .data

        ; used to fopen() the board file defined above
        board_file                      db BOARD_FILE,0

        ; used to change the terminal mode
        mode_r                          db "r",0
        raw_mode_on_cmd         db "stty raw -echo",0
        raw_mode_off_cmd        db "stty -raw echo",0

        ; ANSI escape sequence to clear/refresh the screen
        clear_screen_code       db      27,"[2J",27,"[H",0

        ; things the program will print
        help_str                        db 13,10,"Controls: ", \
                                                        UPCHAR,"=UP / ", \
                                                        LEFTCHAR,"=LEFT / ", \
                                                        DOWNCHAR,"=DOWN / ", \
                                                        RIGHTCHAR,"=RIGHT / ", \
                                                        EXITCHAR,"=EXIT", \
                                                        13,10,10,0
; these are for squares to the left, right, above and below the teleporter
        near_teleporter dd WIDTH*teleport_y + (teleport_x-1)
                                        dd WIDTH*teleport_y + (teleport_x+1)
                                        dd WIDTH * (teleport_y-1) + teleport_x
                                dd WIDTH * (teleport_y+1) + teleport_x
                                         coin_emoji db 0xF0, 0x9F, 0xAA, 0x99, 0
                teleporter db 0xF0, 0x9F, 0x8C, 0x80, 0
                        ; this line stores a message in the memory
                        coin_time db "All 5 coins collected in %d seconds!" , 10,0

;Message if the monster catches the player
	game_over_msg db 13,10, "Game over! You got caught by the big bad monster.",13,10,0

segment .bss

        ; this array stores the current rendered gameboard (HxW)
        board   resb    (HEIGHT * WIDTH)

        ; these variables store the current player position
        xpos    resd    1
        ypos    resd    1
        coinscollected resd 1
        ;variables for time
                start_time resd 1
                elapsed_seconds resd 1

		;variables for the monster
		monster_x resd 1
		monster_y resd 1

segment .text

        global  asm_main
        global  raw_mode_on
        global  raw_mode_off
        global  init_board
        global  render

        extern  system
        extern  putchar
        extern  getchar
        extern  printf
        extern  fopen
        extern  fread
        extern  fgetc
        extern  fclose
        ;the following are for random number generation:
        extern time
        extern srand
        extern rand
asm_main:
        push    ebp
        mov             ebp, esp

		push ebx
		push esi
		push edi


        ; put the terminal in raw mode so the game works nicely
        call    raw_mode_on

        ; read the game board file into the global variable
        call    init_board
        ; seeding random number
                push 0
                call time
                add esp, 4
                push eax
                call srand
                add esp,4

        ;add coins
                call place_coins
        ; set the player at the proper start position
        mov             DWORD [xpos], STARTX
        mov             DWORD [ypos], STARTY

		;set the monster's starting position
		mov 		DWORD[monster_x], 20
		mov 		DWORD[monster_y], 10


        ; the game happens in this loop
        ; the steps are...
        ;   1. render (draw) the current board
        ;   2. get a character from the user
        ;       3. store current xpos,ypos in esi,edi
        ;       4. update xpos,ypos based on character from user
        ;       5. check what's in the buffer (board) at new xpos,ypos
        ;       6. if it's a wall, reset xpos,ypos to saved esi,edi
        ;       7. otherwise, just continue! (xpos,ypos are ok)
                ;Below is how we record when the game starts
                        push 0
                        call time
                        add esp,4
                        mov DWORD[start_time],eax
        game_loop:

                ; draw the game board
                call    render

                ; get an action from the user
                call    getchar

                ; store the current position
                ; we will test if the new position is legal
                ; if not, we will restore these
                mov             esi, DWORD [xpos]
                mov             edi, DWORD [ypos]

                ; choose what to do
                cmp             eax, EXITCHAR
                je              game_loop_end
                cmp             eax, UPCHAR
                je              move_up
                cmp             eax, LEFTCHAR
                je              move_left
                cmp             eax, DOWNCHAR
                je              move_down
                cmp             eax, RIGHTCHAR
                je              move_right
                jmp             input_end                       ; or just do nothing

                ; move the player according to the input character
                move_up:
                        dec             DWORD [ypos]
                        jmp             input_end
                move_left:
                        dec             DWORD [xpos]
                        jmp             input_end
                move_down:
                        inc             DWORD [ypos]
                        jmp             input_end
                move_right:
                        inc             DWORD [xpos]
                input_end:

                ; (W * y) + x = pos

                ; compare the current position to the wall character
                mov             eax, WIDTH
                mul             DWORD [ypos]
                add             eax, DWORD [xpos]
                lea             eax, [board + eax]
                cmp             BYTE [eax], WALL_CHAR
                jne             valid_move
                        ; opps, that was an invalid move, reset
                        mov             DWORD [xpos], esi
                        mov             DWORD [ypos], edi

                valid_move:
                                cmp BYTE[eax],'T'
                                je teleport
                                cmp     BYTE [eax], coin_char
                				jne     monster_turn

                mov     BYTE [eax], empty_char
                inc     DWORD [coinscollected]
                                cmp     DWORD [coinscollected], coin_count
                        jne     monster_turn
                                ;below is how we calculate the current time
                    push    0
                        call    time
                        add     esp, 4
                        sub     eax, DWORD [start_time]
                        mov     DWORD [elapsed_seconds], eax
                        jmp     monster_turn
                teleport:
                        mov     DWORD [xpos], STARTX
                        mov     DWORD [ypos], STARTY
                        jmp     monster_turn


				monster_turn:
					call monster_move     ;to move the monster
					cmp eax, 1				;to check if the monster caught the player
					je game_over
					jmp game_loop			;game continues if the player is still alive

				game_over:
					mov eax, game_over_msg
					call print_string
					add esp, 4
					jmp game_loop_end

        game_loop_end:

        ; restore old terminal functionality
        call raw_mode_off

        mov             eax, 0

		lea esp, [ebp-12]
		pop edi
		pop esi
		pop ebx

        mov             esp, ebp
        pop             ebp
        ret


;---------------------------------------------------------------------------------------
;We are moving the moster one square at a time randomly.
;if the monster catches the player the game is over(the player failed)
;monster_move   ;the function
;return eax= 1 if the player was caught
;		eax = 0 if the player was not caught


monster_move:
	push ebp
	mov ebp, esp
	sub esp, 8

	;save the resigsters used by this function
	push ebx
	push ecx
	push edx
	push esi
	push edi

	;save current monsters position
	mov eax, DWORD [monster_x]
	mov DWORD [ebp-4], eax

	mov eax, DWORD [monster_y]
	mov DWORD [ebp - 8], eax

	;generate random directions
	call rand

	mov edx, 0
	mov ecx, 4
	div ecx			;edx holds the reminder 0-3

	cmp edx, 0
	je monster_up

	cmp edx, 1
	je monster_down

	cmp edx, 2
	je monster_left

	cmp edx, 3
	je monster_right

monster_up:
	dec DWORD [monster_y]
	jmp check_monster_move

monster_down:
	inc DWORD [monster_y]
	jmp check_monster_move

monster_left:
	dec DWORD [monster_x]
	jmp check_monster_move

monster_right:
	inc DWORD [monster_x]
	jmp check_monster_move

check_monster_move:
	;check boundaries
	cmp DWORD [monster_x], 0
	jl monster_invalid_move

	cmp DWORD [monster_x], WIDTH
	jge monster_invalid_move

	cmp DWORD [monster_y],0
	jl monster_invalid_move

	cmp DWORD [monster_y], HEIGHT
	jge monster_invalid_move

	;check board index
    mov eax, DWORD [monster_y]
    mov ebx, WIDTH
    mul ebx
    add eax, DWORD [monster_x]

    ; Check for wall
    cmp BYTE [board + eax], WALL_CHAR
    je monster_invalid_move

    jmp check_caught

monster_invalid_move:

	;restore monsters to old position
	mov eax, DWORD [ebp - 4]
	mov DWORD [monster_x], eax

	mov eax, DWORD [ebp-8]
	mov DWORD [monster_y], eax

check_caught:
	;calculate absolute X distacne
	mov eax, DWORD [xpos]
	sub eax, DWORD [monster_x]

	cmp eax, 0
	jge x_distance_positive

	neg eax

x_distance_positive:
	mov esi, eax

	;calculate absolute Y distance 
	mov eax, DWORD [ypos]
	sub eax, DWORD [monster_y]

	cmp eax, 0
	jge y_distance_positive

	neg eax

y_distance_positive:
	;distance = abs(x difference) + abs(y difference)
	add eax, esi

	;if distance <= 1, player is caught
	cmp eax, 1
	jle player_caught

	;player is safe
	mov eax, 0
	jmp monster_move_end

player_caught:
	mov eax, 1

monster_move_end:

	;restore preserved registers
	pop edi
	pop esi
	pop edx
	pop ecx
	pop ebx


	mov esp, ebp
	pop ebp
	ret

;---------------------------------------------------------------------------------
;limted vision
;tha player can only see 3 steps in all directions
;sight_check
;returns eax = 1 if tile is visible
;eax = 0 if tiles is hidden

sight_check:
    push ebp
    mov ebp, esp

    push esi
    push edi

    ; Coordinates passed by render
    mov esi, DWORD [ebp+8]     ; tile x
    mov edi, DWORD [ebp+12]    ; tile y

    ; Always make border tiles visible
    cmp esi, 0
    je sight_visible

    cmp esi, WIDTH-1
    je sight_visible

    cmp edi, 0
    je sight_visible

    cmp edi, HEIGHT-1
    je sight_visible

    ; abs(tile_x - player_x)
    mov eax, esi
    sub eax, DWORD [xpos]

    cmp eax, 0
    jge sight_x_done
    neg eax

sight_x_done:
    cmp eax, 2
    jg sight_hidden

    ; abs(tile_y - player_y)
    mov eax, edi
    sub eax, DWORD [ypos]

    cmp eax, 0
    jge sight_y_done
    neg eax

sight_y_done:
    cmp eax, 2
    jg sight_hidden

sight_visible:
    mov eax, 1
    jmp sight_exit

sight_hidden:
    mov eax, 0

sight_exit:
    pop edi
    pop esi

    mov esp, ebp
    pop ebp
    ret


raw_mode_on:

        push    ebp
        mov             ebp, esp

        push    raw_mode_on_cmd
        call    system
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

raw_mode_off:

        push    ebp
        mov             ebp, esp

        push    raw_mode_off_cmd
        call    system
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

init_board:

        push    ebp
        mov             ebp, esp

        ; FILE* and loop counter
        ; ebp-4, ebp-8
        sub             esp, 8

        ; open the file
        push    mode_r
        push    board_file
        call    fopen
        add             esp, 8
        mov             DWORD [ebp - 4], eax

        ; read the file data into the global buffer
        ; line-by-line so we can ignore the newline characters
        mov             DWORD [ebp - 8], 0
        read_loop:
        cmp             DWORD [ebp - 8], HEIGHT
        je              read_loop_end

                ; find the offset (WIDTH * counter)
                mov             eax, WIDTH
                mul             DWORD [ebp - 8]
                lea             ebx, [board + eax]

                ; read the bytes into the buffer
                push    DWORD [ebp - 4]
                push    WIDTH
                push    1
                push    ebx
                call    fread
                add             esp, 16
                ; slurp up the newline
                push    DWORD [ebp - 4]
                call    fgetc
                add             esp, 4

        inc             DWORD [ebp - 8]
        jmp             read_loop
        read_loop_end:

        ; close the open file handle
        push    DWORD [ebp - 4]
        call    fclose
        add             esp, 4

        mov             esp, ebp
        pop             ebp
        ret

render:

        push    ebp
        mov             ebp, esp

        ; two ints, for two loop counters
        ; ebp-4, ebp-8
        sub             esp, 8

        ; clear the screen
        push    clear_screen_code
        call    printf
        add             esp, 4


        ; print the help information
        push    help_str
        call    printf
        add             esp, 4
        ; outside loop by height
        ; i.e. for(c=0; c<height; c++)
        mov             DWORD [ebp - 4], 0
        y_loop_start:
        cmp             DWORD [ebp - 4], HEIGHT
        je              y_loop_end

                ; inside loop by width
                ; i.e. for(c=0; c<width; c++)
                mov             DWORD [ebp - 8], 0
                x_loop_start:
                cmp             DWORD [ebp - 8], WIDTH
                je              x_loop_end

                        ; check if the current tile is the player's position

						mov eax, DWORD [xpos]
						cmp eax, DWORD [ebp - 8]
						jne check_visibility

						mov eax, DWORD [ypos]
						cmp eax, DWORD [ebp - 4]
						jne check_visibility

						; Print the player
						push PLAYER_CHAR
						call putchar
						add esp, 4

						jmp pad


						;check wether the current tile is visble
						check_visibility:
						;pass tile coordinates to sight_check
						push DWORD [ebp - 4]   ;tile y
						push DWORD [ebp - 8] 	; tile x

						call sight_check
						add esp, 8

						cmp eax, 1			;if tile visible render it
						je print_monster_check

						push '?'			;otherwise print hidden title
						call putchar
						add esp, 4

						jmp pad




						;check whether this square contains the monster
						print_monster_check:
								mov eax, DWORD [monster_x]
								cmp eax, DWORD [ebp - 8]
								jne print_board

								mov eax, DWORD [monster_y]
								cmp eax, DWORD [ebp - 4]
								jne print_board

								push 'M'
								call putchar
								add esp, 4
								jmp pad


                        print_board:
                                ; otherwise print whatever's in the buffer
                                mov             eax, DWORD [ebp - 4]
                                mov             ebx, WIDTH
                                mul             ebx
                                add             eax, DWORD [ebp - 8]
                                mov             ebx, 0
                                mov             bl, BYTE [board + eax]
                        cmp     bl, coin_char
                        je      print_coin
                                 cmp     bl, 'T'
                        je     print_teleporter
                        push    ebx
                        call    putchar
                        add     esp, 4
                        jmp       pad
                pad:
                        push    ' '
                        call    putchar
                        add     esp, 4
                        jmp     print_end


                print_coin:
                push    coin_emoji
                        call    printf
                        add     esp, 4
                                jmp print_end
                print_teleporter:
        push    teleporter
        call    printf
        add     esp, 4
print_end:

                inc             DWORD [ebp - 8]
                jmp             x_loop_start
                x_loop_end:

                ; write a carriage return (necessary when in raw mode)
                push    0x0d
                call    putchar
                add             esp, 4

                ; write a newline
                push    0x0a
                call    putchar
                add             esp, 4

        inc             DWORD [ebp - 4]
        jmp             y_loop_start
        y_loop_end:
                ;checks whether you’ve collected all five coins and prints it
                 cmp     DWORD [coinscollected], coin_count
        jne     skip_coin_time

        push    DWORD [elapsed_seconds]
        push    coin_time
        call    printf
        add     esp, 8

skip_coin_time:
        mov     esp, ebp
        pop     ebp
        ret
        place_coins:
                push ebp
                mov ebp,esp
                sub esp,4 ; ebp-4 stores how many more coins we need to scatter
                 ;the following picks one of the four squares next tot he teleporter
                        call rand
                        mov edx,0
                        mov ecx,4
                        div ecx
                ; edx has the remainder
                        mov eax, DWORD[near_teleporter+ edx*4]
                        mov  BYTE[board + eax], coin_char
                        mov DWORD[ebp-4], coin_count-1
                place_coins_loop:
                ; pick a random index anywhere in the board
                call    rand
                mov     edx, 0
                mov     ecx, WIDTH * HEIGHT
                div     ecx

                ; skip the player's starting square
                cmp     edx, WIDTH * STARTY + STARTX
                je      place_coins_loop

                ; skip walls, the exit, the teleporter, and other coins
                cmp     BYTE [board + edx], empty_char
                jne     place_coins_loop

                mov     BYTE [board + edx], coin_char

                ; only count a coin when we actually place one
                dec     DWORD [ebp - 4]
                jnz     place_coins_loop

        mov     esp, ebp
        pop     ebp
        ret