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

"""
    FfiOpenClosedInterval

A simple C-compatible struct representing a time interval `[start, end)`.
Used for passing time windows (opening/closing times) across the FFI boundary.

# Fields
- `start_inclusive::Int64`: The inclusive start timestamp.
- `end_exclusive::Int64`: The exclusive end timestamp.
"""
struct FfiOpenClosedInterval
    start_inclusive::Int64 # inclusive
    end_exclusive::Int64   # exclusive
end

"""
    Base.show(io::IO, iv::FfiOpenClosedInterval)

Print a human-readable representation of the interval in standard mathematical notation: `[start, end)`.
"""
Base.show(io::IO, iv::FfiOpenClosedInterval) = print(io, "[$(iv.start_inclusive), $(iv.end_exclusive))")

"""
    AbstractBollardModel

Abstract supertype for all Bollard core types, specifically `ModelBuilder` and the compiled `Model`.
"""
abstract type AbstractBollardModel end

"""
    ModelBuilder <: AbstractBollardModel

A mutable builder object used to configure the definition of a Bollard optimization problem.
It acts as a staging area where problem constraints (vessels, berths, timings) are defined
before being compiled into an immutable `Model`.

# Fields
- `ptr::Ptr{Cvoid}`: Pointer to the underlying Rust `ModelBuilder` instance.
- `num_vessels::Int`: Total number of vessels in the problem.
- `num_berths::Int`: Total number of berths in the problem.
"""
mutable struct ModelBuilder <: AbstractBollardModel
    ptr::Ptr{Cvoid}
    num_vessels::Int
    num_berths::Int

    """
        ModelBuilder(num_berths::Integer, num_vessels::Integer)

    Initialize a new optimization model builder with the specified dimensions.

    # Arguments
    - `num_berths`: The number of berths available in the problem. Must be non-negative.
    - `num_vessels`: The number of vessels to schedule. Must be non-negative.

    # Throws
    - `ArgumentError`: If `num_berths` or `num_vessels` is negative.
    - `ErrorException`: If the underlying Rust library fails to allocate memory.
    """
    function ModelBuilder(num_berths::Integer, num_vessels::Integer)
        num_berths < 0 && throw(ArgumentError("number of berths must be non-negative"))
        num_vessels < 0 && throw(ArgumentError("number of vessels must be non-negative"))

        pointer = ccall((:bollard_model_builder_new, libbollard_ffi), Ptr{Cvoid},
            (Csize_t, Csize_t), num_berths, num_vessels)

        pointer == C_NULL && error("failed to allocate ModelBuilder in Rust backend")

        instance = new(pointer, Int(num_vessels), Int(num_berths))

        finalizer(instance) do obj
            ptr_to_free = obj.ptr
            obj.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_model_builder_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return instance
    end
end

"""
    Model <: AbstractBollardModel

An immutable, compiled optimization model ready for solving.
Created by calling `build()` on a `ModelBuilder`.

# Fields
- `ptr::Ptr{Cvoid}`: Pointer to the underlying Rust `Model` instance.
- `num_vessels::Int`: Total number of vessels.
- `num_berths::Int`: Total number of berths.
"""
mutable struct Model <: AbstractBollardModel
    ptr::Ptr{Cvoid}
    num_vessels::Int
    num_berths::Int

    """
        Model(builder::ModelBuilder)

    Compile a `ModelBuilder` into a `Model`. This process **consumes** the builder.
    Once built, the `builder` is invalidated and cannot be used again.

    # Arguments
    - `builder`: The builder instance containing the problem configuration.

    # Throws
    - `ErrorException`: If the builder is already invalidated (built previously) or if the Rust build fails.
    """
    function Model(builder::ModelBuilder)
        builder.ptr == C_NULL && error("cannot build from an invalidated or already built ModelBuilder")

        pointer = ccall((:bollard_model_builder_build, libbollard_ffi), Ptr{Cvoid}, (Ptr{Cvoid},), builder.ptr)
        pointer == C_NULL && error("Rust build operation returned a null pointer")

        builder.ptr = C_NULL

        instance = new(pointer, builder.num_vessels, builder.num_berths)

        finalizer(instance) do obj
            ptr_to_free = obj.ptr
            obj.ptr = C_NULL
            if ptr_to_free != C_NULL
                ccall((:bollard_model_free, libbollard_ffi), Cvoid, (Ptr{Cvoid},), ptr_to_free)
            end
        end
        return instance
    end
end

# =========================================================================
# ModelBuilder Properties (Setters)
# =========================================================================

"""
    Base.propertynames(::ModelBuilder)

Return the list of properties (methods) available on a `ModelBuilder` instance.
These acts as the public API for configuring the model.
"""
function Base.propertynames(::ModelBuilder)
    return (:add_closing_time!, :add_opening_time!, :set_arrival_time!,
        :set_latest_departure_time!, :set_processing_time!, :forbid_assignment!, :set_weight!, :build)
end

"""
    Base.getproperty(m::ModelBuilder, s::Symbol)

Dispatch for `ModelBuilder` configuration methods. Returns a function closure
that wraps the corresponding Rust FFI call.
"""
function Base.getproperty(m::ModelBuilder, s::Symbol)
    # --- Processing Time ---
    if s === :set_processing_time!
        """
            set_processing_time!(vessel_idx::Integer, berth_idx::Integer, duration::Int64)

        Set the time required to process a specific vessel at a specific berth.
        """
        return (vessel_idx, berth_idx, duration) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            ccall((:bollard_model_builder_set_processing_time, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, Csize_t, Int64),
                m.ptr, vessel_idx - 1, berth_idx - 1, duration)
            return m
        end

        # --- Forbid Assignment ---
    elseif s === :forbid_assignment!
        """
            forbid_assignment!(vessel_idx::Integer, berth_idx::Integer)

        Explicitly forbid a specific vessel from being serviced at a specific berth.
        Effectively sets the processing time to "infinity" (None).
        """
        return (vessel_idx, berth_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            ccall((:bollard_model_builder_forbid_vessel_berth_assignment, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, Csize_t),
                m.ptr, vessel_idx - 1, berth_idx - 1)
            return m
        end

        # --- Closing Time ---
    elseif s === :add_closing_time!
        """
            add_closing_time!(berth_idx::Integer, start_time::Int64, stop_time::Int64)

        Add a "closed" interval to a berth (e.g., maintenance). The berth is unavailable during `[start, end)`.
        """
        return (berth_idx, start_time, stop_time) -> begin
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))
            interval = FfiOpenClosedInterval(start_time, stop_time)
            ccall((:bollard_model_builder_add_closing_time, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, FfiOpenClosedInterval), m.ptr, berth_idx - 1, interval)
            return m
        end

        # --- Opening Time ---
    elseif s === :add_opening_time!
        """
            add_opening_time!(berth_idx::Integer, start_time::Int64, stop_time::Int64)

        Add an "open" interval to a berth. The berth is available for servicing vessels during `[start, end)`.
        """
        return (berth_idx, start_time, stop_time) -> begin
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))
            interval = FfiOpenClosedInterval(start_time, stop_time)
            ccall((:bollard_model_builder_add_opening_time, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, FfiOpenClosedInterval), m.ptr, berth_idx - 1, interval)
            return m
        end

        # --- Arrival Time ---
    elseif s === :set_arrival_time!
        """
            set_arrival_time!(vessel_idx::Integer, timestamp::Int64)

        Set the earliest possible arrival time for a vessel.
        """
        return (vessel_idx, timestamp) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            ccall((:bollard_model_builder_set_arrival_time, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, Int64), m.ptr, vessel_idx - 1, timestamp)
            return m
        end

        # --- Departure Time ---
    elseif s === :set_latest_departure_time!
        """
            set_latest_departure_time!(vessel_idx::Integer, timestamp::Int64)

        Set the deadline by which the vessel must complete service.
        """
        return (vessel_idx, timestamp) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            ccall((:bollard_model_builder_set_latest_departure_time, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, Int64), m.ptr, vessel_idx - 1, timestamp)
            return m
        end

        # --- Vessel Weight ---
    elseif s === :set_weight!
        """
            set_weight!(vessel_idx::Integer, weight_val::Int64)

        Set the objective function weight (priority) for a vessel. Must be non-negative.
        """
        return (vessel_idx, weight_val) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            weight_val < 0 && throw(ArgumentError("objective weights must be non-negative"))
            ccall((:bollard_model_builder_set_vessel_weight, libbollard_ffi), Cvoid,
                (Ptr{Cvoid}, Csize_t, Int64), m.ptr, vessel_idx - 1, weight_val)
            return m
        end

        # --- Build Command ---
    elseif s === :build
        """
            build() -> Model

        Finalize the builder and return a compiled `Model` ready for solving.
        """
        return () -> Model(m)
    else
        return getfield(m, s)
    end
end

# =========================================================================
# Model Properties (Getters)
# =========================================================================

"""
    Base.propertynames(::Model)

Return the list of properties (methods) available on a compiled `Model` instance.
"""
function Base.propertynames(::Model)
    return (:get_weight, :get_processing_time, :get_arrival_time,
        :get_latest_departure_time, :get_opening_intervals, :get_closing_intervals,
        :log_complexity, :num_vessels, :num_berths, :is_allowed, :is_forbidden)
end

"""
    Base.getproperty(m::Model, s::Symbol)

Dispatch for `Model` query methods. Returns a function closure that wraps
the corresponding Rust FFI call.
"""
function Base.getproperty(m::Model, s::Symbol)
    # --- Get Processing Time ---
    if s === :get_processing_time
        """
            get_processing_time(vessel_idx::Integer, berth_idx::Integer) -> Int64

        Get the configured processing time. Returns `-1` if the vessel cannot assign to this berth.
        """
        return (vessel_idx, berth_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            ccall((:bollard_model_processing_time, libbollard_ffi), Int64,
                (Ptr{Cvoid}, Csize_t, Csize_t),
                m.ptr, vessel_idx - 1, berth_idx - 1)
        end

        # --- Get Vessel Weight ---
    elseif s === :get_weight
        """
            get_weight(vessel_idx::Integer) -> Int64

        Get the weight assigned to a vessel.
        """
        return (vessel_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            ccall((:bollard_model_vessel_weight, libbollard_ffi), Int64,
                (Ptr{Cvoid}, Csize_t), m.ptr, vessel_idx - 1)
        end

        # --- Get Arrival Time ---
    elseif s === :get_arrival_time
        """
            get_arrival_time(vessel_idx::Integer) -> Int64

        Get the earliest arrival time for a vessel.
        """
        return (vessel_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            ccall((:bollard_model_vessel_arrival_time, libbollard_ffi), Int64,
                (Ptr{Cvoid}, Csize_t), m.ptr, vessel_idx - 1)
        end

        # --- Get Latest Departure Time ---
    elseif s === :get_latest_departure_time
        """
            get_latest_departure_time(vessel_idx::Integer) -> Int64

        Get the latest allowed departure time for a vessel.
        """
        return (vessel_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            ccall((:bollard_model_vessel_latest_departure_time, libbollard_ffi), Int64,
                (Ptr{Cvoid}, Csize_t), m.ptr, vessel_idx - 1)
        end

        # --- Get Opening Intervals ---
    elseif s === :get_opening_intervals
        """
            get_opening_intervals(berth_idx::Integer) -> Vector{FfiOpenClosedInterval}

        Retrieve the list of available (open) time windows for a specific berth.
        """
        return (berth_idx) -> begin
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            count = ccall((:bollard_model_num_berth_opening_times, libbollard_ffi), Csize_t,
                (Ptr{Cvoid}, Csize_t), m.ptr, berth_idx - 1)

            intervals = Vector{FfiOpenClosedInterval}(undef, count)
            for i in 1:count
                # C indices are 0-based
                intervals[i] = ccall((:bollard_model_berth_opening_time, libbollard_ffi), FfiOpenClosedInterval,
                    (Ptr{Cvoid}, Csize_t, Csize_t), m.ptr, berth_idx - 1, i - 1)
            end
            return intervals
        end

        # --- Get Closing Intervals ---
    elseif s === :get_closing_intervals
        """
            get_closing_intervals(berth_idx::Integer) -> Vector{FfiOpenClosedInterval}

        Retrieve the list of unavailable (closed/maintenance) time windows for a specific berth.
        """
        return (berth_idx) -> begin
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            count = ccall((:bollard_model_num_berth_closing_times, libbollard_ffi), Csize_t,
                (Ptr{Cvoid}, Csize_t), m.ptr, berth_idx - 1)

            intervals = Vector{FfiOpenClosedInterval}(undef, count)
            for i in 1:count
                # C indices are 0-based
                intervals[i] = ccall((:bollard_model_berth_closing_time, libbollard_ffi), FfiOpenClosedInterval,
                    (Ptr{Cvoid}, Csize_t, Csize_t), m.ptr, berth_idx - 1, i - 1)
            end
            return intervals
        end

        # --- Is Allowed (Forbidden check) ---
    elseif s === :is_allowed
        """
            is_allowed(vessel_idx::Integer, berth_idx::Integer) -> Bool

        Check if a specific vessel is allowed to be assigned to a specific berth. 
        Returns `true` if allowed, `false` if forbidden.
        """
        return (vessel_idx, berth_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            ccall((:bollard_model_vessel_allowed_on_berth, libbollard_ffi), Bool,
                (Ptr{Cvoid}, Csize_t, Csize_t),
                m.ptr, vessel_idx - 1, berth_idx - 1)
        end

        # --- Is Forbidden (Allowed check) ---
    elseif s === :is_forbidden
        """
            is_forbidden(vessel_idx::Integer, berth_idx::Integer) -> Bool

        Check if a specific vessel is forbidden from being assigned to a specific berth.
        Returns `true` if forbidden, `false` if allowed.
        """
        return (vessel_idx, berth_idx) -> begin
            @boundscheck 1 <= vessel_idx <= m.num_vessels || throw(BoundsError(m, vessel_idx))
            @boundscheck 1 <= berth_idx <= m.num_berths || throw(BoundsError(m, berth_idx))

            !ccall((:bollard_model_vessel_allowed_on_berth, libbollard_ffi), Bool,
                (Ptr{Cvoid}, Csize_t, Csize_t),
                m.ptr, vessel_idx - 1, berth_idx - 1)
        end

        # --- Complexity Metric ---
    elseif s === :log_complexity
        """
            log_complexity() -> Float64

        Return the base-10 logarithm of the model's estimated complexity.
        Used for heuristics to estimate solution difficulty.
        """
        return () -> ccall((:bollard_model_model_log_complexity, libbollard_ffi), Float64, (Ptr{Cvoid},), m.ptr)

    else
        return getfield(m, s)
    end
end

# =========================================================================
# Base Utilities
# =========================================================================

"""
    Base.size(m::AbstractBollardModel) -> (Int, Int)

Return the dimensions of the model as `(num_vessels, num_berths)`.
"""
Base.size(m::AbstractBollardModel) = (m.num_vessels, m.num_berths)

"""
    Base.length(m::AbstractBollardModel) -> Int

Return the primary dimension of the model, which is the number of vessels.
"""
Base.length(m::AbstractBollardModel) = m.num_vessels

"""
    Base.show(io::IO, m::ModelBuilder)

Print a summary of the ModelBuilder state.
"""
function Base.show(io::IO, m::ModelBuilder)
    print(io, "Bollard.ModelBuilder(vessels=$(m.num_vessels), berths=$(m.num_berths)) [Configuring]")
end

"""
    Base.show(io::IO, m::Model)

Print a summary of the compiled Model.
"""
function Base.show(io::IO, m::Model)
    print(io, "Bollard.Model(vessels=$(m.num_vessels), berths=$(m.num_berths)) [Optimized]")
end