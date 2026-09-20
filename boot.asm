[bits 16]
org 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov si, qestion_msg
    call print
    jmp .12
.12:
    mov ah, 00h
    int 0x16
    cmp al, '1'
    je .ifdos
    cmp al, '2'
    je .ifos
    jmp .12
.ifdos:
    mov ah, 0x02
    mov al, 2
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0x80
    mov bx, 0x7f00
    int 0x13
    cli
    jc error

    jmp 0x0000:0x7f00
.ifos:
    mov ah, 0x02
    mov al, 40
    mov ch, 0
    mov cl, 4
    mov dh, 0
    mov dl, 0x80
    mov bx, 0x7E00
    int 0x13
    cli
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
qestion_msg db "1 dos / 2 OS", 13, 10, 0
times 510 - ($ - $$) db 0
dw 0xAA55
