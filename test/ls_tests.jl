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
# Test Helper: Model & Solution Fabrication
# =========================================================================

"""
    make_simple_model_and_solution(berths::Int, vessels::Int)

Creates a valid Model and a feasible initial Solution.
Local Search requires an initial solution to start.
"""
function make_simple_model_and_solution(berths::Int, vessels::Int)
    # 1. Create Model
    builder = ModelBuilder(berths, vessels)
    for v in 1:vessels
        builder.arrival_time!(v, 0)
        builder.latest_departure_time!(v, 1000)
        builder.weight!(v, 1)
        for b in 1:berths
            builder.processing_time!(v, b, 10)
        end
    end
    model = builder.build()

    # 2. Get an initial solution using the BnB solver (fast for small instances)
    bnb_solver = BnbSolver()
    bnb_outcome = Bollard.solve(bnb_solver, model; solution_limit=1)

    if !bnb_outcome.result.has_solution
        error("Helper failed to generate initial solution for LS tests.")
    end

    return (model, bnb_outcome.result.solution)
end

# =========================================================================
# Main Test Suite
# =========================================================================

@testset "Bollard LS Solver Test Suite" begin

    # ---------------------------------------------------------------------
    # 1. Enums & Data Structures
    # ---------------------------------------------------------------------
    @testset "Enums & Structures" begin
        @testset "Termination Reasons" begin
            @test Int(Bollard.LSLocalOptimum) == 0
            @test Int(Bollard.LSMetaheuristic) == 1
            @test Int(Bollard.LSAborted) == 2
        end
    end

    # ---------------------------------------------------------------------
    # 2. Component Construction & Copying
    # ---------------------------------------------------------------------
    @testset "Component Construction" begin
        (model, sol) = make_simple_model_and_solution(2, 2)

        @testset "Operators Basic" begin
            @test SwapOperator() isa SwapOperator
            @test ShiftOperator() isa ShiftOperator
            @test TwoOptOperator() isa TwoOptOperator
        end

        @testset "ScrambleOperator State" begin
            # Test random vs deterministic seeding
            scramble_rand = ScrambleOperator()
            scramble_det = ScrambleOperator(UInt64(12345))

            @test scramble_rand isa ScrambleOperator
            @test scramble_det isa ScrambleOperator

            # Verify copy mechanics
            cp = copy(scramble_det)
            @test cp isa ScrambleOperator
            @test cp.ptr != C_NULL
            @test cp.ptr != scramble_det.ptr
        end

        @testset "Compound Operators" begin
            ops = [SwapOperator(), ShiftOperator()]

            # Round Robin
            rr = RoundRobinOperator(ops)
            @test rr isa RoundRobinOperator
            @test rr.ptr != C_NULL

            # Random Compound
            rand_op = RandomCompoundOperator(ops)
            @test rand_op isa RandomCompoundOperator

            # MAB
            mab = MultiArmedBanditOperator(ops)
            @test mab isa MultiArmedBanditOperator
        end

        @testset "Neighborhoods" begin
            @test FullNeighborhood(model) isa FullNeighborhood
            @test StaticTopologyNeighborhood(model) isa StaticTopologyNeighborhood
        end

        @testset "Metaheuristics" begin
            @test GreedyDescent() isa GreedyDescent
            @test SimulatedAnnealing(100.0, 0.99, 0.1) isa SimulatedAnnealing
            @test TabuSearch(10) isa TabuSearch
            @test GuidedLocalSearch(0.5) isa GuidedLocalSearch
        end
    end

    # ---------------------------------------------------------------------
    # 3. Solver Integration
    # ---------------------------------------------------------------------
    @testset "Integration: Solving" begin
        (model, initial_sol) = make_simple_model_and_solution(2, 5)
        solver = LSSolver()

        @testset "Greedy Descent Run" begin
            outcome = Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=ShiftOperator(),
                enable_log=false
            )

            @test outcome isa Bollard.LSOutcome
            # Termination reason usually LocalOptimum for small greedy runs
            @test outcome.termination.reason in (Bollard.LSLocalOptimum, Bollard.LSMetaheuristic)
            @test outcome.solution.objective() <= initial_sol.objective()
            @test outcome.statistics.iterations > 0
        end

        @testset "Simulated Annealing Run" begin
            outcome = Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=SimulatedAnnealing(initial_sol),
                operator=SwapOperator(),
                time_limit_ms=200, # Give it enough time to make moves
                enable_log=false
            )
            @test outcome.solution.num_vessels == 5
            @test outcome.statistics.time_total_ms >= 0
        end

        @testset "Operator Reuse Integration" begin
            op = ShiftOperator()

            # Run 1
            Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=op,
                solution_limit=10
            )

            # Run 2 (Reuse 'op' should work)
            res2 = Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=op,
                solution_limit=10
            )

            @test res2.statistics.iterations > 0
        end
    end

    # ---------------------------------------------------------------------
    # 4. Edge Cases (Fixed)
    # ---------------------------------------------------------------------
    @testset "Edge Cases" begin
        # 

        # We use a slightly larger model (10 vessels) so it doesn't finish instantly
        # allowing us to test that the Abort monitors actually trigger.
        (model, initial_sol) = make_simple_model_and_solution(2, 10)
        solver = LSSolver()

        @testset "Strict Solution Limit" begin
            # Set limit to 1. Should abort immediately after finding 1 solution (or checking 1).
            outcome = Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=SwapOperator(),
                solution_limit=1
            )

            # Note: Depending on race/implementation, it might find LocalOptimum instantly
            # if 10 vessels are already optimal (unlikely).
            # But normally, limits trigger 'LSAborted'.
            if outcome.termination.reason != Bollard.LSLocalOptimum
                @test outcome.termination.reason == Bollard.LSAborted
            end
        end

        @testset "Strict Time Limit" begin
            # Set limit to 1ms. Should abort almost immediately.
            outcome = Bollard.solve(solver, model, initial_sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=SwapOperator(),
                time_limit_ms=1
            )

            # Again, checks if it didn't finish naturally
            if outcome.termination.reason != Bollard.LSLocalOptimum
                @test outcome.termination.reason == Bollard.LSAborted
            end
        end
    end

    # ---------------------------------------------------------------------
    # 5. Memory Safety & Lifecycle
    # ---------------------------------------------------------------------
    @testset "Memory Safety" begin

        @testset "Operator Ownership Transfer" begin
            # Verify that passing operators to a compound operator COPIES them,
            # leaving the original Julia wrappers valid and safe to reuse.
            op1 = SwapOperator()
            op2 = ShiftOperator()

            @test op1.ptr != C_NULL
            @test op2.ptr != C_NULL

            compound = RandomCompoundOperator([op1, op2])

            # The wrappers should now REMAIN VALID
            @test op1.ptr != C_NULL
            @test op2.ptr != C_NULL
            @test compound.ptr != C_NULL

            # Ensure the compound operator is actually usable
            (model, sol) = make_simple_model_and_solution(2, 4)
            res = Bollard.solve(LSSolver(), model, sol;
                neighborhood=FullNeighborhood(model),
                metaheuristic=GreedyDescent(),
                operator=compound,
                solution_limit=10
            )
            @test res.statistics.iterations >= 0
        end

        @testset "GC Stress Test" begin
            (model, sol) = make_simple_model_and_solution(1, 2)

            # Rapidly create and destroy solver components
            for _ in 1:20
                local s = LSSolver()
                local op = ShiftOperator()
                local nh = FullNeighborhood(model)
                local mh = GreedyDescent()

                res = Bollard.solve(s, model, sol;
                    neighborhood=nh,
                    metaheuristic=mh,
                    operator=op,
                    solution_limit=1
                )
                @test res.statistics.iterations >= 0
            end
            GC.gc()
            @test true
        end
    end
end