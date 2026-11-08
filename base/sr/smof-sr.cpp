// smof-sr: runs a Real-ESRGAN network (ncnn, CPU only) over a PPM picture, tile by tile.
// usage: smof-sr in.ppm out.ppm MODEL_BASENAME SCALE TILE
// reads MODEL_BASENAME.param and .bin, prints "progress N" lines on stdout.
#include <ncnn/net.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <algorithm>

static bool read_ppm(const char* path, int& w, int& h, std::vector<unsigned char>& px) {
    FILE* f = fopen(path, "rb"); if (!f) return false;
    int maxv = 0; char magic[3] = {0};
    if (fscanf(f, "%2s %d %d %d", magic, &w, &h, &maxv) != 4 || strcmp(magic, "P6") != 0 || maxv != 255) { fclose(f); return false; }
    fgetc(f);
    px.resize((size_t)w * h * 3);
    bool ok = fread(px.data(), 1, px.size(), f) == px.size();
    fclose(f); return ok;
}

int main(int argc, char** argv) {
    if (argc < 6) { fprintf(stderr, "usage: smof-sr in.ppm out.ppm model scale tile\n"); return 2; }
    const char* inp = argv[1]; const char* outp = argv[2];
    std::string model = argv[3];
    int scale = atoi(argv[4]); int tile = std::max(32, atoi(argv[5]));
    const int pad = 10;
    int w, h; std::vector<unsigned char> src;
    if (!read_ppm(inp, w, h, src)) { fprintf(stderr, "cannot read input\n"); return 3; }

    ncnn::Net net;
    net.opt.use_vulkan_compute = false;
    net.opt.num_threads = 2;
    net.opt.use_fp16_packed = false; net.opt.use_fp16_storage = false; net.opt.use_fp16_arithmetic = false;
    if (net.load_param((model + ".param").c_str()) != 0 || net.load_model((model + ".bin").c_str()) != 0) { fprintf(stderr, "cannot load model\n"); return 4; }

    // picture with a replicated border of pad pixels, so tiles near the edge see something sensible
    int pw = w + 2 * pad, ph = h + 2 * pad;
    std::vector<unsigned char> padded((size_t)pw * ph * 3);
    for (int y = 0; y < ph; y++) {
        int sy = std::min(std::max(y - pad, 0), h - 1);
        for (int x = 0; x < pw; x++) {
            int sx = std::min(std::max(x - pad, 0), w - 1);
            memcpy(&padded[((size_t)y * pw + x) * 3], &src[((size_t)sy * w + sx) * 3], 3);
        }
    }

    int ow = w * scale, oh = h * scale;
    std::vector<unsigned char> dst((size_t)ow * oh * 3);
    int tilesX = (w + tile - 1) / tile, tilesY = (h + tile - 1) / tile, total = tilesX * tilesY, done = 0;
    const float norm_in[3] = {1 / 255.f, 1 / 255.f, 1 / 255.f};
    const float norm_out[3] = {255.f, 255.f, 255.f};

    for (int ty = 0; ty < tilesY; ty++) for (int tx = 0; tx < tilesX; tx++) {
        int x0 = tx * tile, y0 = ty * tile;
        int tw = std::min(tile, w - x0), th = std::min(tile, h - y0);
        // the tile with its padding, in padded coordinates
        int cw = tw + 2 * pad, ch = th + 2 * pad;
        std::vector<unsigned char> crop((size_t)cw * ch * 3);
        for (int y = 0; y < ch; y++) memcpy(&crop[(size_t)y * cw * 3], &padded[((size_t)(y0 + y) * pw + x0) * 3], (size_t)cw * 3);
        ncnn::Mat in = ncnn::Mat::from_pixels(crop.data(), ncnn::Mat::PIXEL_RGB, cw, ch);
        in.substract_mean_normalize(0, norm_in);
        ncnn::Extractor ex = net.create_extractor();
        ex.input("data", in);
        ncnn::Mat out;
        ex.extract("output", out);
        out.substract_mean_normalize(0, norm_out);
        std::vector<unsigned char> tilepx((size_t)out.w * out.h * 3);
        out.to_pixels(tilepx.data(), ncnn::Mat::PIXEL_RGB);
        // copy the middle of the result, without the padding
        for (int y = 0; y < th * scale; y++)
            memcpy(&dst[((size_t)(y0 * scale + y) * ow + x0 * scale) * 3], &tilepx[((size_t)(y + pad * scale) * out.w + pad * scale) * 3], (size_t)tw * scale * 3);
        done++;
        printf("progress %d\n", done * 100 / total); fflush(stdout);
    }
    FILE* f = fopen(outp, "wb"); if (!f) return 5;
    fprintf(f, "P6\n%d %d\n255\n", ow, oh);
    fwrite(dst.data(), 1, dst.size(), f); fclose(f);
    return 0;
}
