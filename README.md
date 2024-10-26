# libretro_test_gl_shaders.zig
This sample demonstrates a libretro core using programmable pipeline OpenGL (GL 2.0 and later / OpenGL ES 2.0). It works on both desktop (OpenGL 2.0 and later) and mobile (OpenGL ES 2.0 and later)

## Requirements
On the desktop - A graphics card driver supporting OpenGL 2.0 and/or higher.

On mobile      - A graphics card driver supporting OpenGL ES 2.0 and/or higher.

## Programming language
Zig

## Building
To compile, you will need a Zig compiler and assorted toolchain installed.

    $ zig build --release

This targets [libretro](http://libretro.com) GL interface, so you need a libretro frontend supporting this interface, such as [RetroArch](https://github.com/libretro/RetroArch), installed.

## Running
After building, this command should run the program:

    $ retroarch -L zig-out/*retro_test_gl_shaders.*
