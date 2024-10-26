const assert = debug.assert;
const c = @cImport({
    @cInclude("libretro-common/libretro.h");
});
const debug = std.debug;
const fmt = std.fmt;
const gl = @import("gl");
const mem = std.mem;
const meta = struct {
    fn UnwrapOptional(optional: type) type {
        return @typeInfo(optional).optional.child;
    }
    fn updateStruct(base: anytype, args: anytype) @TypeOf(base) {
        var based = base;
        inline for (
            @typeInfo(@TypeOf(args)).@"struct".fields,
        ) |field|
            @field(based, field.name) = @field(args, field.name);
        return based;
    }
    usingnamespace std.meta;
};
const std = @import("std");

const base_width = 320;
const base_height = 240;
const max_width = 1024;
const max_height = 1024;

const o = struct { // c-re
    var hw_render: c.retro_hw_render_callback = undefined;

    var width: gl.sizei = base_width;
    var height: gl.sizei = base_height;

    var prog: gl.uint = undefined;
    var vbo: gl.uint = undefined;
    const loc = struct {
        pub var a_vertex: gl.uint = undefined;
        pub var a_color: gl.uint = undefined;
        pub var u_mvp: gl.uint = undefined;
    };

    const cb = struct { // -all-acks
        var video: meta.UnwrapOptional(c.retro_video_refresh_t) = undefined;
        var audio: meta.UnwrapOptional(c.retro_audio_sample_t) = undefined;
        var audio_batch: meta.UnwrapOptional(c.retro_audio_sample_batch_t) = undefined;
        var env: meta.UnwrapOptional(c.retro_environment_t) = undefined;
        var input_poll: meta.UnwrapOptional(c.retro_input_poll_t) = undefined;
        var input_state: meta.UnwrapOptional(c.retro_input_state_t) = undefined;
    };

    var frame_count: u16 = 0;
};

const shader_source_preamble = if (gl.info.api == .gles)
    \\#version 100
    \\precision mediump float;
    \\
else
    \\#version 110
    \\
    ;

const vertex_shader =
    shader_source_preamble ++
    \\uniform mat4 u_mvp;
    \\attribute vec2 a_vertex;
    \\attribute vec4 a_color;
    \\varying vec4 v_color;
    \\void main() {
    \\    gl_Position = u_mvp * vec4(a_vertex, 0.0, 1.0);
    \\    v_color = a_color;
    \\}
;

const fragment_shader =
    shader_source_preamble ++
    \\varying vec4 v_color;
    \\void main() {
    \\    gl_FragColor = v_color;
    \\}
;

fn compileProgram() void {
    o.prog = gl.CreateProgram();

    const vert = gl.CreateShader(gl.VERTEX_SHADER);
    defer gl.DeleteShader(vert);
    gl.ShaderSource(vert, 1, &.{vertex_shader}, null);
    gl.CompileShader(vert);
    gl.AttachShader(o.prog, vert);

    const frag = gl.CreateShader(gl.FRAGMENT_SHADER);
    defer gl.DeleteShader(frag);
    gl.ShaderSource(frag, 1, &.{fragment_shader}, null);
    gl.CompileShader(frag);
    gl.AttachShader(o.prog, frag);

    gl.LinkProgram(o.prog);

    inline for (@typeInfo(o.loc).@"struct".decls) |shader_decl|
        @field(o.loc, shader_decl.name) = @intCast((switch (shader_decl.name[0]) {
            'a' => gl.GetAttribLocation,
            'u' => gl.GetUniformLocation,
            else => unreachable,
        })(o.prog, shader_decl.name));
}

fn setupVbo() void {
    // zig fmt: off
    const vertex_data = [_]gl.float {
        -0.5, -0.5,
         0.5, -0.5,
        -0.5,  0.5,
         0.5,  0.5,
         1.0,  1.0,  1.0,  1.0,
         1.0,  1.0,  0.0,  1.0,
         0.0,  1.0,  1.0,  1.0,
         1.0,  0.0,  1.0,  1.0,
    };
    // zig fmt: on

    gl.UseProgram(o.prog);
    defer gl.UseProgram(0);

    gl.GenBuffers(1, @as(*[1]gl.uint, &o.vbo));
    gl.BindBuffer(gl.ARRAY_BUFFER, o.vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertex_data)), &vertex_data, gl.STATIC_DRAW);
}

comptime {
    for (@typeInfo(@This()).@"struct".decls) |decl| {
        if (!mem.startsWith(u8, decl.name, "retro_"))
            continue;
        const field = @field(@This(), decl.name);
        if (@TypeOf(field) != @TypeOf(@field(c, decl.name))) {
            @compileError("pub decl type mismatch: " ++ decl.name);
        }
        @export(&field, .{ .name = decl.name, .linkage = .strong });
    }
}

pub fn retro_init() callconv(.C) void {}

pub fn retro_deinit() callconv(.C) void {}

pub fn retro_api_version() callconv(.C) c_uint {
    return c.RETRO_API_VERSION;
}

pub fn retro_set_controller_port_device(port: c_uint, device: c_uint) callconv(.C) void {
    _, _ = .{ port, device };
}

pub fn retro_get_system_info(info: [*c]c.retro_system_info) callconv(.C) void {
    info.* = .{
        .library_name = "TestCore GL",
        .library_version = "v1",
        .need_fullpath = false,
    };
}

pub fn retro_get_system_av_info(info: [*c]c.retro_system_av_info) callconv(.C) void {
    info.* = .{
        .timing = .{
            .fps = 60.0,
            .sample_rate = 0.0,
        },
        .geometry = .{
            .base_width = base_width,
            .base_height = base_height,
            .max_width = max_width,
            .max_height = max_height,
            .aspect_ratio = 4.0 / 3.0,
        },
    };
}

pub fn retro_set_environment(cb: c.retro_environment_t) callconv(.C) void {
    o.cb.env = cb.?;
    {
        var no_rom = true;
        _ = o.cb.env(c.RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, &no_rom);
    }
    {
        var variables = [_]c.retro_variable{
            .{
                .key = "testgl_resolution",
                .value = "Internal resolution; 320x240|360x480|480x272|512x384|512x512" ++
                    "|640x240|640x448|640x480|720x576|800x600|960x720|1024x768|1024x1024",
            },
            .{},
        };
        _ = o.cb.env(c.RETRO_ENVIRONMENT_SET_VARIABLES, &variables);
    }
}

pub fn retro_set_audio_sample(cb: c.retro_audio_sample_t) callconv(.C) void {
    o.cb.audio = cb.?;
}

pub fn retro_set_audio_sample_batch(cb: c.retro_audio_sample_batch_t) callconv(.C) void {
    o.cb.audio_batch = cb.?;
}

pub fn retro_set_input_poll(cb: c.retro_input_poll_t) callconv(.C) void {
    o.cb.input_poll = cb.?;
}

pub fn retro_set_input_state(cb: c.retro_input_state_t) callconv(.C) void {
    o.cb.input_state = cb.?;
}

pub fn retro_set_video_refresh(cb: c.retro_video_refresh_t) callconv(.C) void {
    o.cb.video = cb.?;
}

fn updateVariables() void {
    var variable: c.retro_variable = .{ .key = "testgl_resolution" };
    if (o.cb.env(c.RETRO_ENVIRONMENT_GET_VARIABLE, &variable) and variable.value != null) {
        var dims = mem.splitScalar(u8, mem.sliceTo(variable.value, 0), 'x');
        inline for (.{ &o.width, &o.height }) |dim| {
            dim.* = fmt.parseUnsigned(@TypeOf(dim.*), dims.next().?, 10) catch unreachable;
        }
        debug.assert(dims.next() == null);
        debug.print("[libretro-test]: Got size: {} x {}.\n", .{ o.width, o.height });
    }
}

pub fn retro_run() callconv(.C) void {
    {
        var is_updated: bool = undefined;
        if (o.cb.env(c.RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &is_updated) and is_updated)
            updateVariables();
    }

    o.cb.input_poll();
    _ = o.cb.input_state(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_UP);

    gl.BindFramebuffer(gl.FRAMEBUFFER, @intCast(o.hw_render.get_current_framebuffer.?()));

    gl.ClearColor(0.3, 0.4, 0.5, 1.0);
    gl.Viewport(0, 0, o.width, o.height);
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

    {
        gl.UseProgram(o.prog);
        defer gl.UseProgram(0);

        gl.Enable(gl.DEPTH_TEST);

        {
            gl.BindBuffer(gl.ARRAY_BUFFER, o.vbo);
            defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

            inline for (.{
                .{ .name = "a_vertex", .size = 2, .offset = 0 },
                .{ .name = "a_color", .size = 4, .offset = 8 * @sizeOf(gl.float) },
            }) |attr| {
                const loc = @field(o.loc, attr.name);
                gl.VertexAttribPointer(loc, attr.size, gl.FLOAT, gl.FALSE, 0, attr.offset);
                gl.EnableVertexAttribArray(loc);
            }
        }
        defer gl.DisableVertexAttribArray(o.loc.a_vertex);
        defer gl.DisableVertexAttribArray(o.loc.a_color);

        const angle = @as(gl.float, @floatFromInt(o.frame_count)) / 100.0;
        var cos = @cos(angle);
        var sin = @sin(angle);

        inline for (0.., .{ 0, 0.4 }, .{ 0, 0.4 }, .{ 0, 0.2 }) |i, dx, dy, dz| {
            // zig fmt: off
            gl.UniformMatrix4fv(
                @intCast(o.loc.u_mvp),
                1,
                gl.FALSE,
                &[_]gl.float{
                    cos, -sin,  0, 0,
                    sin,  cos,  0, 0,
                      0,    0,  1, 0,
                     dx,   dy, dz, 1,
                },
            );
            // zig fmt: on
            gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4);

            if (i == 1)
                break;

            inline for (.{ &cos, &sin }) |trig|
                trig.* *= 0.5;
        }
    }

    o.frame_count +%= 1;

    o.cb.video(c.RETRO_HW_FRAME_BUFFER_VALID, @intCast(o.width), @intCast(o.height), 0);
}

fn contextReset() callconv(.C) void {
    debug.print("Context reset!\n", .{});
    const gl_procs = &(struct {
        var gl_procs: gl.ProcTable = undefined;
    }.gl_procs);
    assert(gl_procs.init(o.hw_render.get_proc_address.?));
    gl.makeProcTableCurrent(gl_procs);

    compileProgram();
    setupVbo();
}

fn contextDestroy() callconv(.C) void {
    debug.print("Context destroy!\n", .{});

    gl.DeleteBuffers(1, @as(*[1]gl.uint, &o.vbo));
    o.vbo = undefined;

    gl.DeleteProgram(o.prog);
    o.prog = undefined;

    gl.makeProcTableCurrent(null);
}

fn initHwContext() bool {
    o.hw_render = meta.updateStruct(
        c.retro_hw_render_callback{
            .context_reset = &contextReset,
            .context_destroy = &contextDestroy,
            .depth = true,
            .stencil = true,
            .bottom_left_origin = true,
        },
        if (gl.info.api == .gles) .{
            .context_type = c.RETRO_HW_CONTEXT_OPENGLES2,
        } else .{
            .context_type = c.RETRO_HW_CONTEXT_OPENGL_CORE,
            .version_major = 2,
            .version_minor = 0,
        },
    );
    return o.cb.env(c.RETRO_ENVIRONMENT_SET_HW_RENDER, &o.hw_render);
}

pub fn retro_load_game(info: [*c]const c.retro_game_info) callconv(.C) bool {
    updateVariables();

    {
        const pix_fmt_name = "RETRO_PIXEL_FORMAT_XRGB8888";
        var pix_fmt = @field(c, pix_fmt_name);
        if (!o.cb.env(c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &pix_fmt)) {
            debug.print(pix_fmt_name ++ " is not supported.\n", .{});
            return false;
        }
    }

    if (!initHwContext()) {
        debug.print("HW Context could not be initialized, exiting...\n", .{});
        return false;
    }

    debug.print("Loaded game!\n", .{});
    _ = info;
    return true;
}

pub fn retro_unload_game() callconv(.C) void {}

pub fn retro_get_region() callconv(.C) c_uint {
    return c.RETRO_REGION_NTSC;
}

pub fn retro_load_game_special(
    game_type: c_uint,
    info: [*c]const c.struct_retro_game_info,
    num_info: usize,
) callconv(.C) bool {
    _, _, _ = .{ game_type, info, num_info };
    return false;
}

pub fn retro_serialize_size() callconv(.C) usize {
    return 0;
}

pub fn retro_serialize(data: ?*anyopaque, size: usize) callconv(.C) bool {
    _ = .{ data, size };
    return false;
}

pub fn retro_unserialize(data: ?*const anyopaque, size: usize) callconv(.C) bool {
    _ = .{ data, size };
    return false;
}

pub fn retro_get_memory_data(id: c_uint) callconv(.C) ?*anyopaque {
    _ = id;
    return null;
}

pub fn retro_get_memory_size(id: c_uint) callconv(.C) usize {
    _ = id;
    return 0;
}

pub fn retro_reset() callconv(.C) void {}

pub fn retro_cheat_reset() callconv(.C) void {}

pub fn retro_cheat_set(index: c_uint, enabled: bool, code: [*c]const u8) callconv(.C) void {
    _, _, _ = .{ index, enabled, code };
}
