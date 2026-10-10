bits 64
org 0x2000000
%define BOOT_INFO_FB      0
%define BOOT_INFO_WIDTH   8
%define BOOT_INFO_HEIGHT  12
%define BOOT_INFO_PITCH   16

kernel_entry:
    ; Сохраним boot_info
    mov rbx, rdi

    ; Загрузим параметры
    mov rdi, [rbx + BOOT_INFO_FB]      ; fb_base
    mov esi, [rbx + BOOT_INFO_WIDTH]   ; width
    mov edx, [rbx + BOOT_INFO_HEIGHT]  ; height
    mov ecx, [rbx + BOOT_INFO_PITCH]   ; pitch 
    shr ecx, 2                          ; pitch / 4 = пикселей на строку
    mov [framebuffer], rdi
    mov [width],       esi
    mov [height],      edi
    mov [pitch],       ecx
    ; Цвет: 0x00RRGGBB 
    mov eax, 0x00ffffff
    xor r8d, r8d                       
.y_loop:
    cmp r8d, edx
    jge .done

    xor r9d, r9d
    mov r10d, r8d
    imul r10d, ecx
.x_loop:
    cmp r9d, esi
    jge .next_y

    mov r11d, r10d
    add r11d, r9d                       ; r11d = y*pitch_px + x
    mov [rdi + r11*4], eax              ; pixels[r11] = color

    inc r9d
    jmp .x_loop

.next_y:
    inc r8d
    jmp .y_loop

.done:
.hang:
    hlt
    jmp .hang
pitch       dd 0
height      dd 0
width       dd 0
framebuffer dd 0
