// The macOS SDK ships libarchive and its link stub without public headers.
// Only the stable read-only ZIP ABI is needed here.
#include <sys/types.h>
#include <stdint.h>
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_format_zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
int archive_read_free(struct archive *);
ssize_t archive_read_data(struct archive *, void *, size_t);
const char *archive_entry_pathname(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);
