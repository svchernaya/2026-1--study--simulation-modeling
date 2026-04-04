using BlackBoxOptim


function run_default_model()
    model = initialize_sir(;
        Ns = [1000, 1000, 1000],
        β_und = [0.5, 0.5, 0.5],
        β_det = [0.05, 0.05, 0.05],
        infection_period = 14,
        detection_time = 7,
        death_rate = 0.02,
        reinfection_probability = 0.0,
        Is = [0, 0, 1],
        seed = 42,
        n_steps = 100,
    )
    return model
end

function plot_SIR_dynamics(model)

    S_history = []
    I_history = []
    R_history = []

    for step in 1:100
        push!(S_history, count(a.status == :S for a in allagents(model)))
        push!(I_history, count(a.status == :I for a in allagents(model)))
        push!(R_history, count(a.status == :R for a in allagents(model)))
        Agents.step!(model, 1)
    end

    plot(1:100, S_history, label="S (Восприимчивые)", linewidth=2)
    plot!(1:100, I_history, label="I (Инфицированные)", linewidth=2)
    plot!(1:100, R_history, label="R (Выздоровевшие)", linewidth=2)
    xlabel!("Время, дни")
    ylabel!("Численность популяции")
    title!("Динамика SIR модели")
    savefig(plotsdir("sir_dynamics.png"))
end

function calculate_R0(beta, infection_period)
    γ = 1 / infection_period
    R0 = beta / γ
    return R0
end

function find_threshold_beta()
    beta_range = 0.05:0.05:0.5
    peaks = []

    for beta in beta_range
        model = initialize_sir(;
            Ns = [1000, 1000, 1000],
            β_und = fill(beta, 3),
            β_det = fill(beta/10, 3),
            infection_period = 14,
            detection_time = 7,
            death_rate = 0.02,
            reinfection_probability = 0.0,
            Is = [0, 0, 1],
            seed = 42,
            n_steps = 100,
        )

        peak = 0.0
        for step in 1:100
            Agents.step!(model, 1)
            frac = count(a.status == :I for a in allagents(model)) / 3000
            if frac > peak
                peak = frac
            end
        end
        push!(peaks, peak)
    end

    for (i, peak) in enumerate(peaks)
        if peak > 0.05
            println("Пороговое β = $(beta_range[i]) при пике = $(round(peak, digits=3))")
            break
        end
    end

    plot(beta_range, peaks, marker=:circle, xlabel="β", ylabel="Пик заболеваемости")
    hline!([0.05], linestyle=:dash, label="Порог 5%")
    vline!([0.0714], linestyle=:dash, label="Теоретический порог R₀=1")
    savefig(plotsdir("threshold_analysis.png"))
end

function heterogeneous_beta()

    model = initialize_sir(;
        Ns = [1000, 1000, 1000],
        β_und = [0.2, 0.5, 0.8],
        β_det = [0.02, 0.05, 0.08],
        infection_period = 14,
        detection_time = 7,
        death_rate = 0.02,
        reinfection_probability = 0.0,
        Is = [1, 0, 0],  # начальный очаг в городе 1
        seed = 42,
        n_steps = 100,
    )

    city_S = [[], [], []]
    city_I = [[], [], []]
    city_R = [[], [], []]

    for step in 1:100
        for city in 1:3
            agents_in_city = [a for a in allagents(model) if a.city == city]
            push!(city_S[city], count(a -> a.status == :S, agents_in_city))
            push!(city_I[city], count(a -> a.status == :I, agents_in_city))
            push!(city_R[city], count(a -> a.status == :R, agents_in_city))
        end
        Agents.step!(model, 1)
    end

    for city in 1:3
        plot(1:100, city_I[city], label="Город $city", linewidth=2)
        plot!(title="Динамика инфицированных по городам", xlabel="Время", ylabel="Число больных")
    end
    savefig(plotsdir("heterogeneous_dynamics.png"))
end

function migration_speed_analysis()
    intensities = 0.0:0.05:0.5
    peak_times = []

    for mig in intensities
        migration_rates = create_migration_matrix(3, mig)
        model = initialize_sir(;
            Ns = [1000, 1000, 1000],
            β_und = [0.5, 0.5, 0.5],
            β_det = [0.05, 0.05, 0.05],
            infection_period = 14,
            detection_time = 7,
            death_rate = 0.02,
            reinfection_probability = 0.0,
            Is = [1, 0, 0],
            seed = 42,
            n_steps = 100,
            migration_rates = migration_rates,
        )

        peak_step = 0
        peak_value = 0.0

        for step in 1:100
            Agents.step!(model, 1)
            total_infected = count(a.status == :I for a in allagents(model))
            if total_infected > peak_value
                peak_value = total_infected
                peak_step = step
            end
        end
        push!(peak_times, peak_step)
    end

    min_time = minimum(peak_times)
    opt_intensity = intensities[argmin(peak_times)]

    plot(intensities, peak_times, marker=:circle, xlabel="Интенсивность миграции",
         ylabel="Время до пика (дни)", title="Влияние миграции на скорость распространения")
    vline!([opt_intensity], linestyle=:dash, label="Оптимум: $opt_intensity")
    savefig(plotsdir("migration_speed.png"))

    println("Минимальное время до пика ($min_time дней) достигается при интенсивности $opt_intensity")
end

mutable struct QuarantineModel
    model
    thresholds::Vector{Float64}      # пороги для каждого города
    city_open::Vector{Bool}          # статус города (открыт/закрыт)
    original_rates::Array{Float64,2} # исходные миграционные rates
end

function setup_quarantine_model(threshold=0.1)
    migration_rates = create_migration_matrix(3, 0.2)

    model = initialize_sir(;
        Ns = [1000, 1000, 1000],
        β_und = [0.5, 0.5, 0.5],
        β_det = [0.05, 0.05, 0.05],
        infection_period = 14,
        detection_time = 7,
        death_rate = 0.02,
        reinfection_probability = 0.0,
        Is = [1, 0, 0],
        seed = 42,
        n_steps = 100,
        migration_rates = migration_rates,
    )

    return QuarantineModel(model, fill(threshold, 3), fill(true, 3), copy(migration_rates))
end

function run_quarantine_simulation(qm::QuarantineModel)
    history = []

    for step in 1:100

        for city in 1:3
            if qm.city_open[city]
                city_agents = [a for a in allagents(qm.model) if a.city == city]
                infected_frac = count(a -> a.status == :I, city_agents) / length(city_agents)

                if infected_frac > qm.thresholds[city]

                    qm.city_open[city] = false

                    qm.model.migration_rates[city, :] .= 0.0
                    qm.model.migration_rates[:, city] .= 0.0
                    println("Город $city закрыт на карантин на шаге $step")
                end
            end
        end

        Agents.step!(qm.model, 1)
        total_infected = count(a.status == :I for a in allagents(qm.model))
        push!(history, total_infected)
    end

    return history
end

function evaluate_quarantine_effectiveness()

    model_no_q = initialize_sir(;
        Ns = [1000, 1000, 1000],
        β_und = [0.5, 0.5, 0.5],
        β_det = [0.05, 0.05, 0.05],
        infection_period = 14,
        detection_time = 7,
        death_rate = 0.02,
        reinfection_probability = 0.0,
        Is = [1, 0, 0],
        seed = 42,
        n_steps = 100,
        migration_rates = create_migration_matrix(3, 0.2),
    )

    history_no_q = []
    for step in 1:100
        Agents.step!(model_no_q, 1)
        push!(history_no_q, count(a.status == :I for a in allagents(model_no_q)))
    end

    qm = setup_quarantine_model(0.15)  # закрываем город при 15% больных
    history_q = run_quarantine_simulation(qm)

    plot(1:100, history_no_q, label="Без карантина", linewidth=2)
    plot!(1:100, history_q, label="С карантином", linewidth=2)
    xlabel!("Время, дни")
    ylabel!("Число инфицированных")
    title!("Эффективность карантинных мер")
    savefig(plotsdir("quarantine_effectiveness.png"))

    final_no_q = history_no_q[end]
    final_q = history_q[end]
    reduction = (final_no_q - final_q) / final_no_q * 100

    println("Снижение числа заболевших: $(round(reduction, digits=1))%")
end

function cost_with_constraint(x)
    β_und = x[1]
    detection_time = round(Int, x[2])
    death_rate = x[3]

    peak_values = []
    death_values = []

    for rep in 1:5
        model = initialize_sir(;
            Ns = [1000, 1000, 1000],
            β_und = fill(β_und, 3),
            β_det = fill(β_und/10, 3),
            infection_period = 14,
            detection_time = detection_time,
            death_rate = death_rate,
            reinfection_probability = 0.1,
            Is = [0, 0, 1],
            seed = 42 + rep,
            n_steps = 100,
        )

        peak = 0.0
        for step in 1:100
            Agents.step!(model, 1)
            frac = count(a.status == :I for a in allagents(model)) / 3000
            if frac > peak
                peak = frac
            end
        end

        push!(peak_values, peak)
        push!(death_values, death_rate * 3000)
    end

    mean_peak = mean(peak_values)
    mean_deaths = mean(death_values)

    penalty = mean_peak > 0.3 ? 1000 * (mean_peak - 0.3) : 0

    return mean_deaths + penalty
end

function run_constrained_optimization()


    result = bboptimize(
        cost_with_constraint,
        SearchRange = [(0.1, 1.0), (3.0, 14.0), (0.01, 0.1)],
        NumDimensions = 3,
        MaxTime = 120,
    )

    best = best_candidate(result)
    best_fitness = best_fitness(result)

    println("Оптимальные параметры при ограничении пик < 30%:")
    println("β_und = $(best[1])")
    println("Время выявления = $(round(Int, best[2])) дней")
    println("Смертность = $(best[3])")
    println("Минимальное число умерших: $(round(best_fitness))")

    save(datadir("constrained_optimization.jld2"), Dict("best" => best, "fitness" => best_fitness))
end

function create_migration_matrix(C, intensity)
    M = ones(C, C) .* intensity ./ (C-1)
    for i in 1:C
        M[i, i] = 1 - intensity
    end
    return M
end
