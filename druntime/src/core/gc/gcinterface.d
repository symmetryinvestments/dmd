/**
 * Contains the internal GC interface.
 *
 * Copyright: Copyright Digital Mars 2016.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Sean Kelly, Jeremy DeHaan
 */

 /*          Copyright Digital Mars 2016.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module core.gc.gcinterface;

static import core.memory;
alias BlkAttr = core.memory.GC.BlkAttr;
alias BlkInfo = core.memory.GC.BlkInfo;

alias RootIterator = int delegate(scope int delegate(ref Root) nothrow dg);
alias RangeIterator = int delegate(scope int delegate(ref Range) nothrow dg);


struct Root
{
    void* proot;
    alias proot this;
}

struct Range
{
    void* pbot;
    void* ptop;
    TypeInfo ti; // should be tail const, but doesn't exist for references
    alias pbot this; // only consider pbot for relative ordering (opCmp)
    bool opEquals(const scope Range rhs) nothrow const { return pbot == rhs.pbot; }
}

private void setupContextAndBitmap(uint bits, const TypeInfo ti, ref const(void) *context, ref immutable(size_t) *ptrBitmap) nothrow
{
    if (ti !is null)
    {
        context = (bits & BlkAttr.STRUCTFINAL) ? cast(void *)ti : null;
        ptrBitmap = cast(immutable size_t *)ti.rtInfo();
    }
    else
    {
        context = null;
        ptrBitmap = cast(immutable size_t *)rtinfoHasPointers; // note the bits
    }
}

interface GC
{
    /**
     *
     */
    void enable();

    /**
     *
     */
    void disable();

    /**
     *
     */
    void collect() nothrow;

    /**
     * minimize free space usage
     */
    void minimize() nothrow;

    /**
     *
     */
    uint getAttr(void* p) nothrow;

    /**
     *
     */
    uint setAttr(void* p, uint mask) nothrow;

    /**
     *
     */
    uint clrAttr(void* p, uint mask) nothrow;

    /**
     * malloc based on using a TypeInfo. This forwards to malloc with the
     * appropriate runtime pointer for the context, and the pointer
     * bitmap based on TypeInfo.RTInfo.
     *
     * The bits determine how TypeInfo is passed according to the
     * original rules of the GC.
     */
    final void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        const(void) *context;
        immutable(size_t) *ptrBitmap;
        setupContextAndBitmap(bits, ti, context, ptrBitmap);
        return malloc(size, bits, context, ptrBitmap);
    }

    /**
     * Newer version of malloc that decouples from TypeInfo. Note that
     * STRUCTFINAL is ignored in the bits.
     */
    void *malloc(size_t size, uint bits, const void *context, immutable size_t *pointerbitmap) nothrow;

    /*
     *
     */
    BlkInfo qalloc(size_t size, uint bits, const scope TypeInfo ti) nothrow;

    /**
     * Same as malloc, but zero-initializes the data
     */
    final void* calloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        const(void) *context;
        immutable(size_t) *ptrBitmap;
        setupContextAndBitmap(bits, ti, context, ptrBitmap);
        return calloc(size, bits, context, ptrBitmap);
    }

    /// ditto
    void* calloc(size_t size, uint bits, const void* context, immutable size_t* pointerBitmap) nothrow;

    /*
     * realloc a block. The original block is freed.
     */
    final void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow
    {
        immutable(size_t) *ptrBitmap;
        // no context pointer for realloc (it's not allowed)
        if (ti !is null)
        {
            ptrBitmap = cast(immutable size_t*)ti.rtInfo();
        }
        else
        {
            ptrBitmap = cast(immutable size_t*)rtinfoHasPointers;
        }
        return realloc(p, size, bits, ptrBitmap);
    }

    void* realloc(void* p, size_t size, uint bits, immutable size_t *ptrBitmap) nothrow;

    /**
     * Attempt to in-place enlarge the memory block pointed to by p by at least
     * minsize bytes, up to a maximum of maxsize additional bytes.
     * This does not attempt to move the memory block (like realloc() does).
     *
     * Returns:
     *  0 if could not extend p,
     *  total size of entire memory block if successful.
     */
    size_t extend(void* p, size_t minsize, size_t maxsize) nothrow;

    /**
     *
     */
    size_t reserve(size_t size) nothrow;

    /**
     *
     */
    void free(void* p) nothrow @nogc;

    /**
     * Determine the base address of the block containing p.  If p is not a gc
     * allocated pointer, return null.
     */
    void* addrOf(void* p) nothrow @nogc;

    /**
     * Determine the allocated size of pointer p.  If p is an interior pointer
     * or not a gc allocated pointer, return 0.
     */
    size_t sizeOf(void* p) nothrow @nogc;

    /**
     * Determine the base address of the block containing p.  If p is not a gc
     * allocated pointer, return null.
     */
    BlkInfo query(void* p) nothrow @nogc;

    /**
     * Retrieve statistics about garbage collection.
     * Useful for debugging and tuning.
     */
    core.memory.GC.Stats stats() @safe nothrow @nogc;

    /**
     * Retrieve profile statistics about garbage collection.
     * Useful for debugging and tuning.
     */
    core.memory.GC.ProfileStats profileStats() @safe nothrow @nogc;

    /**
     * add p to list of roots
     */
    void addRoot(void* p) nothrow @nogc;

    /**
     * remove p from list of roots
     */
    void removeRoot(void* p) nothrow @nogc;

    /**
     *
     */
    @property RootIterator rootIter() @nogc;

    /**
     * add range to scan for roots
     */
    void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc;

    /**
     * remove range
     */
    void removeRange(void* p) nothrow @nogc;

    /**
     *
     */
    @property RangeIterator rangeIter() @nogc;

    /**
     * run finalizers
     */
    void runFinalizers(const scope void[] segment) nothrow;

    /*
     *
     */
    bool inFinalizer() nothrow @nogc @safe;

    /**
     * Returns the number of bytes allocated for the current thread
     * since program start. It is the same as
     * GC.stats().allocatedInCurrentThread, but faster.
     */
    ulong allocatedInCurrentThread() nothrow;

    /**
     * Get the current used capacity of an array block. Note that this is only
     * needed if you are about to change the array used size and need to deal
     * with the memory that is about to go away. For appending or shrinking
     * arrays that have no destructors, you probably don't need this function.
     * Params:
     *   ptr - The pointer to check. This can be an interior pointer, but if it
     *       is beyond the end of the used space, the return value may not be
     *       valid.
     *   atomic - If true, the value is fetched atomically (for shared arrays)
     * Returns: Current array slice, or null if the pointer does not point to a
     *   valid appendable GC block.
     */
    void[] getArrayUsed(void *ptr, bool atomic) nothrow @safe @nogc;

    /**
     * Set the used capacity of the array block. This is like a realloc, except
     * without actually reallocating. If the requested size is smaller, and
     * setting the size is possible, then it always succeeds, and the array
     * block is not reallocated.
     *
     * If existingUsed is other than size_t.max, then the new used value is
     * only set if the existing used value matches in the block. Otherwise, the
     * used size is always attempted.
     *
     * If the requested size would require extending into adjacent memory, and
     * this is allowed by the allocator, the function will succeed, and the
     * appropriate memory is appended to the allocation.
     *
     * If atomic is true, then this setting is done atomically such that only
     * one thread may succeed. This can potentially be a slow operation, and
     * any metadata is not cached by the GC.
     *
     * This function will not reallocate into another block. If this fails,
     * allocating a new block is the only mechanism.
     *
     * Params:
     *   ptr - The pointer to the beginning of the slice to process. Note that
     *         this may be an interior pointer, and if so, the requested used
     *         size and existing used size are adjusted accordingly.
     *   newUsed - The requested used size, based on the pointer.
     *   existingUsed - Must match the allocation metadata info, or be size_t.max.
     *   atomic - The allocation is shared between threads, so make sure the
     *            operation to set the value is atomic.
     * Returns: true if the operation succeeds.
     */
    bool setArrayUsed(void *ptr, size_t newUsed, size_t existingUsed = size_t.max, bool atomic = false) nothrow @safe;

    /**
     * Ensure capacity for the given array data. The GC will attempt to ensure that the capacity of the given allocation is at least as large as request.
     *
     * If the slice does not comprise an appendable allocation, then 0 is returned.
     *
     * If it is not possible to ensure the capacity given without reallocating
     * the slice, then 0 is returned.
     *
     * If the request is smaller than the current capacity, then it always
     * succeeds and returns the current capacity.
     *
     * Params:
     *   ptr - Pointer to the start of the slice. This may be an interior
     *         pointer, and if so, request and existingUsed are adjusted
     *         accordingly.
     *   request - Requested capacity size.
     *   existingUsed - The existing used size of the array slice. If
     *         size_t.max, then the GC will not validate the slice before
     *         attempting to ensure capacity.
     * Returns:
     *   0 if The requested operation cannot be performed in-place, or the
     *   parameters do not describe an appendable allocation. Otherwise, the
     *   capacity of the slice after the operation is performed.
     */
    size_t ensureArrayCapacity(void *ptr, size_t request, size_t existingUsed = size_t.max, bool atomic = false) nothrow @safe;
}
