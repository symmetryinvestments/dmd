module core.internal.gc.impl.conservative.blkcache;
import core.attribute;
import core.memory;

alias BlkInfo = GC.BlkInfo;
alias int delegate(void* addr) nothrow IsMarkedDg;

version(unittest) {
    extern(C) GC.BlkInfo gc_query(void*ptr) @nogc nothrow;
}


/**
  cache for the lookup of the block info
  */
private enum N_CACHE_BLOCKS=8;

// note this is TLS, so no need to sync.
BlkInfo *__blkcache_storage;

static if (N_CACHE_BLOCKS==1)
{
    version=single_cache;
}
else
{
    //version=simple_cache; // uncomment to test simple cache strategy
    //version=random_cache; // uncomment to test random cache strategy

    // ensure N_CACHE_BLOCKS is power of 2.
    static assert(!((N_CACHE_BLOCKS - 1) & N_CACHE_BLOCKS));

    version (random_cache)
    {
        int __nextRndNum = 0;
    }
    int __nextBlkIdx;
}

@property BlkInfo *__blkcache() nothrow @nogc
{
    if (!__blkcache_storage)
    {
        import core.stdc.stdlib;
        import core.stdc.string;
        // allocate the block cache for the first time
        immutable size = BlkInfo.sizeof * N_CACHE_BLOCKS;
        __blkcache_storage = cast(BlkInfo *)malloc(size);
        memset(__blkcache_storage, 0, size);
    }
    return __blkcache_storage;
}

// called when thread is exiting.
@standalone @system static ~this()
{
    // free the blkcache
    if (__blkcache_storage)
    {
        import core.stdc.stdlib;
        free(__blkcache_storage);
        __blkcache_storage = null;
    }
}


// we expect this to be called with the lock in place
// TODO: this is hooked to every GC implementation, we should make sure it only
// gets called when needed.
void processGCMarks(BlkInfo* cache, scope IsMarkedDg isMarked) nothrow
{
    // called after the mark routine to eliminate block cache data when it
    // might be ready to sweep. Clear it out so we don't have stale references
    if(cache)
    {
	cache[0 .. N_CACHE_BLOCKS] = BlkInfo.init;
    }
}

unittest
{
    // Bugzilla 10701 - segfault in GC
    ubyte[] result; result.length = 4096;
    GC.free(result.ptr);
    GC.collect();
}

/**
  Get the cached block info of an interior pointer.  Returns null if the
  interior pointer's block is not cached.

  NOTE: The base ptr in this struct can be cleared asynchronously by the GC,
        so any use of the returned BlkInfo should copy it and then check the
        base ptr of the copy before actually using it.

  TODO: Change this function so the caller doesn't have to be aware of this
        issue.  Either return by value and expect the caller to always check
        the base ptr as an indication of whether the struct is valid, or set
        the BlkInfo as a side-effect and return a bool to indicate success.
  */
BlkInfo *__getBlkInfo(void *interior) nothrow @nogc
{
    if (!__blkcache_storage)
	return null;
    BlkInfo *ptr = __blkcache;
    version (single_cache)
    {
        if (ptr.base && ptr.base <= interior && (interior - ptr.base) < ptr.size)
            return ptr;
        return null; // not in cache.
    }
    else version (simple_cache)
    {
        foreach (i; 0..N_CACHE_BLOCKS)
        {
            if (ptr.base && ptr.base <= interior && (interior - ptr.base) < ptr.size)
                return ptr;
            ptr++;
        }
    }
    else
    {
        // try to do a smart lookup, using __nextBlkIdx as the "head"
        auto curi = ptr + __nextBlkIdx;
	auto i = curi;
	/*version(unittest) {
	    scope(exit) {
		if(i)
		{
		    // validate the cache always matches the real value
		    auto realblk = gc_query(interior);
		    assert(*i == realblk);
		}
	    }
	}*/

        for (; i >= ptr; --i)
        {
            if (i.base && i.base <= interior && cast(size_t)(interior - i.base) < i.size)
                return i;
        }

        for (i = ptr + N_CACHE_BLOCKS - 1; i > curi; --i)
        {
            if (i.base && i.base <= interior && cast(size_t)(interior - i.base) < i.size)
                return i;
        }
	version(unittest) i = null;
    }
    return null; // not in cache.
}

void __insertBlkInfoCache(BlkInfo bi, BlkInfo *curpos) nothrow @nogc
{
    version (single_cache)
    {
        *__blkcache = bi;
    }
    else
    {
        version (simple_cache)
        {
            if (curpos)
                *curpos = bi;
            else
            {
                // note, this is a super-simple algorithm that does not care about
                // most recently used.  It simply uses a round-robin technique to
                // cache block info.  This means that the ordering of the cache
                // doesn't mean anything.  Certain patterns of allocation may
                // render the cache near-useless.
                __blkcache[__nextBlkIdx] = bi;
                __nextBlkIdx = (__nextBlkIdx+1) & (N_CACHE_BLOCKS - 1);
            }
        }
        else version (random_cache)
        {
            // strategy: if the block currently is in the cache, move the
            // current block index to the a random element and evict that
            // element.
            auto cache = __blkcache;
            if (!curpos)
            {
                __nextBlkIdx = (__nextRndNum = 1664525 * __nextRndNum + 1013904223) & (N_CACHE_BLOCKS - 1);
                curpos = cache + __nextBlkIdx;
            }
            else
            {
                __nextBlkIdx = curpos - cache;
            }
            *curpos = bi;
        }
        else
        {
            //
            // strategy: If the block currently is in the cache, swap it with
            // the head element.  Otherwise, move the head element up by one,
            // and insert it there.
            //
            auto cache = __blkcache;
            if (!curpos)
            {
                __nextBlkIdx = (__nextBlkIdx+1) & (N_CACHE_BLOCKS - 1);
                curpos = cache + __nextBlkIdx;
            }
            else if (curpos !is cache + __nextBlkIdx)
            {
                *curpos = cache[__nextBlkIdx];
                curpos = cache + __nextBlkIdx;
            }
            *curpos = bi;
        }
    }
}

debug(PRINTF)
{
    extern(C) void printArrayCache()
    {
        auto ptr = __blkcache;
        printf("CACHE: \n");
        foreach (i; 0 .. N_CACHE_BLOCKS)
        {
            printf("  %d\taddr:% .8x\tsize:% .10d\tused:% .10d\n", i, ptr[i].base, ptr[i].size, ptr[i].used);
        }
    }
}
