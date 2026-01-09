# Copyright (c) 2025 Felix Kahle.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

@assert isdefined(Bollard, :libbollard_ffi) "Bollard module not loaded. Please `using Bollard` before including this file."

"""
    AbstractBollardSolution

Abstract supertype for all Bollard solution types.
"""
abstract type AbstractBollardSolution end

"""
    Solution <: AbstractBollardSolution

A wrapper around a computed Bollard solution.
This object owns the underlying Rust memory and ensures it is freed when the Julia object is finalized.

# Fields
- `ptr::Ptr{Cvoid}`: Pointer to the underlying Rust `BollardFfiSolution` instance.
- `num_vessels::Int`: Total number of vessels in the solution.
"""
mutable struct Solution <: AbstractBollardSolution
    ptr::Ptr{Cvoid}
    num_vessels::Int

    """
        Solution(ptr::Ptr{Cvoid})

    Wrap a raw pointer to a Rust `BollardFfiSolution`.
    This constructor assumes ownership of the pointer.

    # Arguments
    - `ptr`: A valid pointer to a heap-allocated Rust solution.

    # Throws
    - `ErrorException`: If `ptr` is `C_NULL`.
    """
    function Solution(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap a null solution pointer")

        # Cache the number of vessels immediately to allow fast bounds checking in Julia
        n = ccall((:bollard_solution_num_vessels, libbollard_ffi), Csize_t, (Ptr{Cvoid},), ptr)

        instance = new(ptr, Int(n))

        finalizer(instance) do obj
            ptr_to_free = obj.ptr
            obj.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_solution_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return instance
    end
end

# -------------------------------------------------------------------------
# Safe Views (Zero-Copy)
# -------------------------------------------------------------------------

"""
    SolutionView{T} <: AbstractVector{T}

A generic safe, zero-copy view into memory owned by a `Solution`.
Used for scalar data (like timestamps) where no value conversion is needed.
"""
struct SolutionView{T} <: AbstractVector{T}
    parent::Solution
    data::Vector{T}
end

Base.size(v::SolutionView) = size(v.data)
Base.getindex(v::SolutionView, i::Int) = getindex(v.data, i)
Base.IndexStyle(::Type{<:SolutionView}) = IndexLinear()
Base.convert(::Type{Vector{T}}, v::SolutionView{T}) where T = copy(v)

"""
    BerthView{T} <: AbstractVector{Int}

A specialized zero-copy view for berth indices.
**Key Feature:** It automatically converts the raw 0-based indices from Rust 
into 1-based indices for Julia. The user never sees a "0" berth.
"""
struct BerthView{T<:Integer} <: AbstractVector{Int}
    parent::Solution
    data::Vector{T}
end

Base.size(v::BerthView) = size(v.data)
Base.getindex(v::BerthView, i::Int) = Int(v.data[i]) + 1
Base.IndexStyle(::Type{<:BerthView}) = IndexLinear()
Base.convert(::Type{Vector{Int}}, v::BerthView) = copy(v)

# =========================================================================
# Solution Properties (Getters)
# =========================================================================

"""
    Base.propertynames(::Solution)

Return the list of properties (methods) available on a `Solution` instance.
"""
function Base.propertynames(::Solution)
    return (:objective, :berth, :start_time,
        :berths, :start_times, :num_vessels)
end

"""
    Base.getproperty(s::Solution, sym::Symbol)

Dispatch for `Solution` query methods. Returns a function closure that wraps
the corresponding Rust FFI call.
"""
function Base.getproperty(s::Solution, sym::Symbol)
    ptr = getfield(s, :ptr)
    num_vessels = getfield(s, :num_vessels)

    # --- Get Objective Value ---
    if sym === :objective
        """
            objective() -> Int64

        Get the total objective value (cost) of the solution.
        """
        return () -> begin
            ptr == C_NULL && error("accessing method on freed Solution")
            ccall((:bollard_solution_objective, libbollard_ffi), Int64, (Ptr{Cvoid},), ptr)
        end

        # --- Get Vessel Berth Assignment ---
    elseif sym === :berth
        """
            berth(vessel_idx::Integer) -> Int

        Get the berth index assigned to a specific vessel.
        Returns a 1-based index (compatible with Julia arrays).
        """
        return (vessel_idx) -> begin
            ptr == C_NULL && error("accessing method on freed Solution")
            @boundscheck 1 <= vessel_idx <= num_vessels || throw(BoundsError(s, vessel_idx))

            # Call Rust (returns 0-based index)
            val = ccall((:bollard_solution_berth, libbollard_ffi), Csize_t,
                (Ptr{Cvoid}, Csize_t), ptr, vessel_idx - 1)

            # Convert to 1-based index
            return Int(val) + 1
        end

        # --- Get Vessel Start Time ---
    elseif sym === :start_time
        """
            start_time(vessel_idx::Integer) -> Int64

        Get the scheduled start time for a specific vessel.
        """
        return (vessel_idx) -> begin
            ptr == C_NULL && error("accessing method on freed Solution")
            @boundscheck 1 <= vessel_idx <= num_vessels || throw(BoundsError(s, vessel_idx))

            ccall((:bollard_solution_start_time, libbollard_ffi), Int64,
                (Ptr{Cvoid}, Csize_t), ptr, vessel_idx - 1)
        end

        # --- Safe Zero-Copy Views ---

    elseif sym === :start_times
        """
            start_times() -> SolutionView{Int64}

        Return a safe zero-copy view of the start times array.
        """
        return () -> begin
            ptr == C_NULL && error("accessing method on freed Solution")

            raw_ptr = ccall((:bollard_solution_start_times, libbollard_ffi), Ptr{Int64}, (Ptr{Cvoid},), ptr)
            raw = unsafe_wrap(Array, raw_ptr, num_vessels; own=false)

            return SolutionView(s, raw)
        end

    elseif sym === :berths
        """
            berths() -> BerthView{UInt}

        Return a safe zero-copy view of the berths array.
        **Note:** The view automatically converts 0-based internal indices to 1-based Julia indices.
        """
        return () -> begin
            ptr == C_NULL && error("accessing method on freed Solution")

            raw_ptr = ccall((:bollard_solution_berths, libbollard_ffi), Ptr{Csize_t}, (Ptr{Cvoid},), ptr)
            raw = unsafe_wrap(Array, raw_ptr, num_vessels; own=false)

            return BerthView(s, raw)
        end
    else
        return getfield(s, sym)
    end
end

# =========================================================================
# Base Utilities
# =========================================================================

"""
    Base.length(s::AbstractBollardSolution) -> Int

Return the number of vessels in the solution.
"""
Base.length(s::AbstractBollardSolution) = getfield(s, :num_vessels)

"""
    Base.show(io::IO, s::Solution)

Print a summary of the Solution.
"""
function Base.show(io::IO, s::Solution)
    status = getfield(s, :ptr) == C_NULL ? "Freed" : "Active"
    print(io, "Bollard.Solution(vessels=$(getfield(s, :num_vessels))) [$status]")
end