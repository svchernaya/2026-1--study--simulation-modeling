#!/usr/bin/env julia
# add_packages.jl
using Pkg
Pkg.activate(".")

packages = [
    "DrWatson", "DifferentialEquations", "Plots", "DataFrames", 
    "CSV", "JLD2", "Literate", "IJulia", "BenchmarkTools", 
    "Quarto", "StatsPlots", "LaTeXStrings", "FFTW"
]

println("Установка пакетов...")
Pkg.add(packages)
println("\nВсе пакеты установлены!")

