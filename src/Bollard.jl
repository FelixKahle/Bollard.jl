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

"""
    Bollard

Julia interface to the Bollard optimization engine, a research project for modeling and 
solving the Berth Allocation Problem (BAP), a classical NP-hard problem in maritime logistics.

The Berth Allocation Problem involves assigning vessels to berth positions over time, taking 
into account:
- Vessel arrival windows and latest departure times
- Berth availability via opening/closing intervals
- Processing times per vessel and berth
- Optional vessel weights/priorities

This package wraps a high-performance Rust backend via `Bollard_jll`, combining Julia's ease 
of use with Rust's speed for computational efficiency.
"""
module Bollard

import Base: show, size, length, getproperty, propertynames

using Artifacts
using Libdl

export ModelBuilder, Model, FfiOpenClosedInterval
export BnbSolver, BnbSolverOutcome, FixedAssignment
export BnbSolverStatus, BnbTerminationReason
export solve

global libbollard_ffi = ""

function __init__()
    if haskey(ENV, "BOLLARD_FFI_LIB")
        build_dir = ENV["BOLLARD_FFI_LIB"]

        file_name = if Sys.iswindows()
            "bollard_ffi.dll"
        else
            "libbollard_ffi.$(Libdl.dlext)"
        end

        global libbollard_ffi = joinpath(build_dir, file_name)
    else
        root = artifact"bollard_ffi"

        global libbollard_ffi = if Sys.iswindows()
            joinpath(root, "bin", "bollard_ffi.dll")
        else
            joinpath(root, "lib", "libbollard_ffi.$(Libdl.dlext)")
        end
    end

    if !isfile(libbollard_ffi)
        error("Bollard library not found at: $libbollard_ffi\n(Override active: $(haskey(ENV, "BOLLARD_FFI_LIB")))")
    end
end

include("model.jl")
include("bnb.jl")

end # module Bollard