import core.gc.registry;
import core.gc.gcinterface;
import core.stdc.stdlib;

static import core.memory;

extern (C) __gshared string[] rt_options = ["gcopt=gc:malloc"];

extern (C) pragma(crt_constructor) void register_mygc()
{
    registerGCFactory("malloc", &MallocGC.initialize);
}

extern (C) void register_default_gcs()
{
    // remove default GCs
}

/** Simple GC that requires any pointers passed to it's API
    to point to start of the allocation.
 */
class MallocGC : GC
{
    BlkInfo qalloc(size_t size, uint bits, const scope TypeInfo ti) nothrow
    {
        return BlkInfo(GC.malloc(size, bits, ti), size);
    }

nothrow @nogc:
    static GC initialize()
    {
        import core.stdc.string : memcpy;

        __gshared align(__traits(classInstanceAlignment, MallocGC))
            ubyte[__traits(classInstanceSize, MallocGC)] buf;

        auto init = typeid(MallocGC).initializer();
        assert(init.length == buf.length);
        auto instance = cast(MallocGC) memcpy(buf.ptr, init.ptr, init.length);
        instance.__ctor();
        return instance;
    }

    this()
    {
    }

    void Dtor()
    {
    }

    void enable()
    {
    }

    void disable()
    {
    }

    void collect() nothrow
    {
    }

    void collectNoStack() nothrow
    {
    }

    void minimize() nothrow
    {
    }

    uint getAttr(void* p) nothrow
    {
        return 0;
    }

    uint setAttr(void* p, uint mask) nothrow
    {
        return mask;
    }

    uint clrAttr(void* p, uint mask) nothrow
    {
        return mask;
    }

    void* malloc(size_t size, uint bits, const void* context, immutable size_t *ptrbitmap) nothrow
    {
        return sentinelAdd(.malloc(size + sentinelSize), size);
    }

    void* calloc(size_t size, uint bits, const void *context, immutable size_t *ptrbitmap) nothrow
    {
        return sentinelAdd(.calloc(1, size + sentinelSize), size);
    }

    void* realloc(void* p, size_t size, uint bits, immutable size_t *ptrbitmap) nothrow
    {
        return sentinelAdd(.realloc(p - sentinelSize, size + sentinelSize), size);
    }

    size_t extend(void* p, size_t minsize, size_t maxsize) nothrow
    {
        return 0;
    }

    size_t reserve(size_t size) nothrow
    {
        return 0;
    }

    void free(void* p) nothrow
    {
        free(p - sentinelSize);
    }

    void* addrOf(void* p) nothrow
    {
        return p;
    }

    size_t sizeOf(void* p) nothrow
    {
        return query(p).size;
    }

    BlkInfo query(void* p) nothrow
    {
        return p ? BlkInfo(p, sentinelGetBlockSize(p)) : BlkInfo.init;
    }

    core.memory.GC.Stats stats() nothrow
    {
        return core.memory.GC.Stats.init;
    }

    core.memory.GC.ProfileStats profileStats() nothrow
    {
        return typeof(return).init;
    }

    void addRoot(void* p) nothrow @nogc
    {
    }

    void removeRoot(void* p) nothrow @nogc
    {
    }

    @property RootIterator rootIter() @nogc
    {
        return null;
    }

    void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc
    {
    }

    void removeRange(void* p) nothrow @nogc
    {
    }

    @property RangeIterator rangeIter() @nogc
    {
        return null;
    }

    void runFinalizers(const scope void[] segment) nothrow
    {
    }

    bool inFinalizer() nothrow
    {
        return false;
    }

    ulong allocatedInCurrentThread() nothrow
    {
        return stats().allocatedInCurrentThread;
    }

    ArrayMetadata getArrayMetadata(void *ptr) @nogc nothrow @trusted
    {
        return ptr ? ArrayMetadata(ptr, sentinelGetBlockSize(ptr)) : ArrayMetadata.init;
    }

    bool setArrayUsed(ref ArrayMetadata metadata, size_t newUsed, size_t existingUsed = ~0UL, bool atomic = false) nothrow @nogc @trusted
    {
        if(metadata.base)
        {
            if(newUsed > metadata.size)
                return false;

            size_t *usedptr = sentinelGetUsedSize(metadata.base);
            if(existingUsed == -1 || *usedptr == existingUsed)
            {
                *usedptr = newUsed;
                return true;
            }
        }
        return false;
    }

    /**
     * get the array used data size. You must use a metadata struct that you
     * got from the same GC instance.
     * Generally called via the ArrayMetadata method.
     */
    size_t getArrayUsed(ref ArrayMetadata metadata, bool atomic = false) nothrow @nogc @trusted
    {
        return metadata.base ? *sentinelGetUsedSize(metadata.base) : 0;
    }

private:
    // doesn't care for alignment
    static void* sentinelAdd(void* p, size_t value) nothrow @nogc
    {
        auto metadata = cast(size_t*)p;
        metadata[0] = value;
        metadata[1] = value;
        return p + sentinelSize;
    }

    static size_t sentinelGetBlockSize(void* p) nothrow @nogc
    {
        return *cast(size_t*)(p - sentinelSize);
    }

    static size_t* sentinelGetUsedSize(void* p)
    {
        return cast(size_t*)(p - sentinelSize) + 1;
    }

    enum sentinelSize = size_t.sizeof * 2; // block size and used data
}

void main()
{
    // test array append cache
    char[] s;
    foreach (char c; char.min .. char.max + 1)
        s ~= c;
}
