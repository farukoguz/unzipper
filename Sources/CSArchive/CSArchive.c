#include "include/CSArchive.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* libarchive declarations (the CLT SDK ships the library but not the  */
/* headers, so we declare the small subset we use here).               */
/* ------------------------------------------------------------------ */

struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define ARCHIVE_EXTRACT_OWNER 0x0001
#define ARCHIVE_EXTRACT_PERM 0x0002
#define ARCHIVE_EXTRACT_TIME 0x0004
#define ARCHIVE_EXTRACT_NO_OVERWRITE 0x0008
#define ARCHIVE_EXTRACT_UNLINK 0x0010
#define ARCHIVE_EXTRACT_ACL 0x0020
#define ARCHIVE_EXTRACT_FFLAGS 0x0040
#define ARCHIVE_EXTRACT_XATTR 0x0080
#define ARCHIVE_EXTRACT_SECURE_SYMLINKS 0x0100
#define ARCHIVE_EXTRACT_SECURE_NODOTDOT 0x0200

#define AE_IFREG 0100000
#define AE_IFLNK 0120000
#define AE_IFDIR 0040000

struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data_block(struct archive *, const void **, size_t *, int64_t *);
int archive_read_data_skip(struct archive *);
int archive_read_close(struct archive *);
int archive_read_free(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
const char *archive_error_string(struct archive *);
int archive_errno(struct archive *);
const char *archive_format_name(struct archive *);
const char *archive_filter_name(struct archive *, int);

const char *archive_entry_pathname(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
unsigned int archive_entry_mode(struct archive_entry *);
unsigned int archive_entry_filetype(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
void archive_entry_set_pathname(struct archive_entry *, const char *);
void archive_entry_set_hardlink(struct archive_entry *, const char *);

struct archive *archive_write_disk_new(void);
int archive_write_disk_set_options(struct archive *, int);
int archive_write_disk_set_standard_lookup(struct archive *);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data_block(struct archive *, const void *, size_t, int64_t);
int archive_write_finish_entry(struct archive *);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

struct archive_entry *archive_entry_new(void);
void archive_entry_free(struct archive_entry *);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, mode_t);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
void archive_entry_set_symlink(struct archive_entry *, const char *);

struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_set_format_ustar(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_bzip2(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_set_format_option(struct archive *, const char *, const char *, const char *);
int archive_write_set_filter_option(struct archive *, const char *, const char *, const char *);
int archive_write_set_bytes_per_block(struct archive *, int);
int archive_write_open_filename(struct archive *, const char *);
ssize_t archive_write_data(struct archive *, const void *, size_t);

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

static void set_error(char **error, const char *fmt, ...) {
    if (!error) return;
    free(*error);
    *error = NULL;
    va_list ap;
    va_start(ap, fmt);
    char *buf = NULL;
    if (vasprintf(&buf, fmt, ap) < 0) buf = NULL;
    va_end(ap);
    *error = buf;
}

static char *dup_string(const char *value) {
    if (!value) return NULL;
    size_t len = strlen(value) + 1;
    char *copy = malloc(len);
    if (copy) memcpy(copy, value, len);
    return copy;
}

void uz_free_string(char *string) { free(string); }

char *uz_normalize_path(const char *path) {
    if (!path) return dup_string("");

    size_t len = strlen(path);
    char *work = malloc(len + 1);
    if (!work) return NULL;
    size_t w = 0;
    for (size_t i = 0; i < len; i++) {
        char c = path[i];
        work[w++] = (c == '\\') ? '/' : c;
    }
    work[w] = '\0';

    size_t max_parts = (len / 2) + 2;
    char **parts = malloc(max_parts * sizeof(char *));
    if (!parts) { free(work); return NULL; }
    size_t count = 0;

    char *cursor = work;
    while (*cursor) {
        while (*cursor == '/') cursor++;
        if (!*cursor) break;
        char *start = cursor;
        while (*cursor && *cursor != '/') cursor++;
        if (*cursor) { *cursor = '\0'; cursor++; }
        if (strcmp(start, ".") == 0 || start[0] == '\0') continue;
        if (strcmp(start, "..") == 0) {
            if (count > 0) count--;
            continue;
        }
        if (count < max_parts) parts[count++] = start;
    }

    size_t out_len = 0;
    for (size_t i = 0; i < count; i++) {
        out_len += strlen(parts[i]) + (i > 0 ? 1 : 0);
    }
    char *out = malloc(out_len + 1);
    if (!out) { free(work); free(parts); return NULL; }
    size_t pos = 0;
    for (size_t i = 0; i < count; i++) {
        if (i > 0) out[pos++] = '/';
        size_t plen = strlen(parts[i]);
        memcpy(out + pos, parts[i], plen);
        pos += plen;
    }
    out[pos] = '\0';
    free(work);
    free(parts);
    return out;
}

static int selected_index(const int *indices, int count, int index) {
    if (!indices || count <= 0) return 1;
    int lo = 0, hi = count - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (indices[mid] == index) return 1;
        if (indices[mid] < index) lo = mid + 1;
        else hi = mid - 1;
    }
    return 0;
}

static int emit_progress(UZProgress progress,
                         const char *path,
                         long long done,
                         long long total,
                         int entries_done,
                         int entries_total) {
    if (!progress.callback) return 1;
    return progress.callback(progress.context, path ? path : "", done, total,
                             entries_done, entries_total);
}

/* ------------------------------------------------------------------ */
/* Listing                                                             */
/* ------------------------------------------------------------------ */

int uz_list(const char *path,
            UZEntry **out_entries,
            int *out_count,
            char **out_format,
            char **out_filter,
            char **error) {
    if (error) *error = NULL;
    if (out_entries) *out_entries = NULL;
    if (out_count) *out_count = 0;
    if (out_format) *out_format = NULL;
    if (out_filter) *out_filter = NULL;
    if (!path || !out_entries || !out_count) {
        set_error(error, "Invalid arguments.");
        return UZ_ERR;
    }

    struct archive *a = archive_read_new();
    if (!a) { set_error(error, "Could not create archive reader."); return UZ_ERR; }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    if (archive_read_open_filename(a, path, 256 * 1024) != ARCHIVE_OK) {
        set_error(error, "%s", archive_error_string(a) ?: "Could not open archive.");
        archive_read_free(a);
        return UZ_ERR;
    }

    int capacity = 256;
    int count = 0;
    UZEntry *entries = calloc((size_t)capacity, sizeof(UZEntry));
    if (!entries) {
        set_error(error, "Out of memory.");
        archive_read_free(a);
        return UZ_ERR;
    }

    struct archive_entry *entry = NULL;
    int r = ARCHIVE_OK;
    int seen_header = 0;

    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK ||
           r == ARCHIVE_WARN) {
        if (!entry) break;

        if (!seen_header) {
            seen_header = 1;
            if (out_format) *out_format = dup_string(archive_format_name(a));
            if (out_filter) *out_filter = dup_string(archive_filter_name(a, 0));
        }

        if (count == capacity) {
            capacity *= 2;
            UZEntry *grown = realloc(entries, (size_t)capacity * sizeof(UZEntry));
            if (!grown) {
                set_error(error, "Out of memory.");
                uz_free_entries(entries, count);
                archive_read_free(a);
                return UZ_ERR;
            }
            entries = grown;
        }

        const char *raw = archive_entry_pathname(entry);
        char *normalized = uz_normalize_path(raw);
        if (!normalized) {
            set_error(error, "Out of memory.");
            uz_free_entries(entries, count);
            archive_read_free(a);
            return UZ_ERR;
        }

        UZEntry *slot = &entries[count];
        memset(slot, 0, sizeof(*slot));
        slot->pathname = normalized;
        slot->size = archive_entry_size_is_set(entry) ? archive_entry_size(entry) : 0;
        slot->compressed_size = -1;
        slot->mtime = (long long)archive_entry_mtime(entry);
        slot->mode = archive_entry_mode(entry);
        slot->is_dir = (archive_entry_filetype(entry) == AE_IFDIR) ||
                       (raw && raw[0] && raw[strlen(raw) - 1] == '/');
        slot->is_encrypted = archive_entry_is_encrypted(entry) > 0;
        const char *link = archive_entry_symlink(entry);
        if (link) slot->symlink = dup_string(link);
        count++;

        archive_read_data_skip(a);
    }

    if (r != ARCHIVE_EOF && r != ARCHIVE_OK && r != ARCHIVE_WARN) {
        set_error(error, "%s", archive_error_string(a) ?: "Failed while reading archive.");
        uz_free_entries(entries, count);
        archive_read_free(a);
        return UZ_ERR;
    }

    archive_read_close(a);
    archive_read_free(a);

    if (out_format && !*out_format) *out_format = dup_string("Archive");
    if (out_filter && !*out_filter) *out_filter = dup_string("none");
    *out_entries = entries;
    *out_count = count;
    return UZ_OK;
}

void uz_free_entries(UZEntry *entries, int count) {
    if (!entries) return;
    for (int i = 0; i < count; i++) {
        free(entries[i].pathname);
        free(entries[i].symlink);
    }
    free(entries);
}

/* ------------------------------------------------------------------ */
/* Extraction                                                          */
/* ------------------------------------------------------------------ */

int uz_extract(const char *archive_path,
               const char *dest_dir,
               const int *indices,
               int index_count,
               int total_entries,
               const char *password,
               int overwrite,
               long long total_bytes,
               UZProgress progress,
               char **error) {
    if (error) *error = NULL;
    if (!archive_path || !dest_dir) {
        set_error(error, "Invalid arguments.");
        return UZ_ERR;
    }

    char resolved_dest[PATH_MAX];
    if (!realpath(dest_dir, resolved_dest)) {
        set_error(error, "The destination folder does not exist: %s", dest_dir);
        return UZ_ERR;
    }

    struct archive *a = archive_read_new();
    if (!a) { set_error(error, "Could not create archive reader."); return UZ_ERR; }
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    if (password && password[0]) {
        archive_read_add_passphrase(a, password);
    }

    if (archive_read_open_filename(a, archive_path, 256 * 1024) != ARCHIVE_OK) {
        set_error(error, "%s", archive_error_string(a) ?: "Could not open archive.");
        archive_read_free(a);
        return UZ_ERR;
    }

    struct archive *disk = archive_write_disk_new();
    if (!disk) {
        set_error(error, "Could not create extraction writer.");
        archive_read_free(a);
        return UZ_ERR;
    }

    int flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL |
                ARCHIVE_EXTRACT_FFLAGS | ARCHIVE_EXTRACT_SECURE_SYMLINKS |
                ARCHIVE_EXTRACT_SECURE_NODOTDOT;
    if (overwrite) flags |= ARCHIVE_EXTRACT_UNLINK;
    archive_write_disk_set_options(disk, flags);
    archive_write_disk_set_standard_lookup(disk);

    struct archive_entry *entry = NULL;
    long long done = 0;
    int entries_done = 0;
    int ordinal = 0;
    int cancelled = 0;
    int failed = 0;
    int r = ARCHIVE_OK;

    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK ||
           r == ARCHIVE_WARN) {
        if (!entry) break;

        int selected = selected_index(indices, index_count, ordinal);
        char *normalized = uz_normalize_path(archive_entry_pathname(entry));
        if (!normalized) {
            set_error(error, "Out of memory.");
            failed = 1;
            break;
        }
        if (normalized[0] == '\0') selected = 0;

        if (!selected) {
            archive_read_data_skip(a);
            free(normalized);
            ordinal++;
            continue;
        }

        if (!emit_progress(progress, normalized, done, total_bytes,
                           entries_done, total_entries)) {
            cancelled = 1;
            free(normalized);
            break;
        }

        size_t full_len = strlen(resolved_dest) + strlen(normalized) + 2;
        char *full = malloc(full_len);
        if (!full) {
            set_error(error, "Out of memory.");
            free(normalized);
            failed = 1;
            break;
        }
        snprintf(full, full_len, "%s/%s", resolved_dest, normalized);

        struct stat st;
        int exists = (lstat(full, &st) == 0);
        int is_dir_entry = (archive_entry_filetype(entry) == AE_IFDIR);
        if (exists && !overwrite && !is_dir_entry) {
            done += archive_entry_size_is_set(entry) ? archive_entry_size(entry) : 0;
            archive_read_data_skip(a);
            entries_done++;
            free(full);
            free(normalized);
            ordinal++;
            continue;
        }

        archive_entry_set_pathname(entry, full);
        const char *hardlink = archive_entry_hardlink(entry);
        if (hardlink) {
            char *target = uz_normalize_path(hardlink);
            if (target && target[0]) {
                size_t target_len = strlen(resolved_dest) + strlen(target) + 2;
                char *full_target = malloc(target_len);
                if (full_target) {
                    snprintf(full_target, target_len, "%s/%s", resolved_dest, target);
                    archive_entry_set_hardlink(entry, full_target);
                    free(full_target);
                }
            }
            free(target);
        }

        r = archive_write_header(disk, entry);
        if (r < ARCHIVE_WARN) {
            set_error(error, "%s%s", archive_error_string(disk) ?: "Could not write file.",
                      "");
            failed = 1;
            free(full);
            free(normalized);
            break;
        }

        int64_t entry_size = archive_entry_size_is_set(entry) ? archive_entry_size(entry) : 0;
        int entry_cancelled = 0;
        if (entry_size != 0) {
            const void *buffer = NULL;
            size_t size = 0;
            int64_t offset = 0;
            int dr = ARCHIVE_OK;
            while ((dr = archive_read_data_block(a, &buffer, &size, &offset)) == ARCHIVE_OK) {
                size_t written = 0;
                while (written < size) {
                    ssize_t n = archive_write_data_block(disk,
                                                         (const char *)buffer + written,
                                                         size - written,
                                                         offset + (int64_t)written);
                    if (n < ARCHIVE_OK) {
                        set_error(error, "%s", archive_error_string(disk) ?: "Could not write data.");
                        failed = 1;
                        break;
                    }
                    if (n == 0) break;
                    written += (size_t)n;
                }
                if (failed) break;
                done += (long long)size;
                if (!emit_progress(progress, normalized, done, total_bytes,
                                   entries_done, total_entries)) {
                    cancelled = 1;
                    entry_cancelled = 1;
                    break;
                }
            }
            if (!failed && !entry_cancelled && dr != ARCHIVE_EOF) {
                set_error(error, "%s", archive_error_string(a) ?: "Could not read archive data.");
                failed = 1;
            }
        }

        if (failed || cancelled) {
            free(full);
            free(normalized);
            if (cancelled) break;
            break;
        }

        if (archive_write_finish_entry(disk) < ARCHIVE_WARN) {
            set_error(error, "%s", archive_error_string(disk) ?: "Could not finish writing file.");
            failed = 1;
            free(full);
            free(normalized);
            break;
        }

        entries_done++;
        free(full);
        free(normalized);
        ordinal++;
    }

    if (!cancelled && !failed && r != ARCHIVE_EOF && r != ARCHIVE_OK && r != ARCHIVE_WARN) {
        set_error(error, "%s", archive_error_string(a) ?: "Failed while reading archive.");
        failed = 1;
    }

    archive_write_close(disk);
    archive_write_free(disk);
    archive_read_close(a);
    archive_read_free(a);

    if (cancelled) return UZ_ERR_CANCELLED;
    if (failed) return UZ_ERR;
    return UZ_OK;
}

/* ------------------------------------------------------------------ */
/* Creation                                                            */
/* ------------------------------------------------------------------ */

struct UZWriter {
    struct archive *a;
    char *path;
    long long done;
    long long total;
    int entries_done;
    int entries_total;
    int cancelled;
    UZProgress progress;
};

static void configure_format(struct archive *a, const char *format, int level) {
    char level_string[16];
    snprintf(level_string, sizeof(level_string), "%d", level);

    if (strcmp(format, "zip") == 0) {
        archive_write_set_format_zip(a);
        archive_write_set_format_option(a, "zip", "compression", "deflate");
        archive_write_set_format_option(a, "zip", "compression-level", level_string);
    } else if (strcmp(format, "7z") == 0) {
        archive_write_set_format_7zip(a);
        archive_write_set_format_option(a, "7zip", "compression", "lzma2");
        archive_write_set_format_option(a, "7zip", "compression-level", level_string);
    } else if (strcmp(format, "tar.gz") == 0) {
        archive_write_set_format_pax_restricted(a);
        archive_write_add_filter_gzip(a);
        archive_write_set_filter_option(a, "gzip", "compression-level", level_string);
    } else if (strcmp(format, "tar.bz2") == 0) {
        archive_write_set_format_pax_restricted(a);
        archive_write_add_filter_bzip2(a);
        archive_write_set_filter_option(a, "bzip2", "compression-level", level_string);
    } else if (strcmp(format, "tar.xz") == 0) {
        archive_write_set_format_pax_restricted(a);
        archive_write_add_filter_xz(a);
        archive_write_set_filter_option(a, "xz", "compression-level", level_string);
    } else {
        archive_write_set_format_pax_restricted(a);
    }

    archive_write_set_bytes_per_block(a, 64 * 1024);
}

UZWriter *uz_writer_open(const char *archive_path,
                         const char *format,
                         int compression_level,
                         long long total_bytes,
                         int total_entries,
                         UZProgress progress,
                         char **error) {
    if (error) *error = NULL;
    if (!archive_path || !format) {
        set_error(error, "Invalid arguments.");
        return NULL;
    }

    struct archive *a = archive_write_new();
    if (!a) {
        set_error(error, "Could not create archive writer.");
        return NULL;
    }

    int level = compression_level;
    if (level < 0) level = 0;
    if (level > 9) level = 9;
    configure_format(a, format, level);

    if (archive_write_open_filename(a, archive_path) != ARCHIVE_OK) {
        set_error(error, "%s", archive_error_string(a) ?: "Could not create archive.");
        archive_write_free(a);
        return NULL;
    }

    UZWriter *writer = calloc(1, sizeof(UZWriter));
    if (!writer) {
        set_error(error, "Out of memory.");
        archive_write_close(a);
        archive_write_free(a);
        unlink(archive_path);
        return NULL;
    }
    writer->a = a;
    writer->path = dup_string(archive_path);
    writer->total = total_bytes;
    writer->entries_total = total_entries;
    writer->progress = progress;
    writer->cancelled = 0;
    return writer;
}

static int writer_progress(UZWriter *writer, const char *path, int force) {
    if (!writer->progress.callback) return 1;
    if (!force && writer->total > 0 && writer->done < writer->total) {
        /* The Swift side throttles UI updates; report often for cancellation. */
    }
    return emit_progress(writer->progress, path, writer->done, writer->total,
                         writer->entries_done, writer->entries_total);
}

static int write_entry_header(UZWriter *writer,
                              const char *entry_path,
                              unsigned int filetype,
                              mode_t perm,
                              time_t mtime,
                              long long size,
                              const char *symlink) {
    struct archive_entry *entry = archive_entry_new();
    if (!entry) return UZ_ERR;

    char *normalized = uz_normalize_path(entry_path);
    if (!normalized) {
        archive_entry_free(entry);
        return UZ_ERR;
    }

    size_t nlen = strlen(normalized);
    if (filetype == AE_IFDIR) {
        if (nlen == 0) { free(normalized); archive_entry_free(entry); return UZ_OK; }
        char *with_slash = malloc(nlen + 2);
        if (!with_slash) { free(normalized); archive_entry_free(entry); return UZ_ERR; }
        memcpy(with_slash, normalized, nlen);
        with_slash[nlen] = '/';
        with_slash[nlen + 1] = '\0';
        archive_entry_set_pathname(entry, with_slash);
        free(with_slash);
    } else {
        archive_entry_set_pathname(entry, normalized);
    }

    archive_entry_set_filetype(entry, filetype);
    archive_entry_set_perm(entry, perm);
    archive_entry_set_mtime(entry, mtime, 0);
    if (filetype == AE_IFREG) {
        archive_entry_set_size(entry, size);
    } else {
        archive_entry_set_size(entry, 0);
    }
    if (symlink) archive_entry_set_symlink(entry, symlink);

    int rc = archive_write_header(writer->a, entry);
    if (rc < ARCHIVE_WARN) {
        archive_entry_free(entry);
        free(normalized);
        return UZ_ERR;
    }
    if (filetype == AE_IFDIR) {
        archive_write_finish_entry(writer->a);
    }
    archive_entry_free(entry);
    free(normalized);
    return UZ_OK;
}

int uz_writer_add(UZWriter *writer,
                  const char *disk_path,
                  const char *entry_path,
                  char **error) {
    if (error) *error = NULL;
    if (!writer || !disk_path || !entry_path) {
        set_error(error, "Invalid arguments.");
        return UZ_ERR;
    }

    struct stat st;
    if (lstat(disk_path, &st) != 0) {
        set_error(error, "Cannot read %s: %s", disk_path, strerror(errno));
        return UZ_ERR;
    }

    if (!writer_progress(writer, entry_path, 1)) {
        writer->cancelled = 1;
        return UZ_ERR_CANCELLED;
    }

    if (S_ISDIR(st.st_mode)) {
        if (write_entry_header(writer, entry_path, AE_IFDIR, st.st_mode & 07777,
                               st.st_mtime, 0, NULL) != UZ_OK) {
            set_error(error, "%s", archive_error_string(writer->a) ?: "Could not add folder.");
            return UZ_ERR;
        }
        writer->entries_done++;
        writer_progress(writer, entry_path, 1);
        return UZ_OK;
    }

    if (S_ISLNK(st.st_mode)) {
        char target[PATH_MAX];
        ssize_t n = readlink(disk_path, target, sizeof(target) - 1);
        if (n < 0) {
            set_error(error, "Cannot read link %s: %s", disk_path, strerror(errno));
            return UZ_ERR;
        }
        target[n] = '\0';
        if (write_entry_header(writer, entry_path, AE_IFLNK, st.st_mode & 07777,
                               st.st_mtime, 0, target) != UZ_OK) {
            set_error(error, "%s", archive_error_string(writer->a) ?: "Could not add link.");
            return UZ_ERR;
        }
        writer->entries_done++;
        writer_progress(writer, entry_path, 1);
        return UZ_OK;
    }

    if (!S_ISREG(st.st_mode)) {
        return UZ_OK;
    }

    if (write_entry_header(writer, entry_path, AE_IFREG, st.st_mode & 07777,
                           st.st_mtime, (long long)st.st_size, NULL) != UZ_OK) {
        set_error(error, "%s", archive_error_string(writer->a) ?: "Could not add file.");
        return UZ_ERR;
    }

    int fd = open(disk_path, O_RDONLY);
    if (fd < 0) {
        set_error(error, "Cannot open %s: %s", disk_path, strerror(errno));
        return UZ_ERR;
    }

    char buffer[256 * 1024];
    ssize_t n;
    while ((n = read(fd, buffer, sizeof(buffer))) > 0) {
        ssize_t written = 0;
        while (written < n) {
            ssize_t w = archive_write_data(writer->a, buffer + written, (size_t)(n - written));
            if (w < 0) {
                set_error(error, "%s", archive_error_string(writer->a) ?: "Could not write archive.");
                close(fd);
                return UZ_ERR;
            }
            if (w == 0) break;
            written += w;
        }
        writer->done += n;
        if (!writer_progress(writer, entry_path, 0)) {
            writer->cancelled = 1;
            close(fd);
            return UZ_ERR_CANCELLED;
        }
    }
    close(fd);
    if (n < 0) {
        set_error(error, "Cannot read %s: %s", disk_path, strerror(errno));
        return UZ_ERR;
    }

    if (archive_write_finish_entry(writer->a) < ARCHIVE_WARN) {
        set_error(error, "%s", archive_error_string(writer->a) ?: "Could not finish file.");
        return UZ_ERR;
    }

    writer->entries_done++;
    writer_progress(writer, entry_path, 1);
    return UZ_OK;
}

int uz_writer_close(UZWriter *writer, char **error) {
    if (error) *error = NULL;
    if (!writer) return UZ_ERR;

    int rc = archive_write_close(writer->a);
    if (rc < ARCHIVE_WARN) {
        set_error(error, "%s", archive_error_string(writer->a) ?: "Could not finish archive.");
    }
    archive_write_free(writer->a);
    int failed = (rc < ARCHIVE_WARN);
    if (failed && writer->path) unlink(writer->path);
    free(writer->path);
    free(writer);
    return failed ? UZ_ERR : UZ_OK;
}

void uz_writer_abort(UZWriter *writer) {
    if (!writer) return;
    archive_write_close(writer->a);
    archive_write_free(writer->a);
    if (writer->path) unlink(writer->path);
    free(writer->path);
    free(writer);
}
