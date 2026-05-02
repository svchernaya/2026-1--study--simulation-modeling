using DrWatson
@quickactivate "project"

include(srcdir("SIRPetri.jl"))
using .SIRPetri
using DataFrames, CSV, Plots

using Plots

β = 0.3
γ = 0.1
tmax = 100.0

net, u0, states = build_sir_network(β, γ)

df = simulate_deterministic(net, u0, (0.0, tmax), saveat = 0.2, rates = [β, γ])

anim = @animate for i in 1:size(df, 1)
    title_time = round(df.time[i], digits = 1)

    bar(
        ["S", "I", "R"],
        [df.S[i], df.I[i], df.R[i]],
        title = "SIR Model at t = $title_time",
        ylabel = "Population",
        ylims = (0, 1000),
        color = [:blue :red :green],
        legend = false,
        bar_width = 0.6
    )
end

gif(anim, plotsdir("sir_animation.gif"), fps = 10)

println("Анимация сохранена в plots/sir_animation.gif")
