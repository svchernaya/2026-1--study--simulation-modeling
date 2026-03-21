# # Моделирование мира маргариток: динамика при изменяющейся солнечной активности
#
# **Цель:** Исследовать динамику численности черных и белых маргариток, а также
# изменение температуры планеты при сценарии :ramp (изменяющаяся солнечная светимость).

# ## Инициализация проекта
using DrWatson
@quickactivate "project"
using Agents
using DataFrames
using Plots

# ## Подключение модуля с моделью
include(srcdir("daisyworld.jl"))

using CairoMakie
using StatsBase

# ## Определение агрегирующих функций
black(a) = a.breed == :black
white(a) = a.breed == :white
adata = [(black, count), (white, count)]

# ## Инициализация модели со сценарием :ramp
model = daisyworld(solar_luminosity=1.0, scenario=:ramp)

# ## Определение метаданных
temperature(model) = StatsBase.mean(model.temperature)
mdata = [temperature, :solar_luminosity]

# ## Запуск симуляции
agent_df, model_df = run!(model, 1000; adata=adata, mdata=mdata)

# ## Визуализация
figure = CairoMakie.Figure(size=(600, 600))

# График численности
ax1 = figure[1, 1] = Axis(figure, ylabel="daisy count")
blackl = lines!(ax1, agent_df[!, :time], agent_df[!, :count_black], color=:red)
whitel = lines!(ax1, agent_df[!, :time], agent_df[!, :count_white], color=:blue)
figure[1, 2] = Legend(figure, [blackl, whitel], ["black", "white"])

# График температуры
ax2 = figure[2, 1] = Axis(figure, ylabel="temperature")
# График светимости
ax3 = figure[3, 1] = Axis(figure, xlabel="tick", ylabel="luminosity")

lines!(ax2, model_df[!, :time], model_df[!, :temperature], color=:red)
lines!(ax3, model_df[!, :time], model_df[!, :solar_luminosity], color=:red)

for ax in (ax1, ax2); ax.xticklabelsvisible = false; end
figure

save(plotsdir("daisy_luminosity.png"), figure)
