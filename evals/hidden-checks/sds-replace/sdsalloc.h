/* Reviewer-only allocator for the sds-replace probe: counts live blocks and can fail the
 * Nth allocation. Copied next to the workspace's sds.c, which includes it by name. */
#include <stddef.h>
void *probe_malloc(size_t size);
void *probe_realloc(void *ptr, size_t size);
void probe_free(void *ptr);
#define s_malloc probe_malloc
#define s_realloc probe_realloc
#define s_free probe_free
