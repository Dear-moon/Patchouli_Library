#include <mobi.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { WENKU_OK, WENKU_DRM, WENKU_INVALID, WENKU_TOO_LARGE, WENKU_IO };
static const size_t MAX_TEXT = 64u * 1024u * 1024u;
static const size_t MAX_OUTPUT = 512u * 1024u * 1024u;

static int save_parts(const MOBIPart *part, const char *directory,
                      const char *prefix, size_t *total, size_t *count) {
    for (; part; part = part->next) {
        if (!part->size) continue;
        if (++*count > 12000 || part->size > 40u * 1024u * 1024u ||
            part->size > MAX_OUTPUT - *total) return WENKU_TOO_LARGE;
        *total += part->size;
        const MOBIFileMeta meta = mobi_get_filemeta_by_type(part->type);
        char path[4096];
        const int length = part->type == T_OPF
            ? snprintf(path, sizeof(path), "%s/content.opf", directory)
            : snprintf(path, sizeof(path), "%s/%s%05zu.%s", directory, prefix,
                       part->uid, meta.extension);
        if (length < 0 || (size_t)length >= sizeof(path) || !part->data) return WENKU_INVALID;
        FILE *file = fopen(path, "wb");
        if (!file) return WENKU_IO;
        const size_t written = fwrite(part->data, 1, part->size, file);
        const int closed = fclose(file);
        if (written != part->size || closed) return WENKU_IO;
    }
    return WENKU_OK;
}

/* Only reconstructed resources are exported. Encryption support is not built. */
int wenku_export_mobi(const char *input, const char *output_directory) {
    int result = WENKU_INVALID;
    MOBIData *book = mobi_init();
    MOBIRawml *raw = NULL;
    if (!book) return result;
    if (mobi_load_filename(book, input) != MOBI_SUCCESS) goto done;
    if (mobi_is_encrypted(book)) { result = WENKU_DRM; goto done; }
    const size_t maximum = mobi_get_text_maxsize(book);
    if (!maximum || maximum == MOBI_NOTSET) goto done;
    if (maximum > MAX_TEXT) { result = WENKU_TOO_LARGE; goto done; }
    raw = mobi_init_rawml(book);
    if (!raw || mobi_parse_rawml_opt(raw, book, true, false, true) != MOBI_SUCCESS ||
        !raw->markup) goto done;
    size_t total = 0, count = 0;
    result = save_parts(raw->markup, output_directory, "part", &total, &count);
    if (result == WENKU_OK && raw->flow)
        result = save_parts(raw->flow->next, output_directory, "flow", &total, &count);
    if (result == WENKU_OK)
        result = save_parts(raw->resources, output_directory, "resource", &total, &count);
done:
    if (raw) mobi_free_rawml(raw);
    mobi_free(book);
    return result;
}

#ifdef WENKU_MOBI_CLI
int main(int argc, char **argv) {
    return argc == 3 ? wenku_export_mobi(argv[1], argv[2]) : WENKU_INVALID;
}
#endif

/* Dictionary import is separate from the book-to-EPUB exporter above: ORTH
 * coordinates refer to the original RAWML, before link reconstruction or text
 * transcoding. Only fixed app-owned files are created, never source labels. */
#include <fcntl.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <unistd.h>

enum { WENKU_NOT_DICTIONARY = 5, WENKU_DICTIONARY_UNSUPPORTED = 6 };
static const size_t MAX_DICTIONARY_INDEX = 64u * 1024u * 1024u;
static const size_t MAX_DICTIONARY_ENTRIES = 1000000u;
static const size_t MAX_DICTIONARY_ENTRY = 2u * 1024u * 1024u;
static const size_t MAX_DICTIONARY_TITLE = 64u * 1024u;

static uint32_t dictionary_u32(const unsigned char *bytes) {
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static bool dictionary_utf8(const unsigned char *bytes, size_t length) {
    size_t i = 0;
    while (i < length) {
        const unsigned char first = bytes[i++];
        if (first < 0x80) continue;
        uint32_t value;
        size_t remaining;
        uint32_t minimum;
        if (first >= 0xc2 && first <= 0xdf) {
            value = first & 0x1f; remaining = 1; minimum = 0x80;
        } else if (first >= 0xe0 && first <= 0xef) {
            value = first & 0x0f; remaining = 2; minimum = 0x800;
        } else if (first >= 0xf0 && first <= 0xf4) {
            value = first & 0x07; remaining = 3; minimum = 0x10000;
        } else return false;
        if (remaining > length - i) return false;
        while (remaining--) {
            const unsigned char next = bytes[i++];
            if ((next & 0xc0) != 0x80) return false;
            value = (value << 6) | (next & 0x3f);
        }
        if (value < minimum || value > 0x10ffff ||
            (value >= 0xd800 && value <= 0xdfff)) return false;
    }
    return true;
}

/* Preflight the index before libmobi allocates its declared entry array. ORDT2
 * labels are already converted to UTF-8 by mobi_getstring_ordt, unlike ordinary
 * labels which retain the INDX encoding. */
static int dictionary_index_encoding(const MOBIData *book, uint32_t *encoding) {
    const MOBIPdbRecord *meta = mobi_get_record_by_seqnumber(
        book, *book->mh->orth_index + mobi_get_kf8offset(book));
    if (!meta || meta->size < 56 || memcmp(meta->data, "INDX", 4))
        return WENKU_INVALID;
    const uint32_t header = dictionary_u32(meta->data + 4);
    const uint32_t records = dictionary_u32(meta->data + 24);
    const uint32_t entries = dictionary_u32(meta->data + 36);
    if (header < 56 || header > meta->size || !records || !entries)
        return WENKU_INVALID;
    if (records > 10000 || entries > MAX_DICTIONARY_ENTRIES)
        return WENKU_TOO_LARGE;
    if (dictionary_u32(meta->data + 12) != 0)
        return WENKU_DICTIONARY_UNSUPPORTED;
    *encoding = dictionary_u32(meta->data + 28);
    if (*encoding == MOBI_NOTSET) *encoding = MOBI_CP1252;
    if (header >= 180) {
        if (header < 188) return WENKU_DICTIONARY_UNSUPPORTED;
        const uint32_t count = dictionary_u32(meta->data + 168);
        const uint32_t offset = dictionary_u32(meta->data + 176);
        if (count) {
            if (count > 65536) return WENKU_TOO_LARGE;
            if (dictionary_u32(meta->data + 164) > 1)
                return WENKU_DICTIONARY_UNSUPPORTED;
            if (offset > meta->size || meta->size - offset < 4 ||
                2u * count > meta->size - offset - 4 ||
                memcmp(meta->data + offset, "ORDT", 4)) return WENKU_INVALID;
            *encoding = MOBI_UTF8;
        }
    }
    return *encoding == MOBI_UTF8 || *encoding == MOBI_CP1252
        ? WENKU_OK : WENKU_DICTIONARY_UNSUPPORTED;
}

static bool dictionary_write(FILE *file, const void *bytes, size_t length) {
    return !length || fwrite(bytes, 1, length, file) == length;
}

static bool dictionary_write16(FILE *file, uint16_t value) {
    const unsigned char bytes[2] = {(unsigned char)(value >> 8), (unsigned char)value};
    return dictionary_write(file, bytes, sizeof(bytes));
}

static bool dictionary_write32(FILE *file, uint32_t value) {
    const unsigned char bytes[4] = {
        (unsigned char)(value >> 24), (unsigned char)(value >> 16),
        (unsigned char)(value >> 8), (unsigned char)value};
    return dictionary_write(file, bytes, sizeof(bytes));
}

static bool dictionary_write64(FILE *file, uint64_t value) {
    return dictionary_write32(file, (uint32_t)(value >> 32)) &&
           dictionary_write32(file, (uint32_t)value);
}

/* Status 6 distinguishes a legitimate but unsupported zero-length ORTH variant
 * from damage: libmobi reconstructs such entries as standalone idx:orth markers,
 * so there is no reliable definition end to infer from the following headword. */
__attribute__((visibility("default")))
int wenku_export_mobi_dictionary(const char *input, const char *output_directory) {
    int result = WENKU_INVALID, directory = -1;
    bool created_raw = false, created_index = false;
    FILE *source = NULL, *body_file = NULL, *index_file = NULL;
    MOBIData *book = NULL;
    MOBIRawml *raw = NULL;
    char *title = NULL;
    if (!input || !output_directory) return WENKU_IO;
    const int input_fd = open(input, O_RDONLY | O_NOFOLLOW);
    if (input_fd < 0) return WENKU_IO;
    struct stat info;
    if (fstat(input_fd, &info) || !S_ISREG(info.st_mode)) {
        close(input_fd); return WENKU_IO;
    }
    if (info.st_size <= 0) { close(input_fd); return WENKU_INVALID; }
    if ((uint64_t)info.st_size > MAX_OUTPUT) {
        close(input_fd); return WENKU_TOO_LARGE;
    }
    source = fdopen(input_fd, "rb");
    if (!source) { close(input_fd); return WENKU_IO; }
    book = mobi_init();
    if (!book || mobi_load_file(book, source) != MOBI_SUCCESS) goto done;
    if (mobi_is_encrypted(book)) { result = WENKU_DRM; goto done; }
    if (!mobi_is_dictionary(book)) { result = WENKU_NOT_DICTIONARY; goto done; }
    if (!book->mh || !book->mh->text_encoding) {
        result = WENKU_DICTIONARY_UNSUPPORTED; goto done;
    }
    const uint32_t body_encoding = *book->mh->text_encoding;
    if (body_encoding != MOBI_UTF8 && body_encoding != MOBI_CP1252) {
        result = WENKU_DICTIONARY_UNSUPPORTED; goto done;
    }
    const size_t maximum = mobi_get_text_maxsize(book);
    if (!maximum || maximum == MOBI_NOTSET) goto done;
    if (maximum > MAX_TEXT) { result = WENKU_TOO_LARGE; goto done; }
    uint32_t key_encoding;
    result = dictionary_index_encoding(book, &key_encoding);
    if (result != WENKU_OK) goto done;
    result = WENKU_INVALID;
    raw = mobi_init_rawml(book);
    if (!raw || mobi_parse_rawml_opt(raw, book, false, true, false) != MOBI_SUCCESS ||
        !raw->flow || !raw->orth || !raw->orth->entries || !raw->orth->entries_count)
        goto done;
    if (raw->orth->entries_count != raw->orth->total_entries_count) goto done;
    const MOBIPart *body = raw->flow;
    if (!body->data || !body->size || body->next) goto done;
    if (body->size > MAX_TEXT || raw->orth->entries_count > MAX_DICTIONARY_ENTRIES) {
        result = WENKU_TOO_LARGE; goto done;
    }
    if (body_encoding == MOBI_UTF8 && !dictionary_utf8(body->data, body->size))
        goto done;
    size_t title_source_size = 0;
    for (const MOBIExthHeader *item = book->eh; item; item = item->next) {
        if (item->tag == EXTH_UPDATEDTITLE) {
            /* UTF-8 expansion and the metadata joiner's separator are bounded
             * before asking libmobi to allocate/concatenate the title. */
            if (item->size > (MAX_DICTIONARY_TITLE - title_source_size - 2) / 3) {
                result = WENKU_TOO_LARGE; goto done;
            }
            title_source_size += item->size * 3 + 2;
            if (title_source_size > MAX_DICTIONARY_TITLE - 2) {
                result = WENKU_TOO_LARGE; goto done;
            }
        }
    }
    title = mobi_meta_get_title(book);
    const size_t title_size = title ? strlen(title) : 0;
    if (title_size > MAX_DICTIONARY_TITLE) { result = WENKU_TOO_LARGE; goto done; }
    if (title && !dictionary_utf8((const unsigned char *)title, title_size)) {
        result = WENKU_DICTIONARY_UNSUPPORTED; goto done;
    }
    size_t index_size = 32 + title_size;
    for (size_t i = 0; i < raw->orth->entries_count; i++) {
        const MOBIIndexEntry *entry = &raw->orth->entries[i];
        if (!entry->label || !entry->label[0]) goto done;
        const size_t label_size = strlen(entry->label);
        if (label_size > UINT16_MAX || label_size + 10 > MAX_DICTIONARY_INDEX - index_size) {
            result = WENKU_TOO_LARGE; goto done;
        }
        index_size += label_size + 10;
        if (key_encoding == MOBI_UTF8 &&
            !dictionary_utf8((const unsigned char *)entry->label, label_size)) goto done;
        const uint32_t offset = mobi_get_orth_entry_offset(entry);
        const uint32_t length = mobi_get_orth_entry_length(entry);
        if (offset == MOBI_NOTSET || length == MOBI_NOTSET) goto done;
        size_t offset_tags = 0, length_tags = 0;
        for (size_t j = 0; j < entry->tags_count; j++) {
            const MOBIIndexTag *tag = &entry->tags[j];
            if (tag->tagid == 1 || tag->tagid == 2) {
                if (tag->tagvalues_count != 1) {
                    result = WENKU_DICTIONARY_UNSUPPORTED; goto done;
                }
                if (tag->tagid == 1) offset_tags++; else length_tags++;
            }
        }
        if (offset_tags != 1 || length_tags != 1) {
            result = WENKU_DICTIONARY_UNSUPPORTED; goto done;
        }
        if (!length) { result = WENKU_DICTIONARY_UNSUPPORTED; goto done; }
        if (length > MAX_DICTIONARY_ENTRY) { result = WENKU_TOO_LARGE; goto done; }
        if (offset > body->size || length > body->size - offset) goto done;
        if (body_encoding == MOBI_UTF8 &&
            ((offset < body->size && (body->data[offset] & 0xc0) == 0x80) ||
             (offset + length < body->size &&
              (body->data[offset + length] & 0xc0) == 0x80))) goto done;
    }
    directory = open(output_directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (directory < 0) { result = WENKU_IO; goto done; }
    int descriptor = openat(directory, "dictionary.raw", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) { result = WENKU_IO; goto done; }
    created_raw = true;
    body_file = fdopen(descriptor, "wb");
    if (!body_file) { close(descriptor); result = WENKU_IO; goto done; }
    descriptor = openat(directory, "dictionary.orth", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) { result = WENKU_IO; goto done; }
    created_index = true;
    index_file = fdopen(descriptor, "wb");
    if (!index_file) { close(descriptor); result = WENKU_IO; goto done; }
    if (!dictionary_write(body_file, body->data, body->size) ||
        !dictionary_write(index_file, "W8MOBI01", 8) ||
        !dictionary_write32(index_file, body_encoding) ||
        !dictionary_write32(index_file, key_encoding) ||
        !dictionary_write64(index_file, body->size) ||
        !dictionary_write32(index_file, (uint32_t)raw->orth->entries_count) ||
        !dictionary_write32(index_file, (uint32_t)title_size) ||
        !dictionary_write(index_file, title, title_size)) { result = WENKU_IO; goto done; }
    for (size_t i = 0; i < raw->orth->entries_count; i++) {
        const MOBIIndexEntry *entry = &raw->orth->entries[i];
        const size_t length = strlen(entry->label);
        if (!dictionary_write16(index_file, (uint16_t)length) ||
            !dictionary_write(index_file, entry->label, length) ||
            !dictionary_write32(index_file, mobi_get_orth_entry_offset(entry)) ||
            !dictionary_write32(index_file, mobi_get_orth_entry_length(entry))) {
            result = WENKU_IO; goto done;
        }
    }
    result = WENKU_OK;
done:
    if (body_file && fclose(body_file)) result = WENKU_IO;
    if (index_file && fclose(index_file)) result = WENKU_IO;
    if (result != WENKU_OK && directory >= 0) {
        if (created_raw) unlinkat(directory, "dictionary.raw", 0);
        if (created_index) unlinkat(directory, "dictionary.orth", 0);
    }
    if (directory >= 0) close(directory);
    if (source) fclose(source);
    free(title);
    if (raw) mobi_free_rawml(raw);
    if (book) mobi_free(book);
    return result;
}
