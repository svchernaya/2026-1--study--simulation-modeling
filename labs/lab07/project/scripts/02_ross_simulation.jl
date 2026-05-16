using DrWatson
@quickactivate "project"

using ResumableFunctions
using ConcurrentSim
using Distributions
using Random
using StableRNGs
using DataFrames, CSV, Plots
const N = 10
const RUNS = 2
const S_values = [0, 1, 2, 3]
const repair_values = [1, 2]
const LAMBDA = 100
const MU = 1

history_records = []

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

df_results = DataFrame(all_results)
mkpath(datadir("ross"))
CSV.write(datadir("ross", "results.csv"), df_results)

p1 = plot(xlabel="S (резервные машины)", ylabel="Среднее время до краха (часы)", legend=:topleft, yscale=:log10)
colors = [:red, :blue, :green]
for (idx, r) in enumerate(repair_values)
    sub = filter(row -> row.repair_servers == r, df_results)
    plot!(sub.S, sub.avg_crash_time, marker=:circle, linewidth=2,
          label="$r ремонтник(а)", color=colors[idx])
end
savefig(plotsdir("ross_crash_time.png"))


function analytic_crash_time(N, S, λ, μ)
    return (S + 1) * (λ / N + 1/μ)
end

df_1rep = filter(row -> row.repair_servers == 1, df_results)
analytic_vals = [analytic_crash_time(N, S, LAMBDA, MU) for S in df_1rep.S]

p4 = plot(df_1rep.S, df_1rep.avg_crash_time,
          marker=:circle, label="Симуляция")
plot!(df_1rep.S, analytic_vals, linestyle=:dash, label="Аналитика")
savefig(plotsdir("ross_compare.png"))

println("Готово! Результаты в data/ross/ и plots/")
