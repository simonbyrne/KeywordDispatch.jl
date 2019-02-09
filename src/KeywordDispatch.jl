module KeywordDispatch

export @kwdispatch, @kwmethod

function ntsort(nt::NamedTuple{N}) where {N}
    if @generated
        names = tuple(sort(collect(N))...)
        types = Tuple{Any[ fieldtype(nt, n) for n in names ]...}
        vals = Any[ :(getfield(nt, $(QuoteNode(n)))) for n in names ]
        :( NamedTuple{$names,$types}(($(vals...),)) )
    else
        names = tuple(sort(collect(N))...)
        types = Tuple{Any[ fieldtype(typeof(nt), n) for n in names ]...}
        vals = map(n->getfield(nt, n), names)
        NamedTuple{names,types}(vals)
    end
end

# given an argument, output a form appropriate for a method definition in pass-through methods
# currently:
#  - replaces underscores with new symbols
#    g(_) => g(newsym)
#  - replaces tuples with a single symbol
#    g((a,b)) => g(newsym)
#  - inserts symbols for 1-arg ::,
#    g(::T)   => g(newsym::T)
argmeth(x::Symbol) = x == :_ ? gensym() : x
function argmeth(x::Expr)
    x.head == :tuple && return gensym()
    x.head == :(::)  && return :($(length(x.args)==1 ? gensym() : argmeth(x.args[1]))::$(x.args[end]))
    x.head == :...   && return Expr(:..., argmeth.(x.args)...)
    return x
end

# given an argument, output a form appropriate for a method call in pass-through methods
# currently:
#  - removes the :: part
#    g(x::T)   => g(x)
argsym(x::Symbol) = x
function argsym(x::Expr)
    x.head == :(::) && return length(x.args) > 1 ? x.args[1] : :_
    x.head == :...  && return Expr(:..., argsym.(x.args)...)
    return x
end

# given an argument, output an argument type
# currently:
#  - g(x::T)  => T
#  - g(x)     => Any
argtype(x::Symbol) = Any
argtype(x::Expr) = x.head == :(::) ? x.args[end] : error("unexpected expression $x")


struct KeywordMethodError <: Exception
    f
    args
    kwargs
    KeywordMethodError(@nospecialize(f), @nospecialize(args), @nospecialize(kwargs)) = new(f, args, kwargs)
end

function Base.showerror(io::IO, err::KeywordMethodError)
    print(io, "KeywordMethodError: no keyword method matching ")
    if err.f isa Function || err.f isa Type
        print(io, err.f)
    else
        print(io, "(::", typeof(err.f), ")")
    end
    print(io, "(")
    for (i, arg) in enumerate(err.args)
        print(io, "::", typeof(arg))
        if i != length(err.args)
            print(io, ", ")
        end
    end
    print(io, "; ")
    for (i, (kw,kwarg)) in enumerate(pairs(err.kwargs))
        print(io, kw, "::", typeof(kwarg))
        if i != length(err.kwargs)
            print(io, ", ")
        end
    end
    print(io, ")")
end

function kwcall(nt::NamedTuple, f, args...)
    throw(KeywordMethodError(f, args, nt))
end


"""
    @kwdispatch expr

Designate a function signature `expr` that should dispatch on keyword arguments. A
function can also be provided, in which case _all_ calls to that function are will
dispatch to keyword methods.

Note that no keywords should appear in `@kwdispatch` signatures. To define the keyword
methods, use the [`@kwmethod`](@ref) macro.

# Examples

```julia
@kwdispatch f(_)
@kwdispatch f(_::Real)

@kwdispacth f # equivalent to @kwdispatch f(_...)

```
"""
macro kwdispatch(fexpr)
    fexpr = outexpr = :($fexpr = _)

    # unwrap where clauses
    while fexpr.args[1] isa Expr && fexpr.args[1].head == :where
        fexpr = fexpr.args[1]
        fexpr.args[2] = esc(fexpr.args[2])
    end
    fcall = fexpr.args[1]

    # handle: `fun`, `Mod.fun`, `(a::B)`
    if fcall isa Symbol || fcall isa Expr && (fcall.head in (:., :(::), :curly))
        fcall = :($fcall(_...))
    end

    @assert fcall isa Expr && fcall.head == :call

    f = fcall.args[1]
    fargs = fcall.args[2:end]
    if length(fargs) >= 1 && fargs[1] isa Expr && fargs[1].head == :parameters
        error("keyword arguments should only appear in @kwdispatch expressions")
    end
    f = argmeth(f)

    if f isa Expr && f.head == :(::)
        ftype = esc(f.args[end])
    else
        ftype = :(typeof($(esc(f))))
    end

    fargs_method = argmeth.(fargs)
    fexpr.args[1] = :($(esc(f))($(esc.(fargs_method)...); kwargs...))

    outexpr.args[2] = :(kwcall(ntsort(kwargs.data), $(esc(argsym(f))), $(esc.(argsym.(fargs_method))...)))
    return outexpr
end

"""
    @kwmethod expr

Define a keyword method for dispatch. `expr` should be a standard function definition
(either block or inline) with a keyword argument block (which may be empty).

The positional signature should first be designated by the [`@kwdispatch`](@ref) macro.

# Examples

```julia
@kwdispatch f() # designate the no positional argument form

@kwmethod f(;) = nothing # no keyword arguments
@kwmethod f(;a) = a
@kwmethod f(;b) = 2*b
@kwmethod f(;a,b) = a+2*b
```
"""
macro kwmethod(fexpr)
    @assert fexpr isa Expr && fexpr.head in (:function, :(=))
    fexpr.args[2] = esc(fexpr.args[2])

    outexpr = fexpr
    # unwrap where clauses
    while fexpr.args[1] isa Expr && fexpr.args[1].head == :where
        fexpr = fexpr.args[1]
        fexpr.args[2] = esc(fexpr.args[2])
    end

    fcall = fexpr.args[1]
    @assert fcall isa Expr && fcall.head == :call

    f = fcall.args[1]

    length(fcall.args) >= 2 && fcall.args[2] isa Expr && fcall.args[2].head == :parameters ||
        error("@kwmethod requires functions specify a keyword block.\nUse @kwmethod `f(args...;)` to specify no keywords.")

    kwargs = fcall.args[2].args
    fargs = fcall.args[3:end]

    sort!(kwargs, by=argsym)

    kwsyms = argsym.(kwargs)
    kwtypes = argtype.(kwargs)

    if f isa Expr && f.head == :(::)
        F = esc(f)
    else
        F = :(::($(esc(f)) isa Type ? Type{$(esc(f))} : typeof($(esc(f)))))
    end

    fexpr.args[1] = :(KeywordDispatch.kwcall(($(esc.(kwsyms)...),)::NamedTuple{($(QuoteNode.(kwsyms)...),),T},
                                             $F,
                                             $(esc.(fargs)...)) where {T<:Tuple{$(esc.(kwtypes)...)}})
    return outexpr
end


end # module
