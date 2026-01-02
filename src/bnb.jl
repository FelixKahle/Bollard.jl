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

# ------------------------------------------------------------------
# ENUMS
# ------------------------------------------------------------------

"""
    BnbSolverStatus

Enum representing the final status of a Branch-and-Bound search.

# Values
- `StatusOptimal (0)`: The solution found is proven to be optimal.
- `StatusFeasible (1)`: A solution was found, but optimality was not proven (e.g., time limit reached).
- `StatusInfeasible (2)`: The problem is proven to have no solution.
- `StatusUnknown (3)`: No solution was found, but infeasibility was not proven (e.g., stopped early).
"""
@enum BnbSolverStatus begin
    StatusOptimal = 0
    StatusFeasible = 1
    StatusInfeasible = 2
    StatusUnknown = 3
end

"""
    BnbTerminationReason

Enum representing the specific reason why the solver stopped.

# Values
- `ReasonOptimalityProven (0)`: The search exhausted the tree or pruned all remaining nodes based on bounds.
- `ReasonInfeasibilityProven (1)`: The search exhausted the tree and found no feasible assignments.
- `ReasonAborted (2)`: The search was stopped early (e.g., time limit, solution limit).
"""
@enum BnbTerminationReason begin
    ReasonOptimalityProven = 0
    ReasonInfeasibilityProven = 1
    ReasonAborted = 2
end

# ------------------------------------------------------------------
# FIXED ASSIGNMENTS
# ------------------------------------------------------------------

"""
    FixedAssignment

Represents a hard constraint forcing a specific vessel to be serviced at a specific berth 
starting at a specific time.

This struct allows advanced users to "warm start" the solver or enforce partial schedules.
It mirrors the binary layout of the Rust `BnbFfiFixedAssignment` struct to allow direct passing via FFI.

# Fields
- `start_time::Int64`: The timestamp when processing must begin.
- `berth_index::Csize_t`: The 0-based index of the berth (internal representation).
- `vessel_index::Csize_t`: The 0-based index of the vessel (internal representation).
"""
struct FixedAssignment
    start_time::Int64
    berth_index::Csize_t
    vessel_index::Csize_t

    """
        FixedAssignment(vessel_idx::Integer, berth_idx::Integer, start::Integer)

    Create a new fixed assignment constraint using Julia's standard 1-based indexing.

    # Arguments
    - `vessel_idx`: 1-based index of the vessel.
    - `berth_idx`: 1-based index of the berth.
    - `start`: The fixed start time.

    # Throws
    - `ArgumentError`: If indices are not positive.
    """
    function FixedAssignment(vessel_idx::Integer, berth_idx::Integer, start::Integer)
        vessel_idx > 0 || throw(ArgumentError("vessel_idx must be positive"))
        berth_idx > 0 || throw(ArgumentError("berth_idx must be positive"))

        # Convert 1-based Julia indices to 0-based C/Rust indices
        new(Int64(start), Csize_t(berth_idx - 1), Csize_t(vessel_idx - 1))
    end
end

# ------------------------------------------------------------------
# BNB SOLVER OUTCOME
# ------------------------------------------------------------------

"""
    BnbSolverOutcome

A wrapper around the result of a Branch-and-Bound optimization run. 
This object owns the underlying Rust memory and frees it upon finalization.

# Properties (General)
- `status`: Returns `BnbSolverStatus` (Optimal, Feasible, etc.).
- `termination_reason`: Returns `BnbTerminationReason`.
- `objective`: Returns `Int64` (the cost function value). Throws if no solution exists.
- `has_solution`: Returns `Bool` (true if status is Optimal or Feasible).
- `is_optimal`: Returns `Bool` (true if status is Optimal).
- `solution`: Returns `(Vector{Int}, Vector{Int64})` tuple representing `(berth_indices, start_times)`.

# Properties (Statistics)
- `nodes_explored`: Total nodes visited in the search tree.
- `backtracks`: Number of times the solver backtracked.
- `decisions_generated`: Total branching decisions created.
- `max_depth`: Maximum recursion depth reached.
- `prunings_infeasible`: Number of branches pruned due to constraint violations.
- `prunings_bound`: Number of branches pruned because they exceeded the best-known objective.
- `solutions_found`: Total number of feasible solutions found during search.
- `steps`: Total algorithmic steps.
- `time_ms`: Total execution time in milliseconds.
"""
mutable struct BnbSolverOutcome
    ptr::Ptr{Cvoid}

    """
        BnbSolverOutcome(ptr::Ptr{Cvoid})

    Internal constructor. Wraps a raw pointer from the Rust library and registers a finalizer.
    """
    function BnbSolverOutcome(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("solver returned a null outcome pointer")
        instance = new(ptr)

        finalizer(instance) do obj
            ptr_to_free = obj.ptr
            obj.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_outcome_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return instance
    end
end

"""
    Base.propertynames(::BnbSolverOutcome)

Returns the list of available properties for the outcome object.
"""
function Base.propertynames(::BnbSolverOutcome)
    return (:status, :termination_reason, :objective, :has_solution, :is_optimal, :solution,
        :nodes_explored, :backtracks, :decisions_generated, :max_depth,
        :prunings_infeasible, :prunings_bound, :solutions_found, :steps, :time_ms)
end

"""
    Base.getproperty(o::BnbSolverOutcome, s::Symbol)

Dispatch for outcome properties. Calls the appropriate FFI accessor functions.
"""
function Base.getproperty(o::BnbSolverOutcome, s::Symbol)
    # --- Status & Meta ---
    if s === :status
        raw = ccall((:bollard_bnb_outcome_status, libbollard_ffi), Cint, (Ptr{Cvoid},), o.ptr)
        return BnbSolverStatus(raw)
    elseif s === :termination_reason
        raw = ccall((:bollard_bnb_outcome_termination_reason_enum, libbollard_ffi), Cint, (Ptr{Cvoid},), o.ptr)
        return BnbTerminationReason(raw)
    elseif s === :objective
        return ccall((:bollard_bnb_outcome_objective, libbollard_ffi), Int64, (Ptr{Cvoid},), o.ptr)
    elseif s === :has_solution
        return ccall((:bollard_bnb_outcome_has_solution, libbollard_ffi), Bool, (Ptr{Cvoid},), o.ptr)
    elseif s === :is_optimal
        return o.status == StatusOptimal

        # --- Statistics ---
    elseif s === :nodes_explored
        return ccall((:bollard_bnb_outcome_nodes_explored, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :backtracks
        return ccall((:bollard_bnb_outcome_backtracks, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :decisions_generated
        return ccall((:bollard_bnb_outcome_decisions_generated, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :max_depth
        return ccall((:bollard_bnb_outcome_max_depth, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :prunings_infeasible
        return ccall((:bollard_bnb_outcome_prunings_infeasible, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :prunings_bound
        return ccall((:bollard_bnb_outcome_prunings_bound, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :solutions_found
        return ccall((:bollard_bnb_outcome_solutions_found, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :steps
        return ccall((:bollard_bnb_outcome_steps, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)
    elseif s === :time_ms
        return ccall((:bollard_bnb_outcome_time_total_ms, libbollard_ffi), UInt64, (Ptr{Cvoid},), o.ptr)

        # --- Result Data ---
    elseif s === :solution
        return _extract_solution(o)
    else
        return getfield(o, s)
    end
end

"""
    Base.show(io::IO, o::BnbSolverOutcome)

Prints a concise summary of the solver outcome.
"""
function Base.show(io::IO, o::BnbSolverOutcome)
    print(io, "Bollard.BnbSolverOutcome(status=$(o.status), obj=$(o.has_solution ? o.objective : "N/A"))")
end

"""
    _extract_solution(o::BnbSolverOutcome)

Internal helper. Allocates Julia arrays and copies the solution data from Rust.
Returns a tuple: `(berth_indices, start_times)`.
"""
function _extract_solution(o::BnbSolverOutcome)
    !o.has_solution && return (Int[], Int64[])

    n = ccall((:bollard_bnb_outcome_num_vessels, libbollard_ffi), Csize_t, (Ptr{Cvoid},), o.ptr)

    berths_out = Vector{Csize_t}(undef, n)
    starts_out = Vector{Int64}(undef, n)

    ccall((:bollard_bnb_outcome_copy_solution, libbollard_ffi), Cvoid,
        (Ptr{Cvoid}, Ptr{Csize_t}, Ptr{Int64}),
        o.ptr, berths_out, starts_out)

    # Convert C 0-based indices to Julia 1-based indices
    return (map(x -> Int(x) + 1, berths_out), starts_out)
end

# ------------------------------------------------------------------
# BNB SOLVER
# ------------------------------------------------------------------

"""
    BnbSolver

A wrapper around the Branch-and-Bound solving engine. 

The solver instance itself is stateless regarding the problem definition (the `Model` is passed 
to the `solve` function), but it is **stateful regarding memory allocation**. Reusing a `BnbSolver` 
instance across multiple `solve` calls allows the underlying engine to reuse memory buffers, 
significantly reducing overhead in iterative workflows.

# Constructors
- `BnbSolver()`: Creates a new solver with default allocation strategies.
- `BnbSolver(num_berths, num_vessels)`: Creates a solver with memory pre-allocated for a specific problem size.
"""
mutable struct BnbSolver
    ptr::Ptr{Cvoid}

    function BnbSolver(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("failed to allocate BnbSolver")
        instance = new(ptr)

        finalizer(instance) do obj
            ptr_to_free = obj.ptr
            obj.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_bnb_solver_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return instance
    end
end

"""
    BnbSolver()

Create a generic solver instance.
"""
function BnbSolver()
    ptr = ccall((:bollard_bnb_solver_new, libbollard_ffi), Ptr{Cvoid}, ())
    return BnbSolver(ptr)
end

"""
    BnbSolver(num_berths::Integer, num_vessels::Integer)

Create a solver instance with memory pre-allocated for a specific problem dimension.
"""
function BnbSolver(num_berths::Integer, num_vessels::Integer)
    ptr = ccall((:bollard_bnb_solver_preallocated, libbollard_ffi), Ptr{Cvoid},
        (Csize_t, Csize_t), num_berths, num_vessels)
    return BnbSolver(ptr)
end

"""
    EVALUATOR_MAP

A mapping from objective evaluator symbols to their corresponding FFI function name components.

Evaluators serve two roles:
1. **Local Evaluation**: Calculate the actual cost of assigning a vessel to a berth at a specific time.
2. **Lower Bound Estimation**: Project the "best-case scenario" cost for all remaining unassigned vessels. 
This bound is used to prune branches that cannot possibly beat the current best solution.

# Strategies

- **`:Hybrid`** (Recommended Default):
  A sophisticated strategy that blends availability-aware feasibility
  (maintenance and berth release times) with a capacity-sensitive workload estimate.
  It uses a internal heap to approximate an optimal sequence for the remaining backlog.
  It is highly sensitive to both berth congestion and maintenance closures,
  making it a stable and high-performance choice for most instances.

- **`:Workload`**:
  Derives a lower bound by simulating a parallel-machine model.
  It selects the fastest feasible processing option for each vessel and uses a WSPT-style
  (Weighted Shortest Processing Time) priority to order the simulation.
  While it relaxes maintenance windows to stay optimistic,
  it strictly respects berth release times to reflect real capacity limits.

- **`:WeightedFlowTime`**:
  Focuses heavily on the weighted completion objective.
  It examines unassigned vessels against the earliest usable windows of every berth,
  accounting for maintenance and deadlines. 
  It combines a feasibility-aware projection with a lightweight workload relaxation 
  to ensure the bound reacts sharply to maintenance-induced bottlenecks.
"""
const EVALUATOR_MAP = Dict(
    :Hybrid => "hybrid",
    :Workload => "workload",
    :WeightedFlowTime => "wtft"
)

"""
    HEURISTIC_MAP

A mapping from heuristic strategy symbols to their corresponding FFI function name components.

These heuristics determine the **branching order**: the strategy the solver uses to decide which
vessel-to-berth assignment to explore next.
Selecting the right heuristic can significantly impact solution speed and pruning efficiency.

# Strategies

- **`:Regret`** (Regret-guided best-first):
  Prioritizes vessels where choosing a suboptimal berth would incur the highest cost penalty 
  (the "regret" or gap between the best and second-best options).
  Vessels with only one feasible option are prioritized first. This is generally the most robust strategy for minimizing cost.

- **`:Slack`** (Slack-guided best-first):
  Prioritizes vessels with the tightest time windows (`deadline - min_finish_time`).
  This "fail-first" strategy reduces the risk of encountering infeasibility deep in the search tree, making it ideal for highly constrained problems.

- **`:Edf`** (Earliest-Deadline-First):
  Orders individual assignments by increasing urgency, measured as per-decision slack
  (`deadline - (start + processing)`). Similar to `:Slack`,
  but orders specific assignments rather than vessels, focusing the search on preventing immediate deadline violations.

- **`:Fcfs`** (First-Come-First-Served):
  Prioritizes assignments by earliest vessel arrival time.
  Ties are broken by objective cost.
  This mimics a fair FIFO queue and is computationally lightweight.

- **`:Wspt`** (Cost-guided / WSPT-style):
  Orders assignments by increasing immediate objective cost
  (weighted finish time). This "best-first" strategy aims to find high-quality incumbents early to maximize bound pruning.

- **`:Spt`** (Shortest-Processing-Time):
  Prioritizes assignments with the shortest duration (`p_ij`).
  Useful for maximizing throughput and finding low-impact moves early.

- **`:Lpt`** (Longest-Processing-Time):
  Prioritizes assignments with the longest duration.
  Useful for "big rocks first" scheduling, ensuring large tasks fit before filling gaps with smaller ones.

- **`:Chronological`**:
  Iterates through assignments in a deterministic row-major order (vessel index × berth index).
  Useful for baseline comparisons or when the input data is already pre-sorted by an external logic.
"""
const HEURISTIC_MAP = Dict(
    :Chronological => "chronological_exhaustive",
    :Fcfs => "fcfs_heuristic",
    :Regret => "regret_heuristic",
    :Slack => "slack_heuristic",
    :Wspt => "wspt_heuristic",
    :Spt => "spt_heuristic",
    :Lpt => "lpt_heuristic",
    :Edf => "edf_heuristic"
)

for (eval_sym, eval_str) in EVALUATOR_MAP
    for (heur_sym, heur_str) in HEURISTIC_MAP
        base_func_name = "bollard_bnb_solver_solve_with_$(eval_str)_evaluator_and_$(heur_str)_builder"

        func_sym = Symbol(base_func_name)
        @eval function _solve_dispatch(solver::BnbSolver, model::Model,
            ::Val{$(QuoteNode(eval_sym))}, ::Val{$(QuoteNode(heur_sym))},
            sol_limit, time_limit, log)
            ccall(($(QuoteNode(func_sym)), libbollard_ffi), Ptr{Cvoid},
                (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, Int64, Bool),
                solver.ptr, model.ptr, sol_limit, time_limit, log)
        end

        func_fixed_sym = Symbol(base_func_name * "_with_fixed")
        @eval function _solve_dispatch_fixed(solver::BnbSolver, model::Model,
            ::Val{$(QuoteNode(eval_sym))}, ::Val{$(QuoteNode(heur_sym))},
            sol_limit, time_limit, log, fixed::Vector{FixedAssignment})
            ccall(($(QuoteNode(func_fixed_sym)), libbollard_ffi), Ptr{Cvoid},
                (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{FixedAssignment}, Csize_t, Csize_t, Int64, Bool),
                solver.ptr, model.ptr, fixed, Csize_t(length(fixed)), sol_limit, time_limit, log)
        end
    end
end

"""
    solve(model::Model, solver::BnbSolver; kwargs...) -> BnbSolverOutcome

Execute the Branch-and-Bound algorithm on the given model using a specific solver instance.

# Arguments
- `model`: The optimized, compiled `Model` to solve.
- `solver`: The `BnbSolver` instance (memory arena).

# Keyword Arguments
- `evaluator::Symbol=:Hybrid`: The objective function strategy. 
  Options: `:Hybrid`, `:Workload`, `:WeightedFlowTime`.
- `heuristic::Symbol=:Regret`: The branching heuristic strategy. 
  Options: `:Chronological`, `:Fcfs`, `:Regret`, `:Slack`, `:Wspt`, `:Spt`, `:Lpt`.
- `solution_limit::Integer=0`: Stop after finding N feasible solutions (0 for no limit).
- `time_limit_ms::Integer=0`: Stop after N milliseconds (0 for no limit).
- `enable_log::Bool=false`: Print search progress to stdout (via Rust's logging system).
- `fixed_assignments::Vector{FixedAssignment}=[]`: Force specific vessels to specific berths/times (Warm start).

# Returns
A `BnbSolverOutcome` object containing results and statistics.
"""
function solve(model::Model, solver::BnbSolver;
    evaluator::Symbol=:Hybrid,
    heuristic::Symbol=:Regret,
    solution_limit::Integer=0,
    time_limit_ms::Integer=0,
    enable_log::Bool=false,
    fixed_assignments::Vector{FixedAssignment}=FixedAssignment[])

    if !haskey(EVALUATOR_MAP, evaluator)
        throw(ArgumentError("unknown evaluator: :$evaluator; supported: $(keys(EVALUATOR_MAP))"))
    end
    if !haskey(HEURISTIC_MAP, heuristic)
        throw(ArgumentError("unknown heuristic: :$heuristic; supported: $(keys(HEURISTIC_MAP))"))
    end

    @boundscheck for fa in fixed_assignments
        if fa.vessel_index >= model.num_vessels
            throw(BoundsError(model, Int(fa.vessel_index) + 1))
        end
        if fa.berth_index >= model.num_berths
            throw(BoundsError(model, Int(fa.berth_index) + 1))
        end
    end

    outcome_ptr = if isempty(fixed_assignments)
        _solve_dispatch(solver, model, Val(evaluator), Val(heuristic),
            solution_limit, time_limit_ms, enable_log)
    else
        _solve_dispatch_fixed(solver, model, Val(evaluator), Val(heuristic),
            solution_limit, time_limit_ms, enable_log, fixed_assignments)
    end

    return BnbSolverOutcome(outcome_ptr)
end