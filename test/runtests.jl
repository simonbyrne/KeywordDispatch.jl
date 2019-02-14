using Test
using KeywordDispatch
import KeywordDispatch: KeywordMethodError

@testset "new function" begin
    @kwdispatch f()

    @kwmethod f(;) = 10
    @kwmethod f(;a) = a
    @kwmethod f(;a,b) = a+b
    @kwmethod f(;a,b::String) = b

    @test f() == 10
    @test f(a=7) == 7
    @test f(a=7,b=4) == 11
    @test f(b=7,a=4) == 11
    @test f(a=7,b="xx") == "xx"
    @test f(b="xx",a=7) == "xx"

    @test_throws KeywordMethodError f(b=1)
    @test_throws KeywordMethodError f(c=1)
end


@testset "existing" begin
    g()= 1
    @kwdispatch g(_::Real)
    @kwdispatch g(_::Real,_::String)

    @kwmethod g(x::Real,y::String="y";) = 10
    @kwmethod g(x::Real,y::String="y";a) = a
    @kwmethod g(x::Real,y::String="y";a,b) = a+b
    @kwmethod g(x::Real,y::String="y";a,b::String) = y*b

    @test g() == 1
    @test g(1) == 10
    @test g(1,"yy") == 10
    @test g(1,a=7) == 7
    @test g(1,"yy",a=7) == 7
    @test g(1,a=7,b=4) == 11
    @test g(1,"yy",a=7,b=4) == 11
    @test g(1,a=7,b="bb") == "ybb"
    @test g(1,"yy",a=7,b="bb") == "yybb"

    @test_throws KeywordMethodError g(1,b=2)
    @test_throws KeywordMethodError g(1,"aa",b=2)
end

@testset "splatting" begin
    @kwdispatch h(x...)

    @kwmethod h(x::Real;) = 10
    @kwmethod h(x::Real;a) = a
    @kwmethod h(x::Real;a,b) = a+b
    @kwmethod h(x::Real...;a,b::String) = b

    @test h(1) == 10
    @test h(1,a=7) == 7
    @test h(1,a=7,b=4) == 11
    @test h(1,a=7,b="xx") == "xx"
    @test h(1,2,3,a=7,b="xx") == "xx"

    @test_throws KeywordMethodError h("aa")
    @test_throws KeywordMethodError h(1,2,3)
    @test_throws KeywordMethodError h(1,2,3,a=1,b=1)
end

@testset "all methods" begin
    @kwdispatch j

    @kwmethod j(;) = 10
    @kwmethod j(x;c) = x+c

    @test j() == 10
    @test j(3,c=4) == 7

    @test_throws KeywordMethodError j(c=1)
    @test_throws KeywordMethodError j(1)
    @test_throws KeywordMethodError j(1,a=1)
end

struct Foo
end

@testset "type" begin
    global Foo
    
    @kwdispatch Foo(_::String)

    @kwmethod Foo(_::String;) = 10
    @kwmethod Foo(_::String;a) = a
    @kwmethod Foo(_::String;a,b) = a+b
    @kwmethod Foo(_::String;a,b::String) = b

    @test Foo("aa") == 10
    @test Foo("aa",a=7) == 7
    @test Foo("aa",a=7,b=4) == 11
    @test Foo("aa",a=7,b="xx") == "xx"

    @test_throws KeywordMethodError Foo("aa",b=1)
end

@testset "call overloading" begin
    global Foo

    @kwdispatch (::Foo)

    @kwmethod (::Foo)(;) = 13
    @kwmethod (::Foo)(;a) = a+4
    @kwmethod (::Foo)(;a,b) = a+b+7
    @kwmethod (::Foo)(;a,b::String) = a

    @test Foo()() == 13
    @test Foo()(a=7) == 7+4
    @test Foo()(a=7,b=4) == 11+7
    @test Foo()(a=7,b="xx") == 7

    @test_throws KeywordMethodError Foo()(1)
    @test_throws KeywordMethodError Foo()(b=1)
end

struct Bar{T}
    w::T
end
@testset "call overloading with ref" begin
    global Bar
    
    @kwdispatch (::Bar{Float64})

    @kwmethod (t::Bar{Float64})(;) = t.w+13
    @kwmethod (t::Bar{Float64})(;a) = t.w+a+4
    @kwmethod (t::Bar{Float64})(;a,b) = t.w+a+b+7

    @test Bar(5.0)() == 5.0+13
    @test Bar(5.0)(a=7) == 5.0+7+4
    @test Bar(5.0)(a=7,b=4) == 5.0+7+4+7

    @test_throws KeywordMethodError Bar(5.0)(1)
    @test_throws KeywordMethodError Bar(5.0)(b=1)
end

@testset "curly" begin
    global Bar

    @kwdispatch Bar{String}()

    @kwmethod Bar{String}(;) = Bar("")
    @kwmethod Bar{String}(;a) = Bar("a$a")
    @kwmethod Bar{String}(;a,b) = Bar("a$a b$b")

    @test Bar{String}() == Bar("")
    @test Bar{String}(a=7) == Bar("a7")
    @test Bar{String}(a=7,b=4) == Bar("a7 b4")

    @test_throws KeywordMethodError Bar{String}(b=1)
end


@testset "where clauses" begin
    global Bar

    @kwdispatch Bar{T}() where {T<:Integer}

    @kwmethod Bar{T}(;) where {T<:Integer} = Bar(T(13))
    @kwmethod Bar{T}(;a) where {T<:Integer} = Bar(T(a+4))
    @kwmethod Bar{T}(;a,b) where {T<:Integer} = Bar(T(a+b+7))

    @test Bar{Int}() == Bar(Int(13))
    @test Bar{UInt}(a=7) == Bar(UInt(7+4))
    @test Bar{Int16}(a=7,b=4) == Bar(Int16(7+4+7))

    @test_throws KeywordMethodError Bar{Int}(b=1)
end


@testset "different module" begin    
    @kwdispatch Base.RoundingMode

    @kwmethod Base.RoundingMode(;) = 10
    @kwmethod Base.RoundingMode(;a) = a
    @kwmethod Base.RoundingMode(;a,b) = a+b
    @kwmethod Base.RoundingMode(;a,b::String) = b

    @test Base.RoundingMode() == 10
    @test Base.RoundingMode(a=7) == 7
    @test Base.RoundingMode(a=7,b=4) == 11
    @test Base.RoundingMode(a=7,b="xx") == "xx"

    @test_throws KeywordMethodError Base.RoundingMode(b=1)
    @test_throws MethodError Base.RoundDown()
end

@testset "kwdispatch extra argument" begin
    @kwdispatch h(x) begin
        (a) -> x+a
        (b) -> x-b
    end

    @test h(1, a=2) == 3
    @test h(1, b=2) == -1

    @test_throws KeywordMethodError h(1)
    @test_throws KeywordMethodError h(1, c=2)

    @test_throws MethodError h()
    @test_throws MethodError h(;a=1)

    @kwmethod h(x; c) = c

    @test h(1, c=2) == 2
end

struct Baz{T}
    w::T
end

@testset "kwdispatch subtype extra arg" begin
    global Baz
    
    @kwdispatch (::Type{B})() where {B<:Baz} begin
        () -> B(0)
        (w) -> B(w)
        (z) -> B(sqrt(z))
    end

    @test Baz() == Baz{Int}(0)
    @test Baz{Float64}() == Baz{Float64}(0.0)

    @test Baz(w=3) == Baz{Int}(3)
    @test Baz(w=3.0) == Baz{Float64}(3.0)
    @test Baz{Float64}(w=3) == Baz{Float64}(3.0)

    @test Baz(z=4) == Baz{Float64}(2.0)
    @test Baz{Int}(z=4) == Baz{Int}(2)
    @test Baz{Float64}(z=4) == Baz{Float64}(2.0)
end    


@testset "kw rename" begin
    @kwdispatch f(;alpha => α, beta => β)

    @kwmethod f(;α) = 1
    @kwmethod f(;β) = 2
    @kwmethod f(;α,β) = 3

    @test f(α=0) == 1
    @test f(alpha=0) == 1

    @test f(β=0) == 2
    @test f(beta=0) == 2

    @test f(alpha=0,beta=0) == 3
end
