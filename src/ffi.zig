pub const c = @cImport({
    @cInclude("wayland-egl.h"); // required for egl include to work
    @cInclude("EGL/egl.h");
});
