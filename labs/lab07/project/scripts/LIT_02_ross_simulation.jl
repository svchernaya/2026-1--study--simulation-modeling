# # Модель Росса (резервирование с ремонтом)
#
# **Авторы:** А. В. Королькова, PhD, Кулябов Д. С., DSc
#
# **Принадлежность:** Российский университет дружбы народов
#
# ## Назначение скрипта
#
# Данный скрипт реализует дискретно-событийную симуляцию модели Росса —
# системы массового обслуживания с конечной популяцией, резервом и ремонтом.
#
# ### Что делает скрипт
#
# 1. Моделирует работу N идентичных машин, которые постоянно работают
#
# 2. S машин находятся в резерве и готовы заменить отказавшие
#
# 3. R ремонтников обслуживают сломавшиеся машины
#
# 4. При исчерпании резерва система падает (крах)
#
# 5. Проводится параметрическое сканирование для разных S и числа ремонтников
#
# 6. Строятся графики зависимости времени до краха от параметров
#
# 7. Выполняется сравнение с аналитическим решением
#
# ### Постановка задачи
#
# | Элемент | Описание |
# |---------|----------|
# | N | Количество постоянно работающих машин |
# | S | Количество резервных машин |
# | Ремонтники | Обслуживают сломавшиеся машины (1 или 2) |
# | Отказ | Наработка до отказа ~ Exp(λ) |
# | Ремонт | Время ремонта ~ Exp(μ) |
# | Крах | Наступает, когда нет резервной машины для замены |
#
# ## Параметры модели
#
# | Параметр | Значение | Описание |
# |----------|----------|----------|
# | N | 10 | Основные машины |
# | S_values | [0, 1, 2, 3] | Резервные машины (сканирование) |
# | repair_values | [1, 2] | Количество ремонтников |
# | λ (LAMBDA) | 100 | Среднее время до отказа (часы) |
# | μ (MU) | 1 | Среднее время ремонта (часы) |
# | RUNS | 2 | Количество прогонов для статистики |
#
# ## Выходные данные
#
# | Файл | Описание |
# |------|----------|
# | `data/ross/results.csv` | Результаты всех прогонов (S, ремонтники, время краха) |
# | `plots/ross_crash_time.png` | Зависимость времени до краха от S (лог. шкала) |
# | `plots/ross_compare.png` | Сравнение симуляции с аналитикой |
#
# ## Теоретическое обоснование
#
# Система описывается марковским процессом с непрерывным временем.
# Состояние определяется числом исправных машин i (работающие + резерв).
#
# ### Интенсивности переходов
#
# - Отказ: i → i-1 с интенсивностью min(N, i) / λ
# - Ремонт: i → i+1 с интенсивностью μ (если есть очередь на ремонт)
#
# ### Аналитическая формула
#
# Среднее время до краха для одного ремонтника:
#
# E[T] = (S + 1) × (λ/N + 1/μ)
#
# ### Условие краха
#
# Крах наступает при переходе из состояния i = N в i = N-1,
# когда нет резервных машин для замены отказавшей.
#
# ## Инициализация проекта DrWatson

using DrWatson
@quickactivate "project"

# ## Загрузка необходимых пакетов

using ResumableFunctions
using ConcurrentSim
using Distributions
using Random
using StableRNGs
using DataFrames, CSV, Plots

# ## Константы модели

const N = 10
const RUNS = 2
const S_values = [0, 1, 2, 3]
const repair_values = [1, 2]
const LAMBDA = 100
const MU = 1

# ## Хранилище для истории состояния

history_records = []

# ## Поведение одной машины
#
# Каждая машина работает в бесконечном цикле:
# 1. Работает до отказа (timeout с экспоненциальным распределением)
# 2. Пытается взять резервную машину из spares
# 3. Если резерва нет → StopSimulation (крах системы)
# 4. Если резерв есть → сломанная машина идёт в ремонт
# 5. После ремонта возвращается в резерв

@resumable function machine(
    env::Environment,
    repair_facility::Resource,
    spares::Store{Process},
)
    while true
        try
            @yield timeout(env, Inf)
        catch
        end
        @yield timeout(env, rand(Exponential(LAMBDA)))
        get_spare = take!(spares)
        @yield get_spare | timeout(env)
        if state(get_spare) != ConcurrentSim.idle
            @yield interrupt(value(get_spare))
        else
            throw(StopSimulation("No more spares!"))
        end
        @yield request(repair_facility)
        @yield timeout(env, rand(Exponential(MU)))
        @yield unlock(repair_facility)
        @yield put!(spares, active_process(env))
        
        busy_repair = repair_facility.level
        queue_len = length(repair_facility.get_queue)
        push!(history_records, (time=now(env), 
                                operational=length(spares.items) + N,
                                in_repair=busy_repair,
                                repair_queue=queue_len))
    end
end

# ## Инициализация симуляции
#
# Создаёт N работающих машин и S резервных.

@resumable function start_sim(
    env::Environment,
    repair_facility::Resource,
    spares::Store{Process},
    S_local::Int,
)
    for i = 1:N
        proc = @process machine(env, repair_facility, spares)
        @yield interrupt(proc)
    end
    for i = 1:S_local
        proc = @process machine(env, repair_facility, spares)
        @yield put!(spares, proc)
    end
end

# ## Запуск одного эксперимента
#
# Возвращает время до краха и DataFrame с историей состояния.

function sim_repair(S_local::Int, num_repair::Int)
    global history_records
    history_records = []
    
    sim = Simulation()
    repair_facility = Resource(sim, num_repair)
    spares = Store{Process}(sim)
    @process start_sim(sim, repair_facility, spares, S_local)
    
    try
        run(sim)
    catch e
        if !isa(e, StopSimulation)
            rethrow()
        end
    end
    
    stop_time = now(sim)
    return stop_time, DataFrame(history_records)
end

# ## Параметрическое сканирование
#
# Перебираем все комбинации S (резерв) и числа ремонтников.
# Для каждой комбинации выполняем RUNS прогонов.

all_results = []

for S in S_values
    for num_repair in repair_values
        println("S=$S, ремонтников=$num_repair")
        times = []
        
        for run_num in 1:RUNS
            crash_time, history = sim_repair(S, num_repair)
            push!(times, crash_time)
            
            if S == 3 && num_repair == 1 && run_num == 1
                global history_1rep = history
            end
            if S == 3 && num_repair == 2 && run_num == 1
                global history_2rep = history
            end
        end
        
        avg_time = sum(times) / length(times)
        push!(all_results, (S=S, repair_servers=num_repair, 
                           avg_crash_time=avg_time, std_crash_time=std(times)))
    end
end

# ## Сохранение результатов

df_results = DataFrame(all_results)
mkpath(datadir("ross"))
CSV.write(datadir("ross", "results.csv"), df_results)

# ## График 1: Зависимость времени до краха от S
#
# Используется логарифмическая шкала по оси Y, так как значения
# меняются на несколько порядков (от 1 до 25000 часов).

p1 = plot(xlabel="S (резервные машины)", ylabel="Среднее время до краха (часы)", legend=:topleft, yscale=:log10)
colors = [:red, :blue, :green]
for (idx, r) in enumerate(repair_values)
    sub = filter(row -> row.repair_servers == r, df_results)
    plot!(sub.S, sub.avg_crash_time, marker=:circle, linewidth=2,
          label="$r ремонтник(а)", color=colors[idx])
end
savefig(plotsdir("ross_crash_time.png"))

# ## Аналитическое решение
#
# Приближённая формула для среднего времени до краха
# при одном ремонтнике.

function analytic_crash_time(N, S, λ, μ)
    return (S + 1) * (λ / N + 1/μ)
end

# ## График 2: Сравнение симуляции с аналитикой

df_1rep = filter(row -> row.repair_servers == 1, df_results)
analytic_vals = [analytic_crash_time(N, S, LAMBDA, MU) for S in df_1rep.S]

p4 = plot(df_1rep.S, df_1rep.avg_crash_time,
          marker=:circle, label="Симуляция")
plot!(df_1rep.S, analytic_vals, linestyle=:dash, label="Аналитика")
savefig(plotsdir("ross_compare.png"))

# ## Завершение работы

println("Готово! Результаты в data/ross/ и plots/")
