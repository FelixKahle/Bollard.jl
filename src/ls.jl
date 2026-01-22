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
    LSTerminationReason

The specific reason why the Local Search solver terminated.

# Values
- `LSLocalOptimum (0)`: No further improvements could be found in the current neighborhood.
- `LSMetaheuristic (1)`: The metaheuristic logic decided to stop (e.g., temperature cooled).
- `LSAborted (2)`: The solver stopped due to limits (time, solutions) or external signals.
"""
@enum LSTerminationReason::Int32 begin
    LSLocalOptimum = 0
    LSMetaheuristic = 1
    LSAborted = 2
end

# =========================================================================
# Termination Object
# =========================================================================

"""
    LSTermination

Details about why the Local Search solver terminated.
"""
mutable struct LSTermination
    ptr::Ptr{Cvoid}

    function LSTermination(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null LSTermination pointer")
        obj = new(ptr)

        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_ls_termination_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::LSTermination) = (:reason, :message)

function Base.getproperty(t::LSTermination, s::Symbol)
    ptr = getfield(t, :ptr)
    ptr == C_NULL && error("accessing freed LSTermination object")

    if s === :reason
        val = ccall((:bollard_ls_termination_reason, libbollard_ffi), Int32, (Ptr{Cvoid},), ptr)
        return LSTerminationReason(val)
    elseif s === :message
        str_ptr = ccall((:bollard_ls_termination_message, libbollard_ffi), Cstring, (Ptr{Cvoid},), ptr)
        return unsafe_string(str_ptr)
    else
        return getfield(t, s)
    end
end

function Base.show(io::IO, t::LSTermination)
    print(io, "LSTermination($(t.reason): \"$(t.message)\")")
end

# =========================================================================
# Statistics Object
# =========================================================================

"""
    LSStatistics

Performance metrics for the Local Search execution.

# Fields
- `iterations::UInt64`: Number of steps/moves performed.
- `total_solutions::UInt64`: Total valid solutions encountered.
- `accepted_solutions::UInt64`: Number of solutions accepted by the metaheuristic.
- `rejected_solutions::UInt64`: Number of solutions rejected.
- `time_total_ms::UInt64`: Total execution time in milliseconds.
"""
mutable struct LSStatistics
    ptr::Ptr{Cvoid}

    function LSStatistics(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null LSStatistics pointer")
        obj = new(ptr)

        finalizer(obj) do x
            ptr_to_free = x.ptr
            x.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_ls_status_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return obj
    end
end

Base.propertynames(::LSStatistics) = (
    :iterations, :total_solutions, :accepted_solutions,
    :rejected_solutions, :time_total_ms
)

function Base.getproperty(s::LSStatistics, sym::Symbol)
    ptr = getfield(s, :ptr)
    ptr == C_NULL && error("accessing freed LSStatistics object")

    if sym === :iterations
        return ccall((:bollard_ls_status_iterations, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :total_solutions
        return ccall((:bollard_ls_status_total_solutions, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :accepted_solutions
        return ccall((:bollard_ls_status_accepted_solutions, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :rejected_solutions
        return ccall((:bollard_ls_rejected_solutions, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    elseif sym === :time_total_ms
        return ccall((:bollard_ls_status_time_total_ms, libbollard_ffi), UInt64, (Ptr{Cvoid},), ptr)
    else
        return getfield(s, sym)
    end
end

function Base.show(io::IO, s::LSStatistics)
    print(io, "LSStatistics(iter=$(s.iterations), accepted=$(s.accepted_solutions), time=$(s.time_total_ms)ms)")
end

# =========================================================================
# Outcome Object
# =========================================================================

"""
    LSOutcome

The container object returned by the Local Search engine.

# Fields
- `termination::LSTermination`: Why the search stopped.
- `solution::Solution`: The best solution found (or the current solution at termination).
- `statistics::LSStatistics`: Performance metrics.
"""
mutable struct LSOutcome
    ptr::Ptr{Cvoid}
    termination::LSTermination
    solution::Solution
    statistics::LSStatistics

    function LSOutcome(ptr::Ptr{Cvoid})
        ptr == C_NULL && error("cannot wrap null LSOutcome pointer")

        try
            raw_term = ccall((:bollard_ls_outcome_termination, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)
            raw_sol = ccall((:bollard_ls_outcome_solution, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)
            raw_stats = ccall((:bollard_ls_outcome_statistics, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), ptr)

            term_obj = LSTermination(raw_term)
            sol_obj = Solution(raw_sol)
            stats_obj = LSStatistics(raw_stats)

            instance = new(ptr, term_obj, sol_obj, stats_obj)

            finalizer(instance) do x
                ptr_to_free = x.ptr
                x.ptr = C_NULL
                if ptr_to_free != C_NULL
                    ccall((:bollard_ls_outcome_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
                end
            end
            return instance
        catch e
            ccall((:bollard_ls_outcome_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr)
            rethrow(e)
        end
    end
end

Base.propertynames(::LSOutcome) = (:termination, :solution, :statistics)

function Base.getproperty(o::LSOutcome, s::Symbol)
    ptr = getfield(o, :ptr)
    ptr == C_NULL && error("accessing freed LSOutcome object")
    return getfield(o, s)
end

function Base.show(io::IO, o::LSOutcome)
    print(io, "LSOutcome($(o.termination.reason), Obj=$(o.solution.objective()))")
end

# =========================================================================
# Abstract Types
# =========================================================================

"""
    AbstractLSOperator

Abstract supertype for all Local Search operators (moves).
"""
abstract type AbstractLSOperator end

"""
    AbstractLSNeighborhood

Abstract supertype for all Neighborhood definition strategies.
"""
abstract type AbstractLSNeighborhood end

"""
    AbstractLSMetaheuristic

Abstract supertype for all Local Search metaheuristics (guidance logic).
"""
abstract type AbstractLSMetaheuristic end

# =========================================================================
# Operators
# =========================================================================

"""
    release!(op::AbstractLSOperator) -> Ptr{Cvoid}

Extracts the raw pointer from the operator and sets the internal pointer to `C_NULL`.
This effectively transfers ownership out of the Julia object, preventing the 
finalizer from freeing the memory.
"""
function release!(op::AbstractLSOperator)
    ptr = op.ptr
    if ptr == C_NULL
        error("attempted to release an already-consumed or freed operator.")
    end
    op.ptr = C_NULL
    return ptr
end

"""
    SwapOperator

An operator that swaps the berth assignments of two vessels.
"""
mutable struct SwapOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}

    function SwapOperator()
        ptr = ccall((:bollard_ls_swap_operator_new, libbollard_ffi), Ptr{Cvoid}, ())
        ptr == C_NULL && error("failed to allocate operator")
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function SwapOperator(ptr::Ptr{Cvoid})
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(::SwapOperator) = SwapOperator()

"""
    ShiftOperator

An operator that moves a vessel to a different berth.
"""
mutable struct ShiftOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}

    function ShiftOperator()
        ptr = ccall((:bollard_ls_shift_operator_new, libbollard_ffi), Ptr{Cvoid}, ())
        ptr == C_NULL && error("failed to allocate operator")
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function ShiftOperator(ptr::Ptr{Cvoid})
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(::ShiftOperator) = ShiftOperator()

"""
    TwoOptOperator

An operator that performs a 2-opt move on the sequence of vessels.
"""
mutable struct TwoOptOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}

    function TwoOptOperator()
        ptr = ccall((:bollard_ls_two_opt_operator_new, libbollard_ffi), Ptr{Cvoid}, ())
        ptr == C_NULL && error("failed to allocate operator")
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function TwoOptOperator(ptr::Ptr{Cvoid})
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(::TwoOptOperator) = TwoOptOperator()

"""
    ScrambleOperator

An operator that randomizes a portion of the solution.

# Constructors
- `ScrambleOperator()`: Use a random seed.
- `ScrambleOperator(seed::UInt64)`: Use a deterministic seed.
"""
mutable struct ScrambleOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}
    seed::Union{UInt64,Nothing}

    function ScrambleOperator()
        ptr = ccall((:bollard_ls_scramble_operator_new, libbollard_ffi), Ptr{Cvoid}, ())
        obj = new(ptr, nothing)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function ScrambleOperator(seed::UInt64)
        ptr = ccall((:bollard_ls_scramble_operator_new_with_seed, libbollard_ffi), Ptr{Cvoid}, (UInt64,), seed)
        obj = new(ptr, seed)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

function Base.copy(op::ScrambleOperator)
    if op.seed === nothing
        return ScrambleOperator()
    else
        return ScrambleOperator(op.seed)
    end
end

"""
    RoundRobinOperator(operators::Vector{<:AbstractLSOperator})

A compound operator that cycles through a list of sub-operators in order.
**Note:** This consumes the input operators; they cannot be used afterwards.
"""
mutable struct RoundRobinOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}
    operators::Vector{<:AbstractLSOperator}

    function RoundRobinOperator(ops::Vector{<:AbstractLSOperator})
        raw_ptrs = map(op -> release!(copy(op)), ops)
        ptr = ccall((:bollard_ls_round_robin_operator_new, libbollard_ffi), Ptr{Cvoid},
            (Ptr{Ptr{Cvoid}}, Csize_t), raw_ptrs, length(raw_ptrs))
        obj = new(ptr, ops)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(op::RoundRobinOperator) = RoundRobinOperator(op.operators)

"""
    RandomCompoundOperator(operators::Vector{<:AbstractLSOperator})

A compound operator that selects a sub-operator uniformly at random.
**Note:** This consumes the input operators.
"""
mutable struct RandomCompoundOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}
    operators::Vector{<:AbstractLSOperator}

    function RandomCompoundOperator(ops::Vector{<:AbstractLSOperator})
        raw_ptrs = map(op -> release!(copy(op)), ops)
        ptr = ccall((:bollard_ls_random_compound_operator_new, libbollard_ffi), Ptr{Cvoid},
            (Ptr{Ptr{Cvoid}}, Csize_t), raw_ptrs, length(raw_ptrs))
        obj = new(ptr, ops)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(op::RandomCompoundOperator) = RandomCompoundOperator(op.operators)

"""
    MultiArmedBanditOperator(operators::Vector{<:AbstractLSOperator}; memory_coeff=0.5, exploration_coeff=1.0)

A compound operator that uses a Multi-Armed Bandit strategy to select effective sub-operators.
**Note:** This consumes the input operators.
"""
mutable struct MultiArmedBanditOperator <: AbstractLSOperator
    ptr::Ptr{Cvoid}
    operators::Vector{<:AbstractLSOperator}
    memory_coeff::Float64
    exploration_coeff::Float64

    function MultiArmedBanditOperator(ops::Vector{<:AbstractLSOperator}; memory_coeff::Float64=0.5, exploration_coeff::Float64=1.0)
        raw_ptrs = map(op -> release!(copy(op)), ops)
        ptr = ccall((:bollard_ls_new_multi_armed_bandit_compound_operator, libbollard_ffi), Ptr{Cvoid},
            (Ptr{Ptr{Cvoid}}, Csize_t, Float64, Float64),
            raw_ptrs, length(raw_ptrs), memory_coeff, exploration_coeff)
        obj = new(ptr, ops, memory_coeff, exploration_coeff)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_free_dynamic_local_search_operator, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(op::MultiArmedBanditOperator) = MultiArmedBanditOperator(op.operators; memory_coeff=op.memory_coeff, exploration_coeff=op.exploration_coeff)

# =========================================================================
# Neighborhoods
# =========================================================================

"""
    FullNeighborhood(model::Model)

A neighborhood that explores all possible moves defined by the operator.
"""
mutable struct FullNeighborhood <: AbstractLSNeighborhood
    ptr::Ptr{Cvoid}
    function FullNeighborhood(model::Model)
        model.ptr == C_NULL && error("cannot create neighborhood from invalidated model")
        ptr = ccall((:bollard_ls_full_neighborhoods_new, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), model.ptr)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_neighborhoods_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

"""
    StaticTopologyNeighborhood(model::Model)

A restricted neighborhood based on a static topology analysis of the model.
"""
mutable struct StaticTopologyNeighborhood <: AbstractLSNeighborhood
    ptr::Ptr{Cvoid}
    function StaticTopologyNeighborhood(model::Model)
        model.ptr == C_NULL && error("cannot create neighborhood from invalidated model")
        ptr = ccall((:bollard_ls_static_topology_neighborhoods_new, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), model.ptr)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_neighborhoods_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

# =========================================================================
# Metaheuristics
# =========================================================================

"""
    GreedyDescent()

A simple metaheuristic that accepts only improving moves until a local optimum is reached.
"""
mutable struct GreedyDescent <: AbstractLSMetaheuristic
    ptr::Ptr{Cvoid}
    function GreedyDescent()
        ptr = ccall((:bollard_ls_greedy_descent_metaheuristic_new, libbollard_ffi), Ptr{Cvoid}, ())
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

Base.copy(::GreedyDescent) = GreedyDescent()

"""
    SimulatedAnnealing

A metaheuristic that probabilistically accepts worsening moves to escape local optima.

# Constructors
- `SimulatedAnnealing(initial::Float64, decrement::Float64, min_temp::Float64)`: Linear cooling.
- `SimulatedAnnealing(initial::Float64, alpha::Float64, min_temp::Float64; geometric=true)`: Geometric cooling.
- `SimulatedAnnealing(initial_solution::Solution)`: Defaults based on initial solution cost.
"""
mutable struct SimulatedAnnealing <: AbstractLSMetaheuristic
    ptr::Ptr{Cvoid}

    function SimulatedAnnealing(initial::Float64, decrement::Float64, min_temp::Float64)
        ptr = ccall((:bollard_ls_simulated_annealing_metaheuristic_with_linear_cooling_new, libbollard_ffi),
            Ptr{Cvoid}, (Float64, Float64, Float64), initial, decrement, min_temp)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function SimulatedAnnealing(initial::Float64, alpha::Float64, min_temp::Float64, ::Val{:geometric})
        ptr = ccall((:bollard_ls_simulated_annealing_metaheuristic_with_geometric_cooling_new, libbollard_ffi),
            Ptr{Cvoid}, (Float64, Float64, Float64), initial, alpha, min_temp)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function SimulatedAnnealing(initial_sol::Solution)
        initial_sol.ptr == C_NULL && error("solution is invalidated")
        ptr = ccall((:bollard_simulated_annealing_metaheuristic_with_geometric_cooling_from_solution_new, libbollard_ffi),
            Ptr{Cvoid}, (Ptr{Cvoid},), initial_sol.ptr)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

# Convenience constructor helper for geometric dispatch
SimulatedAnnealing(initial, alpha, min_temp; geometric::Bool=true) =
    geometric ? SimulatedAnnealing(initial, alpha, min_temp, Val(:geometric)) : SimulatedAnnealing(initial, alpha, min_temp)

"""
    GuidedLocalSearch

A metaheuristic that penalizes specific features of the solution to escape local optima.

# Constructors
- `GuidedLocalSearch(lambda::Float64)`: Specific penalty factor.
- `GuidedLocalSearch(model::Model, initial_solution::Solution)`: Defaults based on model and solution.
"""
mutable struct GuidedLocalSearch <: AbstractLSMetaheuristic
    ptr::Ptr{Cvoid}

    function GuidedLocalSearch(lambda::Float64)
        ptr = ccall((:bollard_ls_guided_local_search_metaheuristic_new, libbollard_ffi), Ptr{Cvoid}, (Float64,), lambda)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function GuidedLocalSearch(model::Model, initial_sol::Solution)
        (model.ptr == C_NULL || initial_sol.ptr == C_NULL) && error("invalidated arguments")
        ptr = ccall((:bollard_ls_guided_local_search_metaheuristic_with_defaults_from_model_and_solution_new, libbollard_ffi),
            Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}), model.ptr, initial_sol.ptr)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

"""
    TabuSearch

A metaheuristic that forbids recently visited moves.

# Constructors
- `TabuSearch(tenure::Integer)`: Specific tabu tenure size.
- `TabuSearch(model::Model)`: Tenure derived from model size.
"""
mutable struct TabuSearch <: AbstractLSMetaheuristic
    ptr::Ptr{Cvoid}

    function TabuSearch(tenure::Integer)
        ptr = ccall((:bollard_ls_tabu_search_metaheuristic_new, libbollard_ffi), Ptr{Cvoid}, (Csize_t,), tenure)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function TabuSearch(model::Model)
        model.ptr == C_NULL && error("invalidated model")
        ptr = ccall((:bollard_ls_tabu_search_metaheuristic_with_defaults_from_model_new, libbollard_ffi),
            Ptr{Cvoid}, (Ptr{Cvoid},), model.ptr)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_dynamic_metaheuristic_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

# =========================================================================
# LSSolver Object & Main Logic
# =========================================================================

"""
    LSSolver

The Local Search engine instance.
"""
mutable struct LSSolver
    ptr::Ptr{Cvoid}

    function LSSolver()
        ptr = ccall((:bollard_ls_engine_new, libbollard_ffi), Ptr{Cvoid}, ())
        obj = new(ptr)

        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_engine_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end

    function LSSolver(num_vessels::Integer)
        ptr = ccall((:bollard_ls_engine_preallocated, libbollard_ffi), Ptr{Cvoid}, (Csize_t,), num_vessels)
        obj = new(ptr)
        finalizer(obj) do x
            p = x.ptr
            x.ptr = C_NULL
            if p != C_NULL
                ccall((:bollard_ls_engine_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), p)
            end
        end
        return obj
    end
end

"""
    solve(solver::LSSolver, model::Model, initial_solution::Solution;
          neighborhood::AbstractLSNeighborhood,
          metaheuristic::AbstractLSMetaheuristic,
          operator::AbstractLSOperator,
          time_limit_ms::Integer=0,
          solution_limit::Integer=0,
          enable_log::Bool=false) -> LSOutcome

Execute the Local Search to improve an initial solution.

# Arguments
- `solver`: The engine instance.
- `model`: The problem definition.
- `initial_solution`: The starting point for the search.

# Keywords
- `neighborhood`: The neighborhood definition (Required).
- `metaheuristic`: The guidance strategy (Required).
- `operator`: The move operator (Required).
- `time_limit_ms`: Max execution time in milliseconds (0 = no limit).
- `solution_limit`: Max number of solutions to examine (0 = no limit).
- `enable_log`: Print search logs to stdout.
"""
function solve(
    solver::LSSolver,
    model::Model,
    initial_solution::Solution;
    neighborhood::AbstractLSNeighborhood,
    metaheuristic::AbstractLSMetaheuristic,
    operator::AbstractLSOperator,
    time_limit_ms::Integer=0,
    solution_limit::Integer=0,
    enable_log::Bool=false
)
    # Check pointers
    solver.ptr == C_NULL && error("solver is invalidated")
    model.ptr == C_NULL && error("model is invalidated")
    initial_solution.ptr == C_NULL && error("initial solution is invalidated")
    neighborhood.ptr == C_NULL && error("neighborhood is invalidated")
    metaheuristic.ptr == C_NULL && error("metaheuristic is invalidated")
    operator.ptr == C_NULL && error("operator is invalidated")

    GC.@preserve solver model initial_solution neighborhood metaheuristic operator begin
        raw_outcome = ccall((:bollard_ls_engine_run, libbollard_ffi), Ptr{Cvoid},
            (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, UInt64, UInt64, Bool),
            solver.ptr,
            model.ptr,
            initial_solution.ptr,
            neighborhood.ptr,
            metaheuristic.ptr,
            operator.ptr,
            UInt64(time_limit_ms),
            UInt64(solution_limit),
            enable_log
        )
    end

    return LSOutcome(raw_outcome)
end

function Base.show(io::IO, s::LSSolver)
    print(io, "LSSolver")
end