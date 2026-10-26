bits 64
default rel
org 0x2000000

%define BOOT_INFO_FB      0
%define BOOT_INFO_WIDTH   8
%define BOOT_INFO_HEIGHT  12
%define BOOT_INFO_PITCH   16

%define C_BLACK   0x00000000
%define C_WHITE   0x00ffffff
%define C_RED     0x00ff0000
%define C_GREEN   0x0000ff00
%define C_BLUE    0x000000ff
%define C_CYAN    0x0000ffff
%define C_YELLOW  0x00ffff00
%define C_MAGENTA 0x00ff00ff
%define C_GRAY    0x00c0c0c0
%define C_DGRAY   0x00404040
%define C_ORANGE  0x00ff8000

%define FS_MAX_FILES  16
%define FS_MAX_NAME   32
%define FS_ENTRY_SIZE (16 + FS_MAX_NAME + 8)

kernel_entry:
    cld
    mov rbx, rdi

    lea rsp, [stack_top]
    mov rbp, rsp

    mov rdi, [rbx + BOOT_INFO_FB]
    mov esi, [rbx + BOOT_INFO_WIDTH]
    mov edx, [rbx + BOOT_INFO_HEIGHT]
    mov ecx, [rbx + BOOT_INFO_PITCH]

    mov [framebuffer], rdi
    mov [width],  rsi
    mov [height], rdx
    mov [pitch],  rcx

    call fs_init
    call draw_demo

system:
    in al, 0x80
    jmp system

; ------------------------------------------------------------------
pixel:                          ; r8=x, r9=y, eax=color
    push rdi
    push rsi
    mov rdi, [framebuffer]
    mov rsi, [pitch]
    imul rsi, r9
    lea rsi, [rsi + r8*4]
    mov [rdi + rsi], eax
    pop rsi
    pop rdi
    ret

; ------------------------------------------------------------------
fill_screen:                    ; eax=color
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    mov rdi, [framebuffer]
    mov rsi, [pitch]
    mov rcx, [height]
    imul rsi, rcx               ; total bytes
    mov r8d, eax
    xor ecx, ecx
.loop:
    cmp rcx, rsi
    jae .done
    mov [rdi + rcx], r8d
    add rcx, 4
    jmp .loop
.done:
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; ------------------------------------------------------------------
draw_line:                      ; r8=x0 r9=y0 r10=x1 r11=y1 eax=color
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov r12d, eax
    mov r13d, r10d
    sub r13d, r8d
    mov r14d, r11d
    sub r14d, r9d

    mov ebx, 1
    cmp r13d, 0
    jge .sx
    neg r13d
    mov ebx, -1
.sx:
    mov ecx, 1
    cmp r14d, 0
    jge .sy
    neg r14d
    mov ecx, -1
.sy:
    mov esi, r13d
    sub esi, r14d
.loop:
    mov eax, r12d
    call pixel
    cmp r8d, r10d
    jne .step
    cmp r9d, r11d
    jne .step
    jmp .done
.step:
    lea edi, [rsi+rsi]
    mov edx, r14d
    neg edx
    cmp edi, edx
    jl .nx
    sub esi, r14d
    add r8d, ebx
.nx:
    cmp edi, r13d
    jge .ny
    add esi, r13d
    add r9d, ecx
.ny:
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------------
fill_rect:                      ; r8=x r9=y r10=w r11=h eax=color
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13

    mov r12d, eax
    mov r13d, r10d
    mov ebx, r8d
    mov ecx, r9d
    mov esi, r11d
    xor edi, edi
.row:
    cmp edi, esi
    jge .done
    xor edx, edx
.col:
    cmp edx, r13d
    jge .nr
    mov r8d, ebx
    add r8d, edx
    mov r9d, ecx
    add r9d, edi
    mov eax, r12d
    call pixel
    inc edx
    jmp .col
.nr:
    inc edi
    jmp .row
.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------------
draw_rect:                      ; r8=x r9=y r10=w r11=h eax=color
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14

    mov r12d, eax
    mov r13d, r10d
    mov r14d, r11d
    mov ebx, r8d
    mov ecx, r9d

    xor edx, edx
.tb:
    cmp edx, r13d
    jge .sides
    mov r8d, ebx
    add r8d, edx
    mov r9d, ecx
    mov eax, r12d
    call pixel
    mov r8d, ebx
    add r8d, edx
    mov r9d, ecx
    add r9d, r14d
    dec r9d
    mov eax, r12d
    call pixel
    inc edx
    jmp .tb
.sides:
    xor edx, edx
.sl:
    cmp edx, r14d
    jge .done
    mov r8d, ebx
    mov r9d, ecx
    add r9d, edx
    mov eax, r12d
    call pixel
    mov r8d, ebx
    add r8d, r13d
    dec r8d
    mov r9d, ecx
    add r9d, edx
    mov eax, r12d
    call pixel
    inc edx
    jmp .sl
.done:
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------------
draw_circle:                    ; r8=cx r9=cy r10=r eax=color
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12d, eax
    mov r13d, r8d
    mov r14d, r9d
    mov r15d, r10d

    xor ebx, ebx
    mov ecx, r15d
    mov esi, 1
    sub esi, r15d
.loop:
    call .points
    cmp ebx, ecx
    jg .done
    cmp esi, 0
    jge .d_pos
    add esi, ebx
    add esi, ebx
    add esi, 3
    inc ebx
    jmp .loop
.d_pos:
    add esi, ebx
    add esi, ebx
    add esi, 5
    sub esi, ecx
    sub esi, ecx
    inc ebx
    dec ecx
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.points:
    push rax
    push rdx
    push r8
    push r9

    mov r8d, r13d
    add r8d, ebx
    mov r9d, r14d
    add r9d, ecx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    sub r8d, ebx
    mov r9d, r14d
    add r9d, ecx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    add r8d, ebx
    mov r9d, r14d
    sub r9d, ecx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    sub r8d, ebx
    mov r9d, r14d
    sub r9d, ecx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    add r8d, ecx
    mov r9d, r14d
    add r9d, ebx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    sub r8d, ecx
    mov r9d, r14d
    add r9d, ebx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    add r8d, ecx
    mov r9d, r14d
    sub r9d, ebx
    mov eax, r12d
    call pixel

    mov r8d, r13d
    sub r8d, ecx
    mov r9d, r14d
    sub r9d, ebx
    mov eax, r12d
    call pixel

    pop r9
    pop r8
    pop rdx
    pop rax
    ret

; ------------------------------------------------------------------
fill_circle:                    ; r8=cx r9=cy r10=r eax=color
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12d, eax
    mov r13d, r8d
    mov r14d, r9d
    mov r15d, r10d

    xor ebx, ebx
    mov ecx, r15d
    mov esi, 1
    sub esi, r15d
.loop:
    call .hlines
    cmp ebx, ecx
    jg .done
    cmp esi, 0
    jge .d_pos
    add esi, ebx
    add esi, ebx
    add esi, 3
    inc ebx
    jmp .loop
.d_pos:
    add esi, ebx
    add esi, ebx
    add esi, 5
    sub esi, ecx
    sub esi, ecx
    inc ebx
    dec ecx
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

.hlines:
    push rax
    push rdx
    push rdi
    push r8
    push r9
    push r10
    push r11

    mov r8d, r13d
    sub r8d, ebx
    mov r9d, r14d
    add r9d, ecx
    mov r10d, ebx
    add r10d, r10d
    inc r10d
    mov r11d, 1
    mov eax, r12d
    call fill_rect

    mov r8d, r13d
    sub r8d, ebx
    mov r9d, r14d
    sub r9d, ecx
    mov r10d, ebx
    add r10d, r10d
    inc r10d
    mov r11d, 1
    mov eax, r12d
    call fill_rect

    mov r8d, r13d
    sub r8d, ecx
    mov r9d, r14d
    add r9d, ebx
    mov r10d, ecx
    add r10d, r10d
    inc r10d
    mov r11d, 1
    mov eax, r12d
    call fill_rect

    mov r8d, r13d
    sub r8d, ecx
    mov r9d, r14d
    sub r9d, ebx
    mov r10d, ecx
    add r10d, r10d
    inc r10d
    mov r11d, 1
    mov eax, r12d
    call fill_rect

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rdx
    pop rax
    ret

; ------------------------------------------------------------------
clean:                          ; r8=start r9=end eax=1|2|4|8
    cmp r8, r9
    jae .done
    cmp eax, 1
    je .b1
    cmp eax, 2
    je .b2
    cmp eax, 4
    je .b4
    cmp eax, 8
    je .b8
    ret
.b1: mov byte  [r8], 0
     inc r8
     cmp r8, r9
     jb .b1
     ret
.b2: mov word  [r8], 0
     add r8, 2
     cmp r8, r9
     jb .b2
     ret
.b4: mov dword [r8], 0
     add r8, 4
     cmp r8, r9
     jb .b4
     ret
.b8: mov qword [r8], 0
     add r8, 8
     cmp r8, r9
     jb .b8
     ret
.done:
    ret

; ------------------------------------------------------------------
fs_init:
    mov qword [fs_count], 0
    ret

; rdi=name rsi=len rdx=data rcx=datalen -> rax=index|-1
fs_create:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx

    mov rax, [fs_count]
    cmp rax, FS_MAX_FILES
    jge .fail

    imul rax, FS_ENTRY_SIZE
    lea rdi, [fs_table]
    add rdi, rax

    cmp r13, FS_MAX_NAME
    jbe .name_ok
    mov r13, FS_MAX_NAME
.name_ok:
    mov [rdi + 0], r13
    mov [rdi + 8], r15
    mov [rdi + 16 + FS_MAX_NAME], r14

    add rdi, 16
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb

    mov rax, [fs_count]
    inc qword [fs_count]
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; rdi=name rsi=len -> rax=index|-1
fs_find:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov r8, rdi
    mov r9, rsi
    xor r10, r10
.loop:
    cmp r10, [fs_count]
    jae .fail
    imul rax, r10, FS_ENTRY_SIZE
    lea rdi, [fs_table]
    add rdi, rax
    mov rcx, [rdi + 0]
    cmp rcx, r9
    jne .next
    add rdi, 16
    mov rsi, r8
    xor rcx, rcx
.cmp:
    cmp rcx, r9
    jae .found
    mov al, [rdi + rcx]
    mov dl, [rsi + rcx]
    cmp al, dl
    jne .next
    inc rcx
    jmp .cmp
.found:
    mov rax, r10
    jmp .done
.next:
    inc r10
    jmp .loop
.fail:
    mov rax, -1
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ------------------------------------------------------------------
keyboard_poll:
    in al, 0x64
    test al, 1
    jz .done
    in al, 0x60
    mov [last_key], al
.done:
    ret

; ------------------------------------------------------------------
draw_demo:
    mov eax, C_BLACK
    call fill_screen

    ; рамка
    mov eax, C_DGRAY
    xor r8, r8
    xor r9, r9
    mov r10, [width]
    dec r10
    xor r11, r11
    call draw_line

    mov eax, C_DGRAY
    xor r8, r8
    mov r9, [height]
    dec r9
    mov r10, [width]
    dec r10
    xor r11, r11
    call draw_line

    ; прямоугольник
    mov eax, C_RED
    mov r8, 100
    mov r9, 100
    mov r10, 200
    mov r11, 150
    call fill_rect

    mov eax, C_WHITE
    mov r8, 100
    mov r9, 100
    mov r10, 200
    mov r11, 150
    call draw_rect

    ; круг
    mov eax, C_CYAN
    mov r8, 500
    mov r9, 350
    mov r10, 120
    call fill_circle

    mov eax, C_YELLOW
    mov r8, 500
    mov r9, 350
    mov r10, 120
    call draw_circle

    ; диагональ
    mov eax, C_GREEN
    mov r8, 200
    mov r9, 400
    mov r10, 500
    mov r11, 500
    call draw_line

    ; ещё блок
    mov eax, C_MAGENTA
    mov r8, 700
    mov r9, 50
    mov r10, 100
    mov r11, 150
    call fill_rect

    mov eax, C_ORANGE
    mov r8, 700
    mov r9, 50
    mov r10, 100
    mov r11, 150
    call draw_rect

    ret

hang:
    cli
    hlt
    jmp hang

; ------------------------------------------------------------------
section .data
align 16
framebuffer  dq 0
width        dq 0
height       dq 0
pitch        dq 0
fs_count     dq 0
last_key     db 0
align 16
fs_table     times (FS_ENTRY_SIZE * FS_MAX_FILES) db 0
align 16
stack_bottom times 65536 db 0
stack_top:
