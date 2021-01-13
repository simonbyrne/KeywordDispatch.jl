# KeywordDispatch.jl

[![Build Status](https://github.com/simonbyrne/KeywordDispatch.jl/workflows/CI/badge.svg?branch=master)](https://github.com/simonbyrne/KeywordDispatch.jl/actions?query=workflow%3ACI)
[![Code Coverage](https://codecov.io/gh/simonbyrne/KeywordDispatch.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/simonbyrne/KeywordDispatch.jl)

Dispatch on keyword arguments. It exports 2 macros:
 - `@kwdispatch` designates a function signature to use for keyword dispatch
 - `@kwmethod` defines the method for the keyword argument

## Example

```julia
using KeywordDispatch

@kwdispatch f()

@kwmethod f(;a) = "a is $a"
@kwmethod f(;a::Integer) = "a is $a, and is an Integer"
@kwmethod f(;b) = "b is $b"
@kwmethod f(;a,b) = "a is $a, b is $b"
@kwmethod f(;) = "look mum, no args!"
```

at the REPL:
```
julia> f()
"look mum, no args!"

julia> f(a=1.0)
"a is 1.0"

julia> f(a=1)
"a is 1, and is an Integer"

julia> f(b=3,a=1)
"a is 1, b is 3"
```
