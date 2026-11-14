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
%define HEAP_END    0x5000000
%define KBD_MASK    15
%define PIT_FREQ    1000

%define FS_MAGIC        0x4F53464B
%define FS_VERSION      2
%define FS_MAX_FILES    64
%define FS_NAME_MAX     32
%define FS_DATA_START   0x5000000
%define FS_DATA_END     0x7000000
%define FS_DATA_SIZE    (FS_DATA_END - FS_DATA_START)
%define FS_INODE_SIZE   128
%define FS_INODE_HDR    64
%define FS_BLOCK_SIZE   4096
%define FS_TOTAL_BLOCKS 8192
%define FS_BITMAP_SIZE  1024

%define FS_DISK_SUPER_LBA  0
%define FS_DISK_BITMAP_LBA 1
%define FS_DISK_INODES_LBA 3
%define FS_DISK_DATA_LBA   19

%define INO_USED        0
%define INO_NAMELEN     8
%define INO_SIZE        16
%define INO_TYPE        24
%define INO_FIRSTBLK    32
%define INO_BLKCOUNT    40
%define INO_CHECKSUM    48
%define INO_RESERVED    56

%define SB_MAGIC        0
%define SB_VER          8
%define SB_USED         16
%define SB_USEDBLK      24
%define SB_MAXFILES     32
%define SB_DSTART       40
%define SB_DEND         48
%define SB_BLKSZ        56

%define SF_MAGIC        0x00004653
%define SF_HDR_SIZE     32
%define SF_OFF_MAGIC    0
%define SF_OFF_VER      4
%define SF_OFF_TYPE     8
%define SF_OFF_FLAGS    12
%define SF_OFF_ENTRY    16
%define SF_OFF_SIZE     24

%define FT_RAW          0
%define FT_SF_DATA      1
%define FT_SF_EXEC      2
%define FT_DIR          3

%define CON_CW          8
%define CON_CH          8

%macro CMDJ 2
    lea rdi, [r13]
    lea rsi, [%1]
    call strcmp
    test eax, eax
    jz %2
%endmacro

%macro TOKIS 2
    lea rdi, [%1]
    lea rsi, [%2]
    call strcmp
    test eax, eax
%endmacro

%macro GARGS 1
    mov rdi, r12
    mov esi, %1
    call parse_args
    cmp eax, %1
    jb .g_usage
    call gfx_begin
%endmacro

%macro PARSE2 1
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz %1
    call skip_spaces
    mov r12, rdi
    call parse_name
    mov r15, rax
    test r15, r15
    jz %1
%endmacro

kernel_entry:
    cld
    cli
    mov rbx, rdi
    lea rsp, [stack_top]
    mov rbp, rsp
    lea rdi, [bss_zero_start]
    mov ecx, bss_zero_end - bss_zero_start
    xor eax, eax
    rep stosb
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
    call os_user_tick
    cmp qword [con_dirty], 0
    jne .flush
    hlt
    jmp .main
.flush:
    call con_flush
    jmp .main

os_user_init:
    jmp print_prompt

os_user_tick:
    push rbx
    call kbd_poll_char
    test al, al
    jnz .key
    cmp qword [fs_dirty], 0
    je .done
    mov rax, [ticks]
    mov rbx, [last_key_tick]
    sub rax, rbx
    cmp rax, 200
    jb .done
    call fs_save
    jmp .done
.key:
    mov rcx, [ticks]
    mov [last_key_tick], rcx
    call os_user_key
.done:
    pop rbx
    ret

skip_spaces:
    cmp byte [rdi], ' '
    jne .done
    inc rdi
    jmp skip_spaces
.done:
    ret

parse_name:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    cmp byte [rdi + rax], ' '
    je .done
    inc rax
    jmp .loop
.done:
    add rdi, rax
    ret

con_putn:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.l:
    test r12, r12
    jz .done
    movzx edi, byte [rbx]
    call con_putc
    inc rbx
    dec r12
    jmp .l
.done:
    pop r12
    pop rbx
    ret

sf_init_hdr:
    mov dword [rdi + SF_OFF_MAGIC], SF_MAGIC
    mov dword [rdi + SF_OFF_VER], 1
    mov dword [rdi + SF_OFF_TYPE], esi
    mov dword [rdi + SF_OFF_FLAGS], 0
    mov qword [rdi + SF_OFF_ENTRY], 0
    mov qword [rdi + SF_OFF_SIZE], 0
    ret

os_user_key:
    push rbx
    push r12
    movzx edi, al
    cmp dil, 10
    je .enter
    cmp dil, 8
    je .backspace
    cmp dil, 1
    je .hist_up
    cmp dil, 2
    je .hist_down
    cmp dil, 3
    je .left
    cmp dil, 4
    je .right
    cmp dil, 5
    je .home
    cmp dil, 6
    je .end
    cmp dil, 7
    je .delete
    cmp dil, 32
    jb .done
    cmp qword [shell_len], 255
    jae .done
    mov rbx, [shell_len]
    mov r12, [shell_pos]
.sh_r:
    cmp rbx, r12
    jle .ins
    mov al, [shell_buf + rbx - 1]
    mov [shell_buf + rbx], al
    dec rbx
    jmp .sh_r
.ins:
    mov [shell_buf + r12], dil
    inc qword [shell_len]
    inc qword [shell_pos]
    mov rdi, r12
    call shell_reprint
    mov rdi, [shell_len]
    sub rdi, [shell_pos]
    call shell_cursor_back
    jmp .done
.backspace:
    mov rbx, [shell_pos]
    test rbx, rbx
    jz .done
.bl:
    cmp rbx, [shell_len]
    jae .bd
    mov al, [shell_buf + rbx]
    mov [shell_buf + rbx - 1], al
    inc rbx
    jmp .bl
.bd:
    dec qword [shell_pos]
    dec qword [shell_len]
    call con_left
    mov rdi, [shell_pos]
    call shell_reprint
    mov edi, ' '
    call con_putc
    mov rdi, [shell_len]
    sub rdi, [shell_pos]
    inc rdi
    call shell_cursor_back
    jmp .done
.delete:
    mov rbx, [shell_pos]
    cmp rbx, [shell_len]
    jae .done
    inc rbx
.dl:
    cmp rbx, [shell_len]
    jae .dl_done
    mov al, [shell_buf + rbx]
    mov [shell_buf + rbx - 1], al
    inc rbx
    jmp .dl
.dl_done:
    dec qword [shell_len]
    mov rdi, [shell_pos]
    call shell_reprint
    mov edi, ' '
    call con_putc
    mov rdi, [shell_len]
    sub rdi, [shell_pos]
    inc rdi
    call shell_cursor_back
    jmp .done
.left:
    cmp qword [shell_pos], 0
    je .done
    dec qword [shell_pos]
    call con_left
    jmp .done
.right:
    mov rax, [shell_pos]
    cmp rax, [shell_len]
    jae .done
    inc qword [shell_pos]
    call con_right
    jmp .done
.home:
    cmp qword [shell_pos], 0
    je .done
    dec qword [shell_pos]
    call con_left
    jmp .home
.end:
    call shell_goto_end
    jmp .done
.hist_up:
    cmp qword [hist_len], 0
    je .done
    call shell_goto_end
    call shell_erase
    xor ebx, ebx
.hcp_l:
    cmp rbx, [hist_len]
    jae .hdone
    movzx eax, byte [hist_buf + rbx]
    mov [shell_buf + rbx], al
    mov edi, eax
    call con_putc
    inc rbx
    inc qword [shell_len]
    jmp .hcp_l
.hdone:
    mov rax, [shell_len]
    mov [shell_pos], rax
    jmp .done
.hist_down:
    call shell_goto_end
    call shell_erase
    jmp .done
.enter:
    call shell_goto_end
    call con_newline
    mov rbx, [shell_len]
    mov byte [shell_buf + rbx], 0
    test rbx, rbx
    jz .prompt
    mov [hist_len], rbx
    xor ecx, ecx
.hcp:
    movzx eax, byte [shell_buf + rcx]
    mov [hist_buf + rcx], al
    inc rcx
    cmp rcx, rbx
    jb .hcp
    lea rdi, [shell_buf]
    call shell_run_line
    cmp qword [fs_dirty], 0
    je .prompt
    call fs_save
.prompt:
    mov qword [shell_len], 0
    mov qword [shell_pos], 0
    call print_prompt
.done:
    pop r12
    pop rbx
    ret

shell_erase:
    cmp qword [shell_len], 0
    je .r
    dec qword [shell_len]
    mov edi, 8
    call con_putc
    jmp shell_erase
.r:
    mov qword [shell_pos], 0
    ret

shell_goto_end:
    mov rax, [shell_pos]
    cmp rax, [shell_len]
    jae .r
    inc qword [shell_pos]
    call con_right
    jmp shell_goto_end
.r:
    ret

shell_reprint:
    push rbx
    mov rbx, rdi
.l:
    cmp rbx, [shell_len]
    jae .r
    movzx edi, byte [shell_buf + rbx]
    call con_putc
    inc rbx
    jmp .l
.r:
    pop rbx
    ret

shell_cursor_back:
    push rbx
    mov rbx, rdi
.l:
    test rbx, rbx
    jz .r
    call con_left
    dec rbx
    jmp .l
.r:
    pop rbx
    ret

shell_exec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [last_status], 0
    mov r12, rdi
    lea r13, [word_buf]
    xor r14, r14
.parse_word:
    mov al, [r12]
    test al, al
    jz .word_done
    cmp al, ' '
    je .word_done
    cmp r14, 62
    jae .word_done
    mov [r13 + r14], al
    inc r14
    inc r12
    jmp .parse_word
.word_done:
    mov byte [r13 + r14], 0
.skip_spaces:
    cmp byte [r12], ' '
    jne .dispatch
    inc r12
    jmp .skip_spaces
.dispatch:
    lea rdi, [r13]
    lea rsi, [cmd_help]
    call strcmp
    test eax, eax
    jz .do_help
    lea rdi, [r13]
    lea rsi, [cmd_clear]
    call strcmp
    test eax, eax
    jz .do_clear
    lea rdi, [r13]
    lea rsi, [cmd_echo]
    call strcmp
    test eax, eax
    jz .do_echo
    lea rdi, [r13]
    lea rsi, [cmd_layout]
    call strcmp
    test eax, eax
    jz .do_layout
    lea rdi, [r13]
    lea rsi, [cmd_reboot]
    call strcmp
    test eax, eax
    jz .do_reboot
    lea rdi, [r13]
    lea rsi, [cmd_ver]
    call strcmp
    test eax, eax
    jz .do_ver
    lea rdi, [r13]
    lea rsi, [cmd_uptime]
    call strcmp
    test eax, eax
    jz .do_uptime
    lea rdi, [r13]
    lea rsi, [cmd_background]
    call strcmp
    test eax, eax
    jz .do_background
    lea rdi, [r13]
    lea rsi, [cmd_ls]
    call strcmp
    test eax, eax
    jz .do_ls
    lea rdi, [r13]
    lea rsi, [cmd_cat]
    call strcmp
    test eax, eax
    jz .do_cat
    lea rdi, [r13]
    lea rsi, [cmd_touch]
    call strcmp
    test eax, eax
    jz .do_touch
    lea rdi, [r13]
    lea rsi, [cmd_rm]
    call strcmp
    test eax, eax
    jz .do_rm
    lea rdi, [r13]
    lea rsi, [cmd_hex]
    call strcmp
    test eax, eax
    jz .do_hex
    lea rdi, [r13]
    lea rsi, [cmd_sfnew]
    call strcmp
    test eax, eax
    jz .do_sfnew
    lea rdi, [r13]
    lea rsi, [cmd_sfinfo]
    call strcmp
    test eax, eax
    jz .do_sfinfo
    lea rdi, [r13]
    lea rsi, [cmd_sfwrite]
    call strcmp
    test eax, eax
    jz .do_sfwrite
    lea rdi, [r13]
    lea rsi, [cmd_sfhello]
    call strcmp
    test eax, eax
    jz .do_sfhello
    lea rdi, [r13]
    lea rsi, [cmd_run]
    call strcmp
    test eax, eax
    jz .do_run
    lea rdi, [r13]
    lea rsi, [cmd_mkprog]
    call strcmp
    test eax, eax
    jz .do_mkprog
    lea rdi, [r13]
    lea rsi, [cmd_sync]
    call strcmp
    test eax, eax
    jz .do_sync
    lea rdi, [r13]
    lea rsi, [cmd_format]
    call strcmp
    test eax, eax
    jz .do_format
    lea rdi, [r13]
    lea rsi, [cmd_gui]
    call strcmp
    test eax, eax
    jz .do_gui
    CMDJ cmd_cp, .do_cp
    CMDJ cmd_mv, .do_mv
    CMDJ cmd_write, .do_write
    CMDJ cmd_stat, .do_stat
    CMDJ cmd_df, .do_df
    CMDJ cmd_mem, .do_mem
    CMDJ cmd_date, .do_date
    CMDJ cmd_calc, .do_calc
    CMDJ cmd_color, .do_color
    CMDJ cmd_font, .do_font
    CMDJ cmd_sleep, .do_sleep
    CMDJ cmd_shutdown, .do_shutdown
    CMDJ cmd_cpuid, .do_cpuid
    CMDJ cmd_rand, .do_rand
    CMDJ cmd_beep, .do_beep
    CMDJ cmd_mkdir, .do_mkdir
    CMDJ cmd_cd, .do_cd
    CMDJ cmd_pwd, .do_pwd
    CMDJ cmd_append, .do_append
    CMDJ cmd_edit, .do_edit
    CMDJ cmd_sak, .do_sak
    CMDJ cmd_sakdemo, .do_sakdemo
    CMDJ cmd_set, .do_set
    CMDJ cmd_unset, .do_unset
    CMDJ cmd_vars, .do_vars
    CMDJ cmd_let, .do_let
    CMDJ cmd_input, .do_input
    CMDJ cmd_pause, .do_pause
    CMDJ cmd_rem, .done
    CMDJ cmd_if, .do_scriptonly
    CMDJ cmd_elif, .do_scriptonly
    CMDJ cmd_else, .do_scriptonly
    CMDJ cmd_end, .do_scriptonly
    CMDJ cmd_while, .do_scriptonly
    CMDJ cmd_goto, .do_scriptonly
    CMDJ cmd_exit, .do_scriptonly
    CMDJ cmd_rmdir, .do_rm
    CMDJ cmd_del, .do_rm
    CMDJ cmd_type, .do_cat
    CMDJ cmd_cls, .do_clear
    CMDJ cmd_dir, .do_ls
    CMDJ cmd_copy, .do_cp
    CMDJ cmd_ren, .do_mv
    CMDJ cmd_gcls, .do_gcls
    CMDJ cmd_gpix, .do_gpix
    CMDJ cmd_gline, .do_gline
    CMDJ cmd_grect, .do_grect
    CMDJ cmd_gfill, .do_gfill
    CMDJ cmd_gcirc, .do_gcirc
    CMDJ cmd_gdisc, .do_gdisc
    CMDJ cmd_gtext, .do_gtext
    CMDJ cmd_gscale, .do_gscale
    CMDJ cmd_gwait, .do_gwait
    CMDJ cmd_gend, .do_gend
    CMDJ cmd_gauto, .do_gauto
    CMDJ cmd_gflip, .do_gflip
    CMDJ cmd_gkey, .do_gkey
    CMDJ cmd_md, .do_md
    CMDJ cmd_mddemo, .do_mddemo
    jmp .try_script
.unknown:
    mov qword [last_status], 1
    lea rdi, [msg_unknown]
    call con_puts_utf8
    lea rdi, [r13]
    call con_puts
    call con_newline
    jmp .done

.do_help:
    mov rdi, r12
    call skip_spaces
    cmp byte [rdi], 0
    je .help_all
    mov rsi, rdi
    lea rdi, [tok_a]
    call get_token
    lea rbx, [help_tab]
.hl:
    mov rsi, [rbx]
    test rsi, rsi
    jz .help_nf
    lea rdi, [tok_a]
    call strcmp
    test eax, eax
    jz .help_found
    add rbx, 16
    jmp .hl
.help_found:
    mov rdi, [rbx + 8]
    call con_puts_utf8
    call con_newline
    jmp .done
.help_nf:
    mov qword [last_status], 1
    lea rdi, [msg_help_nf]
    call con_puts_utf8
    call con_newline
    jmp .done
.help_all:
    lea rdi, [msg_help_text]
    call con_puts_utf8
    call con_newline
    jmp .done
.do_clear:
    call con_clear
    jmp .done
.do_echo:
    mov rdi, r12
    call con_puts
    call con_newline
    jmp .done
.do_gui:
    call gui_run
    jmp .done
.do_layout:
    lea rdi, [r12]
    lea rsi, [arg_ru]
    call strcmp
    test eax, eax
    jz .set_ru
    lea rdi, [r12]
    lea rsi, [arg_en]
    call strcmp
    test eax, eax
    jz .set_en
    lea rdi, [msg_layout_usage]
    call con_puts_utf8
    call con_newline
    jmp .done
.set_ru:
    mov qword [kbd_layout], 1
    lea rdi, [msg_ru_set]
    call con_puts_utf8
    call con_newline
    jmp .done
.set_en:
    mov qword [kbd_layout], 0
    lea rdi, [msg_en_set]
    call con_puts_utf8
    call con_newline
    jmp .done
.do_reboot:
    cmp qword [fs_dirty], 0
    je .rb
    call fs_save
.rb:
    call reboot
    jmp .done
.do_ver:
    lea rdi, [msg_ver]
    call con_puts_utf8
    call con_newline
    jmp .done
.do_uptime:
    lea rdi, [msg_uptime_prefix]
    call con_puts_utf8
    mov rdi, [ticks]
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done
.do_background:
    mov rdi, r12
    call skip_spaces
    mov al, [rdi]
    cmp al, '0'
    je .fillblack
    cmp al, '1'
    je .fillwhite
    cmp al, '2'
    je .fillred
    cmp al, '3'
    je .fillgreen
    cmp al, '4'
    je .fillblue
    cmp al, '5'
    je .fillcyan
    cmp al, '6'
    je .fillyellow
    cmp al, '7'
    je .fillmagenta
    cmp al, '8'
    je .fillgray
    cmp al, '9'
    je .fillorange
    jmp .done
.fillblack:
    mov eax, C_BLACK
    jmp .fill_go
.fillwhite:
    mov eax, C_WHITE
    jmp .fill_go
.fillred:
    mov eax, C_RED
    jmp .fill_go
.fillgreen:
    mov eax, C_GREEN
    jmp .fill_go
.fillblue:
    mov eax, C_BLUE
    jmp .fill_go
.fillcyan:
    mov eax, C_CYAN
    jmp .fill_go
.fillyellow:
    mov eax, C_YELLOW
    jmp .fill_go
.fillmagenta:
    mov eax, C_MAGENTA
    jmp .fill_go
.fillgray:
    mov eax, C_GRAY
    jmp .fill_go
.fillorange:
    mov eax, C_ORANGE
.fill_go:
    mov [con_bg], rax
    mov qword [con_dirty], 1
    jmp .done

.do_sync:
    call fs_save
    test rax, rax
    jnz .sync_fail
    lea rdi, [msg_synced]
    call con_puts_utf8
    call con_newline
    jmp .done
.sync_fail:
    mov qword [last_status], 1
    lea rdi, [msg_disk_err]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_format:
    call fs_format
    call fs_save
    mov qword [fs_dirty], 0
    lea rdi, [msg_formatted]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_ls:
    lea rdi, [rd_buf]
    mov esi, 4000
    call fs_list
    lea rdi, [rd_buf]
    call con_puts
    call con_newline
    jmp .done

.do_cat:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cat_no_file
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cat_no_file
    mov r15, rax
    mov r13, [r15 + INO_SIZE]
    xor r12, r12
    cmp qword [r15 + INO_TYPE], FT_SF_DATA
    jb .cat_size_ok
    cmp r13, SF_HDR_SIZE
    jbe .cat_empty
    sub r13, SF_HDR_SIZE
    mov r12, SF_HDR_SIZE
.cat_size_ok:
    test r13, r13
    jz .cat_empty
    mov rcx, r13
    cmp rcx, 4096
    jbe .cat_read
    mov rcx, 4096
.cat_read:
    mov rdi, r15
    mov rsi, r12
    lea rdx, [rd_buf]
    call fs_read_at
    mov r13, rax
    lea rbx, [rd_buf]
.cat_print:
    test r13, r13
    jz .cat_print_done
    movzx edi, byte [rbx]
    test dil, dil
    jz .cat_print_done
    call con_putc
    inc rbx
    dec r13
    jmp .cat_print
.cat_print_done:
    call con_newline
    jmp .done
.cat_empty:
    lea rdi, [msg_empty]
    call con_puts_utf8
    call con_newline
    jmp .done
.cat_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_touch:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .touch_fail
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.touch_fail:
    mov qword [last_status], 1
    lea rdi, [msg_exists]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_rm:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_delete
    cmp rax, -1
    je .rm_no_file
    cmp rax, -2
    je .rm_notempty
    lea rdi, [msg_removed]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.rm_notempty:
    mov qword [last_status], 1
    lea rdi, [msg_notempty]
    call con_puts_utf8
    call con_newline
    jmp .done
.rm_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_hex:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .hex_no_file
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .hex_no_file
    mov r15, rax
    mov r13, [r15 + INO_SIZE]
    test r13, r13
    jz .hex_empty
    cmp r13, 128
    jbe .hex_read
    mov r13, 128
.hex_read:
    mov rdi, r15
    xor esi, esi
    lea rdx, [fs_tmpbuf]
    mov rcx, r13
    call fs_read_at
    mov r13, rax
    lea rbx, [fs_tmpbuf]
.hex_loop:
    test r13, r13
    jz .hex_done
    movzx edi, byte [rbx]
    mov esi, 16
    call con_putu
    mov edi, ' '
    call con_putc
    inc rbx
    dec r13
    jmp .hex_loop
.hex_done:
    call con_newline
    jmp .done
.hex_empty:
    lea rdi, [msg_empty]
    call con_puts_utf8
    call con_newline
    jmp .done
.hex_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_sfnew:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    call skip_spaces
    mov r12, rdi
    call parse_name
    mov rcx, rax
    mov edx, FT_SF_DATA
    cmp rcx, 4
    jne .sfnew_create
    cmp byte [r12 + 0], 'e'
    jne .sfnew_create
    cmp byte [r12 + 1], 'x'
    jne .sfnew_create
    cmp byte [r12 + 2], 'e'
    jne .sfnew_create
    cmp byte [r12 + 3], 'c'
    jne .sfnew_create
    mov edx, FT_SF_EXEC
.sfnew_create:
    mov rdi, rbx
    mov rsi, r14
    push rdx
    call fs_create
    pop rdx
    cmp rax, -1
    je .sfnew_fail
    mov r15, rax
    lea rdi, [fs_tmpbuf]
    mov esi, edx
    call sf_init_hdr
    mov rdi, r15
    lea rsi, [fs_tmpbuf]
    mov edx, SF_HDR_SIZE
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.sfnew_fail:
    mov qword [last_status], 1
    lea rdi, [msg_exists]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_sfinfo:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .sfinfo_no_file
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .sfinfo_no_file
    mov r15, rax
    mov rax, [r15 + INO_SIZE]
    cmp rax, SF_HDR_SIZE
    jb .sfinfo_bad
    mov rdi, r15
    xor esi, esi
    lea rdx, [fs_tmpbuf]
    mov ecx, SF_HDR_SIZE
    call fs_read_at
    lea rbx, [fs_tmpbuf]
    cmp dword [rbx + SF_OFF_MAGIC], SF_MAGIC
    jne .sfinfo_bad
    lea rdi, [msg_sf_magic]
    call con_puts_utf8
    mov edi, [rbx + SF_OFF_MAGIC]
    mov esi, 16
    call con_putu
    call con_newline
    lea rdi, [msg_sf_ver]
    call con_puts_utf8
    mov edi, [rbx + SF_OFF_VER]
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_sf_type]
    call con_puts_utf8
    mov edi, [rbx + SF_OFF_TYPE]
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_sf_entry]
    call con_puts_utf8
    mov rdi, [rbx + SF_OFF_ENTRY]
    mov esi, 16
    call con_putu
    call con_newline
    lea rdi, [msg_sf_size]
    call con_puts_utf8
    mov rdi, [rbx + SF_OFF_SIZE]
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done
.sfinfo_bad:
    mov qword [last_status], 1
    lea rdi, [msg_sf_bad]
    call con_puts_utf8
    call con_newline
    jmp .done
.sfinfo_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_sfwrite:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    call skip_spaces
    mov r12, rdi
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .sfwrite_no_file
    mov r15, rax
    mov rdi, r15
    call fs_get_inode
    test rax, rax
    jz .sfwrite_no_file
    mov r13, rax
    cmp qword [r13 + INO_TYPE], FT_SF_DATA
    jb .sfwrite_not_sf
    lea rdi, [fs_tmpbuf + SF_HDR_SIZE]
    mov rsi, r12
    xor ecx, ecx
.sfwrite_cp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .sfwrite_cp_done
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 400
    jae .sfwrite_cp_done
    jmp .sfwrite_cp
.sfwrite_cp_done:
    push rcx
    lea rdi, [fs_tmpbuf]
    mov esi, FT_SF_DATA
    call sf_init_hdr
    pop rcx
    lea rdi, [fs_tmpbuf]
    mov [rdi + SF_OFF_SIZE], rcx
    add rcx, SF_HDR_SIZE
    mov rdi, r15
    lea rsi, [fs_tmpbuf]
    mov rdx, rcx
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.sfwrite_not_sf:
    mov qword [last_status], 1
    lea rdi, [msg_sf_bad]
    call con_puts_utf8
    call con_newline
    jmp .done
.sfwrite_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_sfhello:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    mov edx, FT_SF_EXEC
    call fs_create
    cmp rax, -1
    je .sfhello_fail
    mov r15, rax
    lea rdi, [fs_tmpbuf]
    mov esi, FT_SF_EXEC
    call sf_init_hdr
    mov r13d, sf_hello_code_end - sf_hello_code
    lea rsi, [sf_hello_code]
    lea rdi, [fs_tmpbuf + SF_HDR_SIZE]
    mov ecx, r13d
    cld
    rep movsb
    lea rdi, [fs_tmpbuf]
    mov [rdi + SF_OFF_SIZE], r13
    mov rdi, r15
    lea rsi, [fs_tmpbuf]
    mov edx, r13d
    add edx, SF_HDR_SIZE
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.sfhello_fail:
    mov qword [last_status], 1
    lea rdi, [msg_exists]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_mkprog:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    mov edx, FT_SF_EXEC
    call fs_create
    cmp rax, -1
    je .mkprog_fail
    mov r15, rax
    lea rdi, [fs_tmpbuf]
    mov esi, FT_SF_EXEC
    call sf_init_hdr
    mov r13d, prog_hi_code_end - prog_hi_code
    lea rsi, [prog_hi_code]
    lea rdi, [fs_tmpbuf + SF_HDR_SIZE]
    mov ecx, r13d
    cld
    rep movsb
    lea rdi, [fs_tmpbuf]
    mov [rdi + SF_OFF_SIZE], r13
    mov rdi, r15
    lea rsi, [fs_tmpbuf]
    mov edx, r13d
    add edx, SF_HDR_SIZE
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done
.mkprog_fail:
    mov qword [last_status], 1
    lea rdi, [msg_exists]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_run:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .run_no_file
    mov r15, rax
    mov rdi, r15
    call fs_get_inode
    test rax, rax
    jz .run_no_file
    mov r13, rax
    cmp qword [r13 + INO_TYPE], FT_SF_EXEC
    jne .run_not_exec
    mov rax, [r13 + INO_SIZE]
    cmp rax, SF_HDR_SIZE
    jb .run_no_file
    mov rdi, r13
    xor esi, esi
    lea rdx, [fs_tmpbuf]
    mov ecx, SF_HDR_SIZE
    call fs_read_at
    lea rbx, [fs_tmpbuf]
    cmp dword [rbx + SF_OFF_MAGIC], SF_MAGIC
    jne .run_bad_magic
    lea rdi, [msg_running]
    call con_puts_utf8
    lea rdi, [r13 + FS_INODE_HDR]
    mov rsi, [r13 + INO_NAMELEN]
    call con_putn
    call con_newline
    mov rax, [r13 + INO_FIRSTBLK]
    shl rax, 12
    add rax, FS_DATA_START
    add rax, SF_HDR_SIZE
    mov rcx, [rbx + SF_OFF_ENTRY]
    add rax, rcx
    call rax
    jmp .done
.run_no_file:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done
.run_not_exec:
    mov qword [last_status], 1
    lea rdi, [msg_not_exec]
    call con_puts_utf8
    call con_newline
    jmp .done
.run_bad_magic:
    mov qword [last_status], 1
    lea rdi, [msg_sf_bad]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_cp:
    PARSE2 .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cp_nofile
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    mov r13, rax
    cmp qword [r13 + INO_TYPE], FT_DIR
    je .cp_isdir
    mov rdi, r12
    mov rsi, r15
    mov rdx, [r13 + INO_TYPE]
    call fs_create
    cmp rax, -1
    je .cp_exists
    mov rdi, rax
    mov rsi, [r13 + INO_FIRSTBLK]
    shl rsi, 12
    add rsi, FS_DATA_START
    mov rdx, [r13 + INO_SIZE]
    call fs_write
    cmp rax, -1
    je .cp_space
    lea rdi, [msg_copied]
    call con_puts_utf8
    mov rdi, r12
    mov rsi, r15
    call con_putn
    call con_newline
    jmp .done
.cp_nofile:
    mov qword [last_status], 1
    lea rdi, [msg_no_file]
    call con_puts_utf8
    call con_newline
    jmp .done
.cp_exists:
    mov qword [last_status], 1
    lea rdi, [msg_exists]
    call con_puts_utf8
    call con_newline
    jmp .done
.cp_space:
    mov qword [last_status], 1
    lea rdi, [msg_nospace]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_mv:
    PARSE2 .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cp_nofile
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    mov r13, rax
    mov rdi, r12
    mov rsi, r15
    call fs_lookup
    cmp rax, -1
    je .mv_rename
    mov rcx, rax
    mov rdi, rax
    call fs_get_inode
    cmp qword [rax + INO_TYPE], FT_DIR
    jne .cp_exists
    cmp rax, r13
    je .cp_exists
    inc rcx
    mov [r13 + INO_RESERVED], rcx
    mov qword [fs_dirty], 1
    lea rdi, [msg_moved]
    call con_puts_utf8
    mov rdi, r12
    mov rsi, r15
    call con_putn
    call con_newline
    jmp .done
.mv_rename:
    cmp r15, FS_NAME_MAX
    ja .cp_exists
    mov [r13 + INO_NAMELEN], r15
    lea rdi, [r13 + FS_INODE_HDR]
    mov rsi, r12
    mov rcx, r15
    cld
    rep movsb
    mov rcx, FS_NAME_MAX
    sub rcx, r15
    xor al, al
    rep stosb
    mov qword [fs_dirty], 1
    lea rdi, [msg_moved]
    call con_puts_utf8
    mov rdi, r12
    mov rsi, r15
    call con_putn
    call con_newline
    jmp .done

.do_write:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    cmp r14, FS_NAME_MAX
    ja .done
    call skip_spaces
    mov r12, rdi
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    jne .w_have
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .cp_space
.w_have:
    mov r15, rax
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rdi, r15
    mov rsi, r12
    call fs_write
    cmp rax, -1
    je .cp_space
    lea rdi, [msg_written]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done

.do_stat:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cp_nofile
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    mov r15, rax
    lea rdi, [msg_sf_size]
    call con_puts_utf8
    mov rdi, [r15 + INO_SIZE]
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_st_blocks]
    call con_puts_utf8
    mov rdi, [r15 + INO_BLKCOUNT]
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_st_first]
    call con_puts_utf8
    mov rdi, [r15 + INO_FIRSTBLK]
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_sf_type]
    call con_puts_utf8
    mov rdi, [r15 + INO_TYPE]
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done

.do_df:
    lea rdi, [msg_df_files]
    call con_puts_utf8
    mov rdi, [fs_super + SB_USED]
    mov esi, 10
    call con_putu
    mov edi, '/'
    call con_putc
    mov edi, FS_MAX_FILES
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_df_blocks]
    call con_puts_utf8
    mov rdi, [fs_super + SB_USEDBLK]
    mov esi, 10
    call con_putu
    mov edi, '/'
    call con_putc
    mov edi, FS_TOTAL_BLOCKS
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_df_kb]
    call con_puts_utf8
    mov rdi, [fs_super + SB_USEDBLK]
    shl rdi, 2
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done

.do_mem:
    lea rdi, [msg_mem_used]
    call con_puts_utf8
    mov rdi, [heap_cur]
    sub rdi, HEAP_START
    shr rdi, 10
    mov esi, 10
    call con_putu
    call con_newline
    lea rdi, [msg_mem_free]
    call con_puts_utf8
    mov rdi, HEAP_END
    sub rdi, [heap_cur]
    shr rdi, 10
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done

.do_date:
    call rtc_wait
    mov edi, 9
    call cmos_get
    lea edi, [rax + 2000]
    mov esi, 10
    call con_putu
    mov edi, '-'
    call con_putc
    mov edi, 8
    call cmos_get
    mov edi, eax
    call put2
    mov edi, '-'
    call con_putc
    mov edi, 7
    call cmos_get
    mov edi, eax
    call put2
    mov edi, ' '
    call con_putc
    mov edi, 4
    call cmos_get
    mov edi, eax
    call put2
    mov edi, ':'
    call con_putc
    mov edi, 2
    call cmos_get
    mov edi, eax
    call put2
    mov edi, ':'
    call con_putc
    xor edi, edi
    call cmos_get
    mov edi, eax
    call put2
    call con_newline
    jmp .done

.do_calc:
    mov rdi, r12
    call skip_spaces
    cmp byte [rdi], 0
    je .calc_usage
    call parse_int
    mov rbx, rax
    call skip_spaces
    movzx r14d, byte [rdi]
    test r14d, r14d
    jz .calc_usage
    inc rdi
    call skip_spaces
    call parse_int
    mov r15, rax
    cmp r14b, '+'
    je .c_add
    cmp r14b, '-'
    je .c_sub
    cmp r14b, '*'
    je .c_mul
    cmp r14b, '/'
    je .c_div
    cmp r14b, '%'
    je .c_div
    jmp .calc_usage
.c_add:
    lea rdi, [rbx + r15]
    jmp .c_out
.c_sub:
    mov rdi, rbx
    sub rdi, r15
    jmp .c_out
.c_mul:
    mov rdi, rbx
    imul rdi, r15
    jmp .c_out
.c_div:
    test r15, r15
    jz .c_zero
    mov rax, rbx
    cqo
    idiv r15
    mov rdi, rax
    cmp r14b, '%'
    jne .c_out
    mov rdi, rdx
.c_out:
    call put_int
    call con_newline
    jmp .done
.c_zero:
    mov qword [last_status], 1
    lea rdi, [msg_div0]
    call con_puts_utf8
    call con_newline
    jmp .done
.calc_usage:
    mov qword [last_status], 1
    lea rdi, [msg_calc_usage]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_color:
    mov rdi, r12
    call skip_spaces
    movzx eax, byte [rdi]
    sub eax, '0'
    cmp eax, 9
    ja .done
    lea rdx, [color_tab]
    mov eax, [rdx + rax*4]
    mov [con_fg], rax
    mov qword [con_dirty], 1
    jmp .done

.do_font:
    mov rdi, r12
    call skip_spaces
    call parse_int
    mov edi, 1
    cmp rax, 8
    je .font_set
    mov edi, 2
    cmp rax, 16
    je .font_set
    mov edi, 4
    cmp rax, 32
    je .font_set
    lea rdi, [msg_font_usage]
    call con_puts_utf8
    call con_newline
    jmp .done
.font_set:
    call con_set_scale
    jmp .done

.do_sleep:
    mov rdi, r12
    call skip_spaces
    call parse_int
    mov rdi, rax
    call delay_ms
    jmp .done

.do_shutdown:
    cmp qword [fs_dirty], 0
    je .sd
    call fs_save
.sd:
    lea rdi, [msg_shutdown]
    call con_puts_utf8
    call con_flush
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004
    out dx, ax
    call halt
    jmp .done

.do_cpuid:
    xor eax, eax
    cpuid
    mov [fs_tmpbuf], ebx
    mov [fs_tmpbuf + 4], edx
    mov [fs_tmpbuf + 8], ecx
    mov byte [fs_tmpbuf + 12], 0
    lea rdi, [msg_cpu_vendor]
    call con_puts_utf8
    lea rdi, [fs_tmpbuf]
    call con_puts
    call con_newline
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000004
    jb .done
    mov eax, 0x80000002
    cpuid
    mov [fs_tmpbuf + 16], eax
    mov [fs_tmpbuf + 20], ebx
    mov [fs_tmpbuf + 24], ecx
    mov [fs_tmpbuf + 28], edx
    mov eax, 0x80000003
    cpuid
    mov [fs_tmpbuf + 32], eax
    mov [fs_tmpbuf + 36], ebx
    mov [fs_tmpbuf + 40], ecx
    mov [fs_tmpbuf + 44], edx
    mov eax, 0x80000004
    cpuid
    mov [fs_tmpbuf + 48], eax
    mov [fs_tmpbuf + 52], ebx
    mov [fs_tmpbuf + 56], ecx
    mov [fs_tmpbuf + 60], edx
    mov byte [fs_tmpbuf + 64], 0
    lea rdi, [msg_cpu_brand]
    call con_puts_utf8
    lea rdi, [fs_tmpbuf + 16]
    call con_puts
    call con_newline
    jmp .done

.do_rand:
    mov rdi, r12
    call skip_spaces
    call parse_int
    mov rbx, rax
    test rbx, rbx
    jnz .r_ok
    mov ebx, 100
.r_ok:
    mov rax, [ticks]
    xor [rand_state], rax
    call rand_next
    xor edx, edx
    div rbx
    mov rdi, rdx
    mov esi, 10
    call con_putu
    call con_newline
    jmp .done

.do_beep:
    mov al, 0xB6
    out 0x43, al
    mov ax, 1356
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 3
    out 0x61, al
    mov edi, 200
    call delay_ms
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    jmp .done

.cp_isdir:
    mov qword [last_status], 1
    lea rdi, [msg_isdir]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_scriptonly:
    mov qword [last_status], 1
    lea rdi, [msg_scriptonly]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_pause:
    lea rdi, [msg_pause]
    call con_puts_utf8
    call wait_key
    call con_newline
    jmp .done

.do_mkdir:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    mov edx, FT_DIR
    call fs_create
    cmp rax, -1
    je .touch_fail
    lea rdi, [msg_created]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done

.do_cd:
    mov rdi, r12
    call skip_spaces
    cmp byte [rdi], 0
    je .do_pwd
    call cd_path
    test rax, rax
    jz .done
    mov qword [last_status], 1
    lea rdi, [msg_no_dir]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_pwd:
    call build_path
    mov rdi, rax
    call con_puts
    call con_newline
    jmp .done

.do_append:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    cmp r14, FS_NAME_MAX
    ja .done
    call skip_spaces
    mov r12, rdi
    xor r15d, r15d
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    jne .ap_exist
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .cp_space
    mov r13, rax
    jmp .ap_text
.ap_exist:
    mov r13, rax
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    cmp qword [rax + INO_TYPE], FT_DIR
    je .cp_isdir
    mov rcx, [rax + INO_SIZE]
    cmp rcx, 4096
    jbe .ap_sz
    mov ecx, 4096
.ap_sz:
    mov rdi, rax
    xor esi, esi
    lea rdx, [cap_out]
    call fs_read_at
    mov r15, rax
    test r15, r15
    jz .ap_text
    cmp byte [cap_out + r15 - 1], 10
    je .ap_text
    mov byte [cap_out + r15], 10
    inc r15
.ap_text:
    mov rdi, r12
    call strlen
    lea rdx, [r15 + rax + 1]
    cmp rdx, 8000
    ja .cp_space
    mov rcx, rax
    lea rdi, [cap_out + r15]
    mov rsi, r12
    cld
    rep movsb
    mov byte [rdi], 10
    mov r15, rdx
    mov rdi, r13
    lea rsi, [cap_out]
    mov rdx, r15
    call fs_write
    cmp rax, -1
    je .cp_space
    lea rdi, [msg_written]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done

.do_edit:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    cmp r14, FS_NAME_MAX
    ja .done
    xor eax, eax
    mov [ed_len], rax
    mov [ed_pos], rax
    mov [ed_top], rax
    mov [ed_mod], rax
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .e_run
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .e_run
    cmp qword [rax + INO_TYPE], FT_DIR
    je .cp_isdir
    mov rcx, [rax + INO_SIZE]
    cmp rcx, 4000
    jbe .e_sz
    mov ecx, 4000
.e_sz:
    mov rdi, rax
    xor esi, esi
    lea rdx, [edit_buf]
    call fs_read_at
    mov [ed_len], rax
.e_run:
    call edit_run
    mov r15, rax
    call con_clear
    test r15, r15
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    jne .e_have
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .cp_space
.e_have:
    mov rdi, rax
    lea rsi, [edit_buf]
    mov rdx, [ed_len]
    call fs_write
    cmp rax, -1
    je .cp_space
    lea rdi, [msg_written]
    call con_puts_utf8
    mov rdi, rbx
    mov rsi, r14
    call con_putn
    call con_newline
    jmp .done

.do_set:
    mov rdi, r12
    call skip_spaces
    cmp byte [rdi], 0
    je .do_vars
    mov rbx, rdi
    xor ecx, ecx
.sn:
    mov al, [rbx + rcx]
    test al, al
    jz .sn_end
    cmp al, '='
    je .sn_end
    cmp al, ' '
    je .sn_end
    inc ecx
    jmp .sn
.sn_end:
    mov r14, rcx
    lea rdi, [rbx + rcx]
    call skip_spaces
    cmp byte [rdi], '='
    jne .sv
    inc rdi
    call skip_spaces
.sv:
    mov rdx, rdi
    mov rdi, rbx
    mov rsi, r14
    call var_set
    jmp .done

.do_vars:
    call vars_list
    jmp .done

.do_unset:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov rsi, rax
    mov rdi, rbx
    call var_find
    test rax, rax
    jz .done
    mov byte [rax], 0
    jmp .done

.do_let:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    call skip_spaces
    call parse_int
    mov r15, rax
    call skip_spaces
    mov al, [rdi]
    test al, al
    jz .let_store
    movzx r13d, al
    inc rdi
    call skip_spaces
    call parse_int
    cmp r13b, '+'
    jne .lt1
    add r15, rax
    jmp .let_store
.lt1:
    cmp r13b, '-'
    jne .lt2
    sub r15, rax
    jmp .let_store
.lt2:
    cmp r13b, '*'
    jne .lt3
    imul r15, rax
    jmp .let_store
.lt3:
    cmp r13b, '/'
    je .lt_div
    cmp r13b, '%'
    jne .let_store
.lt_div:
    test rax, rax
    jz .c_zero
    mov rcx, rax
    mov rax, r15
    cqo
    idiv rcx
    cmp r13b, '%'
    jne .lt_q
    mov r15, rdx
    jmp .let_store
.lt_q:
    mov r15, rax
.let_store:
    mov rdi, r15
    call i2s
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r14
    call var_set
    jmp .done

.do_input:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    call skip_spaces
    cmp byte [rdi], 0
    je .in_read
    call con_puts
.in_read:
    lea rdi, [in_buf]
    mov esi, 47
    call read_line
    lea rdx, [in_buf]
    mov rdi, rbx
    mov rsi, r14
    call var_set
    jmp .done

.do_sakdemo:
    lea rdi, [s_demo_name]
    mov esi, 8
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .touch_fail
    mov rdi, rax
    lea rsi, [demo_sak_text]
    mov edx, demo_sak_end - demo_sak_text
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    lea rdi, [s_demo_name]
    call con_puts
    call con_newline
    jmp .done

.try_script:
    lea rdi, [r13]
    call strlen
    mov r14, rax
    test r14, r14
    jz .unknown
    cmp r14, 28
    ja .unknown
    cmp r14, 4
    jb .ts_append
    lea rax, [r13 + r14 - 4]
    cmp dword [rax], 0x6B61732E
    jne .ts_append
    lea rdi, [r13]
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    jne .ts_found
.ts_append:
    lea rdi, [name_tmp]
    lea rsi, [r13]
    mov rcx, r14
    cld
    rep movsb
    mov dword [rdi], 0x6B61732E
    mov byte [rdi + 4], 0
    lea rdi, [name_tmp]
    lea rsi, [r14 + 4]
    call fs_lookup
    cmp rax, -1
    je .unknown
.ts_found:
    mov r15, rax
    jmp .sak_go

.do_sak:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .sak_usage
    call skip_spaces
    mov r12, rdi
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cp_nofile
    mov r15, rax
.sak_go:
    cmp qword [sak_active], 0
    jne .sak_nested
    mov rdi, r15
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    mov rbx, rax
    cmp qword [rbx + INO_TYPE], FT_DIR
    je .cp_isdir
    mov rcx, [rbx + INO_SIZE]
    cmp rcx, 8191
    ja .sak_big
    mov rdi, rbx
    xor esi, esi
    lea rdx, [sak_buf]
    call fs_read_at
    mov [sak_len], rax
    lea rdx, [sak_buf]
    mov byte [rdx + rax], 0
    call sak_set_args
    call sak_exec
    jmp .done
.sak_usage:
    mov qword [last_status], 1
    lea rdi, [msg_sak_usage]
    call con_puts_utf8
    call con_newline
    jmp .done
.sak_nested:
    mov qword [last_status], 1
    lea rdi, [msg_sak_nested]
    call con_puts_utf8
    call con_newline
    jmp .done
.sak_big:
    mov qword [last_status], 1
    lea rdi, [msg_sak_big]
    call con_puts_utf8
    call con_newline
    jmp .done

.g_usage:
    mov qword [last_status], 1
    lea rdi, [msg_g_usage]
    call con_puts_utf8
    call con_newline
    jmp .done

.do_gcls:
    call gfx_begin
    mov rdi, r12
    mov esi, 1
    call parse_args
    xor ecx, ecx
    test eax, eax
    jz .gcls_go
    mov rdi, [garg]
    call color_of
    mov ecx, eax
.gcls_go:
    mov eax, ecx
    call fill_screen
    call gfx_present
    jmp .done

.do_gpix:
    GARGS 3
    mov rdi, [garg + 16]
    call color_of
    mov r8, [garg]
    mov r9, [garg + 8]
    call pixel
    call gfx_present
    jmp .done

.do_gline:
    GARGS 5
    mov rdi, [garg + 32]
    call color_of
    mov r8, [garg]
    mov r9, [garg + 8]
    mov r10, [garg + 16]
    mov r11, [garg + 24]
    call draw_line
    call gfx_present
    jmp .done

.do_grect:
    GARGS 5
    mov rdi, [garg + 32]
    call color_of
    mov r8, [garg]
    mov r9, [garg + 8]
    mov r10, [garg + 16]
    mov r11, [garg + 24]
    call draw_rect
    call gfx_present
    jmp .done

.do_gfill:
    GARGS 5
    mov rdi, [garg + 32]
    call color_of
    mov r8, [garg]
    mov r9, [garg + 8]
    mov r10, [garg + 16]
    mov r11, [garg + 24]
    call gfx_rect
    call gfx_present
    jmp .done

.do_gcirc:
    GARGS 4
    call gcirc_fn
    call gfx_present
    jmp .done

.do_gdisc:
    GARGS 4
    call gdisc_fn
    call gfx_present
    jmp .done

.do_gtext:
    mov rdi, r12
    mov esi, 3
    call parse_args
    cmp eax, 3
    jb .g_usage
    call skip_spaces
    mov rbx, rdi
    call gfx_begin
    mov rdi, [garg + 16]
    call color_of
    mov r8, [garg]
    mov r9, [garg + 8]
    mov rdi, rbx
    call draw_text
    call gfx_present
    jmp .done

.do_gscale:
    mov rdi, r12
    call skip_spaces
    call parse_int
    mov edi, 1
    cmp rax, 1
    je .gs_set
    cmp rax, 8
    je .gs_set
    mov edi, 2
    cmp rax, 2
    je .gs_set
    cmp rax, 16
    je .gs_set
    mov edi, 4
    cmp rax, 4
    je .gs_set
    cmp rax, 32
    je .gs_set
    jmp .g_usage
.gs_set:
    call gfx_begin
    call font_apply
    jmp .done

.do_gwait:
    call gfx_wait_end
    jmp .done

.do_gend:
    call gfx_end
    jmp .done

.do_gauto:
    mov rdi, r12
    call skip_spaces
    call parse_int
    xor ecx, ecx
    test rax, rax
    jnz .ga_set
    mov ecx, 1
.ga_set:
    mov [gfx_manual], rcx
    jmp .done

.do_gflip:
    cmp qword [gfx_active], 0
    je .done
    call swap_buffers
    jmp .done

.do_gkey:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    call kbd_poll_char
    movzx edi, al
    call i2s
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r14
    call var_set
    jmp .done

.do_md:
    mov rdi, r12
    call skip_spaces
    mov rbx, rdi
    call parse_name
    mov r14, rax
    test r14, r14
    jz .done
    mov rdi, rbx
    mov rsi, r14
    call fs_lookup
    cmp rax, -1
    je .cp_nofile
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .cp_nofile
    cmp qword [rax + INO_TYPE], FT_DIR
    je .cp_isdir
    mov rcx, [rax + INO_SIZE]
    cmp rcx, 8000
    jbe .md_sz
    mov ecx, 8000
.md_sz:
    mov rdi, rax
    xor esi, esi
    lea rdx, [cap_out]
    call fs_read_at
    mov [md_len], rax
    call md_view
    jmp .done

.do_mddemo:
    lea rdi, [s_demomd_name]
    mov esi, 7
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .touch_fail
    mov rdi, rax
    lea rsi, [demo_md_text]
    mov edx, demo_md_end - demo_md_text
    call fs_write
    lea rdi, [msg_created]
    call con_puts_utf8
    lea rdi, [s_demomd_name]
    call con_puts
    call con_newline
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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
    mov dx, 0xCF9
    mov al, 0x06
    out dx, al
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
    lea rdi, [idt + 0x13*16]
    lea rax, [isr_syscall]
    call .set_entry
    lea rdi, [idt + 0x20*16]
    lea rax, [irq_timer]
    call .set_entry
    lea rdi, [idt + 0x21*16]
    lea rax, [irq_keyboard]
    call .set_entry
    lea rdi, [idt + 0x2C*16]
    lea rax, [irq_mouse]
    call .set_entry
    lea rax, [idtr]
    mov word [rax], 256*16 - 1
    lea rbx, [idt]
    mov [rax + 2], rbx
    lidt [rax]
    ret
.set_entry:
    push rax
    mov word [rdi + 0], ax
    shr rax, 16
    mov word [rdi + 6], ax
    shr rax, 16
    mov dword [rdi + 8], eax
    mov word [rdi + 2], 0x08
    mov byte [rdi + 4], 0
    mov byte [rdi + 5], 0x8E
    pop rax
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
    cmp al, 0xE0
    je .ext_prefix
    cmp qword [kbd_ext], 0
    je .normal
    mov qword [kbd_ext], 0
    cmp al, 0x48
    je .arrow_up
    cmp al, 0x50
    je .arrow_down
    cmp al, 0x4B
    je .k_left
    cmp al, 0x4D
    je .k_right
    cmp al, 0x47
    je .k_home
    cmp al, 0x4F
    je .k_end
    cmp al, 0x53
    je .k_del
    cmp al, 0x49
    je .k_pgup
    cmp al, 0x51
    je .k_pgdn
    jmp .release
.normal:
    cmp al, 0x2A
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xAA
    je .shift_off
    cmp al, 0xB6
    je .shift_off
    cmp al, 0x38
    je .alt_on
    cmp al, 0xB8
    je .alt_off
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
    mov ecx, eax
    movzx eax, byte [rbx + rax]
    test al, al
    jz .release
    cmp qword [kbd_shift], 0
    je .emit
    cmp qword [kbd_layout], 0
    jne .shift_ru_tab
    lea rbx, [shift_us]
    jmp .shift_tab
.shift_ru_tab:
    lea rbx, [shift_ru]
.shift_tab:
    movzx eax, byte [rbx + rcx]
    test al, al
    jz .release
    jmp .emit
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
    cmp qword [kbd_alt], 0
    je .release
    cmp qword [alt_toggled], 0
    jne .release
    mov qword [alt_toggled], 1
    xor qword [kbd_layout], 1
    jmp .release
.shift_off:
    mov qword [kbd_shift], 0
    mov qword [alt_toggled], 0
    jmp .release
.alt_on:
    mov qword [kbd_alt], 1
    cmp qword [kbd_shift], 0
    je .release
    cmp qword [alt_toggled], 0
    jne .release
    mov qword [alt_toggled], 1
    xor qword [kbd_layout], 1
    jmp .release
.alt_off:
    mov qword [kbd_alt], 0
    mov qword [alt_toggled], 0
.ext_prefix:
    mov qword [kbd_ext], 1
    jmp .release
.arrow_up:
    mov al, 1
    jmp .emit
.arrow_down:
    mov al, 2
    jmp .emit
.k_left:
    mov al, 3
    jmp .emit
.k_right:
    mov al, 4
    jmp .emit
.k_home:
    mov al, 5
    jmp .emit
.k_end:
    mov al, 6
    jmp .emit
.k_del:
    mov al, 7
    jmp .emit
.k_pgup:
    mov al, 11
    jmp .emit
.k_pgdn:
    mov al, 12
    jmp .emit
.release:
    mov al, 0x20
    out 0x20, al
    pop rcx
    pop rbx
    pop rax
    iretq

isr_syscall:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    sti
    mov r10, rax
    shr r10, 8
    and r10, 0xFF
    cmp r10d, 0x00
    je .sys_pixel
    cmp r10d, 0x01
    je .sys_text
    cmp r10d, 0x02
    je .sys_fill
    cmp r10d, 0x03
    je .sys_fillrect
    cmp r10d, 0x04
    je .sys_line
    cmp r10d, 0x05
    je .sys_rect
    cmp r10d, 0x06
    je .sys_swap
    cmp r10d, 0x07
    je .sys_putc
    cmp r10d, 0x08
    je .sys_puts
    cmp r10d, 0x09
    je .sys_putu
    cmp r10d, 0x0A
    je .sys_nl
    cmp r10d, 0x0B
    je .sys_clear
    cmp r10d, 0x0C
    je .sys_gotoxy
    cmp r10d, 0x0D
    je .sys_getc
    cmp r10d, 0x0E
    je .sys_getc_nb
    cmp r10d, 0x0F
    je .sys_delay
    cmp r10d, 0x10
    je .sys_ticks
    cmp r10d, 0x11
    je .sys_fs_open
    cmp r10d, 0x12
    je .sys_fs_read
    cmp r10d, 0x13
    je .sys_fs_write
    cmp r10d, 0x14
    je .sys_fs_close
    cmp r10d, 0x15
    je .sys_fs_seek
    cmp r10d, 0x16
    je .sys_fs_create
    cmp r10d, 0x17
    je .sys_fs_delete
    cmp r10d, 0x18
    je .sys_exit
    cmp r10d, 0x19
    je .sys_get_screen
    cmp r10d, 0x1A
    je .sys_font
    cmp r10d, 0x1B
    je .sys_rand
    jmp .sys_done
.sys_pixel:
    mov eax, ebx
    mov r8, rcx
    mov r9, rdx
    call pixel
    jmp .sys_done
.sys_text:
    mov eax, ebx
    mov r8, rcx
    mov r9, rdx
    mov rdi, rsi
    call draw_text
    jmp .sys_done
.sys_fill:
    mov eax, ebx
    call fill_screen
    jmp .sys_done
.sys_fillrect:
    mov eax, ebx
    mov r8, rcx
    mov r9, rdx
    mov r10, rsi
    mov r11, rdi
    call fill_rect
    jmp .sys_done
.sys_line:
    mov eax, ebx
    mov r8, rcx
    mov r9, rdx
    mov r10, rsi
    mov r11, rdi
    call draw_line
    jmp .sys_done
.sys_rect:
    mov eax, ebx
    mov r8, rcx
    mov r9, rdx
    mov r10, rsi
    mov r11, rdi
    call draw_rect
    jmp .sys_done
.sys_swap:
    call swap_buffers
    jmp .sys_done
.sys_putc:
    movzx edi, bl
    call con_putc
    jmp .sys_done
.sys_puts:
    mov rdi, rsi
    call con_puts_utf8
    jmp .sys_done
.sys_putu:
    mov rdi, rbx
    movzx esi, al
    call con_putu
    jmp .sys_done
.sys_nl:
    call con_newline
    jmp .sys_done
.sys_clear:
    call con_clear
    jmp .sys_done
.sys_gotoxy:
    mov rdi, rcx
    mov rsi, rdx
    call con_gotoxy
    jmp .sys_done
.sys_getc:
    call kbd_getchar
    movzx eax, al
    jmp .sys_done
.sys_getc_nb:
    call kbd_poll_char
    movzx eax, al
    jmp .sys_done
.sys_delay:
    mov rdi, rbx
    call delay_ms
    jmp .sys_done
.sys_ticks:
    call get_ticks
    jmp .sys_done
.sys_fs_open:
    mov rdi, rsi
    call strlen
    mov rdi, rsi
    mov rsi, rax
    call fs_lookup
    cmp rax, -1
    je .sys_fs_err
    mov rdi, rax
    call fs_open
    jmp .sys_done
.sys_fs_read:
    mov rdi, rbx
    mov rsi, rcx
    call fs_read
    jmp .sys_done
.sys_fs_write:
    mov rdi, rbx
    mov rsi, rcx
    call fs_write
    jmp .sys_done
.sys_fs_close:
    mov rdi, rbx
    call fs_close
    jmp .sys_done
.sys_fs_seek:
    mov rdi, rbx
    mov rsi, rcx
    call fs_seek
    jmp .sys_done
.sys_fs_create:
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rdi, rsi
    mov rsi, rdx
    mov edx, FT_SF_DATA
    call fs_create
    jmp .sys_done
.sys_fs_delete:
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rdi, rsi
    mov rsi, rdx
    call fs_delete
    jmp .sys_done
.sys_fs_err:
    mov rax, -1
    jmp .sys_done
.sys_get_screen:
    mov rax, [height]
    mov [rsp + 104], rax
    mov rax, [pitch]
    mov [rsp + 96], rax
    mov rax, [width]
    jmp .sys_done
.sys_font:
    mov rdi, rbx
    call font_apply
    jmp .sys_done
.sys_rand:
    call rand_next
    jmp .sys_done
.sys_exit:
    cli
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    iretq
.sys_done:
    cli
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    iretq

ata_wait_bsy:
    push rcx
    push rdx
    mov dx, 0x177
    mov rcx, 0x100000
.poll:
    in al, dx
    cmp al, 0xFF
    je .fail
    test al, 0x80
    jz .ready
    dec rcx
    jnz .poll
.fail:
    mov rax, -1
    jmp .done
.ready:
    xor eax, eax
.done:
    pop rdx
    pop rcx
    ret

ata_wait_drq:
    push rcx
    push rdx
    mov dx, 0x177
    mov rcx, 0x1000000
.poll:
    in al, dx
    cmp al, 0xFF
    je .fail
    test al, 0x80
    jnz .next
    test al, 0x08
    jnz .ready
.next:
    dec rcx
    jnz .poll
.fail:
    mov rax, -1
    jmp .done
.ready:
    xor eax, eax
.done:
    pop rdx
    pop rcx
    ret

ata_read_sector:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call ata_wait_bsy
    test rax, rax
    jnz .err
    mov rax, r12
    shr rax, 24
    and al, 0x0F
    or al, 0xE0
    mov dx, 0x176
    out dx, al
    mov dx, 0x172
    mov al, 1
    out dx, al
    mov rax, r12
    mov dx, 0x173
    out dx, al
    shr rax, 8
    mov dx, 0x174
    out dx, al
    shr rax, 8
    mov dx, 0x175
    out dx, al
    mov dx, 0x177
    mov al, 0x20
    out dx, al
    call ata_wait_drq
    test rax, rax
    jnz .err
    mov rdi, r13
    mov dx, 0x170
    mov rcx, 256
    cld
    rep insw
    xor eax, eax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ata_write_sector:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call ata_wait_bsy
    test rax, rax
    jnz .err
    mov rax, r12
    shr rax, 24
    and al, 0x0F
    or al, 0xE0
    mov dx, 0x176
    out dx, al
    mov dx, 0x172
    mov al, 1
    out dx, al
    mov rax, r12
    mov dx, 0x173
    out dx, al
    shr rax, 8
    mov dx, 0x174
    out dx, al
    shr rax, 8
    mov dx, 0x175
    out dx, al
    mov dx, 0x177
    mov al, 0x30
    out dx, al
    call ata_wait_drq
    test rax, rax
    jnz .err
    mov rsi, r13
    mov dx, 0x170
    mov rcx, 256
    cld
    rep outsw
    xor eax, eax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ata_flush:
    push rcx
    push rdx
    mov dx, 0x177
    mov al, 0xE7
    out dx, al
    mov rcx, 0x1000000
.w:
    in al, dx
    test al, 0x80
    jz .done
    dec rcx
    jnz .w
.done:
    pop rdx
    pop rcx
    ret

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
    push r15
    cmp r10d, 32
    jb .done
    sub r10d, 32
    shl r10d, 3
    lea rsi, [font8x8]
    add rsi, r10
    mov r12d, eax
    mov r13d, r8d
    mov ebx, r9d
    mov r15, [font_scale]
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
    mov eax, edi
    imul eax, r15d
    lea r8d, [r13d + eax]
    mov eax, ecx
    imul eax, r15d
    lea r9d, [ebx + eax]
    mov r10, r15
    mov r11, r15
    mov eax, r12d
    call gfx_rect
.skip:
    shl dl, 1
    inc edi
    jmp .col
.next_row:
    inc ecx
    jmp .row
.done:
    pop r15
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
    add r12d, dword [font_adv]
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
    cmp qword [cap_on], 0
    je .norm
    mov rbx, [cap_len]
    cmp rbx, 4095
    jae .done
    lea rdx, [cap_buf]
    mov [rdx + rbx], dil
    inc qword [cap_len]
    jmp .done
.norm:
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
    jne .bs_ok
    cmp qword [con_cur_y], 0
    je .done
    dec qword [con_cur_y]
    mov rax, [con_cols]
    mov [con_cur_x], rax
.bs_ok:
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
    cmp qword [gfx_active], 0
    je .go
    mov qword [con_dirty], 0
    ret
.go:
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
    imul r8d, dword [font_adv]
    mov r9d, r14d
    imul r9d, dword [font_adv]
    mov eax, [con_fg]
    call draw_char
.skip:
    inc r15d
    jmp .col
.nr:
    inc r14d
    jmp .row
.done:
    mov r8, [con_cur_x]
    imul r8, [font_adv]
    mov r9, [con_cur_y]
    imul r9, [font_adv]
    mov r10, [font_adv]
    mov r11, [font_scale]
    shl r11, 1
    add r9, r10
    sub r9, r11
    mov eax, [con_fg]
    call gfx_rect
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
    jmp .wait
.done:
    pop rbx
    ret

fs_init:
    call fs_load
    cmp qword [fs_super + SB_MAGIC], FS_MAGIC
    jne .format
    cmp qword [fs_super + SB_VER], FS_VERSION
    jne .format
    mov qword [fs_dirty], 0
    ret
.format:
    call fs_format
    call fs_save
    mov qword [fs_dirty], 0
    ret

fs_save:
    push rbx
    push r12
    push r13
    lea rsi, [fs_super]
    mov rdi, FS_DISK_SUPER_LBA
    call ata_write_sector
    test rax, rax
    jnz .err
    lea rsi, [fs_bitmap]
    mov rdi, FS_DISK_BITMAP_LBA
    call ata_write_sector
    test rax, rax
    jnz .err
    lea rsi, [fs_bitmap + 512]
    mov rdi, FS_DISK_BITMAP_LBA + 1
    call ata_write_sector
    test rax, rax
    jnz .err
    xor r12, r12
.inode_loop:
    cmp r12, 16
    jae .data_start
    mov rbx, r12
    shl rbx, 9
    lea rsi, [fs_inodes + rbx]
    mov rdi, FS_DISK_INODES_LBA
    add rdi, r12
    call ata_write_sector
    test rax, rax
    jnz .err
    inc r12
    jmp .inode_loop
.data_start:
    xor r12, r12
.block_loop:
    cmp r12, FS_TOTAL_BLOCKS
    jae .flush
    mov rdi, r12
    call fs_test_bit
    test al, al
    jz .next_block
    xor r13, r13
.sector_loop:
    cmp r13, 8
    jae .next_block
    mov rsi, r12
    shl rsi, 12
    add rsi, FS_DATA_START
    mov rax, r13
    shl rax, 9
    add rsi, rax
    mov rdi, r12
    shl rdi, 3
    add rdi, FS_DISK_DATA_LBA
    add rdi, r13
    call ata_write_sector
    test rax, rax
    jnz .err
    inc r13
    jmp .sector_loop
.next_block:
    inc r12
    jmp .block_loop
.flush:
    call ata_flush
    mov qword [fs_dirty], 0
    xor eax, eax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

fs_load:
    push rbx
    push r12
    push r13
    lea rsi, [fs_super]
    mov rdi, FS_DISK_SUPER_LBA
    call ata_read_sector
    test rax, rax
    jnz .err
    cmp qword [fs_super + SB_MAGIC], FS_MAGIC
    jne .err
    cmp qword [fs_super + SB_VER], FS_VERSION
    jne .err
    lea rsi, [fs_bitmap]
    mov rdi, FS_DISK_BITMAP_LBA
    call ata_read_sector
    test rax, rax
    jnz .err
    lea rsi, [fs_bitmap + 512]
    mov rdi, FS_DISK_BITMAP_LBA + 1
    call ata_read_sector
    test rax, rax
    jnz .err
    xor r12, r12
.inode_loop:
    cmp r12, 16
    jae .data_start
    mov rbx, r12
    shl rbx, 9
    lea rsi, [fs_inodes + rbx]
    mov rdi, FS_DISK_INODES_LBA
    add rdi, r12
    call ata_read_sector
    test rax, rax
    jnz .err
    inc r12
    jmp .inode_loop
.data_start:
    xor r12, r12
.block_loop:
    cmp r12, FS_TOTAL_BLOCKS
    jae .ok
    mov rdi, r12
    call fs_test_bit
    test al, al
    jz .next_block
    xor r13, r13
.sector_loop:
    cmp r13, 8
    jae .next_block
    mov rsi, r12
    shl rsi, 12
    add rsi, FS_DATA_START
    mov rax, r13
    shl rax, 9
    add rsi, rax
    mov rdi, r12
    shl rdi, 3
    add rdi, FS_DISK_DATA_LBA
    add rdi, r13
    call ata_read_sector
    test rax, rax
    jnz .err
    inc r13
    jmp .sector_loop
.next_block:
    inc r12
    jmp .block_loop
.ok:
    xor eax, eax
    jmp .done
.err:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

fs_format:
    push rdi
    push rcx
    push rax
    mov qword [fs_cwd], 0
    lea rdi, [fs_super]
    mov qword [rdi + SB_MAGIC], FS_MAGIC
    mov qword [rdi + SB_VER], FS_VERSION
    mov qword [rdi + SB_USED], 0
    mov qword [rdi + SB_USEDBLK], 0
    mov qword [rdi + SB_MAXFILES], FS_MAX_FILES
    mov qword [rdi + SB_DSTART], FS_DATA_START
    mov qword [rdi + SB_DEND], FS_DATA_END
    mov qword [rdi + SB_BLKSZ], FS_BLOCK_SIZE
    lea rdi, [fs_inodes]
    mov rcx, FS_INODE_SIZE * FS_MAX_FILES / 8
    xor rax, rax
    cld
    rep stosq
    lea rdi, [fs_bitmap]
    mov rcx, FS_BITMAP_SIZE / 8
    rep stosq
    pop rax
    pop rcx
    pop rdi
    ret

fs_test_bit:
    push rbx
    push rcx
    mov rbx, rdi
    shr rbx, 3
    mov rcx, rdi
    and rcx, 7
    lea rdx, [fs_bitmap]
    mov al, [rdx + rbx]
    shr al, cl
    and al, 1
    pop rcx
    pop rbx
    ret

fs_set_bit:
    push rbx
    push rcx
    push rdx
    mov rbx, rdi
    shr rbx, 3
    mov rcx, rdi
    and rcx, 7
    mov dl, 1
    shl dl, cl
    lea rax, [fs_bitmap]
    or [rax + rbx], dl
    pop rdx
    pop rcx
    pop rbx
    ret

fs_clear_bit:
    push rbx
    push rcx
    push rdx
    mov rbx, rdi
    shr rbx, 3
    mov rcx, rdi
    and rcx, 7
    mov dl, 1
    shl dl, cl
    not dl
    lea rax, [fs_bitmap]
    and [rax + rbx], dl
    pop rdx
    pop rcx
    pop rbx
    ret

fs_alloc_blocks:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    mov r8, rdi
    test r8, r8
    jz .fail
    xor r9, r9
.find_start:
    mov rax, r9
    add rax, r8
    cmp rax, FS_TOTAL_BLOCKS
    ja .fail
    xor r10, r10
.check:
    cmp r10, r8
    jae .found
    mov rdi, r9
    add rdi, r10
    call fs_test_bit
    test al, al
    jnz .next_start
    inc r10
    jmp .check
.found:
    xor r10, r10
.mark:
    cmp r10, r8
    jae .done
    mov rdi, r9
    add rdi, r10
    call fs_set_bit
    inc r10
    jmp .mark
.next_start:
    inc r9
    jmp .find_start
.fail:
    mov rax, -1
    jmp .out
.done:
    mov rax, r9
    add [fs_super + SB_USEDBLK], r8
.out:
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

fs_free_blocks:
    push rbx
    push rcx
    push rdi
    push rsi
    mov rbx, rdi
    mov rcx, rsi
    test rcx, rcx
    jz .done
.l:
    mov rdi, rbx
    call fs_clear_bit
    inc rbx
    dec rcx
    jnz .l
    sub [fs_super + SB_USEDBLK], rsi
.done:
    pop rsi
    pop rdi
    pop rcx
    pop rbx
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
    cmp qword [rbx + INO_USED], 0
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
    xor r11, r11
.loop:
    cmp r11, FS_MAX_FILES
    jae .fail
    imul rax, r11, FS_INODE_SIZE
    lea rdi, [fs_inodes]
    add rdi, rax
    cmp qword [rdi + INO_USED], 0
    je .next
    mov rcx, [rdi + INO_RESERVED]
    cmp rcx, [fs_cwd]
    jne .next
    mov rcx, [rdi + INO_NAMELEN]
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
    test r13, r13
    jz .fail
    cmp r13, FS_NAME_MAX
    ja .fail
    mov rax, [fs_super + SB_USED]
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
    mov qword [rbx + INO_USED], 1
    mov [rbx + INO_NAMELEN], r13
    mov qword [rbx + INO_SIZE], 0
    mov [rbx + INO_TYPE], r14
    mov qword [rbx + INO_FIRSTBLK], 0
    mov qword [rbx + INO_BLKCOUNT], 0
    mov rax, [fs_cwd]
    mov [rbx + INO_RESERVED], rax
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
    mov [rbx + INO_CHECKSUM], rax
    inc qword [fs_super + SB_USED]
    mov qword [fs_dirty], 1
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
    cmp rdi, FS_MAX_FILES
    jae .fail
    imul rdx, rdi, 4
    lea rcx, [fs_fd_pos]
    mov dword [rcx + rdx], 0
    mov rax, rdi
    ret
.fail:
    mov rax, -1
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

fs_read_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rax, [r12 + INO_SIZE]
    sub rax, r13
    jbe .eof
    cmp rax, r15
    jbe .have
    mov rax, r15
.have:
    mov r8, rax
    mov rax, r13
    xor rdx, rdx
    mov rcx, FS_BLOCK_SIZE
    div rcx
    mov r9, [r12 + INO_FIRSTBLK]
    add r9, rax
    shl r9, 12
    add r9, FS_DATA_START
    add r9, rdx
    mov rdi, r14
    mov rsi, r9
    mov rcx, r8
    cld
    rep movsb
    mov rax, r8
    jmp .done
.eof:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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
    cmp qword [rbx + INO_USED], 0
    je .fail
    imul rdx, r14, 4
    lea rcx, [fs_fd_pos]
    mov r15d, [rcx + rdx]
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    call fs_read_at
    test rax, rax
    jz .done
    add r15, rax
    imul rdx, r14, 4
    lea rcx, [fs_fd_pos]
    mov [rcx + rdx], r15d
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
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r12, FS_MAX_FILES
    jae .fail
    mov rdi, r12
    call fs_get_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp qword [rbx + INO_USED], 0
    je .fail
    cmp qword [rbx + INO_TYPE], FT_DIR
    je .fail
    mov rax, r14
    add rax, FS_BLOCK_SIZE - 1
    xor rdx, rdx
    mov rcx, FS_BLOCK_SIZE
    div rcx
    mov r15, rax
    test r15, r15
    jnz .need_alloc
    mov rdi, [rbx + INO_FIRSTBLK]
    mov rsi, [rbx + INO_BLKCOUNT]
    test rsi, rsi
    jz .zero_done
    call fs_free_blocks
.zero_done:
    mov qword [rbx + INO_FIRSTBLK], 0
    mov qword [rbx + INO_BLKCOUNT], 0
    mov qword [rbx + INO_SIZE], 0
    mov qword [fs_dirty], 1
    xor eax, eax
    jmp .done
.need_alloc:
    cmp r15, [rbx + INO_BLKCOUNT]
    ja .realloc
    cmp qword [rbx + INO_FIRSTBLK], 0
    je .realloc
    mov r8, [rbx + INO_FIRSTBLK]
    jmp .copy
.realloc:
    mov rdi, r15
    call fs_alloc_blocks
    cmp rax, -1
    je .fail
    mov r8, rax
    push qword [rbx + INO_FIRSTBLK]
    push qword [rbx + INO_BLKCOUNT]
    mov [rbx + INO_FIRSTBLK], r8
    mov [rbx + INO_BLKCOUNT], r15
    mov rdi, r8
    shl rdi, 12
    add rdi, FS_DATA_START
    mov rsi, r13
    mov rcx, r14
    cld
    rep movsb
    pop rsi
    pop rdi
    test rsi, rsi
    jz .realloc_done
    call fs_free_blocks
.realloc_done:
    mov [rbx + INO_SIZE], r14
    mov qword [fs_dirty], 1
    mov rax, r14
    jmp .done
.copy:
    mov rdi, r8
    shl rdi, 12
    add rdi, FS_DATA_START
    mov rsi, r13
    mov rcx, r14
    cld
    rep movsb
    mov [rbx + INO_SIZE], r14
    mov qword [fs_dirty], 1
    mov rax, r14
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
    call fs_lookup
    cmp rax, -1
    je .fail
    mov r12, rax
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp qword [rbx + INO_TYPE], FT_DIR
    jne .not_dir
    lea rdi, [r12 + 1]
    call fs_dir_has_children
    test rax, rax
    jnz .notempty
.not_dir:
    mov rdi, [rbx + INO_FIRSTBLK]
    mov rsi, [rbx + INO_BLKCOUNT]
    test rsi, rsi
    jz .no_blocks
    call fs_free_blocks
.no_blocks:
    mov qword [rbx + INO_USED], 0
    mov qword [rbx + INO_FIRSTBLK], 0
    mov qword [rbx + INO_BLKCOUNT], 0
    mov qword [rbx + INO_SIZE], 0
    dec qword [fs_super + SB_USED]
    mov qword [fs_dirty], 1
    xor eax, eax
    jmp .done
.notempty:
    mov rax, -2
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
    cmp qword [rbx + INO_USED], 0
    je .next
    mov rax, [rbx + INO_RESERVED]
    cmp rax, [fs_cwd]
    jne .next
    mov rcx, [rbx + INO_NAMELEN]
    mov rax, r14
    add rax, rcx
    add rax, 3
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
    cmp qword [rbx + INO_TYPE], FT_DIR
    jne .nl
    mov byte [r12 + r14], '/'
    inc r14
.nl:
    mov byte [r12 + r14], 10
    inc r14
.next:
    inc r15
    jmp .loop
.done:
    mov byte [r12 + r14], 0
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_dir_has_children:
    xor eax, eax
    lea rdx, [fs_inodes]
    xor ecx, ecx
.l:
    cmp ecx, FS_MAX_FILES
    jae .r
    cmp qword [rdx + INO_USED], 0
    je .n
    cmp [rdx + INO_RESERVED], rdi
    jne .n
    mov eax, 1
    ret
.n:
    add rdx, FS_INODE_SIZE
    inc ecx
    jmp .l
.r:
    ret

parse_int:
    xor eax, eax
    xor ecx, ecx
    cmp byte [rdi], '-'
    jne .digits
    mov ecx, 1
    inc rdi
.digits:
    movzx edx, byte [rdi]
    sub edx, '0'
    cmp edx, 9
    ja .end
    imul rax, rax, 10
    add rax, rdx
    inc rdi
    jmp .digits
.end:
    test ecx, ecx
    jz .ret
    neg rax
.ret:
    ret

put_int:
    test rdi, rdi
    jns .p
    push rdi
    mov edi, '-'
    call con_putc
    pop rdi
    neg rdi
.p:
    mov esi, 10
    jmp con_putu

put2:
    mov eax, edi
    xor edx, edx
    mov ecx, 10
    div ecx
    push rdx
    lea edi, [rax + '0']
    call con_putc
    pop rdi
    add edi, '0'
    jmp con_putc

rtc_wait:
.u:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jnz .u
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    test al, 4
    setnz al
    movzx eax, al
    mov [rtc_bin], rax
    ret

cmos_get:
    push rcx
    mov al, dil
    out 0x70, al
    in al, 0x71
    movzx eax, al
    cmp qword [rtc_bin], 0
    jne .d
    mov ecx, eax
    shr ecx, 4
    imul ecx, ecx, 10
    and eax, 0x0F
    add eax, ecx
.d:
    pop rcx
    ret

rand_next:
    mov rax, [rand_state]
    mov rdx, rax
    shl rdx, 13
    xor rax, rdx
    mov rdx, rax
    shr rdx, 7
    xor rax, rdx
    mov rdx, rax
    shl rdx, 17
    xor rax, rdx
    mov [rand_state], rax
    ret

font_apply:
    mov [font_scale], rdi
    lea rax, [rdi*8]
    mov [font_adv], rax
    ret

con_set_scale:
    call font_apply
    mov rax, [width]
    xor edx, edx
    div qword [font_adv]
    mov [con_cols], rax
    mov rax, [height]
    xor edx, edx
    div qword [font_adv]
    mov [con_rows], rax
    call con_clear
    ret

build_path:
    push rbx
    push r12
    lea rbx, [path_buf + 255]
    mov byte [rbx], 0
    mov r12, [fs_cwd]
.l:
    test r12, r12
    jz .done
    lea rax, [path_buf + 40]
    cmp rbx, rax
    jb .done
    lea rdi, [r12 - 1]
    call fs_get_inode
    mov rcx, [rax + INO_NAMELEN]
    sub rbx, rcx
    lea rsi, [rax + FS_INODE_HDR]
    mov rdi, rbx
    push rax
    cld
    rep movsb
    pop rax
    dec rbx
    mov byte [rbx], '/'
    mov r12, [rax + INO_RESERVED]
    jmp .l
.done:
    cmp byte [rbx], 0
    jne .r
    dec rbx
    mov byte [rbx], '/'
.r:
    mov rax, rbx
    pop r12
    pop rbx
    ret

print_prompt:
    call build_path
    mov rdi, rax
    call con_puts
    lea rdi, [prompt_str]
    jmp con_puts_utf8

cd_path:
    push rbx
    push r12
    push r13
    mov r13, [fs_cwd]
    mov rbx, rdi
    cmp byte [rbx], '/'
    jne .loop
    mov qword [fs_cwd], 0
    inc rbx
.loop:
    cmp byte [rbx], '/'
    jne .comp
    inc rbx
    jmp .loop
.comp:
    mov al, [rbx]
    test al, al
    jz .ok
    cmp al, ' '
    je .ok
    xor r12d, r12d
.len:
    mov al, [rbx + r12]
    test al, al
    jz .have
    cmp al, '/'
    je .have
    cmp al, ' '
    je .have
    inc r12
    jmp .len
.have:
    cmp r12, 2
    jne .dot
    cmp word [rbx], 0x2E2E
    jne .lookup
    mov rax, [fs_cwd]
    test rax, rax
    jz .adv
    lea rdi, [rax - 1]
    call fs_get_inode
    mov rax, [rax + INO_RESERVED]
    mov [fs_cwd], rax
    jmp .adv
.dot:
    cmp r12, 1
    jne .lookup
    cmp byte [rbx], '.'
    je .adv
.lookup:
    mov rdi, rbx
    mov rsi, r12
    call fs_lookup
    cmp rax, -1
    je .fail
    push rax
    mov rdi, rax
    call fs_get_inode
    cmp qword [rax + INO_TYPE], FT_DIR
    pop rcx
    jne .fail
    inc rcx
    mov [fs_cwd], rcx
.adv:
    add rbx, r12
    jmp .loop
.ok:
    xor eax, eax
    jmp .r
.fail:
    mov [fs_cwd], r13
    mov rax, -1
.r:
    pop r13
    pop r12
    pop rbx
    ret

get_token:
    push rcx
.sk:
    cmp byte [rsi], ' '
    jne .go
    inc rsi
    jmp .sk
.go:
    xor ecx, ecx
.cp:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, ' '
    je .end
    cmp al, 10
    je .end
    cmp al, 13
    je .end
    cmp ecx, 47
    jae .skipc
    mov [rdi + rcx], al
    inc ecx
.skipc:
    inc rsi
    jmp .cp
.end:
    mov byte [rdi + rcx], 0
    mov eax, ecx
    pop rcx
    ret

is_namech:
    cmp al, '_'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    jbe .y
    cmp al, 'a'
    jb .n
    cmp al, 'z'
    jbe .y
.n:
    xor eax, eax
    ret
.y:
    mov eax, 1
    ret

is_num:
    xor eax, eax
    cmp byte [rdi], '-'
    jne .d
    inc rdi
.d:
    cmp byte [rdi], 0
    je .no
.l:
    movzx edx, byte [rdi]
    test edx, edx
    jz .yes
    sub edx, '0'
    cmp edx, 9
    ja .no
    inc rdi
    jmp .l
.yes:
    mov eax, 1
.no:
    ret

truthy:
    xor eax, eax
    cmp byte [rdi], 0
    je .r
    cmp byte [rdi], '0'
    jne .y
    cmp byte [rdi + 1], 0
    jne .y
    ret
.y:
    mov eax, 1
.r:
    ret

op_id:
    push rbx
    lea rbx, [op_tab]
.l:
    mov rsi, [rbx]
    test rsi, rsi
    jz .none
    lea rdi, [tok_op]
    call strcmp
    test eax, eax
    jz .found
    add rbx, 16
    jmp .l
.found:
    mov rax, [rbx + 8]
    jmp .r
.none:
    xor eax, eax
.r:
    pop rbx
    ret

compare_toks:
    push rbx
    push r12
    mov r12d, edi
    lea rdi, [tok_a]
    call is_num
    test eax, eax
    jz .str
    lea rdi, [tok_b]
    call is_num
    test eax, eax
    jz .str
    lea rdi, [tok_a]
    call parse_int
    mov rbx, rax
    lea rdi, [tok_b]
    call parse_int
    xor ecx, ecx
    cmp rbx, rax
    je .d
    mov ecx, 1
    jg .d
    mov rcx, -1
    jmp .d
.str:
    lea rdi, [tok_a]
    lea rsi, [tok_b]
    call strcmp
    movsxd rcx, eax
    test rcx, rcx
    jz .d
    js .neg
    mov ecx, 1
    jmp .d
.neg:
    mov rcx, -1
.d:
    xor eax, eax
    cmp r12d, 1
    je .o1
    cmp r12d, 2
    je .o2
    cmp r12d, 3
    je .o3
    cmp r12d, 4
    je .o4
    cmp r12d, 5
    je .o5
    test rcx, rcx
    setge al
    jmp .r
.o1:
    test rcx, rcx
    sete al
    jmp .r
.o2:
    test rcx, rcx
    setne al
    jmp .r
.o3:
    test rcx, rcx
    setl al
    jmp .r
.o4:
    test rcx, rcx
    setg al
    jmp .r
.o5:
    test rcx, rcx
    setle al
.r:
    pop r12
    pop rbx
    ret

eval_term:
    push rbx
    push r12
    xor r12d, r12d
    mov rsi, [cond_ptr]
    lea rdi, [tok_a]
    call get_token
    mov [cond_ptr], rsi
    test eax, eax
    jz .empty
    TOKIS tok_a, kw_not
    jnz .chk_ex
    mov r12d, 1
    mov rsi, [cond_ptr]
    lea rdi, [tok_a]
    call get_token
    mov [cond_ptr], rsi
.chk_ex:
    TOKIS tok_a, kw_exists
    jnz .cmp
    mov rsi, [cond_ptr]
    lea rdi, [tok_b]
    call get_token
    mov [cond_ptr], rsi
    lea rdi, [tok_b]
    call strlen
    lea rdi, [tok_b]
    mov rsi, rax
    call fs_lookup
    xor ebx, ebx
    cmp rax, -1
    je .got
    mov ebx, 1
    jmp .got
.cmp:
    mov rsi, [cond_ptr]
    lea rdi, [tok_op]
    call get_token
    mov [tmp_ptr], rsi
    test eax, eax
    jz .single
    call op_id
    test eax, eax
    jz .single
    mov ebx, eax
    mov rsi, [tmp_ptr]
    lea rdi, [tok_b]
    call get_token
    mov [cond_ptr], rsi
    mov edi, ebx
    call compare_toks
    mov ebx, eax
    jmp .got
.single:
    lea rdi, [tok_a]
    call truthy
    mov ebx, eax
    jmp .got
.empty:
    xor ebx, ebx
.got:
    mov eax, ebx
    xor eax, r12d
    pop r12
    pop rbx
    ret

peek_logic:
    mov rsi, [cond_ptr]
    lea rdi, [tok_op]
    call get_token
    mov [tmp_ptr], rsi
    test eax, eax
    jz .none
    TOKIS tok_op, kw_and
    jz .and
    TOKIS tok_op, kw_and2
    jz .and
    TOKIS tok_op, kw_or
    jz .or
    TOKIS tok_op, kw_or2
    jz .or
.none:
    xor eax, eax
    ret
.and:
    mov rax, [tmp_ptr]
    mov [cond_ptr], rax
    mov eax, 1
    ret
.or:
    mov rax, [tmp_ptr]
    mov [cond_ptr], rax
    mov eax, 2
    ret

eval_cond:
    push r12
    push r13
    mov [cond_ptr], rdi
    call eval_term
    mov r12, rax
.more:
    call peek_logic
    test eax, eax
    jz .done
    mov r13, rax
    call eval_term
    cmp r13, 1
    jne .or
    and r12, rax
    jmp .more
.or:
    or r12, rax
    jmp .more
.done:
    mov rax, r12
    pop r13
    pop r12
    ret

var_find:
    push rbx
    push rcx
    push r8
    cmp rsi, 15
    ja .no
    lea rbx, [var_tab]
    xor r8d, r8d
.l:
    cmp r8d, 32
    jae .no
    cmp byte [rbx], 0
    je .next
    xor ecx, ecx
.c:
    cmp rcx, rsi
    jae .endname
    mov al, [rbx + rcx]
    cmp al, [rdi + rcx]
    jne .next
    inc rcx
    jmp .c
.endname:
    cmp byte [rbx + rcx], 0
    jne .next
    mov rax, rbx
    jmp .r
.next:
    add rbx, 64
    inc r8d
    jmp .l
.no:
    xor eax, eax
.r:
    pop r8
    pop rcx
    pop rbx
    ret

var_set:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test rsi, rsi
    jz .r
    cmp rsi, 15
    ja .r
    call var_find
    test rax, rax
    jnz .have
    lea rbx, [var_tab]
    xor ecx, ecx
.f:
    cmp ecx, 32
    jae .r
    cmp byte [rbx], 0
    je .alloc
    add rbx, 64
    inc ecx
    jmp .f
.alloc:
    mov rdi, rbx
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    mov byte [rdi], 0
    mov rax, rbx
.have:
    lea rdi, [rax + 16]
    mov rsi, r14
    xor ecx, ecx
.v:
    mov dl, [rsi + rcx]
    mov [rdi + rcx], dl
    test dl, dl
    jz .r
    inc ecx
    cmp ecx, 47
    jb .v
    mov byte [rdi + rcx], 0
.r:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

vars_list:
    push rbx
    push r12
    lea rbx, [var_tab]
    xor r12d, r12d
.l:
    cmp r12d, 32
    jae .r
    cmp byte [rbx], 0
    je .n
    mov rdi, rbx
    call con_puts
    mov edi, '='
    call con_putc
    lea rdi, [rbx + 16]
    call con_puts
    call con_newline
.n:
    add rbx, 64
    inc r12d
    jmp .l
.r:
    pop r12
    pop rbx
    ret

expand_vars:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    lea r13, [rdi + rdx - 1]
.l:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, '$'
    je .var
.put:
    cmp r12, r13
    jae .skipput
    mov [r12], al
    inc r12
.skipput:
    inc rsi
    jmp .l
.var:
    cmp byte [rsi + 1], '?'
    jne .var_name
    mov rdi, [last_status]
    call u2s
    mov rbx, rax
    lea r14, [rsi + 2]
    jmp .copyval
.var_name:
    lea rbx, [rsi + 1]
    xor ecx, ecx
.n:
    mov al, [rbx + rcx]
    call is_namech
    test eax, eax
    jz .nend
    inc ecx
    cmp ecx, 15
    jb .n
.nend:
    test ecx, ecx
    jnz .look
    mov al, '$'
    jmp .put
.look:
    lea r14, [rbx + rcx]
    mov r15, rcx
    mov rdi, rbx
    mov rsi, r15
    call var_find
    test rax, rax
    jz .spec
    lea rbx, [rax + 16]
    jmp .copyval
.spec:
    cmp r15, 6
    jne .spec2
    mov rdi, rbx
    lea rsi, [kw_random]
    mov edx, 6
    call memcmp
    test eax, eax
    jnz .spec2
    call rand_next
    xor edx, edx
    mov ecx, 1000
    div rcx
    mov rdi, rdx
    call u2s
    mov rbx, rax
    jmp .copyval
.spec2:
    cmp r15, 5
    jne .empty
    mov rdi, rbx
    lea rsi, [kw_ticks]
    mov edx, 5
    call memcmp
    test eax, eax
    jnz .empty
    mov rdi, [ticks]
    call u2s
    mov rbx, rax
    jmp .copyval
.empty:
    lea rbx, [empty_str]
.copyval:
    mov al, [rbx]
    test al, al
    jz .after
    cmp r12, r13
    jae .after
    mov [r12], al
    inc r12
    inc rbx
    jmp .copyval
.after:
    mov rsi, r14
    jmp .l
.end:
    mov byte [r12], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

wait_key:
.w:
    call kbd_poll_char
    test al, al
    jnz .r
    cmp qword [con_dirty], 0
    je .i
    call con_flush
.i:
    hlt
    jmp .w
.r:
    ret

read_line:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.w:
    call wait_key
    cmp al, 10
    je .enter
    cmp al, 8
    je .bs
    cmp al, 32
    jb .w
    cmp rbx, r13
    jae .w
    mov [r12 + rbx], al
    inc rbx
    movzx edi, al
    call con_putc
    jmp .w
.bs:
    test rbx, rbx
    jz .w
    dec rbx
    mov edi, 8
    call con_putc
    jmp .w
.enter:
    mov byte [r12 + rbx], 0
    call con_newline
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

shell_run_one:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rsi, rdi
    lea rdi, [exp_buf]
    mov edx, 512
    call expand_vars
    lea r12, [exp_buf]
    xor r13d, r13d
    mov rbx, r12
.scan:
    mov al, [rbx]
    test al, al
    jz .exec
    cmp al, '>'
    je .redir
    inc rbx
    jmp .scan
.redir:
    mov byte [rbx], 0
    mov r13d, 1
    inc rbx
    cmp byte [rbx], '>'
    jne .fname
    mov r13d, 2
    inc rbx
.fname:
    mov rdi, rbx
    call skip_spaces
    mov r14, rdi
    call parse_name
    mov r15, rax
    test r15, r15
    jnz .fn_ok
    xor r13d, r13d
    jmp .exec
.fn_ok:
    mov byte [r14 + r15], 0
    mov rdi, r12
    call strlen
.trim:
    test rax, rax
    jz .trimmed
    cmp byte [r12 + rax - 1], ' '
    jne .trimmed
    dec rax
    mov byte [r12 + rax], 0
    jmp .trim
.trimmed:
    mov qword [cap_len], 0
    mov qword [cap_on], 1
.exec:
    mov rdi, r12
    call shell_exec
    cmp qword [sak_active], 0
    jne .nogfx
    call gfx_wait_end
.nogfx:
    test r13d, r13d
    jz .out
    mov qword [cap_on], 0
    xor ecx, ecx
    cmp r13d, 2
    jne .append_cap
    mov rdi, r14
    mov rsi, r15
    call fs_lookup
    cmp rax, -1
    je .append_cap
    mov rdi, rax
    call fs_get_inode
    test rax, rax
    jz .append_cap
    cmp qword [rax + INO_TYPE], FT_DIR
    je .out
    mov rcx, [rax + INO_SIZE]
    cmp rcx, 4096
    jbe .szok
    mov ecx, 4096
.szok:
    mov rdi, rax
    xor esi, esi
    lea rdx, [cap_out]
    call fs_read_at
    mov rcx, rax
.append_cap:
    lea rdi, [cap_out + rcx]
    lea rsi, [cap_buf]
    mov r8, [cap_len]
    add rcx, r8
    mov rbx, rcx
    mov rcx, r8
    cld
    rep movsb
    mov rdi, r14
    mov rsi, r15
    call fs_lookup
    cmp rax, -1
    jne .have
    mov rdi, r14
    mov rsi, r15
    xor edx, edx
    call fs_create
    cmp rax, -1
    je .out
.have:
    mov rdi, rax
    lea rsi, [cap_out]
    mov rdx, rbx
    call fs_write
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

shell_run_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rsi, rdi
    mov rax, [chain_depth]
    cmp rax, 4
    jae .direct
    inc qword [chain_depth]
    imul rax, rax, 264
    lea rdi, [chain_bufs]
    add rdi, rax
    mov r12, rdi
    xor ecx, ecx
.cp:
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .cpd
    inc ecx
    cmp ecx, 255
    jb .cp
    mov byte [rdi + rcx], 0
.cpd:
    xor r13d, r13d
.next:
    mov rbx, r12
    xor r14d, r14d
    xor r15d, r15d
.scan:
    mov al, [rbx]
    test al, al
    jz .run
    cmp al, ';'
    je .semi
    cmp al, '&'
    jne .c_or
    cmp byte [rbx + 1], '&'
    jne .adv
    mov byte [rbx], 0
    lea r15, [rbx + 2]
    mov r14d, 1
    jmp .run
.c_or:
    cmp al, '|'
    jne .adv
    cmp byte [rbx + 1], '|'
    jne .adv
    mov byte [rbx], 0
    lea r15, [rbx + 2]
    mov r14d, 2
    jmp .run
.semi:
    mov byte [rbx], 0
    lea r15, [rbx + 1]
    mov r14d, 3
    jmp .run
.adv:
    inc rbx
    jmp .scan
.run:
    cmp r13d, 1
    jne .chk2
    cmp qword [last_status], 0
    jne .skipseg
    jmp .do
.chk2:
    cmp r13d, 2
    jne .do
    cmp qword [last_status], 0
    je .skipseg
.do:
    mov rdi, r12
    call shell_run_seg
.skipseg:
    test r15, r15
    jz .done
    mov r12, r15
    mov r13d, r14d
    jmp .next
.done:
    dec qword [chain_depth]
    jmp .ret
.direct:
    mov rdi, rsi
    call shell_run_seg
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

shell_run_seg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    xor r12d, r12d
    mov r13d, 1
.skipsp:
    cmp byte [rbx], ' '
    jne .pfx
    inc rbx
    jmp .skipsp
.pfx:
    mov al, [rbx]
    test al, al
    jz .out
    cmp al, '@'
    jne .p1
    or r12d, 1
    inc rbx
    jmp .skipsp
.p1:
    cmp al, '-'
    jne .p2
    or r12d, 2
    inc rbx
    jmp .skipsp
.p2:
    cmp al, '!'
    jne .p3
    or r12d, 4
    inc rbx
    jmp .skipsp
.p3:
    cmp al, '+'
    jne .p4
    or r12d, 8
    inc rbx
    jmp .skipsp
.p4:
    cmp al, '*'
    jne .go
    movzx eax, byte [rbx + 1]
    sub eax, '0'
    cmp eax, 9
    ja .go
    inc rbx
    mov rdi, rbx
    call parse_int
    mov rbx, rdi
    mov r13, rax
    cmp r13, 10000
    jbe .skipsp
    mov r13d, 10000
    jmp .skipsp
.go:
    test r13, r13
    jz .out
    mov r14, [ticks]
.rep:
    test r12d, 1
    jz .noq
    mov qword [cap_len], 0
    mov qword [cap_on], 1
.noq:
    mov rdi, rbx
    call shell_run_one
    test r12d, 1
    jz .noq2
    mov qword [cap_on], 0
.noq2:
    dec r13
    jnz .rep
    test r12d, 2
    jz .ni
    mov qword [last_status], 0
.ni:
    test r12d, 4
    jz .nn
    xor qword [last_status], 1
.nn:
    test r12d, 8
    jz .out
    lea rdi, [msg_time]
    call con_puts_utf8
    mov rdi, [ticks]
    sub rdi, r14
    mov esi, 10
    call con_putu
    lea rdi, [msg_ms]
    call con_puts_utf8
    call con_newline
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

word_is:
    xor ecx, ecx
.l:
    mov al, [rsi + rcx]
    test al, al
    jz .endkw
    cmp al, [rdi + rcx]
    jne .no
    inc ecx
    jmp .l
.endkw:
    mov al, [rdi + rcx]
    test al, al
    jz .yes
    cmp al, ' '
    je .yes
    cmp al, 10
    je .yes
    cmp al, 13
    je .yes
.no:
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

sak_push:
    mov rax, [sak_sp]
    cmp rax, 16
    jae .full
    shl rax, 4
    lea rdx, [sak_stack]
    mov [rdx + rax], rdi
    mov [rdx + rax + 8], rsi
    inc qword [sak_sp]
.full:
    ret

sak_pop:
    cmp qword [sak_sp], 0
    je .r
    dec qword [sak_sp]
.r:
    ret

sak_top:
    mov rax, [sak_sp]
    dec rax
    shl rax, 4
    lea rdx, [sak_stack]
    add rdx, rax
    mov rax, [rdx]
    mov rdx, [rdx + 8]
    ret

sak_skip:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, esi
    xor r13d, r13d
    mov r14, [sak_pc]
.line:
    cmp r14, [sak_len]
    jae .eof
    lea rbx, [sak_buf]
    add rbx, r14
    mov rsi, rbx
.sp:
    cmp byte [rsi], ' '
    jne .w
    inc rsi
    jmp .sp
.w:
    mov rdi, rsi
    lea rsi, [kw_if]
    call word_is
    test eax, eax
    jnz .open
    lea rsi, [kw_while]
    call word_is
    test eax, eax
    jnz .open
    lea rsi, [kw_end]
    call word_is
    test eax, eax
    jnz .isend
    test r12d, r12d
    jnz .nextline
    test r13d, r13d
    jnz .nextline
    lea rsi, [kw_elif]
    call word_is
    test eax, eax
    jnz .found_elif
    lea rsi, [kw_else]
    call word_is
    test eax, eax
    jnz .found_else
    jmp .nextline
.open:
    inc r13d
    jmp .nextline
.isend:
    test r13d, r13d
    jz .found_end
    dec r13d
.nextline:
    lea rbx, [sak_buf]
.adv:
    cmp r14, [sak_len]
    jae .eof
    mov al, [rbx + r14]
    inc r14
    cmp al, 10
    jne .adv
    jmp .line
.found_elif:
    mov [sak_pc], r14
    mov qword [sak_enter], 1
    mov eax, 1
    jmp .r
.found_else:
    mov [sak_pc], r14
    mov qword [sak_enter], 1
    mov eax, 2
    jmp .r
.found_end:
    lea rbx, [sak_buf]
.adv2:
    cmp r14, [sak_len]
    jae .set_end
    mov al, [rbx + r14]
    inc r14
    cmp al, 10
    jne .adv2
.set_end:
    mov [sak_pc], r14
    mov eax, 3
    jmp .r
.eof:
    mov rax, [sak_len]
    mov [sak_pc], rax
    mov eax, 4
.r:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

sak_line:
    push rbx
    push r12
    push r13
    push r14
    lea rsi, [line_buf]
.sp:
    cmp byte [rsi], ' '
    jne .got
    inc rsi
    jmp .sp
.got:
    mov r12, rsi
    mov al, [rsi]
    test al, al
    jz .ret
    cmp al, '#'
    je .ret
    cmp al, ':'
    je .ret
    lea rdi, [tok_a]
    call get_token
    mov r13, rsi
    TOKIS tok_a, kw_rem
    jz .ret
    TOKIS tok_a, kw_if
    jz .if
    TOKIS tok_a, kw_elif
    jz .elif
    TOKIS tok_a, kw_else
    jz .else
    TOKIS tok_a, kw_end
    jz .end
    TOKIS tok_a, kw_while
    jz .while
    TOKIS tok_a, kw_goto
    jz .goto
    TOKIS tok_a, kw_exit
    jz .exit
    mov rdi, r12
    call shell_run_line
    jmp .ret
.elif:
    cmp qword [sak_enter], 0
    jne .if
    call sak_pop
    mov esi, 1
    call sak_skip
    jmp .ret
.if:
    mov qword [sak_enter], 0
    mov rsi, r13
    lea rdi, [exp_buf]
    mov edx, 512
    call expand_vars
    lea rdi, [exp_buf]
    call eval_cond
    test eax, eax
    jz .if_false
    mov edi, 1
    mov rsi, [sak_ls]
    call sak_push
    jmp .ret
.if_false:
    xor esi, esi
    call sak_skip
    jmp .ret
.else:
    cmp qword [sak_enter], 0
    jne .else_enter
    call sak_pop
    mov esi, 1
    call sak_skip
    jmp .ret
.else_enter:
    mov qword [sak_enter], 0
    mov edi, 1
    mov rsi, [sak_ls]
    call sak_push
    jmp .ret
.end:
    cmp qword [sak_sp], 0
    je .ret
    call sak_top
    cmp rax, 1
    jne .end_while
    call sak_pop
    jmp .ret
.end_while:
    mov [sak_pc], rdx
    jmp .ret
.while:
    mov rsi, r13
    lea rdi, [exp_buf]
    mov edx, 512
    call expand_vars
    lea rdi, [exp_buf]
    call eval_cond
    test eax, eax
    jz .wh_false
    cmp qword [sak_sp], 0
    je .wh_push
    call sak_top
    cmp rax, 2
    jne .wh_push
    mov rax, [sak_ls]
    cmp rdx, rax
    je .ret
.wh_push:
    mov edi, 2
    mov rsi, [sak_ls]
    call sak_push
    jmp .ret
.wh_false:
    cmp qword [sak_sp], 0
    je .wh_skip
    call sak_top
    cmp rax, 2
    jne .wh_skip
    mov rax, [sak_ls]
    cmp rdx, rax
    jne .wh_skip
    call sak_pop
.wh_skip:
    mov esi, 1
    call sak_skip
    jmp .ret
.exit:
    mov qword [sak_abort], 1
    jmp .ret
.goto:
    mov rsi, r13
    lea rdi, [tok_b]
    call get_token
    xor r14d, r14d
.gl:
    cmp r14, [sak_len]
    jae .glnf
    lea rbx, [sak_buf]
    add rbx, r14
.gsp:
    cmp byte [rbx], ' '
    jne .gchk
    inc rbx
    jmp .gsp
.gchk:
    cmp byte [rbx], ':'
    jne .gnext
    lea rdi, [rbx + 1]
    lea rsi, [tok_b]
    call word_is
    test eax, eax
    jnz .gfound
.gnext:
    lea rbx, [sak_buf]
.gadv:
    cmp r14, [sak_len]
    jae .gl
    mov al, [rbx + r14]
    inc r14
    cmp al, 10
    jne .gadv
    jmp .gl
.gfound:
    lea rbx, [sak_buf]
.gadv2:
    cmp r14, [sak_len]
    jae .gset
    mov al, [rbx + r14]
    inc r14
    cmp al, 10
    jne .gadv2
.gset:
    mov [sak_pc], r14
    mov qword [sak_sp], 0
    jmp .ret
.glnf:
    lea rdi, [msg_label_nf]
    call con_puts_utf8
    call con_newline
    mov qword [sak_abort], 1
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

sak_exec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [sak_pc], 0
    mov qword [sak_sp], 0
    mov qword [sak_abort], 0
    mov qword [sak_enter], 0
    mov qword [sak_active], 1
.next:
    cmp qword [sak_abort], 0
    jne .fin
    mov rax, [sak_pc]
    cmp rax, [sak_len]
    jae .fin
    mov [sak_ls], rax
    call kbd_poll_char
    cmp al, 27
    jne .fetch
    lea rdi, [msg_aborted]
    call con_puts_utf8
    call con_newline
    jmp .fin
.fetch:
    lea rsi, [sak_buf]
    add rsi, [sak_pc]
    lea rdi, [line_buf]
    xor ecx, ecx
.cp:
    mov al, [rsi]
    test al, al
    jz .eol0
    cmp al, 10
    je .eol
    cmp al, 13
    je .skipcr
    cmp ecx, 255
    jae .skipcr
    mov [rdi + rcx], al
    inc ecx
.skipcr:
    inc rsi
    jmp .cp
.eol:
    inc rsi
    mov byte [rdi + rcx], 0
    lea rax, [sak_buf]
    sub rsi, rax
    mov [sak_pc], rsi
    jmp .run
.eol0:
    mov byte [rdi + rcx], 0
    mov rax, [sak_len]
    mov [sak_pc], rax
.run:
    call sak_line
    cmp qword [con_dirty], 0
    je .next
    call con_flush
    jmp .next
.fin:
    mov qword [sak_active], 0
    call gfx_wait_end
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

sak_set_args:
    push rbx
    push r12
    push r13
    mov r13d, '1'
.clr:
    cmp r13d, 0x3A
    jae .set
    mov [name_tmp], r13b
    mov byte [name_tmp + 1], 0
    lea rdi, [name_tmp]
    mov esi, 1
    call var_find
    test rax, rax
    jz .cn
    mov byte [rax], 0
.cn:
    inc r13d
    jmp .clr
.set:
    mov r13d, '1'
.l:
    cmp r13d, 0x3A
    jae .r
    lea rdi, [tok_a]
    mov rsi, r12
    call get_token
    test eax, eax
    jz .r
    mov r12, rsi
    mov [name_tmp], r13b
    mov byte [name_tmp + 1], 0
    lea rdi, [name_tmp]
    mov esi, 1
    lea rdx, [tok_a]
    call var_set
    inc r13d
    jmp .l
.r:
    pop r13
    pop r12
    pop rbx
    ret

con_left:
    cmp qword [con_cur_x], 0
    jne .d
    cmp qword [con_cur_y], 0
    je .r
    dec qword [con_cur_y]
    mov rax, [con_cols]
    mov [con_cur_x], rax
.d:
    dec qword [con_cur_x]
    mov qword [con_dirty], 1
.r:
    ret

con_right:
    mov rax, [con_cur_x]
    inc rax
    cmp rax, [con_cols]
    jb .s
    xor eax, eax
    inc qword [con_cur_y]
.s:
    mov [con_cur_x], rax
    mov qword [con_dirty], 1
    ret

gfx_begin:
    cmp qword [gfx_active], 0
    jne .r
    mov rax, [font_scale]
    mov [g_save_scale], rax
    mov rax, [font_adv]
    mov [g_save_adv], rax
    mov qword [gfx_active], 1
.r:
    ret

gfx_end:
    cmp qword [gfx_active], 0
    je .r
    mov rax, [g_save_scale]
    mov [font_scale], rax
    mov rax, [g_save_adv]
    mov [font_adv], rax
    mov qword [gfx_active], 0
    mov qword [gfx_manual], 0
    mov qword [con_dirty], 1
.r:
    ret

gfx_present:
    cmp qword [gfx_manual], 0
    jne .r
    call swap_buffers
.r:
    ret

gfx_wait_end:
    cmp qword [gfx_active], 0
    je .r
    call wait_key
    call gfx_end
.r:
    ret

parse_hex:
    xor eax, eax
.l:
    movzx ecx, byte [rdi]
    cmp ecx, '0'
    jb .r
    cmp ecx, '9'
    jbe .d
    or ecx, 0x20
    cmp ecx, 'a'
    jb .r
    cmp ecx, 'f'
    ja .r
    sub ecx, 'a' - 10
    jmp .a
.d:
    sub ecx, '0'
.a:
    shl rax, 4
    or rax, rcx
    inc rdi
    jmp .l
.r:
    ret

parse_args:
    push rbx
    push r12
    mov r12d, esi
    xor ebx, ebx
.l:
    cmp ebx, r12d
    jae .r
    call skip_spaces
    cmp byte [rdi], 0
    je .r
    mov r11, rdi
    cmp byte [rdi], '#'
    jne .dec
    inc rdi
    call parse_hex
    jmp .got
.dec:
    call parse_int
.got:
    cmp rdi, r11
    je .r
    lea rcx, [garg]
    mov [rcx + rbx*8], rax
    inc ebx
    jmp .l
.r:
    mov eax, ebx
    pop r12
    pop rbx
    ret

color_of:
    cmp rdi, 9
    ja .raw
    lea rax, [color_tab]
    mov eax, [rax + rdi*4]
    ret
.raw:
    mov eax, edi
    ret

isqrt:
    xor eax, eax
.l:
    lea rdx, [rax + 1]
    imul rdx, rdx
    cmp rdx, rdi
    ja .r
    inc rax
    jmp .l
.r:
    ret

gdisc_fn:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [garg + 16]
    mov r12, rbx
    imul r12, r12
    neg rbx
    mov rdi, [garg + 24]
    call color_of
    mov r14d, eax
.l:
    cmp rbx, [garg + 16]
    jg .r
    mov rdi, rbx
    imul rdi, rdi
    mov rax, r12
    sub rax, rdi
    mov rdi, rax
    call isqrt
    mov r13, rax
    mov r8, [garg]
    sub r8, r13
    mov r9, [garg + 8]
    add r9, rbx
    lea r10, [r13*2 + 1]
    mov r11d, 1
    mov eax, r14d
    call gfx_rect
    inc rbx
    jmp .l
.r:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

gcirc_fn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, [garg + 16]
    mov r12, rbx
    imul r12, r12
    mov r15, rbx
    dec r15
    imul r15, r15
    neg rbx
    mov rdi, [garg + 24]
    call color_of
    mov r14d, eax
.l:
    cmp rbx, [garg + 16]
    jg .r
    mov rcx, rbx
    imul rcx, rcx
    mov rdi, r12
    sub rdi, rcx
    call isqrt
    mov r13, rax
    mov rdi, r15
    sub rdi, rcx
    js .full
    call isqrt
    mov rcx, rax
    mov r8, [garg]
    sub r8, r13
    mov r9, [garg + 8]
    add r9, rbx
    mov r10, r13
    sub r10, rcx
    inc r10
    mov r11d, 1
    mov eax, r14d
    call gfx_rect
    mov r8, [garg]
    add r8, rcx
    mov eax, r14d
    call gfx_rect
    jmp .next
.full:
    mov r8, [garg]
    sub r8, r13
    mov r9, [garg + 8]
    add r9, rbx
    lea r10, [r13*2 + 1]
    mov r11d, 1
    mov eax, r14d
    call gfx_rect
.next:
    inc rbx
    jmp .l
.r:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

ed_line_start:
    mov rax, rdi
.l:
    test rax, rax
    jz .r
    cmp byte [edit_buf + rax - 1], 10
    je .r
    dec rax
    jmp .l
.r:
    ret

ed_line_end:
    mov rax, rdi
.l:
    cmp rax, [ed_len]
    jae .r
    cmp byte [edit_buf + rax], 10
    je .r
    inc rax
    jmp .l
.r:
    ret

ed_render:
    push rbx
    push r12
.again:
    call con_clear
    mov rbx, [ed_top]
    mov qword [ed_found], 0
.pl:
    mov rax, [con_rows]
    dec rax
    cmp [con_cur_y], rax
    jae .stop
    cmp rbx, [ed_pos]
    jne .nocur
    mov rax, [con_cur_x]
    mov [ed_cx], rax
    mov rax, [con_cur_y]
    mov [ed_cy], rax
    mov qword [ed_found], 1
.nocur:
    cmp rbx, [ed_len]
    jae .stop
    movzx edi, byte [edit_buf + rbx]
    call con_putc
    inc rbx
    jmp .pl
.stop:
    cmp qword [ed_found], 0
    jne .show
    mov rax, [ed_pos]
    cmp rax, [ed_top]
    jb .up_scroll
    mov rdi, [ed_top]
    call ed_line_end
    cmp rax, [ed_len]
    jae .show
    inc rax
    mov [ed_top], rax
    jmp .again
.up_scroll:
    mov rdi, [ed_pos]
    call ed_line_start
    mov [ed_top], rax
    jmp .again
.show:
    cmp qword [con_cols], 50
    jb .nostatus
    xor edi, edi
    mov rsi, [con_rows]
    dec rsi
    call con_gotoxy
    lea rdi, [msg_ed_status]
    call con_puts_utf8
    mov rdi, [ed_len]
    mov esi, 10
    call con_putu
.nostatus:
    mov rdi, [ed_cx]
    mov rsi, [ed_cy]
    call con_gotoxy
    pop r12
    pop rbx
    ret

ed_ask:
    push rbx
    xor edi, edi
    mov rsi, [con_rows]
    dec rsi
    call con_gotoxy
    mov rbx, [con_cols]
    dec rbx
.sp:
    test rbx, rbx
    jz .spd
    mov edi, ' '
    call con_putc
    dec rbx
    jmp .sp
.spd:
    xor edi, edi
    mov rsi, [con_rows]
    dec rsi
    call con_gotoxy
    lea rdi, [msg_ed_ask]
    call con_puts_utf8
    pop rbx
    ret

edit_run:
    push rbx
    push r12
.loop:
    call ed_render
    call wait_key
    movzx ebx, al
    cmp bl, 27
    je .esc
    cmp bl, 1
    je .up
    cmp bl, 2
    je .down
    cmp bl, 3
    je .left
    cmp bl, 4
    je .right
    cmp bl, 5
    je .home
    cmp bl, 6
    je .end
    cmp bl, 7
    je .del
    cmp bl, 8
    je .bs
    cmp bl, 10
    je .ins
    cmp bl, 32
    jb .loop
.ins:
    mov rcx, [ed_len]
    cmp rcx, 4000
    jae .loop
    mov rdx, [ed_pos]
.shr:
    cmp rcx, rdx
    jle .put
    mov al, [edit_buf + rcx - 1]
    mov [edit_buf + rcx], al
    dec rcx
    jmp .shr
.put:
    mov [edit_buf + rdx], bl
    inc qword [ed_len]
    inc qword [ed_pos]
    mov qword [ed_mod], 1
    jmp .loop
.bs:
    mov rdx, [ed_pos]
    test rdx, rdx
    jz .loop
    mov rcx, rdx
.bl:
    cmp rcx, [ed_len]
    jae .bd
    mov al, [edit_buf + rcx]
    mov [edit_buf + rcx - 1], al
    inc rcx
    jmp .bl
.bd:
    dec qword [ed_len]
    dec qword [ed_pos]
    mov qword [ed_mod], 1
    jmp .loop
.del:
    mov rdx, [ed_pos]
    cmp rdx, [ed_len]
    jae .loop
    lea rcx, [rdx + 1]
.dll:
    cmp rcx, [ed_len]
    jae .dd
    mov al, [edit_buf + rcx]
    mov [edit_buf + rcx - 1], al
    inc rcx
    jmp .dll
.dd:
    dec qword [ed_len]
    mov qword [ed_mod], 1
    jmp .loop
.left:
    cmp qword [ed_pos], 0
    je .loop
    dec qword [ed_pos]
    jmp .loop
.right:
    mov rax, [ed_pos]
    cmp rax, [ed_len]
    jae .loop
    inc qword [ed_pos]
    jmp .loop
.home:
    mov rdi, [ed_pos]
    call ed_line_start
    mov [ed_pos], rax
    jmp .loop
.end:
    mov rdi, [ed_pos]
    call ed_line_end
    mov [ed_pos], rax
    jmp .loop
.up:
    mov rdi, [ed_pos]
    call ed_line_start
    mov r12, rax
    test r12, r12
    jz .loop
    mov rcx, [ed_pos]
    sub rcx, r12
    lea rdi, [r12 - 1]
    call ed_line_start
    mov rdx, r12
    dec rdx
    add rax, rcx
    cmp rax, rdx
    jbe .setp
    mov rax, rdx
.setp:
    mov [ed_pos], rax
    jmp .loop
.down:
    mov rdi, [ed_pos]
    call ed_line_end
    mov r12, rax
    cmp r12, [ed_len]
    jae .loop
    mov rdi, [ed_pos]
    call ed_line_start
    mov rcx, [ed_pos]
    sub rcx, rax
    lea rdi, [r12 + 1]
    mov rdx, rdi
    call ed_line_end
    add rdx, rcx
    cmp rdx, rax
    jbe .setd
    mov rdx, rax
.setd:
    mov [ed_pos], rdx
    jmp .loop
.esc:
    call ed_ask
    call wait_key
    cmp al, 10
    je .save
    cmp al, 'y'
    je .save
    cmp al, 'Y'
    je .save
    cmp al, 0xED
    je .save
    cmp al, 0xCD
    je .save
    cmp al, 'n'
    je .quit
    cmp al, 'N'
    je .quit
    cmp al, 0xF2
    je .quit
    cmp al, 0xD2
    je .quit
    jmp .loop
.save:
    mov eax, 1
    jmp .r
.quit:
    xor eax, eax
.r:
    pop r12
    pop rbx
    ret

md_is_hr:
    cmp rdx, 3
    jb .no
    movzx eax, byte [rsi]
    cmp al, '-'
    je .ok
    cmp al, '*'
    je .ok
    cmp al, '_'
    jne .no
.ok:
    xor ecx, ecx
.l:
    cmp rcx, rdx
    jae .yes
    cmp [rsi + rcx], al
    jne .no
    inc rcx
    jmp .l
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

md_inline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13, rdx
    xor ebx, ebx
    mov rax, [md_indent]
    mov [md_x], rax
    mov qword [md_bold], 0
    mov qword [md_ital], 0
    mov qword [md_code], 0
    mov qword [md_link], 0
    mov rax, [md_scale]
    mov [font_scale], rax
    shl rax, 3
    mov [font_adv], rax
.loop:
    cmp rbx, r13
    jae .end
    movzx r14d, byte [r12 + rbx]
    cmp r14d, 0x5C
    jne .n1
    lea rax, [rbx + 1]
    cmp rax, r13
    jae .n1
    inc rbx
    movzx r14d, byte [r12 + rbx]
    jmp .draw
.n1:
    cmp r14d, '*'
    jne .n2
    lea rax, [rbx + 1]
    cmp rax, r13
    jae .ital
    cmp byte [r12 + rax], '*'
    jne .ital
    xor qword [md_bold], 1
    add rbx, 2
    jmp .loop
.ital:
    xor qword [md_ital], 1
    inc rbx
    jmp .loop
.n2:
    cmp r14d, '`'
    jne .n3
    xor qword [md_code], 1
    inc rbx
    jmp .loop
.n3:
    cmp r14d, '['
    jne .n4
    cmp qword [md_link], 0
    jne .draw
    mov qword [md_link], 1
    inc rbx
    jmp .loop
.n4:
    cmp r14d, ']'
    jne .draw
    cmp qword [md_link], 0
    je .draw
    mov qword [md_link], 0
    inc rbx
    cmp rbx, r13
    jae .loop
    cmp byte [r12 + rbx], '('
    jne .loop
.skiplink:
    cmp rbx, r13
    jae .loop
    cmp byte [r12 + rbx], ')'
    je .afterlink
    inc rbx
    jmp .skiplink
.afterlink:
    inc rbx
    jmp .loop
.draw:
    mov rax, [md_x]
    add rax, [font_adv]
    mov rcx, [width]
    sub rcx, 16
    cmp rax, rcx
    jbe .nowrap
    mov rax, [md_indent]
    mov [md_x], rax
    mov rax, [font_adv]
    mov rcx, [md_scale]
    lea rax, [rax + rcx*2]
    add [md_y], rax
.nowrap:
    mov rax, [md_y]
    mov rcx, [font_adv]
    add rcx, rax
    test rcx, rcx
    js .advance
    cmp rax, [height]
    jge .advance
    mov r15d, [md_color]
    cmp qword [md_ital], 0
    je .c1
    mov r15d, 0x0090C8FF
.c1:
    cmp qword [md_bold], 0
    je .c2
    mov r15d, 0x00FFFFFF
.c2:
    cmp qword [md_link], 0
    je .c3
    mov r15d, 0x0060A0FF
.c3:
    cmp qword [md_code], 0
    je .c4
    mov r8, [md_x]
    mov r9, [md_y]
    mov r10, [font_adv]
    mov r11, r10
    mov eax, 0x00303848
    call gfx_rect
    mov r15d, 0x0080FF80
.c4:
    cmp r14d, ' '
    je .afterdraw
    mov r8, [md_x]
    mov r9, [md_y]
    mov r10d, r14d
    mov eax, r15d
    call draw_char
    cmp qword [md_bold], 0
    je .afterdraw
    mov r8, [md_x]
    inc r8
    mov r9, [md_y]
    mov r10d, r14d
    mov eax, r15d
    call draw_char
.afterdraw:
    cmp qword [md_link], 0
    je .advance
    mov r8, [md_x]
    mov r9, [md_y]
    add r9, [font_adv]
    mov r10, [font_adv]
    mov r11d, 1
    mov eax, r15d
    call gfx_rect
.advance:
    mov rax, [font_adv]
    add [md_x], rax
    inc rbx
    jmp .loop
.end:
    mov rax, [font_adv]
    mov rcx, [md_scale]
    lea rax, [rax + rcx*2]
    add [md_y], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

md_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13, rdx
    cmp r13, 3
    jb .nofence
    cmp byte [r12], '`'
    jne .nofence
    cmp byte [r12 + 1], '`'
    jne .nofence
    cmp byte [r12 + 2], '`'
    jne .nofence
    xor qword [md_fence], 1
    jmp .out
.nofence:
    cmp qword [md_fence], 0
    jne .codeline
    test r13, r13
    jz .blank
    mov rsi, r12
    mov rdx, r13
    call md_is_hr
    test eax, eax
    jnz .hr
    mov qword [md_scale], 1
    mov qword [md_indent], 16
    mov qword [md_color], 0x00D0D0D0
    cmp byte [r12], '#'
    je .heading
    cmp byte [r12], '>'
    je .quote
    xor ebx, ebx
.sp:
    cmp rbx, r13
    jae .para
    cmp byte [r12 + rbx], ' '
    jne .bchk
    inc rbx
    jmp .sp
.bchk:
    lea rax, [rbx + 1]
    cmp rax, r13
    jae .para
    cmp byte [r12 + rbx + 1], ' '
    jne .para
    mov al, [r12 + rbx]
    cmp al, '-'
    je .bullet
    cmp al, '*'
    je .bullet
    cmp al, '+'
    je .bullet
.para:
    mov rsi, r12
    mov rdx, r13
    call md_inline
    jmp .out
.bullet:
    lea r8, [rbx*8 + 16]
    mov r9, [md_y]
    add r9, 3
    mov r10d, 4
    mov r11d, 4
    mov eax, 0x00FFC060
    call gfx_rect
    lea rax, [r8 + 16]
    mov [md_indent], rax
    lea rax, [rbx + 2]
    add r12, rax
    sub r13, rax
    mov rsi, r12
    mov rdx, r13
    call md_inline
    jmp .out
.quote:
    mov qword [md_color], 0x00A0A8B8
    mov qword [md_indent], 28
    mov rbx, [md_y]
    inc r12
    dec r13
    test r13, r13
    jz .q_do
    cmp byte [r12], ' '
    jne .q_do
    inc r12
    dec r13
.q_do:
    mov rsi, r12
    mov rdx, r13
    call md_inline
    mov r8d, 16
    mov r9, rbx
    mov r10d, 3
    mov r11, [md_y]
    sub r11, rbx
    mov eax, 0x00606878
    call gfx_rect
    jmp .out
.heading:
    xor ebx, ebx
.hc:
    cmp rbx, r13
    jae .hcend
    cmp byte [r12 + rbx], '#'
    jne .hcend
    inc rbx
    jmp .hc
.hcend:
    cmp rbx, 6
    ja .para
    cmp rbx, r13
    jae .para
    cmp byte [r12 + rbx], ' '
    jne .para
    mov r14, rbx
    inc rbx
    add r12, rbx
    sub r13, rbx
    mov qword [md_scale], 1
    mov qword [md_color], 0x00FF9040
    cmp r14, 1
    jne .h2
    mov qword [md_scale], 4
    mov qword [md_color], 0x00FFE060
    jmp .hdo
.h2:
    cmp r14, 2
    jne .hdo
    mov qword [md_scale], 2
    mov qword [md_color], 0x0060E0FF
.hdo:
    mov rsi, r12
    mov rdx, r13
    call md_inline
    cmp r14, 2
    ja .hgap
    mov r8d, 16
    mov r9, [md_y]
    mov r10, [width]
    sub r10, 32
    mov r11d, 2
    mov eax, [md_color]
    call gfx_rect
    add qword [md_y], 6
.hgap:
    add qword [md_y], 4
    jmp .out
.hr:
    mov r8d, 16
    mov r9, [md_y]
    add r9, 4
    mov r10, [width]
    sub r10, 32
    mov r11d, 2
    mov eax, 0x00606878
    call gfx_rect
    add qword [md_y], 12
    jmp .out
.blank:
    add qword [md_y], 10
    jmp .out
.codeline:
    mov r8d, 8
    mov r9, [md_y]
    mov r10, [width]
    sub r10, 16
    mov r11d, 11
    mov eax, 0x00101018
    call gfx_rect
    mov qword [font_scale], 1
    mov qword [font_adv], 8
    xor ebx, ebx
    mov r14d, 16
.cl:
    cmp rbx, r13
    jae .cld
    movzx r10d, byte [r12 + rbx]
    cmp r10d, ' '
    je .cls
    mov eax, r14d
    add eax, 8
    cmp rax, [width]
    ja .cld
    mov r8d, r14d
    mov r9, [md_y]
    inc r9
    mov eax, 0x0080FF80
    call draw_char
.cls:
    add r14d, 8
    inc rbx
    jmp .cl
.cld:
    add qword [md_y], 11
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

md_render:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax, 0x00181C24
    call fill_screen
    mov rax, 8
    sub rax, [md_scroll]
    mov [md_y], rax
    mov qword [md_fence], 0
    xor ebx, ebx
.nextline:
    cmp rbx, [md_len]
    jae .done
    lea r12, [cap_out]
    add r12, rbx
    xor r13d, r13d
.scan:
    lea rax, [rbx + r13]
    cmp rax, [md_len]
    jae .eol
    cmp byte [r12 + r13], 10
    je .eol
    inc r13
    jmp .scan
.eol:
    mov r14, r13
    test r13, r13
    jz .render
    cmp byte [r12 + r13 - 1], 13
    jne .render
    dec r13
.render:
    mov rsi, r12
    mov rdx, r13
    call md_line
    lea rbx, [rbx + r14 + 1]
    jmp .nextline
.done:
    mov rax, [md_y]
    add rax, [md_scroll]
    add rax, 8
    mov [md_total], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

md_view:
    push rbx
    call gfx_begin
    mov qword [md_scroll], 0
.redraw:
    call md_render
    mov rax, [height]
    lea r9, [rax - 14]
    xor r8d, r8d
    mov r10, [width]
    mov r11d, 14
    mov eax, 0x00303040
    call gfx_rect
    mov qword [font_scale], 1
    mov qword [font_adv], 8
    mov r8d, 8
    mov rax, [height]
    lea r9, [rax - 11]
    mov eax, 0x00FFFFFF
    lea rdi, [msg_md_hint]
    call draw_text
    call swap_buffers
.key:
    call wait_key
    cmp al, 27
    je .exit
    cmp al, 'q'
    je .exit
    cmp al, 0xE9
    je .exit
    cmp al, 1
    je .up
    cmp al, 2
    je .down
    cmp al, 11
    je .pgup
    cmp al, 12
    je .pgdn
    cmp al, 5
    je .home
    cmp al, 6
    je .end
    jmp .key
.up:
    mov rax, [md_scroll]
    sub rax, 24
    jmp .setsc
.down:
    mov rax, [md_scroll]
    add rax, 24
    jmp .setsc
.pgup:
    mov rax, [height]
    sub rax, 40
    neg rax
    add rax, [md_scroll]
    jmp .setsc
.pgdn:
    mov rax, [height]
    sub rax, 40
    add rax, [md_scroll]
    jmp .setsc
.home:
    xor eax, eax
    jmp .setsc
.end:
    mov rax, [md_total]
.setsc:
    mov rdx, [md_total]
    mov rcx, [height]
    sub rcx, 20
    sub rdx, rcx
    test rdx, rdx
    jns .mx
    xor edx, edx
.mx:
    cmp rax, rdx
    jle .lo
    mov rax, rdx
.lo:
    test rax, rax
    jns .st
    xor eax, eax
.st:
    mov [md_scroll], rax
    jmp .redraw
.exit:
    call gfx_end
    pop rbx
    ret


section .data
align 16
prompt_str  db "> ", 0
framebuffer     dq 0
width           dq 0
height          dq 0
pitch           dq 0

backbuffer      dq 0
render_fb       dq 0
render_pitch    dq 0

heap_cur        dq 0

ticks           dq 0
last_key_tick   dq 0
fs_dirty        dq 0

key_head        dq 0
key_tail        dq 0
key_buffer      times 16 db 0
kbd_layout      dq 0
kbd_shift       dq 0
kbd_alt         dq 0
alt_toggled     dq 0
shell_buf       times 256 db 0
shell_len       dq 0
word_buf        times 64 db 0
fs_tmpbuf       times 512 db 0

con_textbuf     dq 0
con_cols        dq 0
con_rows        dq 0
con_cur_x       dq 0
con_cur_y       dq 0
con_dirty       dq 0
con_fg          dq C_LGRAY
con_bg          dq C_BLACK
font_scale      dq 1
font_adv        dq 8
kbd_ext         dq 0
hist_len        dq 0
hist_buf        times 256 db 0
rtc_bin         dq 0
rand_state      dq 0x2545F4914F6CDD1D
color_tab       dd C_BLACK, C_WHITE, C_RED, C_GREEN, C_BLUE, C_CYAN, C_YELLOW, C_MAGENTA, C_GRAY, C_ORANGE

save_color      dd 0
save_x1         dq 0
save_y1         dq 0

align 512
fs_super:
    times 64 db 0

align 512
fs_bitmap:
    times FS_BITMAP_SIZE db 0

align 512
fs_inodes:
    times (FS_INODE_SIZE * FS_MAX_FILES) db 0

align 16
fs_fd_pos:
    times (FS_MAX_FILES * 4) db 0

msg_kernel_loaded db "Ядро загружено! ", 0
msg_panic         db "PANIC: ", 0

cmd_help        db "help", 0
cmd_clear       db "clear", 0
cmd_echo        db "echo", 0
cmd_layout      db "layout", 0
cmd_reboot      db "reboot", 0
cmd_ver         db "ver", 0
cmd_uptime      db "uptime", 0
cmd_background  db "background", 0
cmd_ls          db "ls", 0
cmd_cat         db "cat", 0
cmd_touch       db "touch", 0
cmd_rm          db "rm", 0
cmd_hex         db "hex", 0
cmd_sfnew       db "sfnew", 0
cmd_sfinfo      db "sfinfo", 0
cmd_sfwrite     db "sfwrite", 0
cmd_sfhello     db "sfhello", 0
cmd_run         db "run", 0
cmd_mkprog      db "mkprog", 0
cmd_sync        db "sync", 0
cmd_format      db "format", 0
arg_ru          db "ru", 0
arg_en          db "en", 0
cmd_cp       db "cp", 0
cmd_mv       db "mv", 0
cmd_write    db "write", 0
cmd_stat     db "stat", 0
cmd_df       db "df", 0
cmd_mem      db "mem", 0
cmd_date     db "date", 0
cmd_calc     db "calc", 0
cmd_color    db "color", 0
cmd_font     db "font", 0
cmd_sleep    db "sleep", 0
cmd_shutdown db "shutdown", 0
cmd_cpuid    db "cpuid", 0
cmd_rand     db "rand", 0
cmd_beep     db "beep", 0
cmd_mkdir    db "mkdir", 0
cmd_cd       db "cd", 0
cmd_pwd      db "pwd", 0
cmd_append   db "append", 0
cmd_edit     db "edit", 0
cmd_sak      db "sak", 0
cmd_sakdemo  db "sakdemo", 0
cmd_set      db "set", 0
cmd_unset    db "unset", 0
cmd_vars     db "vars", 0
cmd_let      db "let", 0
cmd_input    db "input", 0
cmd_pause    db "pause", 0
cmd_rem      db "rem", 0
cmd_if       db "if", 0
cmd_elif     db "elif", 0
cmd_else     db "else", 0
cmd_end      db "end", 0
cmd_while    db "while", 0
cmd_goto     db "goto", 0
cmd_exit     db "exit", 0
cmd_rmdir    db "rmdir", 0
cmd_del      db "del", 0
cmd_type     db "type", 0
cmd_cls      db "cls", 0
cmd_dir      db "dir", 0
cmd_copy     db "copy", 0
cmd_ren      db "ren", 0

msg_help_text db "Команды (help <команда> - подробнее):", 10
              db " Файлы:   ls cat touch rm hex cp mv write append edit stat df", 10
              db " Папки:   mkdir cd pwd  (rm удаляет пустую папку)", 10
              db " SF:      sfnew sfinfo sfwrite sfhello mkprog run", 10
              db " Диск:    sync format", 10
              db " Экран:   clear gui font color background layout", 10
              db " Система: ver uptime date mem cpuid reboot shutdown sleep beep rand", 10
              db " Скрипты: sak sakdemo set unset vars let input pause rem", 10
              db "          внутри .sak: if elif else end while goto exit", 10
              db " Графика: gcls gpix gline grect gfill gcirc gdisc gtext gscale", 10
              db "          gauto gflip gkey gwait gend", 10
              db " Текст:   edit (редактор) md mddemo (Markdown)", 10
              db " Прочее:  calc echo      вывод в файл: команда > f, команда >> f", 10
              db " Цепочки:  a ; b   a && b   a || b     префиксы: @cmd -cmd !cmd +cmd *N cmd", 10
              db "Статус последней команды: $?   (help prefix)", 10
              db "Темы: help sak, cond, variables, redirect, keys, gfx, markdown, prefix", 0
msg_unknown       db "Unknown command: ", 0
msg_layout_usage  db "Usage: layout <en|ru>", 0
msg_ru_set        db "Layout: RU", 0
msg_en_set        db "Layout: EN", 0
msg_ver           db "OS alpha v1.0 (folders, .sak scripts, gui)", 0
msg_uptime_prefix db "Ticks: ", 0
msg_no_file       db "No such file", 0
msg_empty         db "(empty)", 0
msg_sf_bad        db "Bad SF header", 0
msg_created       db "Created: ", 0
msg_removed       db "Removed: ", 0
msg_exists        db "Already exists", 0
msg_not_exec      db "Not an SF executable", 0
msg_running       db "Running: ", 0
msg_synced        db "Saved to disk", 0
msg_formatted     db "FS formatted and saved", 0
msg_disk_err      db "Disk write error", 0
msg_sf_magic      db "  magic:   0x", 0
msg_sf_ver        db "  version: ", 0
msg_sf_type       db "  type:    ", 0
msg_sf_entry      db "  entry:   0x", 0
msg_sf_size       db "  size:    ", 0
msg_st_blocks     db "  blocks:  ", 0
msg_st_first      db "  first:   ", 0
msg_copied        db "Copied: ", 0
msg_moved         db "Renamed: ", 0
msg_written       db "Written: ", 0
msg_nospace       db "No space", 0
msg_df_files      db "Files:   ", 0
msg_df_blocks     db "Blocks:  ", 0
msg_df_kb         db "KB used: ", 0
msg_mem_used      db "Heap used KB: ", 0
msg_mem_free      db "Heap free KB: ", 0
msg_calc_usage    db "Usage: calc <a> <+-*/%> <b>", 0
msg_div0          db "Division by zero", 0
msg_font_usage    db "Usage: font <8|16|32>", 0
msg_cpu_vendor    db "CPU vendor: ", 0
msg_cpu_brand     db "CPU: ", 0
msg_shutdown      db "Shutting down...", 0
msg_aborted       db "Script aborted", 0
msg_no_dir        db "Нет такой папки", 0
msg_notempty      db "Папка не пуста", 0
msg_isdir         db "Это папка", 0
msg_scriptonly    db "Работает только внутри .sak скрипта", 0
msg_pause         db "Нажмите любую клавишу...", 0
msg_edit_hint     db "Вводите строки. '.' - сохранить, '.q' - отмена", 0
msg_help_nf       db "Нет справки по этой теме. Список: help", 0
msg_sak_usage     db "Использование: sak <файл.sak> [аргументы]", 0
msg_sak_nested    db "Вложенный запуск sak не поддерживается", 0
msg_sak_big       db "Скрипт слишком большой (макс. 8191 байт)", 0
msg_label_nf      db "Метка не найдена", 0
s_demo_name       db "demo.sak", 0
empty_str         db 0
cmd_gcls     db "gcls", 0
cmd_gpix     db "gpix", 0
cmd_gline    db "gline", 0
cmd_grect    db "grect", 0
cmd_gfill    db "gfill", 0
cmd_gcirc    db "gcirc", 0
cmd_gdisc    db "gdisc", 0
cmd_gtext    db "gtext", 0
cmd_gscale   db "gscale", 0
cmd_gwait    db "gwait", 0
cmd_gend     db "gend", 0
cmd_gauto    db "gauto", 0
cmd_gflip    db "gflip", 0
cmd_gkey     db "gkey", 0
cmd_md       db "md", 0
cmd_mddemo   db "mddemo", 0
s_demomd_name    db "demo.md", 0
demo_md_text:
    db "# MiniOS Markdown demo", 10
    db 10
    db "This is a **bold** word, an *italic* word and some `inline code`.", 10
    db 10
    db "## Lists", 10
    db 10
    db "- first item", 10
    db "- second item with **bold**", 10
    db "  - indented item", 10
    db 10
    db "## Quote", 10
    db 10
    db "> Markdown viewer renders text in graphics mode.", 10
    db 10
    db "---", 10
    db 10
    db "### Code block", 10
    db 10
    db "```", 10
    db "let i 0", 10
    db "while $i < 3", 10
    db "  echo $i", 10
    db "end", 10
    db "```", 10
    db 10
    db "A [link](http://example.com) shows only its text.", 10
    db 10
    db "## Scrolling", 10
    db 10
    db "Use Up/Down, PgUp/PgDn, Home/End. Esc or q closes the viewer.", 10
demo_md_end:
msg_g_usage      db "Мало аргументов. Справка: help gfx", 0
msg_md_hint       db "Up/Down PgUp/PgDn Home/End - scroll    Esc/q - exit", 0
msg_ed_status     db "Esc - меню   Байт: ", 0
msg_ed_ask        db "Сохранить? Enter/y - да, n - нет, др. - назад", 0
msg_time          db "Время: ", 0
msg_ms            db " мс", 0
kw_if      db "if", 0
kw_elif    db "elif", 0
kw_else    db "else", 0
kw_end     db "end", 0
kw_while   db "while", 0
kw_goto    db "goto", 0
kw_exit    db "exit", 0
kw_rem     db "rem", 0
kw_not     db "not", 0
kw_exists  db "exists", 0
kw_and     db "and", 0
kw_and2    db "&&", 0
kw_or      db "or", 0
kw_or2     db "||", 0
kw_random  db "RANDOM", 0
kw_ticks   db "TICKS", 0
s_op_eq2   db "==", 0
s_op_eq1   db "=", 0
s_op_ne    db "!=", 0
s_op_ne2   db "<>", 0
s_op_lt    db "<", 0
s_op_gt    db ">", 0
s_op_le    db "<=", 0
s_op_ge    db ">=", 0
align 8
op_tab     dq s_op_eq2, 1, s_op_eq1, 1, s_op_ne, 2, s_op_ne2, 2, s_op_lt, 3, s_op_gt, 4, s_op_le, 5, s_op_ge, 6, 0, 0
demo_sak_text:
    db "rem demo.sak - example script", 10
    db "echo === SAK demo ===", 10
    db "set name=MiniOS", 10
    db "echo Hello, $name!", 10
    db "let i 1", 10
    db "while $i <= 5", 10
    db "  let sq $i * $i", 10
    db "  if $sq > 10 and $i != 5", 10
    db "    echo $i squared = $sq (big)", 10
    db "  elif $sq == 25", 10
    db "    echo $i squared = $sq (five!)", 10
    db "  else", 10
    db "    echo $i squared = $sq", 10
    db "  end", 10
    db "  let i $i + 1", 10
    db "end", 10
    db "if exists demo.sak", 10
    db "  echo file demo.sak exists", 10
    db "end", 10
    db "set x=3", 10
    db "if not $x == 3", 10
    db "  echo x is not 3", 10
    db "else", 10
    db "  echo x is 3", 10
    db "end", 10
    db "echo Random number: $RANDOM", 10
    db "echo Done. Current time:", 10
    db "date", 10
demo_sak_end:

align 8
help_tab:
    dq hn_0_0, ht_0
    dq hn_1_0, ht_1
    dq hn_1_1, ht_1
    dq hn_2_0, ht_2
    dq hn_3_0, ht_3
    dq hn_4_0, ht_4
    dq hn_5_0, ht_5
    dq hn_6_0, ht_6
    dq hn_7_0, ht_7
    dq hn_8_0, ht_8
    dq hn_9_0, ht_9
    dq hn_10_0, ht_10
    dq hn_11_0, ht_11
    dq hn_11_1, ht_11
    dq hn_12_0, ht_12
    dq hn_12_1, ht_12
    dq hn_13_0, ht_13
    dq hn_14_0, ht_14
    dq hn_14_1, ht_14
    dq hn_14_2, ht_14
    dq hn_15_0, ht_15
    dq hn_16_0, ht_16
    dq hn_16_1, ht_16
    dq hn_17_0, ht_17
    dq hn_17_1, ht_17
    dq hn_18_0, ht_18
    dq hn_19_0, ht_19
    dq hn_20_0, ht_20
    dq hn_21_0, ht_21
    dq hn_22_0, ht_22
    dq hn_23_0, ht_23
    dq hn_24_0, ht_24
    dq hn_24_1, ht_24
    dq hn_24_2, ht_24
    dq hn_25_0, ht_25
    dq hn_26_0, ht_26
    dq hn_27_0, ht_27
    dq hn_28_0, ht_28
    dq hn_29_0, ht_29
    dq hn_30_0, ht_30
    dq hn_31_0, ht_31
    dq hn_32_0, ht_32
    dq hn_33_0, ht_33
    dq hn_34_0, ht_34
    dq hn_35_0, ht_35
    dq hn_36_0, ht_36
    dq hn_37_0, ht_37
    dq hn_38_0, ht_38
    dq hn_39_0, ht_39
    dq hn_40_0, ht_40
    dq hn_41_0, ht_41
    dq hn_42_0, ht_42
    dq hn_43_0, ht_43
    dq hn_43_1, ht_43
    dq hn_44_0, ht_44
    dq hn_45_0, ht_45
    dq hn_46_0, ht_46
    dq hn_47_0, ht_47
    dq hn_48_0, ht_48
    dq hn_48_1, ht_48
    dq hn_49_0, ht_49
    dq hn_50_0, ht_50
    dq hn_50_1, ht_50
    dq hn_50_2, ht_50
    dq hn_50_3, ht_50
    dq hn_51_0, ht_51
    dq hn_52_0, ht_52
    dq hn_53_0, ht_53
    dq hn_54_0, ht_54
    dq hn_55_0, ht_55
    dq hn_55_1, ht_55
    dq hn_55_2, ht_55
    dq hn_56_0, ht_56
    dq hn_n0_0, ht_n0
    dq hn_n0_1, ht_n0
    dq hn_n0_2, ht_n0
    dq hn_n0_3, ht_n0
    dq hn_n0_4, ht_n0
    dq hn_n0_5, ht_n0
    dq hn_n0_6, ht_n0
    dq hn_n0_7, ht_n0
    dq hn_n0_8, ht_n0
    dq hn_n0_9, ht_n0
    dq hn_n0_10, ht_n0
    dq hn_n0_11, ht_n0
    dq hn_n0_12, ht_n0
    dq hn_n0_13, ht_n0
    dq hn_n0_14, ht_n0
    dq hn_n1_0, ht_n1
    dq hn_n1_1, ht_n1
    dq hn_n1_2, ht_n1
    dq hn_p0_0, ht_p0
    dq hn_p0_1, ht_p0
    dq hn_p0_2, ht_p0
    dq hn_p0_3, ht_p0
    dq hn_p0_4, ht_p0
    dq hn_p0_5, ht_p0
    dq hn_p0_6, ht_p0
    dq hn_p0_7, ht_p0
    dq hn_p0_8, ht_p0
    dq hn_p0_9, ht_p0
    dq hn_p0_10, ht_p0
    dq hn_p0_11, ht_p0
    dq 0, 0
ht_0 db "help [команда] - справка.", 10, "Темы: sak, cond, vars, redirect, keys, dirs", 0
hn_0_0 db "help", 0
ht_1 db "clear (cls) - очистить экран", 0
hn_1_0 db "clear", 0
hn_1_1 db "cls", 0
ht_2 db "echo текст - вывести текст ($имя подставит переменную)", 10, "echo привет > f.txt  - записать вывод в файл", 10, "echo ещё >> f.txt    - дописать в конец", 0
hn_2_0 db "echo", 0
ht_3 db "layout en|ru - раскладка клавиатуры (Alt+Shift тоже переключает)", 0
hn_3_0 db "layout", 0
ht_4 db "reboot - сохранить диск и перезагрузить", 0
hn_4_0 db "reboot", 0
ht_5 db "shutdown - сохранить диск и выключить (QEMU/Bochs)", 0
hn_5_0 db "shutdown", 0
ht_6 db "ver - версия системы", 0
hn_6_0 db "ver", 0
ht_7 db "uptime - число тиков таймера (1000 тиков = 1 секунда)", 0
hn_7_0 db "uptime", 0
ht_8 db "background N - цвет фона 0-9", 10, "0 чёрный 1 белый 2 красный 3 зелёный 4 синий", 10, "5 голубой 6 жёлтый 7 лиловый 8 серый 9 оранжевый", 0
hn_8_0 db "background", 0
ht_9 db "color N - цвет текста 0-9 (палитра как у background)", 0
hn_9_0 db "color", 0
ht_10 db "font 8|16|32 - размер шрифта консоли (масштаб шрифта 8x8)", 0
hn_10_0 db "font", 0
ht_11 db "ls (dir) - файлы и папки текущей папки, папки со знаком /", 0
hn_11_0 db "ls", 0
hn_11_1 db "dir", 0
ht_12 db "cat файл - показать содержимое файла (до 4096 байт)", 0
hn_12_0 db "cat", 0
hn_12_1 db "type", 0
ht_13 db "touch файл - создать пустой файл", 0
hn_13_0 db "touch", 0
ht_14 db "rm имя - удалить файл или пустую папку (del, rmdir - то же)", 0
hn_14_0 db "rm", 0
hn_14_1 db "del", 0
hn_14_2 db "rmdir", 0
ht_15 db "hex файл - показать первые 128 байт в 16-ричном виде", 0
hn_15_0 db "hex", 0
ht_16 db "cp источник цель - копировать файл в текущей папке", 0
hn_16_0 db "cp", 0
hn_16_1 db "copy", 0
ht_17 db "mv старое новое - переименовать", 10, "mv файл папка - переместить файл в папку", 0
hn_17_0 db "mv", 0
hn_17_1 db "ren", 0
ht_18 db "write файл текст - записать текст в файл (перезапись)", 10, "Для многих строк: edit, append или >>", 0
hn_18_0 db "write", 0
ht_19 db "append файл текст - дописать строку в конец файла (с переводом строки)", 0
hn_19_0 db "append", 0
ht_20 db "edit файл - полноэкранный редактор, открывает файл целиком", 10, "Стрелки, Home, End, Delete, Backspace, Enter - новая строка", 10, "Esc - меню: Enter или y - сохранить, n - выйти без сохранения", 10, "Другая клавиша - вернуться к правке. Файл до 4000 байт", 0
hn_20_0 db "edit", 0
ht_21 db "stat файл - размер, блоки, тип (3 = папка)", 0
hn_21_0 db "stat", 0
ht_22 db "df - занято файлов и блоков диска", 0
hn_22_0 db "df", 0
ht_23 db "mkdir имя - создать папку в текущей папке", 0
hn_23_0 db "mkdir", 0
ht_24 db "cd путь - сменить папку: cd a, cd a/b, cd .., cd /", 10, "pwd - показать текущий путь. Путь виден в приглашении.", 10, "Команды работают с файлами текущей папки.", 0
hn_24_0 db "cd", 0
hn_24_1 db "pwd", 0
hn_24_2 db "dirs", 0
ht_25 db "sfnew файл [exec] - создать SF файл (exec - исполняемый)", 0
hn_25_0 db "sfnew", 0
ht_26 db "sfinfo файл - показать заголовок SF файла", 0
hn_26_0 db "sfinfo", 0
ht_27 db "sfwrite файл текст - записать текст в SF файл", 0
hn_27_0 db "sfwrite", 0
ht_28 db "sfhello файл - создать SF программу Hello", 0
hn_28_0 db "sfhello", 0
ht_29 db "mkprog файл - создать SF программу 'Привет мир'", 0
hn_29_0 db "mkprog", 0
ht_30 db "run файл - запустить SF исполняемый файл", 0
hn_30_0 db "run", 0
ht_31 db "sync - записать файловую систему на диск", 0
hn_31_0 db "sync", 0
ht_32 db "format - ОЧИСТИТЬ файловую систему", 0
hn_32_0 db "format", 0
ht_33 db "gui - графический рабочий стол: окна, мышь, Paint, Calc, Files", 10, "Esc - выход, w - смена обоев", 0
hn_33_0 db "gui", 0
ht_34 db "mem - использование кучи ядра", 0
hn_34_0 db "mem", 0
ht_35 db "date - дата и время из часов CMOS", 0
hn_35_0 db "date", 0
ht_36 db "cpuid - производитель и название процессора", 0
hn_36_0 db "cpuid", 0
ht_37 db "calc a op b - целые числа, op: + - * / %", 10, "например: calc 17 % 5", 0
hn_37_0 db "calc", 0
ht_38 db "rand [n] - случайное число от 0 до n-1 (по умолчанию 100)", 0
hn_38_0 db "rand", 0
ht_39 db "sleep мс - пауза в миллисекундах", 0
hn_39_0 db "sleep", 0
ht_40 db "beep - короткий сигнал динамика", 0
hn_40_0 db "beep", 0
ht_41 db "set имя=значение - задать переменную. set без аргументов - список", 10, "Использование: echo $имя", 10, "Аргументы скрипта: $1 ... $9", 0
hn_41_0 db "set", 0
ht_42 db "unset имя - удалить переменную", 0
hn_42_0 db "unset", 0
ht_43 db "vars - список переменных (макс. 32)", 10, "Переменные: set x=5, let x $x + 1, input x", 10, "Подстановка: $x. Особые: $RANDOM $TICKS $1..$9", 0
hn_43_0 db "vars", 0
hn_43_1 db "variables", 0
ht_44 db "let имя a op b - вычислить и записать в переменную", 10, "let n 5 / let n $n + 1 / let r $a % 3", 10, "op: + - * / %", 0
hn_44_0 db "let", 0
ht_45 db "input имя [подсказка] - ввести строку с клавиатуры в переменную", 0
hn_45_0 db "input", 0
ht_46 db "pause - ждать нажатия клавиши", 0
hn_46_0 db "pause", 0
ht_47 db "rem текст - комментарий (также строки с # или ::метка)", 0
hn_47_0 db "rem", 0
ht_48 db "sak файл.sak [арг...] - выполнить скрипт", 10, "Можно просто набрать имя: demo (или demo.sak)", 10, "sakdemo - создать пример demo.sak", 10, "Язык: set let input echo + if elif else end while goto exit rem", 10, "Подробнее: help cond, help variables, help redirect", 10, "Esc прерывает скрипт. Вложенный sak не поддерживается.", 0
hn_48_0 db "sak", 0
hn_48_1 db "scripts", 0
ht_49 db "sakdemo - создать пример скрипта demo.sak и запусти его: demo", 0
hn_49_0 db "sakdemo", 0
ht_50 db "if условие / elif условие / else / end", 10, "Пример:", 10, "if $x > 5 and exists a.txt", 10, "  echo ok", 10, "elif $x == 5", 10, "  echo five", 10, "else", 10, "  echo small", 10, "end", 10, "Условия: help cond", 0
hn_50_0 db "if", 0
hn_50_1 db "elif", 0
hn_50_2 db "else", 0
hn_50_3 db "end", 0
ht_51 db "while условие ... end - цикл", 10, "Пример: let i 0 / while $i < 3 / echo $i / let i $i + 1 / end", 0
hn_51_0 db "while", 0
ht_52 db "goto метка - перейти на строку :метка (только на верхнем уровне)", 0
hn_52_0 db "goto", 0
ht_53 db "exit - завершить скрипт", 0
hn_53_0 db "exit", 0
ht_54 db "Условия: A op B, где op: == != < > <= >= (= и <> тоже)", 10, "Если оба числа - сравнение числовое, иначе строковое", 10, "exists файл - файл есть в папке", 10, "not X - отрицание, X and Y, X or Y (также && ||)", 10, "Просто A - истина, если A не пусто и не 0", 0
hn_54_0 db "cond", 0
ht_55 db "команда > файл - записать вывод команды в файл", 10, "команда >> файл - дописать вывод в конец файла", 10, "Работает для любых команд (ls, date, cat...)", 0
hn_55_0 db "redirect", 0
hn_55_1 db ">", 0
hn_55_2 db ">>", 0
ht_56 db "Лево/право, Home, End, Delete, Backspace - правка строки команды", 10, "Стрелка вверх - предыдущая команда, Alt+Shift - раскладка", 10, "Esc - прервать скрипт / выйти из gui, md, edit", 0
hn_56_0 db "keys", 0

ht_n0 db "Графика (в консоли и в .sak). Координаты в пикселях.", 10, "Цвет: 0-9 палитра, #RRGGBB или число.", 10, "gcls [цвет] | gpix x y цвет | gline x1 y1 x2 y2 цвет", 10, "grect x y w h цвет (рамка) | gfill x y w h цвет (залитый)", 10, "gcirc x y r цвет (окружность) | gdisc x y r цвет (круг)", 10, "gtext x y цвет текст | gscale 1|2|4 - размер текста", 10, "gwait - ждать клавишу и вернуться | gend - вернуться сразу", 10, "Анимация: gauto 0 - не показывать до gflip, gkey v - код клавиши в $v", 10, "Коды: стрелки 1 2 3 4, Esc 27, Enter 10. После скрипта экран держится до клавиши.", 0
hn_n0_0 db "gfx", 0
hn_n0_1 db "gcls", 0
hn_n0_2 db "gpix", 0
hn_n0_3 db "gline", 0
hn_n0_4 db "grect", 0
hn_n0_5 db "gfill", 0
hn_n0_6 db "gcirc", 0
hn_n0_7 db "gdisc", 0
hn_n0_8 db "gtext", 0
hn_n0_9 db "gscale", 0
hn_n0_10 db "gwait", 0
hn_n0_11 db "gend", 0
hn_n0_12 db "gauto", 0
hn_n0_13 db "gflip", 0
hn_n0_14 db "gkey", 0
ht_n1 db "md файл - просмотр Markdown в графическом режиме", 10, "# ## ### заголовки, - * + списки, > цитаты, --- линия", 10, "**жирный** *курсив* `код` [текст](ссылка) и блоки ``` ```", 10, "Управление: стрелки, PgUp/PgDn, Home/End, Esc или q - выход", 10, "mddemo - создать пример demo.md. Файлы пишите латиницей или CP1251.", 0
hn_n1_0 db "md", 0
hn_n1_1 db "markdown", 0
hn_n1_2 db "mddemo", 0

ht_p0 db "Цепочки: a ; b - по очереди. a && b - b только если a успешна.", 10, "a || b - b только если a не удалась. Можно смешивать: a && b || c", 10, "Статус последней команды: $? (0 - успех, 1 - ошибка), работает и в .sak", 10, "Префиксы команды (можно сочетать):", 10, "  @cmd - тихо, без вывода       -cmd - игнорировать ошибку", 10, "  !cmd - инвертировать статус   +cmd - показать время выполнения", 10, "  *N cmd - повторить N раз (до 10000)", 10, "Примеры: *3 echo hi   -rm tmp && echo ok   @date > t.txt   +sleep 500", 10, "Знак ; и && || внутри текста echo тоже разделяют команды.", 0
hn_p0_0 db "prefix", 0
hn_p0_1 db "chain", 0
hn_p0_2 db "operators", 0
hn_p0_3 db "&&", 0
hn_p0_4 db "||", 0
hn_p0_5 db ";", 0
hn_p0_6 db "@", 0
hn_p0_7 db "!", 0
hn_p0_8 db "+", 0
hn_p0_9 db "*", 0
hn_p0_10 db "-", 0
hn_p0_11 db "status", 0

align 16
sf_hello_code:
    mov rdi, sf_hello_msg
    mov rax, con_puts
    call rax
    mov edi, 10
    mov rax, con_putc
    call rax
    ret
sf_hello_code_end:
sf_hello_msg: db "Hello from SF!", 0

align 16
prog_hi_code:
    mov edi, prog_hi_msg
    mov rax, con_puts_utf8
    call rax
    mov edi, 10
    mov rax, con_putc
    call rax
    ret
prog_hi_code_end:
prog_hi_msg:
    db "Привет мир!", 0

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
    db 0xFF,0xF7,0xF1,0xEC,0xE8,0xF2,0xFC,0xE1,0xFE,0x2E
    db 0, '*'
    db 0, ' '
    times 70 db 0


align 16
shift_us:
    db 0x00,0x1B,0x21,0x40,0x23,0x24,0x25,0x5E,0x26,0x2A,0x28,0x29,0x5F,0x2B,0x08,0x09
    db 0x51,0x57,0x45,0x52,0x54,0x59,0x55,0x49,0x4F,0x50,0x7B,0x7D,0x0A,0x00,0x41,0x53
    db 0x44,0x46,0x47,0x48,0x4A,0x4B,0x4C,0x3A,0x22,0x7E,0x00,0x7C,0x5A,0x58,0x43,0x56
    db 0x42,0x4E,0x4D,0x3C,0x3E,0x3F,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

align 16
shift_ru:
    db 0x00,0x1B,0x21,0x22,0xB9,0x3B,0x25,0x3A,0x3F,0x2A,0x28,0x29,0x5F,0x2B,0x08,0x09
    db 0xC9,0xD6,0xD3,0xCA,0xC5,0xCD,0xC3,0xD8,0xD9,0xC7,0xD5,0xDA,0x0A,0x00,0xD4,0xDB
    db 0xC2,0xC0,0xCF,0xD0,0xCE,0xCB,0xC4,0xC6,0xDD,0xA8,0x00,0x2F,0xDF,0xD7,0xD1,0xCC
    db 0xC8,0xD2,0xDC,0xC1,0xDE,0x2C,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

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
    db 0x8A,0xCD,0xAA,0x98,0x88,0x88,0x88,0x00
    times 48 db 0
    db 0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00
    db 0x7E,0x60,0x60,0x7C,0x66,0x66,0x7C,0x00
    db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00
    db 0x7E,0x60,0x60,0x60,0x60,0x60,0x60,0x00
    db 0x1E,0x36,0x66,0x66,0x66,0x66,0xFF,0xC3
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00
    db 0xDB,0xDB,0x7E,0x18,0x7E,0xDB,0xDB,0x00
    db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00
    db 0x66,0x66,0x6E,0x7E,0x76,0x66,0x66,0x00
    db 0x24,0x66,0x6E,0x7E,0x76,0x66,0x66,0x00
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
    db 0xC3,0xC3,0xC3,0xF3,0xCB,0xCB,0xF3,0x00
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
    db 0x24,0x00,0x66,0x6E,0x7E,0x76,0x66,0x00
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
    db 0x00,0x00,0xC3,0xF3,0xCB,0xCB,0xF3,0x00
    db 0x00,0x00,0x60,0x60,0x7C,0x66,0x7C,0x00
    db 0x00,0x00,0x3C,0x66,0x1E,0x66,0x3C,0x00
    db 0x00,0x00,0xC3,0xDB,0xFF,0xFF,0xC3,0x00
    db 0x00,0x00,0x3E,0x66,0x3E,0x36,0x66,0x00

%include "asm\gui.asm"

section .bss
align 16
bss_zero_start:
fs_cwd       resq 1
cap_on       resq 1
cap_len      resq 1
sak_len      resq 1
sak_pc       resq 1
sak_sp       resq 1
sak_ls       resq 1
sak_enter    resq 1
sak_active   resq 1
sak_abort    resq 1
cond_ptr     resq 1
tmp_ptr      resq 1
shell_pos    resq 1
ed_len       resq 1
ed_pos       resq 1
ed_top       resq 1
ed_cx        resq 1
ed_cy        resq 1
ed_found     resq 1
ed_mod       resq 1
gfx_active   resq 1
gfx_manual   resq 1
g_save_scale resq 1
g_save_adv   resq 1
md_len       resq 1
md_scroll    resq 1
md_total     resq 1
md_x         resq 1
md_y         resq 1
md_indent    resq 1
md_scale     resq 1
md_color     resq 1
md_bold      resq 1
md_ital      resq 1
md_code      resq 1
md_link      resq 1
md_fence     resq 1
garg         resq 8
last_status  resq 1
chain_depth  resq 1
sak_stack    resb 256
var_tab      resb 2048
bss_zero_end:
sak_buf      resb 8200
line_buf     resb 264
exp_buf      resb 540
tok_a        resb 56
tok_b        resb 56
tok_op       resb 56
in_buf       resb 264
cap_buf      resb 4104
cap_out      resb 8200
rd_buf       resb 4104
edit_buf     resb 4104
path_buf     resb 264
name_tmp     resb 64
chain_bufs   resb 1100
