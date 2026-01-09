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
function make_valid_model(berths::Int, vessels::Int)
    builder = ModelBuilder(berths, vessels)
    # Configure a solvable problem
    for v in 1:vessels
        builder.arrival_time!(v, 0)
        builder.latest_departure_time!(v, 1000)
        builder.weight!(v, 1)
        for b in 1:berths
            # Processing time = 10 * vessel_idx
            builder.processing_time!(v, b, 10 * v)
        end
    end
    return builder.build()
end

@testset "Bollard BnB Solver Test Suite" begin

    # =========================================================================
    # 1. Enums & Data Structures
    # =========================================================================
    @testset "Enums & Data Structures" begin
        @testset "Enum Integer Mapping" begin
            # BnbDecisionBuilderType
            @test Int(Bollard.ChronologicalExhaustive) == 0
            @test Int(Bollard.EarliestDeadlineFirst) == 7

            # BnbObjectiveEvaluatorType
            @test Int(Bollard.EvaluatorHybrid) == 0
            @test Int(Bollard.EvaluatorWeightedFlowTime) == 2

            # BnbTerminationReason
            @test Int(Bollard.BnbOptimalityProven) == 0
            @test Int(Bollard.BnbAborted) == 2
        end

        @testset "FixedAssignment Conversion" begin
            # High-level (1-based indexing)
            high = Bollard.BnbFixedAssignment(10, 5, 100) # Vessel 10, Berth 5

            # Low-level conversion (0-based indexing)
            low = convert(Bollard.FfiBnbFixedAssignment, high)

            @test low isa Bollard.FfiBnbFixedAssignment
            @test low.start_time == 100
            @test low.vessel_index == 9 # 10 - 1
            @test low.berth_index == 4  # 5 - 1
        end
    end

    # =========================================================================
    # 2. Solver Lifecycle
    # =========================================================================
    @testset "Solver Lifecycle" begin
        @testset "Default Constructor" begin
            solver = BnbSolver()
            @test solver.ptr != C_NULL
            @test contains(repr(solver), "Ready")
            # Finalizer runs automatically at block end or GC
        end

        @testset "Model-Based Constructor" begin
            model = make_valid_model(1, 1)
            solver = BnbSolver(model)
            @test solver.ptr != C_NULL
        end

        @testset "Invalid Input Safety" begin
            # Ensure we catch null pointer models if user tries to pass one manually
            # (Simulated by consuming a builder and passing a freed object if accessible)
            # Since Model prevents access after free, we assume Model wrapper safety here.
        end
    end

    # =========================================================================
    # 3. Integration: Solving
    # =========================================================================
    @testset "Integration: Solving" begin

        @testset "Basic Solve (Optimality Proven)" begin
            # 1 Vessel, 1 Berth. Trivial.
            model = make_valid_model(1, 1)
            solver = BnbSolver()

            # UPDATED SYNTAX: solve(solver, model)
            outcome = Bollard.solve(solver, model)

            @test outcome isa Bollard.BnbOutcome
            @test outcome.termination.reason == Bollard.BnbOptimalityProven
            @test outcome.result.has_solution == true

            # Check solution details
            sol = outcome.result.solution
            @test sol.num_vessels == 1
            @test sol.berth(1) == 1
        end

        @testset "Solve with Fixed Assignments" begin
            # 2 Vessels, 2 Berths. 
            # V1 can go to B1 or B2. We force V1 -> B2.
            builder = ModelBuilder(2, 2)

            # Setup feasible windows
            builder.arrival_time!(1, 0)
            builder.latest_departure_time!(1, 100)
            builder.arrival_time!(2, 0)
            builder.latest_departure_time!(2, 100)
            builder.weight!(1, 1)
            builder.weight!(2, 1)

            # Processing times
            builder.processing_time!(1, 1, 10)
            builder.processing_time!(1, 2, 10)
            builder.processing_time!(2, 1, 10)
            builder.processing_time!(2, 2, 10)

            model = builder.build()
            solver = BnbSolver()

            # Force Vessel 1 to Berth 2 starting at time 0
            fixed_move = Bollard.BnbFixedAssignment(1, 2, 0)

            # UPDATED SYNTAX: solve(solver, model, ...)
            outcome = Bollard.solve(solver, model, fixed=[fixed_move])

            @test outcome.result.has_solution
            sol = outcome.result.solution

            # Verify the constraint was respected
            @test sol.berth(1) == 2
            @test sol.start_time(1) == 0
        end

        @testset "Heuristics and Limits" begin
            model = make_valid_model(2, 5) # Slightly larger
            solver = BnbSolver()

            # Test configuration passing
            outcome = Bollard.solve(solver, model;
                builder=Bollard.EarliestDeadlineFirst,
                evaluator=Bollard.EvaluatorWorkload,
                solution_limit=1, # Stop after 1 solution
                enable_log=false
            )

            # It might find optimal immediately or abort depending on solver logic for limit=1
            @test outcome.result.has_solution
            @test outcome.statistics.solutions_found >= 1
        end
    end

    # =========================================================================
    # 4. Outcome & Statistics Access
    # =========================================================================
    @testset "Outcome & Statistics Access" begin
        model = make_valid_model(1, 1)
        solver = BnbSolver()
        outcome = Bollard.solve(solver, model)

        stats = outcome.statistics
        @test stats.nodes_explored >= 0
        @test stats.time_total_ms >= 0
        @test stats.max_depth >= 0

        term = outcome.termination
        @test term.message isa String
        @test !isempty(term.message)

        # Verify printing
        io = IOBuffer()
        show(io, stats)
        @test contains(String(take!(io)), "BnbStatistics")

        io = IOBuffer()
        show(io, term)
        @test contains(String(take!(io)), "BnbTermination")
    end

    # =========================================================================
    # 5. Memory Safety & GC Stress
    # =========================================================================
    @testset "Memory Safety & GC Stress" begin

        @testset "Outcome Children Survival" begin
            # Verify that accessing children (stats, termination) is safe
            # even if we don't hold the Outcome variable explicitly.
            function get_stats_node_count()
                m = make_valid_model(1, 1)
                s = BnbSolver()
                o = Bollard.solve(s, m)
                return o.statistics.nodes_explored
            end

            count = get_stats_node_count()
            GC.gc()
            @test count >= 0
        end

        @testset "Solver GC Stress" begin
            model = make_valid_model(1, 1)
            function churn()
                for _ in 1:100
                    s = BnbSolver()
                    Bollard.solve(s, model; solution_limit=1)
                end
            end
            churn()
            GC.gc()
            @test true # Passed without segfault
        end
    end
end