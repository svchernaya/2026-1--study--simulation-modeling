# # Многокритериальная оптимизация параметров модели SIR

# **Цель исследования:** Найти оптимальные параметры управления эпидемией,
# позволяющие одновременно минимизировать два ключевых показателя:
# - пиковую заболеваемость (нагрузка на систему здравоохранения)
# - долю умерших (летальность)

# **Метод:** Многокритериальная эволюционная оптимизация Borg MOEA.
# Оптимизатор ищет Парето-оптимальные компромиссы между двумя целями.

# ## 1. Подготовка окружения

using DrWatson
@quickactivate "project"

using BlackBoxOptim, Random, Statistics

include(srcdir("sir_model.jl"))

# ## 2. Целевая функция для оптимизации
# 
# Функция `cost_multi` оценивает качество набора параметров путём
# запуска нескольких симуляций и усреднения результатов.
# 
# Входной вектор `x` содержит три оптимизируемых параметра:
# - `x[1]` — β_und (заразность невыявленных больных)
# - `x[2]` — detection_time (время до выявления заболевания в днях)
# - `x[3]` — death_rate (вероятность летального исхода)
# 
# Возвращает кортеж из двух значений, которые нужно минимизировать:
# - средний пик заболеваемости (доля инфицированных)
# - средняя доля умерших (от общей численности популяции)
# 
# Для статистической устойчивости выполняется 5 повторов с разными seed'ами.

function cost_multi(x)
    model = initialize_sir(;
        Ns = [1000, 1000, 1000],
        β_und = fill(x[1], 3),
        β_det = fill(x[1]/10, 3),
        infection_period = 14,
        detection_time = round(Int, x[2]),
        death_rate = x[3],
        reinfection_probability = 0.1,
        Is = [0, 0, 1],
        seed = 42,
        n_steps = 100,
    )

    infected_frac(model) = count(a.status == :I for a in allagents(model)) / nagents(model)
    dead_count(model) = 3000 - nagents(model)

    peak_infected = 0.0

    replicates = 5
    peak_vals = Float64[]
    dead_vals = Int[]

    for rep = 1:replicates
        model = initialize_sir(;
            Ns = [1000, 1000, 1000],
            β_und = fill(x[1], 3),
            β_det = fill(x[1]/10, 3),
            infection_period = 14,
            detection_time = round(Int, x[2]),
            death_rate = x[3],
            reinfection_probability = 0.1,
            Is = [0, 0, 1],
            seed = 42 + rep,
            n_steps = 100,
        )

        for step = 1:100
            Agents.step!(model, 1)
            frac = infected_frac(model)
            if frac > peak_infected
                peak_infected = frac
            end
        end

        push!(peak_vals, peak_infected)
        push!(dead_vals, dead_count(model))
    end

    return (mean(peak_vals), mean(dead_vals) / 3000)
end

# ## 3. Запуск многокритериальной оптимизации
# 
# Алгоритм `:borg_moea` (Multi-Objective Evolutionary Algorithm) ищет
# Парето-оптимальные решения, где нельзя улучшить один показатель
# без ухудшения другого.
# 
# **Поисковые диапазоны:**
# - β_und: от 0.1 до 1.0 (от низкой до высокой заразности)
# - detection_time: от 3 до 14 дней (от быстрого до медленного выявления)
# - death_rate: от 0.01 до 0.1 (от 1% до 10% летальности)
# 
# **Ограничения:**
# - MaxTime = 120 секунд (2 минуты на оптимизацию)
# - NumDimensions = 3 (три параметра)

result = bboptimize(
    cost_multi,
    Method = :borg_moea,
    FitnessScheme = ParetoFitnessScheme{2}(is_minimizing = true),
    SearchRange = [
        (0.1, 1.0),
        (3.0, 14.0),
        (0.01, 0.1),
    ],
    NumDimensions = 3,
    MaxTime = 120,
    TraceMode = :compact,
)

# ## 4. Извлечение и вывод результатов
# 
# `best_candidate` — оптимальный вектор параметров
# `best_fitness` — достигнутые значения (пик, смертность)

best = best_candidate(result)
fitness = best_fitness(result)

println("Оптимальные параметры:")
println("β_und = $(best[1])")
println("Время выявления = $(round(Int, best[2])) дней")
println("Смертность = $(best[3])")
println("Достигнутые показатели:")
println("Пик заболеваемости: $(fitness[1])")
println("Доля умерших: $(fitness[2])")

# ## 5. Сохранение результатов
# 
# Результаты оптимизации сохраняются в JLD2-файл для последующего анализа
# и визуализации Парето-фронта.

save(datadir("optimization_result.jld2"), Dict("best" => best, "fitness" => fitness))
