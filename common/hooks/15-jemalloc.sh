# shellcheck shell=bash
# Octail hook (Java images): jemalloc instead of glibc's malloc when JEMALLOC=1 (off by default).
#
# The Java heap is not malloc'd, but everything native a Minecraft server does is: Netty buffers, zlib/zstd
# (chunk and packet compression), the JIT, threads' own arenas. glibc keeps up to 8 arenas per CPU and returns freed
# memory to the kernel late, so on a busy server the container's memory use creeps hundreds of MB above heap + metaspace
# and can reach the container limit (an OOM kill) although the heap is fine. jemalloc packs and returns that memory;
# MALLOC_CONF tunes it (e.g. MALLOC_CONF=background_thread:true). The image ships Ubuntu's libjemalloc2.
#
# The library is preloaded (LD_PRELOAD) only after a test run proves it loads on this host (jemalloc refuses kernels
# with a larger page size than it was built for, e.g. some 64K-page arm64 kernels); otherwise glibc stays and the
# console says why. OCTAIL_JEMALLOC_LIB names another library (the tests use it); images don't set it.

octail_jemalloc() {
	case "${JEMALLOC:-0}" in
	1 | true | TRUE | yes) ;;
	*) return 0 ;;
	esac
	local lib=${OCTAIL_JEMALLOC_LIB:-} candidate err
	if [ -z "${lib}" ]; then
		for candidate in /usr/lib/*-linux-gnu/libjemalloc.so.2 /usr/lib/libjemalloc.so.2; do
			if [ -f "${candidate}" ]; then
				lib=${candidate}
				break
			fi
		done
	fi
	if [ -z "${lib}" ] || [ ! -f "${lib}" ]; then
		echo "octail: JEMALLOC=1 but this image has no jemalloc; using glibc malloc"
		return 0
	fi
	# ld.so only warns (exit 0) about a library it can't preload, so any output counts as a failure.
	if ! err=$(LD_PRELOAD=${lib} env true 2>&1) || [ -n "${err}" ]; then
		echo "octail: jemalloc (${lib}) does not load here; using glibc malloc: ${err%%$'\n'*}"
		return 0
	fi
	export LD_PRELOAD="${lib}${LD_PRELOAD:+:${LD_PRELOAD}}"
	echo "octail: jemalloc on (${lib})"
}
octail_jemalloc
unset -f octail_jemalloc
