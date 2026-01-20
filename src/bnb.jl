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
    BnbDecisionBuilderType

Determines the branching strategy used by the Branch-and-Bound solver.

# Values
- `ChronologicalExhaustive (0)`: Branch based on time (exhaustive search).
- `FcfsHeuristic (1)`: First-Come, First-Served heuristic ordering.
- `RegretHeuristic (2)`: Regret-based heuristic.
- `SlackHeuristic (3)`: Slack time-based heuristic.
- `WsptHeuristic (4)`: Weighted Shortest Processing Time.
- `SptHeuristic (5)`: Shortest Processing Time.
- `LptHeuristic (6)`: Longest Processing Time.
- `EarliestDeadlineFirst (7)`: EDF ordering.
"""
@enum BnbDecisionBuilderType::Int32 begin
    ChronologicalExhaustive = 0
    FcfsHeuristic = 1
    RegretHeuristic = 2
    SlackHeuristic = 3
    WsptHeuristic = 4
    SptHeuristic = 5
    LptHeuristic = 6
    EarliestDeadlineFirst = 7
end

"""
    BnbObjectiveEvaluatorType

Determines how the objective function is evaluated (lower bound calculation) during the search.

# Values
- `EvaluatorHybrid (0)`: Combination of strategies.
- `EvaluatorWorkload (1)`: Based on remaining workload.
- `EvaluatorWeightedFlowTime (2)`: Based on flow time.
"""
@enum BnbObjectiveEvaluatorType::Int32 begin
    EvaluatorHybrid = 0
    EvaluatorWorkload = 1
    EvaluatorWeightedFlowTime = 2
end

"""
    BnbTerminationReason

Specific termination reasons for the Branch-and-Bound solver.

# Values
- `BnbOptimalityProven (0)`: The search completed and the optimal solution was found.
- `BnbInfeasibilityProven (1)`: The problem has no solution.
- `BnbAborted (2)`: The search was stopped (e.g., time limit).
"""
@enum BnbTerminationReason::Int32 begin
    BnbOptimalityProven = 0
    BnbInfeasibilityProven = 1
    BnbAborted = 2
end

# =========================================================================
# Fixed Assignment Struct
# =========================================================================

"""
    FfiBnbFixedAssignment

A C-compatible struct representing a fixed decision (vessel assigned to a berth at a specific time).
Used to pass constraints to the Rust backend.

# Fields
- `start_time::Int64`: The timestamp to start processing.
- `berth_index::Csize_t`: Zero-based berth index (internal use).
- `vessel_index::Csize_t`: Zero-based vessel index (internal use).
"""
struct FfiBnbFixedAssignment
    start_time::Int64
    berth_index::Csize_t
    vessel_index::Csize_t
end

"""
    BnbFixedAssignment

A high-level Julia helper for defining fixed assignments using 1-based indexing.

# Fields
- `vessel_idx::Int`: The vessel to fix (1-based index).
- `berth_idx::Int`: The berth to assign it to (1-based index).
- `start_time::Int64`: The start time of the assignment.
"""
struct BnbFixedAssignment
    vessel_idx::Int
    berth_idx::Int
    start_time::Int64
end

"""
    Base.convert(::Type{FfiBnbFixedAssignment}, x::BnbFixedAssignment)

Convert a high-level `BnbFixedAssignment` (1-based) to a low-level `FfiBnbFixedAssignment` (0-based).
"""
function Base.convert(::Type{FfiBnbFixedAssignment}, x::BnbFixedAssignment)
    return FfiBnbFixedAssignment(x.start_time, Csize_t(x.berth_idx - 1), Csize_t(x.vessel_idx - 1))
end

# =========================================================================
# Termination Object (BnB Specific)
# =========================================================================

"""
    BnbTermination

Details about why the BnB solver terminated.

# Fields
- `reason::BnbTerminationReason`: The enum code for termination.
- `message::String`: A descriptive message regarding the termination.
"""
mutable struct BnbTermination
    ptr::Ptr{Cvoid}

    """
        BnbTermination(ptr::Ptr{Cvoid})

    Wrap a raw pointer to a Rust `BnbSolverFfiTermination` struct.
    Assumes ownership of the pointer.
    """
    function BnbTermination(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null BnbTermination pointer")
        obj = new(ptr)

        # Race-safe finalizer: capture ptr in closure scope
        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_termination_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::BnbTermination) = (:reason, :message)

function Base.getproperty(t::BnbTermination, s::Symbol)
    ptr = getfield(t, :ptr)
    ptr == C_NULL && error("accessing freed BnbTermination object")

    if s === :reason
        val = ccall((:bollard_bnb_termination_reason, libbollard_ffi), Int32, (Ptr{Cvoid},), ptr)
        return BnbTerminationReason(val)
    elseif s === :message
        str_ptr = ccall((:bollard_bnb_termination_message, libbollard_ffi), Cstring, (Ptr{Cvoid},), ptr)
        return unsafe_string(str_ptr)
    else
        return getfield(t, s)
    end
end

function Base.show(io::IO, t::BnbTermination)
    if getfield(t, :ptr) == C_NULL
        print(io, "BnbTermination(Freed)")
    else
        print(io, "BnbTermination($(t.reason): \"$(t.message)\")")
    end
end

# =========================================================================
# Statistics Object
# =========================================================================

"""
    BnbStatistics

Detailed statistics about the Branch-and-Bound search process.

# Fields
- `nodes_explored::UInt64`: Total nodes visited.
- `backtracks::UInt64`: Total leaf nodes reached or dead-ends hit.
- `decisions_generated::UInt64`: Total distinct branching choices.
- `max_depth::UInt64`: Deepest level reached.
- `prunings_infeasible::UInt64`: Moves pruned due to feasibility.
- `prunings_bound::UInt64`: Moves pruned due to cost bounds.
- `solutions_found::UInt64`: Total valid solutions found.
- `steps::UInt64`: Total solver iterations.
- `time_total_ms::UInt64`: Total time spent in milliseconds.
"""
mutable struct BnbStatistics
    ptr::Ptr{Cvoid}

    function BnbStatistics(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null BnbStatistics pointer")
        obj = new(ptr)

        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_status_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::BnbStatistics) = (
    :nodes_explored, :backtracks, :decisions_generated, :max_depth,
    :prunings_infeasible, :prunings_bound, :solutions_found,
    :steps, :time_total_ms
)

function Base.getproperty(s::BnbStatistics, sym::Symbol)
    ptr = getfield(s, :ptr)
    ptr == C_NULL && error("accessing freed BnbStatistics object")

    if sym === :nodes_explored
        return ccall((:bollard_bnb_status_nodes_explored, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :backtracks
        return ccall((:bollard_bnb_status_backtracks, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :decisions_generated
        return ccall((:bollard_bnb_status_decisions_generated, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :max_depth
        return ccall((:bollard_bnb_status_max_depth, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :prunings_infeasible
        return ccall((:bollard_bnb_status_prunings_infeasible, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :prunings_bound
        return ccall((:bollard_bnb_status_prunings_bound, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :solutions_found
        return ccall((:bollard_bnb_status_solutions_found, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :steps
        return ccall((:bollard_bnb_status_steps, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :time_total_ms
        return ccall((:bollard_bnb_status_time_total_ms, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    else
        return getfield(s, sym)
    end
end

function Base.show(io::IO, s::BnbStatistics)
    @assert getfield(s, :ptr) != C_NULL "accessing freed BnbStatistics object"

    print(io, "BnbStatistics(nodes=$(s.nodes_explored), solutions=$(s.solutions_found), time=$(s.time_total_ms)ms)")
end

# =========================================================================
# Outcome Object
# =========================================================================

"""
    BnbOutcome

The container object returned by the BnB solver. It aggregates the termination reason,
the solution result, and the search statistics.

# Fields
- `termination::BnbTermination`: Why the solver stopped.
- `result::SolverResult`: The optimization result (contains the Solution if found).
- `statistics::BnbStatistics`: Performance metrics.
"""
mutable struct BnbOutcome
    ptr::Ptr{Cvoid}
    # We hold strong references to the children wrappers to ensure they are managed by Julia.
    termination::BnbTermination
    result::SolverResult
    statistics::BnbStatistics

    function BnbOutcome(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null BnbOutcome pointer")

        try
            raw_term = ccall((:bollard_bnb_outcome_termination, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)
            raw_res = ccall((:bollard_bnb_outcome_result, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)
            raw_stats = ccall((:bollard_bnb_outcome_statistics, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)


            term_obj = BnbTermination(raw_term)
            res_obj = SolverResult(raw_res)
            stats_obj = BnbStatistics(raw_stats)

            instance = new(ptr, term_obj, res_obj, stats_obj)

            finalizer(instance) do x
                ptr_to_free = x.ptr
                x.ptr = C_NULL
                if ptr_to_free != C_NULL
                    # This frees the Outcome struct itself, but NOT the inner pointers (term, result, stats).
                    # The inner pointers are freed by the finalizers of the fields `termination`, `result`, and `statistics`.
                    ccall((:bollard_bnb_outcome_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
                end
            end
            return instance
        catch
            ccall((:bollard_bnb_outcome_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr)
            rethrow(e)
        end
    end
end

Base.propertynames(::BnbOutcome) = (:termination, :result, :statistics)

function Base.getproperty(o::BnbOutcome, s::Symbol)
    ptr = getfield(o, :ptr)
    ptr == C_NULL && error("accessing freed BnbOutcome object")

    if s === :termination || s === :result || s === :statistics
        return getfield(o, s)
    else
        return getfield(o, s)
    end
end

function Base.show(io::IO, o::BnbOutcome)
    ptr = getfield(o, :ptr)
    @assert ptr != C_NULL "accessing freed BnbOutcome object"

    print(io, "BnbOutcome($(o.termination.reason))")
end

# =========================================================================
# BnbSolver Object
# =========================================================================

"""
    BnbSolver

The Branch-and-Bound solver instance.
"""
mutable struct BnbSolver
    ptr::Ptr{Cvoid}

    """
        BnbSolver()

    Create a new, empty Branch-and-Bound solver.
    """
    function BnbSolver()
        ptr = ccall((:bollard_bnb_solver_new, libbollard_ffi), Ptr{Cvoid}, ())
        ptr == C_NULL && error("failed to allocate BnbSolver")

        obj = new(ptr)
        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_solver_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end

    """
        BnbSolver(model::Model)

    Create a new BnbSolver initialized with memory suitable for the given Model.
    """
    function BnbSolver(model::Model)
        # Access model pointer safely
        model_ptr = getfield(model, :ptr)
        model_ptr == C_NULL && error("cannot create solver from invalidated model")

        ptr = ccall((:bollard_bnb_solver_from_model, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), model_ptr)
        ptr == C_NULL && error("failed to allocate BnbSolver from model")

        obj = new(ptr)
        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_solver_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

"""
    solve(solver::BnbSolver, model::Model; kwargs...) -> BnbOutcome

Solve the optimization problem defined by `model` using the provided `solver`.

# Keywords
- `builder::BnbDecisionBuilderType`: Branching strategy (default: `ChronologicalExhaustive`).
- `evaluator::BnbObjectiveEvaluatorType`: Lower-bound strategy (default: `EvaluatorHybrid`).
- `solution_limit::Int`: Stop after finding N solutions (0 = no limit).
- `time_limit_ms::Int`: Stop after N milliseconds (0 = no limit).
- `enable_log::Bool`: Print search logs to stdout (default: `false`).
- `initial_solution::Union{Solution, Nothing}`: An optional existing solution to warm-start the search.
- `fixed::Vector{BnbFixedAssignment}`: Force specific assignments (default: empty).
"""
function solve(
    solver::BnbSolver,
    model::Model;
    builder::BnbDecisionBuilderType=ChronologicalExhaustive,
    evaluator::BnbObjectiveEvaluatorType=EvaluatorHybrid,
    solution_limit::Integer=0,
    time_limit_ms::Integer=0,
    enable_log::Bool=false,
    initial_solution::Union{Solution,Nothing}=nothing,
    fixed::Vector{BnbFixedAssignment}=BnbFixedAssignment[]
)
    solver_ptr = getfield(solver, :ptr)
    model_ptr = getfield(model, :ptr)

    solver_ptr == C_NULL && error("cannot use freed BnbSolver")
    model_ptr == C_NULL && error("cannot solve invalidated Model")

    # Helper to convert Julia fixed assignments to FFI structs
    convert_fixed = (f_list) -> begin
        ffi_fixed = [convert(FfiBnbFixedAssignment, f) for f in f_list]
        return (ffi_fixed, length(ffi_fixed))
    end

    GC.@preserve solver model initial_solution begin

        # --- Case 1: Standard Solve (No Initial Solution) ---
        if initial_solution === nothing
            if isempty(fixed)
                # 1a. Basic Solve
                raw_outcome = ccall((:bollard_bnb_solver_solve, libbollard_ffi), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Cvoid}, Int32, Int32, Csize_t, Int64, Bool),
                    solver_ptr, model_ptr,
                    builder, evaluator,
                    solution_limit, time_limit_ms, enable_log
                )
                return BnbOutcome(raw_outcome)
            else
                # 1b. Solve with Fixed Assignments
                ffi_fixed, fixed_len = convert_fixed(fixed)
                raw_outcome = ccall((:bollard_bnb_solver_solve_with_fixed_assignments, libbollard_ffi), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Cvoid}, Int32, Int32, Csize_t, Int64, Bool, Ptr{FfiBnbFixedAssignment}, Csize_t),
                    solver_ptr, model_ptr,
                    builder, evaluator,
                    solution_limit, time_limit_ms, enable_log,
                    ffi_fixed, fixed_len
                )
                return BnbOutcome(raw_outcome)
            end

            # --- Case 2: Warm Start (With Initial Solution) ---
        else
            init_sol_ptr = getfield(initial_solution, :ptr)
            init_sol_ptr == C_NULL && error("cannot use freed Solution as initial_solution")

            if isempty(fixed)
                # 2a. Solve with Initial Solution only
                raw_outcome = ccall((:bollard_bnb_solver_solve_with_initial_solution, libbollard_ffi), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Cvoid}, Int32, Int32, Csize_t, Int64, Bool, Ptr{Cvoid}),
                    solver_ptr, model_ptr,
                    builder, evaluator,
                    solution_limit, time_limit_ms, enable_log,
                    init_sol_ptr
                )
                return BnbOutcome(raw_outcome)
            else
                # 2b. Solve with Initial Solution AND Fixed Assignments
                ffi_fixed, fixed_len = convert_fixed(fixed)
                raw_outcome = ccall((:bollard_bnb_solver_solve_with_initial_solution_and_fixed_assignments, libbollard_ffi), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Cvoid}, Int32, Int32, Csize_t, Int64, Bool, Ptr{Cvoid}, Ptr{FfiBnbFixedAssignment}, Csize_t),
                    solver_ptr, model_ptr,
                    builder, evaluator,
                    solution_limit, time_limit_ms, enable_log,
                    init_sol_ptr,
                    ffi_fixed, fixed_len
                )
                return BnbOutcome(raw_outcome)
            end
        end
    end
end

function Base.show(io::IO, s::BnbSolver)
    print(io, "BnbSolver")
end