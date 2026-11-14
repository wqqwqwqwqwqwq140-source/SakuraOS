section .text

%define C_BODY 0x00D8D8D8

%macro GLD 2
 %ifnum %2
    mov %1, %2
 %else
    lea %1, [%2]
 %endif
%endmacro

%macro GRECT 5
    GLD r8,  %1
    GLD r9,  %2
    GLD r10, %3
    GLD r11, %4
    mov eax, %5
    call gfx_rect
%endmacro

%macro GTEXT 4
    GLD r8, %1
    GLD r9, %2
    mov eax, %3
    lea rdi, [%4]
    call draw_text
%endmacro

%macro GNUM 4
    mov rdi, %4
    call u2s
    mov rdi, rax
    GLD r8, %1
    GLD r9, %2
    mov eax, %3
    call draw_text
%endmacro

gfx_rect:
    push rbx
    push rcx
    push rdx
    push rdi
    push r8
    push r9
    push r10
    push r11
    test r8, r8
    jns .x0
    add r10, r8
    xor r8d, r8d
.x0:
    test r9, r9
    jns .y0
    add r11, r9
    xor r9d, r9d
.y0:
    test r10, r10
    jle .out
    test r11, r11
    jle .out
    mov rdx, [width]
    cmp r8, rdx
    jge .out
    lea rbx, [r8 + r10]
    cmp rbx, rdx
    jle .xok
    mov r10, rdx
    sub r10, r8
.xok:
    mov rdx, [height]
    cmp r9, rdx
    jge .out
    lea rbx, [r9 + r11]
    cmp rbx, rdx
    jle .yok
    mov r11, rdx
    sub r11, r9
.yok:
    mov rbx, [render_pitch]
    mov rdi, rbx
    imul rdi, r9
    lea rdi, [rdi + r8*4]
    add rdi, [render_fb]
    cld
.row:
    push rdi
    mov rcx, r10
    rep stosd
    pop rdi
    add rdi, rbx
    dec r11
    jnz .row
.out:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

u2s:
    push rcx
    push rdx
    push rbx
    mov rax, rdi
    lea rbx, [num_buf + 28]
    mov byte [rbx], 0
    mov ecx, 10
.l:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .l
    mov rax, rbx
    pop rbx
    pop rdx
    pop rcx
    ret

i2s:
    push rbx
    xor ebx, ebx
    test rdi, rdi
    jns .p
    neg rdi
    mov ebx, 1
.p:
    call u2s
    test ebx, ebx
    jz .r
    dec rax
    mov byte [rax], '-'
.r:
    pop rbx
    ret

store2:
    mov eax, edi
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    add dl, '0'
    mov [rsi], al
    mov [rsi + 1], dl
    ret

make_clock:
    call rtc_wait
    mov edi, 4
    call cmos_get
    mov edi, eax
    lea rsi, [clock_buf]
    call store2
    mov edi, 2
    call cmos_get
    mov edi, eax
    lea rsi, [clock_buf + 3]
    call store2
    xor edi, edi
    call cmos_get
    mov edi, eax
    lea rsi, [clock_buf + 6]
    call store2
    ret

gui_text2:
    push qword [font_scale]
    push qword [font_adv]
    mov qword [font_scale], 2
    mov qword [font_adv], 16
    call draw_text
    pop qword [font_adv]
    pop qword [font_scale]
    ret

gui_text4:
    push qword [font_scale]
    push qword [font_adv]
    mov qword [font_scale], 4
    mov qword [font_adv], 32
    call draw_text
    pop qword [font_adv]
    pop qword [font_scale]
    ret

kbc_wait_in:
    push rcx
    mov ecx, 100000
.w:
    in al, 0x64
    test al, 2
    jz .d
    dec ecx
    jnz .w
.d:
    pop rcx
    ret

kbc_wait_out:
    push rcx
    mov ecx, 100000
.w:
    in al, 0x64
    test al, 1
    jnz .d
    dec ecx
    jnz .w
.d:
    pop rcx
    ret

mouse_write:
    push rax
    call kbc_wait_in
    mov al, 0xD4
    out 0x64, al
    call kbc_wait_in
    pop rax
    out 0x60, al
    ret

mouse_init:
    push rbx
    call kbc_wait_in
    mov al, 0xA8
    out 0x64, al
    call kbc_wait_in
    mov al, 0x20
    out 0x64, al
    call kbc_wait_out
    in al, 0x60
    or al, 2
    and al, 0xDF
    mov bl, al
    call kbc_wait_in
    mov al, 0x60
    out 0x64, al
    call kbc_wait_in
    mov al, bl
    out 0x60, al
    mov al, 0xF6
    call mouse_write
    call kbc_wait_out
    in al, 0x60
    mov al, 0xF4
    call mouse_write
    call kbc_wait_out
    in al, 0x60
    mov qword [mouse_cyc], 0
    in al, 0x21
    and al, 0xFB
    out 0x21, al
    in al, 0xA1
    and al, 0xEF
    out 0xA1, al
    pop rbx
    ret

irq_mouse:
    push rax
    push rbx
    push rcx
    push rdx
    in al, 0x60
    mov rbx, [mouse_cyc]
    test rbx, rbx
    jnz .store
    test al, 8
    jz .eoi
.store:
    mov [mouse_pkt + rbx], al
    inc rbx
    cmp rbx, 3
    jb .save
    xor ebx, ebx
    mov [mouse_cyc], rbx
    movzx eax, byte [mouse_pkt]
    movzx ecx, byte [mouse_pkt + 1]
    movzx edx, byte [mouse_pkt + 2]
    test al, 0x10
    jz .xp
    or ecx, 0xFFFFFF00
.xp:
    test al, 0x20
    jz .yp
    or edx, 0xFFFFFF00
.yp:
    movsxd rcx, ecx
    movsxd rdx, edx
    and eax, 7
    mov [mouse_btn], rax
    add [mouse_x], rcx
    sub [mouse_y], rdx
    cmp qword [mouse_x], 0
    jge .x1
    mov qword [mouse_x], 0
.x1:
    mov rax, [width]
    dec rax
    cmp [mouse_x], rax
    jle .y0
    mov [mouse_x], rax
.y0:
    cmp qword [mouse_y], 0
    jge .y1
    mov qword [mouse_y], 0
.y1:
    mov rax, [height]
    dec rax
    cmp [mouse_y], rax
    jle .evt
    mov [mouse_y], rax
.evt:
    mov qword [gui_dirty], 1
    jmp .eoi
.save:
    mov [mouse_cyc], rbx
.eoi:
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

gui_run:
    push rbx
    push r12
    push qword [font_scale]
    push qword [font_adv]
    mov qword [font_scale], 1
    mov qword [font_adv], 8
    cli
    call mouse_init
    sti
    cmp qword [canvas_ptr], 0
    jne .have
    mov rdi, 256*160
    call kmalloc
    test rax, rax
    jz .exit
    mov [canvas_ptr], rax
    call canvas_clear
.have:
    mov rax, [width]
    shr rax, 1
    mov [mouse_x], rax
    mov rax, [height]
    shr rax, 1
    mov [mouse_y], rax
    mov qword [mouse_btn], 0
    mov qword [prev_btn], 0
    mov qword [drag_win], -1
    mov qword [paint_mode], 0
    mov qword [paint_lx], -100000
    mov qword [status_ptr], 0
    mov qword [gui_run_flag], 1
    mov qword [gui_last_sec], -1
    mov qword [gui_dirty], 1
.loop:
    cmp qword [gui_run_flag], 0
    je .exit
    call kbd_poll_char
    test al, al
    jz .nokey
    cmp al, 27
    je .exit
    movzx edi, al
    mov qword [status_ptr], 0
    call gui_key
    mov qword [gui_dirty], 1
.nokey:
    call gui_mouse
    mov rax, [ticks]
    xor edx, edx
    mov ecx, 1000
    div rcx
    cmp rax, [gui_last_sec]
    je .chk
    mov [gui_last_sec], rax
    mov qword [gui_dirty], 1
.chk:
    cmp qword [gui_dirty], 0
    je .idle
    mov qword [gui_dirty], 0
    call gui_draw
    jmp .loop
.idle:
    hlt
    jmp .loop
.exit:
    pop qword [font_adv]
    pop qword [font_scale]
    cmp qword [fs_dirty], 0
    je .nosave
    call fs_save
.nosave:
    mov qword [con_dirty], 1
    pop r12
    pop rbx
    ret

canvas_clear:
    mov rdi, [canvas_ptr]
    test rdi, rdi
    jz .r
    mov ecx, 256*160
    mov al, 1
    cld
    rep stosb
.r:
    ret

gui_key:
    cmp edi, 'w'
    jne .k1
    mov rax, [wall_theme]
    inc rax
    and rax, 3
    mov [wall_theme], rax
    ret
.k1:
    mov rax, [top_win]
    cmp rax, 2
    jne .k2
    lea rdx, [win_vis]
    cmp qword [rdx + 16], 0
    je .k2
    cmp edi, 'c'
    jne .kc
    mov edi, 'C'
.kc:
    jmp calc_press
.k2:
    cmp rax, 1
    jne .kdone
    lea rdx, [win_vis]
    cmp qword [rdx + 8], 0
    je .kdone
    cmp edi, 'c'
    je canvas_clear
    cmp edi, 's'
    je paint_save
    cmp edi, 'l'
    je paint_load
    cmp edi, '='
    jne .km
    cmp qword [brush_r], 4
    jae .kdone
    inc qword [brush_r]
    ret
.km:
    cmp edi, '-'
    jne .kdone
    cmp qword [brush_r], 0
    je .kdone
    dec qword [brush_r]
.kdone:
    ret

paint_save:
    lea rdi, [s_pfile]
    mov esi, 9
    call fs_lookup
    cmp rax, -1
    jne .have
    lea rdi, [s_pfile]
    mov esi, 9
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .fail
.have:
    mov rdi, rax
    mov rsi, [canvas_ptr]
    mov edx, 256*160
    call fs_write
    cmp rax, -1
    je .fail
    lea rax, [s_saved]
    jmp .set
.fail:
    lea rax, [s_failed]
.set:
    mov [status_ptr], rax
    ret

paint_load:
    lea rdi, [s_pfile]
    mov esi, 9
    call fs_lookup
    cmp rax, -1
    je .fail
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .fail
    cmp qword [rax + INO_SIZE], 256*160
    jb .fail
    mov rdi, rax
    xor esi, esi
    mov rdx, [canvas_ptr]
    mov ecx, 256*160
    call fs_read_at
    lea rax, [s_loaded]
    jmp .set
.fail:
    lea rax, [s_failed]
.set:
    mov [status_ptr], rax
    ret

calc_press:
    push rbx
    movzx eax, dil
    cmp eax, 10
    jne .n1
    mov eax, '='
.n1:
    cmp eax, 8
    je .back
    cmp eax, 'C'
    je .clear
    cmp eax, '0'
    jb .isop
    cmp eax, '9'
    ja .isop
    sub eax, '0'
    cmp qword [calc_new], 0
    je .dig
    mov qword [calc_cur], 0
    mov qword [calc_new], 0
.dig:
    mov rcx, [calc_cur]
    cmp rcx, 99999999
    ja .out
    imul rcx, rcx, 10
    add rcx, rax
    mov [calc_cur], rcx
    jmp .out
.back:
    cmp qword [calc_new], 0
    jne .out
    mov rax, [calc_cur]
    xor edx, edx
    mov ecx, 10
    div rcx
    mov [calc_cur], rax
    jmp .out
.clear:
    xor eax, eax
    mov [calc_acc], rax
    mov [calc_cur], rax
    mov [calc_op], rax
    mov qword [calc_new], 1
    jmp .out
.isop:
    cmp eax, '+'
    je .doop
    cmp eax, '-'
    je .doop
    cmp eax, '*'
    je .doop
    cmp eax, '/'
    je .doop
    cmp eax, '='
    jne .out
.doop:
    mov rbx, rax
    cmp qword [calc_new], 0
    jne .chk
.ev:
    call calc_eval
    jmp .after
.chk:
    cmp qword [calc_op], 0
    je .ev
.after:
    mov rax, [calc_acc]
    mov [calc_cur], rax
    mov qword [calc_new], 1
    cmp bl, '='
    jne .setop
    xor ebx, ebx
.setop:
    mov [calc_op], rbx
.out:
    pop rbx
    ret

calc_eval:
    mov rax, [calc_acc]
    mov rcx, [calc_cur]
    mov rdx, [calc_op]
    test rdx, rdx
    jnz .some
    mov rax, rcx
    jmp .st
.some:
    cmp dl, '+'
    je .add
    cmp dl, '-'
    je .sub
    cmp dl, '*'
    je .mul
    cmp dl, '/'
    je .div
    jmp .st
.add:
    add rax, rcx
    jmp .st
.sub:
    sub rax, rcx
    jmp .st
.mul:
    imul rax, rcx
    jmp .st
.div:
    test rcx, rcx
    jz .err
    cqo
    idiv rcx
    jmp .st
.err:
    xor eax, eax
.st:
    mov [calc_acc], rax
    ret

raise_win:
    push rcx
    push rdx
    lea rdx, [z_order]
    xor ecx, ecx
.find:
    cmp [rdx + rcx*8], rbx
    je .shift
    inc ecx
    cmp ecx, 4
    jb .find
    jmp .r
.shift:
    lea rax, [rcx + 1]
.sh:
    cmp rax, 4
    jae .put
    mov r8, [rdx + rax*8]
    mov [rdx + rcx*8], r8
    inc rcx
    inc rax
    jmp .sh
.put:
    mov [rdx + rcx*8], rbx
    mov [top_win], rbx
.r:
    pop rdx
    pop rcx
    ret

gui_mouse:
    push rbx
    mov rax, [mouse_btn]
    mov rbx, [prev_btn]
    mov [prev_btn], rax
    test rax, rax
    jz .release
    mov rdx, rbx
    not rdx
    and rdx, rax
    jz .held
    call gui_click
    jmp .out
.held:
    cmp qword [drag_win], 0
    jl .try_paint
    call drag_move
    jmp .out
.try_paint:
    cmp qword [paint_mode], 0
    je .out
    call paint_at
    mov qword [gui_dirty], 1
    jmp .out
.release:
    mov qword [drag_win], -1
    mov qword [paint_mode], 0
    mov qword [paint_lx], -100000
.out:
    pop rbx
    ret

gui_click:
    push rbx
    push r12
    push r13
    mov r12, [mouse_x]
    mov r13, [mouse_y]
    mov qword [drag_win], -1
    mov qword [paint_mode], 0
    mov qword [paint_lx], -100000
    mov rax, [height]
    sub rax, 28
    cmp r13, rax
    jl .wins
    test byte [mouse_btn], 1
    jz .out
    mov rax, r12
    sub rax, 8
    js .changed
    xor edx, edx
    mov ecx, 80
    div rcx
    cmp rdx, 72
    jae .changed
    cmp rax, 4
    jb .toggle
    je .bx
    jmp .changed
.toggle:
    mov rbx, rax
    lea rax, [win_vis]
    xor qword [rax + rbx*8], 1
    cmp qword [rax + rbx*8], 0
    je .changed
    call raise_win
    jmp .changed
.bx:
    mov qword [gui_run_flag], 0
    jmp .changed
.wins:
    mov qword [gui_zi], 3
.wl:
    mov rax, [gui_zi]
    lea rdx, [z_order]
    mov rbx, [rdx + rax*8]
    call hit_window
    test rax, rax
    jnz .changed
    dec qword [gui_zi]
    jns .wl
.changed:
    mov qword [gui_dirty], 1
.out:
    pop r13
    pop r12
    pop rbx
    ret

hit_window:
    push rcx
    push rdx
    lea rax, [win_vis]
    cmp qword [rax + rbx*8], 0
    je .no
    lea rax, [win_x]
    mov rcx, [rax + rbx*8]
    lea rax, [win_y]
    mov rdx, [rax + rbx*8]
    cmp r12, rcx
    jl .no
    cmp r13, rdx
    jl .no
    lea rax, [win_w]
    mov r8, [rax + rbx*8]
    add r8, rcx
    cmp r12, r8
    jge .no
    lea rax, [win_h]
    mov r9, [rax + rbx*8]
    add r9, rdx
    cmp r13, r9
    jge .no
    call raise_win
    mov r10, r12
    sub r10, rcx
    mov r11, r13
    sub r11, rdx
    cmp r11, 20
    jge .body
    test byte [mouse_btn], 1
    jz .yes
    lea rax, [win_w]
    mov rax, [rax + rbx*8]
    sub rax, 18
    cmp r10, rax
    jl .drag
    lea rax, [win_vis]
    mov qword [rax + rbx*8], 0
    jmp .yes
.drag:
    mov [drag_win], rbx
    mov [drag_dx], r10
    mov [drag_dy], r11
    jmp .yes
.body:
    cmp rbx, 1
    je .paintb
    cmp rbx, 2
    je .calcb
    jmp .yes
.paintb:
    cmp r11, 42
    jge .canvas
    cmp r11, 24
    jl .yes
    lea rax, [r10 - 6]
    test rax, rax
    js .yes
    shr rax, 5
    cmp rax, 8
    jge .yes
    mov [paint_col], rax
    jmp .yes
.canvas:
    cmp r11, 50
    jl .yes
    cmp r11, 210
    jge .yes
    cmp r10, 16
    jl .yes
    cmp r10, 272
    jge .yes
    mov qword [paint_mode], 1
    call paint_at
    jmp .yes
.calcb:
    mov rax, r11
    sub rax, 66
    js .yes
    xor edx, edx
    mov ecx, 36
    div rcx
    cmp rax, 4
    jae .yes
    cmp rdx, 32
    jae .yes
    mov r8, rax
    mov rax, r10
    sub rax, 10
    js .yes
    xor edx, edx
    mov ecx, 44
    div rcx
    cmp rax, 4
    jae .yes
    cmp rdx, 40
    jae .yes
    shl r8, 2
    add r8, rax
    lea rax, [calc_keys]
    movzx edi, byte [rax + r8]
    call calc_press
.yes:
    mov rax, 1
    jmp .ret
.no:
    xor eax, eax
.ret:
    pop rdx
    pop rcx
    ret

drag_move:
    push rbx
    mov rbx, [drag_win]
    mov rax, [mouse_x]
    sub rax, [drag_dx]
    test rax, rax
    jns .x1
    xor eax, eax
.x1:
    lea rcx, [win_w]
    mov rdx, [width]
    sub rdx, [rcx + rbx*8]
    cmp rax, rdx
    jle .x2
    mov rax, rdx
.x2:
    lea rcx, [win_x]
    mov [rcx + rbx*8], rax
    mov rax, [mouse_y]
    sub rax, [drag_dy]
    test rax, rax
    jns .y1
    xor eax, eax
.y1:
    lea rcx, [win_h]
    mov rdx, [height]
    sub rdx, 28
    sub rdx, [rcx + rbx*8]
    cmp rax, rdx
    jle .y2
    mov rax, rdx
.y2:
    lea rcx, [win_y]
    mov [rcx + rbx*8], rax
    mov qword [gui_dirty], 1
    pop rbx
    ret

paint_dab:
    mov rdx, [canvas_ptr]
    test rdx, rdx
    jz .r
    mov r10, [brush_r]
    mov r8, r10
    neg r8
.dy:
    mov r9, r10
    neg r9
.dx:
    lea r11, [rdi + r9]
    lea rax, [rsi + r8]
    cmp r11, 256
    jae .skip
    cmp rax, 160
    jae .skip
    shl rax, 8
    add rax, r11
    mov r11b, [pt_c]
    mov [rdx + rax], r11b
.skip:
    inc r9
    cmp r9, r10
    jle .dx
    inc r8
    cmp r8, r10
    jle .dy
.r:
    ret

paint_line:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    mov r12, [paint_lx]
    mov r13, [paint_ly]
    mov r14, [pt_x]
    sub r14, r12
    mov r15, [pt_y]
    sub r15, r13
    mov rax, r14
    test rax, rax
    jns .a
    neg rax
.a:
    mov rbx, r15
    test rbx, rbx
    jns .b
    neg rbx
.b:
    cmp rbx, rax
    jae .n_ok
    mov rbx, rax
.n_ok:
    xor ecx, ecx
.step:
    mov rax, r14
    imul rax, rcx
    test rbx, rbx
    jz .z1
    cqo
    idiv rbx
    jmp .px
.z1:
    xor eax, eax
.px:
    lea rdi, [rax + r12]
    mov rax, r15
    imul rax, rcx
    test rbx, rbx
    jz .z2
    cqo
    idiv rbx
    jmp .py
.z2:
    xor eax, eax
.py:
    lea rsi, [rax + r13]
    call paint_dab
    inc rcx
    cmp rcx, rbx
    jbe .step
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

paint_at:
    push rbx
    push rcx
    lea rax, [win_x]
    mov rax, [rax + 8]
    mov rbx, [mouse_x]
    sub rbx, rax
    sub rbx, 16
    lea rax, [win_y]
    mov rax, [rax + 8]
    mov rcx, [mouse_y]
    sub rcx, rax
    sub rcx, 50
    movzx eax, byte [paint_col]
    test byte [mouse_btn], 2
    jz .c
    mov eax, 1
.c:
    mov [pt_c], rax
    mov [pt_x], rbx
    mov [pt_y], rcx
    cmp qword [paint_lx], -100000
    jg .go
    mov [paint_lx], rbx
    mov [paint_ly], rcx
.go:
    call paint_line
    mov [paint_lx], rbx
    mov [paint_ly], rcx
    pop rcx
    pop rbx
    ret

gui_draw:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, [ticks]
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov [tmp_val], rax
    call make_clock
    call draw_desktop
    mov qword [gui_zi], 0
.zl:
    mov rax, [gui_zi]
    lea rdx, [z_order]
    mov rbx, [rdx + rax*8]
    call draw_window
    inc qword [gui_zi]
    cmp qword [gui_zi], 4
    jb .zl
    call draw_taskbar
    call draw_cursor
    call swap_buffers
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

draw_desktop:
    push rbx
    push rsi
    mov rax, [wall_theme]
    imul rax, rax, 24
    lea rsi, [wall_tab]
    add rsi, rax
    xor ebx, ebx
.band:
    cmp ebx, 32
    jae .done
    mov rax, [height]
    imul rax, rbx
    shr rax, 5
    mov r9, rax
    lea rcx, [rbx + 1]
    mov rax, [height]
    imul rax, rcx
    shr rax, 5
    sub rax, r9
    mov r11, rax
    mov eax, [rsi + 4]
    imul eax, ebx
    add eax, [rsi]
    shl eax, 16
    mov edx, [rsi + 12]
    imul edx, ebx
    add edx, [rsi + 8]
    shl edx, 8
    or eax, edx
    mov edx, [rsi + 20]
    imul edx, ebx
    add edx, [rsi + 16]
    or eax, edx
    xor r8d, r8d
    mov r10, [width]
    call gfx_rect
    inc ebx
    jmp .band
.done:
    mov r8, [width]
    sub r8, 270
    mov r9d, 14
    xor eax, eax
    lea rdi, [clock_buf]
    call gui_text4
    mov r8, [width]
    sub r8, 272
    mov r9d, 12
    mov eax, C_WHITE
    lea rdi, [clock_buf]
    call gui_text4
    mov r8d, 16
    mov r9d, 12
    mov eax, C_WHITE
    lea rdi, [s_title]
    call gui_text2
    mov r8d, 16
    mov r9d, 36
    mov eax, C_WHITE
    lea rdi, [s_sub]
    call draw_text
    pop rsi
    pop rbx
    ret

draw_window:
    lea rax, [win_vis]
    cmp qword [rax + rbx*8], 0
    je .ret
    lea rax, [win_x]
    mov r12, [rax + rbx*8]
    lea rax, [win_y]
    mov r13, [rax + rbx*8]
    lea rax, [win_w]
    mov r14, [rax + rbx*8]
    lea rax, [win_h]
    mov r15, [rax + rbx*8]
    GRECT r12+4, r13+4, r14, r15, 0x00101010
    GRECT r12-1, r13-1, r14+2, r15+2, C_DGRAY
    GRECT r12, r13, r14, r15, C_BODY
    mov edx, 0x00606070
    cmp rbx, [top_win]
    jne .tc
    mov edx, 0x002050C0
.tc:
    GRECT r12, r13, r14, 20, edx
    GRECT r12+r14-18, r13+2, 16, 16, 0x00C03030
    lea rax, [win_title]
    mov rdi, [rax + rbx*8]
    lea r8, [r12 + 8]
    lea r9, [r13 + 6]
    mov eax, C_WHITE
    call draw_text
    GTEXT r12+r14-14, r13+6, C_WHITE, s_x
    cmp rbx, 0
    je .info
    cmp rbx, 1
    je .paint
    cmp rbx, 2
    je .calc
    call draw_files_content
    ret
.info:
    call draw_info_content
    ret
.paint:
    call draw_paint_content
    ret
.calc:
    call draw_calc_content
.ret:
    ret

draw_info_content:
    GTEXT r12+8, r13+28, C_BLACK, s_l0
    GTEXT r12+8, r13+44, C_BLACK, s_l1
    GNUM r12+104, r13+44, C_BLUE, [tmp_val]
    GTEXT r12+8, r13+60, C_BLACK, s_l2
    GNUM r12+104, r13+60, C_BLUE, [mouse_x]
    GTEXT r12+8, r13+76, C_BLACK, s_l3
    GNUM r12+104, r13+76, C_BLUE, [mouse_y]
    GTEXT r12+8, r13+92, C_BLACK, s_l4
    GNUM r12+104, r13+92, C_BLUE, [width]
    GTEXT r12+144, r13+92, C_BLACK, s_by
    GNUM r12+160, r13+92, C_BLUE, [height]
    GTEXT r12+8, r13+108, C_BLACK, s_l6
    GNUM r12+104, r13+108, C_BLUE, [fs_super + SB_USED]
    GTEXT r12+8, r13+124, C_BLACK, s_l7
    mov rax, HEAP_END
    sub rax, [heap_cur]
    shr rax, 10
    mov [tmp_val2], rax
    GNUM r12+112, r13+124, C_BLUE, [tmp_val2]
    GTEXT r12+8, r13+144, C_DGRAY, s_l5
    ret

draw_paint_content:
    xor ecx, ecx
.pal:
    cmp ecx, 8
    jae .pal_done
    mov rdx, rcx
    shl rdx, 5
    lea r8, [r12 + rdx + 6]
    lea r9, [r13 + 24]
    mov r10, 28
    mov r11, 18
    mov eax, C_BODY
    cmp rcx, [paint_col]
    jne .bg
    mov eax, C_BLACK
.bg:
    call gfx_rect
    lea r8, [r12 + rdx + 8]
    lea r9, [r13 + 26]
    mov r10, 24
    mov r11, 14
    lea rax, [palette]
    mov eax, [rax + rcx*4]
    call gfx_rect
    inc ecx
    jmp .pal
.pal_done:
    GRECT r12+15, r13+49, 258, 162, C_BLACK
    call blit_canvas
    GTEXT r12+8, r13+214, C_DGRAY, s_hint
    GTEXT r12+8, r13+228, C_DGRAY, s_hint2
    GTEXT r12+240, r13+214, C_DGRAY, s_b
    GNUM r12+260, r13+214, C_BLUE, [brush_r]
    ret

blit_canvas:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rsi, [canvas_ptr]
    test rsi, rsi
    jz .out
    lea rdi, [r13 + 50]
    imul rdi, [render_pitch]
    lea rax, [r12 + 16]
    lea rdi, [rdi + rax*4]
    add rdi, [render_fb]
    lea r9, [palette]
    mov edx, 160
.row:
    push rdi
    mov ecx, 256
.px:
    movzx eax, byte [rsi]
    and eax, 7
    mov eax, [r9 + rax*4]
    mov [rdi], eax
    inc rsi
    add rdi, 4
    dec ecx
    jnz .px
    pop rdi
    add rdi, [render_pitch]
    dec edx
    jnz .row
.out:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

draw_calc_content:
    push rbx
    GRECT r12+8, r13+26, 176, 32, 0x00203020
    mov rdi, [calc_cur]
    call i2s
    mov rbx, rax
    mov rdi, rbx
    call strlen
    shl rax, 4
    lea r8, [r12 + 180]
    sub r8, rax
    lea r9, [r13 + 34]
    mov eax, 0x0050FF50
    mov rdi, rbx
    call gui_text2
    xor ecx, ecx
.b:
    cmp ecx, 16
    jae .done
    mov edx, ecx
    and edx, 3
    mov eax, 0x00C8C8D8
    cmp edx, 3
    jne .col
    mov eax, 0x00F0A850
.col:
    imul edx, edx, 44
    lea r8, [r12 + rdx + 10]
    mov edx, ecx
    shr edx, 2
    imul edx, edx, 36
    lea r9, [r13 + rdx + 66]
    mov r10, 40
    mov r11, 32
    call gfx_rect
    lea rdx, [calc_keys]
    movzx eax, byte [rdx + rcx]
    mov [btn_lbl], al
    add r8, 16
    add r9, 12
    mov eax, C_BLACK
    lea rdi, [btn_lbl]
    call draw_text
    inc ecx
    jmp .b
.done:
    pop rbx
    ret

draw_files_content:
    push rbx
    GTEXT r12+8, r13+26, C_DGRAY, s_fn
    GTEXT r12+200, r13+26, C_DGRAY, s_fs
    GRECT r12+8, r13+38, 244, 1, C_DGRAY
    xor ecx, ecx
    xor edx, edx
.f:
    cmp ecx, FS_MAX_FILES
    jae .end
    cmp edx, 10
    jae .end
    imul rax, rcx, FS_INODE_SIZE
    lea rbx, [fs_inodes]
    add rbx, rax
    cmp qword [rbx + INO_USED], 0
    je .nx
    mov rax, [rbx + INO_RESERVED]
    cmp rax, [fs_cwd]
    jne .nx
    imul esi, edx, 12
    add esi, 44
    lea r8, [r12 + 8]
    lea r9, [r13 + rsi]
    lea rdi, [rbx + FS_INODE_HDR]
    mov eax, C_BLACK
    call draw_text
    mov rdi, [rbx + INO_SIZE]
    call u2s
    mov rdi, rax
    lea r8, [r12 + 200]
    lea r9, [r13 + rsi]
    mov eax, C_BLUE
    call draw_text
    inc edx
.nx:
    inc ecx
    jmp .f
.end:
    GTEXT r12+8, r13+166, C_DGRAY, s_l6
    GNUM r12+64, r13+166, C_BLUE, [fs_super + SB_USED]
    pop rbx
    ret

draw_taskbar:
    push rbx
    mov r14, [height]
    sub r14, 28
    mov r15, [width]
    GRECT 0, r14, r15, 28, 0x00303038
    GRECT 0, r14, r15, 1, 0x00707080
    xor ebx, ebx
.t:
    cmp ebx, 5
    jae .t_done
    mov edx, 0x00903030
    cmp ebx, 4
    je .tc
    mov edx, 0x00404048
    lea rax, [win_vis]
    cmp qword [rax + rbx*8], 0
    je .tc
    mov edx, 0x00506090
    cmp rbx, [top_win]
    jne .tc
    mov edx, 0x006888D0
.tc:
    imul eax, ebx, 80
    lea r8, [rax + 8]
    lea r9, [r14 + 4]
    mov r10, 72
    mov r11, 20
    mov eax, edx
    call gfx_rect
    imul eax, ebx, 80
    lea r8, [rax + 24]
    lea r9, [r14 + 10]
    lea rax, [btn_names]
    mov rdi, [rax + rbx*8]
    mov eax, C_WHITE
    call draw_text
    inc ebx
    jmp .t
.t_done:
    mov rdi, [status_ptr]
    test rdi, rdi
    jz .nost
    mov r8d, 420
    lea r9, [r14 + 10]
    mov eax, 0x0080FF80
    call draw_text
.nost:
    GTEXT r15-120, r14+10, C_WHITE, s_up
    GNUM r15-88, r14+10, C_WHITE, [tmp_val]
    pop rbx
    ret

draw_cursor:
    push rbx
    push r12
    push r13
    mov r12, [mouse_x]
    mov r13, [mouse_y]
    xor ebx, ebx
.l:
    cmp ebx, 11
    jae .last
    GRECT r12, r13+rbx, rbx+2, 1, C_BLACK
    cmp ebx, 1
    jb .skip
    GRECT r12+1, r13+rbx, rbx, 1, C_WHITE
.skip:
    inc ebx
    jmp .l
.last:
    GRECT r12, r13+11, 13, 1, C_BLACK
    pop r13
    pop r12
    pop rbx
    ret

section .data
align 16
mouse_x       dq 0
mouse_y       dq 0
mouse_btn     dq 0
mouse_cyc     dq 0
mouse_pkt     times 8 db 0
prev_btn      dq 0
drag_win      dq -1
drag_dx       dq 0
drag_dy       dq 0
paint_mode    dq 0
paint_col     dq 0
paint_lx      dq -100000
paint_ly      dq 0
brush_r       dq 1
pt_x          dq 0
pt_y          dq 0
pt_c          dq 0
canvas_ptr    dq 0
gui_run_flag  dq 0
gui_last_sec  dq 0
gui_dirty     dq 1
gui_zi        dq 0
top_win       dq 1
tmp_val       dq 0
tmp_val2      dq 0
wall_theme    dq 0
status_ptr    dq 0
calc_acc      dq 0
calc_cur      dq 0
calc_op       dq 0
calc_new      dq 1
num_buf       times 32 db 0
btn_lbl       times 4 db 0
clock_buf     db "00:00:00", 0

palette       dd C_BLACK, C_WHITE, C_RED, C_GREEN, C_BLUE, C_YELLOW, C_CYAN, C_MAGENTA

wall_tab      dd 16, 0, 48, 2, 96, 3
              dd 48, 2, 16, 0, 96, 3
              dd 16, 0, 80, 3, 48, 1
              dd 96, 3, 32, 1, 48, 0

win_x         dq 16, 290, 590, 16
win_y         dq 36, 36, 36, 210
win_w         dq 260, 288, 192, 260
win_h         dq 160, 248, 222, 184
win_vis       dq 1, 1, 1, 1
win_title     dq t_info, t_paint, t_calc, t_files
z_order       dq 0, 3, 2, 1
btn_names     dq t_info, t_paint, t_calc, t_files, s_be

calc_keys     db "789/456*123-C0=+"

t_info        db "Info", 0
t_paint       db "Paint", 0
t_calc        db "Calc", 0
t_files       db "Files", 0
s_title       db "MiniOS", 0
s_sub         db "w = wallpaper   Esc = console", 0
s_l0          db "Simple graphical shell", 0
s_l1          db "Uptime (s):", 0
s_l2          db "Mouse X:", 0
s_l3          db "Mouse Y:", 0
s_l4          db "Screen:", 0
s_by          db "x", 0
s_l6          db "Files:", 0
s_l7          db "Heap free KB:", 0
s_l5          db "Esc = back to console", 0
s_hint        db "LMB draw  RMB erase  C clear", 0
s_hint2       db "=/- brush  S save  L load", 0
s_b           db "B:", 0
s_up          db "Up:", 0
s_be          db "Exit", 0
s_x           db "X", 0
s_fn          db "NAME", 0
s_fs          db "SIZE", 0
s_pfile       db "paint.raw", 0
s_saved       db "Saved paint.raw", 0
s_loaded      db "Loaded paint.raw", 0
s_failed      db "Disk/file error", 0
cmd_gui       db "gui", 0
