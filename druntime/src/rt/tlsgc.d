/**
 *
 * Copyright: Copyright Digital Mars 2011 - 2012.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Martin Nowak
 * Source: $(DRUNTIMESRC rt/tlsgc.d)
 */

/*          Copyright Digital Mars 2011.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module rt.tlsgc;

import core.stdc.stdlib;

static import rt.lifetime, rt.sections;
import blkcache = core.internal.gc.impl.conservative.blkcache;

/**
 * Per thread record to store thread associated data for garbage collection.
 */
struct Data
{
    typeof(rt.sections.initTLSRanges()) tlsRanges;
    blkcache.BlkInfo** blockInfoCache;
}

/**
 * Initialization hook, called FROM each thread. No assumptions about
 * module initialization state should be made.
 */
void* init() nothrow @nogc
{
    auto data = cast(Data*).malloc(Data.sizeof);
    import core.exception;
    if ( data is null ) core.exception.onOutOfMemoryError();
    *data = Data.init;

    // do module specific initialization
    data.tlsRanges = rt.sections.initTLSRanges();
    data.blockInfoCache = &blkcache.__blkcache_storage;

    return data;
}

/**
 * Finalization hook, called FOR each thread. No assumptions about
 * module initialization state should be made.
 */
void destroy(void* data) nothrow @nogc
{
    // do module specific finalization
    rt.sections.finiTLSRanges((cast(Data*)data).tlsRanges);

    .free(data);
}

alias void delegate(void* pstart, void* pend) nothrow ScanDg;

/**
 * GC scan hook, called FOR each thread. Can be used to scan
 * additional thread local memory.
 */
void scan(void* data, scope ScanDg dg) nothrow
{
    // do module specific marking
    rt.sections.scanTLSRanges((cast(Data*)data).tlsRanges, dg);
}

/**
 * GC sweep hook, called FOR each thread. Can be used to free
 * additional thread local memory or associated data structures. Note
 * that only memory allocated from the GC can have marks.
 */
void processGCMarks(void* data, scope blkcache.IsMarkedDg dg) nothrow
{
    // do module specific sweeping
    blkcache.processGCMarks(*(cast(Data*)data).blockInfoCache, dg);
}
