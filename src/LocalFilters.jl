module LocalFilters

import Base: CartesianRange, size, length, ndims, first, last, tail,
    getindex, setindex!, convert

export localfilter!,
    localmean, localmean!,
    erode, erode!, slow_erode!,
    dilate, dilate!, slow_dilate!,
    closing, closing!,
    opening, opening!,
    top_hat,
    bottom_hat,
    localextrema, localextrema!

"""
All neighborhoods are instances of a type derived from `Neighborhood`.
"""
abstract Neighborhood{N}

# Default implementation of common methods.
ndims{N}(::Neighborhood{N}) = N
length(B::Neighborhood) = prod(size(B))
size{N}(B::Neighborhood{N}) = ntuple(i -> size(B, i), N)

"""

    anchor(B)    -> I::CartesianIndex{N}

yields the anchor of the structuring element `B` that is the Cartesian index of
the central position in the structuring element within its bounding-box.  `N`
is the number of dimensions.  Argument can also be `K` or `size(K)` to get the
default anchor for kernel `K` (an array).

"""
anchor{N}(dims::NTuple{N,Integer}) =
    CartesianIndex(ntuple(d -> (Int(dims[d]) >> 1) + 1, N))
anchor(B::Neighborhood) = (I = first(B); one(I) - I)
anchor(A::AbstractArray) = anchor(size(A))

"""
The `limits` method yields the corners (as a tuple of 2 `CartesianIndex`)
of `B` (an array, a `CartesianRange` or a `Neighborhood`) and the
infium and supremum of a type `T`:

    limits(B) -> first(B), last(B)
    limits(T) -> typemin(T), typemax(T)

"""
limits(R::CartesianRange) = first(R), last(R)
limits{T}(::Type{T}) = typemin(T), typemax(T)
limits(A::AbstractArray) = limits(CartesianRange(size(A)))
limits(B::Neighborhood) = first(B), last(B)

CartesianRange{N}(B::Neighborhood{N}) =
    CartesianRange{CartesianIndex{N}}(first(B), last(B))

# Provide code and documentation for other operations.

@doc """
Basic operations of mathematical morphology are:

    erode(A, B) -> Amin
    dilate(A, B) -> Amax

which return the local minimum `Amin` and the local maximum `Amax` of argument
`A` for a neighborhood defined by `B`.  The returned result is similar to `A`
(same size and type).

The two operations can be combined in one call:

    localextrema(A, B) -> Amin, Amax

The in-place versions:

    erode!(Amin, A, B) -> Amin
    dilate!(Amax, A, B) -> Amax
    localextrema!(Amin, Amax, A, B) -> Amin, Amax

apply the operation to `a` with structuring element `b` and store the
result in the provided arrays `amin` and/or `amax`.


## See also:
localmean, opening, closing, top_hat, bottom_hat

""" erode

@doc @doc(erode) erode!
@doc @doc(erode) dilate
@doc @doc(erode) dilate!
@doc @doc(erode) localextrema
@doc @doc(erode) localextrema!

@doc """

    localmean(A, B)

yields the local mean of `A` for a neighborhood defined by `B`.  The result is
an array similar to `A`.

The in-place version is:

    localmean!(dst, A, B) -> dst

""" localmean

@doc @doc(localmean) localmean!

"""
A local filtering operation can be performed by calling:

    localfilter!(dst, A, B, initial, update, final) -> dst

where `dst` is the destination, `A` is the source, `B` defines the
neighborhood, `initial`, `update` and `final` are three functions whose
purposes are explained by the following pseudo-code to implement the local
operation:

    for i ∈ Sup(A)
        v = initial()
        for j ∈ Sup(A) and i - j ∈ Sup(B)
            v = update(v, A[j], B[i-j])
        end
        dst[i] = final(v)
    end

where `A` `Sup(A)` yields the support of `A` (that is the set of indices in
`A`) and likely `Sub(B)` for `B`.

For instance, to compute a local minimum (that is an erosion):

    localfilter!(dst, A, B, ()->typemax(T), (v,a,b)->min(v,a), (v)->v)

"""
function localfilter!{T,N}(dst, A::AbstractArray{T,N}, B, initial::Function,
                           update::Function, final::Function)
    # Notes: The signature of this method is intentionally as little
    #        specialized as possible to avoid confusing the dispatcher.  The
    #        prupose of this method is just to convert `B ` into a neighborhood
    #        suitable for `A`.
    localfilter!(dst, A, convert(Neighborhood{N}, B), initial, update, final)
end

# Include code for basic operations with specific structuring element
# types.
include("centeredboxes.jl")
include("cartesianboxes.jl")
include("kernels.jl")

# The following `slow_*` versions are to test the efficiency of Julia compiler.

slow_mean!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N}, B=3) =
    localfilter!(dst, A, B,
                 ()      -> (zero(T),0),
                 (v,a,b) -> (v[1] + a, v[2] + 1),
                 (v)     -> v[1]/v[2])

slow_erode!{T,N}(dst, A::AbstractArray{T,N}, B=3) =
    slow_erode!(dst, A::AbstractArray{T,N}, convert(Neighborhood{N}, B))

slow_dilate!{T,N}(dst, A::AbstractArray{T,N}, B=3) =
    slow_dilate!(dst, A::AbstractArray{T,N}, convert(Neighborhood{N}, B))

# A Window has all its coefficients virtually equal to 1.
typealias Window{N} Union{CenteredBox{N},CartesianBox{N}}

function slow_erode!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                          B::Window{N})
    localfilter!(dst, A, B,
                 ()      -> typemax(T),
                 (v,a,b) -> min(v,a),
                 (v)     -> v)
end

function slow_dilate!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                           B::Window{N})
    localfilter!(dst, A, B,
                 ()      -> typemin(T),
                 (v,a,b) -> max(v,a),
                 (v)     -> v)
end

function slow_erode!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                          B::Kernel{Bool,N})
    localfilter!(dst, A, B,
                 ()      -> typemax(T),
                 (v,a,b) -> b && a < v ? a : v,
                 (v)     -> v)
end

function slow_dilate!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                           B::Kernel{Bool,N})
    localfilter!(dst, A, B,
                 ()      -> typemin(T),
                 (v,a,b) -> b && a > v ? a : v,
                 (v)     -> v)
end

function slow_erode!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                          B::Kernel{T,N})
    localfilter!(dst, A, B,
                 ()      -> typemax(T),
                 (v,a,b) -> min(v, a - b),
                 (v)     -> v)
end

function slow_dilate!{T,N}(dst::AbstractArray{T,N}, A::AbstractArray{T,N},
                           B::Kernel{T,N})
    localfilter!(dst, A, B,
                 ()      -> typemin(T),
                 (v,a,b) -> max(v, a + b),
                 (v)     -> v)
end

slow_mean(a, b) = slow_mean!(similar(a), a, b)
slow_erode(a, b) = slow_erode!(similar(a), a, b)
slow_dilate(a, b) = slow_dilate!(similar(a), a, b)

#------------------------------------------------------------------------------

# To implement variants and out-of-place versions, we first define conversion
# rules to convert various types of arguments into a neighborhood suitable with
# the source (e.g., of given rank `N`).

convert{N}(::Type{Neighborhood{N}}, dim::Integer) =
    CenteredBox(ntuple(i->dim, N))

convert{N,T<:Integer}(::Type{Neighborhood{N}}, dims::Vector{T}) =
    (@assert length(dims) == N; CenteredBox(dims...))

convert{T,N}(::Type{Neighborhood{N}}, A::AbstractArray{T,N}) = Kernel(A)
convert{N}(::Type{Neighborhood{N}}, R::CartesianRange{CartesianIndex{N}}) =
    CartesianBox(R)

function  convert{N,T<:Integer}(::Type{Neighborhood{N}},
                                inds::NTuple{N,AbstractUnitRange{T}})
    CartesianBox(inds)
end

for func in (:localmean, :erode, :dilate)
    local inplace = Symbol(func,"!")
    @eval begin

        function $inplace{T,N}(dst::AbstractArray{T,N},
                               src::AbstractArray{T,N}, B=3)
            $inplace(dst, src, convert(Neighborhood{N}, B))
        end

        $func(A::AbstractArray, B=3) = $inplace(similar(A), A, B)

    end
end

function localextrema!{T,N}(Amin::AbstractArray{T,N},
                            Amax::AbstractArray{T,N},
                            A::AbstractArray{T,N}, B=3)
    localextrema!(Amin, Amax, A, convert(Neighborhood{N}, B))
end

localextrema(A::AbstractArray, B=3) =
    localextrema!(similar(A), similar(A), A, B)

#------------------------------------------------------------------------------
# Higher level operators.

"""

    closing(arr, r)
    opening(arr, r)

perform a closing or an opening of array `arr` by the structuring element
`r`.  If not specified, `r` is a box of size 3 along all the dimensions of
`arr`.  A closing is a dilation followed by an erosion, whereas an opening
is an erosion followed by a dilation.

The in-place versions are:

    closing!(dst, wrk, src, r)
    opening!(dst, wrk, src, r)

which perform the operation on the source `src` and store the result in
destination `dst` using `wrk` as a workspace array.  These 3 arguments must
be similar arrays, `dst` and `src` may be identical, but `wrk` must not be
the same array as `src` or `dst`.  The destination `dst` is returned.

See `erode` or `dilate` for the meaning of the arguments.

"""
function closing!{T,N}(dst::AbstractArray{T,N},
                       wrk::AbstractArray{T,N},
                       src::AbstractArray{T,N}, B::Neighborhood{N})
    erode!(dst, dilate!(wrk, src, B), B)
end

function opening!{T,N}(dst::AbstractArray{T,N},
                       wrk::AbstractArray{T,N},
                       src::AbstractArray{T,N}, B::Neighborhood{N})
    dilate!(dst, erode!(wrk, src, B), B)
end

for func in (:opening, :closing)
    local inplace = Symbol(func,"!")
    @eval begin

        function $inplace{T,N}(dst::AbstractArray{T,N},
                               wrk::AbstractArray{T,N},
                               src::AbstractArray{T,N}, B=3)
            $inplace(dst, wrk, src, convert(Neighborhood{N}, B))
        end

        $func(A::AbstractArray, B=3) =
            $inplace(similar(A), similar(A), A, B)

    end
end

@doc @doc(closing!) closing
@doc @doc(closing!) opening
@doc @doc(closing!) opening!

# Out-of-place top hat filter requires 2 allocations without a
# pre-filtering, 3 allocations with a pre-filtering.

"""

    top_hat(a, r)
    top_hat(a, r, s)
    bottom_hat(a, r)
    bottom_hat(a, r, s)

Perform a summit/valley detection by applying a top-hat filter to array
`a`.  Argument `r` defines the structuring element for the feature
detection.  Optional argument `s` specifies the structuring element used to
apply a smoothing to `a` prior to the top-hat filter.  If `r` and `s` are
specified as the radii of the structuring elements, then `s` should be
smaller than `r`.  For instance:

     top_hat(bitmap, 3, 1)

may be used to detect text or lines in a bimap image.

The in-place versions:

     top_hat!(dst, wrk, src, r)
     bottom_hat!(dst, wrk, src, r)

apply the top-hat filter on the source `src` and store the result in the
destination `dst` using `wrk` as a workspace array.  These 3 arguments must
be similar but different arrays.  The destination `dst` is returned.

See also: dilate, closing, morph_enhance.

"""
top_hat(a, r=3) = top_hat!(similar(a), similar(a), a, r)

bottom_hat(a, r=3) = bottom_hat!(similar(a), similar(a), a, r)

function top_hat(a, r, s)
    wrk = similar(a)
    top_hat!(similar(a), wrk, closing!(similar(a), wrk, a, s), r)
end

function bottom_hat(a, r, s)
    wrk = similar(a)
    bottom_hat!(similar(a), wrk, opening!(similar(a), wrk, a, s), r)
end

function top_hat!{T,N}(dst::AbstractArray{T,N},
                       wrk::AbstractArray{T,N},
                       src::AbstractArray{T,N}, r=3)
    opening!(dst, wrk, src, r)
    @inbounds for i in eachindex(dst, src)
        dst[i] = src[i] - dst[i]
    end
    return dst
end

function bottom_hat!{T,N}(dst::AbstractArray{T,N},
                          wrk::AbstractArray{T,N},
                          src::AbstractArray{T,N}, r=3)
    closing!(dst, wrk, src, r)
    @inbounds for i in eachindex(dst, src)
        dst[i] -= src[i]
    end
    return dst
end

@doc @doc(top_hat)    top_hat!
@doc @doc(top_hat) bottom_hat
@doc @doc(top_hat) bottom_hat!

end
