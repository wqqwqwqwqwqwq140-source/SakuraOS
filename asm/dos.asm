[bits 16]
org 0x7f00
enter_pm:
    in al, 0x92
    or al, 2
    out 0x92, al
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; far jump в 32-битный сегмент кода (0x08)
    jmp 0x08:pm_start

; ============================================================
; GDT
; ============================================================
gdt_start:
    dq 0                        ; null descriptor

    ; 0x08 — код, base=0, limit=4GB, 32-bit
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00

    ; 0x10 — данные, base=0, limit=4GB, 32-bit
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

; ============================================================
; 32-битный код
; ============================================================
[bits 32]
pm_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    ; ── твой 32-битный код здесь ──
    ; например, пишешь в видеопамять 0xB8000
    mov edi, 0xB8000
    mov eax, 0x1E201E20        ; символ ' ' с атрибутом 0x1E
    mov ecx, 80*25
    rep stosd
    mov edi, 0xB8000
    mov ecx, 156
ramka:
    cmp ecx, 0
    je .pm_hang
    mov word [edi+ecx], 0x1ECD
    sub ecx, 2
    jmp ramka
.pm_hang:
    cli
    hlt
    jmp .pm_hang

section .data
color:
    dd 0x1e201e20
dosmode_msg db 'Welcome to SakuraDos!', 13, 10, 0
times 516096 - ($ - $$) - 512 - 124 db 0