# Bollard.jl

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE.txt)
[![Julia 1.11+](https://img.shields.io/badge/Julia-1.11%2B-purple.svg)](https://julialang.org)

---

## 🚢 Overview

`Bollard.jl` is a Julia interface to the Bollard optimization engine, a research project for modeling and solving the Berth Allocation Problem (BAP), a classical NP-hard problem in maritime logistics. It provides high-level Julia types and functions to represent vessels, berths, time windows, and processing durations, enabling experimentation with Branch-and-Bound algorithms and other optimization techniques.

The package wraps a high-performance Rust backend via `Bollard_jll`, combining Julia's ease of use with Rust's speed for computational efficiency.

---

## Problem Description

The Berth Allocation Problem involves assigning vessels to berth positions over time, taking into account:

- Vessel arrival windows and latest departure times
- Berth availability via opening/closing intervals
- Processing times per vessel and berth
- Optional vessel weights/priorities

Solving this efficiently reduces congestion and improves throughput at container terminals.

---

## Features

- **Model Building**: Define optimization problems using the `ModelBuilder` API
- **Branch-and-Bound Solver**: Solve BAP instances with the `BnbSolver`
- **Fixed Assignments**: Support for hard constraints on vessel-berth-time assignments
- **FFI Integration**: Seamless integration with high-performance Rust backend via `Bollard_jll`

---

## Installation

```julia
using Pkg
Pkg.add("https://github.com/FelixKahle/Bollard.jl.git")