# # Анализ влияния миграции на динамику эпидемии SIR

# **Цель исследования:** Определить, как интенсивность миграции между городами
# влияет на время достижения пика эпидемии и пиковую заболеваемость.

# **Метод:** Параметрическое сканирование с усреднением по случайным сидам.
# Модель включает три города с возможностью миграции агентов между ними.

# ## 1. Подготовка окружения

using DrWatson
@quickactivate "project"
using Agents, DataFrames, Plots, CSV, Random

include(srcdir("sir_model.jl"))

# ## 2. Функция создания матрицы миграции
# 
# Функция `create_migration_matrix` создаёт квадратную матрицу вероятностей
# перехода между городами.
# 
# Аргументы:
# - `C` — количество городов (размерность матрицы)
# - `intensity` — интенсивность миграции (вероятность переехать в другой город)
# 
# Принцип работы:
# - Вероятность остаться в своём городе = 1 - intensity
# - Вероятность переехать в конкретный другой город = intensity / (C-1)
# - Сумма вероятностей по строке = 1

function create_migration_matrix(C, intensity)
    M = ones(C, C) .* intensity ./ (C-1)
    for i = 1:C
        M[i, i] = 1 - intensity
    end
    return M
end

# ## 3. Функция измерения времени достижения пика
# 
# Функция `peak_time` запускает симуляцию эпидемии и отслеживает,
# на каком шаге достигается максимальная доля инфицированных.
# 
# Входной словарь `p` содержит:
# - `:C` — количество городов
# - `:migration_intensity` — интенсивность миграции
# - `:Ns` — численность населения по городам
# - `:β_und` — заразность невыявленных по городам
# - `:β_det` — заразность выявленных по городам
# - `:infection_period` — длительность болезни в днях
# - `:detection_time` — время до выявления в днях
# - `:death_rate` — вероятность летального исхода
# - `:reinfection_probability` — вероятность повторного заражения
# - `:Is` — начальное количество заражённых по городам
# - `:seed` — зерно для генератора случайных чисел
# - `:n_steps` — количество шагов симуляции
# 
# Возвращает:
# - `peak_time` — номер шага, на котором достигнут пик
# - `peak_value` — максимальная доля инфицированных

function peak_time(p)
    migration_rates = create_migration_matrix(p[:C], p[:migration_intensity])
    model = initialize_sir(;
        Ns = p[:Ns],
        β_und = p[:β_und],
        β_det = p[:β_det],
        infection_period = p[:infection_period],
        detection_time = p[:detection_time],
        death_rate = p[:death_rate],
        reinfection_probability = p[:reinfection_probability],
        Is = p[:Is],
        seed = p[:seed],
        migration_rates = migration_rates,
    )

    infected_frac(model) = count(a.status == :I for a in allagents(model)) / nagents(model)
    peak = 0.0
    peak_step = 0

    for step = 1:p[:n_steps]
        agent_ids = collect(allids(model))
        for id in agent_ids
            agent = try
                model[id]
            catch
                nothing
            end
            if agent !== nothing
                sir_agent_step!(agent, model)
            end
        end

        frac = infected_frac(model)
        if frac > peak
            peak = frac
            peak_step = step
        end
    end

    return (peak_time = peak_step, peak_value = peak)
end

# ## 4. Планирование эксперимента
# 
# Исследуем интенсивность миграции от 0.0 до 0.5 с шагом 0.1.
# Для каждого значения выполняем 3 прогона с разными seed'ами.
# 
# Начальные условия: первый город имеет 1 заражённого,
# остальные города полностью здоровы.

migration_intensities = 0.0:0.1:0.5
seeds = [42, 43, 44]

params_list = []
for mig in migration_intensities
    for s in seeds
        push!(
            params_list,
            Dict(
                :migration_intensity => mig,
                :C => 3,
                :Ns => [1000, 1000, 1000],
                :β_und => [0.5, 0.5, 0.5],
                :β_det => [0.05, 0.05, 0.05],
                :infection_period => 14,
                :detection_time => 7,
                :death_rate => 0.02,
                :reinfection_probability => 0.1,
                :Is => [1, 0, 0],
                :seed => s,
                :n_steps => 150,
            ),
        )
    end
end

# ## 5. Запуск экспериментов

results = []
for params in params_list
    data = peak_time(params)
    push!(results, merge(params, Dict(pairs(data))))
    println(
        "Завершён эксперимент с migration_intensity = $(params[:migration_intensity]), seed = $(params[:seed])",
    )
end

# ## 6. Сохранение сырых данных

df = DataFrame(results)
CSV.write(datadir("migration_scan_all.csv"), df)

# ## 7. Агрегация и статистическая обработка

using Statistics
grouped = combine(
    groupby(df, [:migration_intensity]),
    :peak_time => mean => :mean_peak_time,
    :peak_value => mean => :mean_peak_value,
)

# ## 8. Визуализация результатов
# 
# Ожидаемый результат:
# - С ростом миграции время до пика увеличивается (эпидемия растягивается)
# - Пиковая заболеваемость снижается (инфекция распределяется по городам)
# 
# Левая ось Y — время до пика в днях (кружки)
# Правая ось Y — численность больных в пике (квадраты, умноженная на 3000)

plot(
    grouped.migration_intensity,
    grouped.mean_peak_time,
    marker = :circle,
    xlabel = "Интенсивность миграции",
    ylabel = "Время до пика (дни)",
    label = "Время пика",
)
plot!(
    grouped.migration_intensity,
    grouped.mean_peak_value .* 3000,
    marker = :square,
    xlabel = "Интенсивность миграции",
    ylabel = "Численность в пике",
    label = "Пиковая заболеваемость",
)
savefig(plotsdir("migration_effect.png"))

# ## 9. Завершение

println("Результаты сохранены в data/migration_scan_all.csv и plots/migration_effect.png")
