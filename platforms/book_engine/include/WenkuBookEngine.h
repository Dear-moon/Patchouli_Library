#ifndef WENKU_BOOK_ENGINE_H
#define WENKU_BOOK_ENGINE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Exports reconstructed, unencrypted OEBPS files into an empty private folder.
 * Status: 0 success, 1 DRM, 2 invalid, 3 size limit, 4 IO. */
int32_t wenku_export_mobi(const char *input, const char *output_directory);
/* Exports original RAWML and verified ORTH word ranges into a private directory.
 * Adds 5 not a MOBI7 dictionary; 6 unsupported encoding/index variant. */
int32_t wenku_export_mobi_dictionary(const char *input, const char *output_directory);
#ifdef __cplusplus
}
#endif
#endif
