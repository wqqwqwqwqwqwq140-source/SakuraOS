[bits 16]
org 0x7E00

start:
    cli

    ; ------------------------------------------
    ; Сегменты
    ; ------------------------------------------

    xor ax, ax
    mov ds, ax
    mov es, ax


    ; ------------------------------------------
    ; Сообщение
    ; ------------------------------------------

    mov si, msg
    call print


    ; ==========================================
    ; VBE 4F00
    ; Получаем информацию о VBE
    ; ==========================================

    mov ax, 0x4F00
    mov di, vbe_info

    mov dword [es:di], 'VBE2'

    int 0x10

    cmp ax, 0x004F
    jne vbe_error


    ; ==========================================
    ; Получаем VideoModePtr
    ; ==========================================

    mov si, [vbe_info + 0x0E]
    mov ax, [vbe_info + 0x10]

    mov [mode_list_offset], si
    mov [mode_list_segment], ax


    ; ==========================================
    ; Ищем 1024x768x32
    ; ==========================================

    call find_mode

    jc vbe_error


    ; ==========================================
    ; Включаем найденный VBE режим
    ; ==========================================

    mov ax, 0x4F02

    mov bx, [vbe_mode]

    ; Bit 14 = Linear Framebuffer
    or bx, 0x4000

    int 0x10

    cmp ax, 0x004F
    jne vbe_error


    ; ==========================================
    ; VBE включён
    ; Теперь Protected Mode
    ; ==========================================


    ; ------------------------------------------
    ; A20
    ; ------------------------------------------

    in al, 0x92
    or al, 2
    out 0x92, al


    ; ------------------------------------------
    ; GDT
    ; ------------------------------------------

    lgdt [gdt_descriptor]


    ; ------------------------------------------
    ; Protected Mode
    ; ------------------------------------------

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump
    jmp 0x08:protected_mode_start


; =================================================
; 32-BIT PROTECTED MODE
; =================================================

[bits 32]

protected_mode_start:

    ; Data selector = 0x10
    mov ax, 0x10

    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Stack
    mov esp, 0x90000


    ; ==========================================
    ; Я устал комментировать (засуньте меня в топ 1 либо заплатите)
    ; ==========================================

    mov edi, [framebuffer]
    mov ecx, 4608000        

    mov eax, 0x05fff4ff
    mov ecx, 0
.fill:
    mov dword [edi+ecx], eax
    cmp ecx, 8294400
    je .hang 
    add ecx, 4
    jmp .fill
    

    ; ==========================================
    ; Готово
    ; ==========================================

.hang:
    cli
    hlt
    jmp .hang


; =================================================
; FIND VBE MODE
; =================================================

[bits 16]

find_mode:

    ; ES:SI = список VBE режимов

    mov ax, [mode_list_segment]
    mov es, ax

    mov si, [mode_list_offset]


.next_mode:

    ; CX = номер режима
    mov cx, [es:si]

    ; Конец списка
    cmp cx, 0xFFFF
    je .not_found


    ; Сохраняем номер режима
    push cx


    ; ------------------------------------------
    ; VBE 4F01
    ; Получаем ModeInfoBlock
    ; ------------------------------------------

    xor ax, ax
    mov es, ax

    mov di, mode_info

    mov ax, 0x4F01
    int 0x10

    pop cx


    ; BIOS успешно вернул информацию?
    cmp ax, 0x004F
    jne .next


    ; ------------------------------------------
    ; ModeAttributes
    ; ------------------------------------------

    test word [mode_info], 1
    jz .next


    ; ------------------------------------------
    ; Linear Framebuffer
    ; ------------------------------------------

    test word [mode_info], 0x80
    jz .next


    ; ------------------------------------------
    ; XResolution = 1024
    ; ------------------------------------------

    cmp word [mode_info + 0x12], 1920
    jne .next


    ; ------------------------------------------
    ; YResolution = 768
    ; ------------------------------------------

    cmp word [mode_info + 0x14], 1080
    jne .next


    ; ------------------------------------------
    ; BitsPerPixel = 32
    ; ------------------------------------------

    cmp byte [mode_info + 0x19], 32
    jne .next


    ; ==========================================
    ; НАШЛИ
    ; ==========================================

    mov [vbe_mode], cx

    ; PhysBasePtr
    mov eax, [mode_info + 0x28]
    mov [framebuffer], eax

    ; BytesPerScanLine
    mov ax, [mode_info + 0x10]
    mov [pitch], ax

    clc
    ret


.next:

    ; Возвращаем ES:SI к списку режимов

    mov ax, [mode_list_segment]
    mov es, ax

    add si, 2

    jmp .next_mode


.not_found:

    stc
    ret



; =================================================
; PRINT
; =================================================

print:

    mov ah, 0x0E
    cld

.print_loop:

    lodsb

    test al, al
    jz .done

    int 0x10

    jmp .print_loop

.done:
    ret



; =================================================
; VBE ERROR
; =================================================

vbe_error:

    mov si, msg_vbe
    call print

    cli

.error_hang:
    hlt
    jmp .error_hang



; =================================================
; GDT
; =================================================

gdt_start:

    ; ------------------------------------------
    ; 0x00 NULL
    ; ------------------------------------------

    dq 0


    ; ------------------------------------------
    ; 0x08 CODE
    ; Base  = 0
    ; Limit = 4 GB
    ; 32-bit
    ; ------------------------------------------

    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00


    ; ------------------------------------------
    ; 0x10 DATA
    ; Base  = 0
    ; Limit = 4 GB
    ; 32-bit
    ; ------------------------------------------

    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00


gdt_end:


gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start



; =================================================
; DATA
; =================================================

msg:
    db "VBE boot...", 13, 10, 0

msg_vbe:
    db "VBE ERROR!", 13, 10, 0


; VBE InfoBlock
vbe_info:
    times 512 db 0


; ModeInfoBlock
mode_info:
    times 256 db 0


; VBE mode list pointer
mode_list_offset:
    dw 0

mode_list_segment:
    dw 0


; Найденный режим
vbe_mode:
    dw 0


; Linear framebuffer
framebuffer:
    dd 0


; BytesPerScanLine
pitch:
    dw 0


; =================================================
; PADDING
; =================================================

times 4096 - ($ - $$) db 0