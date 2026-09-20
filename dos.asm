[bits 16]
org 0x7f00
start:
    sti
    mov cx, 80 * 25
    mov ah, 0x0E
clear:
    cmp cx, 0
    je .end
    mov al, ' '
    int 0x10
    sub cx, 1
    jmp clear
.end:
    cli
    hlt
    jmp $
times 1024 - ($ - $$) db 0