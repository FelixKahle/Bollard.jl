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

@testset "Bollard Wrapper Test Suite" begin

    # =========================================================================
    # 1. Auxiliary Data Structures
    # =========================================================================
    @testset "Data Structures: FfiOpenClosedInterval" begin
        iv = Bollard.FfiOpenClosedInterval(10, 20)
        @test iv.start_inclusive == 10
        @test iv.end_exclusive == 20

        io = IOBuffer()
        show(io, iv)
        @test String(take!(io)) == "[10, 20)"
    end

    # =========================================================================
    # 2. Builder Lifecycle & Base Functionality
    # =========================================================================
    @testset "Builder Lifecycle & Dimensions" begin
        num_berths, num_vessels = 3, 5
        builder = ModelBuilder(num_berths, num_vessels)

        @test size(builder) == (5, 3)
        @test length(builder) == 5
        @test builder.num_vessels == 5
        @test builder.num_berths == 3

        io = IOBuffer()
        show(io, builder)
        output = String(take!(io))
        @test contains(output, "ModelBuilder")
        @test contains(output, "Configuring")

        @test_throws ArgumentError ModelBuilder(-1, 5)
        @test_throws ArgumentError ModelBuilder(5, -1)
    end

    # =========================================================================
    # 3. Input Validation (Bounds & Arguments)
    # =========================================================================
    @testset "Input Validation (Setters)" begin
        builder = ModelBuilder(2, 2)

        @testset "Vessel Index Bounds" begin
            @test_throws BoundsError builder.set_weight!(0, 10)
            @test_throws BoundsError builder.set_weight!(3, 10)

            @test_throws BoundsError builder.set_arrival_time!(0, 100)
            @test_throws BoundsError builder.set_arrival_time!(3, 100)
        end

        @testset "Berth Index Bounds" begin
            @test_throws BoundsError builder.add_opening_time!(0, 0, 10)
            @test_throws BoundsError builder.add_opening_time!(3, 0, 10)

            @test_throws BoundsError builder.add_closing_time!(0, 0, 10)
            @test_throws BoundsError builder.add_closing_time!(3, 0, 10)
        end

        @testset "Matrix (Vessel x Berth) Bounds" begin
            @test_throws BoundsError builder.set_processing_time!(3, 1, 100)
            @test_throws BoundsError builder.set_processing_time!(1, 3, 100)
            @test_throws BoundsError builder.forbid_assignment!(3, 1)
            @test_throws BoundsError builder.forbid_assignment!(1, 3)
        end

        @testset "Argument Logic Constraints" begin
            @test_throws ArgumentError builder.set_weight!(1, -5)
            @test_nowarn builder.set_weight!(1, 0)
        end
    end

    # =========================================================================
    # 4. Data Integrity (Round-Trip Test)
    # =========================================================================
    @testset "Data Integrity (Set -> Build -> Get)" begin
        builder = ModelBuilder(1, 1)

        ref_arrival = 100
        ref_departure = 500
        ref_weight = 50
        ref_proc_time = 45

        ref_open_start = 0
        ref_close_start, ref_close_end = 150, 160

        builder.set_arrival_time!(1, ref_arrival)
        builder.set_latest_departure_time!(1, ref_departure)
        builder.set_weight!(1, ref_weight)
        builder.set_processing_time!(1, 1, ref_proc_time)
        builder.add_opening_time!(1, 0, 500)
        builder.add_closing_time!(1, ref_close_start, ref_close_end)

        model = builder.build()

        # Verify Scalars
        @test model.get_arrival_time(1) == ref_arrival
        @test model.get_latest_departure_time(1) == ref_departure
        @test model.get_weight(1) == ref_weight
        @test model.get_processing_time(1, 1) == ref_proc_time

        open_ivs = model.get_opening_intervals(1)
        @test length(open_ivs) == 2

        @test open_ivs[1].start_inclusive == ref_open_start
        @test open_ivs[1].end_exclusive == ref_close_start

        @test open_ivs[2].start_inclusive == ref_close_end
        @test open_ivs[2].end_exclusive == typemax(Int64)

        close_ivs = model.get_closing_intervals(1)
        @test length(close_ivs) == 1
        @test close_ivs[1].start_inclusive == ref_close_start
        @test close_ivs[1].end_exclusive == ref_close_end
    end

    # =========================================================================
    # 5. Model Logic & Constraints
    # =========================================================================
    @testset "Model Logic: Allowed vs Forbidden" begin
        builder = ModelBuilder(2, 1)
        builder.set_processing_time!(1, 1, 100)
        builder.forbid_assignment!(1, 2)

        model = builder.build()

        @testset "Allowed Case (Berth 1)" begin
            @test model.is_allowed(1, 1) == true
            @test model.is_forbidden(1, 1) == false
            @test model.get_processing_time(1, 1) == 100
        end

        @testset "Forbidden Case (Berth 2)" begin
            @test model.is_allowed(1, 2) == false
            @test model.is_forbidden(1, 2) == true
            @test model.get_processing_time(1, 2) == -1
        end
    end

    # =========================================================================
    # 6. Metadata & Complexity
    # =========================================================================
    @testset "Model Metadata" begin
        builder = ModelBuilder(2, 5)
        model = builder.build()

        @test model.log_complexity() isa Float64

        io = IOBuffer()
        show(io, model)
        output = String(take!(io))
        @test contains(output, "Model")
        @test contains(output, "Optimized")
        @test contains(output, "vessels=5")
    end

    # =========================================================================
    # 7. Memory Safety & State Management
    # =========================================================================
    @testset "Memory Safety & Ownership" begin
        @testset "Builder Consumption" begin
            builder = ModelBuilder(1, 1)
            @test builder.ptr != C_NULL

            model = builder.build()

            @test builder.ptr == C_NULL
            @test_throws ErrorException builder.build()
        end

        @testset "Garbage Collection Stress Test" begin
            function churn_memory()
                for _ in 1:200
                    b = ModelBuilder(2, 2)
                    b.set_weight!(1, 10)
                    m = b.build()
                end
            end
            churn_memory()
            GC.gc()
            @test true
        end
    end
end