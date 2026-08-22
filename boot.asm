[bits 16]
org 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov ah, 0x02
    mov al, 20
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0x80
    mov bx, 0x7E00
    int 0x13

    jc error

    jmp 0x0000:0x7E00

error:
    mov si, error_msg
    call print
    jmp $

print:
    mov ah, 0x0E
    cld
.print_loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .print_loop
.done:
    ret

error_msg db "Disk read error!", 13, 10, 0

times 510 - ($ - $$) db 0
dw 0xAA55