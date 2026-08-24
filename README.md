# VBE Bootloader with Protected Mode Graphics

## Overview

This is a **x86 real-mode bootloader** that sets up a **VBE (VESA BIOS Extensions)** graphics mode, switches to **32-bit protected mode**, and displays a custom logo using a bitmap font. It is designed to be loaded from a boot sector or as a second-stage bootloader at `0x7E00`.

---

## Features

- **VBE Mode Detection**: Scans available video modes and selects:
  - 1920×1080 resolution
  - 32-bit color depth
  - Linear framebuffer support
- **Protected Mode Switch**: Enables 32-bit addressing via:
  - A20 line enable
  - Global Descriptor Table (GDT) with flat 4GB segments
  - Far jump to protected mode
- **Graphical Output**:
  - Fills the screen with a solid color
  - Renders an "OS name" string using a custom bitmap font (12×12 pixels)
- **Error Handling**: Prints VBE error messages in real mode before switching.

---

## Memory Layout

| Address Range       | Usage                          |
|---------------------|--------------------------------|
| `0x7E00`            | Bootloader entry point         |
| `0x500`             | VBE info block                |
| `0x8000`            | Mode info block               |
| `0x90000`           | Stack in protected mode       |
| Framebuffer (VBE)   | Linear framebuffer (set by VBE) |

---

## Build Instructions

### Prerequisites
- **NASM** (Netwide Assembler)
- **QEMU** (for testing) or a real machine with VBE support

### Assembling
```bash
nasm -f bin boot.asm -o boot.bin
```

### Creating a Bootable Image
If booting from a floppy/disk image:
```bash
dd if=/dev/zero of=disk.img bs=512 count=2880
dd if=boot.bin of=disk.img conv=notrunc
```

### Testing with QEMU
```bash
qemu-system-x86_64 -drive format=raw,file=disk.img -vga std
```
> **Note:** `-vga std` ensures VBE support. Some VGA modes may not work with all chipsets.

---

## Code Structure

| Section                 | Description                                       |
|-------------------------|---------------------------------------------------|
| **Real Mode Entry**     | Sets up segments, prints messages, calls VBE     |
| **VBE Mode Selection**  | Scans modes, validates resolution/color depth    |
| **A20 Enable**          | Enables high memory access                        |
| **GDT Setup**           | Flat 32-bit code/data segments                   |
| **Protected Mode Jump** | Far jump to `0x08:protected_mode_start`          |
| **32-bit Graphics**     | Fills framebuffer and draws logo via bitmap font |
| **Font Data**           | Bitmap font for letters `A-Z`, digits, symbols   |

---

## Font & Logo

The font is a **12×12 pixel bitmap** stored in a custom format:
- Each character begins with an ID byte (e.g., `2` for `'0'`, `43` for `'A'`)
- Followed by 12 rows of 12 pixels (each pixel = 1 byte, `0x1F` = on, `0x00` = off)
- Rows are terminated by `0x0B`, characters by `0x0F`

The logo string is defined as:
```asm
msg_OSname: db 65, 43, 55, 67, 64, 43, 0   ; "ABOUTUS" (or similar)
```
Characters are mapped to their font IDs (e.g., `65` = `'A'`, `43` = `'B'`).

---

## Customization

### Changing Resolution
Modify these lines in `find_mode`:
```asm
cmp word [mode_info + 0x12], 1920   ; Width
cmp word [mode_info + 0x14], 1080   ; Height
cmp byte [mode_info + 0x19], 32     ; BPP
```

### Changing Logo
1. Edit `msg_OSname` with new character IDs (see `letter` table).
2. Ensure corresponding font data exists or add new glyphs.

### Changing Colors
- Background fill color: `mov eax, 0x00fff5ff` (ABGR format)
- Font color: `mov dword [edi], 0x00ff1fff` (ABGR)

---

## Notes & Limitations

- **VBE Support**: Requires a VBE 2.0+ BIOS. May not work in all emulators without `-vga std`.
- **Font Format**: The font is embedded as raw byte data, making it easy to replace but not compressed.
- **Stack**: Protected mode stack is at `0x90000` (adjustable).
- **No File System**: This is a flat binary; intended for floppy/disk boot.

---

## Debugging

If the screen stays blank:
1. Check VBE error message output (if in real mode).
2. Ensure the framebuffer address is valid.
3. Verify GDT and protected mode transition with a debugger (e.g., QEMU `-s -S`).

---

## License

GPLV3

---

## Author

Written as a low-level x86 bootloader experiment. Contributions and improvements are welcome!

## Developers

OS was made by:
MatvikCoder, Pushok (The Senost) and with 5 cups of tea!
