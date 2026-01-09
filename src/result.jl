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

# =========================================================================
# Enums
# =========================================================================

"""
    SolverStatus

Categorical status of the optimization result returned by the solver.

# Values
- `StatusOptimal (0)`: The solution found is proven to be optimal.
- `StatusFeasible (1)`: A valid solution was found, but optimality was not proven (e.g., time limit).
- `StatusInfeasible (2)`: The problem has no valid solution.
- `StatusUnknown (3)`: The solver could not determine feasibility (e.g., aborted early).
"""
@enum SolverStatus::Int32 begin
    StatusOptimal = 0
    StatusFeasible = 1
    StatusInfeasible = 2
    StatusUnknown = 3
end

"""
    TerminationReason

The specific reason why the solver terminated execution.

# Values
- `ReasonOptimalityProven (0)`: The search completed exhaustively.
- `ReasonInfeasibilityProven (1)`: The search proved no solution exists.
- `ReasonConverged (2)`: The solver converged to a solution (metaheuristic context).
- `ReasonAborted (3)`: The solver stopped due to limits (time, iterations) or external signals.
"""
@enum TerminationReason::Int32 begin
    ReasonOptimalityProven = 0
    ReasonInfeasibilityProven = 1
    ReasonConverged = 2
    ReasonAborted = 3
end

# =========================================================================
# Termination Object
# =========================================================================

"""
    Termination

Details about why the solver terminated, including a specific reason code and a descriptive message.
This object owns its underlying Rust memory and must not be used after finalization.

# Fields
- `reason::TerminationReason`: The enum code for termination.
- `message::String`: A human-readable description (e.g., "Time limit exceeded").
"""
mutable struct Termination
    ptr::Ptr{Cvoid}

    """
        Termination(ptr::Ptr{Cvoid})

    Wrap a raw pointer to a Rust `BollardFfiTermination` struct.
    Assumes ownership of the pointer.
    """
    function Termination(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null Termination pointer")
        obj = new(ptr)

        # Race-safe finalizer
        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_ffi_termination_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::Termination) = (:reason, :message)

function Base.getproperty(t::Termination, s::Symbol)
    ptr = getfield(t, :ptr)
    ptr == C_NULL && error("accessing freed Termination object")

    if s === :reason
        val = ccall((:bollard_ffi_termination_reason, libbollard_ffi), Int32, (Ptr{Cvoid},), ptr)
        return TerminationReason(val)

    elseif s === :message
        str_ptr = ccall((:bollard_ffi_termination_message, libbollard_ffi), Cstring, (Ptr{Cvoid},), ptr)
        return unsafe_string(str_ptr)

    else
        return getfield(t, s)
    end
end

function Base.show(io::IO, t::Termination)
    print(io, "Termination($(t.reason): \"$(t.message)\")")
end

# =========================================================================
# SolverResult Object
# =========================================================================

"""
    SolverResult

The primary container returned by the solver. It indicates whether the solving process
was successful and holds the `Solution` object if one was found.

# Fields
- `status::SolverStatus`: The high-level outcome (Optimal, Feasible, etc.).
- `status_string::String`: A string representation of the status.
- `has_solution::Bool`: True if a valid solution exists.
- `solution::Union{Solution, Nothing}`: The solution object, or `nothing`.
"""
mutable struct SolverResult
    ptr::Ptr{Cvoid}
    # We store the Solution wrapper directly.
    # This ensures that the Solution's memory is managed by the Solution object's finalizer.
    # When this SolverResult is garbage collected, it will drop the reference to 'solution'.
    # If no other references exist, 'solution' will be GC'd, freeing the underlying solution data.
    solution::Union{Solution,Nothing}

    """
        SolverResult(ptr::Ptr{Cvoid})

    Wrap a raw pointer to a Rust `BollardFfiSolverResult` struct.
    Assumes ownership of the pointer.
    """
    function SolverResult(ptr::Ptr{Cvoid})
        # If the solver returns NULL (e.g. strict panic or OOM), we can't wrap it.
        ptr == C_NULL && error("cannot wrap null SolverResult pointer")

        # Check if the Rust result contains a solution pointer
        has_sol = ccall((:bollard_ffi_solver_result_has_solution, libbollard_ffi), Bool, (Ptr{Cvoid},), ptr)

        sol_obj = nothing
        if has_sol
            # Extract the pointer immediately via the FFI accessor
            raw_sol_ptr = ccall((:bollard_ffi_solver_result_solution, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)

            if raw_sol_ptr != C_NULL
                # Create the Julia wrapper. 
                # This object is now responsible for freeing the solution memory (via its own finalizer).
                sol_obj = Solution(raw_sol_ptr)
            end
        end

        obj = new(ptr, sol_obj)

        # Race-safe finalizer
        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            # We only free the Result container (status, string, etc.).
            # The inner 'solution' pointer is managed by the x.solution wrapper object.
            if ptr_to_free != C_NULL
                ccall((:bollard_ffi_solver_result_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::SolverResult) = (:status, :status_string, :has_solution, :solution)

function Base.getproperty(r::SolverResult, s::Symbol)
    ptr = getfield(r, :ptr)
    ptr == C_NULL && error("accessing freed SolverResult")

    if s === :status
        val = ccall((:bollard_ffi_solver_result_status, libbollard_ffi), Int32, (Ptr{Cvoid},), ptr)
        return SolverStatus(val)

    elseif s === :status_string
        str_ptr = ccall((:bollard_ffi_solver_result_status_string, libbollard_ffi), Cstring, (Ptr{Cvoid},), ptr)
        return unsafe_string(str_ptr)

    elseif s === :has_solution
        return getfield(r, :solution) !== nothing

    elseif s === :solution
        return getfield(r, :solution)

    else
        return getfield(r, s)
    end
end

function Base.show(io::IO, r::SolverResult)
    ptr = getfield(r, :ptr)
    @assert ptr != C_NULL "attempting to show freed SolverResult"

    sol = getfield(r, :solution)
    sol_text = sol !== nothing ? "Solution Found" : "No Solution"

    stat = r.status
    print(io, "SolverResult($stat, $sol_text)")
end