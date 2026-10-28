#include "../Sources/CSArchive/include/CSArchive.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int progress(void *ctx, const char *path, long long done, long long total,
                    int entries_done, int entries_total) {
    (void)ctx;
    fprintf(stderr, "  [%d/%d] %s %.1f%%\n", entries_done, entries_total, path,
            total > 0 ? (double)done * 100.0 / (double)total : 100.0);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: ctest list <archive> | extract <archive> <dest> | create <archive> <format> <root>...\n"); return 2; }
    const char *cmd = argv[1];

    if (strcmp(cmd, "list") == 0) {
        if (argc < 3) return 2;
        UZEntry *entries = NULL;
        int count = 0;
        char *format = NULL, *filter = NULL, *error = NULL;
        if (uz_list(argv[2], &entries, &count, &format, &filter, &error) != UZ_OK) {
            fprintf(stderr, "list error: %s\n", error ? error : "unknown");
            return 1;
        }
        printf("format=%s filter=%s count=%d\n", format, filter, count);
        for (int i = 0; i < count; i++) {
            printf("%4d %c %10lld %s%s\n", i, entries[i].is_dir ? 'd' : '-',
                   entries[i].size, entries[i].pathname,
                   entries[i].is_encrypted ? " [encrypted]" : "");
        }
        uz_free_entries(entries, count);
        uz_free_string(format);
        uz_free_string(filter);
        return 0;
    }

    if (strcmp(cmd, "extract") == 0) {
        if (argc < 4) return 2;
        char *error = NULL;
        UZProgress p = { progress, NULL };
        int rc = uz_extract(argv[2], argv[3], NULL, 0, 0, NULL, 1, 0, p, &error);
        if (rc != UZ_OK) {
            fprintf(stderr, "extract error (%d): %s\n", rc, error ? error : "unknown");
            return 1;
        }
        printf("extracted OK\n");
        return 0;
    }

    if (strcmp(cmd, "create") == 0) {
        if (argc < 5) return 2;
        const char *archive_path = argv[2];
        const char *format = argv[3];
        char *error = NULL;
        UZProgress p = { progress, NULL };
        UZWriter *w = uz_writer_open(archive_path, format, 6, 0, argc - 4, p, &error);
        if (!w) { fprintf(stderr, "open error: %s\n", error ? error : "unknown"); return 1; }
        for (int i = 4; i < argc; i++) {
            const char *root = argv[i];
            const char *base = strrchr(root, '/');
            base = base ? base + 1 : root;
            int rc = uz_writer_add(w, root, base, &error);
            if (rc != UZ_OK) {
                fprintf(stderr, "add error: %s\n", error ? error : "unknown");
                uz_writer_abort(w);
                return 1;
            }
        }
        if (uz_writer_close(w, &error) != UZ_OK) {
            fprintf(stderr, "close error: %s\n", error ? error : "unknown");
            return 1;
        }
        printf("created OK\n");
        return 0;
    }

    return 2;
}
