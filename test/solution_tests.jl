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
# Test Helper: Manual Solution Fabrication
# =========================================================================
# To test the Solution wrapper without running the full solver, we use
# the exposed FFI constructor to create a valid Rust object from raw data.
function create_dummy_solution_ptr(objective::Int64, berths::Vector{Int}, starts::Vector{Int64})
    n = length(berths)
    @assert length(starts) == n

    # Convert 1-based Julia indices (Input) to 0-based Rust indices (Internal Storage)
    # This simulates exactly what the solver would return: internal 0-based data.
    c_berths = [Csize_t(b - 1) for b in berths]

    # Call bollard_solution_new directly
    ptr = ccall((:bollard_solution_new, Bollard.libbollard_ffi), Ptr{Cvoid},
        (Int64, Ptr{Csize_t}, Ptr{Int64}, Csize_t),
        objective, c_berths, starts, Csize_t(n))

    return ptr
end

@testset "Bollard Solution Wrapper Test Suite" begin

    # =========================================================================
    # 1. Lifecycle & Base Functionality
    # =========================================================================
    @testset "Lifecycle & Dimensions" begin
        # Setup data
        ref_obj = 500
        ref_berths = [1, 2, 1]
        ref_starts = [10, 20, 30]

        # Create pointer and wrap
        ptr = create_dummy_solution_ptr(ref_obj, ref_berths, ref_starts)
        sol = Bollard.Solution(ptr)

        @test sol isa Bollard.AbstractBollardSolution
        @test length(sol) == 3
        @test sol.num_vessels == 3

        io = IOBuffer()
        show(io, sol)
        output = String(take!(io))
        @test contains(output, "Solution")
        @test contains(output, "vessels=3")
        @test contains(output, "Active")

        # Test NULL pointer protection in constructor
        @test_throws ErrorException Bollard.Solution(C_NULL)
    end

    # =========================================================================
    # 2. Data Integrity (Scalar Getters)
    # =========================================================================
    @testset "Data Integrity (Scalars)" begin
        ref_obj = 12345
        # Vessel 1 -> Berth 1, Start 100
        # Vessel 2 -> Berth 3, Start 200
        ptr = create_dummy_solution_ptr(ref_obj, [1, 3], [100, 200])
        sol = Bollard.Solution(ptr)

        @test sol.objective() == ref_obj

        # Check conversion from 0-based (Rust) to 1-based (Julia)
        # We input 1 and 3, Rust stored 0 and 2.
        # Getter should convert back to 1 and 3.
        @test sol.berth(1) == 1
        @test sol.berth(2) == 3

        @test sol.start_time(1) == 100
        @test sol.start_time(2) == 200
    end

    # =========================================================================
    # 3. Batch Retrieval (Safe Views & Conversion)
    # =========================================================================
    @testset "Batch Retrieval (Safe Views & Conversion)" begin
        # Data: [Berth 1, Berth 2, Berth 3, Berth 1]
        ref_berths = [1, 2, 3, 1]
        ref_starts = [10, 20, 30, 40]
        ptr = create_dummy_solution_ptr(0, ref_berths, ref_starts)
        sol = Bollard.Solution(ptr)

        @testset "Start Times View (SolutionView)" begin
            view = sol.start_times()
            @test view isa Bollard.SolutionView{Int64}
            @test length(view) == 4
            @test view == ref_starts
            @test view[1] == 10

            # Test Materialization (Copying)
            vec = Vector(view)
            @test vec isa Vector{Int64}
            @test vec == ref_starts

            # Verify Copy Semantics
            vec[1] = 9999
            @test view[1] == 10 # View unaffected
        end

        @testset "Berths View (BerthView)" begin
            view = sol.berths()

            # MUST be BerthView, not SolutionView
            @test view isa Bollard.BerthView{UInt}

            # CRITICAL: Verify 0-based to 1-based auto-conversion
            @test view[1] == 1
            @test view[2] == 2
            @test view[3] == 3

            # Test Materialization (Copying & Transforming)
            # This triggers Base.convert(Vector{Int}, BerthView)
            vec = Vector(view)

            @test vec isa Vector{Int}
            @test vec == ref_berths # Should be [1, 2, 3, 1]

            # Verify Copy Semantics
            vec[1] = 9999
            @test view[1] == 1 # View unaffected
        end
    end

    # =========================================================================
    # 4. Input Validation (Bounds)
    # =========================================================================
    @testset "Input Validation (Bounds)" begin
        ptr = create_dummy_solution_ptr(0, [1, 1], [0, 0])
        sol = Bollard.Solution(ptr)
        n = length(sol)

        @testset "Vessel Index Bounds" begin
            # Lower bound
            @test_throws BoundsError sol.berth(0)
            @test_throws BoundsError sol.start_time(0)

            # Upper bound
            @test_throws BoundsError sol.berth(n + 1)
            @test_throws BoundsError sol.start_time(n + 1)
        end
    end

    # =========================================================================
    # 5. Memory Safety & Use-After-Free
    # =========================================================================
    @testset "Memory Safety & Use-After-Free" begin
        ptr = create_dummy_solution_ptr(0, [1], [10])
        sol = Bollard.Solution(ptr)

        # 1. Verify Active State
        @test sol.ptr != C_NULL

        # 2. Manual Finalization (Simulation)
        finalize(sol)

        # 3. Verify Null State
        @test sol.ptr == C_NULL

        io = IOBuffer()
        show(io, sol)
        @test contains(String(take!(io)), "Freed")

        # 4. Verify Safety Checks on Access
        @test_throws ErrorException sol.objective()
        @test_throws ErrorException sol.berth(1)
        @test_throws ErrorException sol.start_time(1)
        @test_throws ErrorException sol.berths()
        @test_throws ErrorException sol.start_times()
    end

    # =========================================================================
    # 6. Garbage Collection Safety (View Persistence)
    # =========================================================================
    @testset "Safe View GC Persistence" begin
        function create_and_drop_sol()
            p = create_dummy_solution_ptr(0, [1, 2], [10, 20])
            s = Bollard.Solution(p)
            # The view holds a reference to 's', keeping 's' alive
            return s.start_times()
        end

        view = create_and_drop_sol()

        # Aggressive GC
        GC.gc()
        GC.gc()

        # Check if underlying memory is still valid
        @test view[1] == 10
        @test view[2] == 20
        @test view.parent.ptr != C_NULL # Parent must still be alive
    end

    @testset "Garbage Collection Stress Test" begin
        function churn_solutions()
            for _ in 1:1000
                p = create_dummy_solution_ptr(0, [1, 2], [10, 20])
                s = Bollard.Solution(p)
            end
        end
        churn_solutions()
        GC.gc()
        @test true
    end
end