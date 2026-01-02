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

@testset "BnbSolver and Outcome Logic" begin

    # --- 1. Helper with Processing Time ---
    function create_trivial_model()
        # 1 Berth, 1 Vessel
        builder = ModelBuilder(1, 1)
        builder.set_arrival_time!(1, 0)
        builder.set_latest_departure_time!(1, 100)
        builder.set_weight!(1, 10)

        # CRITICAL: Set processing time so the problem is feasible
        builder.set_processing_time!(1, 1, 10)

        return builder.build()
    end

    @testset "Solver Instantiation" begin
        solver1 = BnbSolver()
        @test solver1.ptr != C_NULL

        solver2 = BnbSolver(5, 10)
        @test solver2.ptr != C_NULL

        @test solver1 !== solver2
    end

    @testset "Strategy Dispatch & Invalid Arguments" begin
        model = create_trivial_model()
        solver = BnbSolver()

        # Should be Optimal now that processing time is set
        outcome = solve(model, solver, evaluator=:Hybrid, heuristic=:Regret)

        # CHANGED: Updated struct name from SolverOutcome to BnbSolverOutcome
        @test outcome isa BnbSolverOutcome
        @test outcome.status == Bollard.StatusOptimal

        @test_throws ArgumentError solve(model, solver, evaluator=:InvalidEval)
        @test_throws ArgumentError solve(model, solver, heuristic=:InvalidHeur)
    end

    @testset "Outcome Inspection" begin
        model = create_trivial_model()
        solver = BnbSolver()
        outcome = solve(model, solver)

        # CHANGED: Updated enum types
        @test outcome.status isa Bollard.BnbSolverStatus
        @test outcome.termination_reason isa Bollard.BnbTerminationReason

        # Should be Optimal
        @test outcome.status == Bollard.StatusOptimal
        @test outcome.is_optimal == true
        @test outcome.has_solution == true

        @test outcome.nodes_explored isa UInt64
        @test outcome.time_ms isa UInt64
    end

    @testset "Solution Extraction" begin
        # 2 Berths, 2 Vessels
        builder = ModelBuilder(2, 2)

        # Vessel 1
        builder.set_arrival_time!(1, 0)
        builder.set_latest_departure_time!(1, 100)
        builder.set_weight!(1, 10)
        # Set processing times for Vessel 1
        builder.set_processing_time!(1, 1, 10)
        builder.set_processing_time!(1, 2, 10)

        # Vessel 2
        builder.set_arrival_time!(2, 0)
        builder.set_latest_departure_time!(2, 100)
        builder.set_weight!(2, 20)
        # Set processing times for Vessel 2
        builder.set_processing_time!(2, 1, 10)
        builder.set_processing_time!(2, 2, 10)

        model = builder.build()
        solver = BnbSolver()
        outcome = solve(model, solver)

        @test outcome.has_solution
        berths, start_times = outcome.solution

        @test length(berths) == 2
        @test length(start_times) == 2
        @test all(b -> b in [1, 2], berths)
    end

    @testset "Fixed Assignments" begin
        # 2 Berths, 1 Vessel
        builder = ModelBuilder(2, 1)
        builder.set_arrival_time!(1, 0)
        builder.set_latest_departure_time!(1, 50)
        builder.set_weight!(1, 10)

        # CRITICAL: Processing times must be set for ALL options to ensure feasibility
        builder.set_processing_time!(1, 1, 10)
        builder.set_processing_time!(1, 2, 10)

        model = builder.build()
        solver = BnbSolver()

        # Force Vessel 1 to Berth 2 at time 5
        fixed = [FixedAssignment(1, 2, 5)]

        # We use the default heuristic (Regret) to prove it works
        outcome = solve(model, solver, fixed_assignments=fixed)

        if !outcome.has_solution
            @error "Fixed Assignment Solver Status: $(outcome.status)"
        end

        @test outcome.has_solution

        berths, start_times = outcome.solution
        @test berths[1] == 2
        @test start_times[1] == 5
    end

    @testset "Memory Safety (Stress Test)" begin
        function stress_solve()
            for _ in 1:50
                m = create_trivial_model()
                s = BnbSolver()
                o = solve(m, s)
                stat = o.status
            end
        end
        stress_solve()
        GC.gc()
        @test true
    end
end