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

@testset "Bollard Result & Termination Test Suite" begin

    # =========================================================================
    # 1. Enum Mapping Verification
    # =========================================================================
    @testset "Enum Integer Values" begin
        # Verify Julia enums match Rust #[repr(C)] layout
        @test Int(Bollard.StatusOptimal) == 0
        @test Int(Bollard.StatusFeasible) == 1
        @test Int(Bollard.StatusInfeasible) == 2
        @test Int(Bollard.StatusUnknown) == 3

        @test Int(Bollard.ReasonOptimalityProven) == 0
        @test Int(Bollard.ReasonInfeasibilityProven) == 1
        @test Int(Bollard.ReasonConverged) == 2
        @test Int(Bollard.ReasonAborted) == 3
    end

    # =========================================================================
    # 2. SolverResult Safety
    # =========================================================================
    @testset "SolverResult Null Safety" begin
        # Ensure we can't instantiate a result with a null pointer
        @test_throws ErrorException Bollard.SolverResult(C_NULL)
    end

    @testset "Termination Null Safety" begin
        @test_throws ErrorException Bollard.Termination(C_NULL)
    end

    # Note: Comprehensive logic tests for SolverResult (like extracting the solution)
    # require a valid pointer from the Rust backend. 
    # Since we don't have a `create_dummy_result` C function exposed yet,
    # those logic paths are best tested via the `solve()` integration test
    # or by adding a test helper in Rust similar to `bollard_solution_new`.
end