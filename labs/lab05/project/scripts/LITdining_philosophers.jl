# # Симуляция задачи "Обедающие философы" с помощью сетей Петри

# В этом скрипте мы моделируем классическую задачу синхронизации
# "Обедающие философы" с использованием сетей Петри.
# Сравниваются две модели: классическая (которая приводит к deadlock)
# и модифицированная с арбитром (которая предотвращает deadlock).

# ## Подготовка окружения

# Подключаем DrWatson для управления проектом и активируем его.
using DrWatson
@quickactivate "project"

# Подключаем наш модуль с реализацией сетей Петри для философов.
include(srcdir("DiningPhilosophers.jl"))
using .DiningPhilosophers

# Подключаем библиотеки для работы с таблицами, CSV, графиками и случайностью.
using DataFrames, CSV, Plots, Random

# ## Параметры симуляции

# Количество философов — 5.
N = 5

# Максимальное время симуляции — 50 единиц.
tmax = 50.0

# ## Классическая сеть (без арбитра)

println("=== Классическая сеть (без арбитра) ===")

# Строим классическую сеть Петри для N философов.
net_classic, u0_classic, _ = build_classical_network(N)

# Фиксируем seed для воспроизводимости результатов.
Random.seed!(456)

# Запускаем стохастическую симуляцию (алгоритм Гиллеспи).
df_classic = simulate_stochastic(net_classic, u0_classic, tmax)

# Сохраняем результаты в CSV-файл.
CSV.write(datadir("dining_classic.csv"), df_classic)

# Проверяем, наступил ли deadlock.
dead = detect_deadlock(df_classic, net_classic)
println("Deadlock обнаружен: $dead")

# Строим графики эволюции маркировки.
plot_classic = plot_marking_evolution(df_classic, N)

# Сохраняем графики в файл.
savefig(plotsdir("classic_simulation.png"))

# ## Сеть с арбитром

println("\n=== Сеть с арбитром ===")

# Строим модифицированную сеть с арбитром.
net_arb, u0_arb, _ = build_arbiter_network(N)

# Запускаем стохастическую симуляцию.
df_arb = simulate_stochastic(net_arb, u0_arb, tmax)

# Сохраняем результаты.
CSV.write(datadir("dining_arbiter.csv"), df_arb)

# Проверяем deadlock — в сети с арбитром его быть не должно.
dead_arb = detect_deadlock(df_arb, net_arb)
println("Deadlock обнаружен: $dead_arb")

# Строим и сохраняем графики.
plot_arb = plot_marking_evolution(df_arb, N)
savefig(plotsdir("arbiter_simulation.png"))
