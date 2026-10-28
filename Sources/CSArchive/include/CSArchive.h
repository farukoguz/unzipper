#ifndef UNZIPPER_CSARCHIVE_H
#define UNZIPPER_CSARCHIVE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Minimal, self-contained bindings to the system libarchive. */

typedef struct UZArchive UZArchive;
typedef struct UZWriter UZWriter;

enum {
    UZ_OK = 0,
    UZ_ERR = -1,
    UZ_ERR_CANCELLED = -2
};

typedef struct {
    char *pathname;
    long long size;
    long long compressed_size; /* -1 when unknown */
    long long mtime;           /* seconds since epoch, 0 when unknown */
    unsigned int mode;
    int is_dir;
    int is_encrypted;
    char *symlink;
} UZEntry;

/* Return 1 to continue, 0 to cancel. Called from a background thread. */
typedef int (*UZProgressCallback)(void *context,
                                  const char *pathname,
                                  long long done,
                                  long long total,
                                  int entries_done,
                                  int entries_total);

typedef struct {
    UZProgressCallback callback;
    void *context;
} UZProgress;

/* Lists an archive. Returns UZ_OK on success. */
int uz_list(const char *path,
            UZEntry **out_entries,
            int *out_count,
            char **out_format,
            char **out_filter,
            char **error);

void uz_free_entries(UZEntry *entries, int count);

/* Extracts entries by ordinal index (indices sorted ascending). If index_count
   is zero every entry is extracted. */
int uz_extract(const char *archive_path,
               const char *dest_dir,
               const int *indices,
               int index_count,
               int total_entries,
               const char *password,
               int overwrite,
               long long total_bytes,
               UZProgress progress,
               char **error);

/* Archive creation. */
UZWriter *uz_writer_open(const char *archive_path,
                         const char *format,
                         int compression_level,
                         long long total_bytes,
                         int total_entries,
                         UZProgress progress,
                         char **error);

int uz_writer_add(UZWriter *writer,
                  const char *disk_path,
                  const char *entry_path,
                  char **error);

int uz_writer_close(UZWriter *writer, char **error);

/* Closes and removes the partial archive. */
void uz_writer_abort(UZWriter *writer);

/* Normalizes an archive path: backslashes become slashes, "." and ".."
   components are resolved safely, leading slashes are removed. */
char *uz_normalize_path(const char *path);

void uz_free_string(char *string);

#ifdef __cplusplus
}
#endif

#endif
