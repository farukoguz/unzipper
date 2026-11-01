#include "LZ4Frame.h"

#include <compression.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Minimal, self-contained support for the LZ4 frame format.
 *
 * macOS ships libarchive with LZ4 enabled only through an external `lz4`
 * command, which this app intentionally does not depend on. Reading and writing
 * the frame format here keeps .tar.lz4 archives working without helper
 * processes. Blocks are decoded by a small bounds-checked LZ4 block decoder and
 * encoded with the system Compression framework's raw LZ4 encoder.
 */

#define LZ4_FRAME_MAGIC 0x184D2204u
#define LZ4_SKIPPABLE_MASK 0xFFFFFFF0u
#define LZ4_SKIPPABLE_MAGIC 0x184D2A50u
#define LZ4_HISTORY_SIZE 65536u
#define LZ4_MAX_BLOCK (4u * 1024u * 1024u)

static void set_error_message(char **error, const char *message) {
    if (!error) return;
    free(*error);
    *error = NULL;
    if (!message) return;
    size_t length = strlen(message);
    char *copy = malloc(length + 1);
    if (!copy) return;
    memcpy(copy, message, length + 1);
    *error = copy;
}

static uint32_t read_le32(const unsigned char *bytes) {
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) |
           ((uint32_t)bytes[3] << 24);
}

static int read_exact(FILE *file, void *buffer, size_t length) {
    unsigned char *cursor = buffer;
    while (length > 0) {
        size_t read = fread(cursor, 1, length, file);
        if (read == 0) return ferror(file) ? -1 : 0;
        cursor += read;
        length -= read;
    }
    return 1;
}

static int read_u32(FILE *file, uint32_t *value, int allow_eof) {
    int b0 = fgetc(file);
    if (b0 == EOF) {
        if (allow_eof && !ferror(file)) return 0;
        return -1;
    }
    int b1 = fgetc(file);
    int b2 = fgetc(file);
    int b3 = fgetc(file);
    if (b1 == EOF || b2 == EOF || b3 == EOF) return -1;
    *value = (uint32_t)b0 |
             ((uint32_t)b1 << 8) |
             ((uint32_t)b2 << 16) |
             ((uint32_t)b3 << 24);
    return 1;
}

static int write_u32(FILE *file, uint32_t value) {
    unsigned char bytes[4] = {
        (unsigned char)(value & 0xFF),
        (unsigned char)((value >> 8) & 0xFF),
        (unsigned char)((value >> 16) & 0xFF),
        (unsigned char)((value >> 24) & 0xFF)
    };
    return fwrite(bytes, 1, sizeof(bytes), file) == sizeof(bytes) ? 0 : -1;
}

static int skip_bytes(FILE *file, uint32_t length) {
    unsigned char buffer[4096];
    while (length > 0) {
        size_t chunk = length > sizeof(buffer) ? sizeof(buffer) : length;
        if (read_exact(file, buffer, chunk) != 1) return -1;
        length -= (uint32_t)chunk;
    }
    return 0;
}

static uint32_t rotate_left(uint32_t value, int count) {
    return (value << count) | (value >> (32 - count));
}

/* xxHash32, used for the LZ4 frame descriptor checksum. */
static uint32_t xxh32(const void *input, size_t length, uint32_t seed) {
    const unsigned char *cursor = input;
    const unsigned char *end = cursor + length;
    const uint32_t prime1 = 0x9E3779B1u;
    const uint32_t prime2 = 0x85EBCA77u;
    const uint32_t prime3 = 0xC2B2AE3Du;
    const uint32_t prime4 = 0x27D4EB2Fu;
    const uint32_t prime5 = 0x165667B1u;
    uint32_t hash;

    if (length >= 16) {
        uint32_t v1 = seed + prime1 + prime2;
        uint32_t v2 = seed + prime2;
        uint32_t v3 = seed;
        uint32_t v4 = seed - prime1;
        while (cursor <= end - 16) {
            v1 = rotate_left(v1 + read_le32(cursor) * prime2, 13) * prime1;
            cursor += 4;
            v2 = rotate_left(v2 + read_le32(cursor) * prime2, 13) * prime1;
            cursor += 4;
            v3 = rotate_left(v3 + read_le32(cursor) * prime2, 13) * prime1;
            cursor += 4;
            v4 = rotate_left(v4 + read_le32(cursor) * prime2, 13) * prime1;
            cursor += 4;
        }
        hash = rotate_left(v1, 1) + rotate_left(v2, 7) +
               rotate_left(v3, 12) + rotate_left(v4, 18);
    } else {
        hash = seed + prime5;
    }

    hash += (uint32_t)length;
    while (cursor <= end - 4) {
        hash += read_le32(cursor) * prime3;
        hash = rotate_left(hash, 17) * prime4;
        cursor += 4;
    }
    while (cursor < end) {
        hash += (uint32_t)(*cursor) * prime5;
        hash = rotate_left(hash, 11) * prime1;
        cursor++;
    }

    hash ^= hash >> 15;
    hash *= prime2;
    hash ^= hash >> 13;
    hash *= prime3;
    hash ^= hash >> 16;
    return hash;
}

/* Decodes one raw LZ4 block. `capacity` includes the linked-block history that
   has already been copied into the beginning of `output`. */
static int decode_block(const unsigned char *source,
                        size_t source_length,
                        unsigned char *output,
                        size_t capacity,
                        size_t history_length,
                        size_t *decoded_length) {
    const unsigned char *input = source;
    const unsigned char *input_end = source + source_length;
    unsigned char *cursor = output + history_length;
    unsigned char *output_end = output + capacity;

    while (input < input_end) {
        unsigned char token = *input++;
        size_t literals = token >> 4;
        if (literals == 15) {
            unsigned char extra;
            do {
                if (input >= input_end) return -1;
                extra = *input++;
                literals += extra;
            } while (extra == 255);
        }
        if (literals > (size_t)(input_end - input)) return -1;
        if (literals > (size_t)(output_end - cursor)) return -1;
        memcpy(cursor, input, literals);
        cursor += literals;
        input += literals;

        if (input == input_end) break;
        if (input_end - input < 2) return -1;
        size_t offset = (size_t)input[0] | ((size_t)input[1] << 8);
        input += 2;
        if (offset == 0) return -1;

        size_t match = token & 0x0F;
        if (match == 15) {
            unsigned char extra;
            do {
                if (input >= input_end) return -1;
                extra = *input++;
                match += extra;
            } while (extra == 255);
        }
        match += 4;

        size_t produced = (size_t)(cursor - output);
        if (offset > produced) return -1;
        if (match > (size_t)(output_end - cursor)) return -1;
        const unsigned char *match_cursor = cursor - offset;
        for (size_t i = 0; i < match; i++) {
            cursor[i] = match_cursor[i];
        }
        cursor += match;
    }

    *decoded_length = (size_t)(cursor - output) - history_length;
    return 0;
}

static int decode_frame(FILE *input, FILE *output, char **error) {
    unsigned char descriptor[14];
    unsigned char flags = 0;
    unsigned char block_descriptor = 0;

    if (read_exact(input, &flags, 1) != 1 ||
        read_exact(input, &block_descriptor, 1) != 1) {
        set_error_message(error, "The LZ4 frame header is truncated.");
        return -1;
    }
    descriptor[0] = flags;
    descriptor[1] = block_descriptor;

    if ((flags & 0xC0) != 0x40) {
        set_error_message(error, "The LZ4 frame uses an unsupported version.");
        return -1;
    }
    if (flags & 0x02) {
        set_error_message(error, "The LZ4 frame has reserved flags set.");
        return -1;
    }
    if (block_descriptor & 0x8F) {
        set_error_message(error, "The LZ4 frame has an invalid block descriptor.");
        return -1;
    }

    int independent_blocks = (flags & 0x20) != 0;
    int block_checksum = (flags & 0x10) != 0;
    int has_content_size = (flags & 0x08) != 0;
    int content_checksum = (flags & 0x04) != 0;
    int has_dictionary = (flags & 0x01) != 0;
    int block_code = (block_descriptor >> 4) & 0x07;
    if (block_code < 4 || block_code > 7) {
        set_error_message(error, "The LZ4 frame has an invalid block size.");
        return -1;
    }
    size_t max_block = (size_t)1 << (8 + 2 * block_code);

    size_t descriptor_length = 2;
    if (has_content_size) {
        if (read_exact(input, descriptor + descriptor_length, 8) != 1) {
            set_error_message(error, "The LZ4 frame header is truncated.");
            return -1;
        }
        descriptor_length += 8;
    }
    if (has_dictionary) {
        unsigned char dictionary[4];
        if (read_exact(input, dictionary, sizeof(dictionary)) != 1) {
            set_error_message(error, "The LZ4 frame header is truncated.");
            return -1;
        }
        memcpy(descriptor + descriptor_length, dictionary, sizeof(dictionary));
        descriptor_length += sizeof(dictionary);
        if (read_le32(dictionary) != 0) {
            set_error_message(error, "LZ4 frames with a dictionary are not supported.");
            return -1;
        }
    }

    unsigned char header_checksum = 0;
    if (read_exact(input, &header_checksum, 1) != 1) {
        set_error_message(error, "The LZ4 frame header is truncated.");
        return -1;
    }
    unsigned char expected = (unsigned char)((xxh32(descriptor, descriptor_length, 0) >> 8) & 0xFF);
    if (header_checksum != expected) {
        set_error_message(error, "The LZ4 frame header checksum is invalid.");
        return -1;
    }

    unsigned char *block = malloc(max_block + LZ4_HISTORY_SIZE);
    unsigned char *compressed = malloc(max_block);
    unsigned char *history = independent_blocks ? NULL : malloc(LZ4_HISTORY_SIZE);
    size_t history_length = 0;
    int result = -1;

    if (!block || !compressed || (!independent_blocks && !history)) {
        set_error_message(error, "Out of memory while reading an LZ4 archive.");
        goto cleanup;
    }

    for (;;) {
        uint32_t raw_size = 0;
        if (read_u32(input, &raw_size, 0) != 1) {
            set_error_message(error, "The LZ4 frame is truncated.");
            goto cleanup;
        }
        if (raw_size == 0) break;

        int stored = (raw_size & 0x80000000u) != 0;
        size_t length = (size_t)(raw_size & 0x7FFFFFFFu);
        if (length == 0 || length > max_block) {
            set_error_message(error, "The LZ4 frame contains an invalid block.");
            goto cleanup;
        }

        if (!independent_blocks && history_length > 0) {
            memcpy(block, history, history_length);
        }

        size_t decoded = 0;
        if (stored) {
            if (read_exact(input, block + history_length, length) != 1) {
                set_error_message(error, "The LZ4 frame is truncated.");
                goto cleanup;
            }
            decoded = length;
        } else {
            if (read_exact(input, compressed, length) != 1) {
                set_error_message(error, "The LZ4 frame is truncated.");
                goto cleanup;
            }
            if (decode_block(compressed, length, block,
                             max_block + history_length,
                             history_length, &decoded) != 0) {
                set_error_message(error, "The LZ4 archive contains a corrupt block.");
                goto cleanup;
            }
        }

        if (decoded > 0 &&
            fwrite(block + history_length, 1, decoded, output) != decoded) {
            set_error_message(error, "Could not write the decompressed LZ4 data.");
            goto cleanup;
        }

        if (!independent_blocks) {
            size_t total = history_length + decoded;
            size_t keep = total > LZ4_HISTORY_SIZE ? LZ4_HISTORY_SIZE : total;
            if (keep > 0) memcpy(history, block + total - keep, keep);
            history_length = keep;
        }

        if (block_checksum) {
            uint32_t ignored = 0;
            if (read_u32(input, &ignored, 0) != 1) {
                set_error_message(error, "The LZ4 frame is truncated.");
                goto cleanup;
            }
        }
    }

    if (content_checksum) {
        uint32_t ignored = 0;
        if (read_u32(input, &ignored, 0) != 1) {
            set_error_message(error, "The LZ4 frame is truncated.");
            goto cleanup;
        }
    }

    result = 0;

cleanup:
    free(block);
    free(compressed);
    free(history);
    return result;
}

int uz_lz4_is_frame(const char *path) {
    if (!path) return 0;
    FILE *file = fopen(path, "rb");
    if (!file) return 0;
    unsigned char magic[4];
    size_t read = fread(magic, 1, sizeof(magic), file);
    fclose(file);
    return read == sizeof(magic) && read_le32(magic) == LZ4_FRAME_MAGIC;
}

int uz_lz4_decompress_file(const char *source, const char *destination, char **error) {
    if (error) *error = NULL;
    if (!source || !destination) {
        set_error_message(error, "Invalid arguments.");
        return -1;
    }

    FILE *input = fopen(source, "rb");
    if (!input) {
        char message[256];
        snprintf(message, sizeof(message), "Could not open the LZ4 archive: %s", strerror(errno));
        set_error_message(error, message);
        return -1;
    }
    FILE *output = fopen(destination, "wb");
    if (!output) {
        char message[256];
        snprintf(message, sizeof(message), "Could not prepare the LZ4 archive: %s", strerror(errno));
        set_error_message(error, message);
        fclose(input);
        return -1;
    }

    uint32_t magic = 0;
    int result = -1;
    int read = read_u32(input, &magic, 1);
    if (read != 1) {
        set_error_message(error, "The file is not an LZ4 frame.");
        goto cleanup;
    }

    while (read == 1) {
        if (magic == LZ4_FRAME_MAGIC) {
            if (decode_frame(input, output, error) != 0) goto cleanup;
        } else if ((magic & LZ4_SKIPPABLE_MASK) == LZ4_SKIPPABLE_MAGIC) {
            uint32_t length = 0;
            if (read_u32(input, &length, 0) != 1 ||
                skip_bytes(input, length) != 0) {
                set_error_message(error, "The LZ4 frame is truncated.");
                goto cleanup;
            }
        } else {
            set_error_message(error, "The file is not a valid LZ4 frame.");
            goto cleanup;
        }
        read = read_u32(input, &magic, 1);
        if (read < 0) {
            set_error_message(error, "The LZ4 frame is truncated.");
            goto cleanup;
        }
    }

    result = 0;

cleanup:
    if (fclose(output) != 0 && result == 0) {
        set_error_message(error, "Could not finish the decompressed LZ4 data.");
        result = -1;
    }
    fclose(input);
    if (result != 0) {
        if (error && !*error) set_error_message(error, "Could not read the LZ4 archive.");
        remove(destination);
    }
    return result;
}

int uz_lz4_compress_file(const char *source, const char *destination,
                         int store_only, char **error) {
    if (error) *error = NULL;
    if (!source || !destination) {
        set_error_message(error, "Invalid arguments.");
        return -1;
    }

    FILE *input = fopen(source, "rb");
    if (!input) {
        char message[256];
        snprintf(message, sizeof(message), "Could not open the tar data: %s", strerror(errno));
        set_error_message(error, message);
        return -1;
    }
    FILE *output = fopen(destination, "wb");
    if (!output) {
        char message[256];
        snprintf(message, sizeof(message), "Could not create the LZ4 archive: %s", strerror(errno));
        set_error_message(error, message);
        fclose(input);
        return -1;
    }

    unsigned char header[2] = {0x60, 0x70};
    unsigned char checksum = (unsigned char)((xxh32(header, sizeof(header), 0) >> 8) & 0xFF);
    unsigned char magic[7] = {
        0x04, 0x22, 0x4D, 0x18, header[0], header[1], checksum
    };

    unsigned char *plain = malloc(LZ4_MAX_BLOCK);
    size_t compressed_capacity = LZ4_MAX_BLOCK + LZ4_MAX_BLOCK / 255 + 64;
    unsigned char *compressed = malloc(compressed_capacity);
    int result = -1;

    if (!plain || !compressed) {
        set_error_message(error, "Out of memory while creating an LZ4 archive.");
        goto cleanup;
    }
    if (fwrite(magic, 1, sizeof(magic), output) != sizeof(magic)) {
        set_error_message(error, "Could not write the LZ4 frame header.");
        goto cleanup;
    }

    for (;;) {
        size_t length = fread(plain, 1, LZ4_MAX_BLOCK, input);
        if (length == 0) break;

        int stored = store_only;
        size_t compressed_length = 0;
        if (!stored) {
            compressed_length = compression_encode_buffer(compressed,
                                                          compressed_capacity,
                                                          plain,
                                                          length,
                                                          NULL,
                                                          COMPRESSION_LZ4_RAW);
            if (compressed_length == 0 || compressed_length >= length) {
                stored = 1;
            }
        }

        uint32_t block_header = stored
            ? (0x80000000u | (uint32_t)length)
            : (uint32_t)compressed_length;
        if (write_u32(output, block_header) != 0 ||
            fwrite(stored ? plain : compressed, 1,
                   stored ? length : compressed_length, output) !=
                (stored ? length : compressed_length)) {
            set_error_message(error, "Could not write the compressed LZ4 data.");
            goto cleanup;
        }
    }

    if (ferror(input)) {
        set_error_message(error, "Could not read the tar data.");
        goto cleanup;
    }
    if (write_u32(output, 0) != 0) {
        set_error_message(error, "Could not finish the LZ4 archive.");
        goto cleanup;
    }

    result = 0;

cleanup:
    free(plain);
    free(compressed);
    if (fclose(output) != 0 && result == 0) {
        set_error_message(error, "Could not finish the LZ4 archive.");
        result = -1;
    }
    fclose(input);
    if (result != 0) {
        if (error && !*error) set_error_message(error, "Could not create the LZ4 archive.");
        remove(destination);
    }
    return result;
}
