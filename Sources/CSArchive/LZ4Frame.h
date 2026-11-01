#ifndef UNZIPPER_LZ4FRAME_H
#define UNZIPPER_LZ4FRAME_H

#ifdef __cplusplus
extern "C" {
#endif

/* Returns 1 when the file starts with an LZ4 frame header. */
int uz_lz4_is_frame(const char *path);

/* Decompresses an LZ4 frame file into destination. Returns 0 on success and
   -1 on failure, storing a malloc'd message in *error when error is non-NULL. */
int uz_lz4_decompress_file(const char *source, const char *destination, char **error);

/* Compresses source into a standalone LZ4 frame at destination. When
   store_only is non-zero, blocks are written uncompressed inside the frame. */
int uz_lz4_compress_file(const char *source, const char *destination,
                         int store_only, char **error);

#ifdef __cplusplus
}
#endif

#endif /* UNZIPPER_LZ4FRAME_H */
