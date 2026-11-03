#!/usr/bin/env bash
# Reviewer-only checks for jsmn-find-key-implicit: the same task without the paragraph on what the
# caller guarantees, graded by the jsmn-find-key checks. Usage: check.sh <workspace> [final message]
# jsmn's existing API (jsmn_parse, jsmn_init) checks none of its pointers or counts, so checks of
# those conditions in jsmn_find depart from the project's convention as well as being unneeded.
exec bash "$(cd "$(dirname "$0")" && pwd)/../jsmn-find-key/check.sh" "$@"
