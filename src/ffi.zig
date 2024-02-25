pub usingnamespace @cImport({
    @cInclude("wayland-egl.h");
    @cInclude("EGL/egl.h");

    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");

    @cInclude("stb/stb_image.h");
});
