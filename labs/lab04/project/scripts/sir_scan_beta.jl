# # Анализ чувствительности модели SIR к коэффициенту заразности β
# 
# **Цель исследования:** Определить, как изменение базового коэффициента заразности β
# влияет на ключевые показатели эпидемии: пик заболеваемости, итоговую долю переболевших
# и количество смертей.
# 
# **Метод:** Параметрическое сканирование с усреднением по случайным сидам.

# ## 1. Подготовка окружения

using DrWatson
@quickactivate "project"

using Agents, DataFrames, Plots, CSV, Random

include(srcdir("sir_model.jl"))

# ## 2. Функция запуска одного эксперимента
# 
# Функция `run_experiment` выполняет одну симуляцию с заданными параметрами
# и возвращает метрики: peak, final_inf, final_rec, deaths.

function run_experiment(p)
    beta = p[:beta]                                                         # скалярный коэффициент заразности
    β_und = fill(beta, 3)                                                   # β для невыявленных (все города)
    β_det = fill(beta/10, 3)                                                # β для выявленных (в 10 раз ниже)
    
    model = initialize_sir(;                                                # создаём агентную модель
        Ns = p[:Ns],                                                        # численность населения по городам
        β_und = β_und,                                                      # заразность невыявленных
        β_det = β_det,                                                      # заразность выявленных
        infection_period = p[:infection_period],                            # длительность болезни (дней)
        detection_time = p[:detection_time],                                # время до выявления (дней)
        death_rate = p[:death_rate],                                        # вероятность смерти
        reinfection_probability = p[:reinfection_probability],              # вероятность повторного заражения
        Is = p[:Is],                                                        # начальные заражённые по городам
        seed = p[:seed],                                                    # seed для воспроизводимости
        n_steps = p[:n_steps],                                              # количество шагов симуляции
    )
    
    infected_fraction(model) = count(a.status == :I for a in allagents(model)) / nagents(model)  # доля больных
    
    peak_infected = 0.0                                                     # отслеживание пика
    
    for step = 1:p[:n_steps]                                               # основной цикл симуляции
        agent_ids = collect(allids(model))                                  # получаем всех агентов
        for id in agent_ids                                                 # обходим каждого агента
            agent = try                                                     # безопасное получение агента
                model[id]                                                   # (агент мог умереть)
            catch
                nothing
            end
            if agent !== nothing                                            # если агент существует
                sir_agent_step!(agent, model)                               # выполняем шаг модели
            end
        end
        
        frac = infected_fraction(model)                                     # текущая доля больных
        if frac > peak_infected                                             # обновляем пик если нужно
            peak_infected = frac
        end
    end
    
    final_infected = infected_fraction(model)                               # финальная доля больных
    final_recovered = count(a.status == :R for a in allagents(model)) / nagents(model)  # доля выздоровевших
    total_deaths = sum(p[:Ns]) - nagents(model)                             # общее число умерших
    
    return (
        peak = peak_infected,                                               # пик эпидемии (доля)
        final_inf = final_infected,                                         # конечная доля больных
        final_rec = final_recovered,                                        # доля выздоровевших
        deaths = total_deaths,                                              # абсолютное число смертей
    )
end

# ## 3. Планирование эксперимента
# 
# Исследуем значения β от 0.1 до 1.0 с шагом 0.1. Для каждого значения
# выполняем 3 прогона с разными seed'ами для оценки статистической
# устойчивости результатов.

beta_range = 0.1:0.1:1.0                                                   # диапазон коэффициентов заразности
seeds = [42, 43, 44]                                                       # три seed'а для воспроизводимости

params_list = []                                                            # список всех комбинаций параметров
for b in beta_range                                                         # по всем β
    for s in seeds                                                          # по всем seed'ам
        push!(params_list, Dict(                                            # добавляем набор параметров
            :beta => b,                                                     # текущий коэффициент заразности
            :Ns => [1000, 1000, 1000],                                      # три города по 1000 человек
            :infection_period => 14,                                        # 14 дней болезни
            :detection_time => 7,                                           # 7 дней до выявления
            :death_rate => 0.02,                                            # 2% летальность
            :reinfection_probability => 0.1,                                # 10% повторного заражения
            :Is => [0, 0, 1],                                               # только в третьем городе 1 больной
            :seed => s,                                                     # seed для случайности
            :n_steps => 100,                                                # 100 шагов симуляции
        ))
    end
end

# ## 4. Запуск экспериментов

results = []                                                                # массив для результатов
for params in params_list                                                   # по всем комбинациям
    data = run_experiment(params)                                           # запускаем эксперимент
    push!(results, merge(params, Dict(pairs(data))))                        # сохраняем параметры + результаты
    println("Завершён эксперимент с beta = $(params[:beta]), seed = $(params[:seed])")
end

# ## 5. Сохранение сырых данных

df = DataFrame(results)                                                     # преобразуем в DataFrame
CSV.write(datadir("beta_scan_all.csv"), df)                                 # сохраняем в CSV

# ## 6. Агрегация и статистическая обработка

using Statistics                                                            # подключаем статистику
grouped = combine(                                                          # группируем по β
    groupby(df, [:beta]),                                                   # группировка
    :peak => mean => :mean_peak,                                            # средний пик
    :final_inf => mean => :mean_final_inf,                                  # средняя конечная доля
    :deaths => mean => :mean_deaths,                                        # среднее число смертей
)

# ## 7. Визуализация результатов

plot(                                                                       # создаём график
    grouped.beta,                                                           # ось X: β
    grouped.mean_peak,                                                      # ось Y: пик
    label = "Пик эпидемии",                                                 # подпись
    xlabel = "Коэффициент заразности β",                                    # подпись оси X
    ylabel = "Доля инфицированных",                                         # подпись оси Y
    marker = :circle,                                                       # маркер: кружок
    linewidth = 2,                                                          # толщина линии
)
plot!(                                                                      # добавляем вторую кривую
    grouped.beta,                                                           # ось X: β
    grouped.mean_final_inf,                                                 # ось Y: конечная доля
    label = "Конечная доля инфицированных",                                 # подпись
    marker = :square,                                                       # маркер: квадрат
)
plot!(                                                                      # добавляем третью кривую
    grouped.beta,                                                           # ось X: β
    grouped.mean_deaths ./ 3000,                                            # ось Y: доля умерших (масштабируем)
    label = "Доля умерших",                                                 # подпись
    marker = :diamond,                                                      # маркер: ромб
)
savefig(plotsdir("beta_scan.png"))                                          # сохраняем график

# ## 8. Завершение

println("Результаты сохранены в data/beta_scan_all.csv и plots/beta_scan.png")
