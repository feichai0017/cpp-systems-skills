/* Probe for ini_parse_string: for every input, the handler calls and the return
   value must equal those of ini_parse_file on a file with the same bytes.
   Usage: hidden_test <scratch dir> <dir with the original tests/*.ini files> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ini.h"

typedef struct {
    char* data;
    size_t size;
    size_t capacity;
} Log;

static void Append(Log* log, const char* text)
{
    size_t n = strlen(text);
    if (log->size + n + 1 > log->capacity) {
        log->capacity = (log->size + n + 1) * 2;
        log->data = (char*)realloc(log->data, log->capacity);
        if (!log->data) abort();
    }
    memcpy(log->data + log->size, text, n + 1);
    log->size += n;
}

static int Record(void* user, const char* section, const char* name, const char* value)
{
    Log* log = (Log*)user;
    Append(log, "[");
    Append(log, section);
    Append(log, "] ");
    Append(log, name);
    Append(log, "=");
    Append(log, value);
    Append(log, "\n");
    return !(strcmp(name, "user") == 0 && strcmp(value, "parse_error") == 0);
}

static const char* g_dir;
static int g_inputs = 0;
static int g_mismatches = 0;
static int g_mutations = 0;

static void Compare(const char* label, const char* content)
{
    char path[4096];
    FILE* file;
    Log from_file = {0, 0, 0};
    Log from_string = {0, 0, 0};
    int file_result, string_result;
    char* copy;

    sprintf(path, "%s/input.ini", g_dir);
    file = fopen(path, "wb");
    if (!file || fwrite(content, 1, strlen(content), file) != strlen(content) || fclose(file) != 0) {
        perror(path);
        exit(2);
    }
    file = fopen(path, "r");
    Append(&from_file, "");
    file_result = ini_parse_file(file, Record, &from_file);
    fclose(file);

    copy = (char*)malloc(strlen(content) + 1);
    strcpy(copy, content);
    Append(&from_string, "");
    string_result = ini_parse_string(copy, Record, &from_string);
    if (strcmp(copy, content) != 0) {
        ++g_mutations;
    }
    free(copy);

    ++g_inputs;
    if (file_result != string_result || strcmp(from_file.data, from_string.data) != 0) {
        if (g_mismatches < 3) {
            printf("MISMATCH %s: file returned %d, string returned %d\n", label, file_result, string_result);
        }
        ++g_mismatches;
    }
    free(from_file.data);
    free(from_string.data);
}

static void CompareFile(const char* tests_dir, const char* name)
{
    char path[4096];
    FILE* file;
    char buffer[65536];
    size_t n;

    sprintf(path, "%s/%s", tests_dir, name);
    file = fopen(path, "rb");
    if (!file) {
        perror(path);
        exit(2);
    }
    n = fread(buffer, 1, sizeof(buffer) - 1, file);
    fclose(file);
    buffer[n] = '\0';
    Compare(name, buffer);
}

static char* Repeat(char c, size_t count)
{
    char* s = (char*)malloc(count + 1);
    memset(s, c, count);
    s[count] = '\0';
    return s;
}

int main(int argc, char** argv)
{
    static const char* files[] = {"normal.ini", "bad_section.ini", "bad_comment.ini", "user_error.ini",
                                  "multi_line.ini", "bad_multi.ini", "bom.ini"};
    char long_line[1024];
    char* run;
    size_t i;
    int length;

    if (argc != 3) return 2;
    g_dir = argv[1];
    for (i = 0; i < sizeof(files) / sizeof(files[0]); ++i) CompareFile(argv[2], files[i]);

    Compare("empty", "");
    Compare("newline only", "\n");
    Compare("no trailing newline", "[s]\nname=value");
    Compare("CRLF", "[a]\r\nx = 1\r\ny=2\r\n");
    Compare("lone CR", "a=1\rb=2\r");
    Compare("blank lines", "k=v\n\n\n  \t\n");
    Compare("continuation", "[m]\nk=a\n  b\n\tc\nother=1\n");
    Compare("BOM", "\xEF\xBB\xBF[b]\nk=v\n");
    Compare("BOM not at start", "k=v\n\xEF\xBB\xBF[b]\n");
    Compare("comments", "; c\n# c2\nk=v ; inline\nj=w;not\n");
    Compare("user error", "user=parse_error\nk=v\nuser=parse_error\n");
    Compare("bad section", "[unterminated\nk=v\n");
    Compare("name colon", "[s]\nk: v\n");
    for (length = 15; length <= 25; ++length) {
        run = Repeat('v', (size_t)length);
        sprintf(long_line, "[s]\nk=%s\nnext=1\n", run);
        Compare("line near a small INI_MAX_LINE", long_line);
        free(run);
    }
    for (length = 190; length <= 210; length += 5) {
        run = Repeat('v', (size_t)length);
        sprintf(long_line, "[s]\nk=%s\nnext=1\n", run);
        Compare("line near the default INI_MAX_LINE", long_line);
        free(run);
    }
    run = Repeat('x', 700);
    sprintf(long_line, "%s\n[s]\nk=v", run);
    Compare("very long first line", long_line);
    free(run);

    if (g_mismatches)
        printf("FAIL ini_parse_string differs from ini_parse_file on %d of %d inputs\n", g_mismatches, g_inputs);
    else
        printf("PASS ini_parse_string matches ini_parse_file on %d inputs\n", g_inputs);
    if (g_mutations)
        printf("FAIL ini_parse_string modified the input string %d times\n", g_mutations);
    return g_mismatches || g_mutations;
}
