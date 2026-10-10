#include <efi.h>
#include <efilib.h>

// Куда грузим ядро
#define KERNEL_ADDR   0x2000000ULL
#define KERNEL_MAX    0x1000000ULL   // макс 16 МБ

// Куда пишем boot_info (ядро прочитает отсюда)
#define BOOT_INFO_ADDR 0x7000ULL

struct boot_info {
    UINT64 fb_base;
    UINT32 width;
    UINT32 height;
    UINT32 pitch;
    UINT32 pixel_format;
    UINT64 kernel_size;
} __attribute__((packed));

EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
{
    InitializeLib(ImageHandle, SystemTable);
    Print(L"UEFI Bootloader v2\r\n");

    // --- 1. Найти GOP ---
    EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;
    EFI_STATUS s = uefi_call_wrapper(BS->LocateProtocol, 3, &gop_guid, NULL, (void**)&gop);
    if (EFI_ERROR(s) || !gop) {
        Print(L"GOP not found\r\n");
        for(;;) __asm__ volatile("hlt");
    }

    UINT64 fb     = gop->Mode->FrameBufferBase;
    UINT32 width  = gop->Mode->Info->HorizontalResolution;
    UINT32 height = gop->Mode->Info->VerticalResolution;
    UINT32 pitch  = gop->Mode->Info->PixelsPerScanLine * 4;
    UINT32 fmt    = gop->Mode->Info->PixelFormat;

    Print(L"FB: %dx%d, pitch=%d, base=0x%lx\r\n", width, height, pitch, fb);

    // --- 2. Открыть FAT-раздел, где лежит наш .efi ---
    // --- 2. Найти FAT-раздел через EFI_SIMPLE_FILE_SYSTEM_PROTOCOL ---
    EFI_FILE_HANDLE root = NULL;
    {
        EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
        EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = NULL;
        EFI_HANDLE *handles = NULL;
        UINTN nhandles = 0;

        s = uefi_call_wrapper(BS->LocateHandleBuffer, 5,
                              ByProtocol, &fs_guid, NULL, &nhandles, &handles);
        if (EFI_ERROR(s) || nhandles == 0) {
            Print(L"No FS handles\r\n");
            for(;;) __asm__ volatile("hlt");
        }

        // Пробуем каждый, пока не откроем корень
        for (UINTN i = 0; i < nhandles; i++) {
            s = uefi_call_wrapper(BS->HandleProtocol, 3,
                                  handles[i], &fs_guid, (void**)&fs);
            if (EFI_ERROR(s)) continue;

            s = uefi_call_wrapper(fs->OpenVolume, 2, fs, &root);
            if (!EFI_ERROR(s) && root) {
                Print(L"FS found, handle %d\r\n", i);
                break;
            }
        }

        if (!root) {
            Print(L"Cannot open any FS\r\n");
            for(;;) __asm__ volatile("hlt");
        }
    }

    // --- 3. Открыть kernel.bin ---
    EFI_FILE_HANDLE kfile = NULL;
    s = uefi_call_wrapper(root->Open, 5, root, &kfile,
                          L"kernel.bin", EFI_FILE_MODE_READ, 0);
    if (EFI_ERROR(s) || !kfile) {
        Print(L"kernel.bin not found\r\n");
        for(;;) __asm__ volatile("hlt");
    }

    EFI_FILE_INFO *info = LibFileInfo(kfile);
    UINTN ksize = info->FileSize;
    FreePool(info);

    Print(L"kernel.bin: %d bytes\r\n", ksize);

    if (ksize == 0 || ksize > KERNEL_MAX) {
        Print(L"kernel size invalid\r\n");
        for(;;) __asm__ volatile("hlt");
    }

    // --- 4. Выделить память под ядро и прочитать ---
    EFI_PHYSICAL_ADDRESS kaddr = KERNEL_ADDR;
    s = uefi_call_wrapper(BS->AllocatePages, 4, AllocateAddress,
                          EfiLoaderData, EFI_SIZE_TO_PAGES(ksize), &kaddr);
    if (EFI_ERROR(s)) {
        Print(L"AllocatePages failed (kernel)\r\n");
        for(;;) __asm__ volatile("hlt");
    }

    UINTN read_size = ksize;
    s = uefi_call_wrapper(kfile->Read, 3, kfile, &read_size, (void*)kaddr);
    if (EFI_ERROR(s) || read_size != ksize) {
        Print(L"Read failed: %d of %d\r\n", read_size, ksize);
        for(;;) __asm__ volatile("hlt");
    }
    uefi_call_wrapper(kfile->Close, 1, kfile);

    Print(L"Kernel loaded at 0x%lx\r\n", kaddr);

    // --- 5. Заполнить boot_info ---
    struct boot_info *bi = (struct boot_info *)BOOT_INFO_ADDR;
    bi->fb_base      = fb;
    bi->width        = width;
    bi->height       = height;
    bi->pitch        = pitch;
    bi->pixel_format = fmt;
    bi->kernel_size  = ksize;

    // --- 6. ExitBootServices ---
    UINTN map_size = 0, map_key = 0, desc_size = 0;
    UINT32 desc_ver = 0;
    EFI_MEMORY_DESCRIPTOR *map = NULL;

    uefi_call_wrapper(BS->GetMemoryMap, 5, &map_size, map, &map_key, &desc_size, &desc_ver);
    map_size += 4096;
    s = uefi_call_wrapper(BS->AllocatePool, 3, EfiLoaderData, map_size, (void**)&map);
    if (EFI_ERROR(s)) {
        Print(L"AllocatePool failed\r\n");
        for(;;) __asm__ volatile("hlt");
    }
    uefi_call_wrapper(BS->GetMemoryMap, 5, &map_size, map, &map_key, &desc_size, &desc_ver);

    s = uefi_call_wrapper(BS->ExitBootServices, 2, ImageHandle, map_key);
    if (EFI_ERROR(s)) {
        Print(L"ExitBootServices failed\r\n");
        for(;;) __asm__ volatile("hlt");
    }

    // --- 7. Прыжок в ядро ---
    // RDI = boot_info*
    typedef void (*kernel_t)(struct boot_info *);
    kernel_t kernel = (kernel_t)kaddr;
    kernel(bi);

    // Если ядро вернулось — висим
    for(;;) __asm__ volatile("hlt");
    return EFI_SUCCESS;
}