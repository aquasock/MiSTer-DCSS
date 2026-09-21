#pragma once

#ifdef USE_TILE_LOCAL
#ifdef USE_SWGL

#include <vector>

#include "glwrapper.h"

struct SDL_Window;

// The window that the software renderer draws into (set by the SDL window
// manager once the window exists).
extern SDL_Window *swgl_window;

// A software implementation of the GL wrapper for machines without a GPU. It
// draws the axis-aligned, textured, alpha-blended rectangles and lines that
// the tiles UI is built from straight into the SDL window surface.
class SWStateManager : public GLStateManager
{
public:
    SWStateManager();

    virtual void set(const GLState& state) override;
    virtual void pixelstore_unpack_alignment(unsigned int bpp) override;
    virtual void reset_view_for_redraw() override;
    virtual void reset_view_for_resize(const coord_def &m_windowsz,
                                       const coord_def &m_drawablesz) override;
    virtual void set_transform(const GLW_3VF &trans, const GLW_3VF &scale) override;
    virtual void reset_transform() override;
    virtual void get_transform(GLW_3VF *trans, GLW_3VF *scale) override;
    virtual void set_scissor(int x, int y, unsigned int w, unsigned int h) override;
    virtual void reset_scissor() override;

    virtual void delete_textures(size_t count, unsigned int *textures) override;
    virtual void generate_textures(size_t count, unsigned int *textures) override;
    virtual void bind_texture(unsigned int texture) override;
    virtual void load_texture(unsigned char *pixels, unsigned int width,
                              unsigned int height, MipMapOptions mip_opt,
                              int xoffset=-1, int yoffset=-1) override;
    int logical_to_device(int n) const override;
    int device_to_logical(int n, bool round=true) const override;

    struct Texture
    {
        int w = 0, h = 0;
        std::vector<unsigned int> px;   // RGBA bytes, as uploaded
    };

    GLState state;
    GLW_3VF trans, scale;
    float device_scale = 1.0f;          // device pixels per logical pixel
    bool scissor_on = false;
    int sc_x0 = 0, sc_y0 = 0, sc_x1 = 0, sc_y1 = 0;   // device pixels
    std::vector<Texture> textures;      // handle n is textures[n - 1]
    std::vector<unsigned int> free_handles;
    unsigned int bound = 0;
};

class SWShapeBuffer : public GLShapeBuffer
{
public:
    SWShapeBuffer(bool texture, bool colour, drawing_modes prim);

    virtual const char *print_statistics() const override;
    virtual unsigned int size() const override;
    virtual void add(const GLWPrim &prim) override;
    virtual void draw(const GLState &state) override;
    virtual void clear() override;

protected:
    drawing_modes m_prim_type;
    bool m_texture_verts;
    bool m_colour_verts;
    std::vector<GLWPrim> m_prims;
};

#endif // USE_SWGL
#endif // USE_TILE_LOCAL
