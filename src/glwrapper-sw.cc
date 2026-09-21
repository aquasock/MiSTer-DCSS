#include "AppHdr.h"

#ifdef USE_TILE_LOCAL
#ifdef USE_SWGL

#include "glwrapper-sw.h"

#include <SDL.h>
#include <algorithm>
#include <cmath>
#include <cstring>

#include "options.h"
#include "tilesdl.h"

using std::max;
using std::min;

SDL_Window *swgl_window = nullptr;

namespace opengl
{
    bool check_texture_size(const char *, int, int) { return true; }
    bool flush_opengl_errors() { return false; }
}

GLStateManager *glmanager = nullptr;
static SWStateManager *sw() { return static_cast<SWStateManager *>(glmanager); }

void GLStateManager::init()
{
    if (!glmanager)
        glmanager = new SWStateManager();
}

void GLStateManager::shutdown()
{
    delete glmanager;
    glmanager = nullptr;
}

GLShapeBuffer *GLShapeBuffer::create(bool texture, bool colour,
                                     drawing_modes prim)
{
    return new SWShapeBuffer(texture, colour, prim);
}

/////////////////////////////////////////////////////////////////////////////
// The frame being drawn: the SDL window surface.

namespace
{
struct Target
{
    unsigned char *pixels = nullptr;
    int pitch = 0, w = 0, h = 0;
    int rs = 16, gs = 8, bs = 0, as = 24;
};

Target target()
{
    Target t;
    SDL_Surface *s = swgl_window ? SDL_GetWindowSurface(swgl_window) : nullptr;
    if (!s || s->format->BytesPerPixel != 4)
        return t;
    t.pixels = static_cast<unsigned char *>(s->pixels);
    t.pitch = s->pitch;
    t.w = s->w;
    t.h = s->h;
    t.rs = s->format->Rshift;
    t.gs = s->format->Gshift;
    t.bs = s->format->Bshift;
    t.as = s->format->Ashift;
    return t;
}

inline unsigned int div255(unsigned int x)
{
    x += 128;
    return (x + (x >> 8)) >> 8;
}
} // namespace

/////////////////////////////////////////////////////////////////////////////
// SWStateManager

SWStateManager::SWStateManager() : trans(0, 0, 0), scale(1, 1, 1)
{
}

void SWStateManager::set(const GLState &s)
{
    state = s;
}

void SWStateManager::pixelstore_unpack_alignment(unsigned int)
{
}

void SWStateManager::reset_view_for_redraw()
{
    Target t = target();
    if (!t.pixels)
        return;
    SDL_Surface *s = SDL_GetWindowSurface(swgl_window);
    SDL_FillRect(s, nullptr, SDL_MapRGBA(s->format, 0, 0, 0, 255));
    scissor_on = false;
}

void SWStateManager::reset_view_for_resize(const coord_def &windowsz,
                                           const coord_def &drawablesz)
{
    device_scale = windowsz.x > 0 ? float(drawablesz.x) / windowsz.x : 1.0f;
}

void SWStateManager::set_transform(const GLW_3VF &t, const GLW_3VF &s)
{
    trans = t;
    scale = s;
}

void SWStateManager::reset_transform()
{
    set_transform({0, 0, 0}, {1, 1, 1});
}

void SWStateManager::get_transform(GLW_3VF *t, GLW_3VF *s)
{
    if (t)
        *t = trans;
    if (s)
        *s = scale;
}

void SWStateManager::set_scissor(int x, int y, unsigned int w, unsigned int h)
{
    scissor_on = true;
    sc_x0 = logical_to_device(x);
    sc_y0 = logical_to_device(y);
    sc_x1 = logical_to_device(x + w);
    sc_y1 = logical_to_device(y + h);
}

void SWStateManager::reset_scissor()
{
    scissor_on = false;
}

int SWStateManager::logical_to_device(int n) const
{
    return display_density.logical_to_device(n);
}

int SWStateManager::device_to_logical(int n, bool round) const
{
    return display_density.device_to_logical(n, round);
}

void SWStateManager::generate_textures(size_t count, unsigned int *out)
{
    for (size_t i = 0; i < count; i++)
    {
        if (!free_handles.empty())
        {
            out[i] = free_handles.back();
            free_handles.pop_back();
        }
        else
        {
            textures.emplace_back();
            out[i] = textures.size();
        }
    }
}

void SWStateManager::delete_textures(size_t count, unsigned int *in)
{
    for (size_t i = 0; i < count; i++)
    {
        if (in[i] == 0 || in[i] > textures.size())
            continue;
        Texture &t = textures[in[i] - 1];
        t = Texture();
        free_handles.push_back(in[i]);
        if (bound == in[i])
            bound = 0;
    }
}

void SWStateManager::bind_texture(unsigned int handle)
{
    bound = handle;
}

void SWStateManager::load_texture(unsigned char *pixels, unsigned int width,
                                  unsigned int height, MipMapOptions,
                                  int xoffset, int yoffset)
{
    if (bound == 0 || bound > textures.size())
        return;
    Texture &t = textures[bound - 1];
    if (xoffset >= 0 && pixels && yoffset >= 0 && int(width) + xoffset <= t.w
        && int(height) + yoffset <= t.h)
    {
        for (unsigned int y = 0; y < height; y++)
            memcpy(&t.px[(yoffset + y) * t.w + xoffset], pixels + y * width * 4,
                   width * 4);
        return;
    }
    t.w = width;
    t.h = height;
    t.px.resize(size_t(width) * height);
    if (pixels)
        memcpy(t.px.data(), pixels, size_t(width) * height * 4);
    else
        std::fill(t.px.begin(), t.px.end(), 0u);   // storage only, like glTexImage2D(NULL)
}

/////////////////////////////////////////////////////////////////////////////
// SWShapeBuffer

SWShapeBuffer::SWShapeBuffer(bool texture, bool colour, drawing_modes prim) :
    m_prim_type(prim), m_texture_verts(texture), m_colour_verts(colour)
{
    ASSERT(prim == GLW_RECTANGLE || prim == GLW_LINES);
}

const char *SWShapeBuffer::print_statistics() const
{
    return nullptr;
}

unsigned int SWShapeBuffer::size() const
{
    return m_prims.size() * (m_prim_type == GLW_RECTANGLE ? 4 : 2);
}

void SWShapeBuffer::add(const GLWPrim &prim)
{
    m_prims.push_back(prim);
}

void SWShapeBuffer::clear()
{
    m_prims.clear();
}

namespace
{
// Combines a source pixel (r,g,b,a, 0-255) into the destination.
inline void put(unsigned char *dst, const Target &t, bool blend,
                unsigned int r, unsigned int g, unsigned int b, unsigned int a)
{
    unsigned int *d = reinterpret_cast<unsigned int *>(dst);
    if (blend && a != 255)
    {
        if (a == 0)
            return;
        unsigned int v = *d;
        unsigned int dr = (v >> t.rs) & 255, dg = (v >> t.gs) & 255,
                     db = (v >> t.bs) & 255;
        unsigned int ia = 255 - a;
        r = div255(r * a + dr * ia);
        g = div255(g * a + dg * ia);
        b = div255(b * a + db * ia);
        a = 255;
    }
    *d = (r << t.rs) | (g << t.gs) | (b << t.bs) | (a << t.as);
}
} // namespace

void SWShapeBuffer::draw(const GLState &st)
{
    if (m_prims.empty() || !st.array_vertex)
        return;
    SWStateManager *m = sw();
    m->set(st);

    Target t = target();
    if (!t.pixels)
        return;

    // Clip rectangle in device pixels.
    int cx0 = 0, cy0 = 0, cx1 = t.w, cy1 = t.h;
    if (m->scissor_on)
    {
        cx0 = max(cx0, m->sc_x0);
        cy0 = max(cy0, m->sc_y0);
        cx1 = min(cx1, m->sc_x1);
        cy1 = min(cy1, m->sc_y1);
    }
    if (cx0 >= cx1 || cy0 >= cy1)
        return;

    const float k = m->device_scale;
    const float sx = m->scale.x * k, sy = m->scale.y * k;
    const float tx = m->trans.x * k, ty = m->trans.y * k;

    const SWStateManager::Texture *tex = nullptr;
    if (st.texture && m_texture_verts && st.array_texcoord && m->bound
        && m->bound <= m->textures.size())
    {
        tex = &m->textures[m->bound - 1];
        if (tex->px.empty())
            tex = nullptr;
    }
    const bool vcol = st.array_colour && m_colour_verts;
    const VColour &base = st.colour;

    if (m_prim_type == GLW_LINES)
    {
        for (const GLWPrim &p : m_prims)
        {
            int x0 = int(floorf(p.pos_sx * sx + tx)), y0 = int(floorf(p.pos_sy * sy + ty));
            int x1 = int(floorf(p.pos_ex * sx + tx)), y1 = int(floorf(p.pos_ey * sy + ty));
            const VColour &c = vcol ? p.col_s : base;
            int dx = abs(x1 - x0), dy = -abs(y1 - y0);
            int stepx = x0 < x1 ? 1 : -1, stepy = y0 < y1 ? 1 : -1;
            int err = dx + dy;
            for (;;)
            {
                if (x0 >= cx0 && x0 < cx1 && y0 >= cy0 && y0 < cy1)
                    put(t.pixels + y0 * t.pitch + x0 * 4, t, st.blend, c.r, c.g, c.b, c.a);
                if (x0 == x1 && y0 == y1)
                    break;
                int e2 = 2 * err;
                if (e2 >= dy) { err += dy; x0 += stepx; }
                if (e2 <= dx) { err += dx; y0 += stepy; }
            }
        }
        return;
    }

    for (const GLWPrim &p : m_prims)
    {
        // Transform, then order the corners so x0 < x1 and y0 < y1, carrying
        // the texture coordinates and colours along.
        float ax0 = p.pos_sx * sx + tx, ax1 = p.pos_ex * sx + tx;
        float ay0 = p.pos_sy * sy + ty, ay1 = p.pos_ey * sy + ty;
        float u0 = p.tex_sx, u1 = p.tex_ex, v0 = p.tex_sy, v1 = p.tex_ey;
        VColour c0 = vcol ? p.col_s : base, c1 = vcol ? p.col_e : base;
        if (ax1 < ax0) { std::swap(ax0, ax1); std::swap(u0, u1); }
        if (ay1 < ay0) { std::swap(ay0, ay1); std::swap(v0, v1); std::swap(c0, c1); }
        if (ax1 <= ax0 || ay1 <= ay0)
            continue;

        // Pixels whose centres fall inside the rectangle.
        int ix0 = max(int(ceilf(ax0 - 0.5f)), cx0), ix1 = min(int(ceilf(ax1 - 0.5f)), cx1);
        int iy0 = max(int(ceilf(ay0 - 0.5f)), cy0), iy1 = min(int(ceilf(ay1 - 0.5f)), cy1);
        if (ix0 >= ix1 || iy0 >= iy1)
            continue;

        const bool grad = c0 != c1;
        const float inv_h = 1.0f / (ay1 - ay0);

        // Texture stepping in 16.16 fixed point (texel units).
        int u_fp = 0, du_fp = 0;
        int tw = 0, th = 0;
        if (tex)
        {
            tw = tex->w;
            th = tex->h;
            const float du = (u1 - u0) / (ax1 - ax0) * tw;
            du_fp = int(du * 65536.0f);
            u_fp = int((u0 * tw + (ix0 + 0.5f - ax0) * du) * 65536.0f);
        }

        for (int y = iy0; y < iy1; y++)
        {
            VColour c = c0;
            if (grad)
            {
                float f = (y + 0.5f - ay0) * inv_h;
                c.r = c0.r + int((int(c1.r) - int(c0.r)) * f);
                c.g = c0.g + int((int(c1.g) - int(c0.g)) * f);
                c.b = c0.b + int((int(c1.b) - int(c0.b)) * f);
                c.a = c0.a + int((int(c1.a) - int(c0.a)) * f);
            }
            unsigned char *row = t.pixels + y * t.pitch + ix0 * 4;
            const bool plain = c.r == 255 && c.g == 255 && c.b == 255 && c.a == 255;

            if (!tex)
            {
                for (int x = ix0; x < ix1; x++, row += 4)
                    put(row, t, st.blend, c.r, c.g, c.b, c.a);
                continue;
            }

            int ty_ = int((v0 + (y + 0.5f - ay0) * inv_h * (v1 - v0)) * th);
            ty_ = ty_ < 0 ? 0 : (ty_ >= th ? th - 1 : ty_);
            const unsigned int *src = &tex->px[size_t(ty_) * tw];
            int uf = u_fp;
            for (int x = ix0; x < ix1; x++, row += 4, uf += du_fp)
            {
                int tx_ = uf >> 16;
                tx_ = tx_ < 0 ? 0 : (tx_ >= tw ? tw - 1 : tx_);
                unsigned int s = src[tx_];   // bytes R,G,B,A
                unsigned int r = s & 255, g = (s >> 8) & 255, b = (s >> 16) & 255, a = s >> 24;
                if (!plain)
                {
                    r = div255(r * c.r);
                    g = div255(g * c.g);
                    b = div255(b * c.b);
                    a = div255(a * c.a);
                }
                if (st.alphatest && a == st.alpharef)
                    continue;
                put(row, t, st.blend, r, g, b, a);
            }
        }
    }
}

#endif // USE_SWGL
#endif // USE_TILE_LOCAL
