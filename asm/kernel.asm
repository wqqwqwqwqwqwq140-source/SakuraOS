[bits 16]
org 0x7E00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; текстовый режим для меню
    mov ax, 0x0003
    int 0x10

    mov si, msg
    call print

    ; ---- VBE info ----
    mov ax, 0x4F00
    mov di, vbe_info
    mov dword [es:di], 0x32454256      ; "VBE2"
    int 0x10
    cmp ax, 0x004F
    jne vbe_error

    mov si, [vbe_info + 0x0E]
    mov ax, [vbe_info + 0x10]
    mov [mode_list_offset], si
    mov [mode_list_segment], ax

    ; ---- собрать все подходящие режимы ----
    call collect_modes
    cmp  word [mode_count], 0
    je   vbe_error

    ; ---- меню выбора ----
    call show_menu

    ; ---- mode_info для выбранного режима ----
    mov ax, 0x4F01
    mov cx, [vbe_mode]
    mov di, mode_info
    int 0x10
    cmp ax, 0x004F
    jne vbe_error

    ; ---- установить режим с LFB ----
    mov ax, 0x4F02
    mov bx, [vbe_mode]
    or  bx, 0x4000
    int 0x10
    cmp ax, 0x004F
    jne vbe_error

    ; ---- A20 ----
    in  al, 0x92
    or  al, 2
    out 0x92, al

    ; ---- protected mode ----
    lgdt [gdt_descriptor]
    mov  eax, cr0
    or   eax, 1
    mov  cr0, eax
    jmp  0x08:protected_mode_start

;---------------------------------------------------------
print:
    pusha
.next:
    lodsb
    test al, al
    jz   .done
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    jmp  .next
.done:
    popa
    ret

;---------------------------------------------------------
print_nibble:           ; AL = 0..15
    pusha
    and  al, 0xF
    cmp  al, 10
    jb   .dig
    add  al, 'A' - 10 - '0'
.dig:
    add  al, '0'
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    popa
    ret

print_hex16:            ; AX -> "0xXXXX"
    pusha
    mov  cx, ax
    mov  si, hex_prefix
    call print
    mov  ax, cx
    mov  bx, ax
    mov  ax, bx
    shr  ax, 12
    call print_nibble
    mov  ax, bx
    shr  ax, 8
    and  ax, 0xF
    call print_nibble
    mov  ax, bx
    shr  ax, 4
    and  ax, 0xF
    call print_nibble
    mov  ax, bx
    and  ax, 0xF
    call print_nibble
    popa
    ret

print_dec16:            ; AX -> десятичное
    pusha
    mov  cx, 0
    mov  bx, 10
.div:
    xor  dx, dx
    div  bx
    push dx
    inc  cx
    test ax, ax
    jnz  .div
.out:
    pop  ax
    add  al, '0'
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    loop .out
    popa
    ret

;---------------------------------------------------------
; Собираем режимы: LFB + DirectColor + 32bpp
;---------------------------------------------------------
collect_modes:
    pusha
    mov  word [mode_count], 0

    mov  ax, [mode_list_segment]
    mov  fs, ax
    mov  si, [mode_list_offset]

.next_mode:
    mov  cx, [fs:si]
    cmp  cx, 0xFFFF
    je   .done
    add  si, 2

    push si
    push cx
    mov  ax, 0x4F01
    mov  di, tmp_info
    int  0x10
    pop  cx
    pop  si
    cmp  ax, 0x004F
    jne  .next_mode

    mov  ax, [tmp_info + 0x00]
    and  ax, 0x0081           ; supported + LFB
    cmp  ax, 0x0081
    jne  .next_mode

    cmp  byte [tmp_info + 0x1B], 6    ; DirectColor
    jne  .next_mode

    cmp  byte [tmp_info + 0x19], 32   ; 32 bpp
    jne  .next_mode

    ; сохранить номер режима (16-bit: без масштабирования!)
    mov  ax, [mode_count]
    cmp  ax, MAX_MODES
    jae  .done
    shl  ax, 1
    mov  di, ax
    mov  [mode_list + di], cx
    inc  word [mode_count]
    jmp  .next_mode

.done:
    popa
    ret

;---------------------------------------------------------
; Меню выбора
;---------------------------------------------------------
show_menu:
    pusha

    mov ax, 0x0003
    int 0x10

    mov si, menu_title
    call print

    xor  cx, cx
.print_loop:
    cmp  cx, [mode_count]
    jae  .after_print

    mov  ax, cx
    inc  ax
    call print_dec16
    mov  si, menu_dot
    call print

    ; получить mode info (16-bit: ручной shl)
    mov  ax, cx
    shl  ax, 1
    mov  di, ax
    mov  di, [mode_list + di]     ; di = номер режима
    push cx
    push di
    mov  ax, 0x4F01
    mov  di, tmp_info
    int  0x10
    pop  di
    pop  cx

    mov  ax, [tmp_info + 0x12]
    call print_dec16
    mov  si, menu_x
    call print
    mov  ax, [tmp_info + 0x14]
    call print_dec16
    mov  si, menu_x32
    call print

    mov  ax, di
    call print_hex16
    mov  si, menu_nl
    call print

    inc  cx
    jmp  .print_loop
.after_print:
    mov si, menu_prompt
    call print

    xor  cx, cx
.wait_key:
    mov  ah, 0x00
    int  0x16

    cmp  ah, 0x48
    je   .up
    cmp  ah, 0x50
    je   .down
    cmp  al, 13
    je   .chosen

    cmp  al, '1'
    jb   .wait_key
    cmp  al, '9'
    ja   .wait_key
    sub  al, '1'
    movzx ax, al
    cmp  ax, [mode_count]
    jae  .wait_key
    mov  cx, ax
    jmp  .chosen

.up:
    test cx, cx
    jz   .wait_key
    dec  cx
    call show_cursor
    jmp  .wait_key
.down:
    mov  ax, cx
    inc  ax
    cmp  ax, [mode_count]
    jae  .wait_key
    inc  cx
    call show_cursor
    jmp  .wait_key

.chosen:
    ; 16-bit: ручной shl для индексации mode_list
    mov  ax, cx
    shl  ax, 1
    mov  di, ax
    mov  ax, [mode_list + di]
    mov  [vbe_mode], ax

    popa
    ret

;---------------------------------------------------------
show_cursor:
    pusha
    xor  bx, bx
.clr:
    cmp  bx, [mode_count]
    jae  .draw
    push bx
    mov  ax, bx
    add  ax, 2
    mov  dh, al
    xor  dl, dl
    mov  ah, 0x02
    xor  bh, bh
    int  0x10
    mov  al, ' '
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    pop  bx
    inc  bx
    jmp  .clr
.draw:
    mov  ax, cx
    add  ax, 2
    mov  dh, al
    xor  dl, dl
    mov  ah, 0x02
    xor  bh, bh
    int  0x10
    mov  al, '>'
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    popa
    ret

;---------------------------------------------------------
vbe_error:
    mov si, err_msg
    call print
.hang:
    hlt
    jmp .hang

;---------------------------------------------------------
; Данные
;---------------------------------------------------------
msg        db "kernel: scanning VBE modes...", 13, 10, 0
err_msg    db "kernel: VBE error / no suitable modes", 13, 10, 0

menu_title db 13, 10, "Available VBE modes (32bpp + LFB):", 13, 10, 0
menu_dot   db "] ", 0
menu_x     db "x", 0
menu_x32   db "x32  mode=", 0
menu_nl    db 13, 10, 0
menu_prompt db 13, 10, "Use arrows / number / Enter: ", 0
hex_prefix db "0x", 0

vbe_mode          dw 0
mode_list_offset  dw 0
mode_list_segment dw 0
mode_count        dw 0

MAX_MODES equ 64
mode_list times MAX_MODES*2 db 0

vbe_info  times 512 db 0
mode_info times 256 db 0
tmp_info  times 256 db 0

gdt_start:
    dq 0
gdt_code:
    dw 0xFFFF, 0x0000
    db 0x00, 10011010b, 11001111b, 0x00
gdt_data:
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 11001111b, 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

;---------------------------------------------------------
[bits 32]

protected_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    ; ---- framebuffer ----
    mov  eax, [mode_info + 0x28]        ; PhysBasePtr
    mov  [framebuffer], eax
    movzx eax, word [mode_info + 0x10]  ; pitch
    mov  [pitch], eax
    movzx eax, word [mode_info + 0x12]  ; width
    mov  [width], eax
    movzx eax, word [mode_info + 0x14]  ; height
    mov  [height], eax

    mov edi, [framebuffer]
    mov eax, [pitch]
    imul eax, [height]
    mov ecx, eax
    sub ecx, 4
.fillscreen:
    cmp ecx, 0
    je testsqare
    mov dword [edi+ecx], 0x00ffffff
    sub ecx, 4
    jmp .fillscreen
;по идее мы push ebx sub ecx,1 ладно разберу проще квадрат = херня с равными сторонами НО было бы лучше если бы
;мржно было еще по мимо квадрата рисовать прямоугольник Тогла ebx = размер по x eax = размер по y,
testsqare:
    mov dword [starty], 10
    mov dword [sqarey], 500
    mov dword [sqarex], 600
    mov dword [startx], 20
    mov edx, 0x00ff00ff
    call sqare
    jmp hang
sqare:
    ;ebx = x
    ;/call paint
    ; так нельзя тогда он будет рисовать не правильно
    ; edi = стартовый пиксель к сожалению придется испо хотя зачем квадраты рисовать редко значит можно в памяти хранить?
    ; возможно тогда удалю
    ; проще через переменные
    mov edi, [sqarey]
    mov ecx, [sqarex]
    mov eax, [startx]
    mov ebx, [starty]
    call .sqarexd
    mov edi, [sqarey]
    mov ecx, [sqarex]
    mov eax, [startx]
    mov ebx, [starty]
    call .sqarexy
    ret
.sqarexd:
    cmp ecx, 0
    je .end
    call paint

    add ebx, edi
    call paint
    sub ebx, edi

    sub ecx, 1
    add eax, 1
    jmp .sqarexd
.sqarexy:
    cmp edi, 0
    je .end
    call paint
    
    add eax, ecx
    call paint
    sub eax, ecx

    sub edi, 1
    add ebx, 1
    jmp .sqarexy
.end:
    ret

;.drawtestpixel:
    ;mov ebx, [height]
    ;shr ebx, 1
    ;mov eax, [width]
    ;shr eax, 1
    ;mov edx, 0x00000000
    ;call paint
    ;jmp hang
    ;ура пиксель рисуется щас попробую кввадрат
;пока я соображаю надо ch = x cl = y ну нет фигня так как ну умножать ни как значит память, тоже нет тогда 32 битные e [JNХОЯТ НЕТ IMul а тогда ax bx
;edx = color, ax = y, bx = x
;Я ДЕБИЛ ЗАЧЕМ НЕ ИСПОЛЬЗОВАТЬ 32 БИТНЫЕ
;eax = x (32-бит)
;ebx = y (32-бит)
;edx = цвет

;pitch читается как dword, imul ebx, [pitch] — 32-бит, без потерь
;shl eax, 2 — x * 4
;ebx = offset
;[edi + ebx] = адрес пикселя
;edx записывается
paint:
    push ebx
    push eax
    push edi
    imul ebx, [pitch]          
    shl  eax, 2                
    add  ebx, eax              

    mov  edi, [framebuffer]
    mov  [edi + ebx], edx       ; записать цвет
    pop edi
    pop eax
    pop ebx
    ret
hang:
    hlt
    jmp $

sqarex  dd 0
sqarey  dd 0
startx  dd 0
starty  dd 0
;---------------------------------------------------------
framebuffer dd 0
pitch       dd 0
width       dd 0
height      dd 0
times 516096 - ($ - $$) db 0
