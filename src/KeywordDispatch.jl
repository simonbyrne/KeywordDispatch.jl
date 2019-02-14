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


function unwrap_where(expr)
    stack = Any[]
    while expr isa Expr && expr.head == :where
        push!(stack, expr.args[2])
        expr = expr.args[1]
    end
    expr, stack
end

function wrap_where(expr, stack)
    for w in Iterators.reverse(stack)
        expr = Expr(:where, expr, esc(w))
    end
    expr
end

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
    @kwdispatch sig [methods]

Designate a function signature `sig` that should dispatch on keyword arguments. A
function can also be provided, in which case _all_ calls to that function are will
dispatch to keyword methods.

It is possible to specify keyword aliases by specifying `from => to` pairs in the keyword position.

The optional `methods` argument allows a block of keyword methods specified as anonymous
functions. To define additional keyword methods, use the [`@kwmethod`](@ref) macro.

# Examples

```julia
@kwdispatch f(_)
@kwdispatch f(_::Real)

@kwdispacth f # equivalent to @kwdispatch f(_...)

@kwdispatch f(x) begin
    (a) -> x+a
    (b) -> x-b
end
# equivalent to
#  @kwdispatch f(x)
#  @kwmethod f(x;a) = x+a
#  @kwmethod f(x;b) = x-b

@kwdispatch f(; alpha=>α) # specifies alpha as an alias to α
```
"""
macro kwdispatch(fexpr,methods=nothing)
    fcall, wherestack = unwrap_where(fexpr)

    # handle: `fun`, `Mod.fun`, `(a::B)`
    if fcall isa Symbol || fcall isa Expr && (fcall.head in (:., :(::), :curly))
        fcall = :($fcall(_...))
    end

    @assert fcall isa Expr && fcall.head == :call

    rename_expr = :(kw)

    f = fcall.args[1]
    posargs = fcall.args[2:end]
    if length(posargs) >= 1 && posargs[1] isa Expr && posargs[1].head == :parameters
        parameters = popfirst!(posargs)
        for p in parameters.args
            if p isa Expr && p.head == :call && p.args[1] == :(=>)
                rename_expr = :(kw == $(QuoteNode(p.args[2])) ? $(QuoteNode(p.args[3])) : $rename_expr)
            else
                error("Only renames (from => to) are allowed in keyword position of `@kwdispatch`")
            end
        end
    end
    f = argmeth(f)

    if f isa Expr && f.head == :(::)
        ftype = esc(f.args[end])
    else
        ftype = :(typeof($(esc(f))))
    end

    posargs_method = argmeth.(posargs)
    ff = esc(argsym(f))

    quote
        $(wrap_where(:($(esc(f))($(esc.(posargs_method)...); kwargs...)), wherestack)) = begin
            N = map(kw -> $rename_expr, propertynames(kwargs.data))
            nt = NamedTuple{N}(Tuple(kwargs.data))
            KeywordDispatch.kwcall(ntsort(nt), $ff, $(esc.(argsym.(posargs_method))...))
        end
        $(generate_kwmethods(methods, f, posargs, wherestack))
    end
end

generate_kwmethods(other, f, posargs, wherestack) = other
function generate_kwmethods(expr::Expr, f, posargs, wherestack)
    if expr.head == :block
        for (i, ex) in enumerate(expr.args)
            expr.args[i] = generate_kwmethods(ex, f, posargs, wherestack)
        end
        return expr
    elseif expr.head in (:->, :function)
        if expr.args[1] isa Symbol
            return kwmethod_expr(f, posargs, [expr.args[1]], wherestack, esc(expr.args[2]))
        elseif expr.args[1] isa Expr && expr.args[1].head == :tuple
            return kwmethod_expr(f, posargs, expr.args[1].args, wherestack, esc(expr.args[2]))
        end
    end
    error("Invalid keyword definition $expr.")
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
    body = esc(fexpr.args[2])

    fcall, wherestack = unwrap_where(fexpr.args[1])

    @assert fcall isa Expr && fcall.head == :call

    f = fcall.args[1]

    length(fcall.args) >= 2 && fcall.args[2] isa Expr && fcall.args[2].head == :parameters ||
        error("@kwmethod requires functions specify a keyword block.\nUse @kwmethod `f(args...;)` to specify no keywords.")

    kwargs = fcall.args[2].args
    posargs = fcall.args[3:end]
    kwmethod_expr(f, posargs, kwargs, wherestack, body)
end


function kwmethod_expr(f, posargs, kwargs, wherestack, body)
    sort!(kwargs, by=argsym)

    kwsyms = argsym.(kwargs)
    kwtypes = argtype.(kwargs)

    if f isa Expr && f.head == :(::)
        F = esc(f)
    else
        F = :(::($(esc(f)) isa Type ? Type{$(esc(f))} : typeof($(esc(f)))))
    end

    quote
        $(wrap_where(:(KeywordDispatch.kwcall(($(esc.(kwsyms)...),)::NamedTuple{($(QuoteNode.(kwsyms)...),),T},
                                              $F,
                                              $(esc.(posargs)...)) where {T<:Tuple{$(esc.(kwtypes)...)}}), wherestack)) =
                                                  $body
    end
end

end # module
