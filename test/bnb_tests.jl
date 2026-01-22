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

using Bollard
using Test

# =========================================================================
# Test Helper: Model Fabrication
# =========================================================================
"""
    make_valid_model(berths::Int, vessels::Int)

Creates a simple, solvable Model instance for testing purposes.
"""
function make_valid_model(berths::Int, vessels::Int)
    builder = ModelBuilder(berths, vessels)

    for v in 1:vessels
        # Set feasible windows (0 to 1000)
        builder.arrival_time!(v, 0)
        builder.latest_departure_time!(v, 1000)
        builder.weight!(v, 1)

        for b in 1:berths
            # Processing time scales with vessel index to make costs distinct
            builder.processing_time!(v, b, 10 * v)
        end
    end
    return builder.build()
end

# =========================================================================
# Main Test Suite
# =========================================================================

@testset "Bollard BnB Solver Test Suite" begin

    # ---------------------------------------------------------------------
    # 1. Enums & Data Structures
    # ---------------------------------------------------------------------
    @testset "Enums & Data Structures" begin
        @testset "Enum Integer Mapping" begin
            # BnbDecisionBuilderType
            @test Int(Bollard.Chronological) == 0
            @test Int(Bollard.EdfHeuristic) == 7

            # BnbObjectiveEvaluatorType
            @test Int(Bollard.EvaluatorHybrid) == 0
            @test Int(Bollard.EvaluatorWeightedCompletionTime) == 2

            # BnbTerminationReason
            @test Int(Bollard.BnbOptimalityProven) == 0
            @test Int(Bollard.BnbAborted) == 2
        end

        @testset "FixedAssignment Conversion" begin
            # High-level (1-based indexing)
            high = Bollard.BnbFixedAssignment(10, 5, 100) # Vessel 10, Berth 5 at t=100

            # Low-level conversion (0-based indexing)
            low = convert(Bollard.FfiBnbFixedAssignment, high)

            @test low isa Bollard.FfiBnbFixedAssignment
            @test low.start_time == 100
            @test low.vessel_index == 9 # 10 - 1
            @test low.berth_index == 4  # 5 - 1
        end
    end

    # ---------------------------------------------------------------------
    # 2. Solver Lifecycle
    # ---------------------------------------------------------------------
    @testset "Solver Lifecycle" begin
        @testset "Default Constructor" begin
            solver = BnbSolver()
            @test solver.ptr != C_NULL
            # Check representation string
            @test contains(repr(solver), "BnbSolver")
        end

        @testset "Model-Based Constructor" begin
            model = make_valid_model(1, 1)
            solver = BnbSolver(model)
            @test solver.ptr != C_NULL
        end
    end

    # ---------------------------------------------------------------------
    # 3. Integration: Solving & Warm Starts
    # ---------------------------------------------------------------------
    @testset "Integration: Solving" begin

        @testset "Basic Solve (Optimality Proven)" begin
            # 1 Vessel, 1 Berth. Trivial case.
            model = make_valid_model(1, 1)
            solver = BnbSolver()

            outcome = Bollard.solve(solver, model)

            @test outcome isa Bollard.BnbOutcome
            @test outcome.termination.reason == Bollard.BnbOptimalityProven
            @test outcome.result.has_solution == true

            # Verify Solution Details
            sol = outcome.result.solution
            @test sol.num_vessels == 1
            @test sol.berth(1) == 1
            @test sol.start_time(1) >= 0
        end

        @testset "Solve with Fixed Assignments" begin
            # 2 Vessels, 2 Berths. 
            builder = ModelBuilder(2, 2)
            # Standard windows
            for i in 1:2
                builder.arrival_time!(i, 0)
                builder.latest_departure_time!(i, 100)
                builder.weight!(i, 1)
            end
            # Processing times
            builder.processing_time!(1, 1, 10)
            builder.processing_time!(1, 2, 10)
            builder.processing_time!(2, 1, 10)
            builder.processing_time!(2, 2, 10)

            model = builder.build()
            solver = BnbSolver()

            # Constraint: Force Vessel 1 to Berth 2 starting at time 0
            fixed_move = Bollard.BnbFixedAssignment(1, 2, 0)

            outcome = Bollard.solve(solver, model, fixed=[fixed_move])

            @test outcome.result.has_solution
            sol = outcome.result.solution

            # Verify constraint was respected
            @test sol.berth(1) == 2
            @test sol.start_time(1) == 0
        end

        @testset "Warm Start (Initial Solution)" begin
            # 1. Create a model (2 vessels, 2 berths)
            model = make_valid_model(2, 2)
            solver = BnbSolver()

            # 2. First solve: Generate a solution to use as "Warm Start"
            outcome1 = Bollard.solve(solver, model)
            @test outcome1.result.has_solution
            initial_sol = outcome1.result.solution

            # Cache values to verify consistency
            v1_berth = initial_sol.berth(1)
            v1_start = initial_sol.start_time(1)

            # 3. Second solve: Pass the solution back as `initial_solution`
            # This exercises the `solve_with_initial_solution` FFI path.
            outcome2 = Bollard.solve(solver, model; initial_solution=initial_sol)

            @test outcome2.result.has_solution
            @test outcome2.termination.reason == Bollard.BnbOptimalityProven
            # The new cost should not be worse than the initial solution
            @test outcome2.result.solution.objective() <= initial_sol.objective()

            # 4. Third solve: Initial Solution + Consistent Fixed Assignment
            # This exercises the `solve_with_initial_solution_and_fixed_assignments` FFI path.
            consistent_fixed = Bollard.BnbFixedAssignment(1, v1_berth, v1_start)

            outcome3 = Bollard.solve(solver, model;
                initial_solution=initial_sol,
                fixed=[consistent_fixed]
            )

            @test outcome3.result.has_solution
            @test outcome3.result.solution.berth(1) == v1_berth
            @test outcome3.result.solution.start_time(1) == v1_start
        end

        @testset "Heuristics and Limits" begin
            model = make_valid_model(2, 5)
            solver = BnbSolver()

            outcome = Bollard.solve(solver, model;
                builder=Bollard.EdfHeuristic,
                evaluator=Bollard.EvaluatorWorkload,
                solution_limit=1,
                time_limit_ms=5000,
                enable_log=false
            )

            @test outcome.result.has_solution
            @test outcome.statistics.solutions_found >= 1
        end
    end

    # ---------------------------------------------------------------------
    # 4. Outcome, Statistics & Solution Views
    # ---------------------------------------------------------------------
    @testset "Outcome & Views" begin
        # FIX: Change vessels from 1 to 2 so the output vectors have length 2
        model = make_valid_model(2, 2)
        solver = BnbSolver()
        outcome = Bollard.solve(solver, model)
        sol = outcome.result.solution

        @testset "Statistics Access" begin
            stats = outcome.statistics
            @test stats.nodes_explored >= 0
            @test stats.time_total_ms >= 0

            # Formatting check
            io = IOBuffer()
            show(io, stats)
            @test contains(String(take!(io)), "nodes=")
        end

        @testset "Zero-Copy Views" begin
            # Test BerthView (converts 0-based to 1-based)
            berths = sol.berths()
            @test berths isa Bollard.BerthView
            @test length(berths) == 2  # Now this will pass (1 == 1 was failing before)
            @test berths[1] > 0

            # Test SolutionView (Raw data)
            starts = sol.start_times()
            @test starts isa Bollard.SolutionView
            @test length(starts) == 2  # Now this will pass
            @test starts[1] isa Int64
        end
    end

    # ---------------------------------------------------------------------
    # 5. Memory Safety & GC Stress
    # ---------------------------------------------------------------------
    @testset "Memory Safety & GC Stress" begin

        @testset "Outcome Children Survival" begin
            # Verify accessing children works even if parent outcome is GC'd
            # (Note: In Julia, we must keep parent alive if children rely on it, 
            # but here we test that our structs manage pointers correctly).
            function get_nodes()
                m = make_valid_model(1, 1)
                s = BnbSolver()
                return Bollard.solve(s, m).statistics.nodes_explored
            end

            val = get_nodes()
            GC.gc()
            @test val >= 0
        end

        @testset "Solver Re-use Stress" begin
            model = make_valid_model(1, 1)
            # Create many solvers and solve rapidly to test allocation/free cycles
            for _ in 1:50
                s = BnbSolver()
                res = Bollard.solve(s, model; solution_limit=1)
                @test res.result.has_solution
            end
            GC.gc()
            @test true # Survived without segfault
        end
    end
end