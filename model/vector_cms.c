#include "vector_cms.h"
#include <lcms2.h>
#include <string.h>

typedef struct {
    cmsHPROFILE srgb;
    cmsHPROFILE cmyk;
    cmsHTRANSFORM to_cmyk;
    cmsHTRANSFORM to_rgb;
    cmsHTRANSFORM proof;
    guint8 *data;
    gsize length;
} VectorCms;

void *
vector_cms_open (const char *cmyk_path)
{
    VectorCms *cms = g_new0 (VectorCms, 1);
    cms->srgb = cmsCreate_sRGBProfile ();
    if (cmyk_path != NULL && g_file_get_contents (cmyk_path, (gchar **) &cms->data, &cms->length, NULL)) {
        cms->cmyk = cmsOpenProfileFromMem (cms->data, (cmsUInt32Number) cms->length);
        if (cms->cmyk != NULL && cmsGetColorSpace (cms->cmyk) != cmsSigCmykData) {
            cmsCloseProfile (cms->cmyk);
            cms->cmyk = NULL;
        }
    }
    if (cms->cmyk != NULL) {
        cms->to_cmyk = cmsCreateTransform (cms->srgb, TYPE_RGB_DBL, cms->cmyk, TYPE_CMYK_DBL, INTENT_RELATIVE_COLORIMETRIC, cmsFLAGS_BLACKPOINTCOMPENSATION);
        cms->to_rgb = cmsCreateTransform (cms->cmyk, TYPE_CMYK_DBL, cms->srgb, TYPE_RGB_DBL, INTENT_RELATIVE_COLORIMETRIC, cmsFLAGS_BLACKPOINTCOMPENSATION);
        cms->proof = cmsCreateProofingTransform (cms->srgb, TYPE_BGRA_8, cms->srgb, TYPE_BGRA_8, cms->cmyk, INTENT_RELATIVE_COLORIMETRIC, INTENT_RELATIVE_COLORIMETRIC, cmsFLAGS_SOFTPROOFING | cmsFLAGS_COPY_ALPHA);
    }
    return cms;
}

void
vector_cms_close (void *handle)
{
    VectorCms *cms = handle;
    if (cms == NULL)
        return;
    if (cms->to_cmyk) cmsDeleteTransform (cms->to_cmyk);
    if (cms->to_rgb) cmsDeleteTransform (cms->to_rgb);
    if (cms->proof) cmsDeleteTransform (cms->proof);
    if (cms->cmyk) cmsCloseProfile (cms->cmyk);
    if (cms->srgb) cmsCloseProfile (cms->srgb);
    g_free (cms->data);
    g_free (cms);
}

gboolean
vector_cms_has_profile (void *handle)
{
    VectorCms *cms = handle;
    return cms != NULL && cms->to_cmyk != NULL && cms->to_rgb != NULL;
}

guint8 *
vector_cms_profile_data (void *handle, int *length)
{
    VectorCms *cms = handle;
    *length = cms != NULL && cms->cmyk != NULL ? (int) cms->length : 0;
    return cms != NULL && cms->cmyk != NULL ? cms->data : NULL;
}

void
vector_cms_rgb_to_cmyk (void *handle, double r, double g, double b, double *c, double *m, double *y, double *k)
{
    VectorCms *cms = handle;
    if (cms != NULL && cms->to_cmyk != NULL) {
        double in[3] = { r, g, b };
        double out[4];
        cmsDoTransform (cms->to_cmyk, in, out, 1);
        *c = out[0] / 100.0;
        *m = out[1] / 100.0;
        *y = out[2] / 100.0;
        *k = out[3] / 100.0;
        return;
    }
    double kk = 1.0 - MAX (r, MAX (g, b));
    *k = kk;
    if (kk >= 1.0) {
        *c = *m = *y = 0;
        return;
    }
    *c = (1.0 - r - kk) / (1.0 - kk);
    *m = (1.0 - g - kk) / (1.0 - kk);
    *y = (1.0 - b - kk) / (1.0 - kk);
}

void
vector_cms_cmyk_to_rgb (void *handle, double c, double m, double y, double k, double *r, double *g, double *b)
{
    VectorCms *cms = handle;
    if (cms != NULL && cms->to_rgb != NULL) {
        double in[4] = { c * 100.0, m * 100.0, y * 100.0, k * 100.0 };
        double out[3];
        cmsDoTransform (cms->to_rgb, in, out, 1);
        *r = CLAMP (out[0], 0.0, 1.0);
        *g = CLAMP (out[1], 0.0, 1.0);
        *b = CLAMP (out[2], 0.0, 1.0);
        return;
    }
    *r = (1.0 - c) * (1.0 - k);
    *g = (1.0 - m) * (1.0 - k);
    *b = (1.0 - y) * (1.0 - k);
}

void
vector_cms_proof (void *handle, guint8 *data, int width, int height, int stride)
{
    VectorCms *cms = handle;
    int x, yy;
    for (yy = 0; yy < height; yy++) {
        guint8 *row = data + (gsize) yy * stride;
        for (x = 0; x < width; x++) {
            guint8 *p = row + x * 4;
            int a = p[3];
            if (a > 0 && a < 255) {
                p[0] = (guint8) MIN (255, p[0] * 255 / a);
                p[1] = (guint8) MIN (255, p[1] * 255 / a);
                p[2] = (guint8) MIN (255, p[2] * 255 / a);
            }
        }
        if (cms != NULL && cms->proof != NULL) {
            cmsDoTransform (cms->proof, row, row, width);
        } else {
            for (x = 0; x < width; x++) {
                guint8 *p = row + x * 4;
                double b = p[0] / 255.0, g = p[1] / 255.0, r = p[2] / 255.0;
                double c, m, y2, k, r2, g2, b2;
                vector_cms_rgb_to_cmyk (NULL, r, g, b, &c, &m, &y2, &k);
                c = c * 0.92;
                m = m * 0.9;
                vector_cms_cmyk_to_rgb (NULL, c, m, y2, k * 0.95, &r2, &g2, &b2);
                p[0] = (guint8) (b2 * 255.0 + 0.5);
                p[1] = (guint8) (g2 * 255.0 + 0.5);
                p[2] = (guint8) (r2 * 255.0 + 0.5);
            }
        }
        for (x = 0; x < width; x++) {
            guint8 *p = row + x * 4;
            int a = p[3];
            if (a < 255) {
                p[0] = (guint8) (p[0] * a / 255);
                p[1] = (guint8) (p[1] * a / 255);
                p[2] = (guint8) (p[2] * a / 255);
            }
        }
    }
}

double *
vector_cairo_path (cairo_t *cr, int *count)
{
    cairo_path_t *path = cairo_copy_path (cr);
    GArray *out = g_array_new (FALSE, TRUE, sizeof (double));
    int i, n = 0;
    for (i = 0; i < path->num_data; i += path->data[i].header.length) {
        cairo_path_data_t *d = &path->data[i];
        double rec[7] = { 0, 0, 0, 0, 0, 0, 0 };
        rec[0] = d->header.type;
        if (d->header.type == CAIRO_PATH_MOVE_TO || d->header.type == CAIRO_PATH_LINE_TO) {
            rec[1] = d[1].point.x;
            rec[2] = d[1].point.y;
        } else if (d->header.type == CAIRO_PATH_CURVE_TO) {
            rec[1] = d[1].point.x;
            rec[2] = d[1].point.y;
            rec[3] = d[2].point.x;
            rec[4] = d[2].point.y;
            rec[5] = d[3].point.x;
            rec[6] = d[3].point.y;
        }
        g_array_append_vals (out, rec, 7);
        n++;
    }
    cairo_path_destroy (path);
    *count = n * 7;
    return (double *) g_array_free (out, FALSE);
}

#include <tiffio.h>

gboolean
vector_tiff_cmyk (const char *path, guint8 *cmyk, int width, int height, guint8 *profile, int profile_length, double dpi)
{
    TIFF *tif = TIFFOpen (path, "w");
    int y;
    if (tif == NULL)
        return FALSE;
    TIFFSetField (tif, TIFFTAG_IMAGEWIDTH, width);
    TIFFSetField (tif, TIFFTAG_IMAGELENGTH, height);
    TIFFSetField (tif, TIFFTAG_SAMPLESPERPIXEL, 4);
    TIFFSetField (tif, TIFFTAG_BITSPERSAMPLE, 8);
    TIFFSetField (tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_SEPARATED);
    TIFFSetField (tif, TIFFTAG_INKSET, INKSET_CMYK);
    TIFFSetField (tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    TIFFSetField (tif, TIFFTAG_COMPRESSION, COMPRESSION_LZW);
    TIFFSetField (tif, TIFFTAG_XRESOLUTION, (float) dpi);
    TIFFSetField (tif, TIFFTAG_YRESOLUTION, (float) dpi);
    TIFFSetField (tif, TIFFTAG_RESOLUTIONUNIT, RESUNIT_INCH);
    TIFFSetField (tif, TIFFTAG_ROWSPERSTRIP, TIFFDefaultStripSize (tif, 0));
    if (profile != NULL && profile_length > 0)
        TIFFSetField (tif, TIFFTAG_ICCPROFILE, (uint32_t) profile_length, profile);
    for (y = 0; y < height; y++) {
        if (TIFFWriteScanline (tif, cmyk + (gsize) y * width * 4, y, 0) < 0) {
            TIFFClose (tif);
            return FALSE;
        }
    }
    TIFFClose (tif);
    return TRUE;
}
