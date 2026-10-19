bits 64
org 0x2000000

%define BOOT_INFO_FB      0
%define BOOT_INFO_WIDTH   8
%define BOOT_INFO_HEIGHT  12
%define BOOT_INFO_PITCH   16

kernel_entry:
    ; Сохраним boot_info
    mov rbx, rdi
    mov rsp, stack_top
    mov rbp, rsp

    ; Загрузим параметры
    mov rdi, [rbx + BOOT_INFO_FB]      ; fb_base
    mov esi, [rbx + BOOT_INFO_WIDTH]   ; width  (пикселей)
    mov edx, [rbx + BOOT_INFO_HEIGHT]  ; height (пикселей)
    mov ecx, [rbx + BOOT_INFO_PITCH]   ; pitch  (байт на строку)

    mov [abs framebuffer], rdi
    mov [abs width],  esi
    mov [abs height], edx
    mov [abs pitch],  ecx

    imul ecx, edx
    movsxd rcx, ecx
    mov r8d, 0x00ffffff
    sub  rcx, 4
    jmp .fillscreen
.fillscreen:
    cmp rcx, 0
    je cleanoperate
    mov dword [rdi+rcx], r8d
    sub rcx, 4
    jmp .fillscreen
cleanoperate:
    mov r8, 0x1000000
    mov r9, 0x2000000
    call clean
system:
; умный я ? р8 = шириа р9 = высота rdi= арес еакс цвет, а смысл это наоборот усложняет, проще высичлить смщение тогда просто? нет смысла нет
;хотя для печати квадрата пригодится, урУАИРУабцруоашглцрлфг пиксель рисуется теперь че функцию линию регтангле?? фС???!??№:?!№?!:№?*:Щ:;*?"!:;!2
; пусть создатели дистрибутивов на мою ядро сами делают это
; а я как умный мальчик... (тупой), мхмхммхмххмхммхммхммхмхмхмх даже не знаю ххммхм
; ааа шрифт?
; ну да, оххх еще прерывания, ну может сделать проще щас будет
; хотя квдрат проще
sqare:
;r8 = x start r9 = y start эээ r10 = sizex rcx =sizey eax = калор
    mov r11, [abs pitch]
    mov rdi. [abs framebuffer]
    imul r9, r11
    mov r12, r9
    shl r8, 2
    add r9, r8
.sqareloop
    mov dword [rdi+r9]
    
pixel:
    mov  rdi, [abs framebuffer]
    mov  r10, [abs pitch]
    imul r9, r10
    lea  r8, [r8*4]
    add  r9, r8
    mov  dword [rdi + r9], eax
    ret

clean:
    cmp r8, 0x1000000
    jb .end
    cmp r8, r9
    jb .what
    jmp .end
.what:
    test r8, 3
    jz .cleanloop
    jmp .end
.cleanloop:
    mov qword [r8], 0x00000000
    cmp r8, r9
    jae .end
    add r8, 4
    jmp .cleanloop
.end:
    ret
hang:
    cli
    hlt
    jmp $  
framebuffer     dq 0
width           dq 0
height          dq 0
pitch           dq 0
align 16
stack_bottom:
    resb 65536              ; 64 КБ стека
stack_top:
