#ifndef VECTOR_CMS_H
#define VECTOR_CMS_H

#include <glib.h>

void *vector_cms_open (const char *cmyk_path);
void vector_cms_close (void *handle);
gboolean vector_cms_has_profile (void *handle);
void vector_cms_rgb_to_cmyk (void *handle, double r, double g, double b, double *c, double *m, double *y, double *k);
void vector_cms_cmyk_to_rgb (void *handle, double c, double m, double y, double k, double *r, double *g, double *b);
void vector_cms_proof (void *handle, guint8 *data, int width, int height, int stride);
guint8 *vector_cms_profile_data (void *handle, int *length);

#include <cairo.h>

double *vector_cairo_path (cairo_t *cr, int *count);
gboolean vector_tiff_cmyk (const char *path, guint8 *cmyk, int width, int height, guint8 *profile, int profile_length, double dpi);

#endif
