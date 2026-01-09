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

@testset "Bollard Model Wrapper Test Suite" begin

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
            @test_throws BoundsError builder.weight!(0, 10)
            @test_throws BoundsError builder.weight!(3, 10)

            @test_throws BoundsError builder.arrival_time!(0, 100)
            @test_throws BoundsError builder.arrival_time!(3, 100)
        end

        @testset "Berth Index Bounds" begin
            @test_throws BoundsError builder.add_opening_time!(0, 0, 10)
            @test_throws BoundsError builder.add_opening_time!(3, 0, 10)

            @test_throws BoundsError builder.add_closing_time!(0, 0, 10)
            @test_throws BoundsError builder.add_closing_time!(3, 0, 10)
        end

        @testset "Matrix (Vessel x Berth) Bounds" begin
            @test_throws BoundsError builder.processing_time!(3, 1, 100)
            @test_throws BoundsError builder.processing_time!(1, 3, 100)
            @test_throws BoundsError builder.forbid_assignment!(3, 1)
            @test_throws BoundsError builder.forbid_assignment!(1, 3)
        end

        @testset "Argument Logic Constraints" begin
            @test_throws ArgumentError builder.weight!(1, -5)
            @test_nowarn builder.weight!(1, 0)
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

        builder.arrival_time!(1, ref_arrival)
        builder.latest_departure_time!(1, ref_departure)
        builder.weight!(1, ref_weight)
        builder.processing_time!(1, 1, ref_proc_time)
        builder.add_opening_time!(1, 0, 500)
        builder.add_closing_time!(1, ref_close_start, ref_close_end)

        model = builder.build()

        # Verify Scalars
        @test model.arrival_time(1) == ref_arrival
        @test model.latest_departure_time(1) == ref_departure
        @test model.weight(1) == ref_weight
        @test model.processing_time(1, 1) == ref_proc_time

        open_ivs = model.opening_intervals(1)
        @test length(open_ivs) == 2

        @test open_ivs[1].start_inclusive == ref_open_start
        @test open_ivs[1].end_exclusive == ref_close_start

        @test open_ivs[2].start_inclusive == ref_close_end
        @test open_ivs[2].end_exclusive == typemax(Int64)

        close_ivs = model.closing_intervals(1)
        @test length(close_ivs) == 1
        @test close_ivs[1].start_inclusive == ref_close_start
        @test close_ivs[1].end_exclusive == ref_close_end
    end

    # =========================================================================
    # 5. Batch Retrieval (Zero-Copy Safe Views)
    # =========================================================================
    @testset "Batch Retrieval Methods (Safe Views)" begin
        # 3 Vessels, 2 Berths
        builder = ModelBuilder(2, 3)

        # Set diverse properties
        arrivals = [10, 20, 30]
        departures = [100, 200, 300]

        for i in 1:3
            builder.arrival_time!(i, arrivals[i])
            builder.latest_departure_time!(i, departures[i])
        end

        # Set processing times:
        # V1: B1=5, B2=10
        # V2: B1=Forbidden, B2=20
        # V3: B1=15, B2=Forbidden
        builder.processing_time!(1, 1, 5)
        builder.processing_time!(1, 2, 10)

        builder.forbid_assignment!(2, 1)
        builder.processing_time!(2, 2, 20)

        builder.processing_time!(3, 1, 15)
        builder.forbid_assignment!(3, 2)

        model = builder.build()

        @testset "arrival_times" begin
            view = model.arrival_times()
            @test view isa AbstractVector{Int64}
            # Verify custom struct
            @test view isa Bollard.ModelView{Int64}
            @test length(view) == 3
            @test view == arrivals
        end

        @testset "View Materialization (Convert/Collect)" begin
            view = model.arrival_times()

            # 1. Test 'collect' (standard iteration)
            vec_collected = collect(view)
            @test vec_collected isa Vector{Int64}
            @test vec_collected == arrivals

            # 2. Test explicit 'convert' (optimized copy)
            vec_converted = convert(Vector{Int64}, view)
            @test vec_converted isa Vector{Int64}
            @test vec_converted == arrivals

            # 3. Test 'Vector(...)' constructor shortcut
            vec_ctor = Vector(view)
            @test vec_ctor == arrivals

            # 4. Verify it is a COPY, not a view
            vec_converted[1] = 9999
            @test view[1] == 10  # View remains unchanged
        end

        @testset "latest_departure_times" begin
            view = model.latest_departure_times()
            @test view isa AbstractVector{Int64}
            @test view isa Bollard.ModelView{Int64}
            @test length(view) == 3
            @test view == departures
        end

        @testset "processing_times (row by row)" begin
            # Vessel 1
            row1 = model.processing_times(1)
            @test row1 isa Bollard.ModelView{Int64}
            @test row1 == [5, 10]

            # Vessel 2
            row2 = model.processing_times(2)
            @test row2 == [-1, 20] # -1 for forbidden

            # Vessel 3
            row3 = model.processing_times(3)
            @test row3 == [15, -1]

            # Materialization check for rows
            row2_vec = Vector(row2)
            @test row2_vec isa Vector{Int64}
            @test row2_vec == [-1, 20]

            # Bounds check
            @test_throws BoundsError model.processing_times(0)
            @test_throws BoundsError model.processing_times(4)
        end

        @testset "Empty Interval Handling" begin
            ivs = model.closing_intervals(2)
            @test ivs isa AbstractVector
            @test ivs isa Bollard.ModelView
            @test isempty(ivs)
            @test Vector(ivs) == []
        end
    end

    # =========================================================================
    # 6. Model Logic & Constraints
    # =========================================================================
    @testset "Model Logic: Allowed vs Forbidden" begin
        builder = ModelBuilder(2, 1)
        builder.processing_time!(1, 1, 100)
        builder.forbid_assignment!(1, 2)

        model = builder.build()

        @testset "Allowed Case (Berth 1)" begin
            @test model.is_allowed(1, 1) == true
            @test model.is_forbidden(1, 1) == false
            @test model.processing_time(1, 1) == 100
        end

        @testset "Forbidden Case (Berth 2)" begin
            @test model.is_allowed(1, 2) == false
            @test model.is_forbidden(1, 2) == true
            @test model.processing_time(1, 2) == -1
        end
    end

    # =========================================================================
    # 7. Metadata & Complexity
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
    # 8. Memory Safety & State Management
    # =========================================================================
    @testset "Memory Safety & Ownership" begin
        @testset "Builder Consumption" begin
            builder = ModelBuilder(1, 1)
            @test builder.ptr != C_NULL

            model = builder.build()

            @test builder.ptr == C_NULL
            @test_throws ErrorException builder.build()
        end

        @testset "Safe View Ownership (GC Safety Test)" begin
            # Verify that holding a View prevents the Model from being GC'd.
            # If Model was GC'd, the pointer inside the view would dangle.

            function create_view_and_drop_model()
                b = ModelBuilder(1, 3)
                b.arrival_time!(1, 100)
                b.arrival_time!(2, 200)
                b.arrival_time!(3, 300)
                m = b.build()
                # Return the VIEW, drop 'm'
                return m.arrival_times()
            end

            view = create_view_and_drop_model()

            # Aggressive GC to try and kill the parent Model
            GC.gc()
            GC.gc()

            # Accessing the view should still be safe because the view holds a reference to 'm'
            @test view[1] == 100
            @test view[3] == 300
            @test view.parent.ptr != C_NULL # Parent should still be alive
        end

        @testset "Garbage Collection Stress Test" begin
            function churn_memory()
                for _ in 1:200
                    b = ModelBuilder(2, 2)
                    b.weight!(1, 10)
                    m = b.build()
                end
            end
            churn_memory()
            GC.gc()
            @test true
        end
    end
end