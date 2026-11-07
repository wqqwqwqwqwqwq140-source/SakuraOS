bits 64
default rel
org 0x2000000

%define BI_FB       0
%define BI_W        8
%define BI_H        12
%define BI_PITCH    16

%define C_BLACK     0x00000000
%define C_WHITE     0x00FFFFFF
%define C_RED       0x00FF0000
%define C_GREEN     0x0000FF00
%define C_BLUE      0x000000FF
%define C_CYAN      0x0000FFFF
%define C_YELLOW    0x00FFFF00
%define C_MAGENTA   0x00FF00FF
%define C_GRAY      0x00C0C0C0
%define C_DGRAY     0x00404040
%define C_ORANGE    0x00FF8000
%define C_LGRAY     0x00E0E0E0

%define HEAP_START  0x4000000
%define HEAP_END    0x8000000
%define KBD_MASK    15
%define PIT_FREQ    1000

%define FS_MAGIC        0x4F53464B
%define FS_VERSION      1
%define FS_MAX_FILES    64
%define FS_NAME_MAX     32
%define FS_DATA_START   0x5000000
%define FS_DATA_END     0x7000000
%define FS_DATA_SIZE    (FS_DATA_END - FS_DATA_START)
%define FS_INODE_SIZE   128
%define FS_INODE_HDR    64

%define CON_CW          8
%define CON_CH          8

kernel_entry:
    cld
    cli
    mov rbx, rdi
    lea rsp, [stack_top]
    mov rbp, rsp
    mov rdi, [rbx + BI_FB]
    mov esi, [rbx + BI_W]
    mov edx, [rbx + BI_H]
    mov ecx, [rbx + BI_PITCH]
    mov [framebuffer], rdi
    mov [width], rsi
    mov [height], rdx
    mov [pitch], rcx
    mov [render_fb], rdi
    mov [render_pitch], rcx
    mov qword [heap_cur], HEAP_START
    call init_fb_buffers
    call init_gdt
    call init_idt
    call init_pic
    call init_pit
    call kbd_init
    call fs_init
    call con_init
    sti
    call kernel_main
.hang:
    cli
    hlt
    jmp .hang

kernel_main:
    call con_clear
    lea rdi, [msg_kernel_loaded]
    call con_puts_utf8
    call con_newline
    call con_flush
    call os_user_init
.main:
    sti
    hlt
    cli
    call os_user_tick
    cmp qword [con_dirty], 0
    je .main
    call con_flush
    jmp .main

os_user_init:
    ret

os_user_tick:
    call kbd_poll_char
    test al, al
    jz .done
    movzx edi, al
    call con_putc
.done:
    ret

panic:
    cli
    push rdi
    lea rdi, [msg_panic]
    call con_puts
    pop rdi
    call con_puts
    call con_newline
    call con_flush
.h:
    hlt
    jmp .h

halt:
    cli
.h:
    hlt
    jmp .h

reboot:
    cli
    mov al, 0x06
    out 0xCF9, al
.h:
    hlt
    jmp .h

init_gdt:
    lgdt [gdtr]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    push 0x08
    lea rax, [.reload_cs]
    push rax
    retfq
.reload_cs:
    ret

init_idt:
    lea rdi, [idt]
    lea rax, [isr_default]
    mov rcx, 256
.fill:
    call .set_entry
    add rdi, 16
    dec rcx
    jnz .fill
    lea rdi, [idt + 0x20*16]
    lea rax, [irq_timer]
    call .set_entry
    lea rdi, [idt + 0x21*16]
    lea rax, [irq_keyboard]
    call .set_entry
    lea rax, [idtr]
    mov word [rax], 256*16 - 1
    lea rbx, [idt]
    mov [rax + 2], rbx
    lidt [rax]
    ret
.set_entry:
    mov word [rdi + 0], ax
    shr rax, 16
    mov word [rdi + 6], ax
    shr rax, 16
    mov dword [rdi + 8], eax
    mov word [rdi + 2], 0x08
    mov byte [rdi + 4], 0
    mov byte [rdi + 5], 0x8E
    ret

init_pic:
    mov al, 0x11
    out 0x20, al
    out 0xa0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xa1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xa1, al
    mov al, 0x01
    out 0x21, al
    out 0xa1, al
    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xa1, al
    ret

init_pit:
    mov al, 0x36
    out 0x43, al
    mov ax, 1193182 / PIT_FREQ
    out 0x40, al
    mov al, ah
    out 0x40, al
    ret

isr_default:
    cli
.h:
    hlt
    jmp .h

irq_timer:
    push rax
    inc qword [ticks]
    mov al, 0x20
    out 0x20, al
    pop rax
    iretq

irq_keyboard:
    push rax
    push rbx
    push rcx
    in al, 0x60
    movzx eax, al
    cmp al, 0x2A
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xAA
    je .shift_off
    cmp al, 0xB6
    je .shift_off
    test al, 0x80
    jnz .release
    cmp eax, 127
    ja .release
    cmp qword [kbd_layout], 0
    je .us
    lea rbx, [scancode_ascii_ru]
    jmp .lookup
.us:
    lea rbx, [scancode_ascii]
.lookup:
    movzx eax, byte [rbx + rax]
    test al, al
    jz .release
    cmp qword [kbd_shift], 0
    je .emit
    cmp qword [kbd_layout], 0
    jne .ru_shift
    cmp al, 'a'
    jb .emit
    cmp al, 'z'
    ja .emit
    sub al, 0x20
    jmp .emit
.ru_shift:
    cmp al, 0xB8
    je .yo_shift
    cmp al, 0xE0
    jb .emit
    cmp al, 0xFF
    ja .emit
    sub al, 0x20
    jmp .emit
.yo_shift:
    sub al, 0x10
    jmp .emit
.emit:
    mov rbx, [key_tail]
    mov rcx, rbx
    inc rcx
    and rcx, KBD_MASK
    cmp rcx, [key_head]
    je .release
    mov [key_buffer + rbx], al
    mov [key_tail], rcx
    jmp .release
.shift_on:
    mov qword [kbd_shift], 1
    jmp .release
.shift_off:
    mov qword [kbd_shift], 0
.release:
    mov al, 0x20
    out 0x20, al
    pop rcx
    pop rbx
    pop rax
    iretq

kmalloc:
    push rbx
    add rdi, 15
    and rdi, -16
    mov rax, [heap_cur]
    mov rbx, rax
    add rax, rdi
    cmp rax, HEAP_END
    ja .fail
    mov [heap_cur], rax
    mov rax, rbx
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

memset:
    mov rax, rdi
    mov rcx, rdx
    mov r8b, sil
.l:
    test rcx, rcx
    jz .e
    mov [rdi], r8b
    inc rdi
    dec rcx
    jmp .l
.e:
    ret

memcpy:
    mov rax, rdi
    mov rcx, rdx
    cld
    rep movsb
    ret

memmove:
    mov rax, rdi
    cmp rdi, rsi
    jbe .fwd
    mov rcx, rsi
    add rcx, rdx
    cmp rdi, rcx
    jae .fwd
    mov rcx, rdx
    test rcx, rcx
    jz .e
    add rdi, rcx
    add rsi, rcx
    std
    rep movsb
    cld
    ret
.fwd:
    mov rcx, rdx
    cld
    rep movsb
.e:
    ret

memcmp:
    xor rcx, rcx
.l:
    cmp rcx, rdx
    jae .eq
    mov al, [rdi + rcx]
    mov r8b, [rsi + rcx]
    cmp al, r8b
    jne .ne
    inc rcx
    jmp .l
.eq:
    xor eax, eax
    ret
.ne:
    movzx eax, al
    movzx r8d, r8b
    sub eax, r8d
    ret

strlen:
    xor rax, rax
.l:
    cmp byte [rdi + rax], 0
    je .e
    inc rax
    jmp .l
.e:
    ret

strcmp:
.l:
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, dl
    jne .ne
    test al, al
    jz .eq
    inc rdi
    inc rsi
    jmp .l
.eq:
    xor eax, eax
    ret
.ne:
    movzx eax, al
    movzx edx, dl
    sub eax, edx
    ret

strncmp:
    xor rcx, rcx
.l:
    cmp rcx, rdx
    jae .eq
    mov al, [rdi + rcx]
    mov r8b, [rsi + rcx]
    cmp al, r8b
    jne .ne
    test al, al
    jz .eq
    inc rcx
    jmp .l
.eq:
    xor eax, eax
    ret
.ne:
    movzx eax, al
    movzx r8d, r8b
    sub eax, r8d
    ret

strcpy:
.l:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .e
    inc rdi
    inc rsi
    jmp .l
.e:
    ret

strncpy:
    xor rcx, rcx
.l:
    cmp rcx, rdx
    jae .pad
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .pad
    inc rcx
    jmp .l
.pad:
    cmp rcx, rdx
    jae .e
    mov byte [rdi + rcx], 0
    inc rcx
    jmp .pad
.e:
    ret

init_fb_buffers:
    mov rdi, [pitch]
    imul rdi, [height]
    call kmalloc
    test rax, rax
    jz .no_bb
    mov [backbuffer], rax
    mov [render_fb], rax
    mov rax, [pitch]
    mov [render_pitch], rax
    ret
.no_bb:
    mov rax, [framebuffer]
    mov [render_fb], rax
    mov rax, [pitch]
    mov [render_pitch], rax
    ret

swap_buffers:
    cmp qword [backbuffer], 0
    je .done
    push rax
    push rcx
    push rsi
    push rdi
    cld
    mov rdi, [framebuffer]
    mov rsi, [backbuffer]
    mov rcx, [pitch]
    imul rcx, [height]
    mov rax, rcx
    shr rcx, 3
    rep movsq
    and rax, 7
    mov rcx, rax
    rep movsb
    pop rdi
    pop rsi
    pop rcx
    pop rax
.done:
    ret

pixel:
    push rdi
    push rsi
    push rdx
    mov edx, dword [width]
    cmp r8d, edx
    jae .out
    mov edx, dword [height]
    cmp r9d, edx
    jae .out
    mov rdi, [render_fb]
    mov rsi, [render_pitch]
    imul rsi, r9
    lea rsi, [rsi + r8*4]
    mov [rdi + rsi], eax
.out:
    pop rdx
    pop rsi
    pop rdi
    ret

fill_screen:
    push rdi
    push rcx
    mov rdi, [render_fb]
    mov rcx, [render_pitch]
    imul rcx, [height]
    shr rcx, 2
    cld
    rep stosd
    pop rcx
    pop rdi
    ret

fill_rect:
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
    mov r13d, r10d
    mov r14d, r8d
    mov r15d, r9d
    mov ebx, r11d
    xor edi, edi
.row:
    cmp edi, ebx
    jge .done
    xor edx, edx
.col:
    cmp edx, r13d
    jge .nr
    lea r8d, [r14d + edx]
    lea r9d, [r15d + edi]
    mov eax, r12d
    call pixel
    inc edx
    jmp .col
.nr:
    inc edi
    jmp .row
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

draw_rect:
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
    mov r13d, r10d
    mov r14d, r11d
    mov r15d, r8d
    mov ebx, r9d
    xor edx, edx
.tb:
    cmp edx, r13d
    jge .sides
    lea r8d, [r15d + edx]
    mov r9d, ebx
    mov eax, r12d
    call pixel
    lea r8d, [r15d + edx]
    lea r9d, [ebx + r14d - 1]
    mov eax, r12d
    call pixel
    inc edx
    jmp .tb
.sides:
    xor edx, edx
.sl:
    cmp edx, r14d
    jge .done
    mov r8d, r15d
    lea r9d, [ebx + edx]
    mov eax, r12d
    call pixel
    lea r8d, [r15d + r13d - 1]
    lea r9d, [ebx + edx]
    mov eax, r12d
    call pixel
    inc edx
    jmp .sl
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

draw_line:
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
    mov r15d, r13d
    mov esi, r13d
    sub esi, r14d
    mov [save_color], r12d
    mov [save_x1], r10
    mov [save_y1], r11
.loop:
    mov eax, [save_color]
    call pixel
    mov r10, [save_x1]
    mov r11, [save_y1]
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
    cmp edi, r15d
    jg .ny
    add esi, r15d
    add r9d, ecx
.ny:
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

draw_char:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r11
    push r12
    push r13
    cmp r10d, 32
    jb .done
    sub r10d, 32
    shl r10d, 3
    lea rsi, [font8x8]
    add rsi, r10
    mov r12d, eax
    mov r13d, r8d
    mov ebx, r9d
    xor ecx, ecx
.row:
    cmp ecx, 8
    jge .done
    movzx edx, byte [rsi + rcx]
    xor edi, edi
.col:
    cmp edi, 8
    jge .next_row
    test dl, 0x80
    jz .skip
    lea r8d, [r13d + edi]
    lea r9d, [ebx + ecx]
    mov eax, r12d
    call pixel
.skip:
    shl dl, 1
    inc edi
    jmp .col
.next_row:
    inc ecx
    jmp .row
.done:
    pop r13
    pop r12
    pop r11
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

draw_text:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    mov r12d, r8d
    mov r13d, r9d
    mov r14d, eax
    mov r15, rdi
.loop:
    movzx r10d, byte [r15]
    test r10d, r10d
    jz .done
    mov r8d, r12d
    mov r9d, r13d
    mov eax, r14d
    call draw_char
    add r12d, 8
    inc r15
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

con_init:
    mov rax, [width]
    xor rdx, rdx
    mov rcx, CON_CW
    div rcx
    mov [con_cols], rax
    mov rax, [height]
    xor rdx, rdx
    mov rcx, CON_CH
    div rcx
    mov [con_rows], rax
    mov rdi, [con_cols]
    imul rdi, [con_rows]
    call kmalloc
    test rax, rax
    jz halt
    mov [con_textbuf], rax
    mov qword [con_fg], C_LGRAY
    mov qword [con_bg], C_BLACK
    mov qword [con_cur_x], 0
    mov qword [con_cur_y], 0
    mov qword [con_dirty], 1
    call con_clear
    ret

con_clear:
    push rdi
    push rcx
    mov rdi, [con_textbuf]
    mov rcx, [con_cols]
    imul rcx, [con_rows]
    mov al, ' '
    cld
    rep stosb
    mov qword [con_cur_x], 0
    mov qword [con_cur_y], 0
    mov qword [con_dirty], 1
    pop rcx
    pop rdi
    ret

con_putc:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    movzx eax, dil
    cmp al, 10
    je .lf
    cmp al, 13
    je .cr
    cmp al, 8
    je .bs
    mov rbx, [con_cur_y]
    imul rbx, [con_cols]
    add rbx, [con_cur_x]
    mov rdi, [con_textbuf]
    mov [rdi + rbx], al
    inc qword [con_cur_x]
    mov rax, [con_cols]
    cmp [con_cur_x], rax
    jb .dirty
    mov qword [con_cur_x], 0
    inc qword [con_cur_y]
    call .check_scroll
.dirty:
    mov qword [con_dirty], 1
    jmp .done
.lf:
    mov qword [con_cur_x], 0
    inc qword [con_cur_y]
    call .check_scroll
    mov qword [con_dirty], 1
    jmp .done
.cr:
    mov qword [con_cur_x], 0
    mov qword [con_dirty], 1
    jmp .done
.bs:
    cmp qword [con_cur_x], 0
    je .done
    dec qword [con_cur_x]
    mov rbx, [con_cur_y]
    imul rbx, [con_cols]
    add rbx, [con_cur_x]
    mov rdi, [con_textbuf]
    mov byte [rdi + rbx], ' '
    mov qword [con_dirty], 1
    jmp .done
.check_scroll:
    mov rax, [con_cur_y]
    cmp rax, [con_rows]
    jb .noscroll
    push rdi
    push rsi
    push rcx
    mov rdi, [con_textbuf]
    mov rsi, rdi
    mov rcx, [con_cols]
    add rsi, rcx
    mov rcx, [con_cols]
    imul rcx, [con_rows]
    sub rcx, [con_cols]
    cld
    rep movsb
    mov rdi, [con_textbuf]
    mov rcx, [con_cols]
    imul rcx, [con_rows]
    sub rcx, [con_cols]
    add rdi, rcx
    mov rcx, [con_cols]
    mov al, ' '
    rep stosb
    dec qword [con_cur_y]
    pop rcx
    pop rsi
    pop rdi
.noscroll:
    ret
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

con_puts:
    push r12
    mov r12, rdi
.l:
    movzx edi, byte [r12]
    test edi, edi
    jz .done
    call con_putc
    inc r12
    jmp .l
.done:
    pop r12
    ret

utf8_decode:
    push rbx
    push rcx
    movzx eax, byte [rdi]
    mov esi, 1
    cmp al, 0x80
    jb .done
    cmp al, 0xE0
    jae .invalid
    movzx ebx, byte [rdi + 1]
    cmp al, 0xD0
    je .d0
    cmp al, 0xD1
    je .d1
    jmp .invalid
.d0:
    cmp bl, 0x81
    je .yo
    cmp bl, 0x90
    jb .invalid
    cmp bl, 0xBF
    ja .invalid
    movzx eax, bl
    add eax, 0x30
    mov esi, 2
    jmp .done
.yo:
    mov eax, 0xA8
    mov esi, 2
    jmp .done
.d1:
    cmp bl, 0x91
    je .yo_s
    cmp bl, 0x80
    jb .invalid
    cmp bl, 0x8F
    ja .invalid
    movzx eax, bl
    add eax, 0x70
    mov esi, 2
    jmp .done
.yo_s:
    mov eax, 0xB8
    mov esi, 2
    jmp .done
.invalid:
    xor eax, eax
.done:
    pop rcx
    pop rbx
    ret

con_puts_utf8:
    push r12
    mov r12, rdi
.l:
    movzx eax, byte [r12]
    test al, al
    jz .done
    mov rdi, r12
    call utf8_decode
    test eax, eax
    jz .skip
    mov edi, eax
    call con_putc
    add r12, rsi
    jmp .l
.skip:
    inc r12
    jmp .l
.done:
    pop r12
    ret

con_putu:
    push rbx
    push rcx
    push rdx
    push rsi
    sub rsp, 40
    mov rbx, rdi
    mov r8, rsi
    mov rcx, 32
.num:
    xor rdx, rdx
    mov rax, rbx
    div r8
    mov rbx, rax
    mov eax, edx
    cmp al, 10
    jb .d
    add al, 'A' - 10
    jmp .s
.d:
    add al, '0'
.s:
    dec rcx
    mov [rsp + rcx], al
    test rbx, rbx
    jnz .num
    mov byte [rsp + 32], 0
    lea rdi, [rsp + rcx]
    call con_puts
    add rsp, 40
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

con_newline:
    mov edi, 10
    jmp con_putc

con_gotoxy:
    mov [con_cur_x], rdi
    mov [con_cur_y], rsi
    mov qword [con_dirty], 1
    ret

con_flush:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax, [con_bg]
    call fill_screen
    xor r14d, r14d
.row:
    cmp r14d, [con_rows]
    jae .done
    xor r15d, r15d
.col:
    cmp r15d, [con_cols]
    jae .nr
    mov rax, r14
    imul rax, [con_cols]
    add rax, r15
    mov rdi, [con_textbuf]
    movzx r10d, byte [rdi + rax]
    cmp r10d, ' '
    jbe .skip
    mov r8d, r15d
    shl r8d, 3
    mov r9d, r14d
    shl r9d, 3
    mov eax, [con_fg]
    call draw_char
.skip:
    inc r15d
    jmp .col
.nr:
    inc r14d
    jmp .row
.done:
    call swap_buffers
    mov qword [con_dirty], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kprintf:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov [rsp + 0], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    mov [rsp + 24], r8
    mov [rsp + 32], r9
    xor ebx, ebx
.loop:
    movzx eax, byte [r12]
    test al, al
    jz .done
    cmp al, '%'
    je .fmt
    movzx edi, al
    call con_putc
    inc r12
    jmp .loop
.fmt:
    inc r12
    movzx eax, byte [r12]
    test al, al
    jz .done
    cmp al, 's'
    je .do_s
    cmp al, 'S'
    je .do_S
    cmp al, 'd'
    je .do_d
    cmp al, 'u'
    je .do_u
    cmp al, 'x'
    je .do_x
    cmp al, 'c'
    je .do_c
    cmp al, '%'
    je .do_pct
    movzx edi, al
    call con_putc
    inc r12
    jmp .loop
.do_s:
    mov rdi, [rsp + rbx*8]
    call con_puts
    inc rbx
    inc r12
    jmp .loop
.do_S:
    mov rdi, [rsp + rbx*8]
    call con_puts_utf8
    inc rbx
    inc r12
    jmp .loop
.do_c:
    mov rdi, [rsp + rbx*8]
    call con_putc
    inc rbx
    inc r12
    jmp .loop
.do_u:
    mov rdi, [rsp + rbx*8]
    mov esi, 10
    call con_putu
    inc rbx
    inc r12
    jmp .loop
.do_x:
    mov rdi, [rsp + rbx*8]
    mov esi, 16
    call con_putu
    inc rbx
    inc r12
    jmp .loop
.do_d:
    mov rax, [rsp + rbx*8]
    test rax, rax
    jns .do_d_pos
    push rax
    mov edi, '-'
    call con_putc
    pop rax
    neg rax
.do_d_pos:
    mov rdi, rax
    mov esi, 10
    call con_putu
    inc rbx
    inc r12
    jmp .loop
.do_pct:
    mov edi, '%'
    call con_putc
    inc r12
    jmp .loop
.done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kbd_init:
    ret

kbd_set_layout:
    mov [kbd_layout], rdi
    ret

kbd_poll_char:
    push rbx
    mov rbx, [key_head]
    cmp rbx, [key_tail]
    je .empty
    movzx eax, byte [key_buffer + rbx]
    inc rbx
    and rbx, KBD_MASK
    mov [key_head], rbx
    pop rbx
    ret
.empty:
    xor eax, eax
    pop rbx
    ret

kbd_getchar:
    call kbd_poll_char
    test al, al
    jz kbd_getchar
    ret

get_ticks:
    mov rax, [ticks]
    ret

delay_ms:
    push rbx
    mov rbx, [ticks]
    add rbx, rdi
.wait:
    cmp qword [ticks], rbx
    jae .done
    sti
    hlt
    cli
    jmp .wait
.done:
    pop rbx
    ret

fs_init:
    cmp qword [fs_super], FS_MAGIC
    je .ok
    call fs_format
.ok:
    ret

fs_format:
    push rdi
    push rcx
    push rax
    lea rdi, [fs_super]
    mov qword [rdi + 0], FS_MAGIC
    mov qword [rdi + 8], FS_VERSION
    mov qword [rdi + 16], 0
    mov qword [rdi + 24], 0
    mov qword [rdi + 32], FS_MAX_FILES
    mov qword [rdi + 40], FS_DATA_START
    mov qword [rdi + 48], FS_DATA_END
    mov qword [rdi + 56], 0
    lea rdi, [fs_inodes]
    mov rcx, FS_INODE_SIZE * FS_MAX_FILES / 8
    xor rax, rax
    cld
    rep stosq
    pop rax
    pop rcx
    pop rdi
    ret

fs_new_inode:
    push rbx
    push rcx
    mov rcx, FS_MAX_FILES
    xor rax, rax
.l:
    cmp rax, rcx
    jae .fail
    imul rdx, rax, FS_INODE_SIZE
    lea rbx, [fs_inodes]
    add rbx, rdx
    cmp qword [rbx + 0], 0
    je .found
    inc rax
    jmp .l
.fail:
    mov rax, -1
.found:
    pop rcx
    pop rbx
    ret

fs_get_inode:
    cmp rdi, FS_MAX_FILES
    jae .fail
    imul rax, rdi, FS_INODE_SIZE
    lea rdx, [fs_inodes]
    add rax, rdx
    ret
.fail:
    xor eax, eax
    ret

fs_checksum:
    xor rax, rax
    xor rcx, rcx
.l:
    cmp rcx, rsi
    jae .d
    movzx edx, byte [rdi + rcx]
    add rax, rdx
    inc rcx
    jmp .l
.d:
    ret

fs_lookup:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov r8, rdi
    mov r9, rsi
    mov r10, [fs_super + 16]
    xor r11, r11
.loop:
    cmp r11, r10
    jae .fail
    imul rax, r11, FS_INODE_SIZE
    lea rdi, [fs_inodes]
    add rdi, rax
    cmp qword [rdi + 0], 0
    je .next
    mov rcx, [rdi + 8]
    cmp rcx, r9
    jne .next
    add rdi, FS_INODE_HDR
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
    mov rax, r11
    jmp .done
.next:
    inc r11
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

fs_create:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rax, [fs_super + 16]
    cmp rax, FS_MAX_FILES
    jae .fail
    mov rdi, r12
    mov rsi, r13
    call fs_lookup
    cmp rax, -1
    jne .fail
    call fs_new_inode
    cmp rax, -1
    je .fail
    mov r15, rax
    mov rdi, r15
    call fs_get_inode
    mov rbx, rax
    mov qword [rbx + 0], 1
    mov [rbx + 8], r13
    mov qword [rbx + 16], 0
    mov [rbx + 24], r14
    mov qword [rbx + 32], 0
    mov qword [rbx + 40], 0
    mov qword [rbx + 48], 0
    lea rdi, [rbx + FS_INODE_HDR]
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    mov rcx, FS_NAME_MAX
    sub rcx, r13
    xor al, al
    rep stosb
    lea rdi, [rbx + FS_INODE_HDR]
    mov rsi, FS_NAME_MAX
    call fs_checksum
    mov [rbx + 40], rax
    inc qword [fs_super + 16]
    mov rax, r15
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_open:
    call fs_lookup
    cmp rax, -1
    je .done
    imul rdx, rax, 4
    lea rcx, [fs_fd_pos]
    mov dword [rcx + rdx], 0
.done:
    ret

fs_close:
    ret

fs_seek:
    cmp rdi, FS_MAX_FILES
    jae .fail
    imul rdx, rdi, 4
    lea rcx, [fs_fd_pos]
    mov [rcx + rdx], esi
    xor eax, eax
    ret
.fail:
    mov rax, -1
    ret

fs_read:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r14, FS_MAX_FILES
    jae .fail
    mov rdi, r14
    call fs_get_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp qword [rbx + 0], 0
    je .fail
    imul rdx, r14, 4
    lea rcx, [fs_fd_pos]
    mov r15d, [rcx + rdx]
    mov rax, [rbx + 16]
    sub rax, r15
    jbe .eof
    cmp rax, r13
    jbe .have
    mov rax, r13
.have:
    mov r8, rax
    mov r9, [rbx + 32]
    add r9, FS_DATA_START
    add r9, r15
    mov rdi, r12
    mov rsi, r9
    mov rcx, r8
    cld
    rep movsb
    add r15, r8
    imul rdx, r14, 4
    lea rcx, [fs_fd_pos]
    mov [rcx + rdx], r15d
    mov rax, r8
    jmp .done
.eof:
    xor eax, eax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_write:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r14, FS_MAX_FILES
    jae .fail
    mov rdi, r14
    call fs_get_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp qword [rbx + 0], 0
    je .fail
    cmp qword [rbx + 32], 0
    je .new_alloc
    cmp qword [rbx + 48], 0
    je .new_alloc
    cmp [rbx + 48], r13
    jae .do_copy
.new_alloc:
    mov rdi, [fs_super + 24]
    add rdi, r13
    cmp rdi, FS_DATA_SIZE
    ja .fail
    mov rax, [fs_super + 24]
    mov [rbx + 32], rax
    mov [rbx + 48], r13
    mov rdi, [fs_super + 24]
    add rdi, r13
    mov [fs_super + 24], rdi
.do_copy:
    mov r15, [rbx + 32]
    add r15, FS_DATA_START
    mov rdi, r15
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    mov [rbx + 16], r13
    mov rax, r13
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_delete:
    push rbx
    push r12
    mov r12, rdi
    call fs_lookup
    cmp rax, -1
    je .fail
    mov rdi, rax
    call fs_get_inode
    mov qword [rax + 0], 0
    mov qword [rax + 32], 0
    mov qword [rax + 48], 0
    dec qword [fs_super + 16]
    xor eax, eax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r12
    pop rbx
    ret

fs_list:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    xor r14, r14
    xor r15, r15
.loop:
    cmp r15, FS_MAX_FILES
    jae .done
    imul rax, r15, FS_INODE_SIZE
    lea rbx, [fs_inodes]
    add rbx, rax
    cmp qword [rbx + 0], 0
    je .next
    mov rcx, [rbx + 8]
    mov rax, r14
    add rax, rcx
    add rax, 2
    cmp rax, r13
    jae .done
    lea rsi, [rbx + FS_INODE_HDR]
    mov rdi, r12
    add rdi, r14
    push rcx
    cld
    rep movsb
    pop rcx
    add r14, rcx
    mov rdi, r12
    add rdi, r14
    mov byte [rdi], 10
    inc r14
.next:
    inc r15
    jmp .loop
.done:
    lea rdi, [r12 + r14]
    mov byte [rdi], 0
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data
align 16

framebuffer     dq 0
width           dq 0
height          dq 0
pitch           dq 0

backbuffer      dq 0
render_fb       dq 0
render_pitch    dq 0

heap_cur        dq 0

ticks           dq 0

key_head        dq 0
key_tail        dq 0
key_buffer      times 16 db 0
kbd_layout      dq 0
kbd_shift       dq 0

con_textbuf     dq 0
con_cols        dq 0
con_rows        dq 0
con_cur_x       dq 0
con_cur_y       dq 0
con_dirty       dq 0
con_fg          dq C_LGRAY
con_bg          dq C_BLACK

save_color      dd 0
save_x1         dq 0
save_y1         dq 0

fs_super:
    times 64 db 0

align 16
fs_inodes:
    times (FS_INODE_SIZE * FS_MAX_FILES) db 0

align 16
fs_fd_pos:
    times (FS_MAX_FILES * 4) db 0

msg_kernel_loaded db "Ядро загруженно!", 0
msg_panic         db "PANIC: ", 0

align 16
idt:
    times (256*16) db 0
idtr:
    dw 0
    dq 0

align 16
gdt:
    dq 0
    dq 0x00AF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:
gdtr:
    dw gdt_end - gdt - 1
    dq gdt

align 16
stack_bottom:
    times 65536 db 0
stack_top:

align 16
scancode_ascii:
    db 0, 27
    db '1','2','3','4','5','6','7','8','9','0','-','='
    db 8, 9
    db 'q','w','e','r','t','y','u','i','o','p','[',']'
    db 10, 0
    db 'a','s','d','f','g','h','j','k','l',';',0x27,'`'
    db 0, 0x5C
    db 'z','x','c','v','b','n','m',',','.','/'
    db 0, '*'
    db 0, ' '
    times 70 db 0

align 16
scancode_ascii_ru:
    db 0, 27
    db '1','2','3','4','5','6','7','8','9','0','-','='
    db 8, 9
    db 0xE9,0xF6,0xF3,0xEA,0xE5,0xED,0xE3,0xF8,0xF9,0xE7,0xF5,0xFA
    db 10, 0
    db 0xF4,0xFB,0xE2,0xE0,0xEF,0xF0,0xEE,0xEB,0xE4,0xE6,0xFD,0xB8
    db 0, 0x5C
    db 0xFF,0xF7,0xF1,0xEC,0xE8,0xF2,0xFC,0xE1,0xFE,0x2F
    db 0, '*'
    db 0, ' '
    times 70 db 0

align 16
font8x8:
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x18,0x18,0x18,0x18,0x00,0x00,0x18,0x00
    db 0x6C,0x6C,0x48,0x00,0x00,0x00,0x00,0x00
    db 0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0x00
    db 0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00
    db 0x00,0xC6,0xCC,0x18,0x30,0x66,0xC6,0x00
    db 0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00
    db 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00
    db 0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00
    db 0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00
    db 0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00
    db 0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30
    db 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00
    db 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00
    db 0x3C,0x66,0x6E,0x7E,0x76,0x66,0x3C,0x00
    db 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00
    db 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00
    db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00
    db 0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00
    db 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00
    db 0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00
    db 0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00
    db 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00
    db 0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00
    db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00
    db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30
    db 0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x00
    db 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00
    db 0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x00
    db 0x3C,0x66,0x06,0x0C,0x18,0x00,0x18,0x00
    db 0x3C,0x66,0x6E,0x6E,0x60,0x62,0x3C,0x00
    db 0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00
    db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00
    db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00
    db 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00
    db 0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00
    db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00
    db 0x7E,0x18,0x18,0x18,0x18,0x18,0x7E,0x00
    db 0x3E,0x0C,0x0C,0x0C,0x0C,0x6C,0x38,0x00
    db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00
    db 0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00
    db 0xC6,0xEE,0xFE,0xD6,0xC6,0xC6,0xC6,0x00
    db 0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00
    db 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00
    db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00
    db 0x3C,0x66,0x66,0x66,0x6E,0x6C,0x36,0x00
    db 0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00
    db 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00
    db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00
    db 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00
    db 0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00
    db 0x66,0x66,0x66,0x7E,0x7E,0x7E,0x24,0x00
    db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00
    db 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00
    db 0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00
    db 0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00
    db 0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00
    db 0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00
    db 0x18,0x3C,0x66,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF
    db 0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x3C,0x06,0x3E,0x66,0x3E,0x00
    db 0x60,0x60,0x7C,0x66,0x66,0x66,0x7C,0x00
    db 0x00,0x00,0x3C,0x66,0x60,0x66,0x3C,0x00
    db 0x06,0x06,0x3E,0x66,0x66,0x66,0x3E,0x00
    db 0x00,0x00,0x3C,0x66,0x7E,0x60,0x3C,0x00
    db 0x1C,0x30,0x7C,0x30,0x30,0x30,0x30,0x00
    db 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x3C
    db 0x60,0x60,0x7C,0x66,0x66,0x66,0x66,0x00
    db 0x18,0x00,0x38,0x18,0x18,0x18,0x7E,0x00
    db 0x06,0x00,0x06,0x06,0x06,0x66,0x66,0x3C
    db 0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0x00
    db 0x38,0x18,0x18,0x18,0x18,0x18,0x7E,0x00
    db 0x00,0x00,0xEC,0xFE,0xD6,0xC6,0xC6,0x00
    db 0x00,0x00,0x7C,0x66,0x66,0x66,0x66,0x00
    db 0x00,0x00,0x3C,0x66,0x66,0x66,0x3C,0x00
    db 0x00,0x00,0x7C,0x66,0x66,0x7C,0x60,0x60
    db 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x06
    db 0x00,0x00,0x6C,0x76,0x60,0x60,0x60,0x00
    db 0x00,0x00,0x3E,0x60,0x3C,0x06,0x7C,0x00
    db 0x30,0x30,0x7C,0x30,0x30,0x30,0x1C,0x00
    db 0x00,0x00,0x66,0x66,0x66,0x66,0x3E,0x00
    db 0x00,0x00,0x66,0x66,0x66,0x3C,0x18,0x00
    db 0x00,0x00,0xC6,0xC6,0xD6,0xFE,0x6C,0x00
    db 0x00,0x00,0x66,0x3C,0x18,0x3C,0x66,0x00
    db 0x00,0x00,0x66,0x66,0x66,0x3E,0x06,0x3C
    db 0x00,0x00,0x7E,0x0C,0x18,0x30,0x7E,0x00
    db 0x0C,0x18,0x18,0x70,0x18,0x18,0x0C,0x00
    db 0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x00
    db 0x30,0x18,0x18,0x0E,0x18,0x18,0x30,0x00
    db 0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00
    times 328 db 0
    db 0x24,0x7E,0x60,0x7C,0x60,0x60,0x7E,0x00
    times 120 db 0
    db 0x00,0x24,0x3C,0x66,0x7E,0x60,0x3C,0x00
    times 56 db 0
    db 0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00
    db 0x7E,0x60,0x60,0x7C,0x66,0x66,0x7C,0x00
    db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00
    db 0x7E,0x60,0x60,0x60,0x60,0x60,0x60,0x00
    db 0x1E,0x36,0x66,0x66,0x66,0x66,0xFF,0xC3
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00
    db 0xDB,0xDB,0x7E,0x18,0x7E,0xDB,0xDB,0x00
    db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00
    db 0x66,0x66,0x6E,0x7E,0x76,0x66,0x66,0x00
    db 0x3C,0x66,0x6E,0x7E,0x76,0x66,0x66,0x00
    db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00
    db 0x1E,0x36,0x66,0x66,0x66,0x66,0x66,0x00
    db 0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00
    db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00
    db 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00
    db 0x7E,0x66,0x66,0x66,0x66,0x66,0x66,0x00
    db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00
    db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00
    db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00
    db 0x66,0x66,0x66,0x3E,0x06,0x0C,0x78,0x00
    db 0x18,0x7E,0xDB,0xDB,0xDB,0x7E,0x18,0x00
    db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00
    db 0x66,0x66,0x66,0x66,0x66,0x7F,0x03,0x03
    db 0x66,0x66,0x66,0x3E,0x06,0x06,0x06,0x00
    db 0xDB,0xDB,0xDB,0xDB,0xDB,0xDB,0xFF,0x00
    db 0xDB,0xDB,0xDB,0xDB,0xDB,0xFF,0x03,0x03
    db 0xE0,0x60,0x60,0x7C,0x66,0x66,0x7C,0x00
    db 0xC3,0xC3,0xC3,0xDB,0xDB,0xC3,0xC3,0x00
    db 0x60,0x60,0x60,0x7C,0x66,0x66,0x7C,0x00
    db 0x3C,0x66,0x06,0x1E,0x06,0x66,0x3C,0x00
    db 0xC3,0xC3,0xDB,0xFF,0xFF,0xC3,0xC3,0x00
    db 0x3E,0x66,0x66,0x3E,0x36,0x66,0x66,0x00
    db 0x00,0x00,0x3C,0x06,0x3E,0x66,0x3E,0x00
    db 0x1E,0x30,0x3C,0x66,0x66,0x66,0x3C,0x00
    db 0x00,0x00,0x7C,0x66,0x7C,0x66,0x7C,0x00
    db 0x00,0x00,0x7E,0x60,0x60,0x60,0x60,0x00
    db 0x00,0x1E,0x36,0x66,0x66,0x66,0xFF,0xC3
    db 0x00,0x00,0x3C,0x66,0x7E,0x60,0x3C,0x00
    db 0x00,0x00,0x6C,0xFE,0x18,0xFE,0x6C,0x00
    db 0x00,0x00,0x3C,0x66,0x0C,0x66,0x3C,0x00
    db 0x00,0x00,0x66,0x6E,0x7E,0x76,0x66,0x00
    db 0x18,0x66,0x6E,0x7E,0x76,0x66,0x66,0x00
    db 0x00,0x00,0x66,0x6C,0x78,0x6C,0x66,0x00
    db 0x00,0x00,0x1E,0x36,0x66,0x66,0x66,0x00
    db 0x00,0x00,0x63,0x77,0x7F,0x6B,0x63,0x00
    db 0x00,0x00,0x66,0x66,0x7E,0x66,0x66,0x00
    db 0x00,0x00,0x3C,0x66,0x66,0x66,0x3C,0x00
    db 0x00,0x00,0x7E,0x66,0x66,0x66,0x66,0x00
    db 0x00,0x00,0x7C,0x66,0x66,0x7C,0x60,0x60
    db 0x00,0x00,0x3C,0x66,0x60,0x66,0x3C,0x00
    db 0x00,0x00,0x7E,0x18,0x18,0x18,0x18,0x00
    db 0x00,0x00,0x66,0x66,0x3E,0x06,0x7C,0x00
    db 0x00,0x00,0x18,0x7E,0xDB,0x7E,0x18,0x00
    db 0x00,0x00,0x66,0x3C,0x18,0x3C,0x66,0x00
    db 0x00,0x00,0x66,0x66,0x66,0x7F,0x03,0x00
    db 0x00,0x00,0x66,0x66,0x3E,0x06,0x06,0x00
    db 0x00,0x00,0xDB,0xDB,0xDB,0xDB,0xFF,0x00
    db 0x00,0x00,0xDB,0xDB,0xDB,0xFF,0x03,0x00
    db 0x00,0x00,0x60,0x60,0x7C,0x66,0x7C,0x00
    db 0x00,0xC3,0xC3,0xDB,0xDB,0xC3,0xC3,0x00
    db 0x00,0x00,0x60,0x60,0x7C,0x66,0x7C,0x00
    db 0x00,0x00,0x3C,0x66,0x1E,0x66,0x3C,0x00
    db 0x00,0x00,0xC3,0xDB,0xFF,0xFF,0xC3,0x00
    db 0x00,0x00,0x3E,0x66,0x3E,0x36,0x66,0x00
