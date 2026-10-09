# shellcheck shell=bash
# Octail hook (Java images): show which Java the server gets, so a version mismatch is easy to spot.
if command -v java >/dev/null 2>&1; then
	java -version 2>&1 | head -n 1 | sed 's/^/octail: /'
fi
