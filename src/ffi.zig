pub const c = @cImport({
    @cInclude("wayland-egl.h"); // required for egl include to work
    @cInclude("EGL/egl.h");

    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});
